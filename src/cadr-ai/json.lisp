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

(defun parse-json-simple-integer (source start end)
  ;; Session JSONL and SSE chunks are almost all integers
  ;; (created/index/tokens).  Scanning the window in place skips the
  ;; SUBSEQ token plus the SUBSEQ digits inside PARSE-JSON-NUMBER-TOKEN.
  ;; Decimals, exponents, and leading-zero rejects return NIL so the
  ;; existing token path can fail or parse them.
  (declare (type simple-string source)
           (type fixnum start end))
  (when (>= start end)
    (return-from parse-json-simple-integer nil))
  (let ((index start)
        (negative-p nil))
    (declare (type fixnum index))
    (when (char= (schar source index) #\-)
      (setf negative-p t)
      (incf index)
      (when (= index end)
        (return-from parse-json-simple-integer nil)))
    (let ((first (schar source index)))
      (cond
        ((char= first #\0)
         (incf index)
         (when (< index end)
           (return-from parse-json-simple-integer nil))
         0)
        ((not (digit-char-p first))
         nil)
        (t
         (let ((value 0))
           (loop while (< index end)
                 for code of-type fixnum = (char-code (schar source index))
                 do (unless (<= 48 code 57)
                      (return-from parse-json-simple-integer nil))
                    (setf value (+ (* value 10) (- code 48)))
                    (incf index))
           (if negative-p
               (- value)
               value)))))))

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

(defun copy-unescaped-json-string (source start end base-p)
  ;; Session JSONL keys are ASCII.  Copying those windows into a
  ;; SIMPLE-BASE-STRING keeps hash/equal on 8-bit data; unicode values
  ;; still SUBSEQ into a character string.  Either way the result does
  ;; not share storage with SOURCE (goal20-json-unescaped-window-copies-source).
  ;; Probe 7b (write-string of the unescaped span) lost to peek and is
  ;; not repeated here.
  (declare (type simple-string source)
           (type fixnum start end))
  (let ((count (- end start)))
    (declare (type fixnum count))
    (cond
      ((zerop count) "")
      (base-p
       (let ((out (make-string count :element-type 'base-char)))
         (replace out source :start2 start :end2 end)
         out))
      (t
       (subseq source start end)))))

(defun json-interned-ascii-key (source start end)
  ;; OpenAI completions chunks reuse a closed key set.  Returning the
  ;; literal skips COPY-UNESCAPED-JSON-STRING on every object key.
  ;; Unknown keys still copy.  Values never come through here.
  (declare (type simple-string source)
           (type fixnum start end))
  (let ((count (- end start)))
    (declare (type fixnum count))
    (flet ((key= (literal)
             (and (= count (length literal))
                  (string= literal source :start2 start :end2 end))))
      (case count
        (2 (when (key= "id") "id"))
        (4 (cond
             ((key= "role") "role")
             ((key= "type") "type")
             ((key= "name") "name")))
        (5 (cond
             ((key= "index") "index")
             ((key= "model") "model")
             ((key= "delta") "delta")
             ((key= "usage") "usage")))
        (6 (when (key= "object") "object"))
        (7 (cond
             ((key= "created") "created")
             ((key= "choices") "choices")
             ((key= "content") "content")))
        (8 (when (key= "function") "function"))
        (9 (when (key= "arguments") "arguments"))
        (10 (when (key= "tool_calls") "tool_calls"))
        (12 (when (key= "total_tokens") "total_tokens"))
        (13 (cond
              ((key= "finish_reason") "finish_reason")
              ((key= "prompt_tokens") "prompt_tokens")))
        (17 (when (key= "completion_tokens") "completion_tokens"))))))

(defun parse-json-source (source)
  ;; Cost center for session_load / journal_read
  ;; (docs/benchmarks/goal20-part-o-remaining-sprof.md).  CHAR on a
  ;; general STRING and MEMBER whitespace checks show up as generic
  ;; ops; one coerce to SIMPLE-STRING lets the scan use SCHAR and
  ;; FIXNUM indexes without dropping SAFETY.  Unescaped ASCII strings
  ;; go through COPY-UNESCAPED-JSON-STRING.
  (let* ((source
           (if (simple-string-p source)
               source
               (coerce source 'simple-string)))
         (position 0)
         (length (length source))
         (string-buffer nil))
    (declare (type simple-string source)
             (type fixnum position length))
    (macrolet ((peek ()
                 `(and (< position length)
                       (schar source position)))
               (take ()
                 `(prog1 (peek) (incf position))))
      (labels
          ((fail (message)
             (error 'json-parse-error
                    :message message
                    :position position))
           (skip-space ()
             (loop while (< position length)
                   for character = (schar source position)
                   while (or (char= character #\Space)
                             (char= character #\Tab)
                             (char= character #\Return)
                             (char= character #\Newline))
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
           (append-decoded-char (character)
             (vector-push-extend character string-buffer))
           (skip-string-escape ()
             (unless (peek)
               (fail "Truncated escape"))
             (case (take)
               ((#\" #\\ #\/ #\b #\f #\n #\r #\t))
               (#\u (unicode-unit))
               (otherwise
                (fail "Unknown string escape"))))
           (decode-escaped-string (start end)
             (unless string-buffer
               (setf string-buffer
                     (make-array 64
                                 :element-type 'character
                                 :adjustable t
                                 :fill-pointer 0)))
             (setf (fill-pointer string-buffer) 0)
             (let ((saved position))
               (setf position start)
               (loop while (< position end)
                     do (let ((character (take)))
                          (if (char= character #\\)
                              (progn
                                (unless (peek)
                                  (fail "Truncated escape"))
                                (case (take)
                                  (#\" (append-decoded-char #\"))
                                  (#\\ (append-decoded-char #\\))
                                  (#\/ (append-decoded-char #\/))
                                  (#\b (append-decoded-char #\Backspace))
                                  (#\f (append-decoded-char #\Page))
                                  (#\n (append-decoded-char #\Newline))
                                  (#\r (append-decoded-char #\Return))
                                  (#\t (append-decoded-char #\Tab))
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
                                          (append-decoded-char
                                           (code-char
                                            (+ #x10000
                                               (ash
                                                (- unit #xd800)
                                                10)
                                               (- low #xdc00))))))
                                       ((<= #xdc00 unit #xdfff)
                                        (fail "Unexpected low surrogate"))
                                       (t
                                        (append-decoded-char
                                         (or (code-char unit)
                                             (fail
                                              "Invalid Unicode codepoint")))))))
                                  (otherwise
                                   (fail "Unknown string escape"))))
                              (append-decoded-char character))))
               (setf position saved)
               (subseq string-buffer 0 (fill-pointer string-buffer))))
           (parse-string (&optional intern-p)
             (expect #\")
             (let ((start position)
                   (escaped-p nil)
                   (base-p t))
               (declare (type fixnum start))
               (loop
                 (when (>= position length)
                   (fail "Unterminated string"))
                 (let* ((character (schar source position))
                        (code (char-code character)))
                   (cond
                     ((= code #x22)
                      (let ((end position))
                        (incf position)
                        (return
                          (cond
                            (escaped-p
                             (decode-escaped-string start end))
                            ((and intern-p
                                  (json-interned-ascii-key
                                   source start end)))
                            (t
                             (copy-unescaped-json-string
                              source start end base-p))))))
                     ((< code #x20)
                      (fail "Unescaped control character"))
                     ((= code #x5c)
                      (setf escaped-p t)
                      (incf position)
                      (skip-string-escape))
                     (t
                      (when (> code 127)
                        (setf base-p nil))
                      (incf position)))))))
         (number-character-p (character)
           (and character
                (find character
                      "-+0123456789.eE")))
         (parse-number ()
           (let ((start position))
             (declare (type fixnum start))
             (loop while
                   (number-character-p (peek))
                   do (incf position))
             (or
              (parse-json-simple-integer source start position)
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
                     "JSON number exponent is too large")))))))
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
               (let ((key (parse-string t)))
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
        value)))))

(defun parse-json (source)
  (parse-json-source source))

(defun write-json-string (value stream)
  ;; journal_append Lisp time is stringify (WRITE-JSON-VALUE / this
  ;; function).  Unescaped runs are one WRITE-STRING; escapes still emit
  ;; a short literal.  Per-character WRITE-CHAR on ASCII keys was the
  ;; previous path.  Surrogates are dropped, matching sanitize-surrogates
  ;; (baseline packages/ai/src/utils/sanitize-unicode.ts).
  (write-char #\" stream)
  (let ((length (length value))
        (start 0))
    (declare (type fixnum length start))
    (loop for index from 0 below length
          for character = (char value index)
          for code = (char-code character)
          do
          (cond
            ((<= #xd800 code #xdfff)
             (when (< start index)
               (write-string value stream :start start :end index))
             (setf start (1+ index)))
            ((or (char= character #\")
                 (char= character #\\)
                 (char= character #\Backspace)
                 (char= character #\Page)
                 (char= character #\Newline)
                 (char= character #\Return)
                 (char= character #\Tab)
                 (< code #x20))
             (when (< start index)
               (write-string value stream :start start :end index))
             (case character
               (#\" (write-string "\\\"" stream))
               (#\\ (write-string "\\\\" stream))
               (#\Backspace (write-string "\\b" stream))
               (#\Page (write-string "\\f" stream))
               (#\Newline (write-string "\\n" stream))
               (#\Return (write-string "\\r" stream))
               (#\Tab (write-string "\\t" stream))
               (otherwise
                (format stream "\\u~4,'0X" code)))
             (setf start (1+ index)))))
    (when (< start length)
      (write-string value stream :start start :end length)))
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
  ;; Integers use PRINC.  This path is only non-integer rationals whose
  ;; denominator is 2^a*5^b, so SCALE >= 1 and the integer part is at
  ;; least "0".  Write the digits once instead of building a padded
  ;; copy plus four SUBSEQ/CONCATENATE results.
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
               (digit-length (length digits))
               (padding
                 (max 0
                      (- (1+ scale)
                         digit-length)))
               (split (- (+ padding digit-length) scale)))
          (declare (type fixnum scale digit-length padding split))
          (with-output-to-string (out)
            (when negative-p
              (write-char #\- out))
            (cond
              ((plusp split)
               (if (zerop padding)
                   (write-string digits out :end split)
                   (write-char #\0 out)))
              (t
               (write-char #\0 out)))
            (write-char #\. out)
            (when (plusp padding)
              (dotimes (index (1- padding))
                (write-char #\0 out))
              (write-string digits out))
            (when (and (zerop padding)
                       (< split digit-length))
              (write-string digits out :start split))))))))

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
