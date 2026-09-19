(in-package #:cadr-ai/tests)
(in-suite cadr-ai-suite)

(defun request-fixture (name)
  (parse-json
   (read-fixture
    (format nil "test/fixtures/requests/~A.json" name))))

(defun strict-sample-context ()
  (make-context
   :system-prompt "Be precise."
   :messages
   (list
    (make-user-message
     :content "Inspect README.md"
     :timestamp 1))
   :tools
   (list
    (apply
     (symbol-function 'make-tool)
     (list
      :name "read"
      :description "Read a file."
      :parameters (sample-schema)
      :constrained-sampling
      '(:type :json-schema :strict :require))))))

(defun compat-model (&rest arguments)
  (apply (symbol-function 'make-model) arguments))

(test anthropic-adaptive-thinking-and-long-cache-match-reference
  (let* ((model
           (compat-model
            :id "claude-opus-4-8"
            :provider :anthropic
            :api :anthropic-messages
            :base-url "https://api.anthropic.com"
            :max-tokens 4096
            :reasoning-p t
            :thinking-level-map
            '((:off . "disabled")
              (:high . "high")
              (:xhigh . "xhigh")
              (:max . "max"))
            :compat
            '(:force-adaptive-thinking t
              :supports-strict-tools t)))
         (request
           (build-request
            (make-anthropic-provider :api-key "key")
            model
            (strict-sample-context)
            :stream-p t
            :max-tokens 4096
            :reasoning :xhigh
            :cache-retention :long
            :session-id "fixture-session")))
    (is
     (json-equal-p
      (request-fixture "anthropic-adaptive-long-cache")
      (request-spec-payload request)))))

(test anthropic-thinking-disable-matches-reference
  (let* ((model
           (compat-model
            :id "claude-opus-4-8"
            :provider :anthropic
            :api :anthropic-messages
            :base-url "https://api.anthropic.com"
            :max-tokens 4096
            :reasoning-p t
            :thinking-level-map
            '((:off . "disabled"))
            :compat
            '(:force-adaptive-thinking t)))
         (request
           (build-request
            (make-anthropic-provider :api-key "key")
            model
            (sample-context)
            :stream-p t
            :max-tokens 4096
            :cache-retention :none)))
    (is
     (json-equal-p
      (request-fixture "anthropic-thinking-disabled")
      (request-spec-payload request)))))

(test openai-completions-qwen-reasoning-matches-reference
  (let* ((model
          (compat-model
           :id "qwen3.7-max"
           :provider :qwen-token-plan
           :api :openai-completions
           :base-url
           "https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1"
           :max-tokens 4096
           :reasoning-p t
           :thinking-level-map
           '((:high . "high")
             (:max . "max"))
           :compat
           '(:thinking-format :qwen
             :supports-developer-role nil
             :supports-store nil
             :supports-reasoning-effort t)))
         (request
           (build-request
            (cadr-ai:make-openai-completions-provider
             :api-key "key")
            model
            (sample-context)
            :stream-p t
            :max-tokens 4096
            :reasoning :high
            :cache-retention :none
            :tool-choice "required")))
    (is
     (json-equal-p
      (request-fixture
       "openai-completions-qwen-reasoning")
      (request-spec-payload request)))))

(test openai-completions-baseten-reasoning-matches-reference
  ;; pi@d981de122 api/openai-completions.ts:779-793 — the baseten
  ;; thinking format sends chat_template_args plus reasoning_effort.
  (let* ((model
           (compat-model
            :id "zai-org/GLM-5.2"
            :provider :baseten
            :api :openai-completions
            :base-url "https://inference.baseten.co/v1"
            :max-tokens 4096
            :reasoning-p t
            :thinking-level-map
            '((:off . "none")
              (:high . "high")
              (:max . "max"))
            :compat
            '(:thinking-format :baseten
              :chat-template-args
              (("enable_thinking" :var "thinking.enabled"
                :omit-when-off nil))
              :supports-usage-in-streaming t
              :max-tokens-field :max-tokens
              :supports-strict-mode t
              :supports-developer-role nil
              :supports-store nil
              :supports-reasoning-effort t
              :supports-long-cache-retention nil)))
         (request
           (build-request
            (cadr-ai:make-openai-completions-provider
             :api-key "key")
            model
            (sample-context)
            :stream-p t
            :max-tokens 4096
            :reasoning :high
            :cache-retention :none
            :tool-choice "required")))
    (is
     (json-equal-p
      (request-fixture
       "openai-completions-baseten-reasoning")
      (request-spec-payload request)))))

(test openai-completions-thinking-token-budget-matches-reference
  ;; pi@d981de122 api/openai-completions.ts:847-866 — vLLM caps
  ;; reasoning with a top-level thinking_token_budget; the budget is
  ;; min(level budget, max_tokens - 1024), so 4096-1024=3072 caps high.
  (let ((model
          (compat-model
           :id "vllm-reasoning-model"
           :provider :vllm
           :api :openai-completions
           :base-url "https://vllm.invalid/v1"
           :max-tokens 4096
           :reasoning-p t
           :compat
           '(:supports-reasoning-effort t
             :supports-thinking-token-budget t
             :max-tokens-field :max-tokens))))
    (dolist (case '((:high . "openai-completions-thinking-budget-high")
                    (:low . "openai-completions-thinking-budget-low")))
      (let ((request
              (build-request
               (cadr-ai:make-openai-completions-provider
                :api-key "key")
               model
               (sample-context)
               :stream-p t
               :max-tokens 4096
               :reasoning (car case)
               :cache-retention :none)))
        (is
         (json-equal-p
          (request-fixture (cdr case))
          (request-spec-payload request)))))))

(test openai-responses-reasoning-cache-matches-reference
  (let* ((model
           (compat-model
            :id "gpt-5.5"
            :provider :openai
            :api :openai-responses
            :base-url "https://api.openai.com"
            :max-tokens 4096
            :reasoning-p t
            :thinking-level-map
            '((:off . "none")
              (:high . "high")
              (:xhigh . "xhigh"))
            :compat
            '(:supports-strict-mode t
              :supports-long-cache-retention t)))
         (request
           (build-request
            (make-openai-provider :api-key "key")
            model
            (strict-sample-context)
            :stream-p t
            :max-tokens 4096
            :reasoning :high
            :cache-retention :long
            :session-id "fixture-session")))
    (is
     (json-equal-p
      (request-fixture
       "openai-responses-reasoning-cache")
      (request-spec-payload request)))))

(test google-thinking-high-matches-reference
  (let* ((model
           (compat-model
            :id "gemini-3.6-flash"
            :provider :google
            :api :google-generative-ai
            :base-url
            "https://generativelanguage.googleapis.com/v1beta"
            :max-tokens 4096
            :reasoning-p t))
         (request
           (build-request
            (make-google-provider :api-key "key")
            model
            (sample-context)
            :stream-p t
            :max-tokens 4096
            :reasoning :high)))
    (is
     (json-equal-p
      (request-fixture "google-thinking-high")
      (request-spec-payload request)))))

(test google-thinking-disable-matches-reference
  (let* ((model
           (compat-model
            :id "gemini-3.6-flash"
            :provider :google
            :api :google-generative-ai
            :base-url
            "https://generativelanguage.googleapis.com/v1beta"
            :max-tokens 4096
            :reasoning-p t))
         (request
           (build-request
            (make-google-provider :api-key "key")
            model
            (sample-context)
            :stream-p t
            :max-tokens 4096)))
    (is
     (json-equal-p
      (request-fixture "google-thinking-disabled")
      (request-spec-payload request)))))

(test anthropic-compat-flags-control-tools-temperature-and-cache-affinity
  (let* ((model
           (compat-model
            :id "compatible-claude"
            :provider :compatible
            :api :anthropic-messages
            :base-url "https://example.test"
            :max-tokens 4096
            :compat
            '(:supports-eager-tool-input-streaming nil
              :supports-cache-control-on-tools nil
              :supports-temperature nil
              :send-session-affinity-headers t)))
         (request
           (build-request
            (make-anthropic-provider :api-key "key")
            model
            (sample-context)
            :stream-p t
            :temperature 0.5
            :cache-retention :long
            :session-id "session-1"))
         (payload (request-spec-payload request))
         (tool (aref (cadr-ai::json-get payload "tools") 0))
         (headers (request-spec-headers request)))
    (is (not (cadr-ai::json-present-p
              tool "eager_input_streaming")))
    (is (not (cadr-ai::json-present-p tool "cache_control")))
    (is (not (cadr-ai::json-present-p payload "temperature")))
    (is (string=
         "fine-grained-tool-streaming-2025-05-14"
         (cdr (assoc "anthropic-beta" headers
                     :test #'string-equal))))
    (is (string=
         "session-1"
         (cdr (assoc "x-session-affinity" headers
                     :test #'string-equal))))))

(test anthropic-empty-thinking-signature-follows-model-compat
  (let* ((message
           (cadr-ai:make-assistant-message
            :content
            (list
             (cadr-ai:make-thinking-content
              :thinking "unfinished"
              :signature ""))
            :api :anthropic-messages
            :provider :compatible
            :model "compatible-claude"))
         (default-model
           (compat-model
            :id "compatible-claude"
            :provider :compatible
            :api :anthropic-messages
            :base-url "https://example.test"))
         (empty-signature-model
           (compat-model
            :id "compatible-claude"
            :provider :compatible
            :api :anthropic-messages
            :base-url "https://example.test"
            :compat '(:allow-empty-signature t)))
         (default-block
           (aref
            (cadr-ai::json-get
             (aref
              (cadr-ai::anthropic-messages
               default-model (list message))
              0)
             "content")
            0))
         (compat-block
           (aref
            (cadr-ai::json-get
             (aref
              (cadr-ai::anthropic-messages
               empty-signature-model (list message))
              0)
             "content")
            0)))
    (is (string= "text" (cadr-ai::json-get default-block "type")))
    (is (string= "thinking"
                 (cadr-ai::json-get compat-block "type")))
    (is (string= ""
                 (cadr-ai::json-get compat-block "signature")))))

(test openai-cache-keys-and-session-affinity-match-reference-limits
  (let* ((session-id
           "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-long")
         (model
           (compat-model
            :id "gpt-reasoning"
            :provider :openai
            :api :openai-responses
            :base-url "https://api.openai.com"
            :max-tokens 4096
            :reasoning-p t))
         (request
           (build-request
            (make-openai-provider :api-key "key")
            model
            (sample-context)
            :stream-p t
            :cache-retention :short
            :session-id session-id))
         (payload (request-spec-payload request))
         (headers (request-spec-headers request)))
    (is (= 64
           (length
            (cadr-ai::json-get payload "prompt_cache_key"))))
    (is (string= session-id
                 (cdr (assoc "session_id" headers
                             :test #'string-equal))))
    (is (string= session-id
                 (cdr (assoc "x-client-request-id" headers
                             :test #'string-equal))))))

(test openai-responses-cache-none-omits-affinity-headers
  (let* ((model
           (compat-model
            :id "gpt-reasoning"
            :provider :openai
            :api :openai-responses
            :base-url "https://api.openai.com"
            :max-tokens 4096
            :reasoning-p t))
         (request
           (build-request
            (make-openai-provider :api-key "key")
            model
            (sample-context)
            :stream-p t
            :cache-retention :none
            :session-id "session-disabled"))
         (payload (request-spec-payload request))
         (headers (request-spec-headers request)))
    (is (not (cadr-ai::json-present-p payload "prompt_cache_key")))
    (is (null (assoc "session_id" headers :test #'string-equal)))
    (is (null (assoc "x-client-request-id" headers
                     :test #'string-equal)))))

(test openai-completions-long-cache-matches-reference
  (let* ((session-id
           "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-long")
         (model
           (compat-model
            :id "gpt-chat"
            :provider :openai
            :api :openai-completions
            :base-url "https://api.openai.com"
            :max-tokens 4096
            :compat
            '(:supports-long-cache-retention t
              :send-session-affinity-headers t)))
         (request
           (build-request
            (cadr-ai:make-openai-completions-provider
             :api-key "key")
            model
            (sample-context)
            :stream-p t
            :cache-retention :long
            :session-id session-id))
         (payload (request-spec-payload request))
         (headers (request-spec-headers request)))
    (is (= 64
           (length
            (cadr-ai::json-get payload "prompt_cache_key"))))
    (is (string= "24h"
                 (cadr-ai::json-get payload
                                    "prompt_cache_retention")))
    (is (string= session-id
                 (cdr (assoc "session_id" headers
                             :test #'string-equal))))))

(test completions-compat-controls-max-store-thinking-and-tool-choice
  (let* ((model
           (compat-model
            :id "deepseek-reasoner"
            :provider :deepseek
            :api :openai-completions
            :base-url "https://api.deepseek.com"
            :max-tokens 4096
            :reasoning-p t
            :compat
            '(:thinking-format :deepseek
              :supports-store nil
              :max-tokens-field :max-tokens)))
         (request
           (build-request
            (cadr-ai:make-openai-completions-provider
             :api-key "key")
            model
            (sample-context)
            :stream-p t
            :max-tokens 2048
            :cache-retention :none
            :tool-choice "required"))
         (payload (request-spec-payload request)))
    (is (= 2048 (cadr-ai::json-get payload "max_tokens")))
    (is (not (cadr-ai::json-present-p payload "store")))
    (is (string=
         "disabled"
         (cadr-ai::json-get
          (cadr-ai::json-get payload "thinking")
          "type")))
    (is (string= "required"
                 (cadr-ai::json-get payload "tool_choice")))))

(test completions-omits-tool-choice-when-the-request-has-no-tools
  (let* ((model
           (compat-model
            :id "plain"
            :provider :openai
            :api :openai-completions
            :base-url "https://api.openai.com/v1"
            :max-tokens 4096))
         (context
           (cadr-ai:make-context
            :system-prompt "sys"
            :messages
            (list
             (cadr-ai:make-user-message :content "hi"))))
         (payload
           (request-spec-payload
            (build-request
             (cadr-ai:make-openai-completions-provider
              :api-key "key")
             model context
             :tool-choice "none"))))
    (is (not (cadr-ai::json-present-p payload "tool_choice")))
    (is (not (cadr-ai::json-present-p payload "tools")))))

(test google-thinking-off-and-tool-mode-cover-non-gemini-3
  (let* ((model
           (compat-model
            :id "gemini-2.5-flash"
            :provider :google
            :api :google-generative-ai
            :base-url
            "https://generativelanguage.googleapis.com/v1beta"
            :max-tokens 4096
            :reasoning-p t))
         (request
           (build-request
            (make-google-provider :api-key "key")
            model
            (sample-context)
            :stream-p t
            :tool-choice "any"))
         (payload (request-spec-payload request)))
    (is (= 0
           (cadr-ai::json-get
            (cadr-ai::json-get payload "thinkingConfig")
            "thinkingBudget")))
    (is (string=
         "ANY"
         (cadr-ai::json-get
          (cadr-ai::json-get
           (cadr-ai::json-get payload "toolConfig")
           "functionCallingConfig")
          "mode")))))

(test responses-explicit-long-cache-sends-thirty-minute-ttl
  (let* ((model
           (compat-model
            :id "gpt-5.6-sol"
            :provider :openai
            :api :openai-responses
            :base-url "https://api.openai.com/v1"
            :max-tokens 4096
            :compat
            '(:supports-explicit-prompt-cache-mode t
              :supports-long-cache-retention t)))
         (request
           (build-request
            (make-openai-provider :api-key "key")
            model
            (sample-context)
            :stream-p t
            :cache-retention :long
            :session-id "session-long"
            :max-tokens 128))
         (payload (request-spec-payload request))
         (options
           (cadr-ai::json-get payload "prompt_cache_options")))
    (is (string= "30m" (cadr-ai::json-get options "ttl")))
    (is (not (cadr-ai::json-present-p options "mode")))
    (is (not (cadr-ai::json-present-p payload "prompt_cache_retention")))
    (is (= 128 (cadr-ai::json-get payload "max_output_tokens")))))

(test responses-omit-max-output-tokens-when-compat-disables-them
  (let* ((model
           (compat-model
            :id "gateway"
            :provider :openai
            :api :openai-responses
            :base-url "https://api.openai.com/v1"
            :max-tokens 4096
            :compat '(:supports-max-output-tokens nil)))
         (payload
           (request-spec-payload
            (build-request
             (make-openai-provider :api-key "key")
             model
             (sample-context)
             :stream-p t
             :max-tokens 128))))
    (is (not (cadr-ai::json-present-p payload "max_output_tokens")))))

(test completions-forward-vllm-priority-including-zero
  (let* ((zero
           (compat-model
            :id "vllm"
            :provider :vllm
            :api :openai-completions
            :base-url "http://127.0.0.1:8000/v1"
            :max-tokens 4096
            :compat '(:vllm-priority 0)))
         (unset
           (compat-model
            :id "vllm"
            :provider :vllm
            :api :openai-completions
            :base-url "http://127.0.0.1:8000/v1"
            :max-tokens 4096))
         (zero-payload
           (request-spec-payload
            (build-request
             (cadr-ai:make-openai-completions-provider :api-key "key")
             zero
             (sample-context)
             :stream-p t
             :cache-retention :none)))
         (unset-payload
           (request-spec-payload
            (build-request
             (cadr-ai:make-openai-completions-provider :api-key "key")
             unset
             (sample-context)
             :stream-p t
             :cache-retention :none))))
    (is (cadr-ai::json-present-p zero-payload "priority"))
    (is (= 0 (cadr-ai::json-get zero-payload "priority")))
    (is (not (cadr-ai::json-present-p unset-payload "priority")))))
