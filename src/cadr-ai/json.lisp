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

(defun utf8-string (octets &optional (start 0) end)
  ;; ASCII: pre-sized simple-base-string + ub32 schar
  ;; (copy-unescaped-json-octets). Mixed: same copy on ASCII
  ;; runs; non-ASCII windows decode UTF-8. Optional START/END
  ;; decode one slice without copying the rest. Not FFI. Not intern.
  ;; (goal 20 sprof UTF8->STRING-AREF 58.3% total at ab4a52ea4).
  (let ((n (length octets)))
    (declare (type fixnum n start)
             (type (or null fixnum) end))
    (unless end
      (setf end n))
    (when (or (zerop n) (>= start end))
      (return-from utf8-string ""))
    (if (typep octets '(simple-array (unsigned-byte 8) (*)))
        (copy-utf8-octets octets start end)
        (let* ((count (the fixnum (- end start)))
               (copy
                 (make-array count :element-type '(unsigned-byte 8))))
          (replace copy octets :start2 start :end2 end)
          (copy-utf8-octets copy 0 count)))))

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

(defun json-object-pairs-p (value)
  ;; Session tool-call arguments: even-length string-key pairs
  ;; tagged so WRITE-JSON-VALUE emits an object, not an array,
  ;; and empty arguments stay distinct from JSON false.
  (and (consp value)
       (eq (car value) :json-object)))

(defun json-get (object key &optional default)
  (cond
    ((hash-table-p object)
     (gethash key object default))
    ((json-object-pairs-p object)
     (loop for (pair-key pair-value) on (cdr object) by #'cddr
           when (and (stringp pair-key)
                     (string= pair-key key))
             return pair-value
           finally (return default)))
    (t default)))

(defun json-present-p (object key)
  (cond
    ((hash-table-p object)
     (nth-value 1 (gethash key object)))
    ((json-object-pairs-p object)
     (loop for (pair-key pair-value) on (cdr object) by #'cddr
           thereis (and (stringp pair-key)
                        (string= pair-key key))))
    (t nil)))

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

(declaim (inline copy-unescaped-json-string))
(defun copy-unescaped-json-string (source start end base-p)
  ;; One window copy of SOURCE[START,END).  A SIMPLE-BASE-STRING source
  ;; is SUBSEQ (same element type).  Unicode windows stay a character
  ;; SUBSEQ.  ASCII windows in a character string become one converting
  ;; REPLACE into a fresh SIMPLE-BASE-STRING so hash/equal stay on
  ;; 8-bit data.  The result does not share storage with SOURCE
  ;; (goal20-json-unescaped-window-copies-source).  Probe 7b is the
  ;; write path and is not repeated.
  (declare (type simple-string source)
           (type fixnum start end))
  (let ((count (- end start)))
    (declare (type fixnum count))
    (cond
      ((zerop count) "")
      ((typep source 'simple-base-string)
       (subseq (the simple-base-string source) start end))
      ((not base-p)
       (subseq source start end))
      (t
       (let ((out (make-array count :element-type 'base-char)))
         (declare (type simple-base-string out)
                  (type (simple-array character (*)) source))
         (replace out source :start2 start :end2 end)
         out)))))

(defun json-interned-ascii-key (source start end)
  ;; OpenAI completions chunks and session JSONL reuse a closed key
  ;; set.  Returning the literal skips COPY-UNESCAPED-JSON-STRING on
  ;; every object key.  Unknown keys still copy.  Values never come
  ;; through here.
  (declare (type simple-string source)
           (type fixnum start end))
  (let ((count (- end start)))
    (declare (type fixnum count))
    (when (plusp count)
    (let ((first (schar source start)))
    (flet ((key= (literal)
             (string= literal source :start2 start :end2 end)))
      (case count
        (2 (when (and (char= first #\i) (key= "id")) "id"))
        (4 (case first
             (#\r (when (key= "role") "role"))
             (#\t (cond
                    ((key= "type") "type")
                    ((key= "text") "text")))
             (#\n (when (key= "name") "name"))))
        (5 (case first
             (#\i (cond
                    ((key= "index") "index")
                    ((key= "input") "input")))
             (#\m (when (key= "model") "model"))
             (#\d (when (key= "delta") "delta"))
             (#\u (when (key= "usage") "usage"))
             (#\t (when (key= "total") "total"))))
        (6 (when (char= first #\o)
             (cond
               ((key= "object") "object")
               ((key= "output") "output"))))
        (7 (case first
             (#\c (cond
                    ((key= "created") "created")
                    ((key= "choices") "choices")
                    ((key= "content") "content")))
             (#\m (when (key= "message") "message"))))
        (8 (case first
             (#\f (when (key= "function") "function"))
             (#\p (cond
                    ((key= "parentId") "parentId")
                    ((key= "provider") "provider")))))
        (9 (case first
             (#\a (when (key= "arguments") "arguments"))
             (#\t (when (key= "timestamp") "timestamp"))
             (#\c (when (key= "cacheRead") "cacheRead"))))
        (10 (case first
              (#\t (when (key= "tool_calls") "tool_calls"))
              (#\c (when (key= "cacheWrite") "cacheWrite"))
              (#\s (when (key= "stopReason") "stopReason"))))
        (11 (when (and (char= first #\t) (key= "totalTokens"))
              "totalTokens"))
        (12 (when (and (char= first #\t) (key= "total_tokens"))
              "total_tokens"))
        (13 (case first
              (#\f (when (key= "finish_reason") "finish_reason"))
              (#\p (when (key= "prompt_tokens") "prompt_tokens"))))
        (17 (when (and (char= first #\c) (key= "completion_tokens"))
              "completion_tokens"))))))))

(defun json-interned-ascii-value (source start end)
  ;; session_load / journal_read: repeated short ASCII values
  ;; ("message", "assistant", "user", …) skip COPY-UNESCAPED-JSON-STRING.
  ;; Object keys stay on json-interned-ascii-key.  Not 7b.
  (declare (type simple-string source)
           (type fixnum start end))
  (let ((count (- end start)))
    (declare (type fixnum count))
    (flet ((val= (literal)
             (and (= count (length literal))
                  (string= literal source :start2 start :end2 end))))
      (case count
        (4 (cond
             ((val= "text") "text")
             ((val= "user") "user")
             ((val= "stop") "stop")
             ((val= "read") "read")))
        (6 (cond
             ((val= "custom") "custom")
             ((val= "medium") "medium")))
        (7 (cond
             ((val= "message") "message")
             ((val= "session") "session")
             ((val= "toolUse") "toolUse")))
        (8 (cond
             ((val= "thinking") "thinking")
             ((val= "toolCall") "toolCall")))
        (9 (when (val= "assistant") "assistant"))
        (10 (when (val= "toolResult") "toolResult"))
        (18 (when (val= "openai-completions") "openai-completions"))))))

(defun parse-json-source
    (source &optional object-visitor nest (start 0) end)
  ;; Cost center for session_load / journal_read
  ;; (docs/benchmarks/goal20-part-o-remaining-sprof.md).  CHAR on a
  ;; general STRING and MEMBER whitespace checks show up as generic
  ;; ops; one coerce to SIMPLE-STRING lets the scan use SCHAR and
  ;; FIXNUM indexes without dropping SAFETY.  Unescaped ASCII strings
  ;; go through COPY-UNESCAPED-JSON-STRING.
  ;; OBJECT-VISITOR, when set, walks the top-level object's fields
  ;; and does not allocate that EQUAL hash.  NEST, when set, is
  ;; (KEY) → (VALUES visitor finish): a nested `{` is walked the
  ;; same way and FINISH produces the field value (session message /
  ;; usage).  Other nested objects stay hash tables.  START/END let
  ;; session JSONL parse a reused line buffer.  Not intern.  Not 7b.
  (let* ((source
           (if (simple-string-p source)
               source
               (coerce source 'simple-string)))
         (position start)
         (length (or end (length source)))
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
             ;; The scan only looks for quote, backslash, and controls.
             ;; base-p is decided on the copy path (intern hits never
             ;; copy).  Not intern expand.  Not 7b.
             (expect #\")
             (let ((start position)
                   (escaped-p nil))
               (declare (type fixnum start))
               (loop
                 (when (>= position length)
                   (fail "Unterminated string"))
                 (let ((code (char-code (schar source position))))
                   (cond
                     ((= code #x22)
                      (let ((end position))
                        (incf position)
                        (return
                          (cond
                            (escaped-p
                             (decode-escaped-string start end))
                            ((and intern-p
                                  (or (json-interned-ascii-key
                                       source start end)
                                      (json-interned-ascii-value
                                       source start end))))
                            ((and (not intern-p)
                                  (json-interned-ascii-value
                                   source start end)))
                            (t
                             (let ((base-p t))
                               (loop for index from start below end
                                     when (> (char-code
                                              (schar source index))
                                             127)
                                       do (setf base-p nil)
                                          (return))
                               (copy-unescaped-json-string
                                source start end base-p)))))))
                     ((< code #x20)
                      (fail "Unescaped control character"))
                     ((= code #x5c)
                      (setf escaped-p t)
                      (incf position)
                      (skip-string-escape))
                     (t
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
           (when (and (peek)
                      (char= (peek) #\]))
             (take)
             (return-from parse-array #()))
           (let ((first (parse-value depth)))
             (skip-space)
             (case (peek)
               (#\]
                (take)
                (vector first))
               (#\,
                (take)
                (skip-space)
                (let ((items (list first)))
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
               (otherwise
                (fail "Expected comma or ]")))))
         (parse-typed-array (element)
           ;; ELEMENT is called for each item.  Session content
           ;; arrays use this to skip EQUAL hashes on blocks.
           (expect #\[)
           (skip-space)
           (when (and (peek)
                      (char= (peek) #\]))
             (take)
             (return-from parse-typed-array #()))
           (let ((first (funcall element)))
             (skip-space)
             (case (peek)
               (#\]
                (take)
                (vector first))
               (#\,
                (take)
                (skip-space)
                (let ((items (list first)))
                  (loop
                    (push (funcall element) items)
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
               (otherwise
                (fail "Expected comma or ]")))))
         (parse-object (depth)
           ;; Session JSONL objects are almost all 2–8 keys.  A default
           ;; EQUAL table holds 7 pairs and then GROW-HASH-TABLE copies
           ;; the 8-key message objects; a fixed :size 8/16 over-allocates
           ;; the 2-key majority.  Stack the first 8 pairs, then allocate
           ;; :size COUNT (or spill past 8).  Not intern expand.  Not 7b.
           (expect #\{)
           (skip-space)
           (when (and (peek)
                      (char= (peek) #\}))
             (take)
             (return-from parse-object
               (make-hash-table :test #'equal)))
           (let ((pairs (make-array 16))
                 (count 0)
                 (spilled nil))
             (declare (type (simple-vector 16) pairs)
                      (type fixnum count)
                      (dynamic-extent pairs))
             (loop
               (unless (and (peek)
                            (char= (peek) #\"))
                 (fail "Object key must be a string"))
               (let ((key (parse-string t)))
                 (skip-space)
                 (expect #\:)
                 (skip-space)
                 (let ((value (parse-value depth)))
                   (cond
                     (spilled
                      (setf (gethash key spilled) value))
                     ((< count 8)
                      (setf (svref pairs (* count 2)) key)
                      (setf (svref pairs (1+ (* count 2))) value)
                      (incf count))
                     (t
                      (let ((object
                              (make-hash-table :test #'equal :size 16)))
                        (loop for index from 0 below count
                              do (setf
                                  (gethash
                                   (svref pairs (* index 2))
                                   object)
                                  (svref pairs (1+ (* index 2)))))
                        (setf (gethash key object) value)
                        (setf spilled object))))))
               (skip-space)
               (case (peek)
                 (#\, (take) (skip-space))
                 (#\}
                  (take)
                  (return
                    (or spilled
                        (let ((object
                                (make-hash-table
                                 :test #'equal
                                 :size count)))
                          (loop for index from 0 below count
                                do (setf
                                    (gethash
                                     (svref pairs (* index 2))
                                     object)
                                    (svref pairs (1+ (* index 2)))))
                          object))))
                 (otherwise
                  (fail "Expected comma or }"))))))
         (parse-object-fields (visitor)
           (expect #\{)
           (skip-space)
           (when (and (peek)
                      (char= (peek) #\}))
             (take)
             (return-from parse-object-fields nil))
           (loop
             (unless (and (peek)
                          (char= (peek) #\"))
               (fail "Object key must be a string"))
             (let ((key (parse-string t)))
               (skip-space)
               (expect #\:)
               (skip-space)
               (funcall
                visitor key
                (block nested
                  (when (and nest (peek))
                    (multiple-value-bind
                          (nested-visitor nested-finish kind)
                        (funcall nest key)
                      (cond
                        ((and (eq kind :array)
                              (char= (peek) #\[))
                         (return-from nested
                           (parse-typed-array
                            (lambda ()
                              (skip-space)
                              (cond
                                ((and (peek)
                                      (char= (peek) #\{))
                                 (multiple-value-bind
                                       (item-visitor item-finish)
                                     (funcall nested-visitor)
                                   (parse-object-fields
                                    item-visitor)
                                   (if item-finish
                                       (funcall item-finish)
                                       t)))
                                (t
                                 (parse-value 1)))))))
                        ((and nested-visitor
                              (char= (peek) #\{))
                         (parse-object-fields nested-visitor)
                         (return-from nested
                           (if nested-finish
                               (funcall nested-finish)
                               t))))))
                  (parse-value 1))))
             (skip-space)
             (case (peek)
               (#\, (take) (skip-space))
               (#\}
                (take)
                (return))
               (otherwise
                (fail "Expected comma or }")))))
         (parse-value (depth)
           (skip-space)
           (case (peek)
             (#\" (parse-string))
             (#\{
              (cond
                ((and object-visitor (zerop depth))
                 (parse-object-fields object-visitor)
                 :visited-object)
                ((< depth
                    +maximum-json-nesting-depth+)
                 (parse-object (1+ depth)))
                (t
                 (fail
                  "Maximum JSON nesting depth exceeded"))))
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
        (if object-visitor
            (if (eq value :visited-object)
                t
                (fail "Expected JSON object"))
            value))))))

(defun parse-json-object-fields
    (source visitor &optional nest (start 0) end)
  ;; Top-level object only: each key/value is handed to VISITOR.
  ;; No EQUAL hash for that object.  NEST optionally walks named
  ;; nested objects the same way (session message / usage / cost).
  ;; Other nested values still parse as hash tables / vectors.
  ;; NEST may also return kind :array to walk a JSON array of
  ;; objects (session content blocks).  Public PARSE-JSON is
  ;; unchanged.  START/END parse a reused line buffer.
  (parse-json-source source visitor nest start end))

(defun parse-json (source)
  (parse-json-source source))

(defun octet-u32-le (octets index)
  ;; Four ASCII bytes as a fixnum. Not FFI. Not sb-simd.
  (declare (type (simple-array (unsigned-byte 8) (*)) octets)
           (type fixnum index)
           (optimize (speed 3) (safety 1)))
  (logior (aref octets index)
          (ash (aref octets (the fixnum (+ index 1))) 8)
          (ash (aref octets (the fixnum (+ index 2))) 16)
          (ash (aref octets (the fixnum (+ index 3))) 24)))

(define-compiler-macro octet-u32-le (octets index)
  ;; V8 SeqOneByteString 4-byte load: inline aref+ash.
  ;; sprof session_load @ 335718c2e: OCTET-U32-LE 12.2% self.
  ;; Not empty SWAR. Not intern. Not FFI.
  (let ((octets-g (gensym "OCTETS"))
        (index-g (gensym "INDEX")))
    `(let ((,octets-g ,octets)
           (,index-g ,index))
       (declare (type (simple-array (unsigned-byte 8) (*)) ,octets-g)
                (type fixnum ,index-g))
       (logior (aref ,octets-g ,index-g)
               (ash (aref ,octets-g (the fixnum (+ ,index-g 1))) 8)
               (ash (aref ,octets-g (the fixnum (+ ,index-g 2))) 16)
               (ash (aref ,octets-g (the fixnum (+ ,index-g 3))) 24)))))

(defun octet-window-equals (octets start end literal)
  ;; Short ASCII windows compare as ub32 chunks, then a
  ;; 1–3 byte tail. Constant literals fold via the
  ;; compiler-macro (memcmp of the packed words). Not intern.
  (declare (type (simple-array (unsigned-byte 8) (*)) octets)
           (type fixnum start end)
           (type simple-string literal)
           (optimize (speed 3) (safety 1)))
  (let ((count (- end start))
        (lit-n (length literal)))
    (declare (type fixnum count lit-n))
    (when (= count lit-n)
      (let ((offset 0))
        (declare (type fixnum offset))
        (loop while (>= (the fixnum (- count offset)) 4)
              do
              (let ((want
                      (logior
                       (char-code (schar literal offset))
                       (ash (char-code
                             (schar literal
                                    (the fixnum (+ offset 1))))
                            8)
                       (ash (char-code
                             (schar literal
                                    (the fixnum (+ offset 2))))
                            16)
                       (ash (char-code
                             (schar literal
                                    (the fixnum (+ offset 3))))
                            24))))
                (unless (= (octet-u32-le
                            octets (the fixnum (+ start offset)))
                           want)
                  (return-from octet-window-equals nil)))
              (incf offset 4))
        (loop while (< offset count)
              do
              (unless (= (aref octets (the fixnum (+ start offset)))
                         (char-code (schar literal offset)))
                (return-from octet-window-equals nil))
              (incf offset))
        t))))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defun ascii-literal-u32-le (literal index)
    (declare (type simple-string literal)
             (type fixnum index))
    (logior (char-code (schar literal index))
            (ash (char-code (schar literal (the fixnum (+ index 1)))) 8)
            (ash (char-code (schar literal (the fixnum (+ index 2)))) 16)
            (ash (char-code (schar literal (the fixnum (+ index 3)))) 24))))

(define-compiler-macro octet-window-equals
    (&whole form octets start end literal)
  ;; Constant ASCII string → packed ub32 / tail bytes.
  ;; Not intern. Not FFI.
  (if (and (stringp literal)
           (every (lambda (character)
                    (< (char-code character) 128))
                  literal))
      (let* ((count (length literal))
             (words
               (loop for index from 0 to (- count 4) by 4
                     collect (ascii-literal-u32-le literal index)))
             (tail-start (* 4 (length words)))
             (octets-g (gensym "OCTETS"))
             (start-g (gensym "START"))
             (end-g (gensym "END")))
        `(let ((,octets-g ,octets)
               (,start-g ,start)
               (,end-g ,end))
           (declare (type (simple-array (unsigned-byte 8) (*)) ,octets-g)
                    (type fixnum ,start-g ,end-g))
           (and (= (the fixnum (- ,end-g ,start-g)) ,count)
                ,@(loop for word in words
                        for chunk from 0
                        collect
                        `(= (octet-u32-le
                             ,octets-g
                             (the fixnum
                                  (+ ,start-g ,(* chunk 4))))
                            ,word))
                ,@(loop for index from tail-start below count
                        collect
                        `(= (aref ,octets-g
                                  (the fixnum (+ ,start-g ,index)))
                            ,(char-code (schar literal index)))))))
      form))

(defun copy-unescaped-json-octets (octets start end)
  ;; UTF-8 only on the value window, not the whole JSONL line.
  ;; ASCII: ub32 chunks written as four schars (V8 memcpy of
  ;; the Latin-1 window). Not FFI. Not intern.
  (declare (type (simple-array (unsigned-byte 8) (*)) octets)
           (type fixnum start end)
           (optimize (speed 3) (safety 1)))
  (let ((ascii-p t))
    (loop for index from start below end
          when (>= (aref octets index) 128)
            do (setf ascii-p nil)
               (return))
    (if (not ascii-p)
        (sb-ext:octets-to-string
         octets
         :external-format :utf-8
         :start start
         :end end)
        (let* ((count (- end start))
               (out (make-string count :element-type 'base-char)))
          (declare (type fixnum count)
                   (type simple-base-string out))
          (let ((src start)
                (dst 0)
                (left count))
            (declare (type fixnum src dst left))
            (loop while (>= left 4)
                  do
                  (let ((word (octet-u32-le octets src)))
                    (setf (schar out dst)
                          (code-char (ldb (byte 8 0) word)))
                    (setf (schar out (the fixnum (+ dst 1)))
                          (code-char (ldb (byte 8 8) word)))
                    (setf (schar out (the fixnum (+ dst 2)))
                          (code-char (ldb (byte 8 16) word)))
                    (setf (schar out (the fixnum (+ dst 3)))
                          (code-char (ldb (byte 8 24) word))))
                  (incf src 4)
                  (incf dst 4)
                  (decf left 4))
            (loop while (> left 0)
                  do
                  (setf (schar out dst)
                        (code-char (aref octets src)))
                  (incf src)
                  (incf dst)
                  (decf left))
            out)))))

(defun utf8-next-width (octets index end)
  ;; Bytes of the next well-formed UTF-8 scalar, or NIL.
  (declare (type (simple-array (unsigned-byte 8) (*)) octets)
           (type fixnum index end)
           (optimize (speed 3) (safety 1)))
  (let ((left (the fixnum (- end index)))
        (b0 (aref octets index)))
    (declare (type fixnum left)
             (type (unsigned-byte 8) b0))
    (cond
      ((< b0 #x80) 1)
      ((< b0 #xc2) nil)
      ((< b0 #xe0)
       (when (and (>= left 2)
                  (= (logand (aref octets (the fixnum (1+ index))) #xc0)
                     #x80))
         2))
      ((< b0 #xf0)
       (when (>= left 3)
         (let ((b1 (aref octets (the fixnum (1+ index))))
               (b2 (aref octets (the fixnum (+ index 2)))))
           (declare (type (unsigned-byte 8) b1 b2))
           (when (and (= (logand b1 #xc0) #x80)
                      (= (logand b2 #xc0) #x80)
                      (cond
                        ((= b0 #xe0) (>= b1 #xa0))
                        ((= b0 #xed) (< b1 #xa0))
                        (t t)))
             3))))
      ((< b0 #xf5)
       (when (>= left 4)
         (let ((b1 (aref octets (the fixnum (1+ index))))
               (b2 (aref octets (the fixnum (+ index 2))))
               (b3 (aref octets (the fixnum (+ index 3)))))
           (declare (type (unsigned-byte 8) b1 b2 b3))
           (when (and (= (logand b1 #xc0) #x80)
                      (= (logand b2 #xc0) #x80)
                      (= (logand b3 #xc0) #x80)
                      (cond
                        ((= b0 #xf0) (>= b1 #x90))
                        ((= b0 #xf4) (< b1 #x90))
                        (t t)))
             4)))))))

(defun utf8-decode-char (octets index width)
  (declare (type (simple-array (unsigned-byte 8) (*)) octets)
           (type fixnum index)
           (type (integer 1 4) width)
           (optimize (speed 3) (safety 1)))
  (let ((b0 (aref octets index)))
    (declare (type (unsigned-byte 8) b0))
    (code-char
     (ecase width
       (1 b0)
       (2
        (logior
         (ash (logand b0 #x1f) 6)
         (logand (aref octets (the fixnum (1+ index))) #x3f)))
       (3
        (logior
         (ash (logand b0 #x0f) 12)
         (ash (logand (aref octets (the fixnum (1+ index))) #x3f) 6)
         (logand (aref octets (the fixnum (+ index 2))) #x3f)))
       (4
        (logior
         (ash (logand b0 #x07) 18)
         (ash (logand (aref octets (the fixnum (1+ index))) #x3f) 12)
         (ash (logand (aref octets (the fixnum (+ index 2))) #x3f) 6)
         (logand (aref octets (the fixnum (+ index 3))) #x3f)))))))

(defun copy-utf8-octets (octets start end)
  ;; Whole-buffer / window decode. All-ASCII uses
  ;; copy-unescaped-json-octets. Mixed: pre-size a character
  ;; string, ub32-copy ASCII runs, decode non-ASCII scalars.
  ;; Invalid UTF-8 falls back to octets-to-string.
  (declare (type (simple-array (unsigned-byte 8) (*)) octets)
           (type fixnum start end)
           (optimize (speed 3) (safety 1)))
  (let ((ascii-p t))
    (loop for index from start below end
          when (>= (aref octets index) 128)
            do (setf ascii-p nil)
               (return))
    (when ascii-p
      (return-from copy-utf8-octets
        (copy-unescaped-json-octets octets start end)))
    (let ((chars 0)
          (index start)
          (ok t))
      (declare (type fixnum chars index))
      (loop while (< index end)
            do
            (if (< (aref octets index) 128)
                (progn
                  (incf chars)
                  (incf index))
                (let ((width (utf8-next-width octets index end)))
                  (cond
                    ((null width)
                     (setf ok nil)
                     (return))
                    (t
                     (incf chars)
                     (incf index width))))))
      (unless ok
        (return-from copy-utf8-octets
          (sb-ext:octets-to-string
           octets :external-format :utf-8 :start start :end end)))
      (let ((out (make-array chars :element-type 'character))
            (src start)
            (dst 0))
        (declare (type simple-string out)
                 (type fixnum src dst))
        (loop while (< src end)
              do
              (if (< (aref octets src) 128)
                  (let ((run-end src)
                        (left 0))
                    (declare (type fixnum run-end left))
                    (loop while (and (< run-end end)
                                     (< (aref octets run-end) 128))
                          do (incf run-end))
                    (setf left (the fixnum (- run-end src)))
                    (loop while (>= left 4)
                          do
                          (let ((word (octet-u32-le octets src)))
                            (setf (schar out dst)
                                  (code-char (ldb (byte 8 0) word)))
                            (setf (schar out (the fixnum (+ dst 1)))
                                  (code-char (ldb (byte 8 8) word)))
                            (setf (schar out (the fixnum (+ dst 2)))
                                  (code-char (ldb (byte 8 16) word)))
                            (setf (schar out (the fixnum (+ dst 3)))
                                  (code-char (ldb (byte 8 24) word))))
                          (incf src 4)
                          (incf dst 4)
                          (decf left 4))
                    (loop while (> left 0)
                          do
                          (setf (schar out dst)
                                (code-char (aref octets src)))
                          (incf src)
                          (incf dst)
                          (decf left)))
                  (let ((width (utf8-next-width octets src end)))
                    (setf (schar out dst)
                          (utf8-decode-char octets src width))
                    (incf src width)
                    (incf dst))))
        out))))

(defun decode-escaped-json-octets (octets start end &optional buffer)
  ;; JSON string value window (between quotes).  Decode escapes
  ;; from octets.  Do not octets-to-string the quoted window and
  ;; re-enter PARSE-JSON-SOURCE.  Not intern.  Not FFI.
  (declare (type (simple-array (unsigned-byte 8) (*)) octets)
           (type fixnum start end))
  (unless buffer
    (setf buffer
          (make-array
           (max 16 (- end start))
           :element-type 'character
           :adjustable t
           :fill-pointer 0)))
  (setf (fill-pointer buffer) 0)
  (let ((index start))
    (declare (type fixnum index))
    (labels
        ((fail (message)
           (error 'json-parse-error
                  :message message
                  :position index))
         (append-char (character)
           (vector-push-extend character buffer))
         (append-run (from to)
           (declare (type fixnum from to))
           (when (< from to)
             (let ((ascii-p t))
               (loop for scan of-type fixnum from from below to
                     when (>= (aref octets scan) 128)
                       do (setf ascii-p nil)
                          (return))
               (if ascii-p
                   (loop for scan of-type fixnum from from below to
                         do (append-char
                             (code-char (aref octets scan))))
                   (let ((piece
                           (sb-ext:octets-to-string
                            octets
                            :external-format :utf-8
                            :start from
                            :end to)))
                     (loop for offset from 0 below (length piece)
                           do (append-char
                               (char piece offset))))))))
         (hex-value (code)
           (cond
             ((<= 48 code 57) (- code 48))
             ((<= 65 code 70) (+ (- code 65) 10))
             ((<= 97 code 102) (+ (- code 97) 10))
             (t (fail "Invalid Unicode escape"))))
         (unicode-unit ()
           (when (> (+ index 4) end)
             (fail "Truncated Unicode escape"))
           (let ((value 0))
             (dotimes (n 4)
               (setf value
                     (+ (* value 16)
                        (hex-value (aref octets index))))
               (incf index))
             value)))
      (loop while (< index end)
            do (let ((code (aref octets index)))
                 (cond
                   ((= code 92)
                    (incf index)
                    (when (>= index end)
                      (fail "Truncated escape"))
                    (let ((escape (aref octets index)))
                      (incf index)
                      (case escape
                        (34 (append-char #\"))
                        (92 (append-char #\\))
                        (47 (append-char #\/))
                        (98 (append-char #\Backspace))
                        (102 (append-char #\Page))
                        (110 (append-char #\Newline))
                        (114 (append-char #\Return))
                        (116 (append-char #\Tab))
                        (117
                         (let ((unit (unicode-unit)))
                           (cond
                             ((<= #xd800 unit #xdbff)
                              (unless
                                  (and
                                   (<= (+ index 2) end)
                                   (= (aref octets index) 92)
                                   (= (aref octets (1+ index)) 117))
                                (fail "Missing low surrogate"))
                              (incf index 2)
                              (let ((low (unicode-unit)))
                                (unless (<= #xdc00 low #xdfff)
                                  (fail "Invalid low surrogate"))
                                (append-char
                                 (code-char
                                  (+ #x10000
                                     (ash (- unit #xd800) 10)
                                     (- low #xdc00))))))
                             ((<= #xdc00 unit #xdfff)
                              (fail "Unexpected low surrogate"))
                             (t
                              (append-char
                               (or (code-char unit)
                                   (fail
                                    "Invalid Unicode codepoint")))))))
                        (t
                         (fail "Unknown string escape")))))
                   (t
                    (let ((run-start index))
                      (loop while
                            (and (< index end)
                                 (/= (aref octets index) 92))
                            do (incf index))
                      (append-run run-start index))))))
      (subseq buffer 0 (fill-pointer buffer)))))

(defun json-interned-ascii-key-octets (octets start end)
  (declare (type (simple-array (unsigned-byte 8) (*)) octets)
           (type fixnum start end))
  (let ((count (- end start)))
    (declare (type fixnum count))
    (when (plusp count)
      (let ((first (aref octets start)))
        (macrolet ((key= (literal)
                     `(octet-window-equals octets start end ,literal)))
          (case count
            (2 (when (and (= first 105) (key= "id")) "id"))
            (4 (case first
                 (114 (when (key= "role") "role"))
                 (116 (cond
                        ((key= "type") "type")
                        ((key= "text") "text")))
                 (110 (when (key= "name") "name"))))
            (5 (case first
                 (105 (cond
                        ((key= "index") "index")
                        ((key= "input") "input")))
                 (109 (when (key= "model") "model"))
                 (100 (when (key= "delta") "delta"))
                 (117 (when (key= "usage") "usage"))
                 (116 (when (key= "total") "total"))))
            (6 (when (= first 111)
                 (cond
                   ((key= "object") "object")
                   ((key= "output") "output"))))
            (7 (case first
                 (99 (cond
                       ((key= "created") "created")
                       ((key= "choices") "choices")
                       ((key= "content") "content")))
                 (109 (when (key= "message") "message"))))
            (8 (case first
                 (102 (when (key= "function") "function"))
                 (112 (cond
                        ((key= "parentId") "parentId")
                        ((key= "provider") "provider")))))
            (9 (case first
                 (97 (when (key= "arguments") "arguments"))
                 (116 (when (key= "timestamp") "timestamp"))
                 (99 (when (key= "cacheRead") "cacheRead"))))
            (10 (case first
                  (116 (when (key= "tool_calls") "tool_calls"))
                  (99 (when (key= "cacheWrite") "cacheWrite"))
                  (115 (when (key= "stopReason") "stopReason"))))
            (11 (when (and (= first 116) (key= "totalTokens"))
                  "totalTokens"))
            (12 (when (and (= first 116) (key= "total_tokens"))
                  "total_tokens"))
            (13 (case first
                  (102 (when (key= "finish_reason") "finish_reason"))
                  (112 (when (key= "prompt_tokens") "prompt_tokens"))))
            (17 (when (and (= first 99) (key= "completion_tokens"))
                  "completion_tokens"))))))))

(defun json-interned-ascii-value-octets (octets start end)
  (declare (type (simple-array (unsigned-byte 8) (*)) octets)
           (type fixnum start end))
  (let ((count (- end start)))
    (declare (type fixnum count))
    (macrolet ((val= (literal)
                 `(octet-window-equals octets start end ,literal)))
      (case count
        (4 (cond
             ((val= "text") "text")
             ((val= "user") "user")
             ((val= "stop") "stop")
             ((val= "read") "read")))
        (6 (cond
             ((val= "custom") "custom")
             ((val= "medium") "medium")))
        (7 (cond
             ((val= "message") "message")
             ((val= "session") "session")
             ((val= "toolUse") "toolUse")))
        (8 (cond
             ((val= "thinking") "thinking")
             ((val= "toolCall") "toolCall")))
        (9 (when (val= "assistant") "assistant"))
        (10 (when (val= "toolResult") "toolResult"))
        (18 (when (val= "openai-completions")
              "openai-completions"))))))

(defun parse-json-simple-integer-octets (octets start end)
  (declare (type (simple-array (unsigned-byte 8) (*)) octets)
           (type fixnum start end))
  (when (>= start end)
    (return-from parse-json-simple-integer-octets nil))
  (let ((index start)
        (negative-p nil))
    (declare (type fixnum index))
    (when (= (aref octets index) 45)
      (setf negative-p t)
      (incf index)
      (when (= index end)
        (return-from parse-json-simple-integer-octets nil)))
    (let ((first (aref octets index)))
      (cond
        ((= first 48)
         (incf index)
         (when (< index end)
           (return-from parse-json-simple-integer-octets nil))
         0)
        ((not (<= 49 first 57))
         nil)
        (t
         (let ((value 0))
           (loop while (< index end)
                 for code of-type fixnum = (aref octets index)
                 do (unless (<= 48 code 57)
                      (return-from parse-json-simple-integer-octets
                        nil))
                    (setf value (+ (* value 10) (- code 48)))
                    (incf index))
           (if negative-p
               (- value)
               value)))))))

(defun parse-json-octets
    (octets &optional object-visitor nest (start 0) end)
  ;; Session JSONL: walk the octet window.  UTF-8 decode only
  ;; unescaped string values that contain high bytes.  String
  ;; PARSE-JSON-SOURCE is unchanged.  Not intern expand.  Not 7b.
  (let* ((octets
           (if (typep octets '(simple-array (unsigned-byte 8) (*)))
               octets
               (replace
                (make-array
                 (length octets)
                 :element-type '(unsigned-byte 8))
                octets)))
         (position start)
         (length (or end (length octets))))
    (declare (type (simple-array (unsigned-byte 8) (*)) octets)
             (type fixnum position length))
    (macrolet ((peek-code ()
                 `(and (< position length)
                       (aref octets position)))
               (take-code ()
                 `(prog1 (peek-code) (incf position))))
      (labels
          ((fail (message)
             (error 'json-parse-error
                    :message message
                    :position position))
           (skip-space ()
             (loop while (< position length)
                   for code = (aref octets position)
                   while (or (= code 32)
                             (= code 9)
                             (= code 13)
                             (= code 10))
                   do (incf position)))
           (expect-code (code)
             (unless (eql (take-code) code)
               (fail (format nil "Expected ~S" (code-char code)))))
           (parse-string (&optional intern-p)
             (expect-code 34)
             (let ((start position)
                   (escaped-p nil))
               (declare (type fixnum start))
               (loop
                 (when (>= position length)
                   (fail "Unterminated string"))
                 (let ((code (aref octets position)))
                   (cond
                     ((= code 34)
                      (let ((end position))
                        (incf position)
                        (return
                          (cond
                            (escaped-p
                             (parse-json-source
                              (sb-ext:octets-to-string
                               octets
                               :external-format :utf-8
                               :start (1- start)
                               :end (1+ end))))
                            ((and intern-p
                                  (or (json-interned-ascii-key-octets
                                       octets start end)
                                      (json-interned-ascii-value-octets
                                       octets start end))))
                            ((and (not intern-p)
                                  (json-interned-ascii-value-octets
                                   octets start end)))
                            (t
                             (copy-unescaped-json-octets
                              octets start end))))))
                     ((< code 32)
                      (fail "Unescaped control character"))
                     ((= code 92)
                      (setf escaped-p t)
                      (incf position)
                      (unless (peek-code)
                        (fail "Truncated escape"))
                      (if (= (take-code) 117)
                          (progn
                            (when (> (+ position 4) length)
                              (fail "Truncated Unicode escape"))
                            (incf position 4))
                          nil))
                     (t
                      (incf position)))))))
           (parse-number ()
             (let ((start position))
               (declare (type fixnum start))
               (loop for code = (peek-code)
                     while
                     (and code
                          (or (<= 48 code 57)
                              (= code 45)
                              (= code 43)
                              (= code 46)
                              (= code 101)
                              (= code 69)))
                     do (incf position))
               (or
                (parse-json-simple-integer-octets
                 octets start position)
                (let ((token
                        (copy-unescaped-json-octets
                         octets start position)))
                  (unless
                      (and
                       (plusp (length token))
                       (valid-json-number-token-p token))
                    (fail "Invalid number"))
                  (handler-case
                      (parse-json-number-token token)
                    (json-parse-error ()
                      (fail
                       "JSON number exponent is too large")))))))
           (parse-literal (literal value)
             (let ((end (+ position (length literal))))
               (unless
                   (and (<= end length)
                        (octet-window-equals
                         octets position end literal))
                 (fail (format nil "Expected ~A" literal)))
               (setf position end)
               value))
           (parse-array (depth)
             (expect-code 91)
             (skip-space)
             (when (eql (peek-code) 93)
               (take-code)
               (return-from parse-array #()))
             (let ((first (parse-value depth)))
               (skip-space)
               (let ((code (peek-code)))
                 (cond
                   ((eql code 93)
                    (take-code)
                    (vector first))
                   ((eql code 44)
                    (take-code)
                    (skip-space)
                    (let ((items (list first)))
                      (loop
                        (push (parse-value depth) items)
                        (skip-space)
                        (let ((next (peek-code)))
                          (cond
                            ((eql next 44)
                             (take-code)
                             (skip-space))
                            ((eql next 93)
                             (take-code)
                             (return
                               (coerce (nreverse items) 'vector)))
                            (t
                             (fail "Expected comma or ]")))))))
                   (t
                    (fail "Expected comma or ]"))))))
           (parse-typed-array (element)
             (expect-code 91)
             (skip-space)
             (when (eql (peek-code) 93)
               (take-code)
               (return-from parse-typed-array #()))
             (let ((first (funcall element)))
               (skip-space)
               (let ((code (peek-code)))
                 (cond
                   ((eql code 93)
                    (take-code)
                    (vector first))
                   ((eql code 44)
                    (take-code)
                    (skip-space)
                    (let ((items (list first)))
                      (loop
                        (push (funcall element) items)
                        (skip-space)
                        (let ((next (peek-code)))
                          (cond
                            ((eql next 44)
                             (take-code)
                             (skip-space))
                            ((eql next 93)
                             (take-code)
                             (return
                               (coerce (nreverse items) 'vector)))
                            (t
                             (fail "Expected comma or ]")))))))
                   (t
                    (fail "Expected comma or ]"))))))
           (parse-object (depth)
             (expect-code 123)
             (skip-space)
             (when (eql (peek-code) 125)
               (take-code)
               (return-from parse-object
                 (make-hash-table :test #'equal)))
             (let ((pairs (make-array 16))
                   (count 0)
                   (spilled nil))
               (declare (type (simple-vector 16) pairs)
                        (type fixnum count)
                        (dynamic-extent pairs))
               (loop
                 (unless (eql (peek-code) 34)
                   (fail "Object key must be a string"))
                 (let ((key (parse-string t)))
                   (skip-space)
                   (expect-code 58)
                   (skip-space)
                   (let ((value (parse-value depth)))
                     (cond
                       (spilled
                        (setf (gethash key spilled) value))
                       ((< count 8)
                        (setf (svref pairs (* count 2)) key)
                        (setf (svref pairs (1+ (* count 2))) value)
                        (incf count))
                       (t
                        (let ((object
                                (make-hash-table :test #'equal :size 16)))
                          (loop for index from 0 below count
                                do (setf
                                    (gethash
                                     (svref pairs (* index 2))
                                     object)
                                    (svref pairs (1+ (* index 2)))))
                          (setf (gethash key object) value)
                          (setf spilled object))))))
                 (skip-space)
                 (let ((code (peek-code)))
                   (cond
                     ((eql code 44)
                      (take-code)
                      (skip-space))
                     ((eql code 125)
                      (take-code)
                      (return
                        (or spilled
                            (let ((object
                                    (make-hash-table
                                     :test #'equal
                                     :size count)))
                              (loop for index from 0 below count
                                    do (setf
                                        (gethash
                                         (svref pairs (* index 2))
                                         object)
                                        (svref pairs (1+ (* index 2)))))
                              object))))
                     (t
                      (fail "Expected comma or }")))))))
           (parse-object-fields (visitor)
             (expect-code 123)
             (skip-space)
             (when (eql (peek-code) 125)
               (take-code)
               (return-from parse-object-fields nil))
             (loop
               (unless (eql (peek-code) 34)
                 (fail "Object key must be a string"))
               (let ((key (parse-string t)))
                 (skip-space)
                 (expect-code 58)
                 (skip-space)
                 (funcall
                  visitor key
                  (block nested
                    (when (and nest (peek-code))
                      (multiple-value-bind
                            (nested-visitor nested-finish kind)
                          (funcall nest key)
                        (cond
                          ((and (eq kind :array)
                                (eql (peek-code) 91))
                           (return-from nested
                             (parse-typed-array
                              (lambda ()
                                (skip-space)
                                (cond
                                  ((eql (peek-code) 123)
                                   (multiple-value-bind
                                         (item-visitor item-finish)
                                       (funcall nested-visitor)
                                     (parse-object-fields
                                      item-visitor)
                                     (if item-finish
                                         (funcall item-finish)
                                         t)))
                                  (t
                                   (parse-value 1)))))))
                          ((and nested-visitor
                                (eql (peek-code) 123))
                           (parse-object-fields nested-visitor)
                           (return-from nested
                             (if nested-finish
                                 (funcall nested-finish)
                                 t))))))
                    (parse-value 1))))
               (skip-space)
               (let ((code (peek-code)))
                 (cond
                   ((eql code 44)
                    (take-code)
                    (skip-space))
                   ((eql code 125)
                    (take-code)
                    (return))
                   (t
                    (fail "Expected comma or }"))))))
           (parse-value (depth)
             (skip-space)
             (let ((code (peek-code)))
               (cond
                 ((eql code 34) (parse-string))
                 ((eql code 123)
                  (cond
                    ((and object-visitor (zerop depth))
                     (parse-object-fields object-visitor)
                     :visited-object)
                    ((< depth +maximum-json-nesting-depth+)
                     (parse-object (1+ depth)))
                    (t
                     (fail
                      "Maximum JSON nesting depth exceeded"))))
                 ((eql code 91)
                  (if (< depth +maximum-json-nesting-depth+)
                      (parse-array (1+ depth))
                      (fail
                       "Maximum JSON nesting depth exceeded")))
                 ((eql code 116) (parse-literal "true" t))
                 ((eql code 102) (parse-literal "false" nil))
                 ((eql code 110) (parse-literal "null" 'null))
                 ((and code
                       (or (<= 48 code 57) (= code 45)))
                  (parse-number))
                 (t
                  (fail "Expected JSON value"))))))
        (let ((value (parse-value 0)))
          (skip-space)
          (unless (= position length)
            (fail "Trailing input"))
          (if object-visitor
              (if (eq value :visited-object)
                  t
                  (fail "Expected JSON object"))
              value))))))

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
    ((json-object-pairs-p value)
     (write-char #\{ stream)
     (loop for key in
           (sort
            (loop for (pair-key) on (cdr value) by #'cddr
                  collect pair-key)
            #'string<)
           for first-p = t then nil
           do
           (unless first-p (write-char #\, stream))
           (write-json-string key stream)
           (write-char #\: stream)
           (write-json-value
            (json-get value key)
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
