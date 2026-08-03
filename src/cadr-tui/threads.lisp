(in-package #:cadr-tui)

(defun stop-thread-for-cleanup
    (thread &key (timeout 0.5d0) (terminate-p t))
  (cond
    ((null thread) :absent)
    ((eq thread sb-thread:*current-thread*) :current)
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
