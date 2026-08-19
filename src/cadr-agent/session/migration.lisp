(in-package #:cadr-agent)

(defconstant +session-seen-parent-id+ 1)
(defconstant +session-seen-target-id+ 2)
(defconstant +session-seen-tokens-before+ 4)
(defconstant +session-seen-content+ 8)

(defun mark-session-seen (entry bit)
  (setf (session-entry-%seen entry)
        (logior (session-entry-%seen entry) bit)))

(defun session-seen-p (entry bit)
  (logtest bit (session-entry-%seen entry)))

(defun session-record-put (entry key value)
  (when (plusp (length key))
    (case (char key 0)
      (#\t
       (cond
         ((or (eq key "type") (string= key "type"))
          (setf (session-entry-type entry) value))
         ((or (eq key "timestamp") (string= key "timestamp"))
          (setf (session-entry-timestamp entry) value))
         ((string= key "tokensBefore")
          (mark-session-seen entry +session-seen-tokens-before+)
          (setf (session-entry-tokens-before entry) value))
         ((string= key "thinkingLevel")
          (setf (session-entry-thinking-level entry) value))
         ((string= key "targetId")
          (mark-session-seen entry +session-seen-target-id+)
          (setf (session-entry-target-id entry) value))))
      (#\i
       (when (or (eq key "id") (string= key "id"))
         (setf (session-entry-id entry) value)))
      (#\p
       (cond
         ((or (eq key "parentId") (string= key "parentId"))
          (mark-session-seen entry +session-seen-parent-id+)
          (setf (session-entry-parent-id entry) value))
         ((or (eq key "provider") (string= key "provider"))
          (setf (session-entry-provider entry) value))))
      (#\m
       (cond
         ((or (eq key "message") (string= key "message"))
          (setf (session-entry-message entry) value))
         ((string= key "modelId")
          (setf (session-entry-model-id entry) value))))
      (#\s
       (cond
         ((or (eq key "summary") (string= key "summary"))
          (setf (session-entry-summary entry) value))
         ((string= key "sourceIds")
          (setf (session-entry-source-ids entry) value))))
      (#\f
       (cond
         ((string= key "firstKeptEntryId")
          (setf (session-entry-first-kept-id entry) value))
         ((string= key "fromId")
          (setf (session-entry-from-id entry) value))
         ((string= key "fromHook")
          (setf (session-entry-from-hook-p entry)
                (eq t value)))))
      (#\a
       (when (string= key "activeToolNames")
         (setf (session-entry-active-tool-names entry) value)))
      (#\d
       (cond
         ((or (eq key "details") (string= key "details"))
          (setf (session-entry-details entry) value))
         ((or (eq key "data") (string= key "data"))
          (setf (session-entry-data entry) value))
         ((or (eq key "display") (string= key "display"))
          (setf (session-entry-display-p entry) (eq t value)))))
      (#\u
       (when (or (eq key "usage") (string= key "usage"))
         (setf (session-entry-usage entry) value)))
      (#\c
       (cond
         ((string= key "customType")
          (setf (session-entry-custom-type entry) value))
         ((or (eq key "content") (string= key "content"))
          (mark-session-seen entry +session-seen-content+)
          (setf (session-entry-content entry) value))))
      (#\l
       (when (or (eq key "label") (string= key "label"))
         (setf (session-entry-label entry) value)))
      (#\n
       (when (or (eq key "name") (string= key "name"))
         (setf (session-entry-name entry) value)))
      (#\r
       (when (string= key "retainedTail")
         (setf (session-entry-retained-tail entry) value))))))

(defconstant +swar-lsb+ #x0101010101010101)
(defconstant +swar-msb+ #x8080808080808080)
(defconstant +swar-nl+ #x0A0A0A0A0A0A0A0A)
(defconstant +swar-ht+ #x0909090909090909)
(defconstant +swar-cr+ #x0D0D0D0D0D0D0D0D)
(defconstant +swar-sp+ #x2020202020202020)

(defun swar-eq-msb (word splat)
  ;; V8/haszero after XOR splat: ((x-ones) & ~x & high).
  ;; Words above most-positive-fixnum are bignums; do not
  ;; unbox them with safety 0. Not FFI. Not sb-simd.
  (declare (type (unsigned-byte 64) word splat)
           (optimize (speed 3) (safety 1)))
  (let ((x (logxor word splat)))
    (logand (ldb (byte 64 0) (- x +swar-lsb+))
            (logandc1 x +swar-msb+))))

(defun swar-first-msb-index (mask)
  (declare (type (unsigned-byte 64) mask)
           (optimize (speed 3) (safety 1)))
  (ash (1- (integer-length (logand mask (- mask)))) -3))

(defun octet-find-lf (octets start end)
  ;; First 0x0A in [start,end), or NIL. 8-byte SWAR when aligned.
  (declare (type (simple-array (unsigned-byte 8) (*)) octets)
           (type fixnum start end)
           (optimize (speed 3) (safety 1)))
  (let ((index start))
    (declare (type fixnum index))
    (loop while (< index end)
          do
          (cond
            ((and (zerop (logand index 7))
                  (<= (the fixnum (+ index 8)) end))
             (let ((mask
                     (swar-eq-msb
                      (sb-kernel:%vector-raw-bits octets (ash index -3))
                      +swar-nl+)))
               (if (zerop mask)
                   (incf index 8)
                   (return (+ index (swar-first-msb-index mask))))))
            ((= (aref octets index) 10)
             (return index))
            (t (incf index))))))

(defun octet-skip-json-space (octets start end)
  ;; Advance past JSON whitespace. 8-byte SWAR when aligned.
  (declare (type (simple-array (unsigned-byte 8) (*)) octets)
           (type fixnum start end)
           (optimize (speed 3) (safety 1)))
  (let ((index start))
    (declare (type fixnum index))
    (loop while (< index end)
          do
          (if (and (zerop (logand index 7))
                   (<= (the fixnum (+ index 8)) end))
              (let* ((word
                       (sb-kernel:%vector-raw-bits
                        octets (ash index -3)))
                     (mask
                       (logior (swar-eq-msb word +swar-sp+)
                               (swar-eq-msb word +swar-ht+)
                               (swar-eq-msb word +swar-cr+)
                               (swar-eq-msb word +swar-nl+))))
                (cond
                  ((= mask +swar-msb+)
                   (incf index 8))
                  ((zerop mask)
                   (return-from octet-skip-json-space index))
                  (t
                   (return-from octet-skip-json-space
                     (+ index
                        (swar-first-msb-index
                         (logxor mask +swar-msb+)))))))
              (let ((code (aref octets index)))
                (if (or (= code 32)
                        (= code 9)
                        (= code 13)
                        (= code 10))
                    (incf index)
                    (return-from octet-skip-json-space index)))))
    index))

(defun parse-session-record-octets (octets start end)
  ;; Schema-shaped session JSONL walker.  Known keys fill
  ;; session-entry / session-json-message / usage / content
  ;; slots from the octet window.  Unknown values are skipped
  ;; without allocating.  Integers and YYYY-MM-DDTHH:MM:SS.sssZ
  ;; timestamps are read in place.  Not a general JSON engine.
  ;; Not intern expand.  Not :size.  Not FFI.
  (let* ((octets
           (if (typep octets '(simple-array (unsigned-byte 8) (*)))
               octets
               (replace
                (make-array
                 (length octets)
                 :element-type '(unsigned-byte 8))
                octets)))
         (position start)
         (length (or end (length octets)))
         (entry (make-session-entry))
         (string-buffer nil))
    (declare (type (simple-array (unsigned-byte 8) (*)) octets)
             (type fixnum position length))
    (macrolet ((peek-code ()
                 `(and (< position length)
                       (aref octets position)))
               (take-code ()
                 `(prog1 (peek-code) (incf position)))
               (key= (key-start key-end literal)
                 `(cadr-ai::octet-window-equals
                   octets ,key-start ,key-end ,literal)))
      (labels
          ((fail (message)
             (error 'cadr-ai::json-parse-error
                    :message message
                    :position position))
           (skip-space ()
             (setf position
                   (octet-skip-json-space octets position length)))
           (expect-code (code)
             (unless (eql (take-code) code)
               (fail "Unexpected byte")))
           (skip-string ()
             (expect-code 34)
             (loop
               (when (>= position length)
                 (fail "Unterminated string"))
               (let ((code (take-code)))
                 (cond
                   ((= code 34) (return))
                   ((= code 92)
                    (let ((escape (take-code)))
                      (when (null escape)
                        (fail "Truncated escape"))
                      (when (= escape 117)
                        (when (> (+ position 4) length)
                          (fail "Truncated Unicode escape"))
                        (incf position 4))))))))
           (skip-number ()
             (loop for code = (peek-code)
                   while
                   (and code
                        (or (<= 48 code 57)
                            (= code 45)
                            (= code 43)
                            (= code 46)
                            (= code 101)
                            (= code 69)))
                   do (incf position)))
           (skip-value ()
             (skip-space)
             (let ((code (peek-code)))
               (cond
                 ((eql code 34) (skip-string))
                 ((eql code 123)
                  (expect-code 123)
                  (skip-space)
                  (unless (eql (peek-code) 125)
                    (loop
                      (skip-string)
                      (skip-space)
                      (expect-code 58)
                      (skip-value)
                      (skip-space)
                      (let ((next (peek-code)))
                        (cond
                          ((eql next 44)
                           (take-code)
                           (skip-space))
                          ((eql next 125) (return))
                          (t (fail "Expected comma or }"))))))
                  (expect-code 125))
                 ((eql code 91)
                  (expect-code 91)
                  (skip-space)
                  (unless (eql (peek-code) 93)
                    (loop
                      (skip-value)
                      (skip-space)
                      (let ((next (peek-code)))
                        (cond
                          ((eql next 44)
                           (take-code)
                           (skip-space))
                          ((eql next 93) (return))
                          (t (fail "Expected comma or ]"))))))
                  (expect-code 93))
                 ((eql code 116)
                  (unless (key= position (+ position 4) "true")
                    (fail "Expected true"))
                  (incf position 4))
                 ((eql code 102)
                  (unless (key= position (+ position 5) "false")
                    (fail "Expected false"))
                  (incf position 5))
                 ((eql code 110)
                  (unless (key= position (+ position 4) "null")
                    (fail "Expected null"))
                  (incf position 4))
                 ((and code (or (<= 48 code 57) (= code 45)))
                  (skip-number))
                 (t
                  (fail "Expected JSON value")))))
           (parse-generic ()
             ;; Fill the JSON value in place.  Objects stay
             ;; (:json-object . pairs), not EQUAL hash tables.
             (skip-space)
             (let ((code (peek-code)))
               (cond
                 ((eql code 34) (parse-string-value))
                 ((eql code 123) (parse-arguments-object))
                 ((eql code 91)
                  (expect-code 91)
                  (skip-space)
                  (when (eql (peek-code) 93)
                    (take-code)
                    (return-from parse-generic #()))
                  (let ((items (list (parse-generic))))
                    (loop
                      (skip-space)
                      (let ((next (peek-code)))
                        (cond
                          ((eql next 44)
                           (take-code)
                           (skip-space)
                           (push (parse-generic) items))
                          ((eql next 93)
                           (take-code)
                           (return
                             (coerce (nreverse items) 'vector)))
                          (t
                           (fail "Expected comma or ]")))))))
                 ((eql code 116)
                  (unless (key= position (+ position 4) "true")
                    (fail "Expected true"))
                  (incf position 4)
                  t)
                 ((eql code 102)
                  (unless (key= position (+ position 5) "false")
                    (fail "Expected false"))
                  (incf position 5)
                  nil)
                 ((eql code 110)
                  (parse-literal-null))
                 ((and code
                       (or (<= 48 code 57) (= code 45)))
                  (parse-number-value))
                 (t
                  (fail "Expected JSON value")))))
           (parse-string-value ()
             (expect-code 34)
             (let ((value-start position)
                   (escaped-p nil))
               (loop
                 (when (>= position length)
                   (fail "Unterminated string"))
                 (let ((code (aref octets position)))
                   (cond
                     ((= code 34)
                      (let ((value-end position))
                        (incf position)
                        (return
                          (if escaped-p
                              (cadr-ai::decode-escaped-json-octets
                               octets value-start value-end
                               (or string-buffer
                                   (setf string-buffer
                                         (make-array
                                          64
                                          :element-type 'character
                                          :adjustable t
                                          :fill-pointer 0))))
                              (or
                               (cadr-ai::json-interned-ascii-value-octets
                                octets value-start value-end)
                               (cadr-ai::copy-unescaped-json-octets
                                octets value-start value-end))))))
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
           (parse-number-value ()
             (let ((value-start position))
               (skip-number)
               (or
                (cadr-ai::parse-json-simple-integer-octets
                 octets value-start position)
                (cadr-ai::parse-json-octets
                 octets nil nil value-start position))))
           (iso-ms (value-start value-end)
             (unless (= (- value-end value-start) 24)
               (return-from iso-ms nil))
             (flet ((at (offset)
                      (aref octets (+ value-start offset)))
                    (digits (from to)
                      (let ((number 0))
                        (loop for index from (+ value-start from)
                              below (+ value-start to)
                              for code = (aref octets index)
                              do (unless (<= 48 code 57)
                                   (return-from iso-ms nil))
                                 (setf number
                                       (+ (* number 10) (- code 48))))
                        number)))
               (unless (and (= (at 4) 45)
                            (= (at 7) 45)
                            (= (at 10) 84)
                            (= (at 13) 58)
                            (= (at 16) 58)
                            (= (at 19) 46)
                            (= (at 23) 90))
                 (return-from iso-ms nil))
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
                            cadr-core::+unix-universal-time-offset+))
                      millisecond)))))
           (parse-timestamp-value ()
             (skip-space)
             (let ((code (peek-code)))
               (cond
                 ((eql code 34)
                  (expect-code 34)
                  (let ((value-start position))
                    (loop
                      (when (>= position length)
                        (fail "Unterminated string"))
                      (when (= (aref octets position) 34)
                        (let ((value-end position)
                              (fixed (iso-ms value-start position)))
                          (incf position)
                          (return
                            (or fixed
                                (cadr-ai::copy-unescaped-json-octets
                                 octets value-start value-end)))))
                      (incf position))))
                 ((eql code 110)
                  (skip-value)
                  'null)
                 (t
                  (parse-number-value)))))
           (parse-literal-null ()
             (unless (key= position (+ position 4) "null")
               (fail "Expected null"))
             (incf position 4)
             'null)
           (scan-key ()
             (expect-code 34)
             (let ((key-start position)
                   (escaped-p nil))
               (loop
                 (when (>= position length)
                   (fail "Unterminated string"))
                 (let ((code (aref octets position)))
                   (cond
                     ((= code 34)
                      (let ((key-end position))
                        (incf position)
                        (return
                          (if escaped-p
                              (values nil nil)
                              (values key-start key-end)))))
                     ((= code 92)
                      (setf escaped-p t)
                      (incf position)
                      (let ((escape (take-code)))
                        (when (null escape)
                          (fail "Truncated escape"))
                        (when (= escape 117)
                          (when (> (+ position 4) length)
                            (fail "Truncated Unicode escape"))
                          (incf position 4))))
                     (t
                      (incf position)))))))
           (parse-arguments-object ()
             (expect-code 123)
             (skip-space)
             (when (eql (peek-code) 125)
               (take-code)
               (return-from parse-arguments-object '(:json-object)))
             (let ((pairs nil))
               (loop
                 (unless (eql (peek-code) 34)
                   (fail "Object key must be a string"))
                 (let ((key (parse-string-value)))
                   (skip-space)
                   (expect-code 58)
                   (skip-space)
                   (setf pairs (list* key (parse-generic) pairs)))
                 (skip-space)
                 (let ((code (peek-code)))
                   (cond
                     ((eql code 44)
                      (take-code)
                      (skip-space))
                     ((eql code 125)
                      (take-code)
                      (return (cons :json-object pairs)))
                     (t
                      (fail "Expected comma or }")))))))
           (finish-block (block)
             (let ((type (session-json-block-type block))
                   (primary (session-json-block-primary block))
                   (secondary (session-json-block-secondary block))
                   (extra (session-json-block-extra block)))
               (cond
                 ((or (eq type "text") (string= type "text"))
                  (cadr-ai:make-text-content
                   :text (or primary "")
                   :signature secondary))
                 ((or (eq type "thinking") (string= type "thinking"))
                  (cadr-ai:make-thinking-content
                   :thinking (or primary "")
                   :signature secondary
                   :redacted-p (eq t (getf extra :redacted))))
                 ((or (eq type "image") (string= type "image"))
                  (cadr-ai:make-image-content
                   :mime-type
                   (or (getf extra :mime-type) "image/png")
                   :data (or primary "")))
                 ((or (eq type "toolCall")
                      (string= type "toolCall")
                      (string= type "tool_call"))
                  (cadr-ai:make-tool-call
                   :id (or primary "")
                   :name (or secondary "")
                   :arguments
                   (let ((arguments (getf extra :arguments)))
                     (cond
                       ((cadr-ai::json-object-pairs-p arguments)
                        arguments)
                       ((hash-table-p arguments)
                        arguments)
                       (t '(:json-object))))
                   :thought-signature
                   (getf extra :thought-signature)))
                 (t
                  (error "Unknown content block type: ~S" type)))))
           (put-block-field (block key-start key-end)
             (let ((n (- key-end key-start))
                   (b0 (aref octets key-start)))
               (cond
                 ((and (= n 4) (= b0 116) (key= key-start key-end "type"))
                  (setf (session-json-block-type block)
                        (parse-string-value)))
                 ((and (= n 4) (= b0 116) (key= key-start key-end "text"))
                  (setf (session-json-block-primary block)
                        (parse-string-value)))
                 ((and (= n 8) (key= key-start key-end "thinking"))
                  (setf (session-json-block-primary block)
                        (parse-string-value)))
                 ((and (= n 9) (key= key-start key-end "signature"))
                  (setf (session-json-block-secondary block)
                        (parse-string-value)))
                 ((and (= n 8) (key= key-start key-end "redacted"))
                  (setf (session-json-block-extra block)
                        (list* :redacted (parse-generic)
                               (session-json-block-extra block))))
                 ((and (= n 4) (= b0 100) (key= key-start key-end "data"))
                  (setf (session-json-block-primary block)
                        (parse-string-value)))
                 ((or (and (= n 8) (key= key-start key-end "mimeType"))
                      (and (= n 9) (key= key-start key-end "mime_type")))
                  (setf (session-json-block-extra block)
                        (list* :mime-type (parse-string-value)
                               (session-json-block-extra block))))
                 ((and (= n 2) (key= key-start key-end "id"))
                  (setf (session-json-block-primary block)
                        (parse-string-value)))
                 ((and (= n 4) (= b0 110) (key= key-start key-end "name"))
                  (setf (session-json-block-secondary block)
                        (parse-string-value)))
                 ((and (= n 9) (key= key-start key-end "arguments"))
                  (skip-space)
                  (setf (session-json-block-extra block)
                        (list* :arguments
                               (if (eql (peek-code) 123)
                                   (parse-arguments-object)
                                   (parse-generic))
                               (session-json-block-extra block))))
                 ((or (and (= n 16)
                           (key= key-start key-end "thoughtSignature"))
                      (and (= n 17)
                           (key= key-start key-end "thought_signature")))
                  (setf (session-json-block-extra block)
                        (list* :thought-signature (parse-string-value)
                               (session-json-block-extra block))))
                 (t
                  (skip-value)))))
           (parse-content-block ()
             (let ((block (make-session-json-block)))
               (expect-code 123)
               (skip-space)
               (unless (eql (peek-code) 125)
                 (loop
                   (multiple-value-bind (key-start key-end)
                       (scan-key)
                     (skip-space)
                     (expect-code 58)
                     (skip-space)
                     (if key-start
                         (put-block-field block key-start key-end)
                         (skip-value)))
                   (skip-space)
                   (let ((code (peek-code)))
                     (cond
                       ((eql code 44)
                        (take-code)
                        (skip-space))
                       ((eql code 125) (return))
                       (t (fail "Expected comma or }"))))))
               (expect-code 125)
               (finish-block block)))
           (parse-content-value ()
             (skip-space)
             (let ((code (peek-code)))
               (cond
                 ((eql code 34) (parse-string-value))
                 ((eql code 110) (parse-literal-null))
                 ((eql code 91)
                  (expect-code 91)
                  (skip-space)
                  (when (eql (peek-code) 93)
                    (take-code)
                    (return-from parse-content-value nil))
                  (let ((items
                          (list
                           (if (eql (peek-code) 123)
                               (parse-content-block)
                               (parse-generic)))))
                    (loop
                      (skip-space)
                      (let ((next (peek-code)))
                        (cond
                          ((eql next 44)
                           (take-code)
                           (skip-space)
                           (push
                            (if (eql (peek-code) 123)
                                (parse-content-block)
                                (parse-generic))
                            items))
                          ((eql next 93)
                           (take-code)
                           (return (nreverse items)))
                          (t
                           (fail "Expected comma or ]")))))))
                 (t
                  (parse-generic)))))
           (put-usage-field (usage key-start key-end)
             (cond
               ((key= key-start key-end "input")
                (setf (cadr-ai:usage-input usage)
                      (or (parse-number-value) 0)))
               ((key= key-start key-end "output")
                (setf (cadr-ai:usage-output usage)
                      (or (parse-number-value) 0)))
               ((or (key= key-start key-end "cacheRead")
                    (key= key-start key-end "cache_read"))
                (setf (cadr-ai:usage-cache-read usage)
                      (or (parse-number-value) 0)))
               ((or (key= key-start key-end "cacheWrite")
                    (key= key-start key-end "cache_write"))
                (setf (cadr-ai:usage-cache-write usage)
                      (or (parse-number-value) 0)))
               ((key= key-start key-end "reasoning")
                (setf (cadr-ai:usage-reasoning usage)
                      (parse-generic)))
               ((key= key-start key-end "total")
                (setf (cadr-ai:usage-total usage)
                      (or (parse-number-value) 0)))
               ((key= key-start key-end "cost")
                (setf (cadr-ai:usage-cost usage)
                      (if (eql (peek-code) 123)
                          (parse-cost)
                          (cadr-ai:make-cost))))
               (t
                (skip-value))))
           (put-cost-field (cost key-start key-end)
             (let ((amount
                     (coerce (or (parse-number-value) 0) 'double-float)))
               (cond
                 ((key= key-start key-end "input")
                  (setf (cadr-ai:cost-input cost) amount))
                 ((key= key-start key-end "output")
                  (setf (cadr-ai:cost-output cost) amount))
                 ((or (key= key-start key-end "cacheRead")
                      (key= key-start key-end "cache_read"))
                  (setf (cadr-ai:cost-cache-read cost) amount))
                 ((or (key= key-start key-end "cacheWrite")
                      (key= key-start key-end "cache_write"))
                  (setf (cadr-ai:cost-cache-write cost) amount))
                 ((key= key-start key-end "total")
                  (setf (cadr-ai:cost-total cost) amount))
                 (t
                  nil))))
           (parse-cost ()
             (let ((cost (cadr-ai:make-cost)))
               (expect-code 123)
               (skip-space)
               (unless (eql (peek-code) 125)
                 (loop
                   (multiple-value-bind (key-start key-end)
                       (scan-key)
                     (skip-space)
                     (expect-code 58)
                     (skip-space)
                     (if key-start
                         (put-cost-field cost key-start key-end)
                         (skip-value)))
                   (skip-space)
                   (let ((code (peek-code)))
                     (cond
                       ((eql code 44)
                        (take-code)
                        (skip-space))
                       ((eql code 125) (return))
                       (t (fail "Expected comma or }"))))))
               (expect-code 125)
               cost))
           (parse-usage ()
             (let ((usage (cadr-ai:make-usage)))
               (expect-code 123)
               (skip-space)
               (unless (eql (peek-code) 125)
                 (loop
                   (multiple-value-bind (key-start key-end)
                       (scan-key)
                     (skip-space)
                     (expect-code 58)
                     (skip-space)
                     (if key-start
                         (put-usage-field usage key-start key-end)
                         (skip-value)))
                   (skip-space)
                   (let ((code (peek-code)))
                     (cond
                       ((eql code 44)
                        (take-code)
                        (skip-space))
                       ((eql code 125) (return))
                       (t (fail "Expected comma or }"))))))
               (expect-code 125)
               usage))
           (keep-extra (bag key value)
             (when value
               (setf (session-json-message-extra bag)
                     (list* key value
                            (session-json-message-extra bag)))))
           (put-message-field (bag key-start key-end)
             (let ((n (- key-end key-start))
                   (b0 (aref octets key-start)))
               (cond
                 ((and (= n 4) (key= key-start key-end "role"))
                  (setf (session-json-message-role bag)
                        (parse-string-value)))
                 ((and (= n 4) (= b0 116) (key= key-start key-end "type"))
                  (if (session-json-message-role bag)
                      (skip-value)
                      (setf (session-json-message-role bag)
                            (parse-string-value))))
                 ((and (= n 9) (key= key-start key-end "timestamp"))
                  (setf (session-json-message-timestamp bag)
                        (parse-timestamp-value)))
                 ((and (= n 7) (key= key-start key-end "content"))
                  (setf (session-json-message-content bag)
                        (parse-content-value)))
                 ((and (= n 3) (key= key-start key-end "api"))
                  (keep-extra bag :api (parse-string-value)))
                 ((and (= n 8) (key= key-start key-end "provider"))
                  (keep-extra bag :provider (parse-string-value)))
                 ((and (= n 5) (= b0 109) (key= key-start key-end "model"))
                  (keep-extra bag :model (parse-string-value)))
                 ((and (= n 5) (= b0 117) (key= key-start key-end "usage"))
                  (skip-space)
                  (setf (session-json-message-usage bag)
                        (if (eql (peek-code) 123)
                            (parse-usage)
                            (parse-generic))))
                 ((or (and (= n 10) (key= key-start key-end "stopReason"))
                      (and (= n 11) (key= key-start key-end "stop_reason")))
                  (keep-extra bag :stop-reason (parse-string-value)))
                 ((or (and (= n 10) (key= key-start key-end "responseId"))
                      (and (= n 11) (key= key-start key-end "response_id")))
                  (keep-extra bag :response-id (parse-string-value)))
                 ((or (and (= n 14)
                           (key= key-start key-end "rawStopReason"))
                      (and (= n 15)
                           (key= key-start key-end "raw_stop_reason")))
                  (keep-extra bag :raw-stop-reason (parse-string-value)))
                 ((or (and (= n 12)
                           (key= key-start key-end "errorMessage"))
                      (and (= n 13)
                           (key= key-start key-end "error_message")))
                  (keep-extra bag :error-message (parse-string-value)))
                 ((and (= n 12) (key= key-start key-end "diagnostics"))
                  (keep-extra bag :diagnostics (parse-generic)))
                 ((or (and (= n 10) (key= key-start key-end "toolCallId"))
                      (and (= n 11) (key= key-start key-end "tool_call_id")))
                  (keep-extra bag :tool-call-id (parse-string-value)))
                 ((or (and (= n 8) (key= key-start key-end "toolName"))
                      (and (= n 9) (key= key-start key-end "tool_name")))
                  (keep-extra bag :tool-name (parse-string-value)))
                 ((or (and (= n 7) (key= key-start key-end "isError"))
                      (and (= n 8) (key= key-start key-end "is_error")))
                  (keep-extra bag :is-error (parse-generic)))
                 ((and (= n 7) (key= key-start key-end "details"))
                  (keep-extra bag :details (parse-generic)))
                 ((and (= n 7) (key= key-start key-end "command"))
                  (keep-extra bag :command (parse-string-value)))
                 ((and (= n 6) (key= key-start key-end "output"))
                  (keep-extra bag :output (parse-string-value)))
                 ((or (and (= n 8) (key= key-start key-end "exitCode"))
                      (and (= n 9) (key= key-start key-end "exit_code")))
                  (keep-extra bag :exit-code (parse-number-value)))
                 ((and (= n 9) (key= key-start key-end "cancelled"))
                  (keep-extra bag :cancelled (parse-generic)))
                 ((and (= n 9) (key= key-start key-end "truncated"))
                  (keep-extra bag :truncated (parse-generic)))
                 ((or (and (= n 14)
                           (key= key-start key-end "fullOutputPath"))
                      (and (= n 16)
                           (key= key-start key-end "full_output_path")))
                  (keep-extra bag :full-output-path (parse-string-value)))
                 ((or (and (= n 18)
                           (key= key-start key-end "excludeFromContext"))
                      (and (= n 20)
                           (key= key-start key-end
                                "exclude_from_context")))
                  (keep-extra bag :exclude-from-context (parse-generic)))
                 (t
                  (skip-value)))))
           (parse-message ()
             (let ((bag (make-session-json-message)))
               (expect-code 123)
               (skip-space)
               (unless (eql (peek-code) 125)
                 (loop
                   (multiple-value-bind (key-start key-end)
                       (scan-key)
                     (skip-space)
                     (expect-code 58)
                     (skip-space)
                     (if key-start
                         (put-message-field bag key-start key-end)
                         (skip-value)))
                   (skip-space)
                   (let ((code (peek-code)))
                     (cond
                       ((eql code 44)
                        (take-code)
                        (skip-space))
                       ((eql code 125) (return))
                       (t (fail "Expected comma or }"))))))
               (expect-code 125)
               bag))
           (put-entry-field (key-start key-end)
             (let ((n (- key-end key-start))
                   (b0 (aref octets key-start)))
               (cond
                 ((and (= n 4) (= b0 116) (key= key-start key-end "type"))
                  (setf (session-entry-type entry)
                        (parse-string-value)))
                 ((and (= n 2) (key= key-start key-end "id"))
                  (setf (session-entry-id entry)
                        (parse-string-value)))
                 ((and (= n 8) (key= key-start key-end "parentId"))
                  (mark-session-seen entry +session-seen-parent-id+)
                  (skip-space)
                  (setf (session-entry-parent-id entry)
                        (if (eql (peek-code) 110)
                            (parse-literal-null)
                            (parse-string-value))))
                 ((and (= n 9) (key= key-start key-end "timestamp"))
                  (setf (session-entry-timestamp entry)
                        (parse-timestamp-value)))
                 ((and (= n 7) (= b0 109) (key= key-start key-end "message"))
                  (skip-space)
                  (setf (session-entry-message entry)
                        (if (eql (peek-code) 123)
                            (parse-message)
                            (parse-generic))))
                 ((and (= n 7) (= b0 115) (key= key-start key-end "summary"))
                  (setf (session-entry-summary entry)
                        (parse-string-value)))
                 ((and (= n 9) (key= key-start key-end "sourceIds"))
                  (setf (session-entry-source-ids entry)
                        (parse-generic)))
                 ((and (= n 16)
                       (key= key-start key-end "firstKeptEntryId"))
                  (setf (session-entry-first-kept-id entry)
                        (parse-string-value)))
                 ((and (= n 12) (key= key-start key-end "tokensBefore"))
                  (mark-session-seen entry +session-seen-tokens-before+)
                  (setf (session-entry-tokens-before entry)
                        (parse-number-value)))
                 ((and (= n 13) (key= key-start key-end "thinkingLevel"))
                  (setf (session-entry-thinking-level entry)
                        (parse-string-value)))
                 ((and (= n 8) (key= key-start key-end "provider"))
                  (setf (session-entry-provider entry)
                        (parse-string-value)))
                 ((and (= n 7) (= b0 109) (key= key-start key-end "modelId"))
                  (setf (session-entry-model-id entry)
                        (parse-string-value)))
                 ((and (= n 15)
                       (key= key-start key-end "activeToolNames"))
                  (setf (session-entry-active-tool-names entry)
                        (parse-generic)))
                 ((and (= n 6) (key= key-start key-end "fromId"))
                  (setf (session-entry-from-id entry)
                        (parse-string-value)))
                 ((and (= n 8) (key= key-start key-end "fromHook"))
                  (setf (session-entry-from-hook-p entry)
                        (eq t (parse-generic))))
                 ((and (= n 7) (= b0 100) (key= key-start key-end "details"))
                  (setf (session-entry-details entry)
                        (parse-generic)))
                 ((and (= n 5) (key= key-start key-end "usage"))
                  (skip-space)
                  (setf (session-entry-usage entry)
                        (if (eql (peek-code) 123)
                            (parse-usage)
                            (parse-generic))))
                 ((and (= n 10) (key= key-start key-end "customType"))
                  (setf (session-entry-custom-type entry)
                        (parse-string-value)))
                 ((and (= n 4) (= b0 100) (key= key-start key-end "data"))
                  (setf (session-entry-data entry)
                        (parse-generic)))
                 ((and (= n 7) (= b0 99) (key= key-start key-end "content"))
                  (mark-session-seen entry +session-seen-content+)
                  (setf (session-entry-content entry)
                        (parse-content-value)))
                 ((and (= n 7) (= b0 100) (key= key-start key-end "display"))
                  (setf (session-entry-display-p entry)
                        (eq t (parse-generic))))
                 ((and (= n 8) (key= key-start key-end "targetId"))
                  (mark-session-seen entry +session-seen-target-id+)
                  (setf (session-entry-target-id entry)
                        (parse-string-value)))
                 ((and (= n 5) (= b0 108) (key= key-start key-end "label"))
                  (setf (session-entry-label entry)
                        (parse-string-value)))
                 ((and (= n 4) (= b0 110) (key= key-start key-end "name"))
                  (setf (session-entry-name entry)
                        (parse-string-value)))
                 ((and (= n 12) (key= key-start key-end "retainedTail"))
                  (setf (session-entry-retained-tail entry)
                        (parse-generic)))
                 (t
                  (skip-value))))))
        (skip-space)
        (expect-code 123)
        (skip-space)
        (unless (eql (peek-code) 125)
          (loop
            (multiple-value-bind (key-start key-end)
                (scan-key)
              (skip-space)
              (expect-code 58)
              (skip-space)
              (if key-start
                  (put-entry-field key-start key-end)
                  (skip-value)))
            (skip-space)
            (let ((code (peek-code)))
              (cond
                ((eql code 44)
                 (take-code)
                 (skip-space))
                ((eql code 125) (return))
                (t (fail "Expected comma or }"))))))
        (expect-code 125)
        (skip-space)
        (unless (= position length)
          (fail "Trailing input"))
        entry))))

(defun parse-session-record (line &optional (start 0) end octet-p)
  (when octet-p
    (return-from parse-session-record
      (parse-session-record-octets line start end)))
  (let ((entry (make-session-entry)))
    (labels
        ((usage-or-hash (value)
           (cond
             ((or (null value)
                  (cadr-ai::json-null-p value))
              nil)
             ((typep value 'cadr-ai:usage) value)
             ((hash-table-p value)
              (usage-from-json value))
             (t value)))
         (put-cost-field (cost field value)
           (let ((amount (coerce (or value 0) 'double-float)))
             (cond
               ((or (eq field "input") (string= field "input"))
                (setf (cadr-ai:cost-input cost) amount))
               ((or (eq field "output") (string= field "output"))
                (setf (cadr-ai:cost-output cost) amount))
               ((or (eq field "cacheRead")
                    (string= field "cacheRead")
                    (string= field "cache_read"))
                (setf (cadr-ai:cost-cache-read cost) amount))
               ((or (eq field "cacheWrite")
                    (string= field "cacheWrite")
                    (string= field "cache_write"))
                (setf (cadr-ai:cost-cache-write cost) amount))
               ((or (eq field "total") (string= field "total"))
                (setf (cadr-ai:cost-total cost) amount)))))
         (visit-cost ()
           (let ((cost (cadr-ai:make-cost)))
             (values
              (lambda (field value)
                (put-cost-field cost field value))
              (lambda () cost))))
         (put-usage-field (usage field value)
           (cond
             ((or (eq field "input") (string= field "input"))
              (setf (cadr-ai:usage-input usage) (or value 0)))
             ((or (eq field "output") (string= field "output"))
              (setf (cadr-ai:usage-output usage) (or value 0)))
             ((or (eq field "cacheRead")
                  (string= field "cacheRead")
                  (string= field "cache_read"))
              (setf (cadr-ai:usage-cache-read usage) (or value 0)))
             ((or (eq field "cacheWrite")
                  (string= field "cacheWrite")
                  (string= field "cache_write"))
              (setf (cadr-ai:usage-cache-write usage)
                    (or value 0)))
             ((or (eq field "reasoning")
                  (string= field "reasoning"))
              (setf (cadr-ai:usage-reasoning usage) value))
             ((or (eq field "total") (string= field "total"))
              (setf (cadr-ai:usage-total usage) (or value 0)))
             ((or (eq field "cost") (string= field "cost"))
              (setf (cadr-ai:usage-cost usage)
                    (cond
                      ((typep value 'cadr-ai:cost) value)
                      ((hash-table-p value)
                       (cadr-ai:make-cost
                        :input (usage-cost-amount value "input")
                        :output (usage-cost-amount value "output")
                        :cache-read
                        (usage-cost-amount
                         value "cacheRead" "cache_read")
                        :cache-write
                        (usage-cost-amount
                         value "cacheWrite" "cache_write")
                        :total
                        (usage-cost-amount value "total")))
                      (t (cadr-ai:make-cost)))))))
         (visit-usage ()
           (let ((usage (cadr-ai:make-usage)))
             (values
              (lambda (field value)
                (put-usage-field usage field value))
              (lambda () usage))))
         (keep-extra (bag key value)
           (when value
             (setf (session-json-message-extra bag)
                   (list* key value
                          (session-json-message-extra bag)))))
         (put-message-field (bag field value)
           (when (plusp (length field))
             (case (char field 0)
               (#\r
                (cond
                  ((or (eq field "role") (string= field "role"))
                   (setf (session-json-message-role bag) value))
                  ((or (eq field "responseId")
                       (string= field "responseId")
                       (string= field "response_id"))
                   (keep-extra bag :response-id value))
                  ((or (eq field "rawStopReason")
                       (string= field "rawStopReason")
                       (string= field "raw_stop_reason"))
                   (keep-extra bag :raw-stop-reason value))))
               (#\t
                (cond
                  ((or (eq field "type") (string= field "type"))
                   (unless (session-json-message-role bag)
                     (setf (session-json-message-role bag) value)))
                  ((or (eq field "timestamp")
                       (string= field "timestamp"))
                   (setf (session-json-message-timestamp bag)
                         value))
                  ((or (eq field "toolCallId")
                       (string= field "toolCallId")
                       (string= field "tool_call_id"))
                   (keep-extra bag :tool-call-id value))
                  ((or (eq field "toolName")
                       (string= field "toolName")
                       (string= field "tool_name"))
                   (keep-extra bag :tool-name value))
                  ((or (eq field "truncated")
                       (string= field "truncated"))
                   (keep-extra bag :truncated value))))
               (#\c
                (cond
                  ((or (eq field "content")
                       (string= field "content"))
                   (setf (session-json-message-content bag) value))
                  ((or (eq field "command")
                       (string= field "command"))
                   (keep-extra bag :command value))
                  ((or (eq field "cancelled")
                       (string= field "cancelled"))
                   (keep-extra bag :cancelled value))))
               (#\a
                (when (or (eq field "api") (string= field "api"))
                  (keep-extra bag :api value)))
               (#\p
                (when (or (eq field "provider")
                          (string= field "provider"))
                  (keep-extra bag :provider value)))
               (#\m
                (when (or (eq field "model") (string= field "model"))
                  (keep-extra bag :model value)))
               (#\u
                (when (or (eq field "usage") (string= field "usage"))
                  (setf (session-json-message-usage bag)
                        (usage-or-hash value))))
               (#\s
                (when (or (eq field "stopReason")
                          (string= field "stopReason")
                          (string= field "stop_reason"))
                  (keep-extra bag :stop-reason value)))
               (#\e
                (cond
                  ((or (eq field "errorMessage")
                       (string= field "errorMessage")
                       (string= field "error_message"))
                   (keep-extra bag :error-message value))
                  ((or (eq field "exitCode")
                       (string= field "exitCode")
                       (string= field "exit_code"))
                   (keep-extra bag :exit-code value))
                  ((or (eq field "excludeFromContext")
                       (string= field "excludeFromContext")
                       (string= field "exclude_from_context"))
                   (keep-extra bag :exclude-from-context value))))
               (#\d
                (cond
                  ((or (eq field "diagnostics")
                       (string= field "diagnostics"))
                   (keep-extra bag :diagnostics value))
                  ((or (eq field "details")
                       (string= field "details"))
                   (keep-extra bag :details value))))
               (#\i
                (when (or (eq field "isError")
                          (string= field "isError")
                          (string= field "is_error"))
                  (keep-extra bag :is-error value)))
               (#\o
                (when (or (eq field "output")
                          (string= field "output"))
                  (keep-extra bag :output value)))
               (#\f
                (when (or (eq field "fullOutputPath")
                          (string= field "fullOutputPath")
                          (string= field "full_output_path"))
                  (keep-extra bag :full-output-path value))))))
         (visit-message ()
           (let ((bag (make-session-json-message)))
             (values
              (lambda (field value)
                (put-message-field bag field value))
              (lambda () bag))))
         (keep-block-extra (block key value)
           (when value
             (setf (session-json-block-extra block)
                   (list* key value
                          (session-json-block-extra block)))))
         (put-block-field (block field value)
           (when (plusp (length field))
             (case (char field 0)
               (#\t
                (cond
                  ((or (eq field "type") (string= field "type"))
                   (setf (session-json-block-type block) value))
                  ((or (eq field "text") (string= field "text"))
                   (setf (session-json-block-primary block) value))
                  ((or (eq field "thinking")
                       (string= field "thinking"))
                   (setf (session-json-block-primary block) value))
                  ((or (eq field "thoughtSignature")
                       (string= field "thoughtSignature")
                       (string= field "thought_signature"))
                   (keep-block-extra
                    block :thought-signature value))))
               (#\s
                (when (or (eq field "signature")
                          (string= field "signature"))
                  (setf (session-json-block-secondary block)
                        value)))
               (#\r
                (when (or (eq field "redacted")
                          (string= field "redacted"))
                  (keep-block-extra block :redacted value)))
               (#\d
                (when (or (eq field "data") (string= field "data"))
                  (setf (session-json-block-primary block) value)))
               (#\m
                (when (or (eq field "mimeType")
                          (string= field "mimeType")
                          (string= field "mime_type"))
                  (keep-block-extra block :mime-type value)))
               (#\i
                (when (or (eq field "id") (string= field "id"))
                  (setf (session-json-block-primary block) value)))
               (#\n
                (when (or (eq field "name") (string= field "name"))
                  (setf (session-json-block-secondary block)
                        value)))
               (#\a
                (when (or (eq field "arguments")
                          (string= field "arguments"))
                  (keep-block-extra block :arguments value))))))
         (finish-content-block (block)
           (let ((type (session-json-block-type block))
                 (primary (session-json-block-primary block))
                 (secondary (session-json-block-secondary block))
                 (extra (session-json-block-extra block)))
             (cond
               ((string= type "text")
                (cadr-ai:make-text-content
                 :text (or primary "")
                 :signature secondary))
               ((string= type "thinking")
                (cadr-ai:make-thinking-content
                 :thinking (or primary "")
                 :signature secondary
                 :redacted-p (eq t (getf extra :redacted))))
               ((string= type "image")
                (cadr-ai:make-image-content
                 :mime-type
                 (or (getf extra :mime-type) "image/png")
                 :data (or primary "")))
               ((member type '("toolCall" "tool_call")
                        :test #'string=)
                (cadr-ai:make-tool-call
                 :id (or primary "")
                 :name (or secondary "")
                 :arguments
                 (let ((arguments (getf extra :arguments)))
                   (cond
                     ((cadr-ai::json-object-pairs-p arguments)
                      arguments)
                     ((hash-table-p arguments)
                      arguments)
                     (t '(:json-object))))
                 :thought-signature
                 (getf extra :thought-signature)))
               (t
                (error "Unknown content block type: ~S" type)))))
         (visit-content-block ()
           (let ((block (make-session-json-block)))
             (values
              (lambda (field value)
                (put-block-field block field value))
              (lambda ()
                (finish-content-block block)))))
         (visit-arguments ()
           (let ((pairs nil))
             (values
              (lambda (field value)
                (setf pairs (list* field value pairs)))
              (lambda ()
                (cons :json-object pairs)))))
         (nest (key)
           (cond
             ((or (eq key "message") (string= key "message"))
              (visit-message))
             ((or (eq key "usage") (string= key "usage"))
              (visit-usage))
             ((or (eq key "cost") (string= key "cost"))
              (visit-cost))
             ((or (eq key "arguments") (string= key "arguments"))
              (visit-arguments))
             ((or (eq key "content") (string= key "content"))
              (values #'visit-content-block nil :array)))))
      (if octet-p
          (cadr-ai::parse-json-octets
           line
           (lambda (key value)
             (session-record-put entry key value))
           #'nest
           start
           end)
          (cadr-ai::parse-json-object-fields
           line
           (lambda (key value)
             (session-record-put entry key value))
           #'nest
           start
           end)))
    entry))

(defun parse-session-line
    (line path line-number &key raw-hash-p (start 0) end octet-p)
  (handler-case
      (cond
        (raw-hash-p
         (if octet-p
             (cadr-ai::parse-json-octets line nil nil start end)
             (cadr-ai::parse-json-source line nil nil start end)))
        (t
         (parse-session-record line start end octet-p)))
    (error (cause)
      (session-failure
       path line-number
       "Invalid session JSON at line ~D: ~A"
       line-number cause))))

(defun session-header-ref (object key &optional default)
  (if (session-file-header-p object)
      (cond
        ((string= key "type")
         (or (session-file-header-type object) default))
        ((string= key "version")
         (or (session-file-header-version object) default))
        ((string= key "id")
         (or (session-file-header-id object) default))
        ((string= key "timestamp")
         (or (session-file-header-timestamp object) default))
        ((string= key "cwd")
         (or (session-file-header-cwd object) default))
        ((string= key "parentSession")
         (let ((parent (session-file-header-parent-session object)))
           (if (null parent)
               default
               parent)))
        (t default))
      (cadr-ai::json-get object key default)))

(defun session-file-header-to-hash (header)
  (let ((object
          (cadr-ai::json-object
           "type" (session-file-header-type header)
           "version" (session-file-header-version header)
           "id" (session-file-header-id header)
           "timestamp" (session-file-header-timestamp header)
           "cwd" (session-file-header-cwd header))))
    (let ((parent (session-file-header-parent-session header)))
      (when parent
        (cadr-ai::json-put object "parentSession" parent)))
    (loop for (key value) on (session-file-header-extra header) by #'cddr
          do (cadr-ai::json-put object key value))
    object))

(defun parse-session-header-octets (octets start end)
  ;; First JSONL line fills session-file-header.  Visitor walk,
  ;; not EQUAL hash.  Not intern.  Not FFI.
  (let ((header (make-session-file-header)))
    (cadr-ai::parse-json-octets
     octets
     (lambda (key value)
       (cond
         ((string= key "type")
          (setf (session-file-header-type header) value))
         ((string= key "version")
          (setf (session-file-header-version header) value))
         ((string= key "id")
          (setf (session-file-header-id header) value))
         ((string= key "timestamp")
          (setf (session-file-header-timestamp header) value))
         ((string= key "cwd")
          (setf (session-file-header-cwd header) value))
         ((string= key "parentSession")
          (setf (session-file-header-parent-session header) value))
         (t
          (setf (session-file-header-extra header)
                (list* key value
                       (session-file-header-extra header))))))
     nil
     start
     end)
    header))

(defun validate-session-header (object path)
  (unless (or (session-file-header-p object)
              (hash-table-p object))
    (session-failure path 1 "Invalid session header"))
  (let ((version (session-header-ref object "version" 1)))
    (unless
        (and (string= "session"
                      (session-header-ref object "type"))
             (member version '(1 2 3))
             (stringp (session-header-ref object "id"))
             (or
              (integerp
               (session-header-ref object "timestamp"))
              (stringp
               (session-header-ref object "timestamp")))
             (stringp (session-header-ref object "cwd")))
      (session-failure path 1 "Invalid session header")))
  object)

(defun read-session-objects (path)
  ;; Pairing counterpart of Node 1MiB readSync: one octet
  ;; READ-SEQUENCE per chunk, then split on LF.  Files that
  ;; fit the cap are one exact-size read.  ASCII lines reuse
  ;; one simple-base-string and parse a START/END window.
  ;; JSONL newlines are UTF-8 boundaries.  Not intern.  Not 7b.
  (let ((objects nil)
        (line-number 0)
        (header nil)
        (raw-hash-p t))
    (labels
        ((blank-octets-p (octets start end)
           (loop for index from start below end
                 for unit = (aref octets index)
                 always
                 (or (= unit 32)
                     (= unit 9)
                     (= unit 13)
                     (= unit 10))))
         (consume-line (octets start end)
           (incf line-number)
           (unless (blank-octets-p octets start end)
             (let ((object
                     (handler-case
                         (if (null header)
                             (parse-session-header-octets
                              octets start end)
                             (parse-session-line
                              octets path line-number
                              :raw-hash-p raw-hash-p
                              :start start
                              :end end
                              :octet-p t))
                       (session-error () nil)
                       (cadr-ai::json-parse-error () nil))))
               (when object
                 (unless header
                   (setf header object)
                   (setf raw-hash-p
                         (let ((version
                                 (session-header-ref
                                  object "version" 1)))
                           (or (not (integerp version))
                               (< version 3)))))
                 (push object objects)))))
         (scan-buffer (buffer count pending)
           (let ((start 0))
             (declare (type fixnum start count)
                      (type (simple-array (unsigned-byte 8) (*))
                            buffer))
             (loop
               (let ((lf (octet-find-lf buffer start count)))
                 (unless lf
                   (cond
                     ((null pending)
                      (when (< start count)
                        (consume-line buffer start count)))
                     ((< start count)
                      (loop for copy of-type fixnum
                            from start below count
                            do (vector-push-extend
                                (aref buffer copy) pending))))
                   (return))
                 (cond
                   ((or (null pending)
                        (zerop (fill-pointer pending)))
                    (consume-line buffer start lf))
                   (t
                    (loop for copy of-type fixnum
                          from start below lf
                          do (vector-push-extend
                              (aref buffer copy) pending))
                    (consume-line
                     pending 0 (fill-pointer pending))
                    (setf (fill-pointer pending) 0)))
                 (setf start (1+ lf))))))
         (read-all (stream)
           (let* ((known (ignore-errors (file-length stream)))
                  (cap +max-session-header-scan-bytes+))
             (cond
               ((and (integerp known) (<= known cap))
                (let* ((size (max known 0))
                       (chunk
                         (make-array
                          size
                          :element-type '(unsigned-byte 8))))
                  (when (plusp size)
                    (scan-buffer
                     chunk (read-sequence chunk stream) nil))))
               (t
                (let ((chunk
                        (make-array
                         cap
                         :element-type '(unsigned-byte 8)))
                      (pending
                        (make-array
                         256
                         :element-type '(unsigned-byte 8)
                         :adjustable t
                         :fill-pointer 0)))
                  (loop
                    (let ((count (read-sequence chunk stream)))
                      (declare (type fixnum count))
                      (cond
                        ((zerop count)
                         (when (plusp (fill-pointer pending))
                           (consume-line
                            pending 0 (fill-pointer pending)))
                         (return))
                        (t
                         (scan-buffer
                          chunk count pending)))))))))))
      (handler-case
          (with-open-file
              (stream path
                      :direction :input
                      :element-type '(unsigned-byte 8))
            (read-all stream))
        (session-error (condition)
          (error condition))
        (error (cause)
          (session-failure
           path line-number "Cannot load session: ~A" cause)))
      (unless objects
        (session-failure path 1 "Session file has no header"))
      (nreverse objects))))

(defun migrate-v1-session-objects (objects)
  (let ((by-id (make-hash-table :test #'equal))
        (parent-id nil))
    (cadr-ai::json-put (first objects) "version" 2)
    (loop for object in (rest objects)
          do
      (let ((id (make-session-entry-id by-id)))
        (cadr-ai::json-put object "id" id)
        (cadr-ai::json-put object "parentId" parent-id)
        (setf (gethash id by-id) t
              parent-id id))
      (when
          (and
           (string=
            "compaction"
            (cadr-ai::json-get object "type"))
           (integerp
            (cadr-ai::json-get
             object "firstKeptEntryIndex")))
        (let* ((index
                 (cadr-ai::json-get
                  object "firstKeptEntryIndex"))
               (target
                 (nth index objects)))
          (when
              (and
               target
               (not
                (string=
                 "session"
                 (cadr-ai::json-get target "type"))))
            (cadr-ai::json-put
             object "firstKeptEntryId"
             (cadr-ai::json-get target "id")))
          (remhash "firstKeptEntryIndex" object))))
  objects))

(defun migrate-v2-session-objects (objects)
  (cadr-ai::json-put (first objects) "version" 3)
  (dolist (object (rest objects))
    (when
        (string=
         "message"
         (cadr-ai::json-get object "type"))
      (let ((message
              (cadr-ai::json-get object "message")))
        (when
            (and
             (hash-table-p message)
             (string=
              "hookMessage"
              (or
               (cadr-ai::json-get message "role")
               "")))
          (cadr-ai::json-put
           message "role" "custom")))))
  objects)

(defun persist-migrated-session (objects path)
  (cadr-core:call-with-atomic-output-file
   path
   (lambda (stream)
     (dolist (object objects)
       (write-jsonl-object stream object)))
   :durability :flush))

(defun vector-of-strings-p (value)
  (and (vectorp value)
       (every #'stringp value)))

(defun json-null-to-nil (value)
  (if (cadr-ai::json-null-p value)
      nil
      value))

(defun session-entry-from-hash (object)
  (let ((entry (make-session-entry)))
    (maphash
     (lambda (key value)
       (session-record-put entry key value))
     object)
    entry))

(defun require-session-slot (value name path line-number)
  (when (null value)
    (session-failure
     path line-number
     "Session record is missing ~A" name))
  value)

(defun session-type-keyword (raw)
  ;; Closed session record types.  Avoids SUBSTITUTE + STRING-UPCASE
  ;; + INTERN on every load-session line.  Not JSON intern expand.
  (cond
    ((keywordp raw) raw)
    ((or (eq raw "message") (string= raw "message")) :message)
    ((or (eq raw "model_change") (string= raw "model_change"))
     :model-change)
    ((or (eq raw "thinking_level_change")
         (string= raw "thinking_level_change"))
     :thinking-level-change)
    ((or (eq raw "active_tools_change")
         (string= raw "active_tools_change"))
     :active-tools-change)
    ((or (eq raw "compaction") (string= raw "compaction"))
     :compaction)
    ((or (eq raw "branch_summary") (string= raw "branch_summary"))
     :branch-summary)
    ((or (eq raw "custom") (string= raw "custom")) :custom)
    ((or (eq raw "custom_message") (string= raw "custom_message"))
     :custom-message)
    ((or (eq raw "label") (string= raw "label")) :label)
    ((or (eq raw "session_info") (string= raw "session_info"))
     :session-info)
    ((or (eq raw "leaf") (string= raw "leaf")) :leaf)
    ((stringp raw)
     (intern
      (string-upcase (substitute #\- #\_ raw))
      "KEYWORD"))
    (t raw)))

(defun finalize-session-entry
    (entry path line-number by-id)
  (let* ((type (session-type-keyword (session-entry-type entry)))
         (id (session-entry-id entry))
         (parent-id
           (progn
             (unless (session-seen-p
                      entry +session-seen-parent-id+)
               (session-failure
                path line-number
                "Session record is missing parentId"))
             (json-null-to-nil
              (session-entry-parent-id entry))))
         (timestamp-value
           (require-session-slot
            (session-entry-timestamp entry)
            "timestamp" path line-number))
         (timestamp
           (handler-case
               (iso8601-to-milliseconds timestamp-value)
             (error (cause)
               (session-failure
                path line-number
                "Invalid session timestamp at line ~D: ~A"
                line-number cause)))))
    (unless
        (and
         (member
          type
          '(:message
            :thinking-level-change
            :model-change
            :active-tools-change
            :compaction
            :branch-summary
            :custom
            :custom-message
            :label
            :session-info
            :leaf))
         (stringp id)
         (or (null parent-id)
             (stringp parent-id)))
      (session-failure
       path line-number
       "Invalid session record at line ~D" line-number))
    (when (gethash id by-id)
      (session-failure
       path line-number "Duplicate session entry id: ~A" id))
    (when (and parent-id
               (not (gethash parent-id by-id)))
      (session-failure
       path line-number
       "Missing or forward session parent: ~A" parent-id))
    (setf (session-entry-type entry) type
          (session-entry-parent-id entry) parent-id
          (session-entry-timestamp entry) timestamp)
    (let ((usage-object (session-entry-usage entry)))
      (case type
        (:message
         (setf
          (session-entry-message entry)
          (message-from-json
           (require-session-slot
            (session-entry-message entry)
            "message" path line-number))))
        (:thinking-level-change
         (let ((value
                 (require-session-slot
                  (session-entry-thinking-level entry)
                  "thinkingLevel" path line-number)))
           (unless (stringp value)
             (session-failure
              path line-number
              "Invalid thinking level entry at line ~D"
              line-number))))
        (:model-change
         (let ((provider
                 (require-session-slot
                  (session-entry-provider entry)
                  "provider" path line-number))
               (model-id
                 (require-session-slot
                  (session-entry-model-id entry)
                  "modelId" path line-number)))
           (unless (and (stringp provider)
                        (stringp model-id))
             (session-failure
              path line-number
              "Invalid model change entry at line ~D"
              line-number))))
        (:active-tools-change
         (let ((names
                 (require-session-slot
                  (session-entry-active-tool-names entry)
                  "activeToolNames" path line-number)))
           (unless (vector-of-strings-p names)
             (session-failure
              path line-number
              "Invalid active tools entry at line ~D"
              line-number))
           (setf
            (session-entry-active-tool-names entry)
            (coerce names 'list))))
        (:compaction
         (let* ((summary
                  (require-session-slot
                   (session-entry-summary entry)
                   "summary" path line-number))
                (source-ids
                  (or
                   (session-entry-source-ids entry)
                   #()))
                (first-kept-id
                  (require-session-slot
                   (session-entry-first-kept-id entry)
                   "firstKeptEntryId" path line-number))
                (tokens-before
                  (progn
                    (unless
                        (session-seen-p
                         entry
                         +session-seen-tokens-before+)
                      (session-failure
                       path line-number
                       "Session record is missing tokensBefore"))
                    (session-entry-tokens-before entry))))
           (unless
               (and
                (stringp summary)
                (vector-of-strings-p source-ids)
                (stringp first-kept-id)
                (integerp tokens-before)
                (not (minusp tokens-before))
                (gethash first-kept-id by-id)
                (every
                 (lambda (source-id)
                   (gethash source-id by-id))
                 source-ids))
             (session-failure
              path line-number
              "Invalid compaction record at line ~D"
              line-number))
           (setf
            (session-entry-source-ids entry)
            (coerce source-ids 'list)
            (session-entry-tokens-before entry)
            tokens-before
            (session-entry-usage entry)
            (and usage-object
                 (if (hash-table-p usage-object)
                     (usage-from-json usage-object)
                     usage-object))
            (session-entry-retained-tail entry)
            (let ((tail
                    (session-entry-retained-tail entry)))
              (and
               (vectorp tail)
               (loop for message across tail
                     collect
                     (message-from-json
                      message)))))))
        (:branch-summary
         (let ((from-id
                 (require-session-slot
                  (session-entry-from-id entry)
                  "fromId" path line-number))
               (summary
                 (require-session-slot
                  (session-entry-summary entry)
                  "summary" path line-number)))
           (unless
               (and
                (stringp from-id)
                (or
                 (string= from-id "root")
                 (gethash from-id by-id))
                (stringp summary))
             (session-failure
              path line-number
              "Invalid branch summary at line ~D"
              line-number))
           (setf
            (session-entry-usage entry)
            (and usage-object
                 (if (hash-table-p usage-object)
                     (usage-from-json usage-object)
                     usage-object)))))
        (:custom
         (let ((custom-type
                 (require-session-slot
                  (session-entry-custom-type entry)
                  "customType" path line-number)))
           (unless (stringp custom-type)
             (session-failure
              path line-number
              "Invalid custom entry at line ~D"
              line-number))))
        (:custom-message
         (let ((custom-type
                 (require-session-slot
                  (session-entry-custom-type entry)
                  "customType" path line-number))
               (content
                 (progn
                   (unless
                       (session-seen-p
                        entry +session-seen-content+)
                     (session-failure
                      path line-number
                      "Session record is missing content"))
                   (session-entry-content entry))))
           (unless
               (and
                (stringp custom-type)
                (or
                 (null content)
                 (stringp content)
                 (listp content)
                 (vectorp content)))
             (session-failure
              path line-number
              "Invalid custom message at line ~D"
              line-number))
           (setf
            (session-entry-content entry)
            (cond
              ((stringp content) content)
              ((null content) nil)
              (t
               (content-blocks-from-json
                content))))))
        (:label
         (let ((target-id
                 (progn
                   (unless
                       (session-seen-p
                        entry +session-seen-target-id+)
                     (session-failure
                      path line-number
                      "Session record is missing targetId"))
                   (session-entry-target-id entry)))
               (label
                 (json-null-to-nil
                  (session-entry-label entry))))
           (unless
               (and
                (stringp target-id)
                (gethash target-id by-id)
                (or (null label)
                    (stringp label)))
             (session-failure
              path line-number
              "Invalid label entry at line ~D"
              line-number))
           (setf
            (session-entry-target-id entry) target-id
            (session-entry-label entry) label)))
        (:session-info
         (let ((name
                 (json-null-to-nil
                  (session-entry-name entry))))
           (unless (or (null name) (stringp name))
             (session-failure
              path line-number
              "Invalid session info at line ~D"
              line-number))
           (setf (session-entry-name entry) name)))
        (:leaf
         (let ((target-id
                 (progn
                   (unless
                       (session-seen-p
                        entry +session-seen-target-id+)
                     (session-failure
                      path line-number
                      "Session record is missing targetId"))
                   (json-null-to-nil
                    (session-entry-target-id entry)))))
           (unless
               (and
                (or
                 (null target-id)
                 (stringp target-id))
                (or
                 (null target-id)
                 (gethash target-id by-id)))
             (session-failure
              path line-number
              "Invalid leaf entry at line ~D"
              line-number))
           (setf
            (session-entry-target-id entry)
            target-id))))
      (setf (gethash id by-id) entry)
      entry)))

(defun record-to-session-entry
    (object path line-number by-id)
  (cond
    ((session-entry-p object)
     (finalize-session-entry
      object path line-number by-id))
    ((hash-table-p object)
     (finalize-session-entry
      (session-entry-from-hash object)
      path line-number by-id))
    (t
     (session-failure
      path line-number
      "Session record must be an object"))))

(defun load-session (path)
  (let* ((pathname (pathname path))
         (objects (read-session-objects pathname))
         (header
           (validate-session-header
            (first objects) pathname))
         (version (session-header-ref header "version" 1)))
    (when (< version 3)
      (when (session-file-header-p (first objects))
        (setf (car objects)
              (session-file-header-to-hash (first objects)))
        (setf header (first objects)))
      (handler-case
          (progn
            (when (= version 1)
              (migrate-v1-session-objects objects))
            (migrate-v2-session-objects objects)
            (persist-migrated-session objects pathname))
        (session-error (condition)
          (error condition))
        (error (cause)
          (session-failure
           pathname nil
           "Cannot migrate session to v3: ~A" cause))))
    (let ((by-id
            (make-hash-table
             :test #'equal
             :size (max 8 (length (rest objects)))))
          (labels (make-hash-table :test #'equal :size 8))
          (session-name nil)
          (entries nil)
          (line-number 1))
      (dolist (object (rest objects))
        (incf line-number)
        (let ((entry
                (handler-case
                    (record-to-session-entry
                     object pathname line-number by-id)
           (session-error (condition)
             (error condition))
           (error (cause)
             (session-failure
              pathname line-number
              "Invalid session record at line ~D: ~A"
              line-number cause)))))
          (when (eq :label (session-entry-type entry))
            (if
                (and
                 (session-entry-label entry)
                 (plusp
                  (length
                   (session-entry-label entry))))
                (setf
                 (gethash
                  (session-entry-target-id entry)
                  labels)
                 (session-entry-label entry))
                (remhash
                 (session-entry-target-id entry)
                 labels)))
          (when
              (eq :session-info
                  (session-entry-type entry))
            (setf
             session-name
             (let ((name
                     (session-entry-name entry)))
               (and
                name
                (plusp
                 (length
                  (string-trim
                   '(#\Space #\Tab)
                   name)))
                name))))
          (push entry entries)))
      (setf entries (nreverse entries))
      (let* ((timestamp
               (iso8601-to-milliseconds
                (session-header-ref
                 header "timestamp")))
             (modified-timestamp
               (reduce
                #'max
                entries
                :key
                (lambda (entry)
                  (or
                   (session-entry-activity-timestamp
                    entry)
                   timestamp))
                :initial-value timestamp)))
        (%make-session
       :id (session-header-ref header "id")
       :timestamp timestamp
       :cwd (session-header-ref header "cwd")
       :path pathname
       :parent-session
       (json-null-to-nil
        (session-header-ref header "parentSession"))
       :name session-name
       :labels labels
       :%entries entries
       :%entries-tail (last entries)
       :%entries-tail-head entries
       :by-id by-id
       :persisted-p t
       :modified-timestamp modified-timestamp
       :leaf-id
       (and entries
            (session-entry-id
             (car (last entries)))))))))
