(in-package #:cadr-ai/tests)
(in-suite cadr-ai-suite)

(defclass delayed-binary-input-stream
    (trivial-gray-streams:fundamental-binary-input-stream)
  ((octets :initarg :octets :reader delayed-stream-octets)
   (position :initform 0 :accessor delayed-stream-position)
   (entered :initarg :entered :reader delayed-stream-entered)
   (release :initarg :release :reader delayed-stream-release)
   (delayed-p :initform nil :accessor delayed-stream-delayed-p)))

(defmethod stream-element-type ((stream delayed-binary-input-stream))
  (declare (ignore stream))
  '(unsigned-byte 8))

(defmethod trivial-gray-streams:stream-read-byte
    ((stream delayed-binary-input-stream))
  (unless (delayed-stream-delayed-p stream)
    (setf (delayed-stream-delayed-p stream) t)
    (sb-thread:signal-semaphore
     (delayed-stream-entered stream))
    (sb-thread:wait-on-semaphore
     (delayed-stream-release stream)))
  (let ((position (delayed-stream-position stream))
        (octets (delayed-stream-octets stream)))
    (if (= position (length octets))
        :eof
        (prog1 (aref octets position)
          (incf (delayed-stream-position stream))))))

(defun read-http-request-headers (stream)
  (loop with suffix = 0
        for byte = (read-byte stream nil :eof)
        until (eq byte :eof)
        do (setf suffix
                 (logand #xffffffff
                         (logior (ash suffix 8) byte)))
        when (= suffix #x0d0a0d0a)
          return t))

(defun write-http-string (stream text)
  (write-sequence
   (babel:string-to-octets text :encoding :utf-8)
   stream)
  (finish-output stream))

(test sse-request-explicitly-disables-read-timeout
  (multiple-value-bind (provider model)
      (provider-case :anthropic)
    (let* ((request (build-request provider model (sample-context)
                                   :stream-p t
                                   :max-tokens 4096))
           (captured-arguments nil)
           (events nil)
           (entered
             (sb-thread:make-semaphore :count 0))
           (release
             (sb-thread:make-semaphore :count 0))
           (request-error nil)
           (request-function
             (lambda (url &rest arguments)
               (declare (ignore url))
               (setf captured-arguments arguments)
               (values
                (make-instance
                 'delayed-binary-input-stream
                 :entered entered
                 :release release
                 :octets (babel:string-to-octets
                          (format nil "data: {\"ok\":true}~%~%")
                          :encoding :utf-8))
                200
                '(("content-type" . "text/event-stream"))))))
      (let ((thread
              (sb-thread:make-thread
               (lambda ()
                 (let ((*http-request-function*
                         request-function))
                   (handler-case
                       (request-sse
                        request
                        (lambda (event) (push event events))
                        :connect-timeout 1)
                     (error (condition)
                       (setf request-error condition))))))))
        (sb-thread:wait-on-semaphore entered)
        (is (sb-thread:thread-alive-p thread))
        (sb-thread:signal-semaphore release)
        (sb-thread:join-thread thread))
      (is (null request-error))
      (is (not (null (member :read-timeout
                             captured-arguments
                             :test #'eq))))
      (is (null (getf captured-arguments :read-timeout)))
      (is (eql t (getf captured-arguments :want-stream)))
      (is (= 1 (length events)))
      (is (string= "{\"ok\":true}" (sse-event-data (first events)))))))

(test native-http-consumes-a-real-streaming-http-socket
  (let* ((listener
           (usocket:socket-listen
            "127.0.0.1" 0
            :reuse-address t
            :element-type '(unsigned-byte 8)))
         (port (usocket:get-local-port listener))
         (events nil)
         (release-second-event
           (sb-thread:make-semaphore :count 0))
         (server-error nil)
         (server
           (bordeaux-threads:make-thread
            (lambda ()
              (handler-case
                  (let ((client
                          (usocket:socket-accept
                           listener
                           :element-type '(unsigned-byte 8))))
                    (unwind-protect
                         (let ((stream
                                 (usocket:socket-stream client)))
                           (read-http-request-headers stream)
                           (write-http-string
                            stream
                            (format
                             nil
                             "HTTP/1.1 200 OK~C~CContent-Type: text/event-stream~C~CConnection: close~C~C~C~C"
                             #\Return #\Linefeed
                             #\Return #\Linefeed
                             #\Return #\Linefeed
                             #\Return #\Linefeed))
                           (write-http-string
                            stream
                            (format nil
                                    "data: {\"part\":1}~C~C~C~C"
                                    #\Return #\Linefeed
                                    #\Return #\Linefeed))
                           (sb-thread:wait-on-semaphore
                            release-second-event)
                           (write-http-string
                            stream
                            (format nil
                                    "data: {\"part\":2}~C~C~C~C"
                                    #\Return #\Linefeed
                                    #\Return #\Linefeed)))
                      (when client
                        (usocket:socket-close client))))
                (error (condition)
                  (setf server-error condition))))
            :name "cadr-test-sse-http-server")))
    (unwind-protect
         (let* ((*http-request-function*
                  #'cadr-ai::native-http-request)
                (request
                  (cadr-ai::make-request-spec
                   :url (format nil "http://127.0.0.1:~D/stream"
                                port)
                   :method :post
                   :payload (cadr-ai::json-object)
                   :stream-p t
                   :provider :anthropic)))
           (request-sse
            request
            (lambda (event)
              (push event events)
              (when (string= "{\"part\":1}"
                             (sse-event-data event))
                (sb-thread:signal-semaphore
                 release-second-event)))
            :connect-timeout 1)
           (bordeaux-threads:join-thread server)
           (when server-error
             (error server-error))
           (is (equal
                '("{\"part\":1}" "{\"part\":2}")
                (mapcar #'sse-event-data (nreverse events)))))
      (ignore-errors
        (usocket:socket-close listener))
      (when (bordeaux-threads:thread-alive-p server)
        (bordeaux-threads:join-thread server)))))

(test silent-sse-request-aborts-without-waiting-for-the-server
  (let* ((listener
           (usocket:socket-listen
            "127.0.0.1" 0
            :reuse-address t
            :element-type '(unsigned-byte 8)))
         (port (usocket:get-local-port listener))
         (response-seen
           (sb-thread:make-semaphore :count 0))
         (release-server
           (sb-thread:make-semaphore :count 0))
         (client-done
           (sb-thread:make-semaphore :count 0))
         (abort-p nil)
         (message nil)
         (server-error nil)
         (server
           (bordeaux-threads:make-thread
            (lambda ()
              (handler-case
                  (let ((client
                          (usocket:socket-accept
                           listener
                           :element-type '(unsigned-byte 8))))
                    (unwind-protect
                         (let ((stream
                                 (usocket:socket-stream client)))
                           (read-http-request-headers stream)
                           (write-http-string
                            stream
                            (format
                             nil
                             "HTTP/1.1 200 OK~C~CContent-Type: text/event-stream~C~CConnection: close~C~C~C~C"
                             #\Return #\Linefeed
                             #\Return #\Linefeed
                             #\Return #\Linefeed
                             #\Return #\Linefeed))
                           (sb-thread:wait-on-semaphore
                            release-server))
                      (when client
                        (usocket:socket-close client))))
                (error (condition)
                  (setf server-error condition))))
            :name "cadr-test-silent-sse-server"))
         (provider (make-openai-provider :api-key "test"))
         (model
           (make-model
            :id "gpt-test"
            :provider :openai
            :api :openai-responses
            :base-url (format nil "http://127.0.0.1:~D" port)
            :max-tokens 4096))
         (client
           (sb-thread:make-thread
            (lambda ()
              (unwind-protect
                   (let ((*http-request-function*
                           #'cadr-ai::native-http-request))
                     (setf
                      message
                      (stream-chat
                       provider model (sample-context)
                       (lambda (event)
                         (declare (ignore event)))
                       :abort-p (lambda () abort-p)
                       :on-response
                       (lambda (response callback-model)
                         (declare (ignore response callback-model))
                         (sb-thread:signal-semaphore
                          response-seen)))))
                (sb-thread:signal-semaphore client-done)))
            :name "cadr-test-silent-sse-client")))
    (unwind-protect
         (progn
           (is (sb-thread:wait-on-semaphore response-seen :timeout 2))
           (setf abort-p t)
           (let ((aborted-within-bound-p
                   (sb-thread:wait-on-semaphore
                    client-done :timeout 0.5)))
             (is-true aborted-within-bound-p)
             (unless aborted-within-bound-p
               (sb-thread:signal-semaphore release-server)
               (sb-thread:wait-on-semaphore client-done :timeout 2)))
           (is (eq :aborted
                   (assistant-message-stop-reason message))))
      (sb-thread:signal-semaphore release-server)
      (ignore-errors
        (usocket:socket-close listener))
      (when (sb-thread:thread-alive-p client)
        (sb-thread:join-thread client))
      (when (bordeaux-threads:thread-alive-p server)
        (bordeaux-threads:join-thread server))
      (when server-error
        (error server-error)))))

(test socket-timeouts-remain-distinct-retryable-transport-errors
  (multiple-value-bind (provider model)
      (provider-case :anthropic)
    (let ((request
            (build-request
             provider model (sample-context)
             :stream-p nil :max-tokens 4096)))
      (let ((*http-request-function*
              (lambda (url &rest arguments)
                (declare (ignore url arguments))
                (error 'cadr-ai::native-http-timeout))))
        (handler-case
            (progn
              (cadr-ai::request-json request)
              (fail "Expected timeout-error"))
          (cadr-ai:timeout-error (condition)
            (is (cadr-ai:cadr-error-retryable-p condition))))))))

(test native-http-body-decodes-chunked-framing
  (let* ((source
           (flexi-streams:make-in-memory-input-stream
            (babel:string-to-octets
             (format nil
                     "5~C~Chello~C~C6~C~C world~C~C0~C~CX-Test: ok~C~C~C~C"
                     #\Return #\Linefeed
                     #\Return #\Linefeed
                     #\Return #\Linefeed
                     #\Return #\Linefeed
                     #\Return #\Linefeed
                     #\Return #\Linefeed
                     #\Return #\Linefeed)
             :encoding :utf-8)))
         (headers
           (cadr-ai::json-object
            "transfer-encoding" "chunked"))
         (body
           (cadr-ai::make-http-body-stream
            source headers)))
    (unwind-protect
         (is (string=
              "hello world"
              (cadr-ai::slurp-stream body)))
      (close body))))

(test native-http-body-honors-length-close-and-truncation
  (flet ((source (text)
           (flexi-streams:make-in-memory-input-stream
            (babel:string-to-octets
             text :encoding :utf-8))))
    (let ((body
            (cadr-ai::make-http-body-stream
             (source "helloignored")
             (cadr-ai::json-object
              "content-length" "5"))))
      (unwind-protect
           (is (string=
                "hello"
                (cadr-ai::slurp-stream body)))
        (close body)))
    (let ((body
            (cadr-ai::make-http-body-stream
             (source "until-close")
             (cadr-ai::json-object))))
      (unwind-protect
           (is (string=
                "until-close"
                (cadr-ai::slurp-stream body)))
        (close body)))
    (let ((body
            (cadr-ai::make-http-body-stream
             (source "short")
             (cadr-ai::json-object
              "content-length" "6"))))
      (unwind-protect
           (signals error
             (cadr-ai::slurp-stream body))
        (close body)))
    (signals error
      (cadr-ai::make-http-body-stream
       (source "")
       (cadr-ai::json-object
        "content-length" "-1")))))

(test native-http-host-header-keeps-non-default-port
  (let* ((parsed
           (cadr-ai::parse-http-url
            "http://127.0.0.1:11434/v1/chat/completions"))
         (headers
           (cadr-ai::request-headers parsed nil 0)))
    (is
     (string=
      "127.0.0.1:11434"
      (cdr
       (assoc "Host" headers
              :test #'string-equal)))))
  (let* ((parsed
           (cadr-ai::parse-http-url
            "https://api.deepseek.com/v1/chat/completions"))
         (headers
           (cadr-ai::request-headers parsed nil 0)))
    (is
     (string=
      "api.deepseek.com"
      (cdr
       (assoc "Host" headers
              :test #'string-equal))))
    (is
     (string=
      (format nil "cadr/~A" (cadr-ai::cadr-version))
      (cdr
       (assoc "User-Agent" headers
              :test #'string-equal))))))
