(in-package #:cadr-protocol)

(defconstant +frame-header-length+ 4)
(defconstant +default-max-frame-length+ (* 16 1024 1024))

(define-condition frame-error (error)
  ((message :initarg :message :reader frame-error-message))
  (:report
   (lambda (condition stream)
     (write-string (frame-error-message condition) stream))))

(defun frame-fail (control &rest arguments)
  (error 'frame-error
         :message (apply #'format nil control arguments)))

(defun resolve-max-frame-length (value)
  (resolve-cbor-limit
   "max-frame-length"
   (or value +default-max-frame-length+)
   +maximum-uint32+))

(defun frame-payload-length (bytes)
  (+ (ash (aref bytes 0) 24)
     (ash (aref bytes 1) 16)
     (ash (aref bytes 2) 8)
     (aref bytes 3)))

(defun encode-frame (payload)
  (unless (typep payload '(vector (unsigned-byte 8)))
    (error 'type-error
           :datum payload
           :expected-type '(vector (unsigned-byte 8))))
  (when (> (length payload) +maximum-uint32+)
    (error 'range-error
           :datum (length payload)
           :expected-type `(integer 0 ,+maximum-uint32+)))
  (let* ((length (length payload))
         (frame
           (make-array
            (+ +frame-header-length+ length)
            :element-type '(unsigned-byte 8))))
    (loop for index below 4
          for shift downfrom 24 to 0 by 8
          do (setf (aref frame index)
                   (ldb (byte 8 shift) length)))
    (replace frame payload :start1 4)
    frame))

(defun assert-complete-frame
    (frame &key max-frame-length)
  (unless (typep frame '(vector (unsigned-byte 8)))
    (error 'type-error
           :datum frame
           :expected-type '(vector (unsigned-byte 8))))
  (when (< (length frame) +frame-header-length+)
    (frame-fail
     "Frame does not contain a complete length prefix"))
  (let* ((length (frame-payload-length frame))
         (maximum
           (resolve-max-frame-length max-frame-length)))
    (when (> length maximum)
      (frame-fail
       "Frame length ~D exceeds configured limit of ~D"
       length maximum))
    (unless (= (length frame)
               (+ +frame-header-length+ length))
      (frame-fail
       "Frame must contain exactly one complete payload")))
  nil)

(defstruct (frame-decoder
            (:constructor %make-frame-decoder
                (max-frame-length)))
  (max-frame-length 0 :type integer)
  (pending
    (make-array 0
                :element-type '(unsigned-byte 8)
                :adjustable t
                :fill-pointer 0))
  ;; Unread start. consume-pending only advances this (cbor-reader
  ;; offset). The JS splice at the old :97-101 replace is gone.
  (offset 0 :type integer)
  (state :open :type keyword))

(defun make-frame-decoder (&key max-frame-length)
  (%make-frame-decoder
   (resolve-max-frame-length max-frame-length)))

(defun frame-decoder-fail (decoder control &rest arguments)
  (setf (frame-decoder-state decoder) :failed
        (frame-decoder-offset decoder) 0
        (fill-pointer
         (frame-decoder-pending decoder)) 0)
  (apply #'frame-fail control arguments))

(defun pending-unread (decoder)
  (- (length (frame-decoder-pending decoder))
     (frame-decoder-offset decoder)))

(defun compact-pending (decoder)
  (let* ((pending (frame-decoder-pending decoder))
         (offset (frame-decoder-offset decoder))
         (n (pending-unread decoder)))
    (when (plusp offset)
      (replace pending pending
               :start1 0 :start2 offset :end2 (+ offset n))
      (setf (fill-pointer pending) n
            (frame-decoder-offset decoder) 0))))

(defun append-pending (decoder chunk)
  (when (> (frame-decoder-offset decoder) 4096)
    (compact-pending decoder))
  (let ((pending (frame-decoder-pending decoder)))
    (loop for byte across chunk
          do (vector-push-extend byte pending))))

(defun consume-pending (decoder count)
  (incf (frame-decoder-offset decoder) count))

(defun frame-payload-length-at (bytes start)
  (+ (ash (aref bytes start) 24)
     (ash (aref bytes (+ start 1)) 16)
     (ash (aref bytes (+ start 2)) 8)
     (aref bytes (+ start 3))))

(defun frame-decoder-push (decoder chunk)
  (case (frame-decoder-state decoder)
    (:ended
     (frame-fail "Frame decoder has ended"))
    (:failed
     (frame-fail "Frame decoder has failed")))
  (unless (typep chunk '(vector (unsigned-byte 8)))
    (error 'type-error
           :datum chunk
           :expected-type '(vector (unsigned-byte 8))))
  (append-pending decoder chunk)
  (let ((frames nil)
        (pending (frame-decoder-pending decoder)))
    (loop
      (when (< (pending-unread decoder) 4)
        (return))
      (let* ((start (frame-decoder-offset decoder))
             (length (frame-payload-length-at pending start)))
        (when (> length
                 (frame-decoder-max-frame-length decoder))
          (frame-decoder-fail
           decoder
           "Frame length ~D exceeds configured limit of ~D"
           length
           (frame-decoder-max-frame-length decoder)))
        (when (< (pending-unread decoder) (+ 4 length))
          (return))
        (push (subseq pending
                      (+ start 4)
                      (+ start 4 length))
              frames)
        (consume-pending decoder (+ 4 length))))
    (nreverse frames)))

(defun frame-decoder-end (decoder)
  (case (frame-decoder-state decoder)
    (:ended
     (frame-fail "Frame decoder has ended"))
    (:failed
     (frame-fail "Frame decoder has failed")))
  (unless (zerop (pending-unread decoder))
    (frame-decoder-fail
     decoder "Truncated frame at end of stream"))
  (setf (frame-decoder-state decoder) :ended)
  nil)
