(in-package #:pi-ai/tests)
(in-suite pi-ai-suite)

(test native-json-round-trips-rfc-values
  (let* ((source
           "{\"a\":[true,false,null,-12,1.25e2,\"你好\\n\\ud83d\\udc69\"]}")
         (value (pi-ai::parse-json source))
         (array (pi-ai::json-get value "a"))
         (encoded (pi-ai::stringify-json value))
         (round-trip (pi-ai::parse-json encoded)))
    (is (vectorp array))
    (is (eq t (aref array 0)))
    (is (null (aref array 1)))
    (is (eq 'pi-ai::null (aref array 2)))
    (is (= -12 (aref array 3)))
    (is (= 125d0 (aref array 4)))
    (is (string= (format nil "你好~%👩")
                 (aref array 5)))
    (is (equalp value round-trip))))

(test native-json-rejects-invalid-or-trailing-input
  (dolist (source
           '("{\"a\":1,}"
             "[01]"
             "\"\\ud800\""
             "true false"
             "{\"x\":\"control
\"}"))
    (signals pi-ai:sse-protocol-error
      (pi-ai::parse-json source))))

(test native-json-rejects-excessive-container-nesting
  (let* ((depth
           (1+ pi-ai::+maximum-json-nesting-depth+))
         (source
           (concatenate
            'string
            (make-string depth :initial-element #\[)
            "0"
            (make-string depth :initial-element #\]))))
    (signals pi-ai:sse-protocol-error
      (pi-ai::parse-json source))))

(test native-json-preserves-valid-large-and-fractional-numbers
  (let ((large (pi-ai::parse-json "123e65"))
        (fraction (pi-ai::parse-json "1.25e-2")))
    (is (= (* 123 (expt 10 65)) large))
    (is (= 1/80 fraction))
    (is (string=
         "0.0125"
         (pi-ai::stringify-json fraction)))
    (is (= large
           (pi-ai::parse-json
            (pi-ai::stringify-json large))))))

(test native-json-stringify-rejects-non-finite-floats
  (signals error
    (pi-ai::stringify-json
     sb-ext:double-float-positive-infinity)))

(test native-json-stringify-is-deterministic-and-escapes-controls
  (let ((object
          (pi-ai::json-object
           "z" 1
           "a" (format nil "x~%y"))))
    (is (string=
         "{\"a\":\"x\\ny\",\"z\":1}"
         (pi-ai::stringify-json object)))))
