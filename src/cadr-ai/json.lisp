(in-package #:cadr-ai)

(define-condition json-parse-error (error)
  ((message :initarg :message :reader json-parse-error-message)
   (position :initarg :position :reader json-parse-error-position))
  (:report
   (lambda (condition stream)
     (format stream "~A at character ~D"
             (json-parse-error-message condition)
             (json-parse-error-position condition)))))

(defconstant +maximum-json-nesting-depth+ 256)
(defconstant +maximum-json-decimal-shift+ 100000)

(defun utf8-octets (text)
  (sb-ext:string-to-octets
   text :external-format :utf-8))

(defun utf8-string (octets)
  (sb-ext:octets-to-string
   octets :external-format :utf-8))

(defun json-object (&rest key-values)
  (assert (evenp (length key-values)))
  (let ((object (make-hash-table :test #'equal)))
    (loop for (key value) on key-values by #'cddr
          do (setf (gethash key object) value))
    object))

(defun json-array (&rest values)
  (coerce values 'vector))

(defun list-json-array (values)
  (coerce values 'vector))

(defun json-get (object key &optional default)
  (if (hash-table-p object)
      (gethash key object default)
      default))

(defun json-present-p (object key)
  (and (hash-table-p object)
       (nth-value 1 (gethash key object))))

(defun json-null-p (value)
  (eq value 'null))

(defun json-put (object key value)
  (setf (gethash key object) value)
  object)

(defun valid-json-number-token-p (token)
  (let ((index 0)
        (length (length token)))
    (labels ((current ()
               (and (< index length)
                    (char token index)))
             (digits ()
               (let ((start index))
                 (loop while (and (current)
                                  (digit-char-p
                                   (current)))
                       do (incf index))
                 (> index start))))
      (when (and (current)
                 (char= (current) #\-))
        (incf index))
      (cond
        ((and (current)
              (char= (current) #\0))
         (incf index)
         (when (and (current)
                    (digit-char-p (current)))
           (return-from valid-json-number-token-p
             nil)))
        ((and (current)
              (digit-char-p (current))
              (not (char= (current) #\0)))
         (unless (digits)
           (return-from valid-json-number-token-p
             nil)))
        (t
         (return-from valid-json-number-token-p
           nil)))
      (when (and (current)
                 (char= (current) #\.))
        (incf index)
        (unless (digits)
          (return-from valid-json-number-token-p
            nil)))
      (when (and (current)
                 (find (current) "eE"))
        (incf index)
        (when (and (current)
                   (find (current) "+-"))
          (incf index))
        (unless (digits)
          (return-from valid-json-number-token-p
            nil)))
      (= index length))))

(defun parse-json-number-token (token)
  (let* ((negative-p
           (char= (char token 0) #\-))
         (start (if negative-p 1 0))
         (exponent-position
           (position-if
            (lambda (character)
              (find character "eE"))
            token
            :start start))
         (mantissa-end
           (or exponent-position
               (length token)))
         (decimal-position
           (position #\. token
                     :start start
                     :end mantissa-end))
         (fraction-length
           (if decimal-position
               (- mantissa-end decimal-position 1)
               0))
         (digits
           (if decimal-position
               (concatenate
                'string
                (subseq token start decimal-position)
                (subseq token
                        (1+ decimal-position)
                        mantissa-end))
               (subseq token start mantissa-end)))
         (significand (parse-integer digits))
         (exponent
           (if exponent-position
               (parse-integer
                token
                :start (1+ exponent-position))
               0))
         (decimal-shift
           (- exponent fraction-length)))
    (when (> (abs decimal-shift)
             +maximum-json-decimal-shift+)
      (error 'json-parse-error
             :message "JSON number exponent is too large"
             :position 0))
    (if (zerop significand)
        0
        (let ((signed-significand
                (if negative-p
                    (- significand)
                    significand)))
          (if (minusp decimal-shift)
              (/ signed-significand
                 (expt 10 (- decimal-shift)))
              (* signed-significand
                 (expt 10 decimal-shift)))))))

(defun parse-json-source (source)
  (let ((position 0)
        (length (length source)))
    (labels
        ((fail (message)
           (error 'json-parse-error
                  :message message
                  :position position))
         (peek ()
           (and (< position length)
                (char source position)))
         (take ()
           (prog1 (peek) (incf position)))
         (skip-space ()
           (loop while
                 (and (peek)
                      (member
                       (peek)
                       '(#\Space #\Tab
                         #\Return #\Newline)))
                 do (incf position)))
         (expect (character)
           (unless (and (peek)
                        (char= (take) character))
             (fail
              (format nil "Expected ~S" character))))
         (hex-value (character)
           (or (digit-char-p character 16)
               (fail "Invalid Unicode escape")))
         (unicode-unit ()
           (when (> (+ position 4) length)
             (fail "Truncated Unicode escape"))
           (loop with value = 0
                 repeat 4
                 do (setf value
                          (+ (* value 16)
                             (hex-value (take))))
                 finally (return value)))
         (parse-string ()
           (expect #\")
           (with-output-to-string (output)
             (loop
               (unless (peek)
                 (fail "Unterminated string"))
               (let ((character (take)))
                 (cond
                   ((char= character #\")
                    (return))
                   ((< (char-code character) #x20)
                    (fail "Unescaped control character"))
                   ((char= character #\\)
                    (unless (peek)
                      (fail "Truncated escape"))
                    (case (take)
                      (#\" (write-char #\" output))
                      (#\\ (write-char #\\ output))
                      (#\/ (write-char #\/ output))
                      (#\b (write-char #\Backspace output))
                      (#\f (write-char #\Page output))
                      (#\n (write-char #\Newline output))
                      (#\r (write-char #\Return output))
                      (#\t (write-char #\Tab output))
                      (#\u
                       (let ((unit (unicode-unit)))
                         (cond
                           ((<= #xd800 unit #xdbff)
                            (unless
                                (and
                                 (<= (+ position 2) length)
                                 (char= (take) #\\)
                                 (char= (take) #\u))
                              (fail "Missing low surrogate"))
                            (let ((low (unicode-unit)))
                              (unless (<= #xdc00 low #xdfff)
                                (fail "Invalid low surrogate"))
                              (write-char
                               (code-char
                                (+ #x10000
                                   (ash
                                    (- unit #xd800)
                                    10)
                                   (- low #xdc00)))
                               output)))
                           ((<= #xdc00 unit #xdfff)
                            (fail "Unexpected low surrogate"))
                           (t
                            (write-char
                             (or (code-char unit)
                                 (fail
                                  "Invalid Unicode codepoint"))
                             output)))))
                      (otherwise
                       (fail "Unknown string escape"))))
                   (t (write-char character output)))))))
         (number-character-p (character)
           (and character
                (find character
                      "-+0123456789.eE")))
         (parse-number ()
           (let ((start position))
             (loop while
                   (number-character-p (peek))
                   do (incf position))
             (let ((token
                     (subseq source start position)))
               (unless
                   (and
                    (plusp (length token))
                    (valid-json-number-token-p
                     token))
                 (fail "Invalid number"))
               (handler-case
                   (parse-json-number-token token)
                 (json-parse-error ()
                   (fail
                    "JSON number exponent is too large"))))))
         (parse-literal (literal value)
           (let ((end (+ position
                         (length literal))))
             (unless
                 (and (<= end length)
                      (string= literal source
                               :start2 position
                               :end2 end))
               (fail
                (format nil "Expected ~A" literal)))
             (setf position end)
             value))
         (parse-array (depth)
           (expect #\[)
           (skip-space)
           (let ((items nil))
             (when (and (peek)
                        (char= (peek) #\]))
               (take)
               (return-from parse-array #()))
             (loop
               (push (parse-value depth) items)
               (skip-space)
               (case (peek)
                 (#\, (take) (skip-space))
                 (#\]
                  (take)
                  (return
                    (coerce
                     (nreverse items)
                     'vector)))
                 (otherwise
                  (fail "Expected comma or ]"))))))
         (parse-object (depth)
           (expect #\{)
           (skip-space)
           (let ((object
                   (make-hash-table :test #'equal)))
             (when (and (peek)
                        (char= (peek) #\}))
               (take)
               (return-from parse-object object))
             (loop
               (unless (and (peek)
                            (char= (peek) #\"))
                 (fail "Object key must be a string"))
               (let ((key (parse-string)))
                 (skip-space)
                 (expect #\:)
                 (skip-space)
                 (setf (gethash key object)
                       (parse-value depth)))
               (skip-space)
               (case (peek)
                 (#\, (take) (skip-space))
                 (#\} (take) (return object))
                 (otherwise
                  (fail "Expected comma or }"))))))
         (parse-value (depth)
           (skip-space)
           (case (peek)
             (#\" (parse-string))
             (#\{
              (if (< depth
                     +maximum-json-nesting-depth+)
                  (parse-object (1+ depth))
                  (fail
                   "Maximum JSON nesting depth exceeded")))
             (#\[
              (if (< depth
                     +maximum-json-nesting-depth+)
                  (parse-array (1+ depth))
                  (fail
                   "Maximum JSON nesting depth exceeded")))
             (#\t (parse-literal "true" t))
             (#\f (parse-literal "false" nil))
             (#\n (parse-literal "null" 'null))
             (otherwise
              (if (and (peek)
                       (or
                        (digit-char-p (peek))
                        (char= (peek) #\-)))
                  (parse-number)
                  (fail "Expected JSON value"))))))
      (let ((value (parse-value 0)))
        (skip-space)
        (unless (= position length)
          (fail "Trailing input"))
        value))))

(defun parse-json (source)
  (handler-case
      (parse-json-source source)
    (json-parse-error (cause)
      (error 'sse-protocol-error
             :message
             (format nil
                     "Invalid JSON in provider response: ~A"
                     cause)
             :cause cause))))

(defun write-json-string (value stream)
  (write-char #\" stream)
  (loop for character across value
        for code = (char-code character)
        unless (<= #xd800 code #xdfff)
          do
          (case character
            (#\" (write-string "\\\"" stream))
            (#\\ (write-string "\\\\" stream))
            (#\Backspace (write-string "\\b" stream))
            (#\Page (write-string "\\f" stream))
            (#\Newline (write-string "\\n" stream))
            (#\Return (write-string "\\r" stream))
            (#\Tab (write-string "\\t" stream))
            (otherwise
             (if (< code #x20)
                 (format stream "\\u~4,'0X" code)
                 (write-char character stream)))))
  (write-char #\" stream))

(defun sanitize-surrogates (text)
  (remove-if
   (lambda (character)
     (<= #xd800 (char-code character) #xdfff))
   text))

(defun factor-count (value factor)
  (loop with count = 0
        while (zerop (mod value factor))
        do
        (setf value (/ value factor))
        (incf count)
        finally (return (values count value))))

(defun terminating-rational-json-text (value)
  (let ((negative-p (minusp value))
        (numerator (abs (numerator value)))
        (denominator (denominator value)))
    (multiple-value-bind (twos without-twos)
        (factor-count denominator 2)
      (multiple-value-bind (fives remainder)
          (factor-count without-twos 5)
        (unless (= remainder 1)
          (error
           "Cannot encode non-terminating rational ~S as JSON"
           value))
        (let* ((scale (max twos fives))
               (scaled
                 (* numerator
                    (expt 2 (- scale twos))
                    (expt 5 (- scale fives))))
               (digits (write-to-string scaled))
               (padding
                 (max 0
                      (- (1+ scale)
                         (length digits))))
               (padded
                 (concatenate
                  'string
                  (make-string padding
                               :initial-element #\0)
                  digits))
               (split (- (length padded) scale)))
          (concatenate
           'string
           (if negative-p "-" "")
           (subseq padded 0 split)
           "."
           (subseq padded split)))))))

(defun write-json-value (value stream)
  (cond
    ((eq value 'null) (write-string "null" stream))
    ((eq value t) (write-string "true" stream))
    ((null value) (write-string "false" stream))
    ((stringp value) (write-json-string value stream))
    ((integerp value) (princ value stream))
    ((rationalp value)
     (write-string
      (terminating-rational-json-text value)
      stream))
    ((floatp value)
     (when (or (sb-ext:float-infinity-p value)
               (sb-ext:float-nan-p value))
       (error "Cannot encode non-finite float ~S as JSON"
              value))
     (let ((text
             (write-to-string
              (coerce value 'double-float)
              :readably t)))
       (write-string
        (substitute #\e #\d
                    (substitute #\e #\D text))
        stream)))
    ((hash-table-p value)
     (write-char #\{ stream)
     (loop for key in
           (sort
            (loop for key being
                  the hash-keys of value
                  collect key)
            #'string<)
           for first-p = t then nil
           do
           (unless first-p (write-char #\, stream))
           (write-json-string key stream)
           (write-char #\: stream)
           (write-json-value
            (gethash key value)
            stream))
     (write-char #\} stream))
    ((or (vectorp value) (listp value))
     (write-char #\[ stream)
     (loop for item across (coerce value 'vector)
           for first-p = t then nil
           do
           (unless first-p (write-char #\, stream))
           (write-json-value item stream))
     (write-char #\] stream))
    (t
     (error "Cannot encode ~S as JSON" value))))

(defun stringify-json (value)
  (with-output-to-string (stream)
    (write-json-value value stream)))

(defun non-empty-string-p (value)
  (and (stringp value)
       (plusp (length (string-trim '(#\Space #\Tab #\Newline #\Return)
                                   value)))))

(defun content-text (content &optional (separator (string #\Newline)))
  (cond
    ((stringp content)
     content)
    ((or (listp content) (vectorp content))
     (with-output-to-string (output)
       (loop with first-p = t
             for item across (coerce content 'vector)
             when (typep item 'text-content)
               do
               (unless first-p
                 (write-string separator output))
               (write-string (text-content-text item) output)
               (setf first-p nil))))
    (t
     "")))

(defun content-text-blocks (content type-key)
  (cond
    ((stringp content)
     (json-array (json-object "type" type-key "text" content)))
    ((or (listp content) (vectorp content))
     (list-json-array
      (loop for item across (coerce content 'vector)
            when (typep item 'text-content)
              collect (json-object "type" type-key
                                   "text" (text-content-text item)))))
    (t
     #())))

(defun data-url (image)
  (format nil "data:~A;base64,~A"
          (image-content-mime-type image)
          (image-content-data image)))

(defun response-error-message (body)
  (handler-case
      (let* ((parsed (if (stringp body) (parse-json body) body))
             (error-object (json-get parsed "error"))
             (message (and (hash-table-p error-object)
                           (json-get error-object "message"))))
        (if (non-empty-string-p message)
            message
            "Provider returned an API error"))
    (error ()
      "Provider returned an API error")))
