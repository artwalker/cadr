(in-package #:cadr-ai/tests)
(in-suite cadr-ai-suite)

(test native-json-round-trips-rfc-values
  (let* ((source
           "{\"a\":[true,false,null,-12,1.25e2,\"你好\\n\\ud83d\\udc69\"]}")
         (value (cadr-ai::parse-json source))
         (array (cadr-ai::json-get value "a"))
         (encoded (cadr-ai::stringify-json value))
         (round-trip (cadr-ai::parse-json encoded)))
    (is (vectorp array))
    (is (eq t (aref array 0)))
    (is (null (aref array 1)))
    (is (eq 'cadr-ai::null (aref array 2)))
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
    (signals cadr-ai::json-parse-error
      (cadr-ai::parse-json source))))

(test native-json-rejects-excessive-container-nesting
  (let* ((depth
           (1+ cadr-ai::+maximum-json-nesting-depth+))
         (source
           (concatenate
            'string
            (make-string depth :initial-element #\[)
            "0"
            (make-string depth :initial-element #\]))))
    (signals cadr-ai::json-parse-error
      (cadr-ai::parse-json source))))

(test parse-json-does-not-relabel-damage-as-sse-protocol-error
  (handler-case
      (progn
        (cadr-ai::parse-json "{")
        (fail "parse-json must signal on truncated input"))
    (cadr-ai:sse-protocol-error ()
      (fail "session/config JSON damage must stay json-parse-error"))
    (cadr-ai::json-parse-error ()
      (pass))))

(test native-json-preserves-valid-large-and-fractional-numbers
  (let ((large (cadr-ai::parse-json "123e65"))
        (fraction (cadr-ai::parse-json "1.25e-2")))
    (is (= (* 123 (expt 10 65)) large))
    (is (= 1/80 fraction))
    (is (string=
         "0.0125"
         (cadr-ai::stringify-json fraction)))
    (is (= large
           (cadr-ai::parse-json
            (cadr-ai::stringify-json large))))))

(test native-json-stringify-rejects-non-finite-floats
  (signals error
    (cadr-ai::stringify-json
     sb-ext:double-float-positive-infinity)))

(test native-json-stringify-is-deterministic-and-escapes-controls
  (let ((object
          (cadr-ai::json-object
           "z" 1
           "a" (format nil "x~%y"))))
    (is (string=
         "{\"a\":\"x\\ny\",\"z\":1}"
         (cadr-ai::stringify-json object)))))

(test parse-json-accepts-fill-pointer-and-displaced-source
  (let* ((text "{\"k\":\"v\"}")
         (buffer (make-array (length text)
                             :element-type 'character
                             :fill-pointer (length text)
                             :adjustable t))
         (padded (concatenate 'string "xx" text "yy"))
         (window (make-array (length text)
                             :element-type 'character
                             :displaced-to padded
                             :displaced-index-offset 2)))
    (replace buffer text)
    (is (not (simple-string-p buffer)))
    (is (string=
         "v"
         (cadr-ai::json-get (cadr-ai::parse-json buffer) "k")))
    (is (string=
         "v"
         (cadr-ai::json-get (cadr-ai::parse-json window) "k")))))

(test native-json-removes-unpaired-surrogates
  (let* ((surrogate (code-char #xd83d))
         (emoji (code-char #x1f648))
         (text
           (coerce
            (list #\a surrogate #\b emoji)
            'string)))
    (is (string=
         (format nil "ab~C" emoji)
         (cadr-ai:sanitize-surrogates text)))
    (is (string=
         (format nil "\"ab~C\"" emoji)
         (cadr-ai::stringify-json text)))))
