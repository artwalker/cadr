(in-package #:cadr-ai/tests)

(in-suite cadr-ai-suite)

(defun telemetry-same (left right)
  (cond
    ((and (numberp left) (numberp right)) (= left right))
    ((and (stringp left) (stringp right)) (string= left right))
    ((and (consp left) (consp right))
     (and (telemetry-same (car left) (car right))
          (telemetry-same (cdr left) (cdr right))))
    ((and (vectorp left) (vectorp right))
     (and (= (length left) (length right))
          (every #'telemetry-same left right)))
    (t (eql left right))))

(defun telemetry-attr (attributes name)
  (cdr (assoc name attributes :test #'string=)))

(defun telemetry-recorded-events (span)
  (mapcar (lambda (event)
            (cons (cadr-telemetry:recorded-telemetry-event-name event)
                  (cadr-telemetry:recorded-telemetry-event-attributes event)))
          (cadr-telemetry:recorded-telemetry-span-events span)))

(defun telemetry-span-text (span)
  (with-output-to-string (output)
    (labels ((walk (value)
               (cond
                 ((stringp value) (write-string value output))
                 ((numberp value) (princ value output))
                 ((consp value)
                  (walk (car value))
                  (walk (cdr value)))
                 ((vectorp value)
                  (loop for item across value do (walk item)))
                 ((cadr-telemetry:telemetry-status-p value)
                  (walk (cadr-telemetry:telemetry-status-error-name value))
                  (walk (cadr-telemetry:telemetry-status-error-message value)))
                 ((cadr-telemetry:recorded-telemetry-event-p value)
                  (walk (cadr-telemetry:recorded-telemetry-event-name value))
                  (walk (cadr-telemetry:recorded-telemetry-event-attributes value)))
                 ((cadr-telemetry:recorded-telemetry-link-p value)
                  (walk (cadr-telemetry:recorded-telemetry-link-attributes value)))
                 ((cadr-telemetry:recorded-telemetry-span-p value)
                  (walk (cadr-telemetry:recorded-telemetry-span-name value))
                  (walk (cadr-telemetry:recorded-telemetry-span-attributes value))
                  (walk (cadr-telemetry:recorded-telemetry-span-events value))
                  (walk (cadr-telemetry:recorded-telemetry-span-links value))
                  (walk (cadr-telemetry:recorded-telemetry-span-status value))))))
      (walk span))))

(defun telemetry-model ()
  (cadr-ai:make-model
   :id "model" :name "Model"
   :provider :test :api :telemetry-test
   :base-url "https://example.test"
   :context-window 1000 :max-tokens 100))

(defun telemetry-usage ()
  (cadr-ai:make-usage
   :input 11 :output 22 :cache-read 33 :cache-write 44
   :cost (cadr-ai:make-cost :total 1d0)))

(defun telemetry-message (&key (stop :stop) error-message)
  (cadr-ai:make-assistant-message
   :api :telemetry-test :provider :test :model "model"
   :content (list (cadr-ai:make-text-content :text "text-secret")
                  (cadr-ai:make-thinking-content :thinking "thinking-secret")
                  (cadr-ai:make-tool-call
                   :id "call-secret" :name "lookup"
                   :arguments (let ((table (make-hash-table :test #'equal)))
                                (setf (gethash "value" table) "argument-secret")
                                table)))
   :usage (telemetry-usage)
   :response-id "response"
   :stop-reason stop
   :error-message error-message))

(defun telemetry-events (message)
  (list
   (cadr-ai:make-stream-event :type :start :message message)
   (cadr-ai:make-stream-event
    :type :text-delta :content-index 0 :delta "text-secret" :message message)
   (cadr-ai:make-stream-event
    :type :text-end :content-index 0 :content "text-secret" :message message)
   (cadr-ai:make-stream-event
    :type :thinking-end :content-index 1 :content "thinking-secret"
    :message message)
   (cadr-ai:make-stream-event
    :type :tool-call-delta :content-index 2 :delta "{\"value\":" :message message)
   (cadr-ai:make-stream-event
    :type :tool-call-delta :content-index 2 :delta "\"argument-secret\"}"
    :message message)
   (cadr-ai:make-stream-event
    :type :tool-call-end :content-index 2
    :tool-call (third (cadr-ai:assistant-message-content message))
    :message message)))

(defun telemetry-schema-span (name)
  (cdr (assoc name
              (cadr-telemetry:telemetry-schema-spans cadr-ai:*ai-telemetry-schema*)
              :test #'string=)))

(defun telemetry-schema-metric (name)
  (cdr (assoc name
              (cadr-telemetry:telemetry-schema-metrics cadr-ai:*ai-telemetry-schema*)
              :test #'string=)))

(defun telemetry-schema-attribute (attributes name)
  (cdr (assoc name attributes :test #'string=)))

(defun telemetry-deferred-runtime (message &key events)
  (let* ((model (telemetry-model))
         (provider
           (cadr-ai:make-runtime-provider
            :id :test :name "telemetry"
            :models (list model)
            :api-key-auth-p t
            :auth-resolver
            (lambda (&rest ignored)
              (declare (ignore ignored))
              (cadr-ai:make-runtime-auth-result :type :api-key :api-key "k"))
            :stream-function
            (lambda (request-model context on-event &rest options)
              (declare (ignore request-model context options))
              (dolist (event events)
                (funcall on-event event))
              message)
            :complete-function
            (lambda (request-model context options)
              (declare (ignore request-model context options))
              message)
            :fetch-deferred-function
            (lambda (request-model handle on-event &rest options)
              (declare (ignore request-model handle options))
              (dolist (event events)
                (funcall on-event event))
              message)))
         (runtime (cadr-ai:make-models-runtime)))
    (cadr-ai:models-runtime-set-provider runtime provider)
    (values runtime model)))

(defun telemetry-observe (model span events message &key poll reasoning clock)
  (cadr-ai:call-with-observed-model-request
   model
   (append (when span (list :telemetry span))
           (when reasoning (list :reasoning reasoning)))
   poll
   (lambda (observe finish)
     (when clock (funcall clock :events))
     (dolist (event events)
       (funcall observe event))
     (when clock (funcall clock :finish))
     (funcall finish message)
     message)))

(defun telemetry-uuid-v4-p (text)
  (and (stringp text)
       (= 36 (length text))
       (char= #\4 (char text 14))
       (find (char text 19) "89ab")
       (every (lambda (index) (char= #\- (char text index))) '(8 13 18 23))
       (every (lambda (character)
                (or (digit-char-p character 16) (char= character #\-)))
              text)))

(test telemetry-noop-is-one-span-and-rethrows-the-same-condition
  (let ((span cadr-telemetry:*noop-telemetry-context*))
    (is (eq span
            (cadr-telemetry:telemetry-start-span
             span "child" (lambda (child) child))))
    (is (= 42
           (cadr-telemetry:telemetry-start-span
            span "value" (lambda (child) (declare (ignore child)) 42))))
    (is (eq cadr-telemetry:*noop-telemetry-metrics*
            (cadr-telemetry:telemetry-span-metrics span)))
    (is (eq (cadr-telemetry:telemetry-counter
             cadr-telemetry:*noop-telemetry-metrics* "c")
            (cadr-telemetry:telemetry-counter
             cadr-telemetry:*noop-telemetry-metrics* "other")))
    (is (eq (cadr-telemetry:telemetry-histogram
             cadr-telemetry:*noop-telemetry-metrics* "h")
            (cadr-telemetry:telemetry-histogram
             cadr-telemetry:*noop-telemetry-metrics* "other")))
    (is (null (cadr-telemetry:telemetry-inject
               cadr-telemetry:*noop-telemetry-propagation* span)))
    (is (eq span
            (cadr-telemetry:telemetry-extract
             cadr-telemetry:*noop-telemetry-propagation*
             '(("pi-memory-scope" . "x")))))
    (let ((condition (make-condition 'simple-error
                                     :format-control "sync"
                                     :format-arguments nil)))
      (handler-case
          (cadr-telemetry:telemetry-start-span
           span "boom"
           (lambda (child)
             (declare (ignore child))
             (error condition)))
        (simple-error (caught) (is (eq condition caught)))
        (:no-error () (fail "noop swallowed an error"))))
    (let* ((context (cadr-telemetry:make-in-memory-telemetry))
           (rejection (make-condition 'cadr-telemetry:telemetry-rejection
                                      :value "plain")))
      (handler-case
          (cadr-telemetry:telemetry-start-span
           context "reject"
           (lambda (child)
             (declare (ignore child))
             (error rejection)))
        (cadr-telemetry:telemetry-rejection (caught)
          (is (eq rejection caught)))
        (:no-error () (fail "rejection was swallowed")))
      (let ((recorded (first (cadr-telemetry:in-memory-telemetry-spans context))))
        (is (eq :error
                (cadr-telemetry:telemetry-status-kind
                 (cadr-telemetry:recorded-telemetry-span-status recorded))))
        (is (not (cadr-telemetry:telemetry-status-error-p
                  (cadr-telemetry:recorded-telemetry-span-status recorded))))))))

(test telemetry-schema-is-identity-and-typed-children-keep-the-parent
  (let ((schema cadr-ai:*ai-telemetry-schema*))
    (is (eq schema (cadr-telemetry:define-telemetry-schema schema)))
    (is (= 1 (cadr-telemetry:telemetry-schema-version schema)))
    (is (cadr-telemetry:telemetry-attribute-definition-required
         (cdr (assoc "provider"
                     (cadr-telemetry:telemetry-span-definition-start-attributes
                      (cdr (assoc "pi.ai.request"
                                  (cadr-telemetry:telemetry-schema-spans schema)
                              :test #'string=)))
                 :test #'string=))))
    (let* ((request (telemetry-schema-span "pi.ai.request"))
           (poll (telemetry-schema-span "pi.ai.poll"))
           (start (cadr-telemetry::telemetry-span-definition-start-attributes request))
           (end (cadr-telemetry::telemetry-span-definition-end-attributes request))
           (events (cadr-telemetry::telemetry-span-definition-events request))
           (block (cdr (assoc "pi.ai.block" events :test #'string=)))
           (duration (telemetry-schema-metric "pi.ai.request.duration"))
           (first-chunk (telemetry-schema-metric "pi.ai.first_chunk.duration"))
           (tokens (telemetry-schema-metric "pi.ai.tokens"))
           (cost (telemetry-schema-metric "pi.ai.cost")))
      (is (string= "One logical model request, including authentication and provider setup."
                   (cadr-telemetry:telemetry-span-definition-description request)))
      (is (string= "One deferred-response poll, not the deferred request's lifetime."
                   (cadr-telemetry:telemetry-span-definition-description poll)))
      (is (eq start (cadr-telemetry::telemetry-span-definition-start-attributes poll)))
      (is (eq end (cadr-telemetry::telemetry-span-definition-end-attributes poll)))
      (is (eq events (cadr-telemetry::telemetry-span-definition-events poll)))
      (is (eq (cadr-telemetry::telemetry-span-definition-status request)
              (cadr-telemetry::telemetry-span-definition-status poll)))
      (is (eq (cadr-telemetry::telemetry-span-definition-parents request)
              (cadr-telemetry::telemetry-span-definition-parents poll)))
      (is (equal '(:kind "any")
                 (cadr-telemetry::telemetry-span-definition-parents request)))
      (is (equal '("provider" "api" "model" "reasoning")
                 (mapcar #'car start)))
      (is (equal '("stop" "usage.input" "usage.output" "usage.cache_read"
                   "usage.cache_write" "cost.total" "response.id")
                 (mapcar #'car end)))
      (is (equal '("pending" "stop" "length" "toolUse" "error" "aborted" "deferred")
                 (cadr-telemetry::telemetry-attribute-definition-values
                  (telemetry-schema-attribute end "stop"))))
      (is (null (cadr-telemetry:telemetry-attribute-definition-required
                 (telemetry-schema-attribute end "stop"))))
      (is (string= "high"
                   (cadr-telemetry::telemetry-attribute-definition-cardinality
                    (telemetry-schema-attribute end "response.id"))))
      (is (equal '("pi.ai.first_chunk" "pi.ai.block") (mapcar #'car events)))
      (is (string= "First normalized stream event delivered."
                   (getf (cdr (assoc "pi.ai.first_chunk" events :test #'string=))
                         :description)))
      (is (null (getf (cdr (assoc "pi.ai.first_chunk" events :test #'string=))
                      :attributes)))
      (is (string= "A completed content block; content is never recorded."
                   (getf block :description)))
      (is (equal '("text" "thinking" "tool_call")
                 (cadr-telemetry::telemetry-attribute-definition-values
                  (telemetry-schema-attribute (getf block :attributes) "type"))))
      (is (equal '(:default "ok"
                   :error-when
                   "Stop reason is error: provider_error with at most 500 error-message characters. Aborted stays ok.")
                 (cadr-telemetry::telemetry-span-definition-status request)))
      (is (eq (telemetry-schema-attribute start "provider")
              (telemetry-schema-attribute
               (cadr-telemetry::telemetry-metric-definition-attributes duration)
               "provider")))
      (is (equal '("provider" "model" "stop")
                 (mapcar #'car
                         (cadr-telemetry::telemetry-metric-definition-attributes duration))))
      (is (cadr-telemetry:telemetry-attribute-definition-required
           (telemetry-schema-attribute
            (cadr-telemetry::telemetry-metric-definition-attributes duration)
            "stop")))
      (is (not (eq (telemetry-schema-attribute end "stop")
                   (telemetry-schema-attribute
                    (cadr-telemetry::telemetry-metric-definition-attributes duration)
                    "stop"))))
      (is (equal '("provider" "model")
                 (mapcar #'car
                         (cadr-telemetry::telemetry-metric-definition-attributes
                          first-chunk))))
      (is (equal '("provider" "model" "kind")
                 (mapcar #'car
                         (cadr-telemetry::telemetry-metric-definition-attributes tokens))))
      (is (equal '("input" "output" "cache_read" "cache_write")
                 (cadr-telemetry::telemetry-attribute-definition-values
                  (telemetry-schema-attribute
                   (cadr-telemetry::telemetry-metric-definition-attributes tokens)
                   "kind"))))
      (is (equal '("provider" "model")
                 (mapcar #'car
                         (cadr-telemetry::telemetry-metric-definition-attributes cost))))
      (is (string= "token" (cadr-telemetry:telemetry-metric-definition-unit tokens)))
      (is (string= "USD" (cadr-telemetry:telemetry-metric-definition-unit cost)))
      (is (string= "ms" (cadr-telemetry:telemetry-metric-definition-unit duration)))
      (is (string= "histogram"
                   (cadr-telemetry:telemetry-metric-definition-kind first-chunk)))
      (is (string= "counter" (cadr-telemetry:telemetry-metric-definition-kind tokens))))
    (let* ((context (cadr-telemetry:make-in-memory-telemetry))
           (starter (cadr-telemetry:create-typed-span-starter context (list schema))))
      (funcall starter "parent" nil
               (lambda (parent child-starter)
                 (declare (ignore parent))
                 (funcall child-starter "child" '(("k" . "v"))
                          (lambda (child nested)
                            (declare (ignore nested))
                            (cadr-telemetry:telemetry-add-event child "seen")))))
      (let ((spans (cadr-telemetry:in-memory-telemetry-spans context)))
        (is (= 2 (length spans)))
        (is (eql (cadr-telemetry:recorded-telemetry-span-id (first spans))
                 (cadr-telemetry:recorded-telemetry-span-parent-id
                  (second spans))))))))

(test telemetry-memory-records-attributes-links-and-settlement
  (let* ((wall 1000)
         (mono 100)
         (cadr-telemetry:*telemetry-wall-milliseconds* (lambda () wall))
         (cadr-telemetry:*telemetry-monotonic-milliseconds* (lambda () mono))
         (context (cadr-telemetry:make-in-memory-telemetry))
         (tags (vector "initial"))
         (reason (vector "initial")))
    (let ((open nil)
          (live nil))
      (cadr-telemetry:telemetry-start-span
       context "root"
       (lambda (span)
         (setf live span)
         (setf open (find "root"
                          (cadr-telemetry:in-memory-telemetry-spans context)
                          :key #'cadr-telemetry:recorded-telemetry-span-name
                          :test #'string=))
         (is (not (cadr-telemetry:recorded-telemetry-span-settled open)))
         (cadr-telemetry:telemetry-set-attributes
          span `(("attempt" . 1) ("enabled" . nil) ("tags" . ,tags)
                 ("skip" . :undefined)))
         (setf (aref tags 0) "mutated")
         (cadr-telemetry:telemetry-set-attributes
          span '(("attempt" . 2) ("skip" . :undefined) ("added" . "yes")))
         (setf mono 110)
         (cadr-telemetry:telemetry-add-event span "checkpoint" '(("phase" . "tools")))
         (let ((target
                 (cadr-telemetry:telemetry-start-span
                  span "target" (lambda (child) child))))
           (cadr-telemetry:telemetry-add-link
            span target :attributes `(("reason" . ,reason)))
           (setf (aref reason 0) "mutated")
           (cadr-telemetry:telemetry-add-link
            span cadr-telemetry:*noop-telemetry-context*))
         (setf mono 125)
         (cadr-telemetry:telemetry-set-status span :kind :ok)
         "result"))
      (let* ((spans (cadr-telemetry:in-memory-telemetry-spans context))
             (root (find "root" spans
                         :key #'cadr-telemetry:recorded-telemetry-span-name
                         :test #'string=))
             (attributes (cadr-telemetry:recorded-telemetry-span-attributes root)))
        (is (string= "result"
                     (cadr-telemetry:telemetry-start-span
                      context "ignored" (lambda (span) (declare (ignore span)) "result"))))
        (is (cadr-telemetry:recorded-telemetry-span-settled root))
        (is (telemetry-uuid-v4-p
             (telemetry-attr
              (cadr-telemetry:recorded-telemetry-span-context root)
              "pi-memory-scope")))
        (let ((stored (first
                       (cadr-telemetry:stored-trace-spans
                        (cadr-telemetry:in-memory-telemetry-trace
                         context
                         (telemetry-attr
                          (cadr-telemetry:recorded-telemetry-span-context root)
                          "pi-memory-trace"))))))
          (is (string= (cadr-telemetry:stored-span-id stored)
                       (cadr-telemetry:stored-span-trace-id stored))))
        (is (telemetry-same '(("attempt" . 2) ("enabled" . nil)
                              ("tags" . #("initial")) ("added" . "yes"))
                            attributes))
        (is (= 1 (length (cadr-telemetry:recorded-telemetry-span-links root))))
        (is (equal "initial"
                   (aref (telemetry-attr
                          (cadr-telemetry:recorded-telemetry-link-attributes
                           (first (cadr-telemetry:recorded-telemetry-span-links root)))
                          "reason")
                         0)))
        (cadr-telemetry:telemetry-add-event live "late")
        (cadr-telemetry:telemetry-set-attributes live '(("added" . "no")))
        (is (= 1 (length (cadr-telemetry:recorded-telemetry-span-events
                          (find "root" (cadr-telemetry:in-memory-telemetry-spans context)
                                :key #'cadr-telemetry:recorded-telemetry-span-name
                                :test #'string=)))))
        (let ((before (length (cadr-telemetry:in-memory-telemetry-spans context))))
          (is (= 7
                 (cadr-telemetry:telemetry-start-span
                  live "late-child"
                  (lambda (child)
                    (is (eq context (cadr-telemetry:telemetry-span-metrics child)))
                    7))))
          (is (= before (length (cadr-telemetry:in-memory-telemetry-spans context)))))))))

(test telemetry-records-thrown-errors-unless-status-was-explicit
  (let ((context (cadr-telemetry:make-in-memory-telemetry))
        (condition (make-condition 'simple-error
                                   :format-control "sync"
                                   :format-arguments nil)))
    (handler-case
        (cadr-telemetry:telemetry-start-span
         context "boom"
         (lambda (span)
           (declare (ignore span))
           (error condition)))
      (simple-error (caught) (is (eq condition caught))))
    (let ((status (cadr-telemetry:recorded-telemetry-span-status
                   (first (cadr-telemetry:in-memory-telemetry-spans context)))))
      (is (eq :error (cadr-telemetry:telemetry-status-kind status)))
      (is (string= "Error" (cadr-telemetry:telemetry-status-error-name status)))
      (is (string= "sync" (cadr-telemetry:telemetry-status-error-message status)))))
  (let ((context (cadr-telemetry:make-in-memory-telemetry)))
    (handler-case
        (cadr-telemetry:telemetry-start-span
         context "kept"
         (lambda (span)
           (cadr-telemetry:telemetry-set-status
            span :kind :error :error-name "kept" :error-message "mine")
           (error "later")))
      (error () nil))
    (let ((status (cadr-telemetry:recorded-telemetry-span-status
                   (first (cadr-telemetry:in-memory-telemetry-spans context)))))
      (is (string= "kept" (cadr-telemetry:telemetry-status-error-name status)))
      (is (string= "mine" (cadr-telemetry:telemetry-status-error-message status))))))

(test telemetry-propagation-copies-carriers-and-continues-remote-traces
  (let ((left (cadr-telemetry:make-in-memory-telemetry))
        (right (cadr-telemetry:make-in-memory-telemetry)))
    (cadr-telemetry:telemetry-start-span
     left "root"
     (lambda (span)
       (let* ((first (cadr-telemetry:telemetry-inject left span))
              (mutated (cadr-telemetry:telemetry-inject left span)))
         (setf (cdr (assoc "pi-memory-scope" mutated :test #'string=)) "mutated")
         (is (not (string= "mutated"
                           (cdr (assoc "pi-memory-scope"
                                       (cadr-telemetry:telemetry-inject left span)
                                       :test #'string=)))))
         (is (eq left (cadr-telemetry:telemetry-extract left '(("pi-memory-span" . 42)))))
         (is (eq left (cadr-telemetry:telemetry-extract
                       left
                       (remove "pi-memory-trace" first :key #'car :test #'string=))))
         (let ((parent (cadr-telemetry:telemetry-extract right first)))
           (cadr-telemetry:telemetry-start-span
            parent "remote"
            (lambda (child) (declare (ignore child)) nil)))
         (setf (cdr (assoc "pi-memory-span" first :test #'string=)) "changed"))))
    (let ((remote (find "remote" (cadr-telemetry:in-memory-telemetry-spans right)
                        :key #'cadr-telemetry:recorded-telemetry-span-name
                        :test #'string=)))
      (is (null (cadr-telemetry:recorded-telemetry-span-parent-id remote)))
      (is (string= (cdr (assoc "pi-memory-trace"
                               (cadr-telemetry:recorded-telemetry-span-context
                                (find "root"
                                      (cadr-telemetry:in-memory-telemetry-spans left)
                                      :key #'cadr-telemetry:recorded-telemetry-span-name
                                      :test #'string=))
                               :test #'string=))
                   (cdr (assoc "pi-memory-trace"
                               (cadr-telemetry:recorded-telemetry-span-context remote)
                               :test #'string=))))
      (is (not (string= "changed"
                        (cdr (assoc "pi-memory-span"
                                    (cadr-telemetry:recorded-telemetry-span-parent-context
                                     remote)
                                    :test #'string=))))))))

(test telemetry-concurrent-children-take-end-sequence-in-finish-order
  (let* ((context (cadr-telemetry:make-in-memory-telemetry))
         (entered (sb-thread:make-semaphore :name "telemetry-entered"))
         (release-second (sb-thread:make-semaphore :name "telemetry-second"))
         (release-first (sb-thread:make-semaphore :name "telemetry-first")))
    (cadr-telemetry:telemetry-start-span
     context "parent"
     (lambda (parent)
       (let ((second
               (sb-thread:make-thread
                (lambda ()
                  (cadr-telemetry:telemetry-start-span
                   parent "second"
                   (lambda (span)
                     (declare (ignore span))
                     (sb-thread:signal-semaphore entered)
                     (sb-thread:wait-on-semaphore release-second))))))
             (first
               (sb-thread:make-thread
                (lambda ()
                  (cadr-telemetry:telemetry-start-span
                   parent "first"
                   (lambda (span)
                     (declare (ignore span))
                     (sb-thread:signal-semaphore entered)
                     (sb-thread:wait-on-semaphore release-first)))))))
         (sb-thread:wait-on-semaphore entered)
         (sb-thread:wait-on-semaphore entered)
         (sb-thread:signal-semaphore release-second)
         (sb-thread:join-thread second)
         (sb-thread:signal-semaphore release-first)
         (sb-thread:join-thread first))))
    (let ((spans (cadr-telemetry:in-memory-telemetry-spans context)))
      (flet ((sequence-of (name)
               (cadr-telemetry:recorded-telemetry-span-end-sequence
                (find name spans
                      :key #'cadr-telemetry:recorded-telemetry-span-name
                      :test #'string=))))
        (is (= 1 (sequence-of "second")))
        (is (= 2 (sequence-of "first")))
        (is (= 3 (sequence-of "parent")))))))

(test telemetry-store-filters-pages-and-detaches-snapshots
  (let* ((wall 20000)
         (mono 0)
         (cadr-telemetry:*telemetry-wall-milliseconds* (lambda () wall))
         (cadr-telemetry:*telemetry-monotonic-milliseconds* (lambda () mono))
         (context (cadr-telemetry:make-in-memory-telemetry)))
    (loop for index from 1 to 25
          do (let ((current index))
               (setf wall (* 1000 current))
               (handler-case
                   (cadr-telemetry:telemetry-start-span
                    context (if (= current 7) "special" "work")
                    (lambda (span)
                      (setf mono (+ mono 10))
                      (cadr-telemetry:telemetry-add-event span "tick")
                      (when (= current 3)
                        (cadr-telemetry:telemetry-set-attributes
                         span '(("lane" . "g27e") ("n" . 3)))
                        (error "marked"))
                      (when (= current 4)
                        (cadr-telemetry:telemetry-set-status span :kind :ok))))
                 (simple-error (condition)
                   (is (= 3 current))
                   (is (string= "marked" (princ-to-string condition)))))))
    (multiple-value-bind (page cursor)
        (cadr-telemetry:in-memory-telemetry-find-traces context)
      (is (= 20 (length page)))
      (is (string= (format nil "[~D,~S]"
                           (cadr-telemetry:stored-span-started-ms
                            (first (cadr-telemetry:stored-trace-spans (car (last page)))))
                           (cadr-telemetry:stored-trace-id (car (last page))))
                   cursor))
      (multiple-value-bind (rest next)
          (cadr-telemetry:in-memory-telemetry-find-traces context :cursor cursor)
        (is (= 5 (length rest)))
        (is (null next))))
    (is (= 1 (length (cadr-telemetry:in-memory-telemetry-find-traces
                      context :name "special"))))
    (is (= 1 (length (cadr-telemetry:in-memory-telemetry-find-traces
                      context :errors t))))
    (is (= 1 (length (cadr-telemetry:in-memory-telemetry-find-traces
                      context :attributes '(("lane" . "g27e") ("n" . 3))))))
    (is (null (cadr-telemetry:in-memory-telemetry-find-traces
               context :attributes '(("lane" . "g27e") ("n" . 4)))))
    (let* ((trace (first (cadr-telemetry:in-memory-telemetry-find-traces
                          context :attributes '(("lane" . "g27e")))))
           (stored (cadr-telemetry:in-memory-telemetry-trace
                    context (cadr-telemetry:stored-trace-id trace)))
           (span (find-if (lambda (item)
                            (string= "g27e"
                                     (or (telemetry-attr
                                          (cadr-telemetry:stored-span-attributes item)
                                          "lane")
                                         "")))
                          (cadr-telemetry:stored-trace-spans stored))))
      (is (>= (cadr-telemetry:stored-span-ended-ms span)
              (cadr-telemetry:stored-span-started-ms span)))
      (is (>= (cadr-telemetry:stored-event-time-ms
               (first (cadr-telemetry:stored-span-events span)))
              0))
      (setf (cdr (assoc "lane" (cadr-telemetry:stored-span-attributes span)
                        :test #'string=))
            "changed")
      (is (string= "g27e"
                   (telemetry-attr
                    (cadr-telemetry:stored-span-attributes
                     (first (cadr-telemetry:stored-trace-spans
                             (cadr-telemetry:in-memory-telemetry-trace
                              context (cadr-telemetry:stored-trace-id trace)))))
                    "lane"))))
    (let ((boundaries (list 1 10))
          (description (copy-seq "Duration"))
          (tags (vector "a")))
      (let ((histogram (cadr-telemetry:telemetry-histogram
                        context "snapshot"
                        :description description
                        :unit "ms"
                        :boundaries boundaries)))
        (setf (char description 0) #\X)
        (nconc boundaries (list 100))
        (cadr-telemetry:telemetry-histogram-record
         histogram 4 `(("tags" . ,tags)) context)
        (setf (aref tags 0) "z"))
      (let ((measurement (first (cadr-telemetry:in-memory-measurements context))))
        (is (string= "Duration"
                     (cadr-telemetry:recorded-measurement-description measurement)))
        (is (equal '(1 10)
                   (cadr-telemetry:recorded-measurement-boundaries measurement)))
        (is (string= "a"
                     (aref (telemetry-attr
                            (cadr-telemetry:recorded-measurement-attributes measurement)
                            "tags")
                           0)))
        (is (= 20000 (cadr-telemetry:stored-metric-interval-ms
                      (first (cadr-telemetry:in-memory-telemetry-find-metrics
                              context :name "snapshot")))))
        (is (null (cadr-telemetry:in-memory-telemetry-find-metrics
                   context :name "snapshot" :start-min 30000)))))
    (let ((counter (cadr-telemetry:telemetry-counter context "hits" :unit "1")))
      (cadr-telemetry:telemetry-counter-add counter 2 '(("k" . "v"))))
    (let ((row (first (cadr-telemetry:in-memory-telemetry-find-metrics
                       context :name "hits"))))
      (is (= 1 (cadr-telemetry:stored-metric-count row)))
      (is (= 2 (cadr-telemetry:stored-metric-sum row)))
      (is (string= "1" (cadr-telemetry:stored-metric-unit row)))
      (is (null (cadr-telemetry:recorded-measurement-context
                 (find "hits" (cadr-telemetry:in-memory-measurements context)
                       :key #'cadr-telemetry:recorded-measurement-name
                       :test #'string=)))))))

(defun telemetry-stored (name &rest args &key attributes events links status
                                    parent-id started-ms ended-ms)
  (declare (ignore attributes events links status parent-id started-ms ended-ms))
  (apply #'cadr-telemetry:make-stored-span
         :id name :trace-id "trace" :name name
         :started-ms 0 :ended-ms 10
         :status (cadr-telemetry:make-telemetry-status)
         args))

(test telemetry-render-matches-the-v140-forest
  (let* ((root
           (cadr-telemetry:make-stored-span
            :id "root" :trace-id "trace" :name "root"
            :started-ms 1000 :ended-ms 1020
            :attributes `(("request" . "a b") ("attempt" . 2) ("cached" . nil)
                          ("tags" . #("a" "b")) ("sizes" . #(1 2))
                          ("flags" . #(t nil)))
            :events (list (cadr-telemetry:make-stored-event
                           :name "checkpoint" :time-ms 2
                           :attributes '(("phase" . "tools")))
                          (cadr-telemetry:make-stored-event
                           :name "tick" :time-ms 3.5d0))
            :links (list (cadr-telemetry:make-stored-link
                          :trace-id "remote-trace" :span-id "remote"
                          :attributes '(("reason" . "steer")))
                         (cadr-telemetry:make-stored-link
                          :trace-id "other-trace" :span-id "other"))
            :status (cadr-telemetry:make-telemetry-status)))
         (first-span
           (cadr-telemetry:make-stored-span
            :id "first" :trace-id "trace" :name "first" :parent-id "root"
            :started-ms 1005 :ended-ms 1009.5d0
            :status (cadr-telemetry:make-telemetry-status
                     :kind :error :error-p t
                     :error-name "Error" :error-message "failed call")))
         (nested
           (cadr-telemetry:make-stored-span
            :id "nested" :trace-id "trace" :name "nested" :parent-id "first"
            :started-ms 1006 :ended-ms 1007
            :status (cadr-telemetry:make-telemetry-status)))
         (second
           (cadr-telemetry:make-stored-span
            :id "second" :trace-id "trace" :name "second" :parent-id "root"
            :started-ms 1010 :ended-ms 1012
            :status (cadr-telemetry:make-telemetry-status :kind :error)))
         (spans (list second nested first-span root)))
    (is (string=
         (format nil "~{~A~^~%~}"
                 '("root request=\"a b\" attempt=2 cached=false tags=[\"a\",\"b\"] sizes=[1,2] flags=[true,false] (20ms)"
                   "  · checkpoint phase=\"tools\" (+2ms)"
                   "  · tick (+3.5ms)"
                   "  → link trace remote-trace span remote reason=\"steer\""
                   "  → link trace other-trace span other"
                   "  first (4.5ms) error Error: failed call"
                   "    nested (1ms)"
                   "  second (2ms) error"))
         (cadr-telemetry:render-trace spans)))
    (is (string= "root" (cadr-telemetry:stored-span-name (fourth spans)))))
  (is (string=
       (format nil "~{~A~^~%~}"
               '("earlier (5ms)"
                 "  → link trace trace span later"
                 "later (10ms)"
                 "  child (5ms)"))
       (cadr-telemetry:render-trace
        (list (cadr-telemetry:make-stored-span
               :id "later" :trace-id "trace" :name "later" :parent-id "external"
               :started-ms 20 :ended-ms 30
               :status (cadr-telemetry:make-telemetry-status))
              (cadr-telemetry:make-stored-span
               :id "child" :trace-id "trace" :name "child" :parent-id "later"
               :started-ms 25 :ended-ms 30
               :status (cadr-telemetry:make-telemetry-status))
              (cadr-telemetry:make-stored-span
               :id "earlier" :trace-id "trace" :name "earlier"
               :started-ms 10 :ended-ms 15
               :links (list (cadr-telemetry:make-stored-link
                             :trace-id "trace" :span-id "later"))
               :status (cadr-telemetry:make-telemetry-status))))))
  (is (string= "root (10ms)
  z (10ms)
  a (10ms)
other (10ms)"
               (cadr-telemetry:render-trace
                (list (telemetry-stored "root")
                      (telemetry-stored "z" :parent-id "root")
                      (telemetry-stored "a" :parent-id "root")
                      (telemetry-stored "other")))))
  (is (string= "root text=\"line one\\n\\\"line two\\\"\" (10ms)"
               (cadr-telemetry:render-trace
                (list (telemetry-stored
                       "root"
                       :attributes '(("text" . "line one
\"line two\"")))))))
  (is (string= "" (cadr-telemetry:render-trace nil)))
  (let ((spans
          (loop for index from 0 below 2000
                collect (cadr-telemetry:make-stored-span
                         :id (princ-to-string index)
                         :trace-id "trace"
                         :name (princ-to-string index)
                         :parent-id (if (zerop index) nil (princ-to-string (1- index)))
                         :started-ms index :ended-ms (+ index 10)
                         :status (cadr-telemetry:make-telemetry-status)))))
    (let ((rendered (cadr-telemetry:render-trace spans)))
      (is (= 2000 (length (uiop:split-string rendered :separator '(#\Newline)))))
      (is (string= (format nil "~A1999 (10ms)"
                           (make-string (* 1999 2) :initial-element #\Space))
                   (car (last (uiop:split-string rendered :separator '(#\Newline)))))))))

(test telemetry-observation-omits-content-and-bounds-provider-errors
  (let* ((mono 100)
         (cadr-telemetry:*telemetry-monotonic-milliseconds* (lambda () mono))
         (context (cadr-telemetry:make-in-memory-telemetry))
         (model (telemetry-model))
         (message (telemetry-message)))
    (cadr-telemetry:telemetry-start-span
     context "caller"
     (lambda (parent)
       (telemetry-observe model parent (telemetry-events message) message
                          :reasoning "high"
                          :clock
                          (lambda (phase)
                            (setf mono (if (eq phase :events) 125 175))))))
    (let* ((spans (cadr-telemetry:in-memory-telemetry-spans context))
           (span (second spans))
           (attributes (cadr-telemetry:recorded-telemetry-span-attributes span)))
      (is (string= "pi.ai.request"
                   (cadr-telemetry:recorded-telemetry-span-name span)))
      (is (eql (cadr-telemetry:recorded-telemetry-span-id (first spans))
               (cadr-telemetry:recorded-telemetry-span-parent-id span)))
      (is (telemetry-same
           '(("provider" . "test") ("api" . "telemetry-test") ("model" . "model")
             ("reasoning" . "high") ("stop" . "stop")
             ("usage.input" . 11) ("usage.output" . 22)
             ("usage.cache_read" . 33) ("usage.cache_write" . 44)
             ("cost.total" . 1) ("response.id" . "response"))
           attributes))
      (is (= 4 (length (cadr-telemetry:recorded-telemetry-span-events span))))
      (is (not (search "text-secret" (telemetry-span-text span))))
      (is (not (search "thinking-secret" (telemetry-span-text span))))
      (is (not (search "argument-secret" (telemetry-span-text span))))
      (is (not (search "call-secret" (telemetry-span-text span))))
      (let ((metrics (cadr-telemetry:in-memory-measurements context)))
        (is (= 7 (length metrics)))
        (is (telemetry-same '(11 22 33 44 1)
                            (mapcar #'cadr-telemetry:recorded-measurement-value
                                    (remove "counter"
                                            metrics
                                            :key #'cadr-telemetry:recorded-measurement-kind
                                            :test-not #'string=))))
        (is (= 25 (cadr-telemetry:recorded-measurement-value (first metrics))))
        (is (= 75 (cadr-telemetry:recorded-measurement-value (second metrics))))
        (is (string= "ms" (cadr-telemetry:recorded-measurement-unit (first metrics))))
        (is (string= "token" (cadr-telemetry:recorded-measurement-unit (third metrics))))
        (is (string= "USD" (cadr-telemetry:recorded-measurement-unit
                            (car (last metrics))))))))
  (let ((context (cadr-telemetry:make-in-memory-telemetry))
        (model (telemetry-model)))
    (dolist (stop '(:error :aborted))
      (let ((message (telemetry-message :stop stop :error-message "error-secret")))
        (cadr-telemetry:telemetry-start-span
         context "caller"
         (lambda (parent)
           (telemetry-observe model parent
                              (append (telemetry-events message)
                                      (list (cadr-ai:make-stream-event
                                             :type :error :reason stop
                                             :message message)))
                              message)))))
    (let ((spans (remove "caller" (cadr-telemetry:in-memory-telemetry-spans context)
                         :key #'cadr-telemetry:recorded-telemetry-span-name
                         :test #'string=)))
      (is (string= "provider_error"
                   (cadr-telemetry:telemetry-status-error-name
                    (cadr-telemetry:recorded-telemetry-span-status (first spans)))))
      (is (string= "error-secret"
                   (cadr-telemetry:telemetry-status-error-message
                    (cadr-telemetry:recorded-telemetry-span-status (first spans)))))
      (is (not (search "error-secret"
                       (telemetry-span-text
                        (cadr-telemetry:recorded-telemetry-span-attributes (first spans))))))
      (is (eq :ok (cadr-telemetry:telemetry-status-kind
                   (cadr-telemetry:recorded-telemetry-span-status (second spans)))))
      (is (not (search "error-secret" (telemetry-span-text (second spans)))))))
  (let* ((context (cadr-telemetry:make-in-memory-telemetry))
         (tail (make-string 500 :initial-element #\x))
         (message (telemetry-message
                   :stop :error
                   :error-message (concatenate 'string tail "discarded-tail"))))
    (multiple-value-bind (runtime model)
        (telemetry-deferred-runtime message)
      (cadr-telemetry:telemetry-start-span
       context "caller"
       (lambda (parent)
         (cadr-ai:models-runtime-fetch-deferred
          runtime model '(:id "deferred-secret")
          :telemetry parent :api-key "k"))))
    (let ((span (second (cadr-telemetry:in-memory-telemetry-spans context))))
      (is (string= "pi.ai.poll"
                   (cadr-telemetry:recorded-telemetry-span-name span)))
      (is (string= tail
                   (cadr-telemetry:telemetry-status-error-message
                    (cadr-telemetry:recorded-telemetry-span-status span))))
      (is (not (search "discarded-tail" (telemetry-span-text span))))
      (is (not (search "deferred-secret" (telemetry-span-text span))))
      (is (not (search "xxx"
                       (telemetry-span-text
                        (cadr-telemetry:recorded-telemetry-span-attributes span)))))))
  (let* ((context (cadr-telemetry:make-in-memory-telemetry))
         (split (concatenate 'string
                             (make-string 499 :initial-element #\x)
                             (string (code-char #x1F600))))
         (kept (concatenate 'string
                            (make-string 498 :initial-element #\x)
                            (string (code-char #x1F600))))
         (message (telemetry-message :stop :error :error-message split)))
    (multiple-value-bind (runtime model)
        (telemetry-deferred-runtime message)
      (cadr-telemetry:telemetry-start-span
       context "caller"
       (lambda (parent)
         (cadr-ai:models-runtime-fetch-deferred
          runtime model '(:id "deferred-secret")
          :telemetry parent :api-key "k"))))
    (let ((status (cadr-telemetry:telemetry-status-error-message
                   (cadr-telemetry:recorded-telemetry-span-status
                    (second (cadr-telemetry:in-memory-telemetry-spans context))))))
      (is (string= (concatenate 'string
                                (make-string 499 :initial-element #\x)
                                (string (code-char #xD83D)))
                   status))
      (is (= 500 (cadr-ai::telemetry-utf16-length status)))
      (is (= #xD83D (char-code (char status (1- (length status)))))))
    (let ((whole (cadr-telemetry:make-in-memory-telemetry)))
      (multiple-value-bind (runtime model)
          (telemetry-deferred-runtime
           (telemetry-message :stop :error :error-message kept))
        (cadr-telemetry:telemetry-start-span
         whole "caller"
         (lambda (parent)
           (cadr-ai:models-runtime-fetch-deferred
            runtime model '(:id "deferred-secret")
            :telemetry parent :api-key "k"))))
      (is (string= kept
                   (cadr-telemetry:telemetry-status-error-message
                    (cadr-telemetry:recorded-telemetry-span-status
                     (second (cadr-telemetry:in-memory-telemetry-spans whole))))))))
  (let ((context (cadr-telemetry:make-in-memory-telemetry))
        (message (telemetry-message :stop :error :error-message nil)))
    (multiple-value-bind (runtime model)
        (telemetry-deferred-runtime message)
      (cadr-telemetry:telemetry-start-span
       context "caller"
       (lambda (parent)
         (cadr-ai:models-runtime-fetch-deferred
          runtime model '(:id "deferred-secret")
          :telemetry parent :api-key "k"))))
    (is (string= ""
                 (cadr-telemetry:telemetry-status-error-message
                  (cadr-telemetry:recorded-telemetry-span-status
                   (second (cadr-telemetry:in-memory-telemetry-spans context)))))))
  (let ((context (cadr-telemetry:make-in-memory-telemetry))
        (message (telemetry-message :stop :error :error-message "Unknown provider: test")))
    (cadr-telemetry:telemetry-start-span
     context "caller"
     (lambda (parent)
       (telemetry-observe (telemetry-model) parent
                          (list (cadr-ai:make-stream-event :type :error :message message))
                          message
                          :reasoning '(("effort" . "native-secret")))))
    (let ((span (second (cadr-telemetry:in-memory-telemetry-spans context))))
      (is (null (assoc "reasoning"
                       (cadr-telemetry:recorded-telemetry-span-attributes span)
                       :test #'string=)))
      (is (string= "Unknown provider: test"
                   (cadr-telemetry:telemetry-status-error-message
                    (cadr-telemetry:recorded-telemetry-span-status span))))
      (is (= 1 (length (cadr-telemetry:recorded-telemetry-span-events span))))
      (is (not (search "native-secret" (telemetry-span-text span))))
      (is (not (search "Unknown provider"
                       (telemetry-span-text
                        (cadr-telemetry:recorded-telemetry-span-attributes span))))))))

(test telemetry-tool-deltas-are-counted-without-reading-arguments
  (let* ((context (cadr-telemetry:make-in-memory-telemetry))
         (message (telemetry-message))
         (call (cadr-ai:make-tool-call :id "call" :name "lookup")))
    (cadr-telemetry:telemetry-start-span
     context "caller"
     (lambda (parent)
       (cadr-ai:call-with-observed-model-request
        (telemetry-model) (list :telemetry parent) nil
        (lambda (observe finish)
          (dolist (pair '((2 . "ab") (3 . "123") (2 . "c")))
            (funcall observe
                     (cadr-ai:make-stream-event
                      :type :tool-call-delta
                      :content-index (car pair)
                      :delta (cdr pair)
                      :message message)))
          (dolist (index '(3 2 4))
            (funcall observe
                     (cadr-ai:make-stream-event
                      :type :tool-call-end
                      :content-index index
                      :tool-call call
                      :message message)))
          (funcall finish message)))))
    (let ((events (cdr (cadr-telemetry:recorded-telemetry-span-events
                        (second (cadr-telemetry:in-memory-telemetry-spans context))))))
      (is (telemetry-same
           '((("type" . "tool_call") ("index" . 3) ("chars" . 3) ("tool" . "lookup"))
             (("type" . "tool_call") ("index" . 2) ("chars" . 3) ("tool" . "lookup"))
             (("type" . "tool_call") ("index" . 4) ("chars" . 0) ("tool" . "lookup")))
           (mapcar #'cadr-telemetry:recorded-telemetry-event-attributes events))))))

(test telemetry-metrics-follow-the-span-and-are-created-once
  (let ((context (cadr-telemetry:make-in-memory-telemetry))
        (model (telemetry-model))
        (message (telemetry-message)))
    (cadr-telemetry:telemetry-start-span
     context "caller"
     (lambda (parent)
       (let ((tracing (cadr-telemetry:copy-telemetry-span parent :metrics nil)))
         (telemetry-observe model tracing nil message))))
    (is (= 2 (length (cadr-telemetry:in-memory-telemetry-spans context))))
    (is (null (cadr-telemetry:in-memory-measurements context))))
  (dolist (stop '(:pending :deferred :stop :error))
    (let ((context (cadr-telemetry:make-in-memory-telemetry)))
      (multiple-value-bind (runtime model)
          (telemetry-deferred-runtime
           (telemetry-message :stop stop)
           :events (list (cadr-ai:make-stream-event :type :start)))
        (cadr-telemetry:telemetry-start-span
         context "caller"
         (lambda (parent)
           (cadr-ai:models-runtime-fetch-deferred
            runtime model '(:id "deferred-secret")
            :telemetry parent :api-key "k"))))
      (is (= (if (member stop '(:pending :deferred)) 0 5)
             (count "counter"
                    (cadr-telemetry:in-memory-measurements context)
                    :key #'cadr-telemetry:recorded-measurement-kind
                    :test #'string=)))
      (is (string= "pi.ai.poll"
                   (cadr-telemetry:recorded-telemetry-span-name
                    (second (cadr-telemetry:in-memory-telemetry-spans context)))))))
  (let* ((context (cadr-telemetry:make-in-memory-telemetry))
         (histograms nil)
         (counters nil)
         (original-histogram (cadr-telemetry::telemetry-span-histogram-fn context))
         (original-counter (cadr-telemetry::telemetry-span-counter-fn context)))
    (setf (cadr-telemetry::telemetry-span-histogram-fn context)
          (lambda (name description unit boundaries)
            (push name histograms)
            (funcall original-histogram name description unit boundaries))
          (cadr-telemetry::telemetry-span-counter-fn context)
          (lambda (name description unit)
            (push name counters)
            (funcall original-counter name description unit)))
    (multiple-value-bind (runtime model)
        (telemetry-deferred-runtime
         (telemetry-message)
         :events (list (cadr-ai:make-stream-event :type :start)))
      (cadr-telemetry:telemetry-start-span
       context "caller"
       (lambda (parent)
         (cadr-ai:models-runtime-stream
          runtime model (cadr-ai:make-context)
          (lambda (event) (declare (ignore event)) nil)
          :telemetry parent :api-key "k")))
      (cadr-telemetry:telemetry-start-span
       context "caller"
       (lambda (parent)
         (cadr-ai:models-runtime-fetch-deferred
          runtime model '(:id "deferred-secret")
          :telemetry parent :api-key "k")))
      (cadr-telemetry:telemetry-start-span
       context "caller"
       (lambda (parent)
         (cadr-ai:models-runtime-stream
          runtime model (cadr-ai:make-context)
          (lambda (event) (declare (ignore event)) nil)
          :telemetry parent :api-key "k"))))
    (is (equal '("pi.ai.request.duration" "pi.ai.first_chunk.duration")
               (reverse histograms)))
    (is (equal '("pi.ai.tokens" "pi.ai.cost") (reverse counters)))
    (is (= 21 (length (cadr-telemetry:in-memory-measurements context))))))

(test telemetry-models-runtime-records-a-child-span-only-when-one-is-passed
  (let* ((model (cadr-ai:make-model
                 :id "model" :name "Model"
                 :provider :telemetry-test :api :telemetry-test
                 :base-url "https://example.test"))
         (message (telemetry-message))
         (events (telemetry-events message))
         (received nil)
         (provider
           (cadr-ai:make-runtime-provider
            :id :telemetry-test :name "telemetry"
            :models (list model)
            :api-key-auth-p t
            :auth-resolver
            (lambda (&rest ignored)
              (declare (ignore ignored))
              (cadr-ai:make-runtime-auth-result :type :api-key :api-key "k"))
            :stream-function
            (lambda (request-model context on-event &rest options)
              (declare (ignore request-model context options))
              (dolist (event events)
                (funcall on-event event))
              message)
            :complete-function
            (lambda (request-model context options)
              (declare (ignore request-model context options))
              message)
            :fetch-deferred-function
            (lambda (request-model handle on-event &rest options)
              (declare (ignore request-model options))
              (unless (equal '(:id "deferred-secret") handle)
                (error "deferred handle was not delivered"))
              (dolist (event events)
                (funcall on-event event))
              message)))
         (runtime (cadr-ai:make-models-runtime))
         (context (cadr-telemetry:make-in-memory-telemetry)))
    (cadr-ai:models-runtime-set-provider runtime provider)
    (cadr-telemetry:telemetry-start-span
     context "caller"
     (lambda (parent)
       (cadr-ai:models-runtime-stream
        runtime model (cadr-ai:make-context)
        (lambda (event) (push event received))
        :telemetry parent :api-key "k")))
    (is (equal events (reverse received)))
    (is (string= "pi.ai.request"
                 (cadr-telemetry:recorded-telemetry-span-name
                  (second (cadr-telemetry:in-memory-telemetry-spans context)))))
    (is (= 7 (length (cadr-telemetry:in-memory-measurements context))))
    (cadr-telemetry:telemetry-start-span
     context "poll"
     (lambda (parent)
       (let ((result
               (cadr-ai:models-runtime-stream-deferred
                runtime model '(:id "deferred-secret")
                (lambda (event) (declare (ignore event)) nil)
                :telemetry parent :api-key "k")))
         (is (eq message result)))))
    (let ((span (find "pi.ai.poll"
                      (cadr-telemetry:in-memory-telemetry-spans context)
                      :key #'cadr-telemetry:recorded-telemetry-span-name
                      :test #'string=)))
      (is (string= "pi.ai.poll"
                   (cadr-telemetry:recorded-telemetry-span-name span)))
      (is (not (search "deferred-secret" (telemetry-span-text span))))
      (is (null (assoc "reasoning"
                       (cadr-telemetry:recorded-telemetry-span-attributes span)
                       :test #'string=)))
      (is (= 4 (length (cadr-telemetry:recorded-telemetry-span-events span)))))
    (let* ((plain
             (cadr-ai:make-runtime-provider
              :id :telemetry-test :name "telemetry"
              :models (list model)
              :api-key-auth-p t
              :auth-resolver
              (lambda (&rest ignored)
                (declare (ignore ignored))
                (cadr-ai:make-runtime-auth-result :type :api-key :api-key "k"))
              :stream-function
              (lambda (request-model context on-event &rest options)
                (declare (ignore request-model context on-event options))
                message)))
           (unsupported (cadr-ai:make-models-runtime))
           (failed (cadr-telemetry:make-in-memory-telemetry)))
      (cadr-ai:models-runtime-set-provider unsupported plain)
      (cadr-telemetry:telemetry-start-span
       failed "caller"
       (lambda (parent)
         (let ((result
                 (cadr-ai:models-runtime-fetch-deferred
                  unsupported model '(:id "deferred-secret")
                  :telemetry parent :api-key "k")))
           (is (eq :error (cadr-ai:assistant-message-stop-reason result)))
           (is (string= "Provider telemetry-test does not support deferred responses"
                        (cadr-ai:assistant-message-error-message result))))))
      (is (string= "pi.ai.poll"
                   (cadr-telemetry:recorded-telemetry-span-name
                    (second (cadr-telemetry:in-memory-telemetry-spans failed)))))
      (is (string= "Provider telemetry-test does not support deferred responses"
                   (cadr-telemetry:telemetry-status-error-message
                    (cadr-telemetry:recorded-telemetry-span-status
                     (second (cadr-telemetry:in-memory-telemetry-spans failed)))))))
    (let ((quiet (cadr-telemetry:make-in-memory-telemetry)))
      (cadr-ai:models-runtime-complete
       runtime model (cadr-ai:make-context) :api-key "k")
      (is (null (cadr-telemetry:in-memory-telemetry-spans quiet)))
      (cadr-telemetry:telemetry-start-span
       quiet "caller"
       (lambda (parent)
         (is (eq message
                 (cadr-ai:models-runtime-complete
                  runtime model (cadr-ai:make-context)
                  :telemetry parent :api-key "k")))))
      (is (telemetry-same
           '(("pi.ai.first_chunk")
             ("pi.ai.block" ("type" . "text") ("index" . 0) ("chars" . 11))
             ("pi.ai.block" ("type" . "thinking") ("index" . 1) ("chars" . 15))
             ("pi.ai.block" ("type" . "tool_call") ("index" . 2) ("chars" . 27)
              ("tool" . "lookup")))
           (telemetry-recorded-events
            (second (cadr-telemetry:in-memory-telemetry-spans quiet)))))
      (is (string= "stop"
                   (telemetry-attr
                    (cadr-telemetry:recorded-telemetry-span-attributes
                     (second (cadr-telemetry:in-memory-telemetry-spans quiet)))
                    "stop"))))
    (let* ((failed (cadr-telemetry:make-in-memory-telemetry))
           (completed (cadr-telemetry:make-in-memory-telemetry))
           (missing (cadr-ai:make-models-runtime))
           (absent (cadr-ai:make-model
                    :id "model" :name "Model" :provider :absent :api :test
                    :base-url "https://example.test")))
      (cadr-ai:models-runtime-set-provider missing provider)
      (cadr-telemetry:telemetry-start-span
       failed "caller"
       (lambda (parent)
         (let ((result
                 (cadr-ai:models-runtime-stream
                  missing absent (cadr-ai:make-context)
                  (lambda (event) (declare (ignore event)) nil)
                  :telemetry parent :api-key "k")))
           (is (eq :error (cadr-ai:assistant-message-stop-reason result)))
           (is (string= "Unknown provider: absent"
                        (cadr-ai:assistant-message-error-message result))))))
      (let ((span (second (cadr-telemetry:in-memory-telemetry-spans failed))))
        (is (string= "Unknown provider: absent"
                     (cadr-telemetry:telemetry-status-error-message
                      (cadr-telemetry:recorded-telemetry-span-status span))))
        (is (telemetry-same '(("pi.ai.first_chunk"))
                            (telemetry-recorded-events span))))
      (cadr-telemetry:telemetry-start-span
       completed "caller"
       (lambda (parent)
         (let ((result
                 (cadr-ai:models-runtime-complete
                  missing absent (cadr-ai:make-context)
                  :telemetry parent :api-key "k")))
           (is (eq :error (cadr-ai:assistant-message-stop-reason result)))
           (is (string= "Unknown provider: absent"
                        (cadr-ai:assistant-message-error-message result))))))
      (let ((span (second (cadr-telemetry:in-memory-telemetry-spans completed))))
        (is (string= "Unknown provider: absent"
                     (cadr-telemetry:telemetry-status-error-message
                      (cadr-telemetry:recorded-telemetry-span-status span))))
        (is (telemetry-same '(("pi.ai.first_chunk"))
                            (telemetry-recorded-events span)))))
    (let ((failed (cadr-telemetry:make-in-memory-telemetry))
          (missing (cadr-ai:make-models-runtime)))
      (cadr-telemetry:telemetry-start-span
       failed "caller"
       (lambda (parent)
         (let ((result
                 (cadr-ai:models-runtime-complete
                  missing (telemetry-model) (cadr-ai:make-context)
                  :telemetry parent :api-key "k"
                  :reasoning '(("effort" . "native-secret")))))
           (is (eq :error (cadr-ai:assistant-message-stop-reason result)))
           (is (string= "Unknown provider: test"
                        (cadr-ai:assistant-message-error-message result))))))
      (let ((span (second (cadr-telemetry:in-memory-telemetry-spans failed))))
        (is (string= "pi.ai.request"
                     (cadr-telemetry:recorded-telemetry-span-name span)))
        (is (telemetry-same '(("pi.ai.first_chunk"))
                            (telemetry-recorded-events span)))
        (is (eq :error
                (cadr-telemetry:telemetry-status-kind
                 (cadr-telemetry:recorded-telemetry-span-status span))))
        (is (string= "provider_error"
                     (cadr-telemetry:telemetry-status-error-name
                      (cadr-telemetry:recorded-telemetry-span-status span))))
        (is (string= "Unknown provider: test"
                     (cadr-telemetry:telemetry-status-error-message
                      (cadr-telemetry:recorded-telemetry-span-status span))))
        (is (null (assoc "reasoning"
                         (cadr-telemetry:recorded-telemetry-span-attributes span)
                         :test #'string=)))
        (is (not (search "Unknown provider"
                         (telemetry-span-text
                          (cadr-telemetry:recorded-telemetry-span-attributes span)))))
        (is (not (search "native-secret" (telemetry-span-text span))))))
    (is (not (search "pi.dev"
                     (uiop:read-file-string
                      (merge-pathnames
                       "src/cadr-telemetry/memory.lisp"
                       (asdf:system-source-directory "cadr-telemetry")))))
        "telemetry must not phone home to pi.dev")))
