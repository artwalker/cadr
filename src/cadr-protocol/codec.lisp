(in-package #:cadr-protocol)

(defun bounded-codec-error-message (condition)
  (let ((message
          (if (typep condition 'error)
              (princ-to-string condition)
              "Unknown codec error")))
    (if (<= (length message) 500)
        message
        (concatenate
         'string (subseq message 0 497) "..."))))

(defun encode-protocol-message
    (value parser kind max-frame-length)
  (funcall parser value)
  (handler-case
      (let* ((maximum
               (resolve-max-frame-length max-frame-length))
             (frame
               (encode-frame
                (encode-cbor
                 value :max-byte-length maximum))))
        (assert-complete-frame
         frame :max-frame-length maximum)
        frame)
    (protocol-validation-error (condition)
      (error condition))
    (error (condition)
      (protocol-fail
       (format nil
               "Unable to encode ~A protocol message: ~A"
               kind
               (bounded-codec-error-message condition))))))

(defun encode-client-message
    (message &key max-frame-length)
  (encode-protocol-message
   message #'parse-client-message "client"
   max-frame-length))

(defun encode-server-message
    (message &key max-frame-length)
  (encode-protocol-message
   message #'parse-server-message "server"
   max-frame-length))

(defstruct (message-decoder
            (:constructor %make-message-decoder
                (frames parser kind max-frame-length)))
  frames
  parser
  kind
  max-frame-length
  (failed-p nil))

(defun make-client-message-decoder
    (&key max-frame-length)
  (let ((maximum
          (resolve-max-frame-length max-frame-length)))
    (%make-message-decoder
     (make-frame-decoder :max-frame-length maximum)
     #'parse-client-message
     "client"
     maximum)))

(defun make-server-message-decoder
    (&key max-frame-length)
  (let ((maximum
          (resolve-max-frame-length max-frame-length)))
    (%make-message-decoder
     (make-frame-decoder :max-frame-length maximum)
     #'parse-server-message
     "server"
     maximum)))

(defun decoder-failed (decoder)
  (protocol-fail
   (format nil "~A message decoder has failed"
           (message-decoder-kind decoder))))

(defun message-decoder-push (decoder chunk)
  (when (message-decoder-failed-p decoder)
    (decoder-failed decoder))
  (handler-case
      (mapcar
       (lambda (frame)
         (funcall
          (message-decoder-parser decoder)
          (decode-cbor
           frame
           :max-byte-length
           (message-decoder-max-frame-length decoder))))
       (frame-decoder-push
        (message-decoder-frames decoder)
        chunk))
    (error (condition)
      (setf (message-decoder-failed-p decoder) t)
      (if (typep condition 'protocol-validation-error)
          (error condition)
          (protocol-fail
           (format nil
                   "Invalid ~A protocol frame: ~A"
                   (message-decoder-kind decoder)
                   (bounded-codec-error-message
                    condition)))))))

(defun message-decoder-end (decoder)
  (when (message-decoder-failed-p decoder)
    (decoder-failed decoder))
  (handler-case
      (frame-decoder-end
       (message-decoder-frames decoder))
    (error (condition)
      (setf (message-decoder-failed-p decoder) t)
      (protocol-fail
       (format nil
               "Invalid ~A protocol framing: ~A"
               (message-decoder-kind decoder)
               (bounded-codec-error-message
                condition)))))
  nil)
