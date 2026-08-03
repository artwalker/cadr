(in-package #:cadr-ai)

(defparameter *uuid-last-timestamp* -1)
(defparameter *uuid-sequence* 0)

(defun default-random-octets (count)
  (let ((result
          (make-array count :element-type '(unsigned-byte 8))))
    (with-open-file
        (stream #P"/dev/urandom"
                :direction :input
                :element-type '(unsigned-byte 8))
      (read-sequence result stream))
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
