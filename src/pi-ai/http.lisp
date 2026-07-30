(in-package #:pi-ai)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-bsd-sockets))

(defstruct request-spec
  (url "" :type string)
  (method :post :type symbol)
  (headers nil :type list)
  (payload (make-hash-table :test #'equal) :type hash-table)
  (stream-p nil :type boolean)
  (provider nil :type symbol))

(define-condition native-http-timeout (error) ())

(defstruct parsed-url
  scheme
  host
  port
  path)

(defun parse-http-url (url)
  (let* ((scheme-end (search "://" url))
         (scheme
           (and scheme-end
                (string-downcase
                 (subseq url 0 scheme-end)))))
    (unless (member scheme '("http" "https")
                    :test #'string=)
      (error "Unsupported URL scheme: ~A" url))
    (let* ((authority-start (+ scheme-end 3))
           (path-start
             (or (position #\/ url
                           :start authority-start)
                 (length url)))
           (authority
             (subseq url authority-start path-start))
           (colon
             (position #\: authority :from-end t))
           (host
             (if colon
                 (subseq authority 0 colon)
                 authority))
           (port
             (if colon
                 (or
                  (parse-integer
                   authority
                   :start (1+ colon)
                   :junk-allowed nil)
                  (error "Invalid URL port"))
                 (if (string= scheme "https")
                     443
                     80)))
           (path
             (if (= path-start (length url))
                 "/"
                 (subseq url path-start))))
      (when (zerop (length host))
        (error "URL host is empty"))
      (make-parsed-url
       :scheme scheme
       :host host
       :port port
       :path path))))

(defun normalize-response-body (body)
  (etypecase body
    (string body)
    ((vector (unsigned-byte 8))
     (utf8-string body))))

(defun header-value (headers name)
  (cond
    ((hash-table-p headers)
     (or (gethash name headers)
         (gethash (string-downcase name) headers)
         (loop for key being the hash-keys of headers
                 using (hash-value value)
               when (string-equal key name)
                 return value)))
    ((listp headers)
     (cdr (assoc name headers
                 :test #'string-equal)))
    (t nil)))

(defun header-present-p (headers name)
  (not (null
        (find name headers
              :key #'car
              :test #'string-equal))))

(defparameter +sensitive-request-header-names+
  '("authorization"
    "x-api-key"
    "x-goog-api-key"))

(defun request-secrets (request)
  (loop for (name . value) in
        (request-spec-headers request)
        when
        (and
         (member name
                 +sensitive-request-header-names+
                 :test #'string-equal)
         (stringp value)
         (plusp (length value)))
          append
          (let ((space
                  (position #\Space value)))
            (if (and space
                     (< (1+ space)
                        (length value)))
                (list value
                      (subseq value (1+ space)))
                (list value)))))

(defun redact-request-text (request text)
  (redact-secrets
   text
   (request-secrets request)))

(defun read-http-line (stream)
  (let ((octets
          (make-array
           64
           :element-type '(unsigned-byte 8)
           :adjustable t
           :fill-pointer 0)))
    (loop for byte = (read-byte stream nil :eof)
          do
          (when (eq byte :eof)
            (if (zerop (length octets))
                (return-from read-http-line nil)
                (return)))
          (when (= byte 10)
            (return))
          (unless (= byte 13)
            (vector-push-extend byte octets)))
    (sb-ext:octets-to-string
     octets :external-format :latin-1)))

(defun parse-response-headers (stream)
  (let ((status-line (read-http-line stream)))
    (unless status-line
      (error "HTTP server closed before status line"))
    (let* ((first-space
             (position #\Space status-line))
           (status
             (and first-space
                  (parse-integer
                   status-line
                   :start (1+ first-space)
                   :junk-allowed t)))
           (headers
             (make-hash-table :test #'equalp)))
      (unless status
        (error "Invalid HTTP status line: ~A"
               status-line))
      (loop for line = (read-http-line stream)
            until (or (null line)
                      (zerop (length line)))
            do
            (let ((colon (position #\: line)))
              (unless colon
                (error "Invalid HTTP header: ~A"
                       line))
              (let* ((name
                       (string-downcase
                        (subseq line 0 colon)))
                     (value
                       (string-trim
                        '(#\Space #\Tab)
                        (subseq line (1+ colon))))
                     (old (gethash name headers)))
                (setf
                 (gethash name headers)
                 (if old
                     (format nil "~A, ~A"
                             old value)
                     value)))))
      (values status headers))))

(defclass http-body-stream
    (sb-gray:fundamental-binary-input-stream)
  ((source :initarg :source
           :reader http-body-source)
   (mode :initarg :mode
         :reader http-body-mode)
   (remaining :initarg :remaining
              :accessor http-body-remaining)
   (chunk-remaining :initform 0
                    :accessor http-chunk-remaining)
   (finished-p :initform nil
               :accessor http-body-finished-p)))

(defmethod stream-element-type
    ((stream http-body-stream))
  (declare (ignore stream))
  '(unsigned-byte 8))

(defun consume-http-trailers (source)
  (loop for line = (read-http-line source)
        until (or (null line)
                  (zerop (length line)))))

(defun begin-next-http-chunk (stream)
  (let* ((line
           (or (read-http-line
                (http-body-source stream))
               (error "Truncated chunk header")))
         (semicolon (position #\; line))
         (size
           (parse-integer
            line
            :end (or semicolon
                     (length line))
            :radix 16
            :junk-allowed nil)))
    (if (zerop size)
        (progn
          (consume-http-trailers
           (http-body-source stream))
          (setf (http-body-finished-p stream) t)
          nil)
        (progn
          (setf
           (http-chunk-remaining stream)
           size)
          t))))

(defun finish-http-chunk (stream)
  (let ((source (http-body-source stream)))
    (unless (and (= (read-byte source nil -1) 13)
                 (= (read-byte source nil -1) 10))
      (error "Invalid chunk terminator"))))

(defmethod sb-gray:stream-read-byte
    ((stream http-body-stream))
  (when (http-body-finished-p stream)
    (return-from sb-gray:stream-read-byte :eof))
  (case (http-body-mode stream)
    (:length
     (when (zerop
            (http-body-remaining stream))
       (setf (http-body-finished-p stream) t)
       (return-from sb-gray:stream-read-byte
         :eof))
     (let ((byte
             (read-byte
              (http-body-source stream)
              nil :eof)))
       (when (eq byte :eof)
         (error "Truncated HTTP body"))
       (decf (http-body-remaining stream))
       byte))
    (:chunked
     (when (zerop
            (http-chunk-remaining stream))
       (unless (begin-next-http-chunk stream)
         (return-from sb-gray:stream-read-byte
           :eof)))
     (let ((byte
             (read-byte
              (http-body-source stream)
              nil :eof)))
       (when (eq byte :eof)
         (error "Truncated chunk"))
       (decf (http-chunk-remaining stream))
       (when (zerop
              (http-chunk-remaining stream))
         (finish-http-chunk stream))
       byte))
    (otherwise
     (let ((byte
             (read-byte
              (http-body-source stream)
              nil :eof)))
       (when (eq byte :eof)
         (setf
          (http-body-finished-p stream)
          t))
       byte))))

(defmethod close ((stream http-body-stream)
                  &key abort)
  (close (http-body-source stream)
         :abort abort))

(defun parse-content-length (value)
  (unless (and (plusp (length value))
               (every #'digit-char-p value))
    (error "Invalid Content-Length: ~S" value))
  (parse-integer value))

(defun make-http-body-stream
    (source headers)
  (let ((transfer
          (header-value headers
                        "transfer-encoding"))
        (length
          (header-value headers
                        "content-length")))
    (cond
      ((and transfer
            (search "chunked"
                    transfer
                    :test #'char-equal))
       (make-instance
        'http-body-stream
        :source source
        :mode :chunked
        :remaining 0))
      (length
       (make-instance
        'http-body-stream
        :source source
        :mode :length
        :remaining
        (parse-content-length length)))
      (t
       (make-instance
        'http-body-stream
        :source source
        :mode :close
        :remaining 0)))))

(defun connect-http-stream
    (parsed connect-timeout read-timeout)
  (let* ((host
           (parsed-url-host parsed))
         (entry
           (sb-bsd-sockets:get-host-by-name host))
         (address
           (sb-bsd-sockets:host-ent-address
            entry))
         (socket
           (make-instance
            'sb-bsd-sockets:inet-socket
            :type :stream
            :protocol :tcp)))
    (handler-case
        (progn
          (if connect-timeout
              (sb-sys:with-deadline
                  (:seconds connect-timeout)
                (sb-bsd-sockets:socket-connect
                 socket address
                 (parsed-url-port parsed)))
              (sb-bsd-sockets:socket-connect
               socket address
               (parsed-url-port parsed)))
          (let ((plain
                  (sb-bsd-sockets:socket-make-stream
                   socket
                   :input t :output t
                   :element-type
                   '(unsigned-byte 8)
                   :buffering :none
                   :timeout read-timeout)))
            (if (string=
                 "https"
                 (parsed-url-scheme parsed))
                (cl+ssl:make-ssl-client-stream
                 plain
                 :hostname host
                 :verify :required)
                plain)))
      (sb-sys:io-timeout ()
        (ignore-errors
          (sb-bsd-sockets:socket-close
           socket))
        (error 'native-http-timeout))
      (error (condition)
        (ignore-errors
          (sb-bsd-sockets:socket-close
           socket))
        (error condition)))))

(defun request-headers
    (parsed headers content-length)
  (let ((result (copy-list headers)))
    (unless (header-present-p result "host")
      (push
       (cons "Host"
             (if
                 (or
                  (and
                   (string= "http"
                            (parsed-url-scheme parsed))
                   (= 80 (parsed-url-port parsed)))
                  (and
                   (string= "https"
                            (parsed-url-scheme parsed))
                   (= 443 (parsed-url-port parsed))))
                 (parsed-url-host parsed)
                 (format nil "~A:~D"
                         (parsed-url-host parsed)
                         (parsed-url-port parsed))))
       result))
    (unless (header-present-p result
                              "content-length")
      (push
       (cons "Content-Length"
             (princ-to-string
              content-length))
       result))
    (unless (header-present-p result "connection")
      (push '("Connection" . "close")
            result))
    (unless (header-present-p result "user-agent")
      (push '("User-Agent" . "pi-cl/0.1.0")
            result))
    result))

(defun write-http-request
    (stream parsed method headers content)
  (let* ((body (utf8-octets (or content "")))
         (resolved
           (request-headers
            parsed headers (length body)))
         (head
           (with-output-to-string (output)
             (format output
                     "~A ~A HTTP/1.1~C~C"
                     (string-upcase
                      (symbol-name method))
                     (parsed-url-path parsed)
                     #\Return #\Linefeed)
             (dolist (header resolved)
               (format output
                       "~A: ~A~C~C"
                       (car header)
                       (cdr header)
                       #\Return #\Linefeed))
             (format output "~C~C"
                     #\Return #\Linefeed))))
    (write-sequence (utf8-octets head)
                    stream)
    (write-sequence body stream)
    (finish-output stream)))

(defun slurp-stream-octets (stream)
  (let ((octets
          (make-array
           1024
           :element-type '(unsigned-byte 8)
           :adjustable t
           :fill-pointer 0)))
    (loop for byte = (read-byte stream nil :eof)
          until (eq byte :eof)
          do (vector-push-extend byte octets))
    octets))

(defun native-http-request
    (url &key
           (method :get)
           headers
           content
           (connect-timeout 10)
           (read-timeout 60)
           want-stream
           force-string
           force-binary)
  (declare (ignore force-binary))
  (let* ((parsed (parse-http-url url))
         (stream
           (connect-http-stream
            parsed connect-timeout
            read-timeout)))
    (handler-case
        (progn
          (write-http-request
           stream parsed method headers content)
          (multiple-value-bind (status response-headers)
              (parse-response-headers stream)
            (let ((body
                    (make-http-body-stream
                     stream response-headers)))
              (if want-stream
                  (values body status
                          response-headers)
                  (unwind-protect
                       (let ((octets
                               (slurp-stream-octets
                                body)))
                         (values
                          (if force-string
                              (utf8-string octets)
                              octets)
                          status
                          response-headers))
                    (close body))))))
      (error (condition)
        (when (open-stream-p stream)
          (ignore-errors (close stream
                                :abort t)))
        (error condition)))))

(unless *http-request-function*
  (setf *http-request-function*
        #'native-http-request))

(defun signal-api-error (request body status headers)
  (let* ((retry-after (header-value headers "retry-after"))
         (retryable-p (or (= status 429)
                          (member status
                                  '(500 502 503 504)))))
    (error 'api-error
           :provider (request-spec-provider request)
           :status status
           :retry-after retry-after
           :retryable-p retryable-p
           :message
           (redact-request-text
            request
            (response-error-message body)))))

(defun slurp-stream (stream)
  (if (binary-stream-p stream)
      (utf8-string
       (slurp-stream-octets stream))
      (with-output-to-string (output)
        (loop for character =
              (read-char stream nil :eof)
              until (eq character :eof)
              do (write-char character output)))))

(defun invoke-http-request (request &rest options)
  (handler-case
      (apply *http-request-function*
             (request-spec-url request)
             :method (request-spec-method request)
             :headers (request-spec-headers request)
             :content
             (stringify-json
              (request-spec-payload request))
             options)
    (api-error (condition)
      (error condition))
    (native-http-timeout (cause)
      (error
       'timeout-error
       :message
       (format nil
               "HTTP request timed out: ~A"
               cause)
       :cause cause
       :retryable-p t))
    (sb-sys:io-timeout (cause)
      (error
       'timeout-error
       :message
       (format nil
               "HTTP request timed out: ~A"
               cause)
       :cause cause
       :retryable-p t))
    (sb-bsd-sockets:operation-timeout-error
        (cause)
      (error
       'timeout-error
       :message
       (format nil
               "HTTP request timed out: ~A"
               cause)
       :cause cause
       :retryable-p t))
    (error (cause)
      (error 'network-error
             :message
             (format nil
                     "HTTP request failed: ~A"
                     (redact-request-text
                      request
                      (princ-to-string cause)))
             :cause cause
             :retryable-p t))))

(defun request-json
    (request &key
               (connect-timeout 10)
               (read-timeout 60))
  (multiple-value-bind (body status headers)
      (invoke-http-request
       request
       :connect-timeout connect-timeout
       :read-timeout read-timeout
       :want-stream nil
       :force-string t)
    (let ((text (normalize-response-body body)))
      (unless (<= 200 status 299)
        (signal-api-error request text
                          status headers))
      (values
       (handler-case
           (parse-json text)
         (sse-protocol-error (cause)
           (error
            'transport-error
            :message
            (format nil
                    "Invalid JSON response: ~A"
                    cause)
            :cause cause)))
       status headers))))

(defun request-sse
    (request consumer
     &key (connect-timeout 10))
  (multiple-value-bind (body status headers)
      (invoke-http-request
       request
       :connect-timeout connect-timeout
       ;; SSE may remain silent during model thinking.
       :read-timeout nil
       :want-stream t
       :force-binary t)
    (unwind-protect
         (progn
           (unless (<= 200 status 299)
             (signal-api-error
              request (slurp-stream body)
              status headers))
           (read-sse-stream body consumer)
           (values status headers))
      (when (open-stream-p body)
        (close body)))))
