(in-package #:pi-ai/tests)
(in-suite pi-ai-suite)

(defclass delayed-binary-input-stream
    (trivial-gray-streams:fundamental-binary-input-stream)
  ((octets :initarg :octets :reader delayed-stream-octets)
   (position :initform 0 :accessor delayed-stream-position)
   (delay :initarg :delay :reader delayed-stream-delay)
   (delayed-p :initform nil :accessor delayed-stream-delayed-p)))

(defmethod stream-element-type ((stream delayed-binary-input-stream))
  (declare (ignore stream))
  '(unsigned-byte 8))

(defmethod trivial-gray-streams:stream-read-byte
    ((stream delayed-binary-input-stream))
  (unless (delayed-stream-delayed-p stream)
    (setf (delayed-stream-delayed-p stream) t)
    (sleep (delayed-stream-delay stream)))
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
           (events nil))
      (let ((*http-request-function*
              (lambda (url &rest arguments)
                (declare (ignore url))
                (setf captured-arguments arguments)
                (values
                 (make-instance
                  'delayed-binary-input-stream
                  :delay 0.08
                  :octets (babel:string-to-octets
                           (format nil "data: {\"ok\":true}~%~%")
                           :encoding :utf-8))
                 200
                 '(("content-type" . "text/event-stream"))))))
      (request-sse request (lambda (event) (push event events))
                   :connect-timeout 1)
      (is (not (null (member :read-timeout
                             captured-arguments
                             :test #'eq))))
      (is (null (getf captured-arguments :read-timeout)))
      (is (eql t (getf captured-arguments :want-stream)))
      (is (= 1 (length events)))
      (is (string= "{\"ok\":true}" (sse-event-data (first events))))))))

(test native-http-consumes-a-real-streaming-http-socket
  (let* ((listener
           (usocket:socket-listen
            "127.0.0.1" 0
            :reuse-address t
            :element-type '(unsigned-byte 8)))
         (port (usocket:get-local-port listener))
         (events nil)
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
                           (sleep 0.05)
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
            :name "pi-test-sse-http-server")))
    (unwind-protect
         (let* ((*http-request-function*
                  #'pi-ai::native-http-request)
                (request
                  (pi-ai::make-request-spec
                   :url (format nil "http://127.0.0.1:~D/stream"
                                port)
                   :method :post
                   :payload (pi-ai::json-object)
                   :stream-p t
                   :provider :anthropic)))
           (request-sse
            request
            (lambda (event) (push event events))
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
                (error 'pi-ai::native-http-timeout))))
        (handler-case
            (progn
              (pi-ai::request-json request)
              (fail "Expected timeout-error"))
          (pi-ai:timeout-error (condition)
            (is (pi-ai:pi-error-retryable-p condition))))))))

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
           (pi-ai::json-object
            "transfer-encoding" "chunked"))
         (body
           (pi-ai::make-http-body-stream
            source headers)))
    (unwind-protect
         (is (string=
              "hello world"
              (pi-ai::slurp-stream body)))
      (close body))))

(test native-http-body-honors-length-close-and-truncation
  (flet ((source (text)
           (flexi-streams:make-in-memory-input-stream
            (babel:string-to-octets
             text :encoding :utf-8))))
    (let ((body
            (pi-ai::make-http-body-stream
             (source "helloignored")
             (pi-ai::json-object
              "content-length" "5"))))
      (unwind-protect
           (is (string=
                "hello"
                (pi-ai::slurp-stream body)))
        (close body)))
    (let ((body
            (pi-ai::make-http-body-stream
             (source "until-close")
             (pi-ai::json-object))))
      (unwind-protect
           (is (string=
                "until-close"
                (pi-ai::slurp-stream body)))
        (close body)))
    (let ((body
            (pi-ai::make-http-body-stream
             (source "short")
             (pi-ai::json-object
              "content-length" "6"))))
      (unwind-protect
           (signals error
             (pi-ai::slurp-stream body))
        (close body)))
    (signals error
      (pi-ai::make-http-body-stream
       (source "")
       (pi-ai::json-object
        "content-length" "-1")))))

(test native-http-host-header-keeps-non-default-port
  (let* ((parsed
           (pi-ai::parse-http-url
            "http://127.0.0.1:11434/v1/chat/completions"))
         (headers
           (pi-ai::request-headers parsed nil 0)))
    (is
     (string=
      "127.0.0.1:11434"
      (cdr
       (assoc "Host" headers
              :test #'string-equal)))))
  (let* ((parsed
           (pi-ai::parse-http-url
            "https://api.deepseek.com/v1/chat/completions"))
         (headers
           (pi-ai::request-headers parsed nil 0)))
    (is
     (string=
      "api.deepseek.com"
      (cdr
       (assoc "Host" headers
              :test #'string-equal))))))
