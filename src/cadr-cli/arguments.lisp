(in-package #:cadr-cli)

(defparameter +thinking-level-names+
  '("off" "minimal" "low" "medium"
    "high" "xhigh" "max"))

(defstruct cli-arguments
  provider
  model
  api-key
  base-url
  system-prompt
  (append-system-prompts nil :type list)
  thinking
  mode
  name
  slynk-port
  (print-p nil :type boolean)
  (messages nil :type list)
  (file-arguments nil :type list)
  (continue-p nil :type boolean)
  (resume-p nil :type boolean)
  resume
  (no-session-p nil :type boolean)
  session
  session-id
  fork
  session-directory
  (models nil :type list)
  (tools nil :type list)
  (exclude-tools nil :type list)
  (no-tools-p nil :type boolean)
  (no-builtin-tools-p nil :type boolean)
  (extensions nil :type list)
  (no-extensions-p nil :type boolean)
  export
  (skills nil :type list)
  (no-skills-p nil :type boolean)
  (prompt-templates nil :type list)
  (no-prompt-templates-p nil :type boolean)
  (themes nil :type list)
  (no-themes-p nil :type boolean)
  (no-context-files-p nil :type boolean)
  list-models
  (offline-p nil :type boolean)
  (alt-p nil :type boolean)
  (verbose-p nil :type boolean)
  project-trust-override
  (project-trust-override-supplied-p nil :type boolean)
  (unknown-flags (make-hash-table :test #'equal)
                 :type hash-table)
  (diagnostics nil :type list)
  (no-tui-p nil :type boolean)
  (help-p nil :type boolean)
  (version-p nil :type boolean))

(cadr-core:define-redacted-print-object (cli-arguments value stream)
  (format stream ":mode ~A :provider ~A :model ~A :credentials [REDACTED]"
          (cli-arguments-mode value)
          (cli-arguments-provider value)
          (cli-arguments-model value)))

(defparameter +cli-value-options+
  '(("--provider" . :provider)
    ("--model" . :model)
    ("--api-key" . :api-key)
    ("--base-url" . :base-url)
    ("--system-prompt" . :system-prompt)
    ("--append-system-prompt" . :append-system-prompt)
    ("--thinking" . :thinking)
    ("--mode" . :mode)
    ("--name" . :name)
    ("-n" . :name)
    ("--slynk" . :slynk)
    ("--session" . :session)
    ("--session-id" . :session-id)
    ("--fork" . :fork)
    ("--session-dir" . :session-directory)
    ("--models" . :models)
    ("--tools" . :tools)
    ("-t" . :tools)
    ("--exclude-tools" . :exclude-tools)
    ("-xt" . :exclude-tools)
    ("--extension" . :extension)
    ("-e" . :extension)
    ("--export" . :export)
    ("--skill" . :skill)
    ("--prompt-template" . :prompt-template)
    ("--theme" . :theme)))

(defparameter +cli-flag-options+
  '(("--continue" . :continue)
    ("-c" . :continue)
    ("--no-session" . :no-session)
    ("--no-tools" . :no-tools)
    ("-nt" . :no-tools)
    ("--no-builtin-tools" . :no-builtin-tools)
    ("-nbt" . :no-builtin-tools)
    ("--no-extensions" . :no-extensions)
    ("-ne" . :no-extensions)
    ("--print" . :print)
    ("-p" . :print)
    ("--no-skills" . :no-skills)
    ("-ns" . :no-skills)
    ("--no-prompt-templates" . :no-prompt-templates)
    ("-np" . :no-prompt-templates)
    ("--no-themes" . :no-themes)
    ("--no-context-files" . :no-context-files)
    ("-nc" . :no-context-files)
    ("--offline" . :offline)
    ("--alt" . :alt)
    ("--verbose" . :verbose)
    ("--approve" . :approve)
    ("-a" . :approve)
    ("--no-approve" . :no-approve)
    ("-na" . :no-approve)
    ("--no-tui" . :no-tui)
    ("--help" . :help)
    ("-h" . :help)
    ("--version" . :version)
    ("-v" . :version)))

(defun cli-string-prefix-p (prefix value)
  (and (<= (length prefix) (length value))
       (string= prefix value
                :end2 (length prefix))))

(defun option-with-equals (argument)
  (let ((equals (position #\= argument)))
    (when equals
      (values (subseq argument 0 equals)
              (subseq argument (1+ equals))))))

(defun split-comma-option (value)
  (remove
   ""
   (mapcar
    (lambda (item)
      (string-trim
       '(#\Space #\Tab #\Newline #\Return)
       item))
    (uiop:split-string value :separator '(#\,)))
   :test #'string=))

(defun add-cli-diagnostic (arguments type message)
  (setf
   (cli-arguments-diagnostics arguments)
   (append
    (cli-arguments-diagnostics arguments)
    (list (list :type type :message message)))))

(defun set-cli-value (arguments key value)
  (case key
    (:provider
     (setf (cli-arguments-provider arguments) value))
    (:model
     (setf (cli-arguments-model arguments) value))
    (:api-key
     (setf (cli-arguments-api-key arguments) value))
    (:base-url
     (setf (cli-arguments-base-url arguments) value))
    (:system-prompt
     (setf (cli-arguments-system-prompt arguments) value))
    (:append-system-prompt
     (setf
      (cli-arguments-append-system-prompts arguments)
      (append
       (cli-arguments-append-system-prompts arguments)
       (list value))))
    (:thinking
     (if (valid-thinking-level-p value)
         (setf
          (cli-arguments-thinking arguments)
          (intern (string-upcase value) :keyword))
         (add-cli-diagnostic
          arguments :warning
          (format nil
                  "Invalid thinking level ~S. Valid values: ~{~A~^, ~}"
                  value +thinking-level-names+))))
    (:mode
     (let ((mode
             (find
              value
              '(:text :json :rpc)
              :key #'symbol-name
              :test #'string-equal)))
       (if mode
           (setf (cli-arguments-mode arguments) mode)
           (error
            'cadr-ai:configuration-error
            :message
            "--mode must be text, json, or rpc"))))
    (:name
     (setf (cli-arguments-name arguments) value))
    (:slynk
     (if
         (and
          (plusp (length value))
          (every
           (lambda (character)
             (digit-char-p character 10))
           value))
         (let ((port (parse-integer value :radix 10)))
           (if (<= 1 port 65535)
               (setf
                (cli-arguments-slynk-port arguments)
                port)
               (error
                'cadr-ai:configuration-error
                :message
                "--slynk must be a decimal port in the range 1..65535")))
         (error
          'cadr-ai:configuration-error
          :message
          "--slynk must be a decimal port in the range 1..65535")))
    (:session
     (setf (cli-arguments-session arguments) value))
    (:session-id
     (setf (cli-arguments-session-id arguments) value))
    (:fork
     (setf (cli-arguments-fork arguments) value))
    (:session-directory
     (setf
      (cli-arguments-session-directory arguments)
      value))
    (:models
     (setf
      (cli-arguments-models arguments)
      (split-comma-option value)))
    (:tools
     (setf
      (cli-arguments-tools arguments)
      (split-comma-option value)))
    (:exclude-tools
     (setf
      (cli-arguments-exclude-tools arguments)
      (split-comma-option value)))
    (:extension
     (setf
      (cli-arguments-extensions arguments)
      (append
       (cli-arguments-extensions arguments)
       (list value))))
    (:export
     (setf (cli-arguments-export arguments) value))
    (:skill
     (setf
      (cli-arguments-skills arguments)
      (append
       (cli-arguments-skills arguments)
       (list value))))
    (:prompt-template
     (setf
      (cli-arguments-prompt-templates arguments)
      (append
       (cli-arguments-prompt-templates arguments)
       (list value))))
    (:theme
     (setf
      (cli-arguments-themes arguments)
      (append
       (cli-arguments-themes arguments)
       (list value)))))
  arguments)

(defun set-cli-flag (arguments key)
  (case key
    (:continue
     (setf (cli-arguments-continue-p arguments) t))
    (:no-session
     (setf (cli-arguments-no-session-p arguments) t))
    (:no-tools
     (setf (cli-arguments-no-tools-p arguments) t))
    (:no-builtin-tools
     (setf (cli-arguments-no-builtin-tools-p arguments) t))
    (:no-extensions
     (setf (cli-arguments-no-extensions-p arguments) t))
    (:print
     (setf (cli-arguments-print-p arguments) t))
    (:no-skills
     (setf (cli-arguments-no-skills-p arguments) t))
    (:no-prompt-templates
     (setf
      (cli-arguments-no-prompt-templates-p arguments)
      t))
    (:no-themes
     (setf (cli-arguments-no-themes-p arguments) t))
    (:no-context-files
     (setf
      (cli-arguments-no-context-files-p arguments)
      t))
    (:offline
     (setf (cli-arguments-offline-p arguments) t))
    (:alt
     (setf (cli-arguments-alt-p arguments) t))
    (:verbose
     (setf (cli-arguments-verbose-p arguments) t))
    (:approve
     (setf
      (cli-arguments-project-trust-override arguments) t
      (cli-arguments-project-trust-override-supplied-p
       arguments) t))
    (:no-approve
     (setf
      (cli-arguments-project-trust-override arguments) nil
      (cli-arguments-project-trust-override-supplied-p
       arguments) t))
    (:no-tui
     (setf (cli-arguments-no-tui-p arguments) t))
    (:help
     (setf (cli-arguments-help-p arguments) t))
    (:version
     (setf (cli-arguments-version-p arguments) t)))
  arguments)

(defun cli-option-token-p (value)
  (and value
       (cli-string-prefix-p "-" value)
       (not
        (cli-string-prefix-p "---" value))))

(defun require-cli-value
    (argv equals-name equals-value)
  (let ((value
          (if equals-name
              equals-value
              (and
               argv
               (not
                (cli-option-token-p
                 (first argv)))
               (pop argv)))))
    (if (and value
             (or equals-name
                 (not
                  (cli-option-token-p value))))
        (values value argv)
        (values nil argv))))

(defun parse-cli-arguments (argv)
  (let ((arguments (make-cli-arguments)))
    (loop while argv
          for argument = (pop argv)
          do
          (cond
            ((or (string= argument "--resume")
                 (string= argument "-r"))
             ;; cadr historically accepted an exact id here. Preserve that
             ;; stable surface while also accepting the reference flag form.
             (if (and argv
                      (not (cli-option-token-p (first argv)))
                      (not (cli-string-prefix-p "@" (first argv))))
                 (setf
                  (cli-arguments-resume arguments)
                  (pop argv))
                 (setf
                  (cli-arguments-resume-p arguments)
                  t)))
            ((string= argument "--list-models")
             (if (and argv
                      (not (cli-option-token-p (first argv)))
                      (not (cli-string-prefix-p "@" (first argv))))
                 (setf
                  (cli-arguments-list-models arguments)
                  (pop argv))
                 (setf
                  (cli-arguments-list-models arguments)
                  t)))
            ((or (string= argument "--print")
                 (string= argument "-p"))
             (set-cli-flag arguments :print)
             (when
                 (and argv
                      (not
                       (cli-string-prefix-p
                        "@" (first argv)))
                      (or
                       (not
                        (cli-option-token-p
                         (first argv)))
                       (cli-string-prefix-p
                        "---" (first argv))))
               (setf
                (cli-arguments-messages arguments)
                (append
                 (cli-arguments-messages arguments)
                 (list (pop argv))))))
            ((and (plusp (length argument))
                  (char= (char argument 0) #\@))
             (setf
              (cli-arguments-file-arguments arguments)
              (append
               (cli-arguments-file-arguments arguments)
               (list (subseq argument 1)))))
            (t
             (multiple-value-bind
                   (equals-name equals-value)
                 (option-with-equals argument)
               (let* ((name (or equals-name argument))
                      (value-option
                        (assoc name
                               +cli-value-options+
                               :test #'string=))
                      (flag-option
                        (assoc name
                               +cli-flag-options+
                               :test #'string=)))
                 (cond
                   (value-option
                    (multiple-value-bind (value rest)
                        (require-cli-value
                         argv equals-name equals-value)
                      (setf argv rest)
                      (if value
                          (set-cli-value
                           arguments
                           (cdr value-option)
                           value)
                          (error
                           'cadr-ai:configuration-error
                           :message
                           (format nil "~A requires a value"
                                   name)))))
                   (flag-option
                    (if equals-name
                        (add-cli-diagnostic
                         arguments :error
                         (format nil
                                 "Flag ~A takes no value"
                                 name))
                        (set-cli-flag
                         arguments
                         (cdr flag-option))))
                   ((string= argument "--yolo")
                    (error
                     'cadr-ai:configuration-error
                     :message "Unknown option: --yolo"))
                   ((cli-string-prefix-p "--" argument)
                    (let ((flag-name
                            (subseq
                             (or equals-name argument)
                             2)))
                      (cond
                        (equals-name
                         (setf
                          (gethash
                           flag-name
                           (cli-arguments-unknown-flags
                            arguments))
                          equals-value))
                        ((and argv
                              (not
                               (cli-option-token-p
                                (first argv)))
                              (not
                               (cli-string-prefix-p
                                "@" (first argv))))
                         (setf
                          (gethash
                           flag-name
                           (cli-arguments-unknown-flags
                            arguments))
                          (pop argv)))
                        (t
                         (setf
                          (gethash
                           flag-name
                           (cli-arguments-unknown-flags
                            arguments))
                          t)))))
                   ((cli-string-prefix-p "-" argument)
                    (add-cli-diagnostic
                     arguments :error
                     (format nil
                             "Unknown option: ~A"
                             argument)))
                   (t
                    (setf
                     (cli-arguments-messages arguments)
                     (append
                      (cli-arguments-messages arguments)
                      (list argument))))))))))
    arguments))

(defun cli-stream-color-p (stream)
  ;; The pre-TUI CLI contract follows chalk: SGR only when the stream is a
  ;; terminal and NO_COLOR is unset or empty.
  (and (interactive-stream-p stream)
       (let ((no-color (uiop:getenv "NO_COLOR")))
         (or (null no-color) (zerop (length no-color))))))

(defun cli-bold-text (stream text)
  (if (cli-stream-color-p stream)
      (format nil "~C[1m~A~C[22m" #\Escape text #\Escape)
      text))

(defun cli-error-text (stream text)
  ;; Baseline console.error(chalk.red(text)).
  (if (cli-stream-color-p stream)
      (format nil "~C[31m~A~C[39m" #\Escape text #\Escape)
      text))

(defun cli-warning-text (stream text)
  ;; Baseline chalk.yellow(text).
  (if (cli-stream-color-p stream)
      (format nil "~C[33m~A~C[39m" #\Escape text #\Escape)
      text))

(defun cli-dim-text (stream text)
  ;; Baseline chalk.dim(text).
  (if (cli-stream-color-p stream)
      (format nil "~C[2m~A~C[22m" #\Escape text #\Escape)
      text))

(defun cli-success-text (stream text)
  ;; Baseline chalk.green(text).
  (if (cli-stream-color-p stream)
      (format nil "~C[32m~A~C[39m" #\Escape text #\Escape)
      text))

(defun cli-pad-right (text width)
  (let ((length (length text)))
    (if (>= length width)
        text
        (concatenate
         'string text
         (make-string (- width length) :initial-element #\Space)))))

(defun print-cli-usage
    (&optional (stream *standard-output*) extension-flags)
  ;; Baseline cli/args.ts printHelp.  Extension flags are plists with
  ;; :name/:type/:description/:extension-path, mirroring ExtensionFlag.
  (flet ((bold (text) (cli-bold-text stream text)))
    (format
     stream
     "~A - AI coding assistant with read, bash, edit, write tools~%~%~A~%  cadr [options] [@files...] [messages...]~%~%~A~%  cadr install <source> [-l]     Install extension source and add to settings~%  cadr remove <source> [-l]      Remove extension source from settings~%  cadr uninstall <source> [-l]   Alias for remove~%  cadr update [source|self|cadr]   Update cadr, extensions, or model catalogs~%  cadr list                      List installed extensions from settings~%  cadr config [-l]               Open TUI to enable/disable package resources (Tab switches scope)~%  cadr auth <command>            Print credentials for external clients~%  cadr <command> --help          Show help for install/remove/uninstall/update/list/config/auth~%~%~A~%"
     (bold "cadr")
     (bold "Usage:")
     (bold "Commands:")
     (bold "Options:"))
    (dolist
        (line
         '("  --provider <name>              Provider name (default: google)"
           "  --model <pattern>              Model pattern or ID (supports \"provider/id\" and optional \":<thinking>\")"
           "  --api-key <key>                API key (defaults to env vars)"
           "  --system-prompt <text>         System prompt (default: coding assistant prompt)"
           "  --append-system-prompt <text>  Append text or file contents to the system prompt (can be used multiple times)"
           "  --mode <mode>                  Output mode: text (default), json, or rpc"
           "  --print, -p                    Non-interactive mode: process prompt and exit"
           "  --continue, -c                 Continue previous session"
           "  --resume, -r                   Select a session to resume"
           "  --session <path|id>            Use specific session file or partial UUID"
           "  --session-id <id>              Use exact project session ID, creating it if missing"
           "  --fork <path|id>               Fork specific session file or partial UUID into a new session"
           "  --session-dir <dir>            Directory for session storage and lookup"
           "  --no-session                   Don't save session (ephemeral)"
           "  --name, -n <name>              Set session display name"
           "  --models <patterns>            Comma-separated model patterns for Ctrl+P cycling"
           "                                 Supports globs (anthropic/*, *sonnet*) and fuzzy matching"
           "  --no-tools, -nt                Disable all tools by default (built-in and extension)"
           "  --no-builtin-tools, -nbt       Disable built-in tools by default but keep extension/custom tools enabled"
           "  --tools, -t <tools>            Comma-separated allowlist of tool names to enable"
           "                                 Applies to built-in, extension, and custom tools"
           "  --exclude-tools, -xt <tools>   Comma-separated denylist of tool names to disable"
           "                                 Applies to built-in, extension, and custom tools"
           "  --thinking <level>             Set thinking level: off, minimal, low, medium, high, xhigh, max"
           "  --extension, -e <path>         Load an extension file (can be used multiple times)"
           "  --no-extensions, -ne           Disable extension discovery (explicit -e paths still work)"
           "  --skill <path>                 Load a skill file or directory (can be used multiple times)"
           "  --no-skills, -ns               Disable skills discovery and loading"
           "  --prompt-template <path>       Load a prompt template file or directory (can be used multiple times)"
           "  --no-prompt-templates, -np     Disable prompt template discovery and loading"
           "  --theme <path>                 Load a theme file or directory (can be used multiple times)"
           "  --no-themes                    Disable theme discovery and loading"
           "  --no-context-files, -nc        Disable AGENTS.md and CLAUDE.md discovery and loading"
           "  --export <file>                Export session file to HTML and exit"
           "  --list-models [search]         List available models (with optional fuzzy search)"
           "  --verbose                      Force verbose startup (overrides quietStartup setting)"
           "  --alt                          Use the alternate-screen TUI in interactive mode"
           "  --approve, -a                  Trust project-local files for this run"
           "  --no-approve, -na              Ignore project-local files for this run"
           "  --offline                      Disable startup network operations (same as CADR_OFFLINE=1)"
           "  --help, -h                     Show this help"
           "  --version, -v                  Show version number"))
      (format stream "~A~%" line))
    (format
     stream
     "~%Extensions can register additional flags (e.g., --plan from plan-mode extension).")
    (when extension-flags
      (format stream "~%~A~%" (bold "Extension CLI Flags:"))
      (dolist (flag extension-flags)
        (let* ((name (getf flag :name))
               (value
                 (if (eq (getf flag :type) :string)
                     " <value>"
                     ""))
               (description
                 (or (getf flag :description)
                     (format nil "Registered by ~A"
                             (getf flag :extension-path))))
               (label
                 (format nil "  --~A~A" name value)))
          (format stream "~A~A~%"
                  (cli-pad-right label 30)
                  description)))
      (format stream "~%"))
    (format
     stream
     "~%~A~%  # Print a provider API key for an external client~%  cadr auth print-api-key --provider openai --model gpt-5.5~%~%  # Print an OAuth bearer token for an external client (refreshes if expired)~%  cadr auth print-bearer-token --provider openai-codex --model gpt-5.5~%~%  # Interactive mode~%  cadr~%~%  # Interactive mode with initial prompt~%  cadr \"List all .ts files in src/\"~%~%  # Include files in initial message~%  cadr @prompt.md @image.png \"What color is the sky?\"~%~%  # Non-interactive mode (process and exit)~%  cadr -p \"List all .ts files in src/\"~%~%  # Multiple messages (interactive)~%  cadr \"Read package.json\" \"What dependencies do we have?\"~%~%  # Continue previous session~%  cadr --continue \"What did we discuss?\"~%~%  # Start a named session~%  cadr --name \"Refactor auth module\"~%~%  # Use different model~%  cadr --provider openai --model gpt-4o-mini \"Help me refactor this code\"~%~%  # Use model with provider prefix (no --provider needed)~%  cadr --model openai/gpt-4o \"Help me refactor this code\"~%~%  # Use model with thinking level shorthand~%  cadr --model sonnet:high \"Solve this complex problem\"~%~%  # Limit model cycling to specific models~%  cadr --models claude-sonnet,claude-haiku,gpt-4o~%~%  # Limit to a specific provider with glob pattern~%  cadr --models \"github-copilot/*\"~%~%  # Cycle models with fixed thinking levels~%  cadr --models sonnet:high,haiku:low~%~%  # Start with a specific thinking level~%  cadr --thinking high \"Solve this complex problem\"~%~%  # Read-only mode (no file modifications possible)~%  cadr --tools read,grep,find,ls -p \"Review the code in src/\"~%~%  # Disable one tool while keeping the rest available~%  cadr --exclude-tools ask_question~%~%  # Export a session file to HTML~%  cadr --export ~~/.cadr/agent/sessions/--path--/session.jsonl~%  cadr --export session.jsonl output.html~%~%"
     (bold "Examples:"))
    (format stream "~A~%" (bold "Environment Variables:"))
    (dolist
        (line
         '("  ANTHROPIC_AUTH_TOKEN             - Anthropic bearer auth token"
           "  ANTHROPIC_API_KEY                - Anthropic Claude API key"
           "  ANTHROPIC_OAUTH_TOKEN            - Anthropic OAuth token (alternative to API key)"
           "  ANT_LING_API_KEY                 - Ant Ling API key"
           "  OPENAI_API_KEY                   - OpenAI GPT API key"
           "  AZURE_OPENAI_API_KEY             - Azure OpenAI API key"
           "  AZURE_OPENAI_BASE_URL            - Azure OpenAI/Cognitive Services base URL (e.g. https://{resource}.openai.azure.com)"
           "  AZURE_OPENAI_RESOURCE_NAME       - Azure OpenAI resource name (alternative to base URL)"
           "  AZURE_OPENAI_API_VERSION         - Azure OpenAI API version (default: v1)"
           "  AZURE_OPENAI_DEPLOYMENT_NAME_MAP - Azure OpenAI model=deployment map (comma-separated)"
           "  DEEPSEEK_API_KEY                 - DeepSeek API key"
           "  NVIDIA_API_KEY                   - NVIDIA NIM API key"
           "  GEMINI_API_KEY                   - Google Gemini API key"
           "  GROQ_API_KEY                     - Groq API key"
           "  CEREBRAS_API_KEY                 - Cerebras API key"
           "  XAI_API_KEY                      - xAI Grok API key"
           "  FIREWORKS_API_KEY                - Fireworks API key"
           "  TOGETHER_API_KEY                 - Together AI API key"
           "  OPENROUTER_API_KEY               - OpenRouter API key"
           "  AI_GATEWAY_API_KEY               - Vercel AI Gateway API key"
           "  ZAI_API_KEY                      - ZAI Coding Plan API key (Global)"
           "  ZAI_CODING_CN_API_KEY            - ZAI Coding Plan API key (China)"
           "  MISTRAL_API_KEY                  - Mistral API key"
           "  MINIMAX_API_KEY                  - MiniMax API key"
           "  MOONSHOT_API_KEY                 - Moonshot AI API key"
           "  OPENCODE_API_KEY                 - OpenCode Zen/OpenCode Go API key"
           "  KIMI_API_KEY                     - Kimi For Coding API key"
           "  CLOUDFLARE_API_KEY               - Cloudflare API token (Workers AI and AI Gateway)"
           "  CLOUDFLARE_ACCOUNT_ID            - Cloudflare account id (required for both)"
           "  CLOUDFLARE_GATEWAY_ID            - Cloudflare AI Gateway slug (required for AI Gateway)"
           "  QWEN_TOKEN_PLAN_API_KEY          - Qwen Token Plan API key (international region)"
           "  QWEN_TOKEN_PLAN_CN_API_KEY       - Qwen Token Plan API key (China region)"
           "  XIAOMI_API_KEY                   - Xiaomi MiMo API key (api.xiaomimimo.com billing)"
           "  XIAOMI_TOKEN_PLAN_CN_API_KEY     - Xiaomi MiMo Token Plan API key (China region)"
           "  XIAOMI_TOKEN_PLAN_AMS_API_KEY    - Xiaomi MiMo Token Plan API key (Amsterdam region)"
           "  XIAOMI_TOKEN_PLAN_SGP_API_KEY    - Xiaomi MiMo Token Plan API key (Singapore region)"
           "  AWS_PROFILE                      - AWS profile for Amazon Bedrock"
           "  AWS_ACCESS_KEY_ID                - AWS access key for Amazon Bedrock"
           "  AWS_SECRET_ACCESS_KEY            - AWS secret key for Amazon Bedrock"
           "  AWS_BEARER_TOKEN_BEDROCK         - Bedrock API key (bearer token)"
           "  AWS_REGION                       - AWS region for Amazon Bedrock (e.g., us-east-1)"))
      (format stream "~A~%" line))
    (dolist
        (pair
         '(("CADR_CODING_AGENT_DIR" . "Config directory (default: ~/.cadr/agent)")
           ("CADR_CODING_AGENT_SESSION_DIR" . "Session storage directory (overridden by --session-dir)")
           ("CADR_PACKAGE_DIR" . "Override package directory (for Nix/Guix store paths)")
           ("CADR_OFFLINE" . "Disable startup network operations when set to 1/true/yes")
           ("CADR_TELEMETRY" . "Override install telemetry when set to 1/true/yes or 0/false/no")
           ("CADR_SHARE_VIEWER_URL" . "Base URL for /share command (default: https://cadr.dev/session/)")))
      (format stream "  ~A - ~A~%"
              (cli-pad-right (car pair) 32)
              (cdr pair)))
    (format
     stream
     "~%~A~%  read   - Read file contents~%  bash   - Execute bash commands~%  edit   - Edit files with find/replace~%  write  - Write files (creates/overwrites)~%  grep   - Search file contents (read-only, off by default)~%  find   - Find files by glob pattern (read-only, off by default)~%  ls     - List directory contents (read-only, off by default)~%~%"
     (bold "Built-in Tool Names:")))
  (finish-output stream))

(defun resolve-cli-mode
    (arguments input-terminal-p output-terminal-p)
  (or
   (cli-arguments-mode arguments)
   (and
    (cli-arguments-print-p arguments)
    :text)
   (and
    (cli-arguments-no-tui-p arguments)
    :repl)
   (and
    (or
     (not input-terminal-p)
     (not output-terminal-p))
    :text)
   :tui))

(defun build-cli-print-prompts
    (arguments stdin-content
     &key file-text file-images)
  (let* ((messages
           (copy-list
            (cli-arguments-messages arguments)))
         (first-message (pop messages))
         (text
           (format
            nil "~{~A~}"
            (remove nil
                    (list stdin-content
                          file-text
                          first-message))))
         (initial
           (cond
             (file-images
              (cadr-ai:make-user-message
               :content
               (append
                (when (plusp (length text))
                  (list
                   (cadr-ai:make-text-content
                    :text text)))
                file-images)))
             ((plusp (length text))
              text)
             (t nil))))
    (values initial messages)))
