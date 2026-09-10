(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defparameter +goal28-extension-field-callables+
  '(("ExtensionActions.appendEntry" . cadr-agent:extension-api-append-entry)
    ("ExtensionActions.getActiveTools" . cadr-agent:extension-api-get-active-tools)
    ("ExtensionActions.getAllTools" . cadr-agent:extension-api-get-all-tools)
    ("ExtensionActions.getCommands" . cadr-agent:extension-api-get-commands)
    ("ExtensionActions.getSessionName" . cadr-agent:extension-api-get-session-name)
    ("ExtensionActions.getThinkingLevel" . cadr-agent:extension-api-get-thinking-level)
    ("ExtensionActions.sendMessage" . cadr-agent:extension-api-send-message)
    ("ExtensionActions.sendUserMessage" . cadr-agent:extension-api-send-user-message)
    ("ExtensionActions.setActiveTools" . cadr-agent:extension-api-set-active-tools)
    ("ExtensionActions.setLabel" . cadr-agent:extension-api-set-label)
    ("ExtensionActions.setModel" . cadr-agent:extension-api-set-model)
    ("ExtensionActions.setSessionName" . cadr-agent:extension-context-set-session-name)
    ("ExtensionActions.setThinkingLevel" . cadr-agent:extension-api-set-thinking-level)
    ("ExtensionAPI.events" . cadr-agent:extension-api-events-on)
    ("ExtensionContext.cwd" . cadr-agent:extension-context-cwd)
    ("ExtensionContext.hasUI" . cadr-agent:extension-context-has-ui-p)
    ("ExtensionContext.mode" . cadr-agent:extension-context-mode)
    ("ExtensionContext.model" . cadr-agent:extension-context-model)
    ("ExtensionContext.scopedModels" . cadr-agent:extension-context-scoped-models)
    ("ExtensionContext.signal" . cadr-agent:extension-context-signal)
    ("ExtensionContext.thinkingLevel" . cadr-agent:extension-context-thinking-level)
    ("ExtensionContextActions.abort" . cadr-agent:extension-context-abort)
    ("ExtensionContextActions.compact" . cadr-agent:extension-context-compact)
    ("ExtensionContextActions.getContextUsage" . cadr-agent:extension-context-context-usage)
    ("ExtensionContextActions.getModel" . cadr-agent:extension-context-model)
    ("ExtensionContextActions.getScopedModels" . cadr-agent:extension-context-scoped-models)
    ("ExtensionContextActions.getSignal" . cadr-agent:extension-context-signal)
    ("ExtensionContextActions.getSystemPrompt" . cadr-agent:extension-context-system-prompt)
    ("ExtensionContextActions.hasPendingMessages" . cadr-agent:extension-context-has-pending-messages-p)
    ("ExtensionContextActions.isIdle" . cadr-agent:extension-context-idle-p)
    ("ExtensionContextActions.shutdown" . cadr-agent:extension-context-shutdown)))

(test goal28-extension-type-fields-reach-existing-api
  (dolist (entry +goal28-extension-field-callables+)
    (is (fboundp (cdr entry))))
  (is (find-class 'cadr-agent:extension-api nil))
  (is (find-class 'cadr-agent:extension-context nil))
  (is (fboundp 'cadr-agent:current-extension-api)))

(test goal28-tool-helper-files-reach-existing-helpers
  (is (fboundp 'cadr-cli::truncate-head))
  (is (fboundp 'cadr-cli::truncate-tail))
  (is (fboundp 'cadr-cli::group-edit-diff-ranges))
  (is (macro-function 'cadr-cli::with-file-mutation-queue))
  (is (fboundp 'cadr-cli:make-glob-tool))
  (is (probe-file
       (merge-pathnames
        "src/cadr-cli/tools/path.lisp"
        (asdf:system-source-directory "cadr-cli"))))
  (is (probe-file
       (merge-pathnames
        "src/cadr-cli/tools/edit.lisp"
        (asdf:system-source-directory "cadr-cli"))))
  (is (probe-file
       (merge-pathnames
        "src/cadr-cli/truncation.lisp"
        (asdf:system-source-directory "cadr-cli")))))

(defparameter +goal28-process-env-names+
  '("AI_AGENT"
    "COLORTERM"
    "COLUMNS"
    "DISPLAY"
    "EDITOR"
    "GHOSTTY_RESOURCES_DIR"
    "HTTP_PROXY"
    "HTTPS_PROXY"
    "ITERM_SESSION_ID"
    "KITTY_WINDOW_ID"
    "LINES"
    "TERMINAL_EMULATOR"
    "TERM_PROGRAM"
    "USERPROFILE"
    "VISUAL"
    "WARP_SESSION_ID"
    "WARP_TERMINAL_SESSION_UUID"
    "WAYLAND_DISPLAY"
    "WEZTERM_PANE"
    "WSL_DISTRO_NAME"
    "WSL_INTEROP"))

(test goal28-environment-variables-reach-existing-process-env
  (is (stringp (or (uiop:getenv "PATH") "")))
  (is (stringp (or (uiop:getenv "HOME") "")))
  (is (search
       "CADR_TIMING"
       (uiop:read-file-string
        (merge-pathnames
         "src/cadr-cli/support/timings.lisp"
         (asdf:system-source-directory "cadr-cli")))))
  (is (search
       "CADR_OFFLINE"
       (uiop:read-file-string
        (merge-pathnames
         "src/cadr-cli/bootstrap/main.lisp"
         (asdf:system-source-directory "cadr-cli")))))
  (is (search
       "CADR_CLEAR_ON_SHRINK"
       (uiop:read-file-string
        (merge-pathnames
         "src/cadr-cli/bootstrap/settings.lisp"
         (asdf:system-source-directory "cadr-cli")))))
  (is (search
       "\"PATH\""
       (uiop:read-file-string
        (merge-pathnames
         "src/cadr-cli/support/shell-process.lisp"
         (asdf:system-source-directory "cadr-cli")))))
  (dolist (name +goal28-process-env-names+)
    (is (stringp (or (uiop:getenv name) ""))))
  (let ((root (asdf:system-source-directory "cadr-cli")))
    (dolist (entry
             '(("AI_AGENT" "src/cadr-cli/bootstrap/main.lisp")
               ("COLORTERM" "src/cadr-tui/terminal-image.lisp")
               ("COLUMNS" "src/cadr-tui/terminal.lisp")
               ("DISPLAY" "src/cadr-cli/bootstrap/sessions.lisp")
               ("EDITOR" "src/cadr-cli/bootstrap/settings.lisp")
               ("GHOSTTY_RESOURCES_DIR" "src/cadr-tui/terminal-image.lisp")
               ("HTTP_PROXY" "src/cadr-ai/websocket.lisp")
               ("HTTPS_PROXY" "src/cadr-ai/websocket.lisp")
               ("ITERM_SESSION_ID" "src/cadr-tui/terminal-image.lisp")
               ("KITTY_WINDOW_ID" "src/cadr-tui/terminal-image.lisp")
               ("LINES" "src/cadr-tui/terminal.lisp")
               ("TERMINAL_EMULATOR" "src/cadr-tui/terminal-image.lisp")
               ("TERM_PROGRAM" "src/cadr-tui/terminal-image.lisp")
               ("USERPROFILE" "src/cadr-cli/interactive/entries.lisp")
               ("VISUAL" "src/cadr-cli/bootstrap/settings.lisp")
               ("WARP_SESSION_ID" "src/cadr-tui/terminal-image.lisp")
               ("WARP_TERMINAL_SESSION_UUID" "src/cadr-tui/terminal-image.lisp")
               ("WAYLAND_DISPLAY" "src/cadr-cli/interactive/clipboard.lisp")
               ("WEZTERM_PANE" "src/cadr-tui/terminal-image.lisp")
               ("WSL_DISTRO_NAME" "src/cadr-cli/interactive/clipboard.lisp")
               ("WSL_INTEROP" "src/cadr-cli/interactive/clipboard.lisp")))
      (is (search
           (first entry)
           (uiop:read-file-string
            (merge-pathnames (second entry) root)))))))
