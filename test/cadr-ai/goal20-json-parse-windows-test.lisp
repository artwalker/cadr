(in-package #:cadr-ai/tests)

(in-suite cadr-ai-suite)

(test goal20-json-unescaped-window-copies-source
  (let* ((source "{\"x\":\"ab\"}")
         (value (cadr-ai::parse-json source)))
    (setf (char source 6) #\z)
    (is (string= "ab" (cadr-ai::json-get value "x")))))

(test goal20-json-empty-and-escaped-quote-strings
  (is (string= "" (cadr-ai::parse-json "\"\"")))
  (is (string= "a\"b" (cadr-ai::parse-json "\"a\\\"b\"")))
  (is (string= (format nil "x~%y")
               (cadr-ai::parse-json "\"x\\ny\"")))
  (is (string= "/" (cadr-ai::parse-json "\"\\/\""))))

(test goal20-json-many-short-unescaped-keys-round-trip
  (let ((object (cadr-ai::json-object)))
    (dotimes (index 64)
      (cadr-ai::json-put
       object
       (format nil "k~D" index)
       (format nil "v~D" index)))
    (let* ((encoded (cadr-ai::stringify-json object))
           (round-trip (cadr-ai::parse-json encoded)))
      (dotimes (index 64)
        (is (string=
             (format nil "v~D" index)
             (cadr-ai::json-get
              round-trip
              (format nil "k~D" index))))))))

(test goal20-json-integers-parse-without-token-copy
  ;; P.1: 0 / -0 / -12 / created-scale integers stay exact. Leading
  ;; zeros and decimals still go through the token path.
  (is (eql 0 (cadr-ai::parse-json "0")))
  (is (eql 0 (cadr-ai::parse-json "-0")))
  (is (eql -12 (cadr-ai::parse-json "-12")))
  (is (eql 1786665600 (cadr-ai::parse-json "1786665600")))
  (is (eql 1786665600000 (cadr-ai::parse-json "1786665600000")))
  (signals cadr-ai::json-parse-error
    (cadr-ai::parse-json "01"))
  (signals cadr-ai::json-parse-error
    (cadr-ai::parse-json "00"))
  (signals cadr-ai::json-parse-error
    (cadr-ai::parse-json "-01"))
  (is (= 1/80 (cadr-ai::parse-json "1.25e-2")))
  (is (= (* 123 (expt 10 65))
         (cadr-ai::parse-json "123e65")))
  (is (null (cadr-ai::parse-json-simple-integer "12.3" 0 4)))
  (is (eql 12 (cadr-ai::parse-json-simple-integer "12" 0 2))))

(test goal20-json-single-element-array-is-a-vector
  (let ((one (cadr-ai::parse-json "[1]"))
        (two (cadr-ai::parse-json "[1,2]"))
        (empty (cadr-ai::parse-json "[]")))
    (is (vectorp one))
    (is (= 1 (length one)))
    (is (eql 1 (aref one 0)))
    (is (vectorp two))
    (is (= 2 (length two)))
    (is (eql 1 (aref two 0)))
    (is (eql 2 (aref two 1)))
    (is (vectorp empty))
    (is (zerop (length empty)))))

(test goal20-json-interns-streaming-object-keys
  (let ((first (cadr-ai::parse-json "{\"content\":\"a\"}"))
        (second (cadr-ai::parse-json "{\"content\":\"b\"}"))
        (key-a nil)
        (key-b nil))
    (maphash (lambda (key value)
               (declare (ignore value))
               (when (string= key "content")
                 (setf key-a key)))
             first)
    (maphash (lambda (key value)
               (declare (ignore value))
               (when (string= key "content")
                 (setf key-b key)))
             second)
    (is (string= key-a "content"))
    (is (eq key-a key-b))))

(test goal20-json-interns-session-jsonl-object-keys
  ;; session_load / journal_read: pairing-fixture keys that used to
  ;; go through COPY-UNESCAPED on every line.
  (let ((first
          (cadr-ai::parse-json
           "{\"parentId\":null,\"timestamp\":\"t\",\"message\":{}}"))
        (second
          (cadr-ai::parse-json
           "{\"parentId\":\"e0\",\"timestamp\":\"u\",\"message\":{}}"))
        (keys-a nil)
        (keys-b nil))
    (maphash (lambda (key value)
               (declare (ignore value))
               (push key keys-a))
             first)
    (maphash (lambda (key value)
               (declare (ignore value))
               (push key keys-b))
             second)
    (dolist (name '("parentId" "timestamp" "message"))
      (let ((a (find name keys-a :test #'string=))
            (b (find name keys-b :test #'string=)))
        (is (string= a name))
        (is (eq a b))))))

(test goal20-json-interns-session-jsonl-string-values
  ;; Values, not keys.  "assistant" / "user" / "message" as field
  ;; contents skip COPY-UNESCAPED.  Unique strings still copy.
  (let ((first
          (cadr-ai::parse-json
           "{\"role\":\"assistant\",\"kind\":\"message\"}"))
        (second
          (cadr-ai::parse-json
           "{\"role\":\"assistant\",\"kind\":\"user\"}")))
    (is (eq (cadr-ai::json-get first "role")
            (cadr-ai::json-get second "role")))
    (is (string= (cadr-ai::json-get first "role") "assistant"))
    (is (eq (cadr-ai::json-get first "kind")
            (cadr-ai::json-get
             (cadr-ai::parse-json "{\"x\":\"message\"}") "x")))
    (is (string= (cadr-ai::json-get second "kind") "user"))
    (let* ((source "{\"x\":\"unique-value\"}")
           (parsed (cadr-ai::parse-json source)))
      (setf (char source 6) #\z)
      (is (string= "unique-value" (cadr-ai::json-get parsed "x"))))))

(test goal20-json-object-exact-size-round-trip
  ;; parse-object stacks <=8 pairs then MAKE-HASH-TABLE :size COUNT.
  ;; 8-key (no grow) and 64-key (spill) must both round-trip.
  (let* ((eight
           (cadr-ai::parse-json
            "{\"api\":1,\"content\":2,\"model\":3,\"provider\":4,\"role\":5,\"stopReason\":6,\"timestamp\":7,\"usage\":8}"))
         (keys '("api" "content" "model" "provider" "role"
                 "stopReason" "timestamp" "usage")))
    (is (hash-table-p eight))
    (is (= 8 (hash-table-count eight)))
    (dolist (key keys)
      (is (cadr-ai::json-present-p eight key))))
  (let ((object (cadr-ai::json-object)))
    (dotimes (index 64)
      (cadr-ai::json-put
       object
       (format nil "k~D" index)
       index))
    (let ((parsed (cadr-ai::parse-json (cadr-ai::stringify-json object))))
      (is (= 64 (hash-table-count parsed)))
      (dotimes (index 64)
        (is (eql index
                 (cadr-ai::json-get
                  parsed
                  (format nil "k~D" index))))))))

(test goal20-json-interns-value-set-keys
  ;; "thinking" is a closed value and also a session object key.
  ;; Reuse the value table; do not grow either intern set.
  (let ((first (cadr-ai::parse-json "{\"thinking\":\"x\"}"))
        (second (cadr-ai::parse-json "{\"thinking\":\"y\"}"))
        (key-a nil)
        (key-b nil))
    (maphash (lambda (key value)
               (declare (ignore value))
               (when (string= key "thinking")
                 (setf key-a key)))
             first)
    (maphash (lambda (key value)
               (declare (ignore value))
               (when (string= key "thinking")
                 (setf key-b key)))
             second)
    (is (eq key-a key-b))
    (is (string= key-a "thinking"))))

(test goal20-json-parse-string-defers-base-p
  ;; PARSE-STRING no longer tracks base-p per character.  The copy
  ;; path still yields SIMPLE-BASE-STRING for ASCII and a character
  ;; string for unicode.
  (let ((ascii
          (cadr-ai::json-get
           (cadr-ai::parse-json "{\"k\":\"ascii-id-01\"}") "k"))
        (uni
          (cadr-ai::json-get
           (cadr-ai::parse-json "{\"k\":\"中文\"}") "k")))
    (is (string= ascii "ascii-id-01"))
    (is (typep ascii 'simple-base-string))
    (is (string= uni "中文"))))

(test goal20-json-copy-unescaped-is-one-window-copy
  ;; Drives COPY-UNESCAPED-JSON-STRING itself: one window copy, no
  ;; shared storage, ASCII result is a SIMPLE-BASE-STRING.
  (let* ((source (coerce "{\"k\":\"ascii-id-01\"}" 'simple-string))
         (copied
           (cadr-ai::copy-unescaped-json-string source 6 17 t)))
    (is (string= "ascii-id-01" copied))
    (is (typep copied 'simple-base-string))
    (setf (char source 6) #\z)
    (is (string= "ascii-id-01" copied)))
  (let* ((source (coerce "abcdefgh" 'simple-base-string))
         (copied
           (cadr-ai::copy-unescaped-json-string source 1 4 t)))
    (is (string= "bcd" copied))
    (is (typep copied 'simple-base-string))
    (setf (schar source 1) #\z)
    (is (string= "bcd" copied)))
  (let* ((source (coerce "{\"k\":\"中文\"}" 'simple-string))
         (copied
           (cadr-ai::copy-unescaped-json-string source 6 8 nil)))
    (is (string= "中文" copied))
    (setf (char source 6) #\x)
    (is (string= "中文" copied))))

(test goal20-json-object-fields-skip-top-level-hash
  ;; Session JSONL top-level object: visit keys, no EQUAL hash.
  ;; Nested objects still parse as hash tables.
  (let ((keys nil)
        (values nil))
    (is (eq t
            (cadr-ai::parse-json-object-fields
             "{\"type\":\"message\",\"parentId\":null,\"message\":{\"role\":\"user\"}}"
             (lambda (key value)
               (push key keys)
               (push value values)))))
    (setf keys (nreverse keys)
          values (nreverse values))
    (is (equal '("type" "parentId" "message") keys))
    (is (string= "message" (first values)))
    (is (cadr-ai::json-null-p (second values)))
    (is (hash-table-p (third values)))
    (is (string=
         "user"
         (cadr-ai::json-get (third values) "role"))))
  (signals cadr-ai::json-parse-error
    (cadr-ai::parse-json-object-fields
     "[1]"
     (lambda (key value)
       (declare (ignore key value))))))

(test goal20-json-object-pairs-round-trip
  ;; Session tool-call arguments: tagged pairs, not EQUAL hash.
  (let ((pairs (list* :json-object (list "path" "x" "offset" 1))))
    (is (cadr-ai::json-object-pairs-p pairs))
    (is (string= "x" (cadr-ai::json-get pairs "path")))
    (is (eql 1 (cadr-ai::json-get pairs "offset")))
    (is (eq t (cadr-ai::json-present-p pairs "path")))
    (is (null (cadr-ai::json-present-p pairs "missing")))
    (is (string=
         "{\"offset\":1,\"path\":\"x\"}"
         (cadr-ai::stringify-json pairs)))))
