(in-package #:cadr-ai/tests)
(in-suite cadr-ai-suite)

(test built-in-provider-registry-is-complete
  (let ((ids (mapcar #'cadr-ai:provider-definition-id
                     (cadr-ai:list-provider-definitions))))
    (is (equal '(:anthropic :deepseek :google :ollama :openai) ids)))
  (let ((deepseek (cadr-ai:find-provider-definition :deepseek))
        (ollama (cadr-ai:find-provider-definition :ollama)))
    (is (eq :openai-completions
            (cadr-ai:provider-definition-protocol deepseek)))
    (is (string= "https://api.deepseek.com"
                 (cadr-ai:provider-definition-base-url deepseek)))
    (is (string= "DEEPSEEK_API_KEY"
                 (cadr-ai:provider-definition-key-environment deepseek)))
    (is (eq :openai-completions
            (cadr-ai:provider-definition-protocol ollama)))
    (is (null (cadr-ai:provider-definition-key-environment ollama)))))

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
  (multiple-value-bind (provider model)
      (cadr-ai:instantiate-provider :ollama)
    (is (typep provider 'cadr-ai:openai-completions-provider))
    (is (string= "http://localhost:11434"
                 (cadr-ai:model-base-url model)))))

(test provider-registry-rejects-missing-required-key
  (signals cadr-ai:configuration-error
    (cadr-ai:instantiate-provider :deepseek :api-key nil))
  (signals cadr-ai:configuration-error
    (cadr-ai:find-provider-definition :not-real)))
