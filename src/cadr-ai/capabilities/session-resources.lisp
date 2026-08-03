(in-package #:cadr-ai)

;;; Session-owned transport resources

(defparameter *session-resource-cleanups* nil)
(defparameter *session-resource-cleanups-lock*
  (sb-thread:make-mutex :name "cadr session resource cleanup registry"))

(defun register-session-resource-cleanup (cleanup)
  (sb-thread:with-mutex (*session-resource-cleanups-lock*)
    (pushnew cleanup *session-resource-cleanups* :test #'eq))
  (lambda ()
    (sb-thread:with-mutex (*session-resource-cleanups-lock*)
      (setf *session-resource-cleanups*
            (remove cleanup *session-resource-cleanups* :test #'eq)))
    nil))

(defun clear-session-resource-cleanups ()
  (sb-thread:with-mutex (*session-resource-cleanups-lock*)
    (setf *session-resource-cleanups* nil))
  nil)

(defun cleanup-session-resources (&optional session-id)
  (let ((cleanups
          (sb-thread:with-mutex (*session-resource-cleanups-lock*)
            (reverse (copy-list *session-resource-cleanups*))))
        (errors nil))
    (dolist (cleanup cleanups)
      (handler-case (funcall cleanup session-id)
        (error (condition) (push condition errors))))
    (when errors
      (error "Failed to cleanup session resources: ~{~A~^; ~}"
             (nreverse errors))))
  nil)
