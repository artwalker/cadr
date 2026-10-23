(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(test full-reference-cli-option-contract-is-parsed
  (let ((arguments
          (cadr-cli::parse-cli-arguments
           '("--provider" "openai"
             "--model" "gpt-5.5"
             "--api-key" "secret"
             "--system-prompt" "system"
             "--append-system-prompt" "one"
             "--append-system-prompt" "two"
             "--thinking" "xhigh"
             "-c" "-r"
             "--mode" "json"
             "-n" "named"
             "--no-session"
             "--session" "session.jsonl"
             "--session-id" "sid"
             "--fork" "entry"
             "--session-dir" "sessions"
             "--models" "openai/a, anthropic/b"
             "-t" "read,bash"
             "-xt" "write"
             "-nt" "-nbt"
             "-e" "one.lisp"
             "--extension" "two.lisp"
             "-ne" "-p"
             "--export" "out.html"
             "--skill" "skill"
             "-ns"
             "--prompt-template" "prompt"
             "-np"
             "--theme" "theme.json"
             "--no-themes"
             "-nc"
             "--list-models" "gpt"
             "--offline"
             "--verbose"
             "-a"
             "@README.md"
             "hello"
             "--extension-opt=value"))))
    (is (string= "openai"
                 (cadr-cli::cli-arguments-provider arguments)))
    (is (string= "secret"
                 (cadr-cli::cli-arguments-api-key arguments)))
    (is (equal '("one" "two")
               (cadr-cli::cli-arguments-append-system-prompts
                arguments)))
    (is (eq :xhigh
            (cadr-cli::cli-arguments-thinking arguments)))
    (is (cadr-cli::cli-arguments-continue-p arguments))
    (is (cadr-cli::cli-arguments-resume-p arguments))
    (is (cadr-cli::cli-arguments-no-session-p arguments))
    (is (equal '("openai/a" "anthropic/b")
               (cadr-cli::cli-arguments-models arguments)))
    (is (equal '("read" "bash")
               (cadr-cli::cli-arguments-tools arguments)))
    (is (equal '("write")
               (cadr-cli::cli-arguments-exclude-tools arguments)))
    (is (cadr-cli::cli-arguments-no-tools-p arguments))
    (is (cadr-cli::cli-arguments-no-builtin-tools-p arguments))
    (is (equal '("one.lisp" "two.lisp")
               (cadr-cli::cli-arguments-extensions arguments)))
    (is (cadr-cli::cli-arguments-no-extensions-p arguments))
    (is (equal '("README.md")
               (cadr-cli::cli-arguments-file-arguments arguments)))
    (is (equal '("hello")
               (cadr-cli::cli-arguments-messages arguments)))
    (is (string=
         "value"
         (gethash
          "extension-opt"
          (cadr-cli::cli-arguments-unknown-flags
           arguments))))
    (is (null
         (cadr-cli::cli-arguments-diagnostics arguments)))))

(test goal60-cli-help-matches-v140-print-help
  ;; v1.4.0 packages/coding-agent/src/cli/args.ts printHelp, after the
  ;; cadr identity substitution. cadr ai stays; it is the merged entry.
  (let ((usage
          (with-output-to-string (stream)
            (cadr-cli::print-cli-usage stream))))
    (is (search "cadr [options] [--] [@files...] [messages...]" usage))
    (is (search
         "  --                             End option parsing; treat remaining arguments as messages/files"
         usage))
    (is (search
         "Comma-separated allowlist of tool names or patterns (*) to enable"
         usage))
    (is (search
         "Keeps MCP tools unless an entry starts with mcp__"
         usage))
    (is (search
         "Only +name/-name entries add to or remove from the defaults"
         usage))
    (is (search
         "Comma-separated denylist of tool names or patterns (*) to disable"
         usage))
    (is (search "Applies to all tools, MCP tools included" usage))
    (is (search "cadr --tools +codemode" usage))
    (is (search "cadr --tools read,bash,codemode,'mcp__radius__*'" usage))
    (is (search "cadr -p -- \"- Summarize these points\"" usage))
    (is (search "powershell - Execute PowerShell commands on Windows" usage))
    (is (search "BASETEN_API_KEY                  - Baseten API key" usage))
    (is (search "cadr ai <command>" usage))
    (is (null (search "cadr --tools +grep" usage)))
    (is (null (search "Or only +name/-name entries to change the defaults" usage)))
    (is (null (search "Applies to built-in, extension, and custom tools" usage)))
    (let ((no-extensions (search "--no-extensions, -ne" usage))
          (no-mcp (search "--no-mcp" usage))
          (skill (search "--skill <path>" usage)))
      (is (and no-extensions no-mcp skill
               (< no-extensions no-mcp skill))))))

(test goal60-double-dash-ends-option-parsing
  ;; v1.4.0 packages/coding-agent/src/cli/args.ts parseArgs: arg === "--"
  ;; stops option parsing. @tokens become files; other tokens, including
  ;; ones that start with a dash, become messages.
  (let ((summarize
          (cadr-cli::parse-cli-arguments
           '("-p" "--" "- Summarize these points"))))
    (is-true (cadr-cli::cli-arguments-print-p summarize))
    (is (equal '("- Summarize these points")
               (cadr-cli::cli-arguments-messages summarize)))
    (is (null (cadr-cli::cli-arguments-file-arguments summarize)))
    (is (null (cadr-cli::cli-arguments-diagnostics summarize)))
    (is (zerop
         (hash-table-count
          (cadr-cli::cli-arguments-unknown-flags summarize)))))
  (let ((mixed
          (cadr-cli::parse-cli-arguments
           '("hello" "--" "@notes.md" "--help" "-x"))))
    (is (equal '("hello" "--help" "-x")
               (cadr-cli::cli-arguments-messages mixed)))
    (is (equal '("notes.md")
               (cadr-cli::cli-arguments-file-arguments mixed)))
    (is (null (cadr-cli::cli-arguments-help-p mixed)))
    (is (zerop
         (hash-table-count
          (cadr-cli::cli-arguments-unknown-flags mixed)))))
  (let ((only (cadr-cli::parse-cli-arguments '("--"))))
    (is (null (cadr-cli::cli-arguments-messages only)))
    (is (null (cadr-cli::cli-arguments-file-arguments only)))))

(test print-cli-usage-plain-bytes-match-shipped-literal
  (let ((stream (make-string-output-stream)))
    (cadr-cli::print-cli-usage stream)
    (let* ((got (get-output-stream-string stream))
           (path
             (merge-pathnames
              "test/fixtures/cli-usage-plain.txt"
              (asdf:system-source-directory "cadr-cli")))
           (expected (uiop:read-file-string path)))
      (is (= (length expected) (length got)))
      (is (string= expected got)))))

(test paired-path-parse-argv-fixture-drives-shipped-parser
  (let* ((path
           (merge-pathnames
            "test/fixtures/goal20-paired-paths/cli-argv.json"
            (asdf:system-source-directory "cadr-cli")))
         (argv
           (coerce
            (cadr-ai::json-get
             (cadr-ai::parse-json (uiop:read-file-string path))
             "parse")
            'list))
         (arguments
           (cadr-cli::parse-cli-arguments argv)))
    (is (string=
         "goal20faux"
         (cadr-cli::cli-arguments-provider arguments)))
    (is (string=
         "goal20-paired-3"
         (cadr-cli::cli-arguments-model arguments)))
    (is (eq :medium
            (cadr-cli::cli-arguments-thinking arguments)))
    (is (equal
         '("be terse" "cite files")
         (cadr-cli::cli-arguments-append-system-prompts arguments)))
    (is (equal
         '("read" "bash" "edit")
         (cadr-cli::cli-arguments-tools arguments)))
    (is (equal
         '("web_search" "fetch")
         (cadr-cli::cli-arguments-exclude-tools arguments)))
    (is (string=
         "/goal20-paired-paths/sessions"
         (cadr-cli::cli-arguments-session-directory arguments)))
    (is (eq :json (cadr-cli::cli-arguments-mode arguments)))
    (is (cadr-cli::cli-arguments-no-themes-p arguments))
    (is (cadr-cli::cli-arguments-no-context-files-p arguments))
    (is (cadr-cli::cli-arguments-verbose-p arguments))
    (is (string=
         "goal20"
         (cadr-cli::cli-arguments-list-models arguments)))
    (is (equal
         '("explain the paired path benchmark")
         (cadr-cli::cli-arguments-messages arguments)))
    (is (equal
         '("docs/performance.md")
         (cadr-cli::cli-arguments-file-arguments arguments)))))

(test reference-cli-shorthands-diagnostics-and-print-frontmatter
  (let ((arguments
          (cadr-cli::parse-cli-arguments
           (list "-v" "-h" "-na" "-p"
                 (format nil "---~%title: hi~%---~%body")
                 "--bad" "value" "-z"))))
    (is (cadr-cli::cli-arguments-version-p arguments))
    (is (cadr-cli::cli-arguments-help-p arguments))
    (is
     (cadr-cli::cli-arguments-project-trust-override-supplied-p
      arguments))
    (is (not
         (cadr-cli::cli-arguments-project-trust-override
          arguments)))
    (is (= 1
           (length
            (cadr-cli::cli-arguments-messages arguments))))
    (is (string= "value"
                 (gethash
                  "bad"
                  (cadr-cli::cli-arguments-unknown-flags
                   arguments))))
    (is (equal
         '((:type :error
            :message "Unknown option: -z"))
         (cadr-cli::cli-arguments-diagnostics arguments)))))

(test session-flags-and-file-arguments-drive-runtime-state
  (with-test-directory (root)
    (let* ((sessions
             (merge-pathnames "sessions/" root))
           (cwd
             (merge-pathnames "project/" root))
           (_cwd-ready
             (ensure-directories-exist
              (merge-pathnames "anchor" cwd)))
           (session
             (cadr-agent:create-session
              :directory sessions
              :cwd cwd
              :id "exact"))
           (text
             (merge-pathnames "input.txt" cwd)))
      (declare (ignore _cwd-ready))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-assistant-message
        :content
        (list
         (cadr-ai:make-text-content
          :text "persist"))
        :api :openai-responses
        :provider :openai
        :model "mock"
        :stop-reason :stop))
      (write-text text "file body")
      (is (null
           (cadr-cli::resolve-cli-session
            :no-session-p t
            :session-id "ephemeral"
            :directory sessions
            :cwd cwd)))
      (is (string=
           "exact"
           (cadr-agent:session-id
            (cadr-cli::resolve-cli-session
             :session-id "exact"
             :directory sessions
             :cwd cwd))))
      (is (string=
           "fresh"
           (cadr-agent:session-id
            (cadr-cli::resolve-cli-session
             :session-id "fresh"
             :directory sessions
             :cwd cwd
             :output
             (make-string-output-stream)))))
      (is (string=
           "exact"
           (cadr-agent:session-id
            (cadr-cli::resolve-cli-session
             :session-path
             (namestring
              (cadr-agent:session-path
               session))
             :directory sessions
             :cwd cwd))))
      (signals cadr-ai:configuration-error
        (cadr-cli::resolve-cli-session
         :continue-p t
         :session-id "bad"
         :directory sessions
         :cwd cwd))
      (signals cadr-ai:configuration-error
        (cadr-cli::resolve-cli-session
         :session-id "../escape"
         :directory sessions
         :cwd cwd))
      (multiple-value-bind (file-text images)
          (cadr-cli::process-cli-file-arguments
           '("input.txt") cwd)
        (is (search "file body" file-text))
        (is (null images))
        (multiple-value-bind (initial remaining)
            (cadr-cli::build-cli-print-prompts
             (cadr-cli::parse-cli-arguments
              '("question" "follow-up"))
             "stdin"
             :file-text file-text)
          (is (search
               "stdin<file"
               initial))
          (is (search
               "file body"
               initial))
          (is (uiop:string-suffix-p
               initial "question"))
          (is (equal
               '("follow-up")
               remaining)))))))

(test fork-accepts-session-id-prefix-and-prefers-current-project
  (with-test-directory (root)
    (let* ((sessions
             (merge-pathnames "sessions/" root))
           (cwd
             (merge-pathnames "project/" root))
           (other-cwd
             (merge-pathnames "other/" root))
           (_cwd-ready
             (ensure-directories-exist
              (merge-pathnames "anchor" cwd)))
           (_other-ready
             (ensure-directories-exist
              (merge-pathnames "anchor" other-cwd)))
           (local
             (cadr-agent:create-session
              :directory sessions
              :cwd cwd
              :id "abcdef-local"))
           (global
             (cadr-agent:create-session
              :directory sessions
              :cwd other-cwd
              :id "abcdef-global")))
      (declare (ignore _cwd-ready _other-ready))
      (cadr-agent:session-append-message
       local
       (cadr-ai:make-user-message
        :content "local"))
      (cadr-agent:session-append-message
       local
       (cadr-ai:make-assistant-message
        :content
        (list
         (cadr-ai:make-text-content
          :text "local reply"))
        :api :openai-responses
        :provider :openai
        :model "mock"
        :stop-reason :stop))
      (cadr-agent:session-append-message
       global
       (cadr-ai:make-user-message
        :content "global"))
      (cadr-agent:session-append-message
       global
       (cadr-ai:make-assistant-message
        :content
        (list
         (cadr-ai:make-text-content
          :text "global reply"))
        :api :openai-responses
        :provider :openai
        :model "mock"
        :stop-reason :stop))
      (let ((fork
              (cadr-cli::resolve-cli-session
               :fork-source "abcdef"
               :directory sessions
               :cwd cwd)))
        (is
         (string=
          "abcdef-local"
          (cadr-agent:session-parent-session
           fork)))
        (is
         (string=
          "local"
          (cadr-ai:user-message-content
           (first
            (cadr-agent:session-messages
             fork)))))))))
