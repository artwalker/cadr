(in-package #:cadr-ai)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-bsd-sockets))

(defstruct request-spec
  (url "" :type string)
  (method :post :type symbol)
  (headers nil :type list)
  (payload (make-hash-table :test #'equal) :type hash-table)
  (raw-body nil :type (or null string
                          (simple-array (unsigned-byte 8) (*))))
  (stream-p nil :type boolean)
  (stream-format :sse :type symbol)
  (provider nil :type symbol))

(define-condition native-http-timeout (error) ())

(defparameter *native-http-abort-p* nil)

(defun signal-http-request-aborted ()
  (error 'request-aborted :message "Request was aborted"))

(defun http-abort-requested-p (abort-p)
  (and abort-p
       (not (null (ignore-errors (funcall abort-p))))))

(defun signal-native-http-network-error (cause)
  (error 'network-error
         :message "fetch failed"
         :cause cause
         :retryable-p t))

(defun call-with-abortable-stream-operation
    (stream abort-p function &optional abort-function)
  (if (null abort-p)
      (funcall function)
      (let ((finished
              (sb-thread:make-semaphore :count 0))
            (aborted-p nil)
            (watcher nil)
            (operation-thread sb-thread:*current-thread*))
        (when (funcall abort-p)
          (signal-http-request-aborted))
        (setf
         watcher
         (sb-thread:make-thread
          (lambda ()
            (loop
              (when (funcall abort-p)
                (setf aborted-p t)
                (ignore-errors
                  (if abort-function
                      (funcall abort-function)
                      (close stream :abort t)))
                ;; Closing a socket does not reliably wake SBCL while cl+ssl is
                ;; blocked inside SSL_connect. Interrupt the Lisp operation as
                ;; well so an abort cannot wait for the TLS peer to respond.
                (unless (sb-thread:try-semaphore finished)
                  (sb-thread:interrupt-thread
                   operation-thread
                   #'signal-http-request-aborted))
                (return))
              (when
                  (sb-thread:wait-on-semaphore
                   finished :timeout 0.005)
                (return))))
          :name "cadr-http-abort-watcher"))
        (unwind-protect
             (handler-case
                 (multiple-value-prog1
                     (funcall function)
                   (when (or aborted-p
                             (funcall abort-p))
                     (signal-http-request-aborted)))
               (request-aborted (condition)
                 (error condition))
               (error (condition)
                 (if (or aborted-p
                         (funcall abort-p))
                     (signal-http-request-aborted)
                     (error condition))))
          (sb-thread:signal-semaphore finished)
          (sb-thread:join-thread watcher)))))

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
               :accessor http-body-finished-p)
   (abort-function :initarg :abort-function
                   :initform nil
                   :reader http-body-abort-function)))

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

(defmethod sb-gray:stream-read-byte :around
    ((stream http-body-stream))
  (handler-case
      (call-next-method)
    (transport-error (condition)
      (error condition))
    (error (cause)
      (signal-native-http-network-error cause))))

(defmethod close ((stream http-body-stream)
                  &key abort)
  (close (http-body-source stream)
         :abort abort))

(defun close-http-body-safely (body abort-p)
  (when (open-stream-p body)
    (handler-case
        (close body
               :abort
               (http-abort-requested-p abort-p))
      (error (cause)
        (ignore-errors (close body :abort t))
        (unless (http-abort-requested-p abort-p)
          (signal-native-http-network-error cause))))))

(defun parse-content-length (value)
  (unless (and (plusp (length value))
               (every #'digit-char-p value))
    (error "Invalid Content-Length: ~S" value))
  (parse-integer value))

(defun make-http-body-stream
    (source headers &optional abort-function)
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
        :remaining 0
        :abort-function abort-function))
      (length
       (make-instance
        'http-body-stream
        :source source
        :mode :length
        :remaining
        (parse-content-length length)
        :abort-function abort-function))
      (t
       (make-instance
        'http-body-stream
        :source source
        :mode :close
        :remaining 0
        :abort-function abort-function)))))

(defun connect-http-stream
    (parsed connect-timeout read-timeout &optional abort-p)
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
        (call-with-abortable-stream-operation
         nil abort-p
         (lambda ()
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
             (values
              (if (string=
                   "https"
                   (parsed-url-scheme parsed))
                  (cl+ssl:make-ssl-client-stream
                   plain
                   :hostname host
                   :verify :required)
                  plain)
              socket)))
         (lambda ()
           (ignore-errors
             (sb-bsd-sockets:socket-shutdown
              socket :direction :io))
           (ignore-errors
             (sb-bsd-sockets:socket-close socket))))
      (sb-sys:io-timeout ()
        (ignore-errors
          (sb-bsd-sockets:socket-close
           socket))
        (error 'native-http-timeout))
      (transport-error (condition)
        (ignore-errors
          (sb-bsd-sockets:socket-close socket))
        (error condition))
      (error (condition)
        (ignore-errors
          (sb-bsd-sockets:socket-close
           socket))
        (signal-native-http-network-error
         condition)))))

(defun parsed-url-authority (parsed)
  (if (or (and (string= "http" (parsed-url-scheme parsed))
               (= 80 (parsed-url-port parsed)))
          (and (string= "https" (parsed-url-scheme parsed))
               (= 443 (parsed-url-port parsed))))
      (parsed-url-host parsed)
      (format nil "~A:~D"
              (parsed-url-host parsed)
              (parsed-url-port parsed))))

(defun write-proxy-connect-request (stream target)
  (let ((authority (parsed-url-authority target)))
    (write-sequence
     (utf8-octets
      (format nil
              "CONNECT ~A HTTP/1.1~C~CHost: ~A~C~CProxy-Connection: keep-alive~C~C~C~C"
              authority #\Return #\Linefeed
              authority #\Return #\Linefeed
              #\Return #\Linefeed
              #\Return #\Linefeed))
     stream)
    (finish-output stream)))

(defun connect-native-http-stream
    (target url proxy-url connect-timeout read-timeout abort-p)
  (if (null proxy-url)
      (multiple-value-bind (stream socket)
          (connect-http-stream
           target connect-timeout read-timeout abort-p)
        (values stream socket (parsed-url-path target)))
      (let ((proxy (parse-http-url proxy-url)))
        (multiple-value-bind (stream socket)
            (connect-http-stream
             proxy connect-timeout read-timeout abort-p)
          (if (string= "https" (parsed-url-scheme target))
              (handler-case
                  (progn
                    (call-with-abortable-stream-operation
                     stream abort-p
                     (lambda ()
                       (write-proxy-connect-request stream target)
                       (multiple-value-bind (status headers)
                           (parse-response-headers stream)
                         (declare (ignore headers))
                         (unless (<= 200 status 299)
                           (error "HTTP proxy CONNECT failed with status ~D"
                                  status)))))
                    (values
                     (call-with-abortable-stream-operation
                      stream abort-p
                      (lambda ()
                        (cl+ssl:make-ssl-client-stream
                         stream
                         :hostname (parsed-url-host target)
                         :verify :required)))
                     socket
                     (parsed-url-path target)))
                (error (condition)
                  (ignore-errors (close stream :abort t))
                  (ignore-errors
                    (sb-bsd-sockets:socket-close socket))
                  (if (typep condition 'transport-error)
                      (error condition)
                      (signal-native-http-network-error condition))))
              (values stream socket url))))))

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
      (push (cons "User-Agent"
                  (format nil "cadr/~A"
                          (cadr-version)))
            result))
    result))

(defun write-http-request
    (stream parsed method headers content &optional request-target)
  (let* ((body (if (typep content '(array (unsigned-byte 8) (*)))
                   (coerce content '(simple-array (unsigned-byte 8) (*)))
                   (utf8-octets (or content ""))))
         (resolved
           (request-headers
            parsed headers (length body)))
         (head
           (with-output-to-string (output)
             (format output
                     "~A ~A HTTP/1.1~C~C"
                     (string-upcase
                      (symbol-name method))
                     (or request-target (parsed-url-path parsed))
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
           force-binary
           environment)
  (declare (ignore force-binary))
  (let* ((parsed (parse-http-url url))
         (proxy-url
           (resolve-http-proxy-url-for-target url environment)))
    (multiple-value-bind (stream socket request-target)
        (connect-native-http-stream
         parsed url proxy-url connect-timeout
         read-timeout *native-http-abort-p*)
      (flet ((abort-connection ()
               (sb-bsd-sockets:socket-shutdown
                socket :direction :io)))
        (handler-case
            (call-with-abortable-stream-operation
             stream *native-http-abort-p*
             (lambda ()
               (write-http-request
                stream parsed method headers content
                request-target)
               (multiple-value-bind (status response-headers)
                   (parse-response-headers stream)
                 (let ((body
                         (make-http-body-stream
                          stream response-headers
                          #'abort-connection)))
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
             #'abort-connection)
          (error (condition)
            (when (open-stream-p stream)
              (ignore-errors
                (close stream :abort t)))
            (if (typep condition 'transport-error)
                (error condition)
                (signal-native-http-network-error
                 condition))))))))

(unless *http-request-function*
  (setf *http-request-function*
        #'native-http-request))

(defun signal-api-error (request body status headers)
  (let* ((retry-after (header-value headers "retry-after"))
         (error-code
           (ignore-errors
             (let* ((object (parse-json body))
                    (nested (json-get object "error"))
                    (value
                      (or (json-get object "__type")
                          (json-get object "code")
                          (and (hash-table-p nested)
                               (or
                                (json-get nested "code")
                                (json-get nested "type"))))))
               (and (stringp value) value))))
         (retryable-p (or (= status 429)
                          (member status
                                  '(500 502 503 504)))))
    (error 'api-error
           :provider (request-spec-provider request)
           :status status
           :code error-code
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
             (or
              (request-spec-raw-body request)
              (stringify-json
               (request-spec-payload request)))
             options)
    (api-error (condition)
      (error condition))
    (request-aborted (condition)
      (error condition))
    (transport-error (condition)
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
      (signal-native-http-network-error cause))))

(defun request-json
    (request &key
               (connect-timeout 10)
               (read-timeout 60)
               abort-p
               environment
               on-response)
  (multiple-value-bind (body status headers)
      (let ((*native-http-abort-p* abort-p))
        (apply #'invoke-http-request
               request
               (append
                (list :connect-timeout connect-timeout
                      :read-timeout read-timeout)
                (when environment (list :environment environment))
                (list :want-stream nil :force-string t))))
    (let ((text (normalize-response-body body)))
      (when on-response
        (funcall on-response status headers))
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
     &key (connect-timeout 10)
       abort-p
       environment
       on-response)
  (multiple-value-bind (body status headers)
      (let ((*native-http-abort-p* abort-p))
        (apply #'invoke-http-request
               request
               (append
                (list :connect-timeout connect-timeout
                      ;; SSE may remain silent during model thinking.
                      :read-timeout nil)
                (when environment (list :environment environment))
                (list :want-stream t :force-binary t))))
    (unwind-protect
         (progn
           (when on-response
             (funcall on-response status headers))
           (unless (<= 200 status 299)
             (signal-api-error
              request (slurp-stream body)
              status headers))
           (call-with-abortable-stream-operation
            body abort-p
            (lambda ()
              (read-sse-stream body consumer))
            (and (typep body 'http-body-stream)
                 (http-body-abort-function body)))
           (values status headers))
      (when (open-stream-p body)
        (close-http-body-safely body abort-p)))))

(defun read-exact-octets (stream count &optional eof-value)
  (let ((result
          (make-array count
                      :element-type '(unsigned-byte 8))))
    (loop for offset from 0 below count
          for byte = (read-byte stream nil :eof)
          do
          (when (eq byte :eof)
            (if (and eof-value (zerop offset))
                (return-from read-exact-octets eof-value)
                (error 'sse-protocol-error
                       :message "Truncated AWS event-stream frame")))
          (setf (aref result offset) byte))
    result))

(defun octets-u16 (octets offset)
  (logior (ash (aref octets offset) 8)
          (aref octets (1+ offset))))

(defun octets-u32 (octets offset)
  (logior
   (ash (aref octets offset) 24)
   (ash (aref octets (+ offset 1)) 16)
   (ash (aref octets (+ offset 2)) 8)
   (aref octets (+ offset 3))))

(defun crc32-octets (octets &optional (end (length octets)))
  (let ((crc #xffffffff))
    (loop for index below end
          do
          (setf crc (logxor crc (aref octets index)))
          (loop repeat 8
                do
            (setf crc
                  (if (oddp crc)
                      (logxor #xedb88320 (ash crc -1))
                      (ash crc -1)))))
    (ldb (byte 32 0) (logxor crc #xffffffff))))

(defun event-stream-header-value
    (octets offset type)
  (case type
    (0 (values t offset))
    (1 (values nil offset))
    (2 (values (aref octets offset) (1+ offset)))
    (3 (values (octets-u16 octets offset) (+ offset 2)))
    (4 (values (octets-u32 octets offset) (+ offset 4)))
    ((6 7)
     (let* ((length (octets-u16 octets offset))
            (start (+ offset 2))
            (end (+ start length))
            (value
              (if (= type 7)
                  (utf8-string (subseq octets start end))
                  (subseq octets start end))))
       (values value end)))
    (otherwise
     (error 'sse-protocol-error
            :message
            (format nil
                    "Unsupported AWS event-stream header type: ~D"
                    type)))))

(defun parse-event-stream-headers (octets)
  (let ((offset 0)
        (headers nil))
    (loop while (< offset (length octets))
          do
          (let* ((name-length (aref octets offset))
                 (name-start (1+ offset))
                 (name-end (+ name-start name-length))
                 (name
                   (utf8-string
                    (subseq octets name-start name-end)))
                 (type (aref octets name-end)))
            (multiple-value-bind (value next)
                (event-stream-header-value
                 octets (1+ name-end) type)
              (push (cons name value) headers)
              (setf offset next))))
    (nreverse headers)))

(defun bedrock-modeled-exception-message (payload code)
  (or
   (ignore-errors
     (let ((object (parse-json payload)))
       (and (hash-table-p object)
            (or (json-get object "message")
                (json-get object "Message")))))
   (and (non-empty-string-p payload) payload)
   code
   "Bedrock exception"))

(defun read-aws-event-stream
    (stream consumer)
  (loop
    for prelude = (read-exact-octets stream 12 :eof)
    until (eq prelude :eof)
    do
    (let* ((total-length (octets-u32 prelude 0))
           (headers-length (octets-u32 prelude 4))
           (prelude-crc (octets-u32 prelude 8)))
      (unless (and (>= total-length 16)
                   (<= headers-length (- total-length 16)))
        (error 'sse-protocol-error
               :message "Invalid AWS event-stream frame length"))
      (unless (= prelude-crc (crc32-octets prelude 8))
        (error 'sse-protocol-error
               :message "Invalid AWS event-stream prelude CRC"))
      (let* ((remainder
               (read-exact-octets stream (- total-length 12)))
             (frame
               (concatenate
                '(vector (unsigned-byte 8))
                prelude remainder))
             (message-crc
               (octets-u32 frame (- total-length 4))))
        (unless (= message-crc
                   (crc32-octets frame (- total-length 4)))
          (error 'sse-protocol-error
                 :message "Invalid AWS event-stream message CRC"))
        (let* ((header-start 12)
               (payload-start (+ header-start headers-length))
               (headers
                 (parse-event-stream-headers
                  (subseq frame header-start payload-start)))
               (payload
                 (utf8-string
                  (subseq frame payload-start (- total-length 4))))
               (message-type
                 (cdr (assoc ":message-type" headers
                             :test #'string=)))
               (event-type
                 (cdr (assoc ":event-type" headers
                             :test #'string=)))
               (exception-type
                 (cdr (assoc ":exception-type" headers
                             :test #'string=)))
               (error-code
                 (cdr (assoc ":error-code" headers
                             :test #'string=)))
               (error-message
                 (cdr (assoc ":error-message" headers
                             :test #'string=))))
          (cond
            ((string= message-type "exception")
             ;; Smithy deserializes modeled exceptions to bare objects.  The
             ;; exception code is no longer observable by the provider catch.
             (error
              'bedrock-stream-exception
              :message
              (bedrock-modeled-exception-message
               payload exception-type)))
            ((string= message-type "error")
             ;; Unmodeled errors retain :error-code as the thrown Error name.
             (error 'api-error
                    :provider :amazon-bedrock
                    :status nil
                    :code error-code
                    :message
                    (or error-message "UnknownError")))
            (t
             (funcall
              consumer
              (make-sse-event
               :event event-type
               :data payload)))))))))

(defun request-aws-event-stream
    (request consumer
     &key (connect-timeout 10)
       abort-p
       environment
       on-response)
  (multiple-value-bind (body status headers)
      (let ((*native-http-abort-p* abort-p))
        (apply #'invoke-http-request
               request
               (append
                (list :connect-timeout connect-timeout :read-timeout nil)
                (when environment (list :environment environment))
                (list :want-stream t :force-binary t))))
    (unwind-protect
         (progn
           (when on-response
             (funcall on-response status headers))
           (unless (<= 200 status 299)
             (signal-api-error
              request (slurp-stream body)
              status headers))
           (call-with-abortable-stream-operation
            body abort-p
            (lambda ()
              (read-aws-event-stream body consumer))
            (and (typep body 'http-body-stream)
                 (http-body-abort-function body)))
           (values status headers))
      (when (open-stream-p body)
        (close-http-body-safely body abort-p)))))

(defun request-provider-events
    (request consumer
     &key (connect-timeout 10)
       abort-p
       environment
       on-response)
  (ecase (request-spec-stream-format request)
    (:sse
     (request-sse request consumer
                  :connect-timeout connect-timeout
                  :abort-p abort-p
                  :environment environment
                  :on-response on-response))
    (:aws-event-stream
     (request-aws-event-stream
      request consumer
      :connect-timeout connect-timeout
      :abort-p abort-p
      :environment environment
      :on-response on-response))))
