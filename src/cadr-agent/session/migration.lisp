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

(defmacro %octet-u32-le (octets index)
  ;; V8 SeqOneByteString 4-byte load, inlined at the walker
  ;; scanners. sprof session_load @ 335718c2e: OCTET-U32-LE
  ;; 12.2% self (quote/LF/space). Not empty SWAR. Not intern.
  ;; Not FFI. Same bits as cadr-ai:octet-u32-le.
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

(defconstant +swar-lsb+ #x01010101)
(defconstant +swar-msb+ #x80808080)
(defconstant +swar-nl+ #x0A0A0A0A)
(defconstant +swar-ht+ #x09090909)
(defconstant +swar-cr+ #x0D0D0D0D)
(defconstant +swar-sp+ #x20202020)
(defconstant +swar-quot+ #x22222222)
(defconstant +swar-bs+ #x5C5C5C5C)

;; V8 inlines haszero into the string scan. sprof session_load
;; @ 335718c2e after u32 inline: OCTET-FIND-QUOTE-OR-BACKSLASH
;; 10.9% self / 27.1% total; SWAR-EQ-MSB 7.1%; quote-or-bs-mask
;; 6.7%. Not empty SWAR (the masks already work). Not intern.
;; Not FFI.
(declaim (inline swar-eq-msb swar-first-msb-index swar-ws-mask
                 swar-quote-or-bs-mask swar-ctrl-mask
                 octet-find-lf octet-skip-json-space
                 octet-find-quote-or-backslash))

(defun swar-eq-msb (word splat)
  ;; V8/haszero after XOR splat on one ub32. The mask is
  ;; ≤ #x80808080, always a fixnum. A 64-bit
  ;; %vector-raw-bits word boxed ALLOC-UNSIGNED-BIGNUM-IN-RDX
  ;; when bit 62/63 was set. Not FFI. Not sb-simd.
  (declare (type (unsigned-byte 32) word splat)
           (optimize (speed 3) (safety 1)))
  (let ((x (logxor word splat)))
    (logand (ldb (byte 32 0) (- x +swar-lsb+))
            (logandc1 x +swar-msb+))))

(defun swar-first-msb-index (mask)
  (declare (type (unsigned-byte 32) mask)
           (optimize (speed 3) (safety 1)))
  (ash (1- (integer-length (logand mask (- mask)))) -3))

(defun swar-ws-mask (word)
  (declare (type (unsigned-byte 32) word)
           (optimize (speed 3) (safety 1)))
  (logior (swar-eq-msb word +swar-sp+)
          (swar-eq-msb word +swar-ht+)
          (swar-eq-msb word +swar-cr+)
          (swar-eq-msb word +swar-nl+)))

(defun swar-quote-or-bs-mask (word)
  ;; V8 JSON string scan: haszero('"') | haszero('\\') on
  ;; one ub32. Mask ≤ #x80808080, always a fixnum. Not FFI.
  (declare (type (unsigned-byte 32) word)
           (optimize (speed 3) (safety 1)))
  (logior (swar-eq-msb word +swar-quot+)
          (swar-eq-msb word +swar-bs+)))

(defun octet-find-lf (octets start end)
  ;; First 0x0A in [start,end), or NIL. Two ub32 haszero when
  ;; 8-aligned. No 64-bit word, no bignum.
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
             (let ((m0 (swar-eq-msb
                        (%octet-u32-le octets index)
                        +swar-nl+))
                   (m1 (swar-eq-msb
                        (%octet-u32-le
                         octets (the fixnum (+ index 4)))
                        +swar-nl+)))
               (cond
                 ((and (zerop m0) (zerop m1))
                  (incf index 8))
                 ((zerop m0)
                  (return
                    (+ index 4 (swar-first-msb-index m1))))
                 (t
                  (return
                    (+ index (swar-first-msb-index m0)))))))
            ((= (aref octets index) 10)
             (return index))
            (t (incf index))))))

(defun octet-skip-json-space (octets start end)
  ;; Advance past JSON whitespace. Two ub32 haszero when aligned.
  (declare (type (simple-array (unsigned-byte 8) (*)) octets)
           (type fixnum start end)
           (optimize (speed 3) (safety 1)))
  (let ((index start))
    (declare (type fixnum index))
    (loop while (< index end)
          do
          (if (and (zerop (logand index 7))
                   (<= (the fixnum (+ index 8)) end))
              (let ((m0 (swar-ws-mask
                         (%octet-u32-le octets index)))
                    (m1 (swar-ws-mask
                         (%octet-u32-le
                          octets (the fixnum (+ index 4))))))
                (cond
                  ((and (= m0 +swar-msb+) (= m1 +swar-msb+))
                   (incf index 8))
                  ((zerop m0)
                   (return-from octet-skip-json-space index))
                  ((/= m0 +swar-msb+)
                   (return-from octet-skip-json-space
                     (+ index
                        (swar-first-msb-index
                         (logxor m0 +swar-msb+)))))
                  ((zerop m1)
                   (return-from octet-skip-json-space
                     (+ index 4)))
                  (t
                   (return-from octet-skip-json-space
                     (+ index 4
                        (swar-first-msb-index
                         (logxor m1 +swar-msb+)))))))
              (let ((code (aref octets index)))
                (if (or (= code 32)
                        (= code 9)
                        (= code 13)
                        (= code 10))
                    (incf index)
                    (return-from octet-skip-json-space index)))))
    index))

(defun swar-ctrl-mask (word)
  ;; Bytes < 0x20 (unescaped JSON controls). Fixnum mask.
  (declare (type (unsigned-byte 32) word)
           (optimize (speed 3) (safety 1)))
  (logand (ldb (byte 32 0) (- word +swar-sp+))
          (logandc1 word +swar-msb+)))

(defun octet-find-quote-or-backslash (octets start end)
  ;; First 0x22, 0x5C, or byte<32 in [start,end), or NIL.
  ;; V8 string scan: two ub32 haszero (quote and backslash)
  ;; plus hasless(0x20). Not LF/space SWAR. Not FFI.
  ;; A backslash hit is consumed by a byte walk of that
  ;; escape; the caller then resumes this scan.
  (declare (type (simple-array (unsigned-byte 8) (*)) octets)
           (type fixnum start end)
           (optimize (speed 3) (safety 1)))
  (let ((index start))
    (declare (type fixnum index))
    (loop while (<= (the fixnum (+ index 4)) end)
          do
          (let* ((word (%octet-u32-le octets index))
                 (mask
                   (logior (swar-quote-or-bs-mask word)
                           (swar-ctrl-mask word))))
            (if (zerop mask)
                (incf index 4)
                (return (+ index (swar-first-msb-index mask))))))
    (loop while (< index end)
          do
          (let ((code (aref octets index)))
            (when (or (= code 34)
                      (= code 92)
                      (< code 32))
              (return index)))
          (incf index))))

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
                   octets ,key-start ,key-end ,literal))
               ;; V8 SkipWhiteSpace / Expect is inlined in the
               ;; parser, not a labels call per field. sprof load
               ;; @ 9b1678b20: SKIP-SPACE 8.2% self, EXPECT-CODE
               ;; 3.5%. Not empty SWAR. Not intern. Not FFI.
               (skip-space ()
                 `(setf position
                        (octet-skip-json-space octets position length)))
               (expect-code (code)
                 `(unless (eql (take-code) ,code)
                    (fail "Unexpected byte"))))
      (labels
          ((fail (message)
             (error 'cadr-ai::json-parse-error
                    :message message
                    :position position))
           (skip-string ()
             (expect-code 34)
             (loop
               (let ((hit
                       (octet-find-quote-or-backslash
                        octets position length)))
                 (unless hit
                   (fail "Unterminated string"))
                 (setf position hit)
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
                          (incf position 4))))
                     (t
                      (fail "Unescaped control character")))))))
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
                 (let ((hit
                         (octet-find-quote-or-backslash
                          octets position length)))
                   (unless hit
                     (fail "Unterminated string"))
                   (setf position hit)
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
                        (fail "Unescaped control character"))))))))
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
             ;; V8 ParseString: sequential scan to the closing
             ;; quote, then intern/copy. Session timestamps are
             ;; YYYY-MM-DDTHH:MM:SS.sssZ (24 ASCII). A per-byte
             ;; quote walk is not that scan. Not labels macrolet.
             ;; Not empty SWAR. Not intern. Not FFI.
             (skip-space)
             (let ((code (peek-code)))
               (cond
                 ((eql code 34)
                  (expect-code 34)
                  (let* ((value-start position)
                         (iso-end (the fixnum (+ position 24)))
                         (fixed
                           (and (<= (the fixnum (1+ iso-end)) length)
                                (= (aref octets iso-end) 34)
                                (iso-ms value-start iso-end))))
                    (if fixed
                        (progn
                          (setf position (the fixnum (1+ iso-end)))
                          fixed)
                        (loop
                          (let ((hit
                                  (octet-find-quote-or-backslash
                                   octets position length)))
                            (unless hit
                              (fail "Unterminated string"))
                            (setf position hit)
                            (let ((b (aref octets position)))
                              (cond
                                ((= b 34)
                                 (let ((value-end position)
                                       (parsed
                                         (iso-ms value-start position)))
                                   (incf position)
                                   (return
                                     (or parsed
                                         (cadr-ai::copy-unescaped-json-octets
                                          octets value-start
                                          value-end)))))
                                ((= b 92)
                                 (incf position)
                                 (unless (take-code)
                                   (fail "Truncated escape")))
                                (t
                                 (fail "Unescaped control character")))))))))
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
                 (let ((hit
                         (octet-find-quote-or-backslash
                          octets position length)))
                   (unless hit
                     (fail "Unterminated string"))
                   (setf position hit)
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
                        (fail "Unescaped control character"))))))))
           (classify-entry-key (key-start key-end)
             ;; Preclassify closed entry keys once after scan-key.
             ;; Tag = (logior u32-le-prefix (ash n 32)).  Not length-case.
             ;; Not intern. Not FFI.
             (let ((n (- key-end key-start)))
               (cond
                 ((= n 2)
                  (if (and (= (aref octets key-start) 105)
                           (= (aref octets (+ key-start 1)) 100))
                      #x200006469
                      0))
                 ((>= n 4)
                  (logior (%octet-u32-le octets key-start)
                          (ash n 32)))
                 (t 0))))
           (parse-arguments-object ()
             ;; Keys from the octet window. Closed path/offset/limit
             ;; literals skip copy-unescaped. Not three-pair compact.
             ;; Not intern-table grow.
             (expect-code 123)
             (skip-space)
             (when (eql (peek-code) 125)
               (take-code)
               (return-from parse-arguments-object '(:json-object)))
             (let ((pairs nil))
               (loop
                 (unless (eql (peek-code) 34)
                   (fail "Object key must be a string"))
                 (multiple-value-bind (key-start key-end)
                     (scan-key)
                   (skip-space)
                   (expect-code 58)
                   (skip-space)
                   (let* ((n (- key-end key-start))
                          (key
                            (cond
                              ((and (= n 4)
                                    (key= key-start key-end "path"))
                               "path")
                              ((and (= n 6)
                                    (key= key-start key-end "offset"))
                               "offset")
                              ((and (= n 5)
                                    (key= key-start key-end "limit"))
                               "limit")
                              (t
                               (or
                                (cadr-ai::json-interned-ascii-value-octets
                                 octets key-start key-end)
                                (cadr-ai::copy-unescaped-json-octets
                                 octets key-start key-end))))))
                     (setf pairs (list* key (parse-generic) pairs))))
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
           (try-compact-content-block ()
             ;; Type-first compact prefixes pi emits (pairing fixture).
             ;; Miss (spaces, key order, extra fields, escaped type)
             ;; rewinds; generic parse-content-block runs. Never
             ;; session-json-block on the hit path.
             (unless (eql (peek-code) 123)
               (return-from try-compact-content-block nil))
             (let ((saved position))
               (flet ((rewind ()
                        (setf position saved)
                        nil)
                      (take-prefix (literal)
                        (let ((n (length literal)))
                          (declare (type fixnum n))
                          (when (and (<= (the fixnum (+ position n)) length)
                                     (key= position
                                           (the fixnum (+ position n))
                                           literal))
                            (incf position n)
                            t))))
                 (cond
                   ((take-prefix "{\"type\":\"text\",\"text\":")
                    (let ((text (parse-string-value)))
                      (if (eql (peek-code) 125)
                          (progn
                            (take-code)
                            (cadr-ai:make-text-content
                             :text (or text "")))
                          (rewind))))
                   ((take-prefix "{\"type\":\"thinking\",\"thinking\":")
                    (let ((thinking (parse-string-value)))
                      (if (eql (peek-code) 125)
                          (progn
                            (take-code)
                            (cadr-ai:make-thinking-content
                             :thinking (or thinking "")))
                          (rewind))))
                   ((take-prefix "{\"type\":\"toolCall\",\"id\":")
                    (let ((id (parse-string-value)))
                      (if (not (take-prefix ",\"name\":"))
                          (rewind)
                          (let ((name (parse-string-value)))
                            (if (not (take-prefix ",\"arguments\":"))
                                (rewind)
                                (if (not (eql (peek-code) 123))
                                    (rewind)
                                    (let ((arguments (parse-arguments-object)))
                                      (if (eql (peek-code) 125)
                                          (progn
                                            (take-code)
                                            (cadr-ai:make-tool-call
                                             :id (or id "")
                                             :name (or name "")
                                             :arguments
                                             (cond
                                               ((cadr-ai::json-object-pairs-p
                                                 arguments)
                                                arguments)
                                               ((hash-table-p arguments)
                                                arguments)
                                               (t '(:json-object)))))
                                          (rewind)))))))))
                   (t
                    (rewind))))))
           (parse-content-block ()
             (or (try-compact-content-block)
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
                   (finish-block block))))
           (parse-content-small-array ()
             ;; Structural 1- or 2-object array. Parse the first object
             ;; once; do not rewind into a second size-specialized walk.
             ;; Miss (non-object element or 3+) rewinds to generic loop.
             ;; Not try-compact-thinking-text-array. Not type-prefix.
             ;; Not three-block. Not svref bag.
             (let ((saved position))
               (flet ((rewind ()
                        (setf position saved)
                        nil))
                 (unless (eql (peek-code) 123)
                   (return-from parse-content-small-array (rewind)))
                 (let ((first (parse-content-block)))
                   (skip-space)
                   (let ((next (peek-code)))
                     (cond
                       ((eql next 93)
                        (take-code)
                        (list first))
                       ((eql next 44)
                        (take-code)
                        (skip-space)
                        (unless (eql (peek-code) 123)
                          (return-from parse-content-small-array (rewind)))
                        (let ((second (parse-content-block)))
                          (skip-space)
                          (if (eql (peek-code) 93)
                              (progn
                                (take-code)
                                (list first second))
                              (rewind))))
                       (t
                        (rewind))))))))
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
                  (or (parse-content-small-array)
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
                               (fail "Expected comma or ]"))))))))
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
           (try-compact-usage ()
             ;; Pairing-fixture usage envelope: fixed key order and
             ;; shape. Miss (spaces, reorder, snake_case, non-zero
             ;; decimal cost) rewinds to generic parse-usage. Not
             ;; message-entry-prefix. Not key= dispatch.
             (unless (eql (peek-code) 123)
               (return-from try-compact-usage nil))
             (let ((saved position))
               (flet ((rewind ()
                        (setf position saved)
                        nil)
                      (take-prefix (literal)
                        (let ((n (length literal)))
                          (declare (type fixnum n))
                          (when (and (<= (the fixnum (+ position n)) length)
                                     (key= position
                                           (the fixnum (+ position n))
                                           literal))
                            (incf position n)
                            t))))
                 (unless (take-prefix "{\"input\":")
                   (return-from try-compact-usage (rewind)))
                 (let ((usage (cadr-ai:make-usage)))
                   (setf (cadr-ai:usage-input usage)
                         (or (parse-number-value) 0))
                   (unless (take-prefix ",\"output\":")
                     (return-from try-compact-usage (rewind)))
                   (setf (cadr-ai:usage-output usage)
                         (or (parse-number-value) 0))
                   (unless (take-prefix ",\"cacheRead\":")
                     (return-from try-compact-usage (rewind)))
                   (setf (cadr-ai:usage-cache-read usage)
                         (or (parse-number-value) 0))
                   (unless (take-prefix ",\"cacheWrite\":")
                     (return-from try-compact-usage (rewind)))
                   (setf (cadr-ai:usage-cache-write usage)
                         (or (parse-number-value) 0))
                   (unless (take-prefix ",\"totalTokens\":")
                     (return-from try-compact-usage (rewind)))
                   (parse-number-value)
                   (unless (take-prefix ",\"cost\":")
                     (return-from try-compact-usage (rewind)))
                   (cond
                     ((take-prefix
                       "{\"input\":0,\"output\":0,\"cacheRead\":0,\"cacheWrite\":0,\"total\":0}")
                      (setf (cadr-ai:usage-cost usage)
                            (cadr-ai:make-cost)))
                     (t
                      (return-from try-compact-usage (rewind))))
                   (if (eql (peek-code) 125)
                       (progn
                         (take-code)
                         usage)
                       (rewind))))))
           (parse-usage ()
             (or (try-compact-usage)
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
                   usage)))
           (keep-extra (bag key value)
             (when value
               (setf (session-json-message-extra bag)
                     (list* key value
                            (session-json-message-extra bag)))))
           (put-message-field (bag key-start key-end)
             ;; Closed message keys: (u32, length) is unique.  Skip
             ;; second octet-window-equals after scan-key.  Not
             ;; length-case. Not intern. Not FFI.
             (let ((n (- key-end key-start)))
               (cond
                 ((and (= n 3)
                       (= (aref octets key-start) 97)
                       (= (aref octets (+ key-start 1)) 112)
                       (= (aref octets (+ key-start 2)) 105))
                  (setf (session-json-message-api bag)
                        (keyword-from-json (parse-string-value))))
                 ((>= n 4)
                  (let ((w (%octet-u32-le octets key-start)))
                    (cond
                      ((and (= w #x656c6f72) (= n 4))
                       (setf (session-json-message-role bag)
                             (parse-string-value)))
                      ((and (= w #x70736572) (= n 10))
                       (keep-extra bag :response-id
                                   (parse-string-value)))
                      ((and (= w #x70736572) (= n 11))
                       (keep-extra bag :response-id
                                   (parse-string-value)))
                      ((and (= w #x53776172) (= n 13))
                       (keep-extra bag :raw-stop-reason
                                   (parse-string-value)))
                      ((and (= w #x5f776172) (= n 15))
                       (keep-extra bag :raw-stop-reason
                                   (parse-string-value)))
                      ((and (= w #x65707974) (= n 4))
                       (if (session-json-message-role bag)
                           (skip-value)
                           (setf (session-json-message-role bag)
                                 (parse-string-value))))
                      ((and (= w #x656d6974) (= n 9))
                       (setf (session-json-message-timestamp bag)
                             (parse-timestamp-value)))
                      ((and (= w #x6c6f6f74) (= n 10))
                       (keep-extra bag :tool-call-id
                                   (parse-string-value)))
                      ((and (= w #x6c6f6f74) (= n 12))
                       (keep-extra bag :tool-call-id
                                   (parse-string-value)))
                      ((and (= w #x6c6f6f74) (= n 8))
                       (keep-extra bag :tool-name
                                   (parse-string-value)))
                      ((and (= w #x6c6f6f74) (= n 9))
                       (keep-extra bag :tool-name
                                   (parse-string-value)))
                      ((and (= w #x6e757274) (= n 9))
                       (keep-extra bag :truncated (parse-generic)))
                      ((and (= w #x746e6f63) (= n 7))
                       (setf (session-json-message-content bag)
                             (parse-content-value)))
                      ((and (= w #x6d6d6f63) (= n 7))
                       (keep-extra bag :command (parse-string-value)))
                      ((and (= w #x636e6163) (= n 9))
                       (keep-extra bag :cancelled (parse-generic)))
                      ((and (= w #x766f7270) (= n 8))
                       (setf (session-json-message-provider bag)
                             (keyword-from-json (parse-string-value))))
                      ((and (= w #x766f7270) (= n 21))
                       (keep-extra bag :provider-thinking-level
                                   (parse-string-value)))
                      ((and (= w #x766f7270) (= n 23))
                       (keep-extra bag :provider-thinking-level
                                   (parse-string-value)))
                      ((and (= w #x65646f6d) (= n 5))
                       (setf (session-json-message-model bag)
                             (parse-string-value)))
                      ((and (= w #x67617375) (= n 5))
                       (skip-space)
                       (setf (session-json-message-usage bag)
                             (if (eql (peek-code) 123)
                                 (parse-usage)
                                 (parse-generic))))
                      ((and (= w #x706f7473) (= n 10))
                       (setf (session-json-message-stop-reason bag)
                             (keyword-from-json (parse-string-value))))
                      ((and (= w #x706f7473) (= n 11))
                       (setf (session-json-message-stop-reason bag)
                             (keyword-from-json (parse-string-value))))
                      ((and (= w #x6f727265) (= n 12))
                       (keep-extra bag :error-message
                                   (parse-string-value)))
                      ((and (= w #x6f727265) (= n 13))
                       (keep-extra bag :error-message
                                   (parse-string-value)))
                      ((and (= w #x74697865) (= n 8))
                       (keep-extra bag :exit-code
                                   (parse-number-value)))
                      ((and (= w #x74697865) (= n 9))
                       (keep-extra bag :exit-code
                                   (parse-number-value)))
                      ((and (= w #x6c637865) (= n 18))
                       (keep-extra bag :exclude-from-context
                                   (parse-generic)))
                      ((and (= w #x6c637865) (= n 20))
                       (keep-extra bag :exclude-from-context
                                   (parse-generic)))
                      ((and (= w #x67616964) (= n 11))
                       (keep-extra bag :diagnostics (parse-generic)))
                      ((and (= w #x61746564) (= n 7))
                       (keep-extra bag :details (parse-generic)))
                      ((and (= w #x72457369) (= n 7))
                       (keep-extra bag :is-error (parse-generic)))
                      ((and (= w #x655f7369) (= n 8))
                       (keep-extra bag :is-error (parse-generic)))
                      ((and (= w #x7074756f) (= n 6))
                       (keep-extra bag :output (parse-string-value)))
                      ((and (= w #x6c6c7566) (= n 14))
                       (keep-extra bag :full-output-path
                                   (parse-string-value)))
                      ((and (= w #x6c6c7566) (= n 16))
                       (keep-extra bag :full-output-path
                                   (parse-string-value)))
                      (t
                       (skip-value)))))
                 (t
                  (skip-value)))))
           (try-compact-message ()
             ;; Shared {"role":" gate then fixture envelopes. Content-compact
             ;; sibling. Miss rewinds. Not stack-local typed fill.
             (unless (eql (peek-code) 123)
               (return-from try-compact-message nil))
             (let ((saved position))
               (flet ((rewind ()
                        (setf position saved)
                        nil)
                      (take-prefix (literal)
                        (let ((n (length literal)))
                          (declare (type fixnum n))
                          (when (and (<= (the fixnum (+ position n)) length)
                                     (key= position
                                           (the fixnum (+ position n))
                                           literal))
                            (incf position n)
                            t))))
                 (unless (take-prefix "{\"role\":\"")
                   (return-from try-compact-message (rewind)))
                 (cond
                   ((take-prefix "user\",\"content\":[{\"type\":\"text\",\"text\":")
                    (let ((text (parse-string-value)))
                      (if (not (take-prefix "}],\"timestamp\":"))
                          (rewind)
                          (let ((timestamp (parse-timestamp-value)))
                            (if (eql (peek-code) 125)
                                (progn
                                  (take-code)
                                  (cadr-ai:make-user-message
                                   :content
                                   (list
                                    (cadr-ai:make-text-content
                                     :text (or text "")))
                                   :timestamp timestamp))
                                (rewind))))))
                   ((take-prefix
                     "toolResult\",\"toolCallId\":")
                    (let ((tool-call-id (parse-string-value)))
                      (if (not (take-prefix ",\"toolName\":"))
                          (rewind)
                          (let ((tool-name (parse-string-value)))
                            (if (not
                                 (take-prefix
                                  ",\"content\":[{\"type\":\"text\",\"text\":"))
                                (rewind)
                                (let ((text (parse-string-value)))
                                  (if (not (take-prefix "}],\"isError\":"))
                                      (rewind)
                                      (let ((is-error (parse-generic)))
                                        (if (not (take-prefix
                                                  ",\"timestamp\":"))
                                            (rewind)
                                            (let ((timestamp
                                                    (parse-timestamp-value)))
                                              (if (eql (peek-code) 125)
                                                  (progn
                                                    (take-code)
                                                    (cadr-ai:make-tool-result-message
                                                     :tool-call-id
                                                     (or tool-call-id "")
                                                     :tool-name
                                                     (or tool-name "")
                                                     :content
                                                     (list
                                                      (cadr-ai:make-text-content
                                                       :text (or text "")))
                                                     :is-error
                                                     (eq t is-error)
                                                     :timestamp timestamp))
                                                  (rewind))))))))))))
                   ((take-prefix
                     "assistant\",\"content\":[{\"type\":\"toolCall\",\"id\":")
                    (let ((id (parse-string-value)))
                      (if (not (take-prefix ",\"name\":"))
                          (rewind)
                          (let ((name (parse-string-value)))
                            (if (not (take-prefix ",\"arguments\":"))
                                (rewind)
                                (if (not (eql (peek-code) 123))
                                    (rewind)
                                    (let ((arguments (parse-arguments-object)))
                                      (if (not (eql (peek-code) 125))
                                          (rewind)
                                          (progn
                                            (take-code)
                                            (if (not (take-prefix "],\"api\":"))
                                                (rewind)
                                                (let ((bag
                                                        (make-session-json-message)))
                                                  (setf (session-json-message-role
                                                         bag)
                                                        "assistant"
                                                        (session-json-message-content
                                                         bag)
                                                        (list
                                                         (cadr-ai:make-tool-call
                                                          :id (or id "")
                                                          :name (or name "")
                                                          :arguments
                                                          (cond
                                                            ((cadr-ai::json-object-pairs-p
                                                              arguments)
                                                             arguments)
                                                            ((hash-table-p
                                                              arguments)
                                                             arguments)
                                                            (t
                                                             '(:json-object))))))
                                                  (or (try-compact-assistant-tail
                                                       bag)
                                                      (rewind)))))))))))))
                   (t
                    (rewind))))))
           (try-compact-assistant-tail (bag)
             ;; Pairing-fixture assistant metadata after content: fixed
             ;; api/provider/model/usage/stopReason/timestamp order.
             ;; Content still uses parse-content-value. Miss rewinds.
             ;; Not message-entry-prefix. Not thinking-text envelope.
             ;; Not toolUse typed emit.
             (unless (and (session-json-message-role bag)
                          (string= (session-json-message-role bag)
                                   "assistant")
                          (session-json-message-content bag))
               (return-from try-compact-assistant-tail nil))
             (let ((saved position))
               (flet ((rewind ()
                        (setf position saved)
                        nil)
                      (take-prefix (literal)
                        (let ((n (length literal)))
                          (declare (type fixnum n))
                          (when (and (<= (the fixnum (+ position n)) length)
                                     (key= position
                                           (the fixnum (+ position n))
                                           literal))
                            (incf position n)
                            t))))
                 (unless (take-prefix
                          "\"openai-completions\",\"provider\":\"goal20faux\",\"model\":\"goal20-paired-1\",\"usage\":")
                   (return-from try-compact-assistant-tail (rewind)))
                 (let ((usage (try-compact-usage)))
                   (unless usage
                     (return-from try-compact-assistant-tail (rewind)))
                   (flet ((finish (stop-reason)
                            (let ((timestamp (parse-timestamp-value)))
                              (if (eql (peek-code) 125)
                                  (progn
                                    (take-code)
                                    (cadr-ai:make-assistant-message
                                     :content
                                     (content-blocks-from-json
                                      (session-json-message-content bag))
                                     :api :openai-completions
                                     :provider :goal20faux
                                     :model "goal20-paired-1"
                                     :usage usage
                                     :stop-reason stop-reason
                                     :timestamp timestamp))
                                  (rewind)))))
                     (cond
                       ((take-prefix ",\"stopReason\":\"stop\",\"timestamp\":")
                        (finish :stop))
                       ((take-prefix ",\"stopReason\":\"toolUse\",\"timestamp\":")
                        (finish :tooluse))
                       (t
                        (rewind))))))))
           (parse-message ()
             (or (try-compact-message)
                 (let ((bag (make-session-json-message))
                       (typed-result nil))
                   (expect-code 123)
                   (skip-space)
                   (unless (eql (peek-code) 125)
                     (loop
                       (when typed-result
                         (return))
                       (multiple-value-bind (key-start key-end)
                           (scan-key)
                         (skip-space)
                         (expect-code 58)
                         (skip-space)
                         (if key-start
                             (let ((n (- key-end key-start)))
                               (when (and (= n 3)
                                          (= (aref octets key-start) 97)
                                          (= (aref octets (+ key-start 1))
                                             112)
                                          (= (aref octets (+ key-start 2))
                                             105)
                                          (session-json-message-role bag)
                                          (string= (session-json-message-role
                                                    bag)
                                                   "assistant")
                                          (session-json-message-content bag))
                                 (let ((msg (try-compact-assistant-tail bag)))
                                   (when msg
                                     (setf typed-result msg))))
                               (unless typed-result
                                 (put-message-field bag key-start key-end)))
                             (skip-value)))
                       (skip-space)
                       (let ((code (peek-code)))
                         (cond
                           ((eql code 44)
                            (take-code)
                            (skip-space))
                           ((eql code 125) (return))
                           (t (fail "Expected comma or }"))))))
                   (or typed-result
                       (progn
                         (expect-code 125)
                         bag)))))
           (put-entry-field (tag)
             ;; Closed entry keys: scan-key preclassified tag.  One u32
             ;; read in classify-entry-key; no second key= compare.
             ;; Not length-case. Not intern. Not FFI.
             (case tag
               (#x200006469
                (setf (session-entry-id entry)
                      (parse-string-value)))
               (#x465707974
                (setf (session-entry-type entry)
                      (parse-string-value)))
               (#x865726170
                (mark-session-seen entry +session-seen-parent-id+)
                (skip-space)
                (setf (session-entry-parent-id entry)
                      (if (eql (peek-code) 110)
                          (parse-literal-null)
                          (parse-string-value))))
               (#x9656d6974
                (setf (session-entry-timestamp entry)
                      (parse-timestamp-value)))
               (#x77373656d
                (skip-space)
                (setf (session-entry-message entry)
                      (if (eql (peek-code) 123)
                          (parse-message)
                          (parse-generic))))
               (#x76d6d7573
                (setf (session-entry-summary entry)
                      (parse-string-value)))
               (#x972756f73
                (setf (session-entry-source-ids entry)
                      (parse-generic)))
               (#x1073726966
                (setf (session-entry-first-kept-id entry)
                      (parse-string-value)))
               (#xc656b6f74
                (mark-session-seen entry +session-seen-tokens-before+)
                (setf (session-entry-tokens-before entry)
                      (parse-number-value)))
               (#xd6e696874
                (setf (session-entry-thinking-level entry)
                      (parse-string-value)))
               (#x8766f7270
                (setf (session-entry-provider entry)
                      (parse-string-value)))
               (#x765646f6d
                (setf (session-entry-model-id entry)
                      (parse-string-value)))
               (#xf69746361
                (setf (session-entry-active-tool-names entry)
                      (parse-generic)))
               (#x66d6f7266
                (setf (session-entry-from-id entry)
                      (parse-string-value)))
               (#x86d6f7266
                (setf (session-entry-from-hook-p entry)
                      (eq t (parse-generic))))
               (#x761746564
                (setf (session-entry-details entry)
                      (parse-generic)))
               (#x567617375
                (skip-space)
                (setf (session-entry-usage entry)
                      (if (eql (peek-code) 123)
                          (parse-usage)
                          (parse-generic))))
               (#xa74737563
                (setf (session-entry-custom-type entry)
                      (parse-string-value)))
               (#x461746164
                (setf (session-entry-data entry)
                      (parse-generic)))
               (#x7746e6f63
                (mark-session-seen entry +session-seen-content+)
                (setf (session-entry-content entry)
                      (parse-content-value)))
               (#x770736964
                (setf (session-entry-display-p entry)
                      (eq t (parse-generic))))
               (#x867726174
                (mark-session-seen entry +session-seen-target-id+)
                (setf (session-entry-target-id entry)
                      (parse-string-value)))
               (#x56562616c
                (setf (session-entry-label entry)
                      (parse-string-value)))
               (#x4656d616e
                (setf (session-entry-name entry)
                      (parse-string-value)))
               (#xc61746572
                (setf (session-entry-retained-tail entry)
                      (parse-generic)))
               (otherwise
                (skip-value)))))
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
                  (put-entry-field (classify-entry-key key-start key-end))
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
                (cond
                  ((or (eq field "provider")
                       (string= field "provider"))
                   (keep-extra bag :provider value))
                  ((or (eq field "providerThinkingLevel")
                       (string= field "providerThinkingLevel")
                       (string= field "provider_thinking_level"))
                   (keep-extra bag :provider-thinking-level value))))
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
  (cond
    (raw-hash-p
     (if octet-p
         (cadr-ai::parse-json-octets line nil nil start end)
         (cadr-ai::parse-json-source line nil nil start end)))
    (t
     (parse-session-record line start end octet-p))))

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

(defun repair-unterminated-session-file (path)
  ;; pi@16787ad5b session-manager.ts #8345: after a valid load, append a
  ;; trailing newline so the next JSONL entry cannot fuse with a
  ;; truncated last line.
  (when (probe-file path)
    (let ((needs-newline-p
            (with-open-file
                (stream path
                        :direction :input
                        :element-type '(unsigned-byte 8)
                        :if-does-not-exist nil)
              (let ((length (file-length stream)))
                (when (and (integerp length) (plusp length))
                  (file-position stream (1- length))
                  (not (= 10 (read-byte stream))))))))
      (when needs-newline-p
        (with-open-file
            (stream path
                    :direction :output
                    :element-type '(unsigned-byte 8)
                    :if-exists :append)
          (write-byte 10 stream)))))
  path)

(defun read-session-objects (path &key strict-p hash-records-p)
  ;; Pairing counterpart of Node 1MiB readSync: one octet
  ;; READ-SEQUENCE per chunk, then split on LF.  Files that
  ;; fit the cap are one exact-size read.  ASCII lines reuse
  ;; one simple-base-string and parse a START/END window.
  ;; JSONL newlines are UTF-8 boundaries.  Not intern.  Not 7b.
  ;; STRICT-P fails the load on a bad body line instead of skipping it.
  ;; HASH-RECORDS-P keeps body lines on the general octet JSON parser
  ;; so harness JSONL round-trips that the schema walker does not cover.
  (let ((objects nil)
        (line-number 0)
        (header nil)
        (raw-hash-p t)
        (trailing-lf-p nil))
    (labels
        ((blank-octets-p (octets start end)
           (loop for index from start below end
                 for unit = (aref octets index)
                 always
                 (or (= unit 32)
                     (= unit 9)
                     (= unit 13)
                     (= unit 10))))
         (line-has-body-p (octets start end)
           ;; Fixture JSONL lines start with '{'.  Skip the per-byte
           ;; whitespace walk on the hot path.  Not consume-line '{'
           ;; blank-skip.  Not ignore-errors consume-line.
           (and (< start end)
                (or (= (aref octets start) 123)
                    (not (blank-octets-p octets start end)))))
         (parse-line (octets start end)
           (if (null header)
               (parse-session-header-octets
                octets start end)
               (parse-session-line
                octets path line-number
                :raw-hash-p raw-hash-p
                :start start
                :end end
                :octet-p t)))
         (consume-line (octets start end)
           (incf line-number)
           (when (line-has-body-p octets start end)
             (let ((object
                     (if strict-p
                         (handler-case
                             (parse-line octets start end)
                           (session-error (condition)
                             (error condition))
                           (error (cause)
                             (if header
                                 (handler-case
                                     (cadr-ai::parse-json-octets
                                      octets nil nil start end)
                                   (error ()
                                     (session-failure
                                      path line-number
                                      "Invalid JSONL session entry: ~A"
                                      cause)))
                                 (session-failure
                                  path line-number
                                  "Invalid JSONL session entry: ~A"
                                  cause))))
                         (block consume-parse
                           (handler-bind
                               ((error
                                 #'(lambda (cause)
                                     (declare (ignore cause))
                                     (return-from consume-parse nil))))
                             (parse-line octets start end))))))
               (when object
                 (unless header
                   (setf header object)
                   (setf raw-hash-p
                         (or hash-records-p
                             (let ((version
                                     (session-header-ref
                                      object "version" 1)))
                               (or (not (integerp version))
                                   (< version 3))))))
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
                    (let ((count (read-sequence chunk stream)))
                      (setf trailing-lf-p (= (aref chunk (1- count)) 10))
                      (scan-buffer chunk count nil)))))
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
                         (setf trailing-lf-p (= (aref chunk (1- count)) 10))
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
      (unless trailing-lf-p
        (repair-unterminated-session-file path))
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
    (entry path line-number by-id
     &key (decode-message-p t))
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
         (let ((raw
                 (require-session-slot
                  (session-entry-message entry)
                  "message" path line-number)))
           (setf
            (session-entry-message entry)
            (if decode-message-p
                (message-from-json raw)
                raw))))
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

(defun session-header-like-p (object)
  (or (session-file-header-p object)
      (and (hash-table-p object)
           (string=
            "session"
            (or (cadr-ai::json-get object "type") "")))))

(defun file-entry-header (entries)
  (find-if #'session-header-like-p entries))

(defun file-entry-body (entries)
  (remove-if #'session-header-like-p entries))

(defun hash-message-role (object)
  (and (hash-table-p object)
       (let ((message (cadr-ai::json-get object "message")))
         (and (hash-table-p message)
              (cadr-ai::json-get message "role")))))

(defun adopt-session-object (object path line-number by-id)
  (cond
    ((session-entry-p object)
     (let ((id (session-entry-id object)))
       (when (gethash id by-id)
         (session-failure
          path line-number
          "Duplicate session entry id: ~A" id))
       (setf (gethash id by-id) object)
       object))
    ((member (hash-message-role object)
             '("hookMessage" "custom")
             :test #'string=)
     (finalize-session-entry
      (session-entry-from-hash object)
      path line-number by-id
      :decode-message-p nil))
    (t
     (record-to-session-entry
      object path line-number by-id))))

(defun session-index-adopted-body (session records)
  (let ((by-id (session-by-id session))
        (labels (session-labels session))
        (entries nil)
        (entries-tail nil)
        (session-name nil)
        (line-number 1))
    (clrhash by-id)
    (clrhash labels)
    (dolist (object records)
      (incf line-number)
      (let ((entry
              (adopt-session-object
               object (session-path session) line-number by-id)))
        (when (eq :label (session-entry-type entry))
          (if (and (session-entry-label entry)
                   (plusp (length (session-entry-label entry))))
              (setf (gethash (session-entry-target-id entry) labels)
                    (session-entry-label entry))
              (remhash (session-entry-target-id entry) labels)))
        (when (eq :session-info (session-entry-type entry))
          (setf session-name
                (let ((name (session-entry-name entry)))
                  (and name
                       (plusp
                        (length
                         (string-trim '(#\Space #\Tab) name)))
                       name))))
        (let ((cell (list entry)))
          (if entries-tail
              (setf (cdr entries-tail) cell
                    entries-tail cell)
              (setf entries cell
                    entries-tail cell)))))
    (setf (session-%entries session) entries
          (session-%entries-tail session) entries-tail
          (session-%entries-tail-head session) entries
          (session-name session) session-name
          (session-leaf-id session)
          (and entries-tail
               (session-entry-id (car entries-tail)))
          (session-modified-timestamp session)
          (reduce
           #'max
           entries
           :key
           (lambda (entry)
             (or (session-entry-activity-timestamp entry)
                 (session-timestamp session)))
           :initial-value (session-timestamp session)))
    session))

(defun create-in-memory-session
    (&key cwd id parent-session entries
          (timestamp (cadr-ai::unix-milliseconds)))
  (let ((header (file-entry-header entries))
        (body (file-entry-body entries)))
    (if header
        (let* ((header-hash
                 (if (session-file-header-p header)
                     (session-file-header-to-hash header)
                     header))
               (objects (cons header-hash (copy-list body)))
               (version (session-header-ref header-hash "version" 1)))
          (when (< version 3)
            (when (every #'hash-table-p objects)
              (when (= version 1)
                (migrate-v1-session-objects objects))
              (migrate-v2-session-objects objects)))
          (let ((resolved (first objects)))
            (session-index-adopted-body
             (%make-session
              :id (session-header-ref resolved "id")
              :version 3
              :timestamp
              (iso8601-to-milliseconds
               (session-header-ref resolved "timestamp"))
              :cwd (session-header-ref resolved "cwd")
              :path nil
              :parent-session
              (json-null-to-nil
               (session-header-ref resolved "parentSession"))
              :modified-timestamp
              (iso8601-to-milliseconds
               (session-header-ref resolved "timestamp")))
             (rest objects))))
        (session-index-adopted-body
         (create-session
          :cwd cwd
          :id id
          :parent-session parent-session
          :timestamp timestamp
          :persist-p nil)
         body))))

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
    ;; pi _buildIndex: walk FileEntry[] in order, Map by id, last
    ;; non-header is leaf. Lisp encoding is a simple-vector of the
    ;; parsed records. Runtime %entries stays a cons list for O(1)
    ;; append. Not a third JSON parser. Not :size. Not intern.
    (let* ((records (coerce (rest objects) 'simple-vector))
           (count (length records))
           (by-id (make-hash-table :test #'equal))
           (labels (make-hash-table :test #'equal))
           (session-name nil)
           (entries nil)
           (entries-tail nil)
           (line-number 1))
      (declare (type simple-vector records)
               (type fixnum count line-number))
      (loop for index of-type fixnum from 0 below count
            for object = (aref records index)
            do
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
          (let ((cell (list entry)))
            (if entries-tail
                (setf (cdr entries-tail) cell
                      entries-tail cell)
                (setf entries cell
                      entries-tail cell)))))
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
       :%entries-tail entries-tail
       :%entries-tail-head entries
       :by-id by-id
       :persisted-p t
       :modified-timestamp modified-timestamp
       :leaf-id
       (and entries-tail
            (session-entry-id
             (car entries-tail))))))))
