(in-package #:cadr-ai/tests)

(in-suite cadr-ai-suite)

(test goal24-anthropic-messages-models-carry-prompt-cache-lifetimes
  (let* ((metadata
           (cadr-ai:find-model-metadata :anthropic "claude-sonnet-4-6"))
         (model (cadr-ai::model-from-metadata metadata))
         (cache (cadr-ai:model-prompt-cache model)))
    (is (eq :anthropic (cadr-ai:model-provider model)))
    (is (eq :anthropic-messages (cadr-ai:model-api model)))
    (is (= 300 (getf cache :short)))
    (is (= 3600 (getf cache :long)))))

(test goal24-non-anthropic-models-have-null-prompt-cache
  (flet ((cache-of (provider id)
           (cadr-ai:model-prompt-cache
            (cadr-ai::model-from-metadata
             (cadr-ai:find-model-metadata provider id)))))
    (is (null (cache-of :openai "gpt-4.1")))
    (is (null
         (cache-of
          :fireworks
          "accounts/fireworks/models/gpt-oss-120b")))))
