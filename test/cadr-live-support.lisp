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
   #:provider-endpoint-unavailable-p
   #:live-sse-thinking-content-fields
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

(defun provider-endpoint-unavailable-p (text)
  "True when TEXT is a provider-side endpoint/route outage, not a parse miss."
  (and text
       (search "endpoint is unavailable" text :test #'char-equal)))

(defun live-sse-thinking-content-fields (value &optional acc)
  "Collect keys whose values are nonempty thinking/reasoning strings.

Usage counters (`reasoning_tokens`) and request echoes
(`reasoning: {effort, summary}`) are not content.  A live sweep
treats leftover string fields as a suspected parse miss."
  (cond
    ((hash-table-p value)
     (maphash
      (lambda (key child)
        (when (and (stringp key)
                   (member key
                           '("reasoning" "reasoning_content"
                             "reasoning_text" "thinking")
                           :test #'string-equal)
                   (stringp child)
                   (plusp (length child)))
          (pushnew key acc :test #'string-equal))
        (setf acc (live-sse-thinking-content-fields child acc)))
      value)
     acc)
    ((vectorp value)
     (loop for child across value
           do (setf acc
                    (live-sse-thinking-content-fields child acc)))
     acc)
    ((consp value)
     (dolist (child value acc)
       (setf acc (live-sse-thinking-content-fields child acc))))
    (t acc)))

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

(defun live-support-environment-value (name)
  (let ((value (uiop:getenv name)))
    (and value
         (let ((trimmed
                 (string-trim
                  '(#\Space #\Tab #\Newline #\Return)
                  value)))
           (and (plusp (length trimmed))
                trimmed)))))

(defun prepare-opencode-go-credential
    (&optional
       (path (cadr-cli:default-auth-path)))
  "OpenCode Go API key from auth.json or OPENCODE_API_KEY.

File wins when both exist so an isolated HOME with a written
credential is not overridden by a leftover process environment.
OPENCODE_API_KEY is the DeepSeek-style env gate for machines that
never wrote auth.json."
  (or
   (when (probe-file path)
     (let ((credential
             (cadr-ai:read-auth-credential
              path :opencode-go)))
       (and
        (typep credential
               'cadr-ai:api-key-credential)
        (plusp
         (length
          (cadr-ai:api-key-credential-key credential)))
        credential)))
   (let ((key
           (live-support-environment-value
            "OPENCODE_API_KEY")))
     (and key
          (cadr-ai:make-api-key-credential
           :provider :opencode-go
           :key key)))))

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
