(in-package #:cadr-ai/tests)

(in-suite cadr-ai-suite)

(test goal12-short-hash-matches-javascript-utf16-vectors
  (is (string= "k4n83c7h0j2b" (cadr-ai:short-hash "")))
  (is (string= "y0biex7f9bbh" (cadr-ai:short-hash "abc")))
  (is (string= "1uqnrlm1d9i9jc" (cadr-ai:short-hash "中文😀")))
  (is (string= "10iaqc8tka5dz"
               (cadr-ai:short-hash
                "tool-call-id-with-long-foreign-id"))))

(test goal12-json-repair-and-streaming-parse-match-baseline
  (let* ((raw (format nil "{\"path\":\"C:~Clogs~%name\",\"ok\":true}" #\\))
         (repaired (cadr-ai:repair-json raw))
         (parsed (cadr-ai:parse-json-with-repair raw)))
    (is (search (format nil "C:~C~Clogs\\nname" #\\ #\\) repaired))
    (is (string= (format nil "C:~Clogs~%name" #\\)
                 (cadr-ai::json-get parsed "path"))))
  (let ((parsed
          (cadr-ai:parse-streaming-json
           "{\"outer\":{\"text\":\"hel")))
    (is (string= "hel"
                 (cadr-ai::json-get
                  (cadr-ai::json-get parsed "outer") "text"))))
  (is (= 1
         (cadr-ai::json-get
          (cadr-ai:parse-streaming-json "{\"a\":1,\"b\":")
          "a")))
  (is (= 0
         (hash-table-count
          (cadr-ai:parse-streaming-json "not-json")))))

(test goal12-event-stream-buffers-wakes-and-exposes-final-result
  (let ((stream
          (cadr-ai:make-event-stream
           :complete-p (lambda (event) (eq (getf event :type) :done))
           :result-function (lambda (event) (getf event :value)))))
    (cadr-ai:event-stream-push stream '(:type :delta :value "a"))
    (multiple-value-bind (event done-p)
        (cadr-ai:event-stream-next stream)
      (is (string= "a" (getf event :value)))
      (is-false done-p))
    (let* ((ready (sb-thread:make-semaphore :count 0))
           (waiter
            (bt:make-thread
             (lambda ()
               (sb-thread:signal-semaphore ready)
               (cadr-ai:event-stream-next stream)))))
      (sb-thread:wait-on-semaphore ready)
      (cadr-ai:event-stream-push stream '(:type :done :value "final"))
      (multiple-value-bind (event done-p) (bt:join-thread waiter)
        (is (string= "final" (getf event :value)))
        (is-false done-p)))
    (is (string= "final" (cadr-ai:event-stream-result stream)))
    (multiple-value-bind (event done-p)
        (cadr-ai:event-stream-next stream)
      (is (null event))
      (is-true done-p))))

(test goal12-deferred-tools-preserve-transcript-loading-semantics
  (let* ((read (cadr-ai:make-tool :name "read"))
         (write (cadr-ai:make-tool :name "write"))
         (context
           (cadr-ai:make-context
            :tools (list read write read)
            :messages
            (list
             (cadr-ai:make-tool-result-message
              :tool-call-id "load-1" :tool-name "tool_search"
              :added-tool-names '("write")))))
         (immediate nil)
         (deferred nil))
    (multiple-value-setq (immediate deferred)
      (cadr-ai:split-deferred-tools context t))
    (is (equal '("read") (mapcar #'cadr-ai:tool-name immediate)))
    (is (eq write (gethash "write" deferred)))
    (push
     (cadr-ai:make-assistant-message
      :content
      (list
       (cadr-ai:make-tool-call
        :id "call-1" :name "write")))
     (cadr-ai:context-messages context))
    (multiple-value-setq (immediate deferred)
      (cadr-ai:split-deferred-tools context t))
    (is (equal '("read" "write")
               (mapcar #'cadr-ai:tool-name immediate)))
    (is (= 0 (hash-table-count deferred)))))

(test goal12-constrained-sampling-resolves-strict-and-grammar-contracts
  (let* ((schema
           (cadr-ai::json-object
            "type" "object"
            "properties"
            (cadr-ai::json-object
             "query" (cadr-ai::json-object "type" "string"))
            "required" (vector "query")))
         (grammar
           (cadr-ai:make-tool
            :name "search"
            :parameters schema
            :constrained-sampling
            (list :type :grammar
                  :variants
                  (list :openai-lark "start: /.+/"
                        :openai-regex ".+"))))
         (strict
           (cadr-ai:make-tool
            :name "strict"
            :parameters schema
            :constrained-sampling
            (list :type :json-schema :strict :require)))
         (unconvertible
           ;; v0.84.2: a schema outside the strict subset (here: $ref) is
           ;; not strict-samplable; :require turns that into an error.
           (cadr-ai:make-tool
            :name "unconvertible"
            :parameters
            (cadr-ai::json-object
             "$ref" "#/definitions/query")
            :constrained-sampling
            (list :type :json-schema :strict :require)))
         (unconvertible-prefer
           (cadr-ai:make-tool
            :name "unconvertible-prefer"
            :parameters
            (cadr-ai::json-object
             "$ref" "#/definitions/query")
            :constrained-sampling
            (list :type :json-schema :strict :prefer))))
    (let ((resolved
            (cadr-ai:resolve-grammar-constrained-sampling grammar t)))
      (is (eq :lark (getf resolved :format)))
      (is (string= "query" (getf resolved :input-property))))
    (is-true (cadr-ai:resolve-json-schema-strict-sampling strict t))
    (signals error
      (cadr-ai:resolve-json-schema-strict-sampling strict nil))
    (signals error
      (cadr-ai:resolve-json-schema-strict-sampling unconvertible t))
    (is-false
      (cadr-ai:resolve-json-schema-strict-sampling unconvertible-prefer t))
    (is (string= "hello"
                 (cadr-ai:get-grammar-tool-input
                  "search"
                  (cadr-ai::json-object "query" "hello")
                  "query")))
    (let ((properties
            (cadr-ai:create-grammar-tool-input-properties
             (list grammar strict) t)))
      (is (string= "query" (gethash "search" properties))))))

(test goal12-session-resource-cleanup-is-removable-and-aggregates-failures
  (cadr-ai:clear-session-resource-cleanups)
  (let* ((calls nil)
        (remove-first
          (cadr-ai:register-session-resource-cleanup
           (lambda (session-id) (push (list :first session-id) calls)))))
    (cadr-ai:register-session-resource-cleanup
     (lambda (session-id) (push (list :second session-id) calls)))
    (cadr-ai:cleanup-session-resources "s1")
    (is (equal '((:second "s1") (:first "s1")) calls))
    (funcall remove-first)
    (setf calls nil)
    (cadr-ai:cleanup-session-resources "s2")
    (is (equal '((:second "s2")) calls)))
  (cadr-ai:clear-session-resource-cleanups)
  (cadr-ai:register-session-resource-cleanup (lambda (id) (declare (ignore id)) (error "one")))
  (cadr-ai:register-session-resource-cleanup (lambda (id) (declare (ignore id)) (error "two")))
  (handler-case
      (progn (cadr-ai:cleanup-session-resources) (fail "expected cleanup error"))
    (error (condition)
      (is (search "one" (princ-to-string condition)))
      (is (search "two" (princ-to-string condition)))))
  (cadr-ai:clear-session-resource-cleanups))

(test goal12-http-proxy-resolution-matches-no-proxy-and-validation
  (is (string=
       "http://proxy.example:8080"
       (cadr-ai:resolve-http-proxy-url-for-target
        "https://api.example.com/v1"
        '(("HTTPS_PROXY" . "http://proxy.example:8080")))))
  (is (null
       (cadr-ai:resolve-http-proxy-url-for-target
        "https://api.example.com:443/v1"
        '(("HTTPS_PROXY" . "http://proxy.example:8080")
          ("NO_PROXY" . ".example.com:443")))))
  (signals error
    (cadr-ai:resolve-http-proxy-url-for-target
     "https://api.example.com"
     '(("HTTPS_PROXY" . "socks5://proxy.example:1080")))))

(test goal12-native-http-routes-through-proxy-and-uses-connect-for-tls
  (let* ((listener
           (usocket:socket-listen
            "127.0.0.1" 0 :reuse-address t
            :element-type '(unsigned-byte 8)))
         (port (usocket:get-local-port listener))
         (request-line nil)
         (host-header nil)
         (server-error nil)
         (server
           (bt:make-thread
            (lambda ()
              (handler-case
                  (let ((client
                          (usocket:socket-accept
                           listener
                           :element-type '(unsigned-byte 8))))
                    (unwind-protect
                         (let ((stream (usocket:socket-stream client)))
                           (setf request-line
                                 (cadr-ai::read-http-line stream))
                           (loop for line = (cadr-ai::read-http-line stream)
                                 until (zerop (length line))
                                 when (uiop:string-prefix-p "Host:" line)
                                   do (setf host-header line))
                           (write-http-string
                            stream
                            (format nil
                                    "HTTP/1.1 200 OK~C~CContent-Length: 11~C~CContent-Type: application/json~C~CConnection: close~C~C~C~C{\"ok\":true}"
                                    #\Return #\Linefeed #\Return #\Linefeed
                                    #\Return #\Linefeed #\Return #\Linefeed
                                    #\Return #\Linefeed)))
                      (usocket:socket-close client)))
                (error (condition)
                  (setf server-error condition))))
            :name "cadr-test-http-proxy")))
    (unwind-protect
         (let* ((cadr-ai::*http-request-function*
                  #'cadr-ai::native-http-request)
                (request
                  (cadr-ai::make-request-spec
                   :url "http://origin.invalid/path?q=1"
                   :method :get
                   :provider :fixture))
                (result
                  (cadr-ai::request-json
                   request
                   :environment
                   `(("HTTP_PROXY" . ,(format nil "http://127.0.0.1:~D" port))
                     ("NO_PROXY" . "")))))
           (bt:join-thread server)
           (when server-error (error server-error))
           (is-true (cadr-ai::json-get result "ok"))
           (is (string=
                "GET http://origin.invalid/path?q=1 HTTP/1.1"
                request-line))
           (is (string= "Host: origin.invalid" host-header)))
      (ignore-errors (usocket:socket-close listener))
      (when (bt:thread-alive-p server)
        (bt:join-thread server))))
  (let* ((output (flexi-streams:make-in-memory-output-stream))
         (target
           (cadr-ai::parse-http-url
            "https://api.example.com:8443/v1")))
    (cadr-ai::write-proxy-connect-request output target)
    (let ((wire
            (babel:octets-to-string
             (flexi-streams:get-output-stream-sequence output)
             :encoding :utf-8)))
      (is (uiop:string-prefix-p
           "CONNECT api.example.com:8443 HTTP/1.1"
           wire))
      (is (search "Host: api.example.com:8443" wire)))))

(test goal12-images-api-registry-and-runtime-are-provider-extensible
  (cadr-ai:clear-images-api-providers)
  (let* ((calls nil)
         (model
           (cadr-ai:make-image-model
            :id "paint" :name "paint" :api :fixture-images
            :provider :fixture :base-url "https://images.test"))
         (provider
           (cadr-ai:make-images-provider
            :id :fixture :name "Fixture"
            :models (list model)
            :generate-function
            (lambda (request-model context options)
              (push (list request-model context options) calls)
              (cadr-ai:make-assistant-images
               :api :fixture-images :provider :fixture
               :model "paint" :output '("ok") :stop-reason :stop)))))
    (cadr-ai:register-images-api-provider
     :fixture-images
     (lambda (request-model context options)
       (funcall (cadr-ai:images-provider-generate-function provider)
                request-model context options))
     :source-id "test")
    (let ((runtime (cadr-ai:make-images-models)))
      (cadr-ai:images-models-set-provider runtime provider)
      (is (eq provider (cadr-ai:images-models-provider runtime :fixture)))
      (is (eq model (cadr-ai:images-models-model runtime :fixture "paint")))
      (let ((result
              (cadr-ai:images-models-generate
               runtime model (cadr-ai:make-images-context :input '("prompt")))))
        (is (equal '("ok") (cadr-ai:assistant-images-output result)))
        (is (= 1 (length calls)))))))

(test event-stream-preserves-fifo-without-nconc
  (let ((stream (cadr-ai:make-event-stream)))
    (dotimes (i 20)
      (cadr-ai:event-stream-push stream i))
    (is (equal
         (loop repeat 20
               collect (cadr-ai:event-stream-next stream))
         (loop for i below 20 collect i)))))

(test provider-definition-row-keys-come-from-mop
  (is (not (boundp 'cadr-ai::+provider-definition-row-keys+)))
  (let ((keys (cadr-ai::provider-definition-row-keys)))
    (is (member :id keys))
    (is (member :model-filter-strategy keys))
    (is (= (length keys)
           (1+
            (length
             (cadr-ai::provider-definition-compared-slots)))))))

(test google-gemini-3-model-p-owns-tool-id-sniff
  (is (cadr-ai::google-gemini-3-model-p
       (make-model :id "gemini-3.6-flash")))
  (is (not
       (cadr-ai::google-gemini-3-model-p
        (make-model :id "gemini-2.5-pro")))))
