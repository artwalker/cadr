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

(defun iso8601-fixed-milliseconds (value)
  ;; Session JSONL timestamps are YYYY-MM-DDTHH:MM:SS.sssZ.
  ;; Scan digits in place so load-session does not SUBSEQ /
  ;; CONCATENATE / MAKE-STRING a fraction on every entry.
  (declare (type simple-string value))
  (unless (and (= (length value) 24)
               (char= (schar value 4) #\-)
               (char= (schar value 7) #\-)
               (char= (schar value 10) #\T)
               (char= (schar value 13) #\:)
               (char= (schar value 16) #\:)
               (char= (schar value 19) #\.)
               (char= (schar value 23) #\Z))
    (return-from iso8601-fixed-milliseconds nil))
  (flet ((digits (start end)
           (declare (type fixnum start end))
           (let ((number 0))
             (declare (type fixnum number))
             (loop for index of-type fixnum from start below end
                   for code of-type fixnum
                     = (char-code (schar value index))
                   do (unless (<= 48 code 57)
                        (return-from iso8601-fixed-milliseconds
                          nil))
                      (setf number
                            (+ (* number 10) (- code 48))))
             number)))
    (let ((year (digits 0 4))
          (month (digits 5 7))
          (day (digits 8 10))
          (hour (digits 11 13))
          (minute (digits 14 16))
          (second (digits 17 19))
          (millisecond (digits 20 23)))
      (when (and (<= 1 month 12)
                 (<= 1 day 31)
                 (<= 0 hour 23)
                 (<= 0 minute 59)
                 (<= 0 second 59))
        (+ (* 1000
              (- (encode-universal-time
                  second minute hour day month year 0)
                 +unix-universal-time-offset+))
           millisecond)))))

(defun iso8601-to-milliseconds (value)
  (cond
    ((integerp value) value)
    ((stringp value)
     (let* ((source
              (if (simple-string-p value)
                  value
                  (coerce value 'simple-string)))
            (fixed
              (and (= (length source) 24)
                   (iso8601-fixed-milliseconds source))))
       (if (integerp fixed)
           fixed
           (if (>= (length source) 19)
               (handler-case
                   (let* ((year (parse-integer source :start 0 :end 4))
                          (month (parse-integer source :start 5 :end 7))
                          (day (parse-integer source :start 8 :end 10))
                          (hour
                            (parse-integer source :start 11 :end 13))
                          (minute
                            (parse-integer source :start 14 :end 16))
                          (second
                            (parse-integer source :start 17 :end 19))
                          (dot (position #\. source :start 19))
                          (zone
                            (or (position #\Z source :start 19)
                                (length source)))
                          (fraction
                            (if dot
                                (subseq
                                 source (1+ dot)
                                 (min zone (+ dot 4)))
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
                   (error "Invalid ISO-8601 timestamp: ~S" value)))
               (error "Invalid timestamp: ~S" value)))))
    (t
     (error "Invalid timestamp: ~S" value))))

(defun current-utc-iso8601 (&key (fraction-digits 3))
  (milliseconds-to-utc-iso8601
   (unix-milliseconds)
   :fraction-digits fraction-digits))
