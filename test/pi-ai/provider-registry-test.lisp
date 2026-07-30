(in-package #:pi-ai/tests)
(in-suite pi-ai-suite)

(test built-in-provider-registry-is-complete
  (let ((ids (mapcar #'pi-ai:provider-definition-id
                     (pi-ai:list-provider-definitions))))
    (is (equal '(:anthropic :deepseek :google :ollama :openai) ids)))
  (let ((deepseek (pi-ai:find-provider-definition :deepseek))
        (ollama (pi-ai:find-provider-definition :ollama)))
    (is (eq :openai-completions
            (pi-ai:provider-definition-protocol deepseek)))
    (is (string= "https://api.deepseek.com"
                 (pi-ai:provider-definition-base-url deepseek)))
    (is (string= "DEEPSEEK_API_KEY"
                 (pi-ai:provider-definition-key-environment deepseek)))
    (is (eq :openai-completions
            (pi-ai:provider-definition-protocol ollama)))
    (is (null (pi-ai:provider-definition-key-environment ollama)))))

(test provider-registry-constructs-protocol-adapter-and-model
  (multiple-value-bind (provider model)
      (pi-ai:instantiate-provider :deepseek :api-key "secret"
                                 :base-url "https://proxy.example/v1"
                                 :model-id "deepseek-v4-pro")
    (is (typep provider 'pi-ai:openai-completions-provider))
    (is (eq :openai-completions (pi-ai:model-api model)))
    (is (eq :deepseek (pi-ai:model-provider model)))
    (is (string= "https://proxy.example/v1"
                 (pi-ai:model-base-url model)))
    (is (string= "deepseek-v4-pro" (pi-ai:model-id model))))
  (multiple-value-bind (provider model)
      (pi-ai:instantiate-provider :ollama)
    (is (typep provider 'pi-ai:openai-completions-provider))
    (is (string= "http://localhost:11434"
                 (pi-ai:model-base-url model)))))

(test provider-registry-rejects-missing-required-key
  (signals pi-ai:configuration-error
    (pi-ai:instantiate-provider :deepseek :api-key nil))
  (signals pi-ai:configuration-error
    (pi-ai:find-provider-definition :not-real)))
