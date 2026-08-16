(in-package #:cadr-agent)

;;; Baseline packages/agent/src/harness/events.ts (v0.84.2): the harness
;;; run lifecycle event bus.  No cadr consumer exists yet; this is the
;;; structural transcription of the bus itself.

(defun make-run-start-event (lane run-id)
  (list :type :run-start :lane lane :run-id run-id))

(defun make-run-end-event (lane run-id outcome leaf-id)
  ;; OUTCOME is one of :completed, :aborted, :failed.
  (list :type :run-end :lane lane :run-id run-id
        :outcome outcome :leaf-id leaf-id))

(defun harness-event-type (event)
  (getf event :type))

(defclass harness-event-bus ()
  ((listeners
    :initform (make-hash-table :test #'eq)
    :reader harness-event-bus-listeners)
   (watch-listeners
    :initform nil
    :accessor harness-event-bus-watch-listeners)))

(defun make-harness-event-bus ()
  (make-instance 'harness-event-bus))

(defun harness-event-bus-on (bus type listener)
  "Register LISTENER for future events of TYPE and return its unsubscribe
function.  Earlier events are not replayed."
  (push listener (gethash type (harness-event-bus-listeners bus)))
  (lambda ()
    (let ((listeners (harness-event-bus-listeners bus)))
      (setf (gethash type listeners)
            (delete listener (gethash type listeners) :test #'eq :count 1))
      (when (null (gethash type listeners))
        (remhash type listeners)))))

(defun harness-event-bus-emit (bus event)
  "Publish EVENT to the current subscriptions and watch subscriptions."
  (dolist (listener (gethash (harness-event-type event)
                             (harness-event-bus-listeners bus)))
    (funcall listener event))
  (dolist (listener (harness-event-bus-watch-listeners bus))
    (funcall listener event)))

(defun harness-event-bus-watch (bus capture-snapshot)
  "Returns (values snapshot start-fn unsubscribe-fn).  Events emitted
before START-FN is invoked are buffered and flushed in order; emissions
reentrant into the flush keep their order."
  (let ((listener nil)
        (buffered nil))
    (let ((receive
            (lambda (event)
              (if listener
                  (funcall listener event)
                  (setf buffered (append buffered (list event)))))))
      (push receive (harness-event-bus-watch-listeners bus))
      (let ((snapshot (funcall capture-snapshot)))
        (values
         snapshot
         (lambda (next-listener)
           (loop while buffered
                 do (let ((pending buffered))
                      (setf buffered nil)
                      (dolist (event pending)
                        (funcall next-listener event))))
           (setf listener next-listener))
         (lambda ()
           (setf (harness-event-bus-watch-listeners bus)
                 (delete receive
                         (harness-event-bus-watch-listeners bus)
                         :test #'eq :count 1)
                 buffered nil)))))))
