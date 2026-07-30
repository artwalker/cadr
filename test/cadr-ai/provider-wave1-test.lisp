(in-package #:cadr-ai/tests)
(in-suite cadr-ai-suite)

(defmacro define-wave1-provider-test
    (test-name provider protocol base-url key-environment
     default-model catalog-count)
  `(test ,test-name
     (let ((definition
             (cadr-ai:find-provider-definition ,provider)))
       (is (eq ,protocol
               (cadr-ai:provider-definition-protocol definition)))
       (is (string= ,base-url
                    (cadr-ai:provider-definition-base-url definition)))
       (is (string= ,key-environment
                    (cadr-ai:provider-definition-key-environment
                     definition)))
       (is (string= ,default-model
                    (cadr-ai:provider-definition-default-model definition))))
     (is (= ,catalog-count
            (length (cadr-ai:list-model-metadata ,provider))))
     (multiple-value-bind (provider-object model)
         (cadr-ai:instantiate-provider ,provider :api-key "fixture-key")
       (let ((request
               (build-request
                provider-object model (sample-context)
                :stream-p t
                :max-tokens 4096
                :cache-retention :none)))
         (is
          (json-equal-p
           (request-fixture
            ,(format nil "~(~A~)-default" provider))
           (request-spec-payload request))
          "~A payload differs:~%actual: ~A~%expected: ~A"
          ,provider
          (cadr-ai::stringify-json
           (request-spec-payload request))
          (cadr-ai::stringify-json
           (request-fixture
            ,(format nil "~(~A~)-default" provider))))))
     (signals cadr-ai:configuration-error
       (cadr-ai:instantiate-provider ,provider :api-key nil))))

(define-wave1-provider-test
    ant-ling-provider-matches-fixed-catalog
    :ant-ling :openai-completions
    "https://api.ant-ling.com/v1"
    "ANT_LING_API_KEY" "Ring-2.6-1T" 3)

(define-wave1-provider-test
    cerebras-provider-matches-fixed-catalog
    :cerebras :openai-completions
    "https://api.cerebras.ai/v1"
    "CEREBRAS_API_KEY" "zai-glm-4.7" 3)

(define-wave1-provider-test
    groq-provider-matches-fixed-catalog
    :groq :openai-completions
    "https://api.groq.com/openai/v1"
    "GROQ_API_KEY" "openai/gpt-oss-120b" 7)

(define-wave1-provider-test
    huggingface-provider-matches-fixed-catalog
    :huggingface :openai-completions
    "https://router.huggingface.co/v1"
    "HF_TOKEN" "moonshotai/Kimi-K2.6" 51)

(define-wave1-provider-test
    minimax-provider-matches-fixed-catalog
    :minimax :anthropic-messages
    "https://api.minimax.io/anthropic"
    "MINIMAX_API_KEY" "MiniMax-M2.7" 3)

(define-wave1-provider-test
    minimax-cn-provider-matches-fixed-catalog
    :minimax-cn :anthropic-messages
    "https://api.minimaxi.com/anthropic"
    "MINIMAX_CN_API_KEY" "MiniMax-M2.7" 3)

(define-wave1-provider-test
    moonshotai-provider-matches-fixed-catalog
    :moonshotai :openai-completions
    "https://api.moonshot.ai/v1"
    "MOONSHOT_API_KEY" "kimi-k2.6" 10)

(define-wave1-provider-test
    moonshotai-cn-provider-matches-fixed-catalog
    :moonshotai-cn :openai-completions
    "https://api.moonshot.cn/v1"
    "MOONSHOT_API_KEY" "kimi-k2.6" 10)

(define-wave1-provider-test
    qwen-token-plan-provider-matches-fixed-catalog
    :qwen-token-plan :openai-completions
    "https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1"
    "QWEN_TOKEN_PLAN_API_KEY" "qwen3.7-max" 15)

(define-wave1-provider-test
    qwen-token-plan-cn-provider-matches-fixed-catalog
    :qwen-token-plan-cn :openai-completions
    "https://token-plan.cn-beijing.maas.aliyuncs.com/compatible-mode/v1"
    "QWEN_TOKEN_PLAN_CN_API_KEY" "qwen3.7-max" 15)

(define-wave1-provider-test
    together-provider-matches-fixed-catalog
    :together :openai-completions
    "https://api.together.ai/v1"
    "TOGETHER_API_KEY" "moonshotai/Kimi-K2.6" 17)

(define-wave1-provider-test
    xiaomi-provider-matches-fixed-catalog
    :xiaomi :openai-completions
    "https://api.xiaomimimo.com/v1"
    "XIAOMI_API_KEY" "mimo-v2.5-pro" 6)
