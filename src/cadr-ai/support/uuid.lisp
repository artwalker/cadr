(in-package #:cadr-ai)

(defparameter *uuid-last-timestamp* -1)
(defparameter *uuid-sequence* 0)

;; Lisp encoding of packages/ai/src/utils/uuid.ts fillRandomBytes
;; (crypto.getRandomValues on a 16-byte buffer). Opening /dev/urandom
;; per uuid-v7 dominated session_compact (sprof read 79%). Keep one
;; stream and a 256-byte pool.
(defparameter *uuid-entropy-stream* nil)
(defparameter *uuid-entropy-buffer*
  (make-array 256 :element-type '(unsigned-byte 8)))
(defparameter *uuid-entropy-fill* 0)
(defparameter *uuid-entropy-index* 0)

(defun uuid-entropy-stream ()
  (let ((stream *uuid-entropy-stream*))
    (if (and (streamp stream) (open-stream-p stream))
        stream
        (setf *uuid-entropy-stream*
              (open #P"/dev/urandom"
                    :direction :input
                    :element-type '(unsigned-byte 8)
                    :if-does-not-exist :error)))))

(defun refill-uuid-entropy ()
  (let ((n (read-sequence *uuid-entropy-buffer* (uuid-entropy-stream))))
    (setf *uuid-entropy-fill* n
          *uuid-entropy-index* 0)
    (when (zerop n)
      (error "uuid entropy: /dev/urandom returned 0 bytes"))))

(defun default-random-octets (count)
  (let ((result
          (make-array count :element-type '(unsigned-byte 8))))
    (dotimes (index count)
      (when (>= *uuid-entropy-index* *uuid-entropy-fill*)
        (refill-uuid-entropy))
      (setf (aref result index)
            (aref *uuid-entropy-buffer* *uuid-entropy-index*))
      (incf *uuid-entropy-index*))
    result))

(defun uuid-v7
    (&key
       (timestamp (unix-milliseconds))
       (random-source #'default-random-octets))
  (let ((random (funcall random-source 16)))
    (if (> timestamp *uuid-last-timestamp*)
        (setf
         *uuid-sequence*
         (+ (ash (aref random 6) 24)
            (ash (aref random 7) 16)
            (ash (aref random 8) 8)
            (aref random 9))
         *uuid-last-timestamp* timestamp)
        (progn
          (setf *uuid-sequence*
                (ldb (byte 32 0) (1+ *uuid-sequence*)))
          (when (zerop *uuid-sequence*)
            (incf *uuid-last-timestamp*))))
    (let ((bytes
            (make-array
             16 :element-type '(unsigned-byte 8)
             :initial-element 0)))
      (dotimes (index 6)
        (setf
         (aref bytes index)
         (ldb
          (byte 8 (* 8 (- 5 index)))
          *uuid-last-timestamp*)))
      (setf
       (aref bytes 6)
       (logior #x70 (ldb (byte 4 28) *uuid-sequence*))
       (aref bytes 7)
       (ldb (byte 8 20) *uuid-sequence*)
       (aref bytes 8)
       (logior #x80 (ldb (byte 6 14) *uuid-sequence*))
       (aref bytes 9)
       (ldb (byte 8 6) *uuid-sequence*)
       (aref bytes 10)
       (logior
        (ash (ldb (byte 6 0) *uuid-sequence*) 2)
        (logand (aref random 10) #x03)))
      (loop for index from 11 below 16
            do (setf (aref bytes index) (aref random index)))
      (let ((hex (octets-hex bytes)))
        (format nil "~A-~A-~A-~A-~A"
                (subseq hex 0 8)
                (subseq hex 8 12)
                (subseq hex 12 16)
                (subseq hex 16 20)
                (subseq hex 20 32))))))
