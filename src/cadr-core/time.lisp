(in-package #:cadr-core)

(defconstant +unix-universal-time-offset+ 2208988800)

(defun unix-milliseconds ()
  "Unix epoch milliseconds.  Baseline Date.now() is real ms, not
second*1000.  get-universal-time is second-granular and made every
timestamp/ID land on .000 — UUID v7, RPC ids, OAuth expiry, session
export.  sb-ext:get-time-of-day is the matching SBCL clock."
  (multiple-value-bind (seconds microseconds)
      (sb-ext:get-time-of-day)
    (+ (* seconds 1000) (floor microseconds 1000))))

(defun milliseconds-to-utc-iso8601
    (milliseconds &key (fraction-digits 3))
  (unless (member fraction-digits '(0 3))
    (error "FRACTION-DIGITS must be 0 or 3"))
  (multiple-value-bind
        (second minute hour day month year)
      (decode-universal-time
       (+ +unix-universal-time-offset+
          (floor milliseconds 1000))
       0)
    (if (zerop fraction-digits)
        (format nil
                "~4,'0D-~2,'0D-~2,'0DT~2,'0D:~2,'0D:~2,'0DZ"
                year month day hour minute second)
        (format nil
                "~4,'0D-~2,'0D-~2,'0DT~2,'0D:~2,'0D:~2,'0D.~3,'0DZ"
                year month day hour minute second
                (mod milliseconds 1000)))))

(defun iso8601-to-milliseconds (value)
  (cond
    ((integerp value) value)
    ((and (stringp value) (>= (length value) 19))
     (handler-case
         (let* ((year (parse-integer value :start 0 :end 4))
                (month (parse-integer value :start 5 :end 7))
                (day (parse-integer value :start 8 :end 10))
                (hour (parse-integer value :start 11 :end 13))
                (minute (parse-integer value :start 14 :end 16))
                (second (parse-integer value :start 17 :end 19))
                (dot (position #\. value :start 19))
                (zone (or (position #\Z value :start 19)
                          (length value)))
                (fraction
                  (if dot
                      (subseq value (1+ dot) (min zone (+ dot 4)))
                      "0"))
                (millisecond
                  (parse-integer
                   (concatenate
                    'string fraction
                    (make-string
                     (max 0 (- 3 (length fraction)))
                     :initial-element #\0)))))
           (+ (* 1000
                 (- (encode-universal-time
                     second minute hour day month year 0)
                    +unix-universal-time-offset+))
              millisecond))
       (error ()
         (error "Invalid ISO-8601 timestamp: ~S" value))))
    (t
     (error "Invalid timestamp: ~S" value))))

(defun current-utc-iso8601 (&key (fraction-digits 3))
  (milliseconds-to-utc-iso8601
   (unix-milliseconds)
   :fraction-digits fraction-digits))
