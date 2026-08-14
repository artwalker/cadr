(defpackage #:cadr-live-test-support
  (:use #:cl)
  (:export
   #:execute-live-test-specs
   #:live-test-result-basis
   #:live-test-result-checks
   #:live-test-result-failure-output
   #:live-test-result-failures
   #:live-test-result-name
   #:live-test-result-nature
   #:live-test-result-passes
   #:live-test-result-skip-reason
   #:live-test-result-skips
   #:live-test-result-status
   #:live-test-spec-markers
   #:live-test-spec-name
   #:live-test-spec-policy
   #:make-live-test-result
   #:make-live-test-spec
   #:prepare-opencode-go-credential
   #:prepare-kimi-coding-credential
   #:prepare-openai-codex-credential
   #:provider-quota-exhausted-p
   #:write-live-test-report))

(in-package #:cadr-live-test-support)

(defstruct live-test-spec
  name
  (policy :contract)
  (markers nil))

(defstruct live-test-result
  name
  status
  (checks 0)
  (passes 0)
  (skips 0)
  (failures 0)
  skip-reason
  failure-output
  nature
  basis)

(defun provider-quota-exhausted-p (text)
  "True when TEXT carries a provider-side quota/usage-limit message.

The matched phrases mirror the canonical quota signals already used by
src/cadr-ai/support/retry.lisp and src/cadr-agent/loop/events.lisp. A live
item that only fails because the account is out of quota cannot exercise the
product contract, so it is reported as an explicit SKIP with this reason
instead of a suspected product defect."
  (and text
       (some
        (lambda (needle)
          (search needle text :test #'char-equal))
        '("usage limit"
          "insufficient_quota"
          "quota exceeded"
          "monthly usage limit reached"
          "available balance"
          "out of budget"))))

(defun execute-live-test-specs (specs executor)
  (mapcar
   (lambda (spec)
     (handler-case
         (funcall executor spec)
       (error (condition)
         (make-live-test-result
          :name (live-test-spec-name spec)
          :status :fail
          :checks 1
          :failures 1
          :failure-output (princ-to-string condition)
          :nature :unable-to-determine
          :basis
          "The live item raised an unexpected condition before its contract could be classified."))))
   specs))

(defun live-test-nature-label (nature)
  (ecase nature
    (:suspected-product-defect "suspected product defect")
    (:suspected-model-output-variation "suspected model-output variance")
    (:unable-to-determine "cannot determine")))

(defun write-live-test-report (results &optional (stream *standard-output*))
  (let ((run-count 0)
        (pass-items 0)
        (skip-items 0)
        (fail-items 0)
        (checks 0)
        (passes 0)
        (skips 0)
        (failures 0))
    (format stream "Live test report~%")
    (dolist (result results)
      (incf checks (live-test-result-checks result))
      (incf passes (live-test-result-passes result))
      (incf skips (live-test-result-skips result))
      (incf failures (live-test-result-failures result))
      (let ((name
              (symbol-name
               (live-test-result-name result))))
        (ecase (live-test-result-status result)
          (:pass
           (incf run-count)
           (incf pass-items)
           (format stream "PASS ~A (~D checks)~%"
                   name
                   (live-test-result-checks result)))
          (:skip
           (incf skip-items)
           (format stream "SKIP ~A: ~A~%"
                   name
                   (or (live-test-result-skip-reason result)
                       "No reason supplied")))
          (:fail
           (incf run-count)
           (incf fail-items)
           (format stream "FAIL ~A [~A]~%"
                   name
                   (live-test-nature-label
                    (or (live-test-result-nature result)
                        :unable-to-determine)))
           (format stream "Basis: ~A~%"
                   (or (live-test-result-basis result)
                       "No classification basis supplied."))
           (format stream "Failure output:~%~A~%"
                   (or (live-test-result-failure-output result)
                       "No failure output was captured."))))))
    (format stream
            "Items: ~D, run: ~D, pass: ~D, skip: ~D, fail: ~D~%"
            (length results) run-count pass-items skip-items fail-items)
    (format stream
            "Checks: ~D, pass: ~D, skip: ~D, fail: ~D~%"
            checks passes skips failures)
    (zerop fail-items)))

(defun credential-expiring-p (credential)
  (<= (cadr-ai:oauth-credential-expires credential)
      (+ (cadr-ai::unix-milliseconds) 300000)))

(defun prepare-kimi-coding-credential
    (&optional
       (path (cadr-cli:default-auth-path)))
  (unless (probe-file path)
    (return-from prepare-kimi-coding-credential nil))
  (let ((credential
          (cadr-ai:read-auth-credential
           path :kimi-coding)))
    (and
     (typep credential
            'cadr-ai:api-key-credential)
     credential)))

(defun prepare-opencode-go-credential
    (&optional
       (path (cadr-cli:default-auth-path)))
  (unless (probe-file path)
    (return-from prepare-opencode-go-credential nil))
  (let ((credential
          (cadr-ai:read-auth-credential
           path :opencode-go)))
    (and
     (typep credential
            'cadr-ai:api-key-credential)
     credential)))

(defun prepare-openai-codex-credential
    (&optional
       (path (cadr-cli:default-auth-path))
       (refresh-function
         #'cadr-ai:refresh-openai-oauth-credential))
  (unless (probe-file path)
    (return-from prepare-openai-codex-credential nil))
  (let ((credential
          (cadr-cli:auth-storage-modify
           (cadr-cli:make-file-auth-storage path)
           :openai-codex
           (lambda (current)
             (when
                 (and
                  (typep current
                         'cadr-ai:oauth-credential)
                  (credential-expiring-p current))
               (let ((refreshed
                       (funcall refresh-function
                                current)))
                 (unless
                     (typep refreshed
                            'cadr-ai:oauth-credential)
                   (error
                    "OpenAI Codex OAuth refresh returned an invalid credential"))
                 refreshed))))))
    (and
     (typep credential
            'cadr-ai:oauth-credential)
     credential)))
