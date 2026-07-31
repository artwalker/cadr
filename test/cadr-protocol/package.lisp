(defpackage #:cadr-protocol/tests
  (:use #:cl #:fiveam)
  (:export #:run-tests))

(in-package #:cadr-protocol/tests)

(def-suite cadr-protocol-suite)
(in-suite cadr-protocol-suite)

(defun octets (&rest values)
  (make-array (length values)
              :element-type '(unsigned-byte 8)
              :initial-contents values))

(defun bytes= (left right)
  (equalp left right))

(defun protocol-object (&rest entries)
  (let ((object (make-hash-table :test #'equal)))
    (loop for (key value) on entries by #'cddr
          do (setf (gethash key object) value))
    object))

(defun object-get (object key)
  (gethash key object))

(defun protocol-value= (left right)
  (cond
    ((and (hash-table-p left) (hash-table-p right))
     (and (= (hash-table-count left) (hash-table-count right))
          (loop for key being the hash-keys of left
                  using (hash-value value)
                always
                (multiple-value-bind (other present-p)
                    (gethash key right)
                  (and present-p
                       (protocol-value= value other))))))
    ((and (vectorp left) (vectorp right))
     (and (= (length left) (length right))
          (loop for left-value across left
                for right-value across right
                always (protocol-value= left-value right-value))))
    ((and (cadr-protocol::byte-string-p left)
          (cadr-protocol::byte-string-p right))
     (bytes= (cadr-protocol:byte-string-octets left)
             (cadr-protocol:byte-string-octets right)))
    ((and (floatp left) (floatp right)
          (zerop left) (zerop right))
     (eql (minusp (float-sign left))
          (minusp (float-sign right))))
    (t (equalp left right))))

(defun condition-message-contains-p
    (condition-type needle thunk)
  (handler-case
      (progn (funcall thunk) nil)
    (error (condition)
      (and (typep condition condition-type)
           (search needle (princ-to-string condition)
                   :test #'char-equal)))))

(defmacro signals-message (condition-type needle &body body)
  `(is (condition-message-contains-p
        ',condition-type ,needle (lambda () ,@body))))

(defun run-tests ()
  (run! 'cadr-protocol-suite))
