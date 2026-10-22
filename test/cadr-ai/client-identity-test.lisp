(in-package #:cadr-ai/tests)

(in-suite cadr-ai-suite)

;;; Locked to pi@4a080252f packages/ai/src/utils/identity.ts and
;;; packages/ai/test/identity.test.ts. Product strings are cadr's:
;;; slug "cadr", referer the canonical repository, runtime sbcl.

(defun expected-detailed-user-agent
    (&optional (version (cadr-ai::cadr-version)))
  (format nil "cadr/~A (~(~A~); sbcl/~A; ~(~A~))"
          version
          (software-type)
          (lisp-implementation-version)
          (machine-type)))

(defun identity-header-value (headers name)
  (cdr (assoc name headers :test #'string-equal)))

(defun identity-completions-headers
    (provider base-url &key headers identity session-id model-headers)
  (cadr-ai:request-spec-headers
   (cadr-ai:build-request
    (cadr-ai:make-openai-completions-provider :api-key "key")
    (cadr-ai:make-model
     :id "test-model"
     :name "Test Model"
     :provider provider
     :api :openai-completions
     :base-url base-url
     :max-tokens 16
     :headers model-headers)
    (sample-context)
    :stream-p nil
    :session-id session-id
    :identity identity
    :headers headers)))

(test client-identity-formats-user-agents
  (is (string= (expected-detailed-user-agent)
               (cadr-ai::format-user-agent)))
  (is (string= (expected-detailed-user-agent "9.9.9")
               (cadr-ai::format-user-agent
                (cadr-ai::client-identity :version "9.9.9"))))
  (is (string= "cadr"
               (cadr-ai::format-user-agent
                (cadr-ai::client-identity
                 :user-agent :short
                 :version "9.9.9"))))
  (is (string= "acme/1.0"
               (cadr-ai::format-user-agent
                (cadr-ai::client-identity
                 :user-agent "acme/1.0")))))

(test client-identity-merges-field-by-field
  (is (null (cadr-ai::merge-client-identity nil nil)))
  (let ((merged
          (cadr-ai::merge-client-identity
           (cadr-ai::client-identity
            :attribution cadr-ai::+cadr-attribution+
            :user-agent :short)
           (cadr-ai::client-identity :version "1.0.0"))))
    (is (eq :short (getf merged :user-agent)))
    (is (eq cadr-ai::+cadr-attribution+
            (getf merged :attribution)))
    (is (string= "1.0.0" (getf merged :version))))
  (let ((merged
          (cadr-ai::merge-client-identity
           (cadr-ai::client-identity
            :attribution cadr-ai::+cadr-attribution+)
           (cadr-ai::client-identity :attribution nil))))
    (is (eq :off (getf merged :attribution)))))

(test client-identity-sends-no-attribution-unless-enabled
  (let ((headers
          (cadr-ai::attribution-headers
           :openrouter "https://openrouter.ai/api/v1")))
    (is (null headers)))
  (is (null
       (cadr-ai::attribution-headers
        :openrouter "https://openrouter.ai/api/v1"
        (cadr-ai::client-identity :attribution nil))))
  (let ((headers
          (identity-completions-headers
           :openrouter "https://openrouter.ai/api/v1")))
    (is (string= (expected-detailed-user-agent)
                 (identity-header-value headers "user-agent")))
    (is (null (identity-header-value headers "http-referer")))
    (is (= 1
           (count "user-agent" headers
                  :key #'car :test #'string-equal)))))

(test client-identity-attributes-openrouter-requests
  (let ((headers
          (cadr-ai::attribution-headers
           :openrouter "https://openrouter.ai/api/v1"
           (cadr-ai::client-identity
            :attribution cadr-ai::+cadr-attribution+))))
    (is (string= "https://github.com/artwalker/cadr"
                 (identity-header-value headers "HTTP-Referer")))
    (is (string= "cadr"
                 (identity-header-value headers "X-OpenRouter-Title")))
    (is (string= "cli-agent"
                 (identity-header-value
                  headers "X-OpenRouter-Categories"))))
  (let ((headers
          (cadr-ai::attribution-headers
           :openrouter "https://openrouter.ai/api/v1"
           (cadr-ai::client-identity
            :attribution
            (cadr-ai::client-attribution
             "acme" "https://acme.example"
             '("cli-agent" "cloud-agent"))))))
    (is (string= "https://acme.example"
                 (identity-header-value headers "HTTP-Referer")))
    (is (string= "acme"
                 (identity-header-value headers "X-OpenRouter-Title")))
    (is (string= "cli-agent,cloud-agent"
                 (identity-header-value
                  headers "X-OpenRouter-Categories"))))
  (let ((headers
          (cadr-ai::attribution-headers
           :openrouter "https://openrouter.ai/api/v1"
           (cadr-ai::client-identity
            :attribution
            (cadr-ai::client-attribution
             "acme" "https://acme.example" '())))))
    (is (null
         (identity-header-value
          headers "X-OpenRouter-Categories"))))
  (is (string= "pi"
               (identity-header-value
                (cadr-ai::attribution-headers
                 :custom "not-a-url-openrouter.ai"
                 (cadr-ai::client-identity
                  :attribution
                  (cadr-ai::client-attribution
                   "pi" "https://pi.dev" '("cli-agent"))))
                "X-OpenRouter-Title"))))

(test client-identity-attributes-nvidia-and-opencode
  (is (string= "Pi"
               (identity-header-value
                (cadr-ai::attribution-headers
                 :nvidia "https://example.test/v1"
                 (cadr-ai::client-identity
                  :attribution
                  (cadr-ai::client-attribution
                   "pi" "https://pi.dev" '("cli-agent"))))
                "X-BILLING-INVOKE-ORIGIN")))
  (is (string= "Acme"
               (identity-header-value
                (cadr-ai::attribution-headers
                 :custom-nim "https://integrate.api.nvidia.com/v1"
                 (cadr-ai::client-identity
                  :attribution
                  (cadr-ai::client-attribution
                   "acme" "https://acme.example")))
                "X-BILLING-INVOKE-ORIGIN")))
  (is (string= "Cadr"
               (identity-header-value
                (cadr-ai::attribution-headers
                 :nvidia "https://integrate.api.nvidia.com/v1"
                 (cadr-ai::client-identity
                  :attribution cadr-ai::+cadr-attribution+))
                "X-BILLING-INVOKE-ORIGIN")))
  (is (string= "pi"
               (identity-header-value
                (cadr-ai::attribution-headers
                 :opencode "https://opencode.ai/zen/v1"
                 (cadr-ai::client-identity
                  :attribution
                  (cadr-ai::client-attribution "pi" "https://pi.dev")))
                "x-opencode-client")))
  (is (string= "acme"
               (identity-header-value
                (cadr-ai::attribution-headers
                 :custom "https://opencode.ai/zen/v1"
                 (cadr-ai::client-identity
                  :attribution
                  (cadr-ai::client-attribution
                   "acme" "https://acme.example")))
                "x-opencode-client")))
  (is (null
       (identity-header-value
        (cadr-ai::attribution-headers
         :openrouter "https://openrouter.ai/api/v1"
         (cadr-ai::client-identity
          :attribution cadr-ai::+cadr-attribution+))
        "X-BILLING-INVOKE-ORIGIN")))
  (is (null
       (cadr-ai::attribution-headers
        :vercel-ai-gateway "https://ai-gateway.vercel.sh/v1"
        (cadr-ai::client-identity
         :attribution cadr-ai::+cadr-attribution+)))))

(test client-identity-applies-below-model-and-request-headers
  (let ((headers
          (identity-completions-headers
           :openrouter "https://openrouter.ai/api/v1"
           :identity
           (cadr-ai::client-identity
            :attribution cadr-ai::+cadr-attribution+
            :user-agent :short)
           :model-headers
           '(("X-OpenRouter-Title" . "model-title"))
           :headers '(("HTTP-Referer" . nil)))))
    (is (string= "cadr"
                 (identity-header-value headers "user-agent")))
    (is (string= "model-title"
                 (identity-header-value headers "x-openrouter-title")))
    (is (null (identity-header-value headers "http-referer")))
    (is (string= "cli-agent"
                 (identity-header-value
                  headers "x-openrouter-categories")))))

(test client-identity-keeps-impersonating-model-user-agent
  (let ((headers
          (identity-completions-headers
           :github-copilot "https://api.githubcopilot.com"
           :identity
           (cadr-ai::client-identity :user-agent "acme")
           :model-headers
           '(("User-Agent" . "GitHubCopilotChat/0.35.0")))))
    (is (string= "GitHubCopilotChat/0.35.0"
                 (identity-header-value headers "user-agent")))
    (is (= 1
           (count "user-agent" headers
                  :key #'car :test #'string-equal)))))

(test client-identity-sends-opencode-session-to-custom-providers
  (let ((plain
          (identity-completions-headers
           :custom-opencode "https://opencode.ai/zen/v1"
           :session-id "session-1"))
        (configured
          (identity-completions-headers
           :custom-opencode "https://opencode.ai/zen/v1"
           :session-id "session-1"
           :headers '(("X-OpenCode-Session" . "configured"))))
        (attributed
          (identity-completions-headers
           :opencode "https://opencode.ai/zen/v1"
           :identity
           (cadr-ai::client-identity
            :attribution cadr-ai::+cadr-attribution+))))
    (is (string= "session-1"
                 (identity-header-value plain "x-opencode-session")))
    (is (null (identity-header-value plain "x-opencode-client")))
    (is (string= "configured"
                 (identity-header-value
                  configured "x-opencode-session")))
    (is (string= "cadr"
                 (identity-header-value
                  attributed "x-opencode-client")))
    (is (null
         (identity-header-value
          attributed "x-opencode-session")))))

(test client-identity-hides-attribution-from-header-hook
  (let* ((cadr-ai::*identity-deleted-header-names* (list nil))
         (model
           (cadr-ai:make-model
            :id "test-model"
            :provider :openrouter
            :api :openai-completions
            :base-url "https://openrouter.ai/api/v1"
            :max-tokens 16))
         (provider
           (cadr-ai:make-openai-completions-provider :api-key "key"))
         (identity
           (cadr-ai::client-identity
            :attribution cadr-ai::+cadr-attribution+
            :user-agent :short))
         (seen nil)
         (request
           (cadr-ai:build-request
            provider model (sample-context)
            :stream-p nil
            :identity identity)))
    (cadr-ai::apply-provider-request-callbacks
     request model nil
     (lambda (headers)
       (setf seen headers)
       (acons "HTTP-Referer" nil headers))
     :identity identity
     :provider provider)
    (is (null (identity-header-value seen "http-referer")))
    (is (null (identity-header-value seen "x-openrouter-title")))
    (is (null (identity-header-value seen "x-openrouter-categories")))
    (is (string= "cadr"
                 (identity-header-value seen "user-agent")))
    (is (null
         (identity-header-value
          (cadr-ai:request-spec-headers request)
          "http-referer")))
    (is (string= "cadr"
                 (identity-header-value
                  (cadr-ai:request-spec-headers request)
                  "x-openrouter-title")))))

(test client-identity-reduces-bedrock-user-agent
  (is (string= (format nil "cadr/~A" (cadr-ai::cadr-version))
               (cadr-ai::bedrock-identity-user-agent)))
  (is (string= "cadr"
               (cadr-ai::bedrock-identity-user-agent
                (cadr-ai::client-identity :user-agent :short))))
  (is (string= "acme/1"
               (cadr-ai::bedrock-identity-user-agent
                (cadr-ai::client-identity :user-agent "acme/1")))))

(test client-identity-attributes-openrouter-image-requests
  (let ((headers
          (cadr-ai:request-spec-headers
           (cadr-ai::build-openrouter-image-request
            (cadr-ai:make-image-model
             :id "image"
             :provider :openrouter
             :base-url "https://openrouter.ai/api/v1"
             :headers '(("X-OpenRouter-Title" . "model-title")))
            (cadr-ai:make-images-context)
            "key"
            '(("HTTP-Referer" . "https://caller.example"))
            :identity
            (cadr-ai::client-identity
             :attribution cadr-ai::+cadr-attribution+
             :user-agent :short)))))
    (is (string= "cadr"
                 (identity-header-value headers "user-agent")))
    (is (string= "model-title"
                 (identity-header-value headers "x-openrouter-title")))
    (is (string= "https://caller.example"
                 (identity-header-value headers "http-referer")))
    (is (string= "cli-agent"
                 (identity-header-value
                  headers "x-openrouter-categories")))))
