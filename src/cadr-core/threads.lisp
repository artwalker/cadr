(in-package #:cadr-core)

(defun stop-thread-for-cleanup (thread &rest args)
  (declare (dynamic-extent args))
  (cond
    ((null thread) :absent)
    ((eq thread sb-thread:*current-thread*) :current)
    (t
     (let ((timeout 0.5d0)
           (terminate-p t))
       (loop for (key value) on args by #'cddr
             do (case key
                  (:timeout (setf timeout value))
                  (:terminate-p (setf terminate-p value))))
       (stop-thread-for-cleanup-rest thread timeout terminate-p)))))

(defun stop-thread-for-cleanup-rest (thread timeout terminate-p)
  "Bound a cleanup wait and optionally terminate a worker that ignores it."
  (cond
    ((not (sb-thread:thread-alive-p thread))
     (ignore-errors
       (sb-thread:join-thread thread :timeout timeout :default nil))
     :joined)
    (t
     (let* ((timed-out (list :timed-out))
            (result
              (handler-case
                  (sb-thread:join-thread
                   thread :timeout timeout :default timed-out)
                (condition () timed-out))))
       (if (not (eq result timed-out))
           :joined
           (if (not terminate-p)
               :abandoned
               (progn
                 (ignore-errors
                   (sb-thread:terminate-thread thread))
                 (let ((terminated
                         (handler-case
                             (sb-thread:join-thread
                              thread :timeout timeout
                              :default timed-out)
                           (condition () timed-out))))
                   (if (or (not (eq terminated timed-out))
                           (not (sb-thread:thread-alive-p thread)))
                       :terminated
                       :abandoned)))))))))

(defun join-active-thread (thread &key reason)
  "Wait without a timeout only for required result synchronization.

REASON is mandatory so an unbounded active join cannot masquerade as cleanup."
  (unless (and (stringp reason)
               (plusp (length
                       (string-trim '(#\Space #\Tab #\Newline #\Return)
                                    reason))))
    (error "An active thread join requires a non-empty reason"))
  (sb-thread:join-thread thread))
