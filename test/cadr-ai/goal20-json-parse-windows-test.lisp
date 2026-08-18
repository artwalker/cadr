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
