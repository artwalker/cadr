(in-package #:cadr-evals/tests)

(in-suite cadr-evals-suite)

(defun reporter-test-result
    (harness score run-id)
  (let ((artifacts
          (cadr-ai::json-object
           "runId" run-id
           cadr-evals:+cadr-session-snapshot-artifact+
           "{\"type\":\"session\"}\n"
           cadr-evals:+eval-harness-iteration-artifact+
           (cadr-ai::json-object
            "schemaVersion" 1
            "evalSet" "extension authoring"
            "groupKey" "[\"hello\",1]"
            "harness" harness
            "baseline" "without-docs"
            "candidates" #( "with-docs" )
            "repetition" 1)
           "custom" "kept")))
    (cadr-evals::make-eval-result
     :output "Hello, Bob!"
     :usage
     (cadr-ai::json-object
      "totalTokens" 10
      "metadata"
      (cadr-ai::json-object
       "estimatedCostUsd" 0.01d0))
     :timings
     (cadr-ai::json-object "totalMs" 20)
     :artifacts artifacts
     :recorded-artifacts
     (list
      (cadr-evals:record-eval-source-artifact
       run-id
       (cadr-evals:make-eval-attachment
        :name "hello.lisp"
        :content-type "text/x-common-lisp"
        :body
        (format nil
                ";; score ~A~%(define-tool \"hello\")~%"
                score)))))))

(defun reporter-test-case
    (harness score run-id)
  (cadr-evals:make-eval-reporter-case
   :id (format nil "case-~A" harness)
   :file "src/extensions.eval.lisp"
   :name "creates, reloads, and uses a hello extension"
   :full-name
   (format nil "~A > creates, reloads, and uses a hello extension"
           harness)
   :status :passed
   :harness-name harness
   :score score
   :result
   (reporter-test-result harness score run-id)))

(defun reporter-test-lines (text)
  (remove-if
   (lambda (line)
     (zerop (length line)))
   (uiop:split-string text
                      :separator '(#\Newline))))

(test eval-harness-reporter-appends-permissioned-records-and-summarizes
  (let ((root (cadr-evals::make-eval-root)))
    (unwind-protect
         (let* ((output
                  (make-string-output-stream))
                (reporter
                  (cadr-evals:make-eval-harness-reporter
                   :artifact-directory root
                   :output output)))
           (cadr-evals:eval-reporter-record-case
            reporter
            (reporter-test-case
             "without-docs" 0 "run-baseline"))
           (cadr-evals:eval-reporter-record-case
            reporter
            (reporter-test-case
             "with-docs" 1 "run-candidate"))
           (let* ((runs-path
                    (merge-pathnames "runs.jsonl" root))
                  (lines
                    (reporter-test-lines
                     (uiop:read-file-string
                      runs-path
                      :external-format :utf-8)))
                  (first-record
                    (cadr-ai::parse-json
                     (first lines)))
                  (metadata
                    (cadr-ai::json-get
                     first-record "metadata"))
                  (references
                    (cadr-ai::json-get
                     first-record "artifacts")))
             (is (= 2 (length lines)))
             (is (= #o600
                    (logand #o777
                            (sb-posix:stat-mode
                             (sb-posix:stat
                              (namestring runs-path))))))
             (is (= 1
                    (cadr-ai::json-get
                     first-record "schemaVersion")))
             (is (string=
                  "without-docs"
                  (cadr-ai::json-get
                   first-record "harness")))
             (is (string=
                  "kept"
                  (cadr-ai::json-get
                   metadata "custom")))
             (is (null
                  (cadr-ai::json-get
                   metadata "runId")))
             (is (null
                  (cadr-ai::json-get
                   metadata
                   cadr-evals:+cadr-session-snapshot-artifact+)))
             (is (= 2 (length references)))
             (is (every
                  (lambda (reference)
                    (probe-file
                     (merge-pathnames
                      (cadr-ai::json-get
                       reference "path")
                      root)))
                  references)))
           (is (= 2
                  (length
                   (cadr-evals:eval-harness-reporter-observations
                    reporter))))
           (cadr-evals:eval-reporter-finish
            reporter :completed)
           (let ((text
                   (get-output-stream-string
                    output)))
             (is (search "Eval Comparisons" text))
             (is (search "Pass rate  +100.0 pp" text))))
      (when (probe-file root)
        (uiop:delete-directory-tree
         root :validate t
         :if-does-not-exist :ignore)))))

(test eval-harness-reporter-interrupted-notice-is-exact
  (let* ((output
           (make-string-output-stream))
         (reporter
           (cadr-evals:make-eval-harness-reporter
            :output output)))
    (cadr-evals:eval-reporter-finish
     reporter :interrupted)
    (is (string=
         (format nil
                 "~%Eval comparisons unavailable: test run interrupted.~%")
         (get-output-stream-string output)))))
