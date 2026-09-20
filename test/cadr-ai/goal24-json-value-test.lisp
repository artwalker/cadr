(in-package #:cadr-ai/tests)
(in-suite cadr-ai-suite)

(test goal24-json-value-p-accepts-primitives-and-nested
  ;; Baseline packages/ai/test/message-types.test.ts runtime expects
  ;; (not expectTypeOf): object / array / primitive / null details.
  (is (cadr-ai:json-value-p 'null))
  (is (cadr-ai:json-value-p t))
  (is (cadr-ai:json-value-p nil))
  (is (cadr-ai:json-value-p "diagnostic"))
  (is (cadr-ai:json-value-p 3))
  (is (cadr-ai:json-value-p 1.5d0))
  (let ((object
          (cadr-ai::json-object
           "path" "a.ts"
           "items" (cadr-ai::json-array "first")
           "summary" (cadr-ai::json-object "lines" 3))))
    (is (cadr-ai:json-value-p object))
    (is (= 3
           (cadr-ai::json-get
            (cadr-ai::json-get object "summary")
            "lines"))))
  (is (cadr-ai:json-value-p (cadr-ai::json-array "a" "b")))
  (is (cadr-ai:json-value-p
       (cadr-ai::json-array
        "a"
        (cadr-ai::json-object "count" 1))))
  (is (cadr-ai:json-value-p (list "a" "b")))
  (is (cadr-ai:json-value-p
       (list "a" (cadr-ai::json-object "count" 1)))))

(test goal24-json-value-p-rejects-non-json
  ;; Lisp stand-ins for baseline rejected Date / callback shapes.
  (is (not (cadr-ai:json-value-p #'identity)))
  (is (not (cadr-ai:json-value-p (lambda () nil))))
  (is (not (cadr-ai:json-value-p #p"/tmp/x")))
  (is (not (cadr-ai:json-value-p :keyword)))
  (is (not (cadr-ai:json-value-p 'some-symbol)))
  (is (cadr-ai:json-value-p (make-hash-table :test #'equal)))
  (let ((bad (make-hash-table :test #'equal)))
    (setf (gethash :path bad) "a.ts")
    (is (not (cadr-ai:json-value-p bad))))
  (let ((with-fn (make-hash-table :test #'equal)))
    (setf (gethash "callback" with-fn) #'identity)
    (is (not (cadr-ai:json-value-p with-fn))))
  (let ((with-date (make-hash-table :test #'equal)))
    (setf (gethash "value" with-date) #p"/tmp/when")
    (is (not (cadr-ai:json-value-p with-date)))))

(test goal24-ensure-json-value-preserves-json-structure
  (let* ((details
           (cadr-ai::json-object
            "path" "a.ts"
            "items" (cadr-ai::json-array "first")
            "summary" (cadr-ai::json-object "lines" 3)))
         (ensured (cadr-ai:ensure-json-value details))
         (safe (cadr-ai:coerce-json-value details)))
    (is (cadr-ai:json-value-p ensured))
    (is (= 3
           (cadr-ai::json-get
            (cadr-ai::json-get ensured "summary")
            "lines")))
    (is (equalp ensured safe))
    (is (string=
         (cadr-ai::stringify-json details)
         (cadr-ai::stringify-json ensured)))))

(test goal24-tool-call-and-result-round-trip-json-fields
  ;; Construction keeps Lisp conveniences (keyword plists) for getf
  ;; callers; session / ensure-json-value is the JsonValue boundary.
  (let* ((plist-arguments
           (list :path "a.ts"
                 :items (list "first")
                 :summary (list :lines 3)))
         (call
           (cadr-ai:make-tool-call
            :id "call-1"
            :name "read"
            :arguments plist-arguments))
         (json-arguments
           (cadr-ai:ensure-json-value
            (cadr-ai:tool-call-arguments call)))
         (result
           (cadr-ai:make-tool-result-message
            :tool-call-id "call-1"
            :tool-name "read"
            :content nil
            :details json-arguments
            :timestamp 1))
         (null-result
           (cadr-ai:make-tool-result-message
            :tool-call-id "call-1"
            :tool-name "read"
            :details 'null
            :timestamp 1))
         (array-result
           (cadr-ai:make-tool-result-message
            :tool-call-id "call-1"
            :tool-name "read"
            :details (cadr-ai::json-array "a" "b")
            :timestamp 1))
         (mixed-array-result
           (cadr-ai:make-tool-result-message
            :tool-call-id "call-1"
            :tool-name "read"
            :details (cadr-ai::json-array
                      "a"
                      (cadr-ai::json-object "count" 1))
            :timestamp 1))
         (primitive-result
           (cadr-ai:make-tool-result-message
            :tool-call-id "call-1"
            :tool-name "read"
            :details "diagnostic"
            :timestamp 1))
         (session-safe
           (cadr-ai:ensure-json-value
            (cadr-ai:tool-result-message-details result))))
    (is (equal "a.ts" (getf (cadr-ai:tool-call-arguments call) :path)))
    (is (cadr-ai:json-value-p json-arguments))
    (is (string= "a.ts" (cadr-ai::json-get json-arguments "path")))
    (is (= 3
           (cadr-ai::json-get
            (cadr-ai::json-get json-arguments "summary")
            "lines")))
    (is (cadr-ai:json-value-p
         (cadr-ai:tool-result-message-details result)))
    (is (= 3
           (cadr-ai::json-get
            (cadr-ai::json-get
             (cadr-ai:tool-result-message-details result)
             "summary")
            "lines")))
    (is (eq 'null
            (cadr-ai:tool-result-message-details null-result)))
    (is (cadr-ai:json-value-p
         (cadr-ai:tool-result-message-details array-result)))
    (is (equalp
         #("a" "b")
         (cadr-ai:tool-result-message-details array-result)))
    (is (string=
         "a"
         (aref
          (cadr-ai:tool-result-message-details mixed-array-result)
          0)))
    (is (= 1
           (cadr-ai::json-get
            (aref
             (cadr-ai:tool-result-message-details
              mixed-array-result)
             1)
            "count")))
    (is (string=
         "diagnostic"
         (cadr-ai:tool-result-message-details primitive-result)))
    (is (string=
         (cadr-ai::stringify-json
          (cadr-ai:tool-result-message-details result))
         (cadr-ai::stringify-json session-safe)))))
