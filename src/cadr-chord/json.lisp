(in-package #:cadr-chord)

(defconstant +json-null+ '+json-null+)
(defconstant +json-absent+ '+json-absent+)

(defun json-null-p (value)
  (eq value +json-null+))

(defun json-absent-p (value)
  (eq value +json-absent+))

(defun json-object (&rest pairs)
  (let ((object (make-hash-table :test #'equal)))
    (loop for (key value) on pairs by #'cddr
          do (setf (gethash key object) value))
    object))

(defun json-object-p (value)
  (hash-table-p value))

(defun json-get (object key &optional default)
  (gethash key object default))

(defun json-put (object key value)
  (setf (gethash key object) value)
  object)

(defun json-array (&rest items)
  (make-array (length items)
              :adjustable t
              :fill-pointer (length items)
              :initial-contents items))

(defun json-container-p (value)
  (or (json-object-p value) (and (vectorp value) (not (stringp value)))))

(defun json-keys (object)
  (sort (loop for key being the hash-keys of object collect key) #'string<))

(defun finite-number-p (value)
  (and (realp value)
       (not (floatp value))
       (not (complexp value))))

(defun finite-float-p (value)
  (and (floatp value)
       (= value value)
       (< (abs value) most-positive-double-float)))

(defun json-number-p (value)
  (or (finite-number-p value) (finite-float-p value)))

(defun json-atom-p (value)
  (or (json-null-p value)
      (eq value t)
      (null value)
      (stringp value)
      (json-number-p value)))

(defun copy-json (value &key omit-undefined-properties)
  (let ((seen (make-hash-table :test #'eq)))
    (labels ((walk (item)
               (cond
                 ((json-absent-p item)
                  (error 'type-error
                         :datum item
                         :expected-type 'json-value
                         :format-control "Value contains a non-JSON ~A; expected strict JSON"
                         :format-arguments (list "undefined")))
                 ((json-atom-p item) item)
                 ((not (json-container-p item))
                  (error 'type-error
                         :datum item
                         :expected-type 'json-value
                         :format-control "Value contains a non-JSON ~A; expected strict JSON"
                         :format-arguments (list (type-of item))))
                 ((gethash item seen)
                  (error 'type-error
                         :datum item
                         :expected-type 'json-value
                         :format-control "Value contains cycles and is not strict JSON"))
                 (t
                  (setf (gethash item seen) t)
                  (unwind-protect
                       (cond
                         ((vectorp item)
                          (let ((copy (json-array)))
                            (loop for element across item
                                  do (vector-push-extend
                                      (if (and (json-absent-p element) omit-undefined-properties)
                                          (error 'type-error
                                                 :datum element
                                                 :expected-type 'json-value
                                                 :format-control "Value must contain strict JSON dense plain arrays")
                                          (walk element))
                                      copy))
                            copy))
                         (t
                          (let ((copy (json-object)))
                            (dolist (key (json-keys item))
                              (let ((element (gethash key item)))
                                (unless (and omit-undefined-properties (json-absent-p element))
                                  (when (json-absent-p element)
                                    (error 'type-error
                                           :datum element
                                           :expected-type 'json-value
                                           :format-control "Value contains a non-JSON ~A; expected strict JSON"
                                           :format-arguments (list "undefined")))
                                  (setf (gethash key copy) (walk element)))))
                            copy)))
                    (remhash item seen))))))
      (when (floatp value)
        (unless (finite-float-p value)
          (error 'type-error
                 :datum value
                 :expected-type 'json-value
                 :format-control "Value contains a non-finite number and is not strict JSON")))
      (walk value))))

(defun json-value-p (value)
  (handler-case (progn (copy-json value) t)
    (type-error () nil)))

(defun json-escape (text)
  (with-output-to-string (output)
    (write-char #\" output)
    (loop for character across text
          do (cond
               ((char= character #\") (write-string "\\\"" output))
               ((char= character #\\) (write-string "\\\\" output))
               ((char= character #\Backspace) (write-string "\\b" output))
               ((char= character #\Page) (write-string "\\f" output))
               ((char= character #\Newline) (write-string "\\n" output))
               ((char= character #\Return) (write-string "\\r" output))
               ((char= character #\Tab) (write-string "\\t" output))
               ((< (char-code character) 32)
                (format output "\\u~4,'0X" (char-code character)))
               (t (write-char character output))))
    (write-char #\" output)))

(defun json-number-text (value)
  (if (integerp value)
      (princ-to-string value)
      (let* ((double (coerce value 'double-float))
             (text (format nil "~F" double)))
        (if (find #\e text :test #'char-equal)
            (string-downcase (substitute #\e #\d text))
            (string-right-trim '(#\0) (string-right-trim '(#\.) text))))))

(defun canonical-json (value)
  (cond
    ((json-null-p value) "null")
    ((eq value t) "true")
    ((null value) "false")
    ((stringp value) (json-escape value))
    ((json-number-p value) (json-number-text value))
    ((and (vectorp value) (not (stringp value)))
     (format nil "[~{~A~^,~}]" (map 'list #'canonical-json value)))
    ((hash-table-p value)
     (format nil "{~{~A~^,~}}"
             (mapcar (lambda (key)
                       (concatenate 'string (json-escape key) ":"
                                    (canonical-json (gethash key value))))
                     (json-keys value))))
    (t "null")))

(defun parse-json (text)
  (let ((index 0)
        (length (length text)))
    (labels ((peek ()
               (when (< index length) (char text index)))
             (skip ()
               (loop while (member (peek) '(#\Space #\Tab #\Newline #\Return))
                     do (incf index)))
             (consume (expected)
               (skip)
               (unless (and (peek) (char= (peek) expected))
                 (error "malformed JSON"))
               (incf index))
             (parse-string ()
               (consume #\")
               (with-output-to-string (output)
                 (loop
                   (let ((character (peek)))
                     (unless character (error "malformed JSON"))
                     (incf index)
                     (cond
                       ((char= character #\") (return))
                       ((char= character #\\)
                        (let ((escaped (peek)))
                          (unless escaped (error "malformed JSON"))
                          (incf index)
                          (case escaped
                            (#\" (write-char #\" output))
                            (#\\ (write-char #\\ output))
                            (#\/ (write-char #\/ output))
                            (#\b (write-char #\Backspace output))
                            (#\f (write-char #\Page output))
                            (#\n (write-char #\Newline output))
                            (#\r (write-char #\Return output))
                            (#\t (write-char #\Tab output))
                            (#\u
                             (let ((digits (subseq text index (+ index 4))))
                               (incf index 4)
                               (write-char (code-char (parse-integer digits :radix 16)) output)))
                            (t (error "malformed JSON")))))
                       (t (write-char character output)))))))
             (parse-number ()
               (let ((start index))
                 (when (and (peek) (char= (peek) #\-)) (incf index))
                 (loop while (and (peek) (digit-char-p (peek))) do (incf index))
                 (when (and (peek) (char= (peek) #\.))
                   (incf index)
                   (loop while (and (peek) (digit-char-p (peek))) do (incf index)))
                 (when (and (peek) (member (peek) '(#\e #\E)))
                   (incf index)
                   (when (and (peek) (member (peek) '(#\+ #\-))) (incf index))
                   (loop while (and (peek) (digit-char-p (peek))) do (incf index)))
                 (let ((token (subseq text start index)))
                   (if (or (find #\. token) (find #\e token :test #'char-equal))
                       (read-from-string (substitute #\d #\e (string-downcase token)))
                       (parse-integer token)))))
             (parse-array ()
               (consume #\[)
               (skip)
               (let ((array (json-array)))
                 (unless (and (peek) (char= (peek) #\]))
                   (loop
                     (vector-push-extend (parse-value) array)
                     (skip)
                     (cond
                       ((and (peek) (char= (peek) #\])) (return))
                       ((and (peek) (char= (peek) #\,)) (incf index))
                       (t (error "malformed JSON")))))
                 (consume #\])
                 array))
             (parse-object ()
               (consume #\{)
               (skip)
               (let ((object (json-object)))
                 (unless (and (peek) (char= (peek) #\}))
                   (loop
                     (let ((key (parse-string)))
                       (consume #\:)
                       (setf (gethash key object) (parse-value)))
                     (skip)
                     (cond
                       ((and (peek) (char= (peek) #\})) (return))
                       ((and (peek) (char= (peek) #\,)) (incf index) (skip))
                       (t (error "malformed JSON")))))
                 (consume #\})
                 object))
             (parse-value ()
               (skip)
               (let ((character (peek)))
                 (cond
                   ((null character) (error "malformed JSON"))
                   ((char= character #\") (parse-string))
                   ((char= character #\[) (parse-array))
                   ((char= character #\{) (parse-object))
                   ((char= character #\t) (incf index 4) t)
                   ((char= character #\f) (incf index 5) nil)
                   ((char= character #\n) (incf index 4) +json-null+)
                   (t (parse-number))))))
      (prog1 (parse-value)
        (skip)
        (when (< index length) (error "malformed JSON"))))))
