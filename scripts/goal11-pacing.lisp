(defpackage #:cadr-goal11-pacing
  (:use #:cl)
  (:export #:paced-wait-until))

(in-package #:cadr-goal11-pacing)

(defun paced-wait-until
    (target-time
     &key
       (clock-function #'get-internal-real-time)
       (sleep-function #'sleep)
       (time-units-per-second internal-time-units-per-second))
  (unless (plusp time-units-per-second)
    (error "time-units-per-second must be positive"))
  ;; CL:SLEEP may return early. Recheck the monotonic clock so the reported
  ;; duration proves actual pacing instead of trusting one sleep call.
  (loop
    for remaining = (- target-time (funcall clock-function))
    while (plusp remaining)
    do (funcall
        sleep-function
        (/ remaining
           (coerce time-units-per-second 'double-float)))))
