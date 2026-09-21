(in-package #:cadr-ai/tests)

(in-suite cadr-ai-suite)

(test goal24-copilot-gpt-6-astra-uses-responses-api
  (let ((metadata
          (cadr-ai:find-model-metadata :github-copilot "gpt-6-astra")))
    (is (eq :openai-responses (cadr-ai:model-metadata-api metadata)))
    (is (equal '(:supports-openai-grammar-tools t)
               (cadr-ai:model-metadata-compat metadata)))))
