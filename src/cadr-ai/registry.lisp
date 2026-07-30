(in-package #:cadr-ai)

(defstruct provider-definition
  (id nil :type symbol)
  (name "" :type string)
  (protocol nil :type symbol)
  (base-url "" :type string)
  (auth-types nil :type list)
  (default-model "" :type string)
  (key-environment nil :type (or null string))
  (supports-images-p nil :type boolean)
  (supports-tools-p t :type boolean)
  (reasoning-p nil :type boolean))

(defparameter *provider-definitions* (make-hash-table))

(defparameter *wave1-provider-definition-rows*
  '((:id :ant-ling
     :name "Ant Ling"
     :protocol :openai-completions
     :base-url "https://api.ant-ling.com/v1"
     :default-model "Ring-2.6-1T"
     :key-environment "ANT_LING_API_KEY")
    (:id :cerebras
     :name "Cerebras"
     :protocol :openai-completions
     :base-url "https://api.cerebras.ai/v1"
     :default-model "zai-glm-4.7"
     :key-environment "CEREBRAS_API_KEY")
    (:id :groq
     :name "Groq"
     :protocol :openai-completions
     :base-url "https://api.groq.com/openai/v1"
     :default-model "openai/gpt-oss-120b"
     :key-environment "GROQ_API_KEY")
    (:id :huggingface
     :name "Hugging Face"
     :protocol :openai-completions
     :base-url "https://router.huggingface.co/v1"
     :default-model "moonshotai/Kimi-K2.6"
     :key-environment "HF_TOKEN")
    (:id :minimax
     :name "MiniMax"
     :protocol :anthropic-messages
     :base-url "https://api.minimax.io/anthropic"
     :default-model "MiniMax-M2.7"
     :key-environment "MINIMAX_API_KEY")
    (:id :minimax-cn
     :name "MiniMax CN"
     :protocol :anthropic-messages
     :base-url "https://api.minimaxi.com/anthropic"
     :default-model "MiniMax-M2.7"
     :key-environment "MINIMAX_CN_API_KEY")
    (:id :moonshotai
     :name "Moonshot AI"
     :protocol :openai-completions
     :base-url "https://api.moonshot.ai/v1"
     :default-model "kimi-k2.6"
     :key-environment "MOONSHOT_API_KEY")
    (:id :moonshotai-cn
     :name "Moonshot AI CN"
     :protocol :openai-completions
     :base-url "https://api.moonshot.cn/v1"
     :default-model "kimi-k2.6"
     :key-environment "MOONSHOT_API_KEY")
    (:id :qwen-token-plan
     :name "Qwen Token Plan"
     :protocol :openai-completions
     :base-url
     "https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1"
     :default-model "qwen3.7-max"
     :key-environment "QWEN_TOKEN_PLAN_API_KEY")
    (:id :qwen-token-plan-cn
     :name "Qwen Token Plan CN"
     :protocol :openai-completions
     :base-url
     "https://token-plan.cn-beijing.maas.aliyuncs.com/compatible-mode/v1"
     :default-model "qwen3.7-max"
     :key-environment "QWEN_TOKEN_PLAN_CN_API_KEY")
    (:id :together
     :name "Together"
     :protocol :openai-completions
     :base-url "https://api.together.ai/v1"
     :default-model "moonshotai/Kimi-K2.6"
     :key-environment "TOGETHER_API_KEY")
    (:id :xiaomi
     :name "Xiaomi"
     :protocol :openai-completions
     :base-url "https://api.xiaomimimo.com/v1"
     :default-model "mimo-v2.5-pro"
     :key-environment "XIAOMI_API_KEY")))

(defun register-provider-definition (definition)
  (setf (gethash (provider-definition-id definition)
                 *provider-definitions*)
        definition)
  definition)

(defun find-provider-definition (id)
  (or (gethash id *provider-definitions*)
      (error 'configuration-error
             :message (format nil "Unknown provider: ~A" id))))

(defun list-provider-definitions ()
  (sort
   (loop for definition being the hash-values
           of *provider-definitions*
         collect definition)
   #'string<
   :key (lambda (definition)
          (symbol-name (provider-definition-id definition)))))

(defun register-built-in-providers ()
  (clrhash *provider-definitions*)
  (dolist
      (definition
       (append
        (list
        (make-provider-definition
         :id :anthropic
         :name "Anthropic"
         :protocol :anthropic-messages
         :base-url "https://api.anthropic.com"
         :auth-types '(:api-key :oauth)
         :default-model "claude-opus-4-8"
         :key-environment "ANTHROPIC_API_KEY"
         :supports-images-p t
         :reasoning-p t)
        (make-provider-definition
         :id :openai
         :name "OpenAI"
         :protocol :openai-responses
         :base-url "https://api.openai.com"
         :auth-types '(:api-key :oauth)
         :default-model "gpt-5.5"
         :key-environment "OPENAI_API_KEY"
         :supports-images-p t
         :reasoning-p t)
        (make-provider-definition
         :id :google
         :name "Google"
         :protocol :google-generative-ai
         :base-url "https://generativelanguage.googleapis.com/v1beta"
         :auth-types '(:api-key)
         :default-model "gemini-3.6-flash"
         :key-environment "GEMINI_API_KEY"
         :supports-images-p t
         :reasoning-p t)
        (make-provider-definition
         :id :deepseek
         :name "DeepSeek"
         :protocol :openai-completions
         :base-url "https://api.deepseek.com"
         :auth-types '(:api-key)
         :default-model "deepseek-v4-flash"
         :key-environment "DEEPSEEK_API_KEY"
         :reasoning-p t)
        (make-provider-definition
         :id :ollama
         :name "Ollama"
         :protocol :openai-completions
         :base-url "http://localhost:11434"
         :auth-types '(:api-key)
         :default-model "gpt-oss:20b"
         :key-environment nil
         :reasoning-p t))
        (mapcar
         (lambda (row)
           (apply
            #'make-provider-definition
            (append row
                    '(:auth-types (:api-key)
                      :supports-tools-p t
                      :reasoning-p t))))
         *wave1-provider-definition-rows*)))
    (register-provider-definition definition)))

(register-built-in-providers)

(defun make-protocol-provider (definition api-key
                               oauth-access-token oauth-account-id)
  (case (provider-definition-protocol definition)
    (:anthropic-messages
     (make-anthropic-provider
      :api-key api-key
      :oauth-access-token oauth-access-token))
    (:openai-responses
     (make-openai-provider
      :api-key api-key
      :oauth-access-token oauth-access-token
      :oauth-account-id oauth-account-id))
    (:openai-completions
     (make-openai-completions-provider
      :api-key api-key
      :authentication-required-p
      (not (null
            (provider-definition-key-environment definition)))))
    (:google-generative-ai
     (make-google-provider :api-key api-key))
    (otherwise
     (error 'configuration-error
            :message
            (format nil "Unsupported provider protocol: ~A"
                    (provider-definition-protocol definition))))))

(defun instantiate-provider
    (id &key api-key oauth-access-token oauth-account-id
             base-url model-id allow-missing-auth-p)
  (let* ((definition (find-provider-definition id))
         (requires-key-p
           (and
            (provider-definition-key-environment definition)
            (not oauth-access-token))))
    (when (and requires-key-p
               (not allow-missing-auth-p)
               (not (non-empty-string-p api-key)))
      (error 'configuration-error
             :message
             (format nil "~A is not set"
                     (provider-definition-key-environment definition))))
    (let* ((resolved-id
             (or model-id
                 (provider-definition-default-model definition)))
           (metadata
             (ignore-errors
               (find-model-metadata id resolved-id))))
      (values
       (make-protocol-provider definition api-key
                               oauth-access-token oauth-account-id)
       (make-model
        :id resolved-id
        :provider id
        :api (provider-definition-protocol definition)
        :base-url
        (or base-url
            (and metadata
                 (non-empty-string-p
                  (model-metadata-base-url metadata))
                 (model-metadata-base-url metadata))
            (provider-definition-base-url definition))
        :name
        (if (and metadata
                 (non-empty-string-p
                  (model-metadata-name metadata)))
            (model-metadata-name metadata)
            resolved-id)
        :max-tokens
        (if metadata
            (model-metadata-max-output-tokens metadata)
            4096)
        :context-window
        (if metadata
            (model-metadata-context-window metadata)
            0)
        :supports-images-p
        (if metadata
            (model-metadata-supports-images-p metadata)
            (provider-definition-supports-images-p definition))
        :supports-tools-p
        (if metadata
            (model-metadata-supports-tools-p metadata)
            (provider-definition-supports-tools-p definition))
        :reasoning-p
        (if metadata
            (model-metadata-reasoning-p metadata)
            (provider-definition-reasoning-p definition))
        :thinking-level-map
        (and metadata
             (model-metadata-thinking-level-map metadata))
        :headers
        (and metadata
             (model-metadata-headers metadata))
        :compat
        (and metadata
             (model-metadata-compat metadata)))))))
