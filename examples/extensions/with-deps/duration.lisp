(defpackage #:cadr-example-duration
  (:use #:cl)
  (:export #:parse-duration-ms))

(in-package #:cadr-example-duration)

(defun duration-unit-multiplier (unit)
  (cond
    ((member unit '("ms" "msec" "msecs" "millisecond" "milliseconds")
             :test #'string-equal)
     1)
    ((member unit '("s" "sec" "secs" "second" "seconds")
             :test #'string-equal)
     1000)
    ((member unit '("m" "min" "mins" "minute" "minutes")
             :test #'string-equal)
     60000)
    ((member unit '("h" "hr" "hrs" "hour" "hours")
             :test #'string-equal)
     3600000)
    ((member unit '("d" "day" "days") :test #'string-equal)
     86400000)
    ((member unit '("w" "week" "weeks") :test #'string-equal)
     604800000)
    (t nil)))

(defun parse-duration-ms (value)
  (multiple-value-bind (match registers)
      (cl-ppcre:scan-to-strings
       "^\\s*([+-]?(?:[0-9]+(?:\\.[0-9]+)?|\\.[0-9]+))\\s*([A-Za-z]+)\\s*$"
       value)
    (declare (ignore match))
    (when registers
      (let ((multiplier
              (duration-unit-multiplier (aref registers 1))))
        (and multiplier
             (round (* (read-from-string (aref registers 0))
                       multiplier)))))))
