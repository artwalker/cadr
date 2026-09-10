(in-package #:cadr-ai)

(defmethod build-request
    ((provider openai-codex-provider) model context
     &key stream-p max-tokens temperature reasoning
       cache-retention session-id tool-choice metadata
       thinking-budgets)
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
             :metadata metadata
             :thinking-budgets thinking-budgets)))
      (unless reasoning
        (remhash "reasoning"
                 (request-spec-payload request)))
      ;; The fixed Codex Responses baseline has no max_output_tokens field.  The
      ;; ChatGPT backend rejects the ordinary Responses parameter.
      (remhash "max_output_tokens"
               (request-spec-payload request))
      (setf (request-spec-provider request) :openai-codex)
      request)))
