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
