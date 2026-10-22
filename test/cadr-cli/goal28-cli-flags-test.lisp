(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(test goal28-cli-flags-reach-existing-parser
  (let ((arguments
          (cadr-cli::parse-cli-arguments
           '("--provider" "openai"
             "--model" "gpt-5.5"
             "--api-key" "secret"
             "--system-prompt" "system"
             "--append-system-prompt" "extra"
             "--thinking" "high"
             "--mode" "text"
             "--name" "named"
             "--print"
             "--continue"
             "--resume"
             "--no-session"
             "--session" "session.jsonl"
             "--session-id" "sid"
             "--fork" "entry"
             "--session-dir" "sessions"
             "--models" "openai/a,anthropic/b"
             "--tools" "read,bash"
             "--exclude-tools" "write"
             "--no-tools"
             "--no-builtin-tools"
             "--no-mcp"
             "--extension" "one.lisp"
             "--no-extensions"
             "--export" "out.html"
             "--skill" "skill"
             "--no-skills"
             "--prompt-template" "prompt"
             "--no-prompt-templates"
             "--theme" "theme.json"
             "--use-theme" "dark"
             "--no-themes"
             "--no-context-files"
             "--list-models" "gpt"
             "--offline"
             "--verbose"
             "--approve"
             "--tui-mode" "fullscreen"
             "--help"
             "--version"))))
    (is (string= "openai" (cadr-cli::cli-arguments-provider arguments)))
    (is (string= "gpt-5.5" (cadr-cli::cli-arguments-model arguments)))
    (is (string= "secret" (cadr-cli::cli-arguments-api-key arguments)))
    (is (string= "system" (cadr-cli::cli-arguments-system-prompt arguments)))
    (is (equal '("extra") (cadr-cli::cli-arguments-append-system-prompts arguments)))
    (is (eq :high (cadr-cli::cli-arguments-thinking arguments)))
    (is (eq :text (cadr-cli::cli-arguments-mode arguments)))
    (is (string= "named" (cadr-cli::cli-arguments-name arguments)))
    (is (cadr-cli::cli-arguments-print-p arguments))
    (is (cadr-cli::cli-arguments-continue-p arguments))
    (is (cadr-cli::cli-arguments-resume-p arguments))
    (is (cadr-cli::cli-arguments-no-session-p arguments))
    (is (string= "session.jsonl" (cadr-cli::cli-arguments-session arguments)))
    (is (string= "sid" (cadr-cli::cli-arguments-session-id arguments)))
    (is (string= "entry" (cadr-cli::cli-arguments-fork arguments)))
    (is (string= "sessions" (cadr-cli::cli-arguments-session-directory arguments)))
    (is (equal '("openai/a" "anthropic/b") (cadr-cli::cli-arguments-models arguments)))
    (is (equal '("read" "bash") (cadr-cli::cli-arguments-tools arguments)))
    (is (equal '("write") (cadr-cli::cli-arguments-exclude-tools arguments)))
    (is (cadr-cli::cli-arguments-no-tools-p arguments))
    (is (cadr-cli::cli-arguments-no-builtin-tools-p arguments))
    (is (cadr-cli::cli-arguments-no-mcp-p arguments))
    (is (equal '("one.lisp") (cadr-cli::cli-arguments-extensions arguments)))
    (is (cadr-cli::cli-arguments-no-extensions-p arguments))
    (is (string= "out.html" (cadr-cli::cli-arguments-export arguments)))
    (is (equal '("skill") (cadr-cli::cli-arguments-skills arguments)))
    (is (cadr-cli::cli-arguments-no-skills-p arguments))
    (is (equal '("prompt") (cadr-cli::cli-arguments-prompt-templates arguments)))
    (is (cadr-cli::cli-arguments-no-prompt-templates-p arguments))
    (is (equal '("theme.json") (cadr-cli::cli-arguments-themes arguments)))
    (is (string= "dark" (cadr-cli::cli-arguments-use-theme arguments)))
    (is (cadr-cli::cli-arguments-no-themes-p arguments))
    (is (cadr-cli::cli-arguments-no-context-files-p arguments))
    (is (string= "gpt" (cadr-cli::cli-arguments-list-models arguments)))
    (is (cadr-cli::cli-arguments-offline-p arguments))
    (is (cadr-cli::cli-arguments-verbose-p arguments))
    (is (eq t (cadr-cli::cli-arguments-project-trust-override arguments)))
    (is (cadr-cli::cli-arguments-project-trust-override-supplied-p arguments))
    (is (eq :fullscreen (cadr-cli::cli-arguments-tui-mode arguments)))
    (is (cadr-cli::cli-arguments-help-p arguments))
    (is (cadr-cli::cli-arguments-version-p arguments)))
  (let ((arguments
          (cadr-cli::parse-cli-arguments
           '("--no-approve"))))
    (is (null (cadr-cli::cli-arguments-project-trust-override arguments)))
    (is (cadr-cli::cli-arguments-project-trust-override-supplied-p arguments)))
  (let ((arguments
          (cadr-cli::parse-cli-arguments '("--no-mcp"))))
    (is (cadr-cli::cli-arguments-no-mcp-p arguments))))

(test goal28-no-mcp-disables-builtin-mcp-factory
  ;; pi@4a080252f main.ts disabledBuiltinExtensions: ["mcp"]
  (with-test-directory (temporary)
    (let* ((mcp-factory
             (list :name "mcp" :factory (lambda (&rest _) nil) :hidden-p t))
           (manager
             (cadr-cli::make-cli-extension-manager
              :cwd temporary
              :output (make-broadcast-stream)
              :extension-factories (list mcp-factory)
              :disabled-builtin-extensions '("mcp")
              :no-discovery-p t)))
      (is (null
           (find "mcp"
                 (cadr-cli::cli-extension-manager-extension-factories
                  manager)
                 :key (lambda (entry) (getf entry :name))
                 :test #'string-equal)))
      (is (find "llama.cpp"
                (cadr-cli::cli-extension-manager-extension-factories
                 manager)
                :key (lambda (entry) (getf entry :name))
                :test #'string-equal)))))

(test provider-flag-requires-a-model
  (let* ((errors (make-string-output-stream))
         (help (make-string-output-stream))
         (status
           (let ((*error-output* errors)
                 (*standard-output* (make-broadcast-stream)))
             (cadr-cli:main '("--provider" "openai"))))
         (help-status
           (let ((*error-output* (make-broadcast-stream))
                 (*standard-output* help))
             (cadr-cli:main '("--provider" "openai" "--help")))))
    (is (= 1 status))
    (is (search
         "Error: --provider requires --model (for example: --provider openai --model <pattern>)"
         (get-output-stream-string errors)))
    (is (= 0 help-status))
    (is (search
         "Provider to search for --model (requires --model)"
         (get-output-stream-string help))))
  (is (equal
       '("gpt-4o" "claude-sonnet")
       (cadr-cli::cli-arguments-models
        (cadr-cli::parse-cli-arguments
         '("--models" "gpt-4o, ,claude-sonnet,"))))))
