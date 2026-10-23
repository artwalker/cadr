(in-package #:cadr-telemetry)

(defvar *telemetry-wall-milliseconds* nil
  "When set, a function of no arguments replacing Date.now for span and metric clocks.")

(defvar *telemetry-monotonic-milliseconds* nil
  "When set, a function of no arguments replacing performance.now.")

(defun telemetry-wall-milliseconds ()
  (if *telemetry-wall-milliseconds*
      (funcall *telemetry-wall-milliseconds*)
      (cadr-core:unix-milliseconds)))

(defun telemetry-monotonic-milliseconds ()
  (if *telemetry-monotonic-milliseconds*
      (funcall *telemetry-monotonic-milliseconds*)
      (* 1000d0
         (/ (get-internal-real-time)
            internal-time-units-per-second))))

(defun uuid-v4 ()
  ;; crypto.randomUUID. One read per recorder; scopes are not on the hot path.
  (let ((bytes (make-array 16 :element-type '(unsigned-byte 8))))
    (with-open-file (input #P"/dev/urandom"
                           :element-type '(unsigned-byte 8)
                           :direction :input)
      (read-sequence bytes input))
    (setf (aref bytes 6) (logior #x40 (logand (aref bytes 6) #x0f))
          (aref bytes 8) (logior #x80 (logand (aref bytes 8) #x3f)))
    (flet ((word (start length)
             (loop with value = 0
                   for index from start below (+ start length)
                   do (setf value (logior (ash value 8) (aref bytes index)))
                   finally (return value))))
      (format nil "~(~8,'0x-~4,'0x-~4,'0x-~4,'0x-~12,'0x~)"
              (word 0 4) (word 4 2) (word 6 2) (word 8 2) (word 10 6)))))

(defun js-number-text (number)
  (if (integerp number)
      (princ-to-string number)
      (let* ((float (float number 1.0d0))
             (rounded (round float)))
        (if (= float rounded)
            (princ-to-string rounded)
            (let ((text (format nil "~F" float)))
              (if (find #\. text)
                  (string-right-trim '(#\0) text)
                  text))))))

(defun json-string (value)
  (with-output-to-string (output)
    (write-char #\" output)
    (loop for character across value
          do (case character
               (#\" (write-string "\\\"" output))
               (#\\ (write-string "\\\\" output))
               (#\Newline (write-string "\\n" output))
               (#\Return (write-string "\\r" output))
               (#\Tab (write-string "\\t" output))
               (otherwise (write-char character output))))
    (write-char #\" output)))

(defun json-attribute-value (value)
  (cond
    ((eq value t) "true")
    ((null value) "false")
    ((stringp value) (json-string value))
    ((numberp value) (js-number-text value))
    ((vectorp value)
     (with-output-to-string (output)
       (write-char #\[ output)
       (loop for item across value
             for first = t then nil
             do (unless first (write-char #\, output))
                (write-string (json-attribute-value item) output))
       (write-char #\] output)))
    (t (json-string (princ-to-string value)))))

(defun undefined-attribute-p (value)
  (eq value :undefined))

(defun copy-attribute-value (value)
  (if (vectorp value)
      (copy-seq value)
      value))

(defun copy-attributes (attributes)
  (let ((copy nil))
    (dolist (pair attributes)
      (unless (undefined-attribute-p (cdr pair))
        (setf copy
              (append copy
                      (list (cons (car pair)
                                  (copy-attribute-value (cdr pair))))))))
    copy))

(defun merge-attributes (base incoming)
  (let ((result (copy-attributes base)))
    (dolist (pair (copy-attributes incoming))
      (let ((existing (assoc (car pair) result :test #'string=)))
        (if existing
            (setf (cdr existing) (cdr pair))
            (setf result (append result (list pair))))))
    result))

(defun attribute-value (attributes name)
  (cdr (assoc name attributes :test #'string=)))

(defun attribute-equal (left right)
  (cond
    ((and (numberp left) (numberp right)) (= left right))
    ((and (stringp left) (stringp right)) (string= left right))
    (t (eq left right))))

(defun attributes-match-p (attributes query)
  (every (lambda (pair)
           (let ((found (assoc (car pair) attributes :test #'string=)))
             (and found (attribute-equal (cdr found) (cdr pair)))))
         query))

(defun copy-carrier (carrier)
  (copy-alist carrier))

(defun carrier-value (carrier name)
  (cdr (assoc name carrier :test #'string=)))

(defun carrier-id (carrier)
  (format nil "~A:~A"
          (carrier-value carrier "pi-memory-scope")
          (carrier-value carrier "pi-memory-span")))

(defun json-cursor (started-ms trace-id)
  (format nil "[~A,~A]"
          (js-number-text started-ms)
          (json-string trace-id)))

(defun parse-json-string (text start)
  (let ((output (make-array 0 :element-type 'character
                              :adjustable t :fill-pointer 0))
        (index (1+ start)))
    (loop while (< index (length text))
          do (let ((character (char text index)))
               (cond
                 ((char= character #\")
                  (return (values output (1+ index))))
                 ((char= character #\\)
                  (incf index)
                  (vector-push-extend
                   (case (char text index)
                     (#\n #\Newline)
                     (#\r #\Return)
                     (#\t #\Tab)
                     (otherwise (char text index)))
                   output)
                  (incf index))
                 (t
                  (vector-push-extend character output)
                  (incf index)))))))

(defun parse-cursor (text)
  (let* ((open (position #\[ text))
         (comma (position #\, text :start (or open 0))))
    (unless (and open comma)
      (return-from parse-cursor nil))
    (let ((number (ignore-errors
                   (read-from-string text t nil :start (1+ open) :end comma))))
      (unless (numberp number)
        (return-from parse-cursor nil))
      (multiple-value-bind (trace end)
          (parse-json-string text (1+ comma))
        (declare (ignore end))
        (when (stringp trace)
          (list number trace))))))
