(in-package #:cadr-ai)

(defmethod build-request
    ((provider openai-codex-provider) model context
     &key stream-p max-tokens temperature reasoning
       cache-retention session-id tool-choice metadata)
  (let ((token (provider-oauth-access-token provider)))
    (unless (non-empty-string-p token)
      (error 'authentication-error
             :message "OpenAI Codex OAuth credential is missing"))
    (let ((request
            (build-request
             (make-openai-provider
              :oauth-access-token token
             :oauth-account-id
              (provider-oauth-account-id provider))
             (copy-model-with model)
             context
             :stream-p stream-p
             :max-tokens max-tokens
             :temperature temperature
             :reasoning reasoning
             :cache-retention cache-retention
             :session-id session-id
             :tool-choice tool-choice
             :metadata metadata)))
      (unless reasoning
        (remhash "reasoning"
                 (request-spec-payload request)))
      (setf (request-spec-provider request) :openai-codex)
      request)))
