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
    (is (string=
         "0.05"
         (cadr-ai::stringify-json 1/20)))
    (is (string=
         "-1.25"
         (cadr-ai::stringify-json -5/4)))
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

(test stringify-json-writes-unescaped-spans-and-escapes
  (is (string=
       "\"abcdefghij\""
       (cadr-ai::stringify-json "abcdefghij")))
  (is (string=
       "\"ab\\\"cd\\\\ef\\ngh\""
       (cadr-ai::stringify-json
        (format nil "ab\"cd\\ef~%gh")))))

(test write-json-string-simple-base-equals-generic-mutants
  ;; Unescaped simple-base-string shortcut vs generic CHAR walk
  ;; (wide character vector). Escapes, controls, and surrogates
  ;; still match. Drives shipped stringify-json / WRITE-JSON-STRING.
  (flet ((wide (text)
           (let ((padded (concatenate 'string "xx" text "yy")))
             (make-array
              (length text)
              :element-type 'character
              :displaced-to padded
              :displaced-index-offset 2))))
    (let ((plain "abcdefghij"))
      (is (simple-string-p plain))
      (is (not (simple-string-p (wide plain))))
      (is (string=
           (cadr-ai::stringify-json plain)
           (cadr-ai::stringify-json (wide plain)))))
    (let ((escaped (format nil "ab\"cd\\ef~%gh~Cij" #\Tab)))
      (is (string=
           "\"ab\\\"cd\\\\ef\\ngh\\tij\""
           (cadr-ai::stringify-json escaped)))
      (is (string=
           (cadr-ai::stringify-json escaped)
           (cadr-ai::stringify-json (wide escaped)))))
    (let* ((surrogate (code-char #xd83d))
           (emoji (code-char #x1f648))
           (text
             (coerce
              (list #\a surrogate #\b emoji)
              'string)))
      (is (string=
           (format nil "\"ab~C\"" emoji)
           (cadr-ai::stringify-json text))))))

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

(test utf8-string-ascii-is-simple-base-string
  ;; Shipped UTF8-STRING: all-ASCII is copy-unescaped-json-octets
  ;; (pre-sized simple-base-string, ub32 schar). Not octets-to-string.
  (dolist (text (list "ascii-id-01"
                      "xyz"
                      (make-string 220 :initial-element #\x)))
    (let* ((octets (cadr-ai::utf8-octets text))
           (decoded (cadr-ai::utf8-string octets)))
      (is (string= text decoded))
      (is (typep decoded 'simple-base-string))
      (setf (aref octets 0) 122)
      (is (string= text decoded)))))

(test utf8-string-mixed-matches-octets-to-string
  ;; Mixed ASCII runs + UTF-8 scalars, including the pairing
  ;; fixture line. Drives the shipped decoder, not a reimplementation.
  (dolist (text (list
                 ""
                 "é🙂中文 mixed tail line"
                 (format nil "~A~%~A~%"
                         (make-string 220 :initial-element #\x)
                         "é🙂中文 mixed tail line")
                 "一"
                 (format nil "你好~%👩")))
    (let ((octets (cadr-ai::utf8-octets text)))
      (is (string=
           (sb-ext:octets-to-string octets :external-format :utf-8)
           (cadr-ai::utf8-string octets))))))

(test utf8-string-range-does-not-read-outside-window
  (let* ((prefix (cadr-ai::utf8-octets "aaa"))
         (mid (cadr-ai::utf8-octets "é🙂中文"))
         (suffix (cadr-ai::utf8-octets "zzz"))
         (octets
           (concatenate '(simple-array (unsigned-byte 8) (*))
                        prefix mid suffix))
         (start (length prefix))
         (end (+ start (length mid)))
         (decoded (cadr-ai::utf8-string octets start end)))
    (is (string= "é🙂中文" decoded))
    (setf (aref octets 0) 90)
    (setf (aref octets (1- (length octets))) 90)
    (is (string= "é🙂中文" decoded))))

(test utf8-string-invalid-matches-octets-to-string
  ;; Overlong / surrogate / out-of-range must take the same
  ;; octets-to-string fallback as the previous decoder.
  (flet ((decode (octets)
           (handler-case
               (cons :ok
                     (cadr-ai::utf8-string octets))
             (error () '(:error))))
         (sb-decode (octets)
           (handler-case
               (cons :ok
                     (sb-ext:octets-to-string
                      octets :external-format :utf-8))
             (error () '(:error)))))
    (dolist (bytes '((#xe0 #x80 #x80)
                     (#xed #xa0 #x80)
                     (#xf4 #x90 #x80 #x80)
                     (#xf0 #x80 #x80 #x80)
                     (#xc2)
                     (#x80)))
      (let ((octets
              (coerce bytes '(simple-array (unsigned-byte 8) (*)))))
        (is (equal (sb-decode octets) (decode octets)))))))
