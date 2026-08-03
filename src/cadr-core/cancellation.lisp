(in-package #:cadr-core)

(defstruct (cancellation-state
            (:constructor %make-cancellation-state))
  (aborted-p nil :type boolean)
  aborted-function
  (lock
    (sb-thread:make-mutex :name "cadr cancellation state"))
  (condition
    (sb-thread:make-waitqueue :name "cadr cancellation condition")))

(defun make-cancellation-state (&key aborted-function)
  (unless (or (null aborted-function)
              (functionp aborted-function))
    (error 'type-error
           :datum aborted-function
           :expected-type '(or null function)))
  (%make-cancellation-state :aborted-function aborted-function))

(defun cancellation-predicate-aborted-p (predicate)
  (and predicate
       (not (null (ignore-errors (funcall predicate))))))

(defun cancellation-aborted-p (state)
  (unless (typep state 'cancellation-state)
    (error 'type-error
           :datum state
           :expected-type 'cancellation-state))
  (or
   (sb-thread:with-mutex ((cancellation-state-lock state))
     (cancellation-state-aborted-p state))
   (cancellation-predicate-aborted-p
    (cancellation-state-aborted-function state))))

(defun set-cancellation-aborted-p (state value)
  (unless (typep state 'cancellation-state)
    (error 'type-error
           :datum state
           :expected-type 'cancellation-state))
  (sb-thread:with-mutex ((cancellation-state-lock state))
    (setf (cancellation-state-aborted-p state)
          (not (null value)))
    (when value
      (sb-thread:condition-broadcast
       (cancellation-state-condition state))))
  value)

(defun abort-cancellation (state)
  (set-cancellation-aborted-p state t)
  state)

(defun wait-for-cancellation (state &key timeout)
  (unless (typep state 'cancellation-state)
    (error 'type-error
           :datum state
           :expected-type 'cancellation-state))
  (when (cancellation-aborted-p state)
    (return-from wait-for-cancellation :aborted))
  (sb-thread:with-mutex ((cancellation-state-lock state))
    (unless (cancellation-state-aborted-p state)
      (sb-thread:condition-wait
       (cancellation-state-condition state)
       (cancellation-state-lock state)
       :timeout timeout))
    (if (cancellation-state-aborted-p state)
        :aborted
        (if (cancellation-predicate-aborted-p
             (cancellation-state-aborted-function state))
            :aborted
            :timeout))))
