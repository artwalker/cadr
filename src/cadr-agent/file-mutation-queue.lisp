(in-package #:cadr-agent)

(defstruct (file-mutation-queue-state
            (:constructor make-file-mutation-queue-state (key)))
  (key "" :type string :read-only t)
  (waitqueue
    (sb-thread:make-waitqueue :name "cadr file mutation queue")
    :read-only t)
  (next-ticket 0 :type (integer 0 *))
  (serving-ticket 0 :type (integer 0 *))
  (pending-count 0 :type (integer 0 *)))

(defparameter *file-mutation-queues*
  (make-hash-table :test #'equal))

(defparameter *file-mutation-queues-guard*
  (sb-thread:make-mutex
   :name "cadr file mutation queue registry"))

(defun file-mutation-queue-key (path)
  (let ((absolute
          (uiop:ensure-absolute-pathname path)))
    (namestring
     (handler-case
         (truename absolute)
       (file-error (condition)
         (handler-case
             (let ((existing (probe-file absolute)))
               (if existing
                   (error condition)
                   absolute))
           (file-error ()
             (error condition))))))))

(defun ensure-file-mutation-queue-state (key)
  (or (gethash key *file-mutation-queues*)
      (setf (gethash key *file-mutation-queues*)
            (make-file-mutation-queue-state key))))

(defun file-mutation-queue-lock (path)
  (sb-thread:with-mutex (*file-mutation-queues-guard*)
    (ensure-file-mutation-queue-state
     (file-mutation-queue-key path))))

(defun register-file-mutation (path)
  (sb-thread:with-mutex (*file-mutation-queues-guard*)
    (let* ((key (file-mutation-queue-key path))
           (state (ensure-file-mutation-queue-state key))
           (ticket (file-mutation-queue-state-next-ticket state)))
      (incf (file-mutation-queue-state-next-ticket state))
      (incf (file-mutation-queue-state-pending-count state))
      (sb-thread:condition-broadcast
       (file-mutation-queue-state-waitqueue state))
      (values key state ticket))))

(defun wait-for-file-mutation-turn (state ticket)
  (sb-thread:with-mutex (*file-mutation-queues-guard*)
    (loop until
          (= ticket
             (file-mutation-queue-state-serving-ticket state))
          do
      (sb-thread:condition-wait
       (file-mutation-queue-state-waitqueue state)
       *file-mutation-queues-guard*))))

(defun release-file-mutation-turn (key state)
  (sb-thread:with-mutex (*file-mutation-queues-guard*)
    (incf (file-mutation-queue-state-serving-ticket state))
    (decf (file-mutation-queue-state-pending-count state))
    (when (and
           (zerop
            (file-mutation-queue-state-pending-count state))
           (eq state (gethash key *file-mutation-queues*)))
      (remhash key *file-mutation-queues*))
    (sb-thread:condition-broadcast
     (file-mutation-queue-state-waitqueue state))))

(defun with-file-mutation-queue (path function)
  (multiple-value-bind (key state ticket)
      (register-file-mutation path)
    (wait-for-file-mutation-turn state ticket)
    (unwind-protect
         (funcall function)
      (release-file-mutation-turn key state))))
