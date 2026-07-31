(in-package #:cadr-ai)

(defstruct provider-definition
  (id nil :type symbol)
  (name "" :type string)
  (protocol nil :type symbol)
  (base-url "" :type string)
  (auth-types nil :type list)
  (default-model "" :type string)
  (key-environment nil :type (or null string))
  (required-environment nil :type list)
  (dynamic-models-p nil :type boolean)
  (supports-images-p nil :type boolean)
  (supports-tools-p t :type boolean)
  (reasoning-p nil :type boolean))

(defparameter *provider-definitions* (make-hash-table))

(defparameter *built-in-provider-definition-rows*
  '((:id :amazon-bedrock
     :name "Amazon Bedrock"
     :protocol :bedrock-converse-stream
     :base-url "https://bedrock-runtime.us-east-1.amazonaws.com"
     :auth-types (:api-key)
     :default-model "us.anthropic.claude-opus-4-6-v1")
    (:id :ant-ling
     :name "Ant Ling"
     :protocol :openai-completions
     :base-url "https://api.ant-ling.com/v1"
     :auth-types (:api-key)
     :default-model "Ring-2.6-1T"
     :key-environment "ANT_LING_API_KEY")
    (:id :anthropic
     :name "Anthropic"
     :protocol :anthropic-messages
     :base-url "https://api.anthropic.com"
     :auth-types (:api-key :oauth)
     :default-model "claude-opus-4-8"
     :key-environment "ANTHROPIC_API_KEY")
    (:id :azure-openai-responses
     :name "Azure OpenAI"
     :protocol :azure-openai-responses
     :base-url ""
     :auth-types (:api-key)
     :default-model "gpt-5.4"
     :key-environment "AZURE_OPENAI_API_KEY"
     :required-environment
     ("AZURE_OPENAI_BASE_URL or AZURE_OPENAI_RESOURCE_NAME"))
    (:id :cerebras
     :name "Cerebras"
     :protocol :openai-completions
     :base-url "https://api.cerebras.ai/v1"
     :auth-types (:api-key)
     :default-model "zai-glm-4.7"
     :key-environment "CEREBRAS_API_KEY")
    (:id :cloudflare-ai-gateway
     :name "Cloudflare AI Gateway"
     :protocol :openai-completions
     :base-url
     "https://gateway.ai.cloudflare.com/v1/{CLOUDFLARE_ACCOUNT_ID}/{CLOUDFLARE_GATEWAY_ID}/compat"
     :auth-types (:api-key)
     :default-model "workers-ai/@cf/moonshotai/kimi-k2.6"
     :key-environment "CLOUDFLARE_API_KEY"
     :required-environment
     ("CLOUDFLARE_ACCOUNT_ID" "CLOUDFLARE_GATEWAY_ID"))
    (:id :cloudflare-workers-ai
     :name "Cloudflare Workers AI"
     :protocol :openai-completions
     :base-url
     "https://api.cloudflare.com/client/v4/accounts/{CLOUDFLARE_ACCOUNT_ID}/ai/v1"
     :auth-types (:api-key)
     :default-model "@cf/moonshotai/kimi-k2.6"
     :key-environment "CLOUDFLARE_API_KEY"
     :required-environment ("CLOUDFLARE_ACCOUNT_ID"))
    (:id :deepseek
     :name "DeepSeek"
     :protocol :openai-completions
     :base-url "https://api.deepseek.com"
     :auth-types (:api-key)
     :default-model "deepseek-v4-pro"
     :key-environment "DEEPSEEK_API_KEY")
    (:id :fireworks
     :name "Fireworks"
     :protocol :anthropic-messages
     :base-url "https://api.fireworks.ai/inference"
     :auth-types (:api-key)
     :default-model "accounts/fireworks/models/kimi-k2p6"
     :key-environment "FIREWORKS_API_KEY")
    (:id :github-copilot
     :name "GitHub Copilot"
     :protocol :openai-responses
     :base-url "https://api.individual.githubcopilot.com"
     :auth-types (:api-key :oauth)
     :default-model "gpt-5.4"
     :key-environment "COPILOT_GITHUB_TOKEN")
    (:id :google
     :name "Google"
     :protocol :google-generative-ai
     :base-url "https://generativelanguage.googleapis.com/v1beta"
     :auth-types (:api-key)
     :default-model "gemini-3.1-pro-preview"
     :key-environment "GEMINI_API_KEY")
    (:id :google-vertex
     :name "Google Vertex AI"
     :protocol :google-vertex
     :base-url "https://{location}-aiplatform.googleapis.com"
     :auth-types (:api-key)
     :default-model "gemini-3.1-pro-preview")
    (:id :groq
     :name "Groq"
     :protocol :openai-completions
     :base-url "https://api.groq.com/openai/v1"
     :auth-types (:api-key)
     :default-model "openai/gpt-oss-120b"
     :key-environment "GROQ_API_KEY")
    (:id :huggingface
     :name "Hugging Face"
     :protocol :openai-completions
     :base-url "https://router.huggingface.co/v1"
     :auth-types (:api-key)
     :default-model "moonshotai/Kimi-K2.6"
     :key-environment "HF_TOKEN")
    (:id :kimi-coding
     :name "Kimi For Coding"
     :protocol :anthropic-messages
     :base-url "https://api.kimi.com/coding"
     :auth-types (:api-key :oauth)
     :default-model "kimi-for-coding"
     :key-environment "KIMI_API_KEY")
    (:id :minimax
     :name "MiniMax"
     :protocol :anthropic-messages
     :base-url "https://api.minimax.io/anthropic"
     :auth-types (:api-key)
     :default-model "MiniMax-M2.7"
     :key-environment "MINIMAX_API_KEY")
    (:id :minimax-cn
     :name "MiniMax CN"
     :protocol :anthropic-messages
     :base-url "https://api.minimaxi.com/anthropic"
     :auth-types (:api-key)
     :default-model "MiniMax-M2.7"
     :key-environment "MINIMAX_CN_API_KEY")
    (:id :mistral
     :name "Mistral"
     :protocol :mistral-conversations
     :base-url "https://api.mistral.ai"
     :auth-types (:api-key)
     :default-model "devstral-medium-latest"
     :key-environment "MISTRAL_API_KEY")
    (:id :moonshotai
     :name "Moonshot AI"
     :protocol :openai-completions
     :base-url "https://api.moonshot.ai/v1"
     :auth-types (:api-key)
     :default-model "kimi-k2.6"
     :key-environment "MOONSHOT_API_KEY")
    (:id :moonshotai-cn
     :name "Moonshot AI CN"
     :protocol :openai-completions
     :base-url "https://api.moonshot.cn/v1"
     :auth-types (:api-key)
     :default-model "kimi-k2.6"
     :key-environment "MOONSHOT_API_KEY")
    (:id :nvidia
     :name "NVIDIA"
     :protocol :openai-completions
     :base-url "https://integrate.api.nvidia.com/v1"
     :auth-types (:api-key)
     :default-model "nvidia/nemotron-3-super-120b-a12b"
     :key-environment "NVIDIA_API_KEY")
    (:id :openai
     :name "OpenAI"
     :protocol :openai-responses
     :base-url "https://api.openai.com/v1"
     :auth-types (:api-key)
     :default-model "gpt-5.5"
     :key-environment "OPENAI_API_KEY")
    (:id :openai-codex
     :name "OpenAI Codex"
     :protocol :openai-codex-responses
     :base-url "https://chatgpt.com/backend-api"
     :auth-types (:oauth)
     :default-model "gpt-5.5")
    (:id :opencode
     :name "OpenCode Zen"
     :protocol :openai-completions
     :base-url "https://opencode.ai/zen/v1"
     :auth-types (:api-key)
     :default-model "kimi-k2.6"
     :key-environment "OPENCODE_API_KEY")
    (:id :opencode-go
     :name "OpenCode Go"
     :protocol :openai-completions
     :base-url "https://opencode.ai/zen/go/v1"
     :auth-types (:api-key)
     :default-model "kimi-k2.6"
     :key-environment "OPENCODE_API_KEY")
    (:id :openrouter
     :name "OpenRouter"
     :protocol :openai-completions
     :base-url "https://openrouter.ai/api/v1"
     :auth-types (:api-key :oauth)
     :default-model "moonshotai/kimi-k2.6"
     :key-environment "OPENROUTER_API_KEY")
    (:id :qwen-token-plan
     :name "Qwen Token Plan"
     :protocol :openai-completions
     :base-url
     "https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1"
     :auth-types (:api-key)
     :default-model "qwen3.7-max"
     :key-environment "QWEN_TOKEN_PLAN_API_KEY")
    (:id :qwen-token-plan-cn
     :name "Qwen Token Plan CN"
     :protocol :openai-completions
     :base-url
     "https://token-plan.cn-beijing.maas.aliyuncs.com/compatible-mode/v1"
     :auth-types (:api-key)
     :default-model "qwen3.7-max"
     :key-environment "QWEN_TOKEN_PLAN_CN_API_KEY")
    (:id :radius
     :name "Radius"
     :protocol :pi-messages
     :base-url "https://radius.pi.dev"
     :auth-types (:api-key :oauth)
     :default-model "auto"
     :key-environment "RADIUS_API_KEY"
     :dynamic-models-p t)
    (:id :together
     :name "Together"
     :protocol :openai-completions
     :base-url "https://api.together.ai/v1"
     :auth-types (:api-key)
     :default-model "moonshotai/Kimi-K2.6"
     :key-environment "TOGETHER_API_KEY")
    (:id :vercel-ai-gateway
     :name "Vercel AI Gateway"
     :protocol :anthropic-messages
     :base-url "https://ai-gateway.vercel.sh"
     :auth-types (:api-key)
     :default-model "zai/glm-5.1"
     :key-environment "AI_GATEWAY_API_KEY")
    (:id :xai
     :name "xAI"
     :protocol :openai-responses
     :base-url "https://api.x.ai/v1"
     :auth-types (:api-key :oauth)
     :default-model "grok-4.5"
     :key-environment "XAI_API_KEY")
    (:id :xiaomi
     :name "Xiaomi"
     :protocol :openai-completions
     :base-url "https://api.xiaomimimo.com/v1"
     :auth-types (:api-key)
     :default-model "mimo-v2.5-pro"
     :key-environment "XIAOMI_API_KEY")
    (:id :xiaomi-token-plan-ams
     :name "Xiaomi Token Plan AMS"
     :protocol :openai-completions
     :base-url "https://token-plan-ams.xiaomimimo.com/v1"
     :auth-types (:api-key)
     :default-model "mimo-v2.5-pro"
     :key-environment "XIAOMI_TOKEN_PLAN_AMS_API_KEY")
    (:id :xiaomi-token-plan-cn
     :name "Xiaomi Token Plan CN"
     :protocol :openai-completions
     :base-url "https://token-plan-cn.xiaomimimo.com/v1"
     :auth-types (:api-key)
     :default-model "mimo-v2.5-pro"
     :key-environment "XIAOMI_TOKEN_PLAN_CN_API_KEY")
    (:id :xiaomi-token-plan-sgp
     :name "Xiaomi Token Plan SGP"
     :protocol :openai-completions
     :base-url "https://token-plan-sgp.xiaomimimo.com/v1"
     :auth-types (:api-key)
     :default-model "mimo-v2.5-pro"
     :key-environment "XIAOMI_TOKEN_PLAN_SGP_API_KEY")
    (:id :zai
     :name "Z.AI"
     :protocol :openai-completions
     :base-url "https://api.z.ai/api/coding/paas/v4"
     :auth-types (:api-key)
     :default-model "glm-5.1"
     :key-environment "ZAI_API_KEY")
    (:id :zai-coding-cn
     :name "Z.AI Coding CN"
     :protocol :openai-completions
     :base-url "https://open.bigmodel.cn/api/coding/paas/v4"
     :auth-types (:api-key)
     :default-model "glm-5.1"
     :key-environment "ZAI_CODING_CN_API_KEY")))

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
  (dolist (row *built-in-provider-definition-rows*)
    (register-provider-definition
     (apply #'make-provider-definition row))))

(register-built-in-providers)

(defun make-protocol-provider
    (protocol definition api-key oauth-access-token oauth-account-id
     options)
  (let* ((provider-id (provider-definition-id definition))
         (native-oauth-p
           (member provider-id
                   '(:anthropic :openai-codex :radius)))
         (effective-api-key
           (if (and oauth-access-token (not native-oauth-p))
               oauth-access-token
               api-key))
         (effective-oauth-token
           (and native-oauth-p oauth-access-token))
         (effective-options
           (if (and oauth-access-token
                    (eq provider-id :kimi-coding))
               (append
                (list :oauth-bearer-token oauth-access-token)
                options)
               options))
         (common
          (list
           :api-key effective-api-key
           :oauth-access-token effective-oauth-token
           :oauth-account-id oauth-account-id
           :provider-id provider-id
           :options effective-options)))
    (case protocol
      (:anthropic-messages
       (apply #'make-anthropic-provider common))
      (:openai-responses
       (apply #'make-openai-provider common))
      (:openai-completions
       (apply
        #'make-openai-completions-provider
        (append
         common
         (list
          :authentication-required-p
          (not
           (null
            (provider-definition-key-environment definition)))))))
      (:google-generative-ai
       (apply #'make-google-provider common))
      (:azure-openai-responses
       (apply #'make-azure-openai-provider common))
      (:bedrock-converse-stream
       (apply #'make-bedrock-provider common))
      (:google-vertex
       (apply #'make-vertex-provider common))
      (:mistral-conversations
       (apply #'make-mistral-provider common))
      (:openai-codex-responses
       (apply #'make-openai-codex-provider common))
      (:pi-messages
       (apply #'make-pi-messages-provider common))
      (otherwise
       (error 'configuration-error
              :message
              (format nil "Unsupported provider protocol: ~A"
                      protocol))))))

(defun instantiate-provider
    (id &key api-key oauth-access-token oauth-account-id
             base-url model-id reasoning allow-missing-auth-p options)
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
               (find-model-metadata id resolved-id)))
           (fallback-metadata
             (and
              (null metadata)
              (ignore-errors
                (find-model-metadata
                 id
                 (provider-definition-default-model definition)))))
           (effective-metadata
             (or metadata fallback-metadata))
           (protocol
             (or (and effective-metadata
                      (model-metadata-api effective-metadata))
                 (provider-definition-protocol definition))))
      (values
       (make-protocol-provider
        protocol definition api-key oauth-access-token oauth-account-id
        (if base-url
            (append (list :explicit-base-url base-url) options)
            options))
       (make-model
        :id resolved-id
        :provider id
        :api protocol
        :base-url
        (or base-url
            (and effective-metadata
                 (non-empty-string-p
                  (model-metadata-base-url effective-metadata))
                 (model-metadata-base-url effective-metadata))
            (provider-definition-base-url definition))
        :name
        (if (and metadata
                 (non-empty-string-p
                  (model-metadata-name metadata)))
            (model-metadata-name metadata)
            resolved-id)
        :max-tokens
        (if effective-metadata
            (model-metadata-max-output-tokens effective-metadata)
            4096)
        :context-window
        (if effective-metadata
            (model-metadata-context-window effective-metadata)
            0)
        :supports-images-p
        (if effective-metadata
            (model-metadata-supports-images-p effective-metadata)
            (provider-definition-supports-images-p definition))
        :supports-tools-p
        (if effective-metadata
            (model-metadata-supports-tools-p effective-metadata)
            (provider-definition-supports-tools-p definition))
        :reasoning-p
        (or
         (and
          (null metadata)
          reasoning
          (not (eq reasoning :off)))
         (if effective-metadata
             (model-metadata-reasoning-p effective-metadata)
             (provider-definition-reasoning-p definition)))
        :thinking-level-map
        (and effective-metadata
             (model-metadata-thinking-level-map effective-metadata))
        :headers
        (and effective-metadata
             (model-metadata-headers effective-metadata))
        :compat
        (and effective-metadata
             (model-metadata-compat effective-metadata)))))))

(defparameter +built-in-runtime-environment-names+
  '("ANT_LING_API_KEY"
    "ANTHROPIC_API_KEY"
    "ANTHROPIC_AUTH_TOKEN"
    "ANTHROPIC_OAUTH_TOKEN"
    "AZURE_OPENAI_API_KEY"
    "AZURE_OPENAI_BASE_URL"
    "AZURE_OPENAI_RESOURCE_NAME"
    "AZURE_OPENAI_DEPLOYMENT_NAME"
    "CEREBRAS_API_KEY"
    "CLOUDFLARE_API_KEY"
    "CLOUDFLARE_ACCOUNT_ID"
    "CLOUDFLARE_GATEWAY_ID"
    "COPILOT_GITHUB_TOKEN"
    "DEEPSEEK_API_KEY"
    "FIREWORKS_API_KEY"
    "GEMINI_API_KEY"
    "GOOGLE_CLOUD_API_KEY"
    "GOOGLE_APPLICATION_CREDENTIALS"
    "GOOGLE_CLOUD_PROJECT"
    "GOOGLE_CLOUD_LOCATION"
    "GCLOUD_PROJECT"
    "GROQ_API_KEY"
    "HF_TOKEN"
    "KIMI_API_KEY"
    "MINIMAX_API_KEY"
    "MINIMAX_CN_API_KEY"
    "MISTRAL_API_KEY"
    "MOONSHOT_API_KEY"
    "NVIDIA_API_KEY"
    "OPENAI_API_KEY"
    "OPENCODE_API_KEY"
    "OPENROUTER_API_KEY"
    "QWEN_TOKEN_PLAN_API_KEY"
    "QWEN_TOKEN_PLAN_CN_API_KEY"
    "RADIUS_API_KEY"
    "TOGETHER_API_KEY"
    "AI_GATEWAY_API_KEY"
    "XAI_API_KEY"
    "XIAOMI_API_KEY"
    "XIAOMI_TOKEN_PLAN_AMS_API_KEY"
    "XIAOMI_TOKEN_PLAN_CN_API_KEY"
    "XIAOMI_TOKEN_PLAN_SGP_API_KEY"
    "ZAI_API_KEY"
    "ZAI_CODING_CN_API_KEY"
    "AWS_PROFILE"
    "AWS_REGION"
    "AWS_DEFAULT_REGION"
    "AWS_ACCESS_KEY_ID"
    "AWS_SECRET_ACCESS_KEY"
    "AWS_SESSION_TOKEN"
    "AWS_BEARER_TOKEN_BEDROCK"
    "AWS_CONTAINER_CREDENTIALS_RELATIVE_URI"
    "AWS_CONTAINER_CREDENTIALS_FULL_URI"
    "AWS_WEB_IDENTITY_TOKEN_FILE"))

(defun ambient-provider-environment ()
  (loop for name in +built-in-runtime-environment-names+
        for value = (uiop:getenv name)
        when (non-empty-string-p value)
          collect (cons name value)))

(defun merge-provider-environment (explicit ambient)
  (append
   explicit
   (remove-if
    (lambda (entry)
      (assoc (car entry) explicit :test #'string=))
    ambient)))

(defun provider-runtime-models (provider-id)
  (mapcar #'model-from-metadata
          (list-model-metadata provider-id)))

(defun built-in-api-key-auth
    (definition credential environment overrides)
  (let* ((explicit-key (getf overrides :api-key))
         (credential-key
           (and (typep credential 'api-key-credential)
                (api-key-credential-key credential)))
         (credential-environment
           (and (typep credential 'api-key-credential)
                (api-key-credential-environment credential)))
         (effective-environment
           (merge-provider-environment
            (append
             (or (getf overrides :environment) nil)
             credential-environment)
            environment))
         (provider-id (provider-definition-id definition))
         (key-name
           (provider-definition-key-environment definition))
         (key
           (or (and (non-empty-string-p explicit-key)
                    explicit-key)
               (and (non-empty-string-p credential-key)
                    credential-key)
               (and key-name
                    (environment-value
                     effective-environment key-name)))))
    (case provider-id
      (:amazon-bedrock
       (let ((resolved
               (resolve-bedrock-credentials
                effective-environment
                :bearer-token key)))
         (when resolved
           (make-runtime-auth-result
            :api-key (getf resolved :bearer-token)
            :environment effective-environment
            :source
            (ecase (getf resolved :source)
              (:bearer-token "AWS_BEARER_TOKEN_BEDROCK")
              (:profile "AWS profile")
              (:access-keys "AWS_ACCESS_KEY_ID")
              (:ecs-task-role "AWS ECS task role")
              (:web-identity "AWS web identity"))
            :type :api-key))))
      (:google-vertex
       (handler-case
           (let ((resolved
                   (resolve-vertex-auth
                    effective-environment
                    :api-key key)))
             (make-runtime-auth-result
              :api-key (getf resolved :api-key)
              :environment effective-environment
              :source
              (if (eq :api-key (getf resolved :type))
                  "GOOGLE_CLOUD_API_KEY"
                  "Google ADC")
              :type :api-key))
         (configuration-error () nil)))
      (otherwise
       (when
           (or (non-empty-string-p key)
               (null key-name))
         (make-runtime-auth-result
          :api-key key
          :environment effective-environment
          :source
          (cond
            ((non-empty-string-p explicit-key)
             "Explicit API key")
            ((and (typep credential 'api-key-credential)
                  (non-empty-string-p credential-key))
             "Stored API key")
            (key-name key-name)
            (t "Keyless"))
          :type :api-key))))))

(defun built-in-oauth-to-auth (provider-id credential)
  (case provider-id
    (:kimi-coding
     (make-runtime-auth-result
      :headers
      (list
       (cons "Authorization"
             (format nil "Bearer ~A"
                     (oauth-credential-access credential))))
      :source "OAuth" :type :oauth))
    (otherwise
     (make-runtime-auth-result
      :api-key (oauth-credential-access credential)
      :source "OAuth" :type :oauth))))

(defun built-in-provider-options (environment)
  (list
   :environment environment
   :azure-base-url
   (environment-value environment "AZURE_OPENAI_BASE_URL")
   :azure-resource-name
   (environment-value environment "AZURE_OPENAI_RESOURCE_NAME")
   :azure-deployment-name
   (environment-value environment "AZURE_OPENAI_DEPLOYMENT_NAME")
   :cloudflare-account-id
   (environment-value environment "CLOUDFLARE_ACCOUNT_ID")
   :cloudflare-gateway-id
   (environment-value environment "CLOUDFLARE_GATEWAY_ID")
   :project
   (or (environment-value environment "GOOGLE_CLOUD_PROJECT")
       (environment-value environment "GCLOUD_PROJECT"))
   :location
   (environment-value environment "GOOGLE_CLOUD_LOCATION")))

(defun built-in-runtime-dispatch
    (definition model context options stream-p on-event)
  (let* ((auth-type (getf options :auth-type))
         (api-key (getf options :api-key))
         (environment (getf options :environment))
         (provider
           (make-protocol-provider
            (model-api model)
            definition
            (and (not (eq auth-type :oauth)) api-key)
            (and (eq auth-type :oauth) api-key)
            nil
            (built-in-provider-options environment))))
    (if stream-p
        (apply #'stream-chat
               provider model context on-event
               (remove-runtime-only-options options))
        (apply #'complete-chat
               provider model context
               (remove-runtime-only-options options)))))

(defun remove-runtime-only-options (options)
  (loop for (key value) on options by #'cddr
        unless (member key
                       '(:api-key :headers :environment :auth-type))
          append (list key value)))

(defun make-built-in-runtime-provider (definition)
  (let ((provider-id
          (provider-definition-id definition)))
    (make-runtime-provider
     :id provider-id
     :name (provider-definition-name definition)
     :models (provider-runtime-models provider-id)
     :api-key-auth-p
     (not
      (null
       (member :api-key
               (provider-definition-auth-types definition))))
     :oauth-auth-p
     (not
      (null
       (member :oauth
               (provider-definition-auth-types definition))))
     :auth-resolver
     (lambda (credential environment overrides)
       (built-in-api-key-auth
        definition credential environment overrides))
     :oauth-refresh-function
     (case provider-id
       (:anthropic #'refresh-anthropic-oauth-credential)
       (:openai-codex #'refresh-openai-oauth-credential)
       (otherwise nil))
     :oauth-to-auth-function
     (lambda (credential)
       (built-in-oauth-to-auth provider-id credential))
     :complete-function
     (lambda (model context options)
       (built-in-runtime-dispatch
        definition model context options nil nil))
     :stream-function
     (lambda (model context on-event &rest options)
       (built-in-runtime-dispatch
        definition model context options t on-event)))))

(defun make-built-in-models-runtime
    (&key credential-store model-store environment)
  (let ((runtime
          (make-models-runtime
           :credential-store credential-store
           :model-store model-store
           :environment
           (merge-provider-environment
            environment
            (ambient-provider-environment)))))
    (dolist (definition (list-provider-definitions))
      (models-runtime-set-provider
       runtime
       (make-built-in-runtime-provider definition)))
    runtime))
