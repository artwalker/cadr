(in-package #:cadr-core)

(defvar *redacted-object-types* nil)

(defun register-redacted-object-type (type)
  (pushnew type *redacted-object-types* :test #'eq)
  type)

(defun redacted-object-types ()
  (sort (copy-list *redacted-object-types*)
        #'string< :key #'symbol-name))

(defmacro define-redacted-print-object
    ((type value stream) &body body)
  `(progn
     (defmethod print-object ((,value ,type) ,stream)
       (print-unreadable-object (,value ,stream :type t)
         (locally ,@body)))
     (eval-when (:load-toplevel :execute)
       (register-redacted-object-type ',type))))

(defun replace-all (source needle replacement)
  (if (zerop (length needle))
      source
      (with-output-to-string (output)
        (loop with start = 0
              for position = (search needle source :start2 start)
              do
              (if position
                  (progn
                    (write-string source output :start start :end position)
                    (write-string replacement output)
                    (setf start (+ position (length needle))))
                  (progn
                    (write-string source output :start start)
                    (return)))))))

(defun redact-secrets (text secrets)
  (reduce
   (lambda (result secret)
     (if (and (stringp secret) (plusp (length secret)))
         (replace-all result secret "[REDACTED]")
         result))
   secrets :initial-value text))
