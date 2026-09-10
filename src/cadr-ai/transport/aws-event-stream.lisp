(in-package #:cadr-ai)

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
       (read-timeout nil)
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
       (read-timeout nil)
       abort-p
       environment
       on-response)
  (ecase (request-spec-stream-format request)
    (:sse
     (request-sse request consumer
                  :connect-timeout connect-timeout
                  :read-timeout read-timeout
                  :abort-p abort-p
                  :environment environment
                  :on-response on-response))
    (:aws-event-stream
     (request-aws-event-stream
      request consumer
      :connect-timeout connect-timeout
      :read-timeout read-timeout
      :abort-p abort-p
      :environment environment
      :on-response on-response))))
