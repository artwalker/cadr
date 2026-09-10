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
    (is (cadr-cli::cli-arguments-project-trust-override-supplied-p arguments))))
