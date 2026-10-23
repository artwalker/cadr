(in-package #:cadr-durable)

(define-condition durable-error (error)
  ((text :initarg :text :reader durable-error-text))
  (:report (lambda (condition stream)
             (write-string (durable-error-text condition) stream))))

(define-condition read-after-write (durable-error) ())

(define-condition storage-request-error (durable-error) ())

(define-condition session-failed (durable-error) ())

(define-condition conversation-busy (durable-error)
  ((conversation-id :initarg :conversation-id :reader conversation-busy-id)))

(defun durable-error (type text &rest initargs)
  (apply #'error type :text text initargs))

(defun request-error (text)
  (error 'storage-request-error :text text))

(defun fail-session ()
  (error 'session-failed
         :text "Session failed after a storage error; close and reopen it"))
