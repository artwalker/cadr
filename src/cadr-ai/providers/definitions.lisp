(in-package #:cadr-ai)

(defstruct provider-definition
  (id nil :type symbol)
  (baseline-source "" :type string)
  (name "" :type string)
  (protocol nil :type symbol)
  (protocols nil :type list)
  (base-url "" :type string)
  (auth-types nil :type list)
  (default-model "" :type string)
  (key-environment nil :type (or null string))
  (required-environment nil :type list)
  (dynamic-models-p nil :type boolean)
  (supports-images-p nil :type boolean)
  (supports-tools-p t :type boolean)
  (reasoning-p nil :type boolean)
  oauth-metadata
  (api-key-name nil :type (or null string))
  (environment-names nil :type list)
  (api-key-auth-strategy nil :type (or null symbol))
  (oauth-login-strategy nil :type (or null symbol))
  (oauth-refresh-strategy nil :type (or null symbol))
  (oauth-to-auth-strategy nil :type (or null symbol))
  (model-filter-strategy nil :type (or null symbol)))

(defparameter *provider-definitions* (make-hash-table))

(defparameter *provider-definition-comparison-exclusions*
  '((baseline-source
     . "Trace metadata naming the pi source line; not a baseline runtime field.")))

(defun provider-definition-comparison-exclusions ()
  *provider-definition-comparison-exclusions*)

(defun provider-definition-compared-slots ()
  (let ((excluded
          (mapcar #'car *provider-definition-comparison-exclusions*)))
    (remove-if
     (lambda (name) (member name excluded))
     (mapcar #'sb-mop:slot-definition-name
             (sb-mop:class-slots (find-class 'provider-definition))))))

(defparameter *built-in-provider-definition-rows*
  `(
    (:id :amazon-bedrock
     :baseline-source "packages/ai/src/providers/amazon-bedrock.ts:75"
     :name "Amazon Bedrock"
     :protocol :bedrock-converse-stream
     :protocols (:bedrock-converse-stream)
     :base-url "https://bedrock-runtime.us-east-1.amazonaws.com"
     :auth-types (:api-key)
     :default-model "us.anthropic.claude-opus-4-6-v1"
     :key-environment nil
     :required-environment nil
     :dynamic-models-p nil
     :supports-images-p nil
     :supports-tools-p t
     :reasoning-p nil
     :oauth-metadata nil
     :api-key-name "AWS credentials or bearer token"
     :environment-names ("AWS_PROFILE" "AWS_REGION" "AWS_DEFAULT_REGION" "AWS_ACCESS_KEY_ID" "AWS_SECRET_ACCESS_KEY" "AWS_SESSION_TOKEN" "AWS_BEARER_TOKEN_BEDROCK" "AWS_CONTAINER_CREDENTIALS_RELATIVE_URI" "AWS_CONTAINER_CREDENTIALS_FULL_URI" "AWS_WEB_IDENTITY_TOKEN_FILE")
     :api-key-auth-strategy :bedrock
     :oauth-login-strategy nil
     :oauth-refresh-strategy nil
     :oauth-to-auth-strategy nil
     :model-filter-strategy nil)
    (:id :ant-ling
     :baseline-source "packages/ai/src/providers/ant-ling.ts:7"
     :name "Ant Ling"
     :protocol :openai-completions
     :protocols (:openai-completions)
     :base-url "https://api.ant-ling.com/v1"
     :auth-types (:api-key)
     :default-model "Ring-2.6-1T"
     :key-environment "ANT_LING_API_KEY"
     :required-environment nil
     :dynamic-models-p nil
     :supports-images-p nil
     :supports-tools-p t
     :reasoning-p nil
     :oauth-metadata nil
     :api-key-name "Ant Ling API key"
     :environment-names ("ANT_LING_API_KEY")
     :api-key-auth-strategy :environment
     :oauth-login-strategy nil
     :oauth-refresh-strategy nil
     :oauth-to-auth-strategy nil
     :model-filter-strategy nil)
    (:id :anthropic
     :baseline-source "packages/ai/src/providers/anthropic.ts:39"
     :name "Anthropic"
     :protocol :anthropic-messages
     :protocols (:anthropic-messages)
     :base-url "https://api.anthropic.com"
     :auth-types (:api-key :oauth)
     :default-model "claude-opus-4-8"
     :key-environment "ANTHROPIC_API_KEY"
     :required-environment nil
     :dynamic-models-p nil
     :supports-images-p nil
     :supports-tools-p t
     :reasoning-p nil
     :oauth-metadata ,+anthropic-oauth-metadata+
     :api-key-name "Anthropic API key"
     :environment-names ("ANTHROPIC_API_KEY" "ANTHROPIC_AUTH_TOKEN" "ANTHROPIC_OAUTH_TOKEN")
     :api-key-auth-strategy :environment
     :oauth-login-strategy :anthropic
     :oauth-refresh-strategy :anthropic
     :oauth-to-auth-strategy :access-token
     :model-filter-strategy nil)
    (:id :azure-openai-responses
     :baseline-source "packages/ai/src/providers/azure-openai-responses.ts:7"
     :name "Azure OpenAI"
     :protocol :azure-openai-responses
     :protocols (:azure-openai-responses)
     :base-url ""
     :auth-types (:api-key)
     :default-model "gpt-5.4"
     :key-environment "AZURE_OPENAI_API_KEY"
     :required-environment ("AZURE_OPENAI_BASE_URL or AZURE_OPENAI_RESOURCE_NAME")
     :dynamic-models-p nil
     :supports-images-p nil
     :supports-tools-p t
     :reasoning-p nil
     :oauth-metadata nil
     :api-key-name "Azure OpenAI API key"
     :environment-names ("AZURE_OPENAI_API_KEY" "AZURE_OPENAI_BASE_URL" "AZURE_OPENAI_RESOURCE_NAME" "AZURE_OPENAI_DEPLOYMENT_NAME")
     :api-key-auth-strategy :environment
     :oauth-login-strategy nil
     :oauth-refresh-strategy nil
     :oauth-to-auth-strategy nil
     :model-filter-strategy nil)
    (:id :baseten
     :baseline-source "packages/ai/src/providers/baseten.ts:7"
     :name "Baseten"
     :protocol :openai-completions
     :protocols (:openai-completions)
     :base-url "https://inference.baseten.co/v1"
     :auth-types (:api-key)
     :default-model "zai-org/GLM-5.2"
     :key-environment "BASETEN_API_KEY"
     :required-environment nil
     :dynamic-models-p nil
     :supports-images-p nil
     :supports-tools-p t
     :reasoning-p nil
     :oauth-metadata nil
     :api-key-name "Baseten API key"
     :environment-names ("BASETEN_API_KEY")
     :api-key-auth-strategy :environment
     :oauth-login-strategy nil
     :oauth-refresh-strategy nil
     :oauth-to-auth-strategy nil
     :model-filter-strategy nil)
    (:id :cerebras
     :baseline-source "packages/ai/src/providers/cerebras.ts:7"
     :name "Cerebras"
     :protocol :openai-completions
     :protocols (:openai-completions)
     :base-url "https://api.cerebras.ai/v1"
     :auth-types (:api-key)
     :default-model "zai-glm-4.7"
     :key-environment "CEREBRAS_API_KEY"
     :required-environment nil
     :dynamic-models-p nil
     :supports-images-p nil
     :supports-tools-p t
     :reasoning-p nil
     :oauth-metadata nil
     :api-key-name "Cerebras API key"
     :environment-names ("CEREBRAS_API_KEY")
     :api-key-auth-strategy :environment
     :oauth-login-strategy nil
     :oauth-refresh-strategy nil
     :oauth-to-auth-strategy nil
     :model-filter-strategy nil)
    (:id :cloudflare-ai-gateway
     :baseline-source "packages/ai/src/providers/cloudflare-ai-gateway.ts:12"
     :name "Cloudflare AI Gateway"
     :protocol :openai-completions
     :protocols (:anthropic-messages :openai-completions :openai-responses)
     :base-url "https://gateway.ai.cloudflare.com/v1/{CLOUDFLARE_ACCOUNT_ID}/{CLOUDFLARE_GATEWAY_ID}/compat"
     :auth-types (:api-key)
     :default-model "workers-ai/@cf/moonshotai/kimi-k2.6"
     :key-environment "CLOUDFLARE_API_KEY"
     :required-environment ("CLOUDFLARE_ACCOUNT_ID" "CLOUDFLARE_GATEWAY_ID")
     :dynamic-models-p nil
     :supports-images-p nil
     :supports-tools-p t
     :reasoning-p nil
     :oauth-metadata nil
     :api-key-name "Cloudflare API key"
     :environment-names ("CLOUDFLARE_API_KEY" "CLOUDFLARE_ACCOUNT_ID" "CLOUDFLARE_GATEWAY_ID")
     :api-key-auth-strategy :environment
     :oauth-login-strategy nil
     :oauth-refresh-strategy nil
     :oauth-to-auth-strategy nil
     :model-filter-strategy nil)
    (:id :cloudflare-workers-ai
     :baseline-source "packages/ai/src/providers/cloudflare-workers-ai.ts:8"
     :name "Cloudflare Workers AI"
     :protocol :openai-completions
     :protocols (:openai-completions)
     :base-url "https://api.cloudflare.com/client/v4/accounts/{CLOUDFLARE_ACCOUNT_ID}/ai/v1"
     :auth-types (:api-key)
     :default-model "@cf/moonshotai/kimi-k2.6"
     :key-environment "CLOUDFLARE_API_KEY"
     :required-environment ("CLOUDFLARE_ACCOUNT_ID")
     :dynamic-models-p nil
     :supports-images-p nil
     :supports-tools-p t
     :reasoning-p nil
     :oauth-metadata nil
     :api-key-name "Cloudflare API key"
     :environment-names ("CLOUDFLARE_API_KEY" "CLOUDFLARE_ACCOUNT_ID")
     :api-key-auth-strategy :environment
     :oauth-login-strategy nil
     :oauth-refresh-strategy nil
     :oauth-to-auth-strategy nil
     :model-filter-strategy nil)
    (:id :deepseek
     :baseline-source "packages/ai/src/providers/deepseek.ts:7"
     :name "DeepSeek"
     :protocol :openai-completions
     :protocols (:openai-completions)
     :base-url "https://api.deepseek.com"
     :auth-types (:api-key)
     :default-model "deepseek-v4-pro"
     :key-environment "DEEPSEEK_API_KEY"
     :required-environment nil
     :dynamic-models-p nil
     :supports-images-p nil
     :supports-tools-p t
     :reasoning-p nil
     :oauth-metadata nil
     :api-key-name "DeepSeek API key"
     :environment-names ("DEEPSEEK_API_KEY")
     :api-key-auth-strategy :environment
     :oauth-login-strategy nil
     :oauth-refresh-strategy nil
     :oauth-to-auth-strategy nil
     :model-filter-strategy nil)
    (:id :fireworks
     :baseline-source "packages/ai/src/providers/fireworks.ts:8"
     :name "Fireworks"
     :protocol :anthropic-messages
     :protocols (:anthropic-messages :openai-completions)
     :base-url "https://api.fireworks.ai/inference"
     :auth-types (:api-key)
     :default-model "accounts/fireworks/models/kimi-k2p6"
     :key-environment "FIREWORKS_API_KEY"
     :required-environment nil
     :dynamic-models-p nil
     :supports-images-p nil
     :supports-tools-p t
     :reasoning-p nil
     :oauth-metadata nil
     :api-key-name "Fireworks API key"
     :environment-names ("FIREWORKS_API_KEY")
     :api-key-auth-strategy :environment
     :oauth-login-strategy nil
     :oauth-refresh-strategy nil
     :oauth-to-auth-strategy nil
     :model-filter-strategy nil)
    (:id :github-copilot
     :baseline-source "packages/ai/src/providers/github-copilot.ts:10"
     :name "GitHub Copilot"
     :protocol :openai-responses
     :protocols (:anthropic-messages :openai-completions :openai-responses)
     :base-url "https://api.individual.githubcopilot.com"
     :auth-types (:api-key :oauth)
     :default-model "gpt-5.4"
     :key-environment "COPILOT_GITHUB_TOKEN"
     :required-environment nil
     :dynamic-models-p nil
     :supports-images-p nil
     :supports-tools-p t
     :reasoning-p nil
     :oauth-metadata ,+github-copilot-oauth-metadata+
     :api-key-name "GitHub Copilot token"
     :environment-names ("COPILOT_GITHUB_TOKEN")
     :api-key-auth-strategy :environment
     :oauth-login-strategy :github-copilot
     :oauth-refresh-strategy :github-copilot
     :oauth-to-auth-strategy :github-copilot
     :model-filter-strategy :github-available-models)
    (:id :google
     :baseline-source "packages/ai/src/providers/google.ts:7"
     :name "Google"
     :protocol :google-generative-ai
     :protocols (:google-generative-ai)
     :base-url "https://generativelanguage.googleapis.com/v1beta"
     :auth-types (:api-key)
     :default-model "gemini-3.1-pro-preview"
     :key-environment "GEMINI_API_KEY"
     :required-environment nil
     :dynamic-models-p nil
     :supports-images-p nil
     :supports-tools-p t
     :reasoning-p nil
     :oauth-metadata nil
     :api-key-name "Gemini API key"
     :environment-names ("GEMINI_API_KEY")
     :api-key-auth-strategy :environment
     :oauth-login-strategy nil
     :oauth-refresh-strategy nil
     :oauth-to-auth-strategy nil
     :model-filter-strategy nil)
    (:id :google-vertex
     :baseline-source "packages/ai/src/providers/google-vertex.ts:86"
     :name "Google Vertex AI"
     :protocol :google-vertex
     :protocols (:google-vertex)
     :base-url "https://{location}-aiplatform.googleapis.com"
     :auth-types (:api-key)
     :default-model "gemini-3.1-pro-preview"
     :key-environment nil
     :required-environment nil
     :dynamic-models-p nil
     :supports-images-p nil
     :supports-tools-p t
     :reasoning-p nil
     :oauth-metadata nil
     :api-key-name "Google Cloud credentials"
     :environment-names ("GOOGLE_CLOUD_API_KEY" "GOOGLE_APPLICATION_CREDENTIALS" "GOOGLE_CLOUD_PROJECT" "GOOGLE_CLOUD_LOCATION" "GCLOUD_PROJECT")
     :api-key-auth-strategy :vertex
     :oauth-login-strategy nil
     :oauth-refresh-strategy nil
     :oauth-to-auth-strategy nil
     :model-filter-strategy nil)
    (:id :groq
     :baseline-source "packages/ai/src/providers/groq.ts:7"
     :name "Groq"
     :protocol :openai-completions
     :protocols (:openai-completions)
     :base-url "https://api.groq.com/openai/v1"
     :auth-types (:api-key)
     :default-model "openai/gpt-oss-120b"
     :key-environment "GROQ_API_KEY"
     :required-environment nil
     :dynamic-models-p nil
     :supports-images-p nil
     :supports-tools-p t
     :reasoning-p nil
     :oauth-metadata nil
     :api-key-name "Groq API key"
     :environment-names ("GROQ_API_KEY")
     :api-key-auth-strategy :environment
     :oauth-login-strategy nil
     :oauth-refresh-strategy nil
     :oauth-to-auth-strategy nil
     :model-filter-strategy nil)
    (:id :huggingface
     :baseline-source "packages/ai/src/providers/huggingface.ts:7"
     :name "Hugging Face"
     :protocol :openai-completions
     :protocols (:openai-completions)
     :base-url "https://router.huggingface.co/v1"
     :auth-types (:api-key)
     :default-model "moonshotai/Kimi-K2.6"
     :key-environment "HF_TOKEN"
     :required-environment nil
     :dynamic-models-p nil
     :supports-images-p nil
     :supports-tools-p t
     :reasoning-p nil
     :oauth-metadata nil
     :api-key-name "Hugging Face token"
     :environment-names ("HF_TOKEN")
     :api-key-auth-strategy :environment
     :oauth-login-strategy nil
     :oauth-refresh-strategy nil
     :oauth-to-auth-strategy nil
     :model-filter-strategy nil)
    (:id :kimi-coding
     :baseline-source "packages/ai/src/providers/kimi-coding.ts:8"
     :name "Kimi For Coding"
     :protocol :anthropic-messages
     :protocols (:anthropic-messages)
     :base-url "https://api.kimi.com/coding"
     :auth-types (:api-key :oauth)
     :default-model "kimi-for-coding"
     :key-environment "KIMI_API_KEY"
     :required-environment nil
     :dynamic-models-p nil
     :supports-images-p nil
     :supports-tools-p t
     :reasoning-p nil
     :oauth-metadata ,+kimi-coding-oauth-metadata+
     :api-key-name "Kimi API key"
     :environment-names ("KIMI_API_KEY" "KIMI_CODE_OAUTH_HOST" "KIMI_OAUTH_HOST")
     :api-key-auth-strategy :environment
     :oauth-login-strategy :kimi
     :oauth-refresh-strategy :kimi
     :oauth-to-auth-strategy :kimi-bearer
     :model-filter-strategy nil)
    (:id :minimax
     :baseline-source "packages/ai/src/providers/minimax.ts:7"
     :name "MiniMax"
     :protocol :anthropic-messages
     :protocols (:anthropic-messages)
     :base-url "https://api.minimax.io/anthropic"
     :auth-types (:api-key)
     :default-model "MiniMax-M2.7"
     :key-environment "MINIMAX_API_KEY"
     :required-environment nil
     :dynamic-models-p nil
     :supports-images-p nil
     :supports-tools-p t
     :reasoning-p nil
     :oauth-metadata nil
     :api-key-name "MiniMax API key"
     :environment-names ("MINIMAX_API_KEY")
     :api-key-auth-strategy :environment
     :oauth-login-strategy nil
     :oauth-refresh-strategy nil
     :oauth-to-auth-strategy nil
     :model-filter-strategy nil)
    (:id :minimax-cn
     :baseline-source "packages/ai/src/providers/minimax-cn.ts:7"
     :name "MiniMax CN"
     :protocol :anthropic-messages
     :protocols (:anthropic-messages)
     :base-url "https://api.minimaxi.com/anthropic"
     :auth-types (:api-key)
     :default-model "MiniMax-M2.7"
     :key-environment "MINIMAX_CN_API_KEY"
     :required-environment nil
     :dynamic-models-p nil
     :supports-images-p nil
     :supports-tools-p t
     :reasoning-p nil
     :oauth-metadata nil
     :api-key-name "MiniMax CN API key"
     :environment-names ("MINIMAX_CN_API_KEY")
     :api-key-auth-strategy :environment
     :oauth-login-strategy nil
     :oauth-refresh-strategy nil
     :oauth-to-auth-strategy nil
     :model-filter-strategy nil)
    (:id :mistral
     :baseline-source "packages/ai/src/providers/mistral.ts:7"
     :name "Mistral"
     :protocol :mistral-conversations
     :protocols (:mistral-conversations)
     :base-url "https://api.mistral.ai"
     :auth-types (:api-key)
     :default-model "devstral-medium-latest"
     :key-environment "MISTRAL_API_KEY"
     :required-environment nil
     :dynamic-models-p nil
     :supports-images-p nil
     :supports-tools-p t
     :reasoning-p nil
     :oauth-metadata nil
     :api-key-name "Mistral API key"
     :environment-names ("MISTRAL_API_KEY")
     :api-key-auth-strategy :environment
     :oauth-login-strategy nil
     :oauth-refresh-strategy nil
     :oauth-to-auth-strategy nil
     :model-filter-strategy nil)
    (:id :moonshotai
     :baseline-source "packages/ai/src/providers/moonshotai.ts:7"
     :name "Moonshot AI"
     :protocol :openai-completions
     :protocols (:openai-completions)
     :base-url "https://api.moonshot.ai/v1"
     :auth-types (:api-key)
     :default-model "kimi-k2.6"
     :key-environment "MOONSHOT_API_KEY"
     :required-environment nil
     :dynamic-models-p nil
     :supports-images-p nil
     :supports-tools-p t
     :reasoning-p nil
     :oauth-metadata nil
     :api-key-name "Moonshot AI API key"
     :environment-names ("MOONSHOT_API_KEY")
     :api-key-auth-strategy :environment
     :oauth-login-strategy nil
     :oauth-refresh-strategy nil
     :oauth-to-auth-strategy nil
     :model-filter-strategy nil)
    (:id :moonshotai-cn
     :baseline-source "packages/ai/src/providers/moonshotai-cn.ts:7"
     :name "Moonshot AI CN"
     :protocol :openai-completions
     :protocols (:openai-completions)
     :base-url "https://api.moonshot.cn/v1"
     :auth-types (:api-key)
     :default-model "kimi-k2.6"
     :key-environment "MOONSHOT_API_KEY"
     :required-environment nil
     :dynamic-models-p nil
     :supports-images-p nil
     :supports-tools-p t
     :reasoning-p nil
     :oauth-metadata nil
     :api-key-name "Moonshot AI API key"
     :environment-names ("MOONSHOT_API_KEY")
     :api-key-auth-strategy :environment
     :oauth-login-strategy nil
     :oauth-refresh-strategy nil
     :oauth-to-auth-strategy nil
     :model-filter-strategy nil)
    (:id :nvidia
     :baseline-source "packages/ai/src/providers/nvidia.ts:7"
     :name "NVIDIA"
     :protocol :openai-completions
     :protocols (:openai-completions)
     :base-url "https://integrate.api.nvidia.com/v1"
     :auth-types (:api-key)
     :default-model "nvidia/nemotron-3-super-120b-a12b"
     :key-environment "NVIDIA_API_KEY"
     :required-environment nil
     :dynamic-models-p nil
     :supports-images-p nil
     :supports-tools-p t
     :reasoning-p nil
     :oauth-metadata nil
     :api-key-name "NVIDIA API key"
     :environment-names ("NVIDIA_API_KEY")
     :api-key-auth-strategy :environment
     :oauth-login-strategy nil
     :oauth-refresh-strategy nil
     :oauth-to-auth-strategy nil
     :model-filter-strategy nil)
    (:id :openai
     :baseline-source "packages/ai/src/providers/openai.ts:7"
     :name "OpenAI"
     :protocol :openai-responses
     :protocols (:openai-responses)
     :base-url "https://api.openai.com/v1"
     :auth-types (:api-key)
     :default-model "gpt-5.5"
     :key-environment "OPENAI_API_KEY"
     :required-environment nil
     :dynamic-models-p nil
     :supports-images-p nil
     :supports-tools-p t
     :reasoning-p nil
     :oauth-metadata nil
     :api-key-name "OpenAI API key"
     :environment-names ("OPENAI_API_KEY")
     :api-key-auth-strategy :environment
     :oauth-login-strategy nil
     :oauth-refresh-strategy nil
     :oauth-to-auth-strategy nil
     :model-filter-strategy nil)
    (:id :openai-codex
     :baseline-source "packages/ai/src/providers/openai-codex.ts:8"
     :name "OpenAI Codex"
     :protocol :openai-codex-responses
     :protocols (:openai-codex-responses)
     :base-url "https://chatgpt.com/backend-api"
     :auth-types (:oauth)
     :default-model "gpt-5.5"
     :key-environment nil
     :required-environment nil
     :dynamic-models-p nil
     :supports-images-p nil
     :supports-tools-p t
     :reasoning-p nil
     :oauth-metadata ,+openai-codex-oauth-metadata+
     :api-key-name nil
     :environment-names nil
     :api-key-auth-strategy nil
     :oauth-login-strategy :openai-device
     :oauth-refresh-strategy :openai-device
     :oauth-to-auth-strategy :access-token
     :model-filter-strategy nil)
    (:id :opencode
     :baseline-source "packages/ai/src/providers/opencode.ts:12"
     :name "OpenCode Zen"
     :protocol :openai-completions
     :protocols (:anthropic-messages :google-generative-ai :openai-completions :openai-responses)
     :base-url "https://opencode.ai/zen/v1"
     :auth-types (:api-key)
     :default-model "kimi-k2.6"
     :key-environment "OPENCODE_API_KEY"
     :required-environment nil
     :dynamic-models-p nil
     :supports-images-p nil
     :supports-tools-p t
     :reasoning-p nil
     :oauth-metadata nil
     :api-key-name "OpenCode API key"
     :environment-names ("OPENCODE_API_KEY")
     :api-key-auth-strategy :environment
     :oauth-login-strategy nil
     :oauth-refresh-strategy nil
     :oauth-to-auth-strategy nil
     :model-filter-strategy nil)
    (:id :opencode-go
     :baseline-source "packages/ai/src/providers/opencode-go.ts:9"
     :name "OpenCode Go"
     :protocol :openai-completions
     :protocols (:anthropic-messages :openai-completions :openai-responses)
     :base-url "https://opencode.ai/zen/go/v1"
     :auth-types (:api-key)
     :default-model "kimi-k2.6"
     :key-environment "OPENCODE_API_KEY"
     :required-environment nil
     :dynamic-models-p nil
     :supports-images-p nil
     :supports-tools-p t
     :reasoning-p nil
     :oauth-metadata nil
     :api-key-name "OpenCode API key"
     :environment-names ("OPENCODE_API_KEY")
     :api-key-auth-strategy :environment
     :oauth-login-strategy nil
     :oauth-refresh-strategy nil
     :oauth-to-auth-strategy nil
     :model-filter-strategy nil)
    (:id :openrouter
     :baseline-source "packages/ai/src/providers/openrouter.ts:8"
     :name "OpenRouter"
     :protocol :openai-completions
     :protocols (:openai-completions)
     :base-url "https://openrouter.ai/api/v1"
     :auth-types (:api-key :oauth)
     :default-model "moonshotai/kimi-k2.6"
     :key-environment "OPENROUTER_API_KEY"
     :required-environment nil
     :dynamic-models-p nil
     :supports-images-p nil
     :supports-tools-p t
     :reasoning-p nil
     :oauth-metadata ,+openrouter-oauth-metadata+
     :api-key-name "OpenRouter API key"
     :environment-names ("OPENROUTER_API_KEY")
     :api-key-auth-strategy :environment
     :oauth-login-strategy :openrouter
     :oauth-refresh-strategy :openrouter
     :oauth-to-auth-strategy :access-token
     :model-filter-strategy nil)
    (:id :qwen-token-plan
     :baseline-source "packages/ai/src/providers/qwen-token-plan.ts:7"
     :name "Qwen Token Plan"
     :protocol :openai-completions
     :protocols (:openai-completions)
     :base-url "https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1"
     :auth-types (:api-key)
     :default-model "qwen3.7-max"
     :key-environment "QWEN_TOKEN_PLAN_API_KEY"
     :required-environment nil
     :dynamic-models-p nil
     :supports-images-p nil
     :supports-tools-p t
     :reasoning-p nil
     :oauth-metadata nil
     :api-key-name "Qwen Token Plan API key"
     :environment-names ("QWEN_TOKEN_PLAN_API_KEY")
     :api-key-auth-strategy :environment
     :oauth-login-strategy nil
     :oauth-refresh-strategy nil
     :oauth-to-auth-strategy nil
     :model-filter-strategy nil)
    (:id :qwen-token-plan-cn
     :baseline-source "packages/ai/src/providers/qwen-token-plan-cn.ts:7"
     :name "Qwen Token Plan CN"
     :protocol :openai-completions
     :protocols (:openai-completions)
     :base-url "https://token-plan.cn-beijing.maas.aliyuncs.com/compatible-mode/v1"
     :auth-types (:api-key)
     :default-model "qwen3.7-max"
     :key-environment "QWEN_TOKEN_PLAN_CN_API_KEY"
     :required-environment nil
     :dynamic-models-p nil
     :supports-images-p nil
     :supports-tools-p t
     :reasoning-p nil
     :oauth-metadata nil
     :api-key-name "Qwen Token Plan CN API key"
     :environment-names ("QWEN_TOKEN_PLAN_CN_API_KEY")
     :api-key-auth-strategy :environment
     :oauth-login-strategy nil
     :oauth-refresh-strategy nil
     :oauth-to-auth-strategy nil
     :model-filter-strategy nil)
    (:id :qwen-token-plan-individual
     :baseline-source
     "packages/ai/src/providers/qwen-token-plan-individual.ts:7"
     :name "Qwen Token Plan Individual"
     :protocol :openai-completions
     :protocols (:openai-completions)
     :base-url
     "https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1"
     :auth-types (:api-key)
     :default-model "qwen3.8-max"
     :key-environment "QWEN_TOKEN_PLAN_API_KEY"
     :required-environment nil
     :dynamic-models-p nil
     :supports-images-p nil
     :supports-tools-p t
     :reasoning-p nil
     :oauth-metadata nil
     :api-key-name "Qwen Token Plan Individual API key"
     :environment-names ("QWEN_TOKEN_PLAN_API_KEY")
     :api-key-auth-strategy :environment
     :oauth-login-strategy nil
     :oauth-refresh-strategy nil
     :oauth-to-auth-strategy nil
     :model-filter-strategy nil)
    (:id :radius
     :baseline-source "packages/ai/src/providers/radius.ts:28"
     :name "Radius"
     :protocol :pi-messages
     :protocols (:pi-messages)
     :base-url "https://radius.pi.dev"
     :auth-types (:api-key :oauth)
     :default-model "auto"
     :key-environment "RADIUS_API_KEY"
     :required-environment nil
     :dynamic-models-p t
     :supports-images-p nil
     :supports-tools-p t
     :reasoning-p nil
     :oauth-metadata ,+radius-oauth-metadata+
     :api-key-name "Radius API key"
     :environment-names ("RADIUS_API_KEY" "RADIUS_GATEWAY_URL")
     :api-key-auth-strategy :environment
     :oauth-login-strategy :radius
     :oauth-refresh-strategy :radius
     :oauth-to-auth-strategy :access-token
     :model-filter-strategy nil)
    (:id :together
     :baseline-source "packages/ai/src/providers/together.ts:7"
     :name "Together"
     :protocol :openai-completions
     :protocols (:openai-completions)
     :base-url "https://api.together.ai/v1"
     :auth-types (:api-key)
     :default-model "moonshotai/Kimi-K2.6"
     :key-environment "TOGETHER_API_KEY"
     :required-environment nil
     :dynamic-models-p nil
     :supports-images-p nil
     :supports-tools-p t
     :reasoning-p nil
     :oauth-metadata nil
     :api-key-name "Together API key"
     :environment-names ("TOGETHER_API_KEY")
     :api-key-auth-strategy :environment
     :oauth-login-strategy nil
     :oauth-refresh-strategy nil
     :oauth-to-auth-strategy nil
     :model-filter-strategy nil)
    (:id :vercel-ai-gateway
     :baseline-source "packages/ai/src/providers/vercel-ai-gateway.ts:7"
     :name "Vercel AI Gateway"
     :protocol :anthropic-messages
     :protocols (:anthropic-messages)
     :base-url "https://ai-gateway.vercel.sh"
     :auth-types (:api-key)
     :default-model "zai/glm-5.1"
     :key-environment "AI_GATEWAY_API_KEY"
     :required-environment nil
     :dynamic-models-p nil
     :supports-images-p nil
     :supports-tools-p t
     :reasoning-p nil
     :oauth-metadata nil
     :api-key-name "Vercel AI Gateway API key"
     :environment-names ("AI_GATEWAY_API_KEY")
     :api-key-auth-strategy :environment
     :oauth-login-strategy nil
     :oauth-refresh-strategy nil
     :oauth-to-auth-strategy nil
     :model-filter-strategy nil)
    (:id :xai
     :baseline-source "packages/ai/src/providers/xai.ts:9"
     :name "xAI"
     :protocol :openai-responses
     :protocols (:openai-completions :openai-responses)
     :base-url "https://api.x.ai/v1"
     :auth-types (:api-key :oauth)
     :default-model "grok-4.5"
     :key-environment "XAI_API_KEY"
     :required-environment nil
     :dynamic-models-p nil
     :supports-images-p nil
     :supports-tools-p t
     :reasoning-p nil
     :oauth-metadata ,+xai-oauth-metadata+
     :api-key-name "xAI API key"
     :environment-names ("XAI_API_KEY")
     :api-key-auth-strategy :environment
     :oauth-login-strategy :xai
     :oauth-refresh-strategy :xai
     :oauth-to-auth-strategy :access-token
     :model-filter-strategy nil)
    (:id :xiaomi
     :baseline-source "packages/ai/src/providers/xiaomi.ts:7"
     :name "Xiaomi"
     :protocol :openai-completions
     :protocols (:openai-completions)
     :base-url "https://api.xiaomimimo.com/v1"
     :auth-types (:api-key)
     :default-model "mimo-v2.5-pro"
     :key-environment "XIAOMI_API_KEY"
     :required-environment nil
     :dynamic-models-p nil
     :supports-images-p nil
     :supports-tools-p t
     :reasoning-p nil
     :oauth-metadata nil
     :api-key-name "Xiaomi API key"
     :environment-names ("XIAOMI_API_KEY")
     :api-key-auth-strategy :environment
     :oauth-login-strategy nil
     :oauth-refresh-strategy nil
     :oauth-to-auth-strategy nil
     :model-filter-strategy nil)
    (:id :xiaomi-token-plan-ams
     :baseline-source "packages/ai/src/providers/xiaomi-token-plan-ams.ts:7"
     :name "Xiaomi Token Plan AMS"
     :protocol :openai-completions
     :protocols (:openai-completions)
     :base-url "https://token-plan-ams.xiaomimimo.com/v1"
     :auth-types (:api-key)
     :default-model "mimo-v2.5-pro"
     :key-environment "XIAOMI_TOKEN_PLAN_AMS_API_KEY"
     :required-environment nil
     :dynamic-models-p nil
     :supports-images-p nil
     :supports-tools-p t
     :reasoning-p nil
     :oauth-metadata nil
     :api-key-name "Xiaomi Token Plan AMS API key"
     :environment-names ("XIAOMI_TOKEN_PLAN_AMS_API_KEY")
     :api-key-auth-strategy :environment
     :oauth-login-strategy nil
     :oauth-refresh-strategy nil
     :oauth-to-auth-strategy nil
     :model-filter-strategy nil)
    (:id :xiaomi-token-plan-cn
     :baseline-source "packages/ai/src/providers/xiaomi-token-plan-cn.ts:7"
     :name "Xiaomi Token Plan CN"
     :protocol :openai-completions
     :protocols (:openai-completions)
     :base-url "https://token-plan-cn.xiaomimimo.com/v1"
     :auth-types (:api-key)
     :default-model "mimo-v2.5-pro"
     :key-environment "XIAOMI_TOKEN_PLAN_CN_API_KEY"
     :required-environment nil
     :dynamic-models-p nil
     :supports-images-p nil
     :supports-tools-p t
     :reasoning-p nil
     :oauth-metadata nil
     :api-key-name "Xiaomi Token Plan CN API key"
     :environment-names ("XIAOMI_TOKEN_PLAN_CN_API_KEY")
     :api-key-auth-strategy :environment
     :oauth-login-strategy nil
     :oauth-refresh-strategy nil
     :oauth-to-auth-strategy nil
     :model-filter-strategy nil)
    (:id :xiaomi-token-plan-sgp
     :baseline-source "packages/ai/src/providers/xiaomi-token-plan-sgp.ts:7"
     :name "Xiaomi Token Plan SGP"
     :protocol :openai-completions
     :protocols (:openai-completions)
     :base-url "https://token-plan-sgp.xiaomimimo.com/v1"
     :auth-types (:api-key)
     :default-model "mimo-v2.5-pro"
     :key-environment "XIAOMI_TOKEN_PLAN_SGP_API_KEY"
     :required-environment nil
     :dynamic-models-p nil
     :supports-images-p nil
     :supports-tools-p t
     :reasoning-p nil
     :oauth-metadata nil
     :api-key-name "Xiaomi Token Plan SGP API key"
     :environment-names ("XIAOMI_TOKEN_PLAN_SGP_API_KEY")
     :api-key-auth-strategy :environment
     :oauth-login-strategy nil
     :oauth-refresh-strategy nil
     :oauth-to-auth-strategy nil
     :model-filter-strategy nil)
    (:id :zai
     :baseline-source "packages/ai/src/providers/zai.ts:7"
     :name "Z.AI"
     :protocol :openai-completions
     :protocols (:openai-completions)
     :base-url "https://api.z.ai/api/coding/paas/v4"
     :auth-types (:api-key)
     :default-model "glm-5.1"
     :key-environment "ZAI_API_KEY"
     :required-environment nil
     :dynamic-models-p nil
     :supports-images-p nil
     :supports-tools-p t
     :reasoning-p nil
     :oauth-metadata nil
     :api-key-name "Z.AI API key"
     :environment-names ("ZAI_API_KEY")
     :api-key-auth-strategy :environment
     :oauth-login-strategy nil
     :oauth-refresh-strategy nil
     :oauth-to-auth-strategy nil
     :model-filter-strategy nil)
    (:id :zai-coding-cn
     :baseline-source "packages/ai/src/providers/zai-coding-cn.ts:7"
     :name "Z.AI Coding CN"
     :protocol :openai-completions
     :protocols (:openai-completions)
     :base-url "https://open.bigmodel.cn/api/coding/paas/v4"
     :auth-types (:api-key)
     :default-model "glm-5.1"
     :key-environment "ZAI_CODING_CN_API_KEY"
     :required-environment nil
     :dynamic-models-p nil
     :supports-images-p nil
     :supports-tools-p t
     :reasoning-p nil
     :oauth-metadata nil
     :api-key-name "Z.AI Coding CN API key"
     :environment-names ("ZAI_CODING_CN_API_KEY")
     :api-key-auth-strategy :environment
     :oauth-login-strategy nil
     :oauth-refresh-strategy nil
     :oauth-to-auth-strategy nil
     :model-filter-strategy nil)))

(defun provider-definition-row-keys ()
  ;; Slot names from MOP. Adding a slot is the row contract; do not
  ;; hand-copy 22 keywords again.
  (let ((class (find-class 'provider-definition)))
    (unless (sb-mop:class-finalized-p class)
      (sb-mop:finalize-inheritance class))
    (mapcar
     (lambda (name)
       (intern (symbol-name name) :keyword))
     (mapcar #'sb-mop:slot-definition-name
             (sb-mop:class-slots class)))))

(defun validate-provider-definition-row (row)
  (let ((keys (loop for tail on row by #'cddr
                    collect (car tail)))
        (expected (provider-definition-row-keys)))
    (unless (and (= (length keys) (length expected))
                 (null (set-difference keys expected))
                 (null (set-difference expected keys)))
      (error 'configuration-error
             :message (format nil "Invalid provider declaration fields for ~A"
                              (getf row :id)))))
  (unless (and (keywordp (getf row :id))
               (non-empty-string-p (getf row :baseline-source))
               (non-empty-string-p (getf row :name))
               (keywordp (getf row :protocol))
               (member (getf row :protocol) (getf row :protocols))
               (stringp (getf row :base-url))
               (non-empty-string-p (getf row :default-model)))
    (error 'configuration-error
           :message (format nil "Incomplete provider declaration for ~A"
                            (getf row :id))))
  (dolist (name (append (getf row :environment-names)
                        (remove-if-not #'stringp
                                       (getf row :required-environment))))
    (unless (non-empty-string-p name)
      (error 'configuration-error
             :message (format nil "Invalid provider environment name for ~A"
                              (getf row :id)))))
  (unless (= (length (getf row :environment-names))
             (length (remove-duplicates (getf row :environment-names)
                                        :test #'string=)))
    (error 'configuration-error
           :message (format nil "Duplicate provider environment name for ~A"
                            (getf row :id))))
  (unless (eq (not (null (member :api-key (getf row :auth-types))))
              (not (null (getf row :api-key-auth-strategy))))
    (error 'configuration-error
           :message (format nil "Incoherent API-key declaration for ~A"
                            (getf row :id))))
  (let ((oauth-p (not (null (member :oauth (getf row :auth-types))))))
    (unless (and (eq oauth-p (not (null (getf row :oauth-metadata))))
                 (eq oauth-p (not (null (getf row :oauth-login-strategy))))
                 (eq oauth-p (not (null (getf row :oauth-refresh-strategy))))
                 (eq oauth-p (not (null (getf row :oauth-to-auth-strategy)))))
      (error 'configuration-error
             :message (format nil "Incoherent OAuth declaration for ~A"
                              (getf row :id)))))
  row)

(defvar *provider-definitions-list-cache* nil)

(defun register-provider-definition (definition)
  (setf *provider-definitions-list-cache* nil)
  (setf (gethash (provider-definition-id definition)
                 *provider-definitions*)
        definition)
  definition)

(defun find-provider-definition (id)
  (or (gethash id *provider-definitions*)
      (error 'configuration-error
             :message (format nil "Unknown provider: ~A" id))))

(defun provider-oauth-subscription-p (id)
  ;; pi@b79e4cc83 core/model-runtime.ts:462-464 isUsingSubscription:
  ;; true when the provider's OAuth registration is subscription-backed.
  (let ((definition (gethash id *provider-definitions*)))
    (and definition
         (let ((metadata
                 (provider-definition-oauth-metadata definition)))
           (and metadata
                (oauth-provider-metadata-is-subscription-p metadata)
                t)))))

(defun list-provider-definitions ()
  (let ((source *provider-definitions*))
    (if (and *provider-definitions-list-cache*
             (eq (first *provider-definitions-list-cache*) source))
        (second *provider-definitions-list-cache*)
        (let ((definitions
                (sort
                 (loop for definition being the hash-values
                         of source
                       collect definition)
                 #'string<
                 :key (lambda (definition)
                        (symbol-name
                         (provider-definition-id definition))))))
          (setf *provider-definitions-list-cache*
                (list source definitions))
          definitions))))

(defvar *provider-definition-ids-cache* nil)
(defvar *provider-definition-ids-digest-cache* nil)

(defun list-provider-definition-ids ()
  ;; pi packages/ai/src/providers/all.ts getBuiltinProviders: Object.keys(MODELS).
  (let ((source *model-catalog*))
    (if (and *provider-definition-ids-cache*
             (eq (first *provider-definition-ids-cache*) source))
        (second *provider-definition-ids-cache*)
        (let ((ids
                (sort
                 (loop with seen = (make-hash-table :test #'equal)
                       for metadata being the hash-values of source
                       for name = (string-downcase
                                   (symbol-name
                                    (model-metadata-provider metadata)))
                       unless (gethash name seen)
                         do (setf (gethash name seen) t)
                         and collect name)
                 #'string<)))
          (setf *provider-definition-ids-cache* (list source ids)
                *provider-definition-ids-digest-cache* nil)
          ids))))

(defun provider-definition-ids-sorted-digest ()
  (let ((ids (list-provider-definition-ids)))
    (if (and *provider-definition-ids-digest-cache*
             (eq (first *provider-definition-ids-digest-cache*) ids))
        (second *provider-definition-ids-digest-cache*)
        (let ((digest
                (octets-hex
                 (sha256-bytes
                  (utf8-octets
                   (format nil "~{~a~^~%~}" ids))))))
          (setf *provider-definition-ids-digest-cache*
                (list ids digest))
          digest))))

(defun register-built-in-providers ()
  (clrhash *provider-definitions*)
  (setf *provider-definitions-list-cache* nil)
  (dolist (row *built-in-provider-definition-rows*)
    (validate-provider-definition-row row)
    (when (gethash (getf row :id) *provider-definitions*)
      (error 'configuration-error
             :message (format nil "Duplicate provider declaration: ~A"
                              (getf row :id))))
    (register-provider-definition
     (apply #'make-provider-definition row))))

(register-built-in-providers)

(defparameter +built-in-runtime-environment-names+
  (sort
   (remove-duplicates
    (loop for definition in (list-provider-definitions)
          append (copy-list
                  (provider-definition-environment-names definition)))
    :test #'string=)
   #'string<))
