(in-package #:cadr-live-tests)

(defun live-test-specs ()
  (list
   (cadr-live-test-support:make-live-test-spec
    :name
    'cadr-ai/live-tests::live-deepseek-chat-completions-streams
    :markers '("DEEPSEEK_OK"))
   (cadr-live-test-support:make-live-test-spec
    :name
    'cadr-ai/live-tests::live-anthropic-stream-preserves-two-turn-context
    :markers '("FIRST_OK" "FIRST_OK:SECOND_OK"))
   (cadr-live-test-support:make-live-test-spec
    :name
    'cadr-cli/live-tests::live-deepseek-print-mode-emits-only-final-text
    :markers '("DEEPSEEK_PRINT_OK"))
   (cadr-live-test-support:make-live-test-spec
    :name
    'cadr-cli/live-tests::live-opencode-go-explicit-model-uses-api-key-credential
    :markers '("OPENCODE_GO_EXPLICIT_OK"))
   (cadr-live-test-support:make-live-test-spec
    :name
    'cadr-evals/live-tests::live-deepseek-eval-smoke
    :markers '("Paris"))
   (cadr-live-test-support:make-live-test-spec
    :name
    'cadr-evals/live-tests::live-opencode-go-eval-smoke-uses-explicit-model-and-api-key
    :markers '("Paris"))
   (cadr-live-test-support:make-live-test-spec
    :name
    'cadr-ai/live-tests::live-opencode-go-mimo-stream-emits-thinking)
   (cadr-live-test-support:make-live-test-spec
    :name
    'cadr-evals/live-tests::live-deepseek-self-extension-write-reload-and-invoke
    :policy :model-behavior)
   (cadr-live-test-support:make-live-test-spec
    :name
    'cadr-evals/live-tests::live-deepseek-repository-fail-fix-pass-loop
    :policy :model-behavior)))

(defun unexpected-failure-p (result)
  (typep result 'fiveam::unexpected-test-failure))

(defun result-description (result)
  (with-output-to-string (stream)
    (format stream "Check: ~S~%Reason: ~A"
            (fiveam::test-expr result)
            (or (fiveam::reason result)
                "No reason supplied"))
    (when (unexpected-failure-p result)
      (format stream "~%Condition: ~A"
              (fiveam::actual-condition result)))))

(defun classify-failures (spec failures)
  (cond
    ((some #'unexpected-failure-p failures)
     (values
      :unable-to-determine
      "The item raised an unexpected condition; the report does not guess whether the cause is local, upstream, or environmental."))
    ((eq :model-behavior
         (cadr-live-test-support:live-test-spec-policy spec))
     (values
      :suspected-model-output-variation
      "The provider returned normally, but a model-directed behavioral assertion failed."))
    ((let ((markers
             (cadr-live-test-support:live-test-spec-markers spec)))
       (and markers
            (every
             (lambda (failure)
               (let ((description
                       (result-description failure)))
                 (some
                  (lambda (marker)
                    (search marker description
                            :test #'char-equal))
                  markers)))
             failures)))
     (values
      :suspected-model-output-variation
      "The provider returned normally and only an exact model-output assertion failed."))
    (t
     (values
      :suspected-product-defect
      "A deterministic provider, transport, usage, status, or state-integrity assertion failed."))))

(defun quota-exhausted-failures-p (failures)
  "True when a provider-side quota/usage-limit signal explains the failures.

An account that is out of quota cannot exercise the product contract; the
item is then reported as an explicit SKIP naming the quota signal instead of
as a product-defect failure. Missing-credential skips already follow the same
environmental classification path. Any failure carrying the signal suffices:
the remaining assertion failures (empty output, non-zero status) are
downstream consequences of the account-level refusal."
  (and failures
       (some
        (lambda (failure)
          (cadr-live-test-support:provider-quota-exhausted-p
           (result-description failure)))
        failures)))

(defun quota-exhausted-skip-reason (failures)
  (let ((signal
          (some
           (lambda (needle)
             (and
              (some
               (lambda (failure)
                 (search
                  needle
                  (result-description failure)
                  :test #'char-equal))
               failures)
              needle))
           '("usage limit"
             "insufficient_quota"
             "quota exceeded"
             "monthly usage limit reached"
             "available balance"
             "out of budget"))))
    (format
     nil
     "Provider account quota/usage limit reached (~A); live verification cannot run"
     signal)))

(defun failure-output (failures captured-output)
  (with-output-to-string (stream)
    (loop for failure in failures
          for index from 1
          do (format stream "Failure ~D:~%~A~%"
                     index
                     (result-description failure)))
    (let ((captured
            (string-trim
             '(#\Space #\Tab #\Newline #\Return)
             captured-output)))
      (when (plusp (length captured))
        (format stream "Captured output:~%~A~%" captured)))))

(defun run-fiveam-live-test (spec)
  (let ((captured (make-string-output-stream))
        (results nil))
    (let ((*standard-output* captured)
          (*error-output* captured)
          (fiveam:*test-dribble* captured))
      (setf results
            (fiveam:run
             (cadr-live-test-support:live-test-spec-name spec)
             :print-names nil)))
    (let* ((passes
             (count-if #'fiveam::test-passed-p results))
           (skips
             (remove-if-not #'fiveam::test-skipped-p results))
           (failures
             (remove-if-not #'fiveam::test-failure-p results))
           (checks (length results)))
      (cond
        (failures
         (if (quota-exhausted-failures-p failures)
             (cadr-live-test-support:make-live-test-result
              :name (cadr-live-test-support:live-test-spec-name spec)
              :status :skip
              :checks checks
              :passes passes
              :skips (+ (length skips) (length failures))
              :skip-reason
              (quota-exhausted-skip-reason failures))
             (multiple-value-bind (nature basis)
                 (classify-failures spec failures)
               (cadr-live-test-support:make-live-test-result
                :name (cadr-live-test-support:live-test-spec-name spec)
                :status :fail
                :checks checks
                :passes passes
                :skips (length skips)
                :failures (length failures)
                :failure-output
                (failure-output
                 failures
                 (get-output-stream-string captured))
                :nature nature
                :basis basis))))
        (skips
         (cadr-live-test-support:make-live-test-result
          :name (cadr-live-test-support:live-test-spec-name spec)
          :status :skip
          :checks checks
          :passes passes
          :skips (length skips)
          :skip-reason
          (format nil "~{~A~^; ~}"
                  (mapcar #'fiveam::reason skips))))
        ((zerop checks)
         (cadr-live-test-support:make-live-test-result
          :name (cadr-live-test-support:live-test-spec-name spec)
          :status :fail
          :checks 1
          :failures 1
          :failure-output "FiveAM returned no result for the live item."
          :nature :unable-to-determine
          :basis
          "The named live item was loaded but produced no check result."))
        (t
         (cadr-live-test-support:make-live-test-result
          :name (cadr-live-test-support:live-test-spec-name spec)
          :status :pass
          :checks checks
          :passes passes))))))

(defun run-tests ()
  (cadr-live-test-support:write-live-test-report
   (cadr-live-test-support:execute-live-test-specs
    (live-test-specs)
    #'run-fiveam-live-test)))
