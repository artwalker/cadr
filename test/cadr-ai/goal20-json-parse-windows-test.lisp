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
