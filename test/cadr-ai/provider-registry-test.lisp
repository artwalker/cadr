(in-package #:cadr-ai/tests)
(in-suite cadr-ai-suite)

(test built-in-provider-registry-is-complete
  (let ((ids (mapcar #'cadr-ai:provider-definition-id
                     (cadr-ai:list-provider-definitions))))
    (is (= 38 (length ids)))
    (is (member :amazon-bedrock ids))
    (is (member :google-vertex ids))
    (is (member :radius ids))
    (is (not (member :ollama ids))))
  (let ((deepseek (cadr-ai:find-provider-definition :deepseek)))
    (is (eq :openai-completions
            (cadr-ai:provider-definition-protocol deepseek)))
    (is (string= "https://api.deepseek.com"
                 (cadr-ai:provider-definition-base-url deepseek)))
    (is (string= "DEEPSEEK_API_KEY"
                 (cadr-ai:provider-definition-key-environment deepseek)))))

(test goal13-oauth-presentation-metadata-is-owned-by-each-provider
  (dolist
      (expected
       '((:anthropic
          "Anthropic"
          "Anthropic (Claude Pro/Max)"
          nil
          "Complete login in your browser. If the browser is on another machine, paste the final redirect URL here."
          "Complete login in your browser, or paste the authorization code / redirect URL here:")
         (:github-copilot
          "GitHub Copilot" "GitHub Copilot" nil nil nil)
         (:kimi-coding
          "Kimi For Coding" "Kimi Code (subscription)"
          "Sign in with Kimi Code" nil nil)
         (:openai-codex
          "OpenAI Codex" "OpenAI (ChatGPT Plus/Pro)" nil
          "A browser window should open. Complete login to finish."
          "Complete login in your browser, or paste the authorization code / redirect URL here:")
         (:openrouter
          "OpenRouter" "OpenRouter OAuth" "Sign in with OpenRouter"
          "Complete sign-in in your browser. If the browser is on another machine, paste the final redirect URL here."
          "Complete sign-in in your browser, or paste the authorization code / redirect URL here:")
         (:radius
          "Radius" "Radius" nil "Continue in your browser." nil)
         (:xai
          "xAI" "xAI (Grok/X subscription)"
          "Sign in with SuperGrok or X Premium" nil nil)))
    (destructuring-bind
        (provider-id provider-name method-name login-label
         auth-url-instructions manual-input-message)
        expected
      (let* ((definition
               (cadr-ai:find-provider-definition provider-id))
             (metadata
               (cadr-ai::provider-definition-oauth-metadata
                definition)))
        (is (string= provider-name
                     (cadr-ai:provider-definition-name definition)))
        (is (string= provider-name
                     (cadr-ai::oauth-provider-metadata-provider-name
                      metadata)))
        (is (string= method-name
                     (cadr-ai::oauth-provider-metadata-method-name
                      metadata)))
        (is (equal login-label
                   (cadr-ai::oauth-provider-metadata-login-label
                    metadata)))
        (is (equal auth-url-instructions
                   (cadr-ai::oauth-provider-metadata-auth-url-instructions
                    metadata)))
        (is (equal manual-input-message
                   (cadr-ai::oauth-provider-metadata-manual-input-message
                    metadata)))))))

(test provider-registry-constructs-protocol-adapter-and-model
  (multiple-value-bind (provider model)
      (cadr-ai:instantiate-provider :deepseek :api-key "secret"
                                 :base-url "https://proxy.example/v1"
                                 :model-id "deepseek-v4-pro")
    (is (typep provider 'cadr-ai:openai-completions-provider))
    (is (eq :openai-completions (cadr-ai:model-api model)))
    (is (eq :deepseek (cadr-ai:model-provider model)))
    (is (string= "https://proxy.example/v1"
                 (cadr-ai:model-base-url model)))
    (is (string= "deepseek-v4-pro" (cadr-ai:model-id model))))
  (signals cadr-ai:configuration-error
    (cadr-ai:instantiate-provider :ollama)))

(test provider-registry-rejects-missing-required-key
  (signals cadr-ai:configuration-error
    (cadr-ai:instantiate-provider :deepseek :api-key nil))
  (signals cadr-ai:configuration-error
    (cadr-ai:find-provider-definition :not-real)))
