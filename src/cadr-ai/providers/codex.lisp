(in-package #:cadr-ai)

(defun codex-header-absent-p (value)
  (or (null value) (json-null-p value)))

(defun codex-delete-header (headers name)
  (remove name headers :key #'car :test #'string-equal))

(defun codex-set-header (headers name value)
  (acons name value (codex-delete-header headers name)))

(defun codex-apply-header-entries (headers entries &key delete-null-p)
  (dolist (entry entries)
    (let ((name (car entry))
          (value (cdr entry)))
      (setf headers
            (if (and delete-null-p (codex-header-absent-p value))
                (codex-delete-header headers name)
                (codex-set-header headers name value)))))
  headers)

(defun apply-codex-header-overrides
    (headers model caller-headers token account-id)
  ;; pi@4a080252f #10429. Defaults go on first. Model headers, then
  ;; caller headers, replace them. A null caller value removes the
  ;; name. Authorization and the account id are written last.
  (let ((locked
          (loop for name in '("content-type" "accept" "openai-beta"
                              "session-id" "x-client-request-id")
                for value =
                (cdr (assoc name headers :test #'string-equal))
                when value
                  collect (cons name value))))
    (setf headers
          (codex-set-header
           (codex-delete-header
            (codex-delete-header headers "originator")
            "user-agent")
           "originator" +openai-originator+))
    (setf headers
          (codex-apply-header-entries
           headers (model-headers model)))
    (setf headers
          (codex-apply-header-entries
           headers caller-headers :delete-null-p t))
    (dolist (entry locked)
      (setf headers
            (codex-set-header headers (car entry) (cdr entry))))
    (codex-set-header
     (codex-set-header
      headers "authorization" (format nil "Bearer ~A" token))
     "chatgpt-account-id" account-id)))

(defmethod build-request
    ((provider openai-codex-provider) model context
     &key stream-p max-tokens temperature reasoning
       cache-retention session-id tool-choice metadata
       thinking-budgets headers sampling-params
       (service-tier nil service-tier-p)
       (reasoning-summary nil reasoning-summary-p)
       &allow-other-keys)
  (let ((token (provider-oauth-access-token provider)))
    (unless (non-empty-string-p token)
      (error 'authentication-error
             :message "OpenAI Codex OAuth credential is missing"))
    (let ((request
            (apply #'build-request
                   (make-openai-provider
                    :oauth-access-token token
                    :oauth-account-id
                    (provider-oauth-account-id provider))
                   (copy-model-with model)
                   context
                   (append
                    (list :stream-p stream-p
                          :max-tokens max-tokens
                          :temperature temperature
                          :reasoning reasoning
                          :cache-retention cache-retention
                          :session-id session-id
                          :tool-choice tool-choice
                          :metadata metadata
                          :thinking-budgets thinking-budgets
                          :sampling-params sampling-params)
                    (when service-tier-p
                      (list :service-tier service-tier))
                    (when reasoning-summary-p
                      (list :reasoning-summary reasoning-summary))))))
      ;; The fixed Codex Responses baseline has no max_output_tokens field.  The
      ;; ChatGPT backend rejects the ordinary Responses parameter.
      (remhash "max_output_tokens"
               (request-spec-payload request))
      (setf (request-spec-provider request) :openai-codex
            (request-spec-headers request)
            (apply-codex-header-overrides
             (request-spec-headers request)
             model headers token
             (provider-oauth-account-id provider)))
      request)))
