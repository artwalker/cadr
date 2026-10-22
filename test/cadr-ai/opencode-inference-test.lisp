(in-package #:cadr-ai/tests)
(in-suite cadr-ai-suite)

(defun opencode-catalog-model (provider id)
  (let ((meta (cadr-ai:find-model-metadata provider id)))
    (make-model
     :id (cadr-ai:model-metadata-id meta)
     :provider provider
     :api (cadr-ai:model-metadata-api meta)
     :base-url (cadr-ai:model-metadata-base-url meta)
     :reasoning-p (cadr-ai:model-metadata-reasoning-p meta)
     :compat (cadr-ai:model-metadata-compat meta))))

(test opencode-models-use-inference-hosts
  (dolist (metadata (cadr-ai:list-model-metadata))
    (when (member (cadr-ai:model-metadata-provider metadata)
                  '(:opencode :opencode-go))
      (is (null
           (search "zen"
                   (cadr-ai:model-metadata-base-url metadata))))))
  (let ((gemini
          (cadr-ai:find-model-metadata :opencode "gemini-3-flash"))
        (qwen
          (cadr-ai:find-model-metadata :opencode-go "deepseek-v4-pro"))
        (m3
          (cadr-ai:find-model-metadata :opencode-go "minimax-m3"))
        (go (cadr-ai:find-provider-definition :opencode-go))
        (zen (cadr-ai:find-provider-definition :opencode)))
    (is (eq :google-generative-ai
            (cadr-ai:model-metadata-api gemini)))
    (is (string=
         "https://opencode.ai/inference/v1"
         (cadr-ai:model-metadata-base-url gemini)))
    (is (eq :openai-completions
            (cadr-ai:model-metadata-api qwen)))
    (is (string=
         "https://opencode.ai/inference/go/v1"
         (cadr-ai:model-metadata-base-url qwen)))
    (is (eq :anthropic-messages
            (cadr-ai:model-metadata-api m3)))
    (is (string=
         "https://opencode.ai/inference/go"
         (cadr-ai:model-metadata-base-url m3)))
    (is (member :google-generative-ai
                (cadr-ai::provider-definition-protocols go)))
    (is (string=
         "https://opencode.ai/inference/go/v1"
         (cadr-ai:provider-definition-base-url go)))
    (is (string=
         "https://opencode.ai/inference/v1"
         (cadr-ai:provider-definition-base-url zen))))
  (is (string=
       "https://opencode.ai/inference/v1/models/gemini-3-flash:streamGenerateContent?alt=sse"
       (request-spec-url
        (build-request
         (make-google-provider :api-key "key")
         (opencode-catalog-model :opencode "gemini-3-flash")
         (make-context)
         :stream-p t))))
  (is (string=
       "https://opencode.ai/inference/go/v1/messages"
       (request-spec-url
        (build-request
         (make-anthropic-provider :api-key "key")
         (opencode-catalog-model :opencode-go "minimax-m3")
         (make-context)
         :stream-p t))))
  (is (string=
       "https://opencode.ai/inference/go/v1/chat/completions"
       (request-spec-url
        (build-request
         (cadr-ai:make-openai-completions-provider :api-key "key")
         (opencode-catalog-model :opencode-go "deepseek-v4-pro")
         (make-context)
         :stream-p t)))))
