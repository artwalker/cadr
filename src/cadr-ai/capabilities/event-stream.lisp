(in-package #:cadr-ai)

;;; Producer/consumer event streams

(defclass event-stream ()
  ((queue :initform nil :accessor event-stream-queue)
   (done-p :initform nil :accessor event-stream-done-p)
   (result-ready-p :initform nil :accessor event-stream-result-ready-p)
   (result-value :initform nil :accessor event-stream-result-value)
   (complete-p :initarg :complete-p :reader event-stream-complete-p)
   (result-function :initarg :result-function :reader event-stream-result-function)
   (lock :initform (sb-thread:make-mutex :name "cadr event stream")
         :reader event-stream-lock)
   (condition :initform (sb-thread:make-waitqueue :name "cadr event stream")
              :reader event-stream-condition)))

(defun make-event-stream (&key complete-p result-function)
  (make-instance 'event-stream
                 :complete-p (or complete-p (constantly nil))
                 :result-function (or result-function #'identity)))

(defun event-stream-push (stream event)
  (sb-thread:with-mutex ((event-stream-lock stream))
    (unless (event-stream-done-p stream)
      (setf (event-stream-queue stream)
            (nconc (event-stream-queue stream) (list event)))
      (when (funcall (event-stream-complete-p stream) event)
        (setf (event-stream-done-p stream) t
              (event-stream-result-ready-p stream) t
              (event-stream-result-value stream)
              (funcall (event-stream-result-function stream) event)))
      (sb-thread:condition-broadcast (event-stream-condition stream))))
  event)

(defun event-stream-end (stream &optional (result nil result-supplied-p))
  (sb-thread:with-mutex ((event-stream-lock stream))
    (setf (event-stream-done-p stream) t)
    (when result-supplied-p
      (setf (event-stream-result-ready-p stream) t
            (event-stream-result-value stream) result))
    (sb-thread:condition-broadcast (event-stream-condition stream)))
  nil)

(defun event-stream-next (stream)
  (sb-thread:with-mutex ((event-stream-lock stream))
    (loop while (and (null (event-stream-queue stream))
                     (not (event-stream-done-p stream)))
          do (sb-thread:condition-wait
              (event-stream-condition stream)
              (event-stream-lock stream)))
    (if (event-stream-queue stream)
        (values (pop (event-stream-queue stream)) nil)
        (values nil t))))

(defun event-stream-result (stream)
  (sb-thread:with-mutex ((event-stream-lock stream))
    (loop until (event-stream-result-ready-p stream)
          do (sb-thread:condition-wait
              (event-stream-condition stream)
              (event-stream-lock stream)))
    (event-stream-result-value stream)))
