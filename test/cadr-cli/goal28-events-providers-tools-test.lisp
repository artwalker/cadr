(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun goal28-event-keyword (name)
  (intern
   (string-upcase
    (substitute #\- #\_ name))
   :keyword))

(defparameter +goal28-pin-extension-events+
  '("after_provider_response" "agent_end" "agent_settled"
    "agent_start" "before_agent_start" "before_provider_headers"
    "before_provider_request" "context" "input" "message_end"
    "message_start" "message_update" "model_select"
    "project_trust" "resources_discover" "session_before_compact"
    "session_before_fork" "session_before_switch"
    "session_before_tree" "session_compact"
    "session_compact_failed" "session_info_changed"
    "session_shutdown" "session_start" "session_tree"
    "thinking_level_select" "tool_execution_end"
    "tool_execution_start" "tool_execution_update" "turn_end"
    "turn_start" "ui_prompt_end" "ui_prompt_start" "user_bash"))

(defparameter +goal28-pin-provider-files+
  '("amazon-bedrock.ts" "ant-ling.ts" "anthropic.ts"
    "azure-openai-responses.ts" "baseten.ts" "cerebras.ts"
    "cloudflare-ai-gateway.ts" "cloudflare-workers-ai.ts"
    "deepseek.ts" "fireworks.ts" "github-copilot.ts"
    "google-vertex.ts" "google.ts" "groq.ts" "huggingface.ts"
    "kimi-coding.ts" "minimax-cn.ts" "minimax.ts" "mistral.ts"
    "moonshotai-cn.ts" "moonshotai.ts" "nvidia.ts"
    "openai-codex.ts" "openai.ts" "opencode-go.ts" "opencode.ts"
    "openrouter.ts" "qwen-token-plan-cn.ts"
    "qwen-token-plan-individual.ts" "qwen-token-plan.ts"
    "radius.ts" "together.ts" "vercel-ai-gateway.ts" "xai.ts"
    "xiaomi-token-plan-ams.ts" "xiaomi-token-plan-cn.ts"
    "xiaomi-token-plan-sgp.ts" "xiaomi.ts" "zai-coding-cn.ts"
    "zai.ts"))

(defparameter +goal28-pin-tool-files+
  '("bash.ts" "edit.ts" "find.ts" "grep.ts" "ls.ts"
    "powershell.ts" "read.ts" "write.ts"))

(defun goal28-provider-id-from-file (filename)
  (intern
   (string-upcase
    (subseq filename 0 (- (length filename) 3)))
   :keyword))

(test goal28-extension-events-reach-existing-hook-table
  (dolist (name +goal28-pin-extension-events+)
    (is (member
         (goal28-event-keyword name)
         cadr-agent::+extension-hook-events+))))

(test goal28-providers-reach-existing-definitions
  (dolist (filename +goal28-pin-provider-files+)
    (let* ((id (goal28-provider-id-from-file filename))
           (definition
             (cadr-ai::find-provider-definition id)))
      (is (not (null definition)))
      (is (eq id
              (cadr-ai::provider-definition-id
               definition))))))

(test goal28-tool-files-reach-existing-makers
  (is (fboundp 'cadr-cli:make-bash-tool))
  (is (fboundp 'cadr-cli:make-edit-tool))
  (is (fboundp 'cadr-cli:make-find-tool))
  (is (fboundp 'cadr-cli:make-grep-tool))
  (is (fboundp 'cadr-cli:make-ls-tool))
  (is (fboundp 'cadr-cli:make-powershell-tool))
  (is (fboundp 'cadr-cli:make-read-tool))
  (is (fboundp 'cadr-cli:make-write-tool))
  (let* ((cwd (uiop:getcwd))
         (tools
           (list
            (cadr-cli:make-bash-tool cwd)
            (cadr-cli:make-edit-tool cwd)
            (cadr-cli:make-find-tool cwd)
            (cadr-cli:make-grep-tool cwd)
            (cadr-cli:make-ls-tool cwd)
            (cadr-cli:make-powershell-tool cwd)
            (cadr-cli:make-read-tool cwd)
            (cadr-cli:make-write-tool cwd))))
    (is (= (length +goal28-pin-tool-files+)
           (length tools)))
    (dolist (tool tools)
      (is (typep tool 'cadr-ai:tool)))))
