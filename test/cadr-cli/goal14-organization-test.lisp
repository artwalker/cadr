(in-package #:cadr-cli/tests)

(in-suite cadr-cli-suite)

(defun goal14-b1-source (root relative)
  (let ((path (merge-pathnames relative root)))
    (and (probe-file path)
         (uiop:read-file-string path))))

(defun goal14-source-block (source start-marker end-marker)
  (let* ((marker-start (and source (search start-marker source)))
         (start
           (and marker-start
                (let ((previous-newline
                        (position #\Newline source :end marker-start :from-end t)))
                  (if previous-newline (1+ previous-newline) 0))))
         (end-start (and start (search end-marker source :start2 start)))
         (line-end (and end-start (position #\Newline source :start end-start))))
    (and start end-start
         (subseq source start (if line-end (1+ line-end) (length source))))))

(defun goal14-sha256 (text)
  (string-downcase
   (format nil "~{~2,'0X~}"
           (coerce
            (cadr-ai::sha256-bytes (cadr-ai::utf8-octets text))
            'list))))

(test goal16-c3-production-environment-names-are-cadr-only
  (let* ((root (asdf:system-source-directory "cadr-cli"))
         (contracts
           '(("src/cadr-ai/providers/bedrock.lisp"
              "CADR_CACHE_RETENTION" "PI_CACHE_RETENTION")
             ("src/cadr-server/config.lisp"
              "CADR_CONFIG_DIR" "PI_CONFIG_DIR")
             ("src/cadr-evals/reporter.lisp"
              "CADR_EVAL_ARTIFACT_DIR" "PI_EVAL_ARTIFACT_DIR")
             ("src/cadr-cli/support/html.lisp"
              "CADR_EXPERIMENTAL" "PI_EXPERIMENTAL")
             ("src/cadr-evals/harness.lisp"
              "CADR_EVAL_MODEL" "PI_MODEL")
             ("src/cadr-cli/tool-manager.lisp"
              "CADR_OFFLINE" "PI_OFFLINE")
             ("src/cadr-evals/harness.lisp"
              "CADR_EVAL_PROVIDER" "PI_PROVIDER")
             ("src/cadr-server/radius.lisp"
              "CADR_RADIUS_SERVER_URL" "PI_RADIUS_SERVER_URL")
             ("src/cadr-server/radius.lisp"
              "CADR_RADIUS_URL" "PI_RADIUS_URL")
             ("src/cadr-server/rpc-process.lisp"
              "CADR_SERVER_CADR_PATH" "PI_SERVER_CADR_PATH")
             ("src/cadr-server/config.lisp"
              "CADR_SERVER_DIR" "PI_SERVER_DIR")
             ("src/cadr-cli/support/changelog-share.lisp"
              "CADR_SHARE_VIEWER_URL" "PI_SHARE_VIEWER_URL")
             ("src/cadr-cli/sdk/cache-version.lisp"
              "CADR_SKIP_VERSION_CHECK" "PI_SKIP_VERSION_CHECK")
             ("src/cadr-cli/support/timings.lisp"
              "CADR_TIMING" "PI_TIMING"))))
    (dolist (contract contracts)
      (destructuring-bind (relative replacement retired) contract
        (let ((source (goal14-b1-source root relative)))
          (is (not (null source)) "missing identity owner ~A" relative)
          (when source
          (is (search replacement source)
              "~A omits ~A" relative replacement)
          (is (not (search retired source))
              "~A still reads retired ~A" relative retired)))))))

(test goal18-install-telemetry-has-no-egress
  ;; Adjudicated intentional difference: the baseline reports installs
  ;; to the pi.dev report-install endpoint
  ;; (interactive-mode.ts:1045-1062); cadr keeps the
  ;; enableInstallTelemetry settings surface but no telemetry egress may
  ;; exist anywhere in the source tree.
  (let* ((root (asdf:system-source-directory "cadr-cli"))
         (files
           (directory
            (merge-pathnames "src/**/*.lisp" root))))
    (is (plusp (length files)) "telemetry gate found no sources")
    (dolist (file files)
      (let ((source (uiop:read-file-string file)))
        (is (not (search "report-install" source))
            "~A references the baseline telemetry endpoint" file)
        (is (not (search "pi.dev/api" source))
            "~A references the baseline telemetry host" file)))))

(test goal16-c4-free-identity-values-are-cadr-owned
  (let* ((root (asdf:system-source-directory "cadr-cli"))
         (contracts
           '(("src/cadr-cli/interactive/clipboard.lisp"
              "cadr-wsl-clip-" "pi-wsl-clip-")
             ("examples/extensions/notify.lisp"
              "example-notify-terminal \"Cadr\"" "example-notify-terminal \"Pi\"")
             ("src/cadr-agent/export-html/template.js"
              "cadr-share:v1:sidebar-width" "pi-share:v1:sidebar-width")
             ("src/cadr-ai/providers/openai.lisp"
              "cadr_tool_load_" "pi_tool_load_")
             ("src/cadr-server/radius.lisp"
              "Radius instance" "Radius Pi")
             ("src/cadr-server/radius.lisp"
              "cadr-radius-instance-" "cadr-radius-pi-"))))
    (dolist (contract contracts)
      (destructuring-bind (relative replacement retired) contract
        (let ((source (goal14-b1-source root relative)))
          (is (not (null source)) "missing identity owner ~A" relative)
          (when source
            (is (search replacement source)
                "~A omits ~A" relative replacement)
            (is (not (search retired source))
                "~A still carries ~A" relative retired)))))))

(test goal14-b1-interactive-leaf-services-have-exact-owners
  (let* ((root (asdf:system-source-directory "cadr-cli"))
         (owners
           '(("src/cadr-cli/interactive/transcript.lisp"
              "(defun render-user-message-lines"
              "(defun render-assistant-message-lines")
             ("src/cadr-cli/interactive/status.lisp"
              "(defstruct (status-log"
              "(defun maybe-anthropic-subscription-warning")
             ("src/cadr-cli/interactive/footer.lisp"
              "(defun format-cwd-for-footer"
              "(defun footer-data-provider-dispose")
             ("src/cadr-cli/interactive/theme.lisp"
              "(defstruct theme-detection"
              "(defun load-theme-summaries")
             ("src/cadr-cli/interactive/images.lisp"
              "(defstruct image-process-result"
              "(defun process-image-file")
             ("src/cadr-cli/interactive/clipboard.lisp"
              "(defun clipboard-command-candidates"
              "(defun read-clipboard-image")
             ("src/cadr-cli/interactive/syntax.lisp"
              "(defparameter +syntax-highlight-languages+"
              "(defun simple-syntax-highlight")
             ("src/cadr-cli/interactive/tool-render-session.lisp"
              "(defstruct (tool-render-session"
              "(defun render-tool-session")))
         (legacy
           (or
            (goal14-b1-source
             root "src/cadr-cli/interactive-services.lisp")
            (format
             nil "~{~A~^~%~}"
             (loop
               for family in
               '("sessions" "tree" "settings" "auth"
                 "models" "trust" "fork")
               collect
               (goal14-b1-source
                root
                (format
                 nil
                 "src/cadr-cli/interactive/selectors/~A.lisp"
                 family)))))))
    (dolist (owner owners)
      (let ((source (goal14-b1-source root (first owner))))
        (is (not (null source)) "missing B1 owner ~A" (first owner))
        (when source
          (dolist (marker (rest owner))
            (is (search marker source)
                "~A does not own ~A" (first owner) marker)))))
    (dolist (marker
             (mapcan (lambda (owner) (copy-list (rest owner))) owners))
      (is (not (search marker legacy))
          "interactive-services still owns ~A" marker))
    (dolist (selector
             '("(defun render-session-selector"
               "(defun render-tree-selector"
               "(defun render-settings-selector"
               "(defun render-oauth-selector"
               "(defun render-model-selector"))
      (is (search selector legacy)
          "B1 moved selector code before selector-frame convergence: ~A"
          selector))))

(test goal14-b1-asdf-loads-leaf-owners-before-selector-consumers
  (let* ((root (asdf:system-source-directory "cadr-cli"))
         (source
           (uiop:read-file-string
            (merge-pathnames "cadr-cli.asd" root)))
         (ordered
           '("(:file \"media\")"
             "(:module \"interactive\""
             "(:file \"footer\")"
             "(:file \"theme\")"
             "(:file \"images\")"
             "(:file \"clipboard\")"
             "(:file \"syntax\")"
             "(:file \"tool-render-session\")"
             "(:module \"selectors\""
             "(:file \"common\")"
             "(:file \"sessions\")"
             "(:file \"tree\")"
             "(:file \"settings\")"
             "(:file \"auth\")"
             "(:file \"models\")"
             "(:file \"trust\")"
             "(:file \"fork\")"
             "(:file \"truncation\")"))
         (positions
           (let ((cursor 0))
             (loop for marker in ordered
                   for position = (search marker source :start2 cursor)
                   collect position
                   when position do (setf cursor (1+ position))))))
    (is (every #'identity positions)
        "cadr-cli.asd omits a B1 load boundary: ~S"
        (loop for marker in ordered
              for position in positions
              unless position collect marker))
    (when (every #'identity positions)
      (is (every #'< positions (rest positions))
          "B1 owner load order is not dependency-safe: ~S" positions))))

(test goal14-b2-selector-frame-owns-shared-selector-decisions
  (let* ((root (asdf:system-source-directory "cadr-cli"))
         (common
           (goal14-b1-source
            root "src/cadr-cli/interactive/selectors/common.lisp"))
         (families
           '("sessions" "tree" "settings" "auth"
             "models" "trust" "fork")))
    (is (not (null common)) "missing B2 selector-frame owner")
    (when common
      (dolist (marker
               '("(defstruct (selector-frame"
                 "(defun render-selector-frame"
                 "(defun selector-frame-visible-slice"
                 "(defun selector-frame-move-index"))
        (is (search marker common)
            "selector-frame owner omits ~A" marker)))
    (dolist (family families)
      (let* ((relative
               (format nil
                       "src/cadr-cli/interactive/selectors/~A.lisp"
                       family))
             (source (goal14-b1-source root relative)))
        (is (not (null source)) "missing B2 selector family ~A" relative)
        (when source
          (is (search "render-selector-frame" source)
              "~A bypasses selector-frame rendering" relative)
          (is (search "selector-frame-move-index" source)
              "~A retains local wrap-navigation policy" relative))))))

(test goal14-b2-selector-frame-wraps-and-centers-independently
  (let ((move (find-symbol "SELECTOR-FRAME-MOVE-INDEX" :cadr-cli))
        (slice (find-symbol "SELECTOR-FRAME-VISIBLE-SLICE" :cadr-cli)))
    (is (and move (fboundp move))
        "selector-frame wrap primitive is unavailable")
    (is (and slice (fboundp slice))
        "selector-frame viewport primitive is unavailable")
    (when (and move (fboundp move))
      (is (= 2 (funcall move 0 3 -1)))
      (is (= 0 (funcall move 2 3 1)))
      (is (= 0 (funcall move 0 0 -1))))
    (when (and slice (fboundp slice))
      (multiple-value-bind (visible start end total)
          (funcall slice '(a b c d e) 3 3)
        (is (equal '(c d e) visible))
        (is (= 2 start))
        (is (= 5 end))
        (is (= 5 total))))))

(test goal14-b4-domain-services-have-exact-owners
  (let* ((root (asdf:system-source-directory "cadr-cli"))
         (owners
           '(("support/model-help.lisp" "(defun get-provider-login-help")
             ("support/event-bus.lisp" "(defstruct (event-bus")
             ("support/timings.lisp" "(defun record-timing")
             ("support/file-watcher.lisp" "(defstruct (file-watcher")
             ("support/paths.lisp" "(defun normalize-path-input")
             ("support/shell-process.lisp" "(defstruct shell-config")
             ("support/threads.lisp" "(defun stop-thread-for-cleanup")
             ("support/atomic-write.lisp" "(defun atomic-write-utf8")
             ("support/changelog-share.lisp" "(defun parse-changelog")
             ("support/html.lisp" "(defun escape-html")
             ("support/resume-version-git.lisp" "(defun format-resume-command")
             ("support/headers.lisp" "(defun merge-header-sources")
             ("support/external-editor.lisp" "(defun edit-in-external-editor")
             ("settings/config-values.lisp" "(defun resolve-config-value")
             ("settings/manager.lisp" "(defstruct (settings-manager")
             ("settings/trust.lisp" "(defstruct (project-trust-store")
             ("models/auth-storage.lisp" "(defstruct (file-auth-storage")
             ("models/store.lisp" "(defstruct (file-models-store")
             ("models/registry.lisp" "(defstruct (model-registry")
             ("models/matching.lisp" "(defun resolve-scoped-models")
             ("models/credential-print.lisp" "(define-condition auth-command-error")
             ("packages/source.lisp" "(defstruct package-source")
             ("packages/settings.lisp" "(defun settings-package-entries")
             ("packages/manifest.lisp" "(defun read-package-pi-manifest")
             ("packages/config-selector.lisp" "(defstruct config-resource-item")
             ("packages/commands.lisp" "(defstruct package-command-options")
             ("extensions/discovery.lisp" "(defstruct extension-source-record")
             ("extensions/loader.lisp" "(defun call-with-extension-output-boundary")
             ("extensions/commands.lisp" "(defun handle-extension-command")
             ("extensions/installer.lisp" "(defun install-extension-package")
             ("sdk/cache-version.lisp" "(defun detect-cache-miss")
             ("sdk/system-prompt.lisp" "(defun build-system-prompt")
             ("sdk/settings-service.lisp" "(defclass sdk-settings-manager")
             ("sdk/resource-service.lisp" "(defclass sdk-resource-loader")
             ("sdk/model-service.lisp" "(defclass sdk-model-runtime")
             ("sdk/session-manager.lisp" "(defclass session-manager")
             ("sdk/agent-session.lisp" "(defclass agent-session")
             ("sdk/session-runtime.lisp" "(defclass agent-session-services")))
         (legacy
           '("core-support.lisp" "utilities.lisp" "settings.lisp"
             "model-services.lisp" "package-manager.lisp" "extensions.lisp"
             "sdk-services.lisp" "sdk.lisp")))
    (dolist (owner owners)
      (let* ((relative
               (format nil "src/cadr-cli/~A" (first owner)))
             (source (goal14-b1-source root relative)))
        (is (not (null source)) "missing B4 owner ~A" relative)
        (when source
          (is (search (second owner) source)
              "~A does not own ~A" relative (second owner)))))
    (dolist (relative legacy)
      (is (not (probe-file (merge-pathnames
                            (format nil "src/cadr-cli/~A" relative)
                            root)))
          "B4 legacy mixed owner remains: ~A" relative))))

(test goal14-b4-converges-sinks-and-javascript-length-before-split
  (let* ((root (asdf:system-source-directory "cadr-cli"))
         (loader
           (goal14-b1-source root "src/cadr-cli/extensions/loader.lisp"))
         (cli-truncation
           (goal14-b1-source root "src/cadr-cli/truncation.lisp"))
         (agent-truncation
           (goal14-b1-source root "src/cadr-agent/truncate.lisp")))
    (is (not (null loader)) "missing B4 extension output owner")
    (when loader
      (dolist (marker
               '("(defun extension-manager-notify"
                 "(defun call-with-extension-output-boundary"
                 "(defun call-with-infrastructure-output-isolated"))
        (is (search marker loader)
            "extension loader omits output sink ~A" marker)))
    (is (search "(cadr-agent::utf16-code-unit-length text)" cli-truncation)
        "CLI UTF-16 compatibility entry point does not delegate")
    (is (search "(cadr-agent::harness-utf8-length" cli-truncation)
        "CLI utf8-length does not delegate to harness-utf8-length")
    (is (not (search "cadr-ai::utf8-octets text" cli-truncation))
        "CLI utf8-length still encodes the whole string to count")
    (is (not (search "loop for character across text" cli-truncation))
        "CLI still owns a second JavaScript length implementation")
    (is (search "loop for character across text" agent-truncation)
        "cadr-agent no longer owns the JavaScript length metric")))

(test goal14-b5-command-and-rpc-domains-have-exact-owners
  (let* ((root (asdf:system-source-directory "cadr-cli"))
         (owners
           '(("bootstrap/tools.lisp"
              "(defun make-baseline-coding-tools"
              "(defun tool-prompt-snippets")
             ("bootstrap/sessions.lisp"
              "(defun resolve-cli-session"
              "(defun handle-session-command")
             ("bootstrap/settings.lisp"
              "(defun make-cli-settings-selector-state"
              "(defun resolve-cli-system-prompt")
             ("bootstrap/auth.lisp"
              "(defun model-registry-login-options"
              "(defun handle-native-auth-command")
             ("bootstrap/commands.lisp"
              "(defun cli-handler")
             ("bootstrap/main.lisp"
              "(defun main")
             ("modes/rpc/models.lisp"
              "(defun rpc-available-models"
              "(defun rpc-set-thinking-level")
             ("modes/rpc/prompt-bash.lisp"
              "(defun rpc-start-prompt"
              "(defun rpc-start-bash")
             ("modes/rpc/sessions.lisp"
              "(defun rpc-new-session"
              "(defun rpc-session-tree")
             ("modes/rpc/commands.lisp"
              "(defun rpc-command-list"
              "(defun rpc-handle-command")
             ("modes/rpc/mode.lisp"
              "(defun rpc-handle-line"
              "(defun run-rpc-mode")))
         (legacy
           '("src/cadr-cli/main.lisp"))
         (definition-count 0))
    (dolist (owner owners)
      (let* ((relative
               (format nil "src/cadr-cli/~A" (first owner)))
             (source (goal14-b1-source root relative)))
        (is (not (null source)) "missing B5 owner ~A" relative)
        (when source
          (incf definition-count
                (count-if
                 (lambda (line)
                   (uiop:string-prefix-p "(def" line))
                 (uiop:split-string source :separator '(#\Newline))))
          (dolist (marker (rest owner))
            (is (search marker source)
                "~A does not own ~A" relative marker)))))
    ;; Goal 18 I7 added three definitions inside the B5 owners:
    ;; cli-session-abort and fork-cli-session-into (bootstrap/sessions.lisp)
    ;; and cli-help-extension-flags (bootstrap/commands.lisp).
    ;; +3 goal 18 I7 tail: validate-cli-session-flags (sessions.lisp) and
    ;; format-list-models-token-count/no-models-available-message
    ;; (main.lisp, baseline listModels table port).
    ;; +1 goal 18 adjudicated -r picker: run-resume-session-picker
    ;; (sessions.lisp, baseline cli/session-picker.ts port).
    ;; +3 goal 18 Part L: settings-tui-mode,
    ;; settings-fullscreen-scrollbar, and
    ;; settings-mermaid-rendering-mode (bootstrap/settings.lisp, the
    ;; v0.84.1 settings readers).
    ;; +1 goal 20 v0.84.2 baseline upgrade: settings-default-tools
    ;; (bootstrap/settings.lisp, the v0.84.2 defaultTools reader).
    ;; +1 goal 20 v0.84.2 baseline upgrade: parse-default-tools-setting
    ;; (bootstrap/settings.lisp, shared by the raw and SDK managers).
    ;; +1 goal 20 v0.84.2 baseline upgrade:
    ;; settings-fullscreen-exit-output (bootstrap/settings.lisp).
    ;; +1 goal 20 CI-1d: rpc-apply-input-hooks-off-reader
    ;; (modes/rpc/prompt-bash.lisp). Steer/follow_up must not run
    ;; blocking :input hooks on the JSONL reader.
    ;; +4 goal 20 K9: +hotkeys-markdown-sections+ (sessions),
    ;; +settings-fallback-keys+ (settings), apply-input-or-queue
    ;; (prompt-bash), rpc-dialog-request-object (rpc/ui).
    ;; +6 Goal 20 list_models column slots: write-unsigned-decimal,
    ;; unsigned-decimal-length, list-models-token-scale,
    ;; write-list-models-token-count, list-models-token-count-length,
    ;; write-ascii-downcase.
    (is (= 134 definition-count)
        "B5 moved a different top-level definition set: ~D"
        definition-count)
    (dolist (relative legacy)
      (is (not (probe-file (merge-pathnames relative root)))
          "B5 legacy mixed owner remains: ~A" relative))))

(test goal14-b5-converges-mode-output-and-time-before-split
  (let* ((root (asdf:system-source-directory "cadr-cli"))
         (sessions
           (goal14-b1-source root "src/cadr-cli/bootstrap/sessions.lisp"))
         (commands
           (goal14-b1-source root "src/cadr-cli/bootstrap/commands.lisp"))
         (rpc-jsonl
           (goal14-b1-source root "src/cadr-cli/modes/rpc/jsonl.lisp"))
         (rpc-files
           (loop for name in '("models" "prompt-bash" "sessions"
                               "commands" "mode")
                 collect
                 (goal14-b1-source
                  root
                  (format nil "src/cadr-cli/modes/rpc/~A.lisp" name)))))
    (is (and sessions
             (search "(cadr-core:milliseconds-to-utc-iso8601" sessions))
        "session export timestamp does not use the B3 time owner")
    (is (and rpc-jsonl
             (search "(cadr-core:unix-milliseconds)" rpc-jsonl))
        "RPC ids do not use the B3 time owner")
    (is (and commands
             (search "(frontend-output" commands)
             (search ":output frontend-output" commands))
        "CLI command controller does not own and inject its mode output")
    (dolist (source rpc-files)
      (is (not (null source)) "missing B5 RPC source")
      (when source
        (is (not (search "write-json-line" source))
            "RPC domain bypasses rpc-write-object")))))

(test goal14-b5-asdf-loads-command-domains-before-entrypoints
  (let* ((root (asdf:system-source-directory "cadr-cli"))
         (source
           (uiop:read-file-string
            (merge-pathnames "cadr-cli.asd" root)))
         (ordered
           '("(:file \"jsonl\")"
             "(:file \"ui\")"
             "(:file \"models\")"
             "(:file \"prompt-bash\")"
             "(:file \"sessions\")"
             "(:file \"commands\")"
             "(:file \"mode\")"
             "(:module \"bootstrap\""
             "(:file \"tools\")"
             "(:file \"sessions\")"
             "(:file \"settings\")"
             "(:file \"auth\")"
             "(:file \"commands\")"
             "(:file \"main\")"
             "(:file \"crash\")"))
         (positions
           (let ((cursor 0))
             (loop for marker in ordered
                   for position = (search marker source :start2 cursor)
                   collect position
                   when position do (setf cursor (1+ position))))))
    (is (every #'identity positions)
        "cadr-cli.asd omits a B5 load boundary: ~S"
        (loop for marker in ordered
              for position in positions
              unless position collect marker))
    (when (every #'identity positions)
      (is (every #'< positions (rest positions))
          "B5 owner load order is not dependency-safe: ~S" positions))))

(test goal14-b6-interactive-controller-and-components-have-exact-owners
  (let* ((root (asdf:system-source-directory "cadr-cli"))
         (owners
           '(("interactive/state.lisp"
              "(defstruct tui-entry"
              "(defstruct (tui-state")
             ("interactive/status.lisp"
              "(defstruct (tui-render-coordinator"
              "(defun render-tui-status-indicator")
             ("interactive/user-bash.lisp"
              "(defun render-user-bash-entry"
              "(defun append-tui-user-bash-result")
             ("interactive/transcript.lisp"
              "(defun seed-tui-message"
              "(defun render-tui-entries")
             ("interactive/tool-rendering.lisp"
              "(defun tool-summary-segments"
              "(defun tui-handle-agent-event")
             ("interactive/entries.lisp"
              "(defun append-tui-entry"
              "(defun add-tui-status")
             ("interactive/pending-messages.lisp"
              "(defun restore-queued-messages-to-editor"
              "(defun render-tui-pending-message-lines")
             ("interactive/frame.lisp"
              "(defun render-tui-overlay-lines"
              "(defun render-tui-state")
             ("interactive/extension-ui.lisp"
              "(defstruct extension-custom-ui-state"
              "(defun render-tui-extension-overlay")
             ("interactive/autocomplete.lisp"
              "(defparameter +tui-autocomplete-command-specifications+"
              "(defun make-tui-autocomplete-provider")
             ("interactive/themes.lisp"
              "(defparameter +tui-theme-json-color-map+"
              "(defun poll-tui-theme-watcher")
             ("interactive/controller.lisp"
              "(defun tui-terminal-title"
              "(defun route-tui-submission"
              "(defun run-tui")
             ("interactive/components/loaders.lisp"
              "(defclass dynamic-border-component"
              "(defclass bordered-loader-component")
             ("interactive/components/countdown.lisp"
              "(defclass countdown-timer"
              "(defun countdown-timer-tick")
             ("interactive/components/armin.lisp"
              "(defclass armin-component"
              "(defun armin-component-tick")
             ("interactive/components/daxnuts.lisp"
              "(defclass daxnuts-component"
              "(defun daxnuts-component-tick")
             ("interactive/components/announcement.lisp"
              "(defun make-earendil-announcement-component")))
         (definition-count 0))
    (dolist (owner owners)
      (let* ((relative (format nil "src/cadr-cli/~A" (first owner)))
             (source (goal14-b1-source root relative)))
        (is (not (null source)) "missing B6 owner ~A" relative)
        (when source
          (incf definition-count
                (count-if
                 (lambda (line)
                   (uiop:string-prefix-p "(def" line))
                 (uiop:split-string source :separator '(#\Newline))))
          (dolist (marker (rest owner))
            (is (search marker source)
                "~A does not own ~A" relative marker)))))
    ;; 251 = goal 18 Part D (+1 debug command); +11 goal 18 Part H
    ;; startup-section helpers in entries.lisp (baseline resource block
    ;; rendering: scope groups, conflict blocks, extension labels); +2
    ;; goal 18 Part I8 render-aware-component channel in extension-ui.lisp.
    ;; +4 goal 18 I7 tail: baseline getShortcuts port in
    ;; interactive/autocomplete.lisp (extension-shortcut-path,
    ;; builtin-shortcut-key-map, resolve-extension-shortcuts,
    ;; refresh-extension-shortcut-diagnostics).
    ;; +2 goal 18 Part L: *tui-mode-switch-hook* and
    ;; *alt-screen-flash-function* (interactive/controller.lisp, the
    ;; v0.84.1 alt-screen live-flash and mode-switch seams).
    ;; +4 goal 20 P0-4: *tui-input-thread*, tui-input-thread-p,
    ;; call-extension-host-turn-without-blocking-tui,
    ;; wrap-extension-host-tui-turn-dispatch (extension-ui.lisp).
    ;; -1 goal 20 sb-cover third-tier: deleted unused trailing-lines
    ;; (interactive/frame.lisp). Last-n is owned by user-bash/tool-block
    ;; /overlay; baseline trailingLines is edit-diff context.
    ;; +16 goal 20 K9: format-key-text*, wrap-transcript-lines,
    ;; kebab-keyword-to-camel, startup help table, dialog chrome,
    ;; armin 2D helpers, daxnuts parse cache, tui-multiline-editor-p.
    (is (= 289 definition-count)
        "B6 moved a different top-level definition set: ~D"
        definition-count)
    (dolist (relative '("src/cadr-cli/tui.lisp"
                        "src/cadr-cli/interactive-components.lisp"))
      (is (not (probe-file (merge-pathnames relative root)))
          "B6 legacy mixed owner remains: ~A" relative))))

(test goal14-b6-reuses-output-selector-and-cleanup-owners-before-split
  (let* ((root (asdf:system-source-directory "cadr-cli"))
         (entries
           (goal14-b1-source root "src/cadr-cli/interactive/entries.lisp"))
         (controller
           (goal14-b1-source root "src/cadr-cli/interactive/controller.lisp"))
         (b6-sources
           (loop for name in
                 '("state" "status" "user-bash" "transcript" "tool-rendering"
                   "entries" "pending-messages" "frame" "extension-ui"
                   "autocomplete" "themes" "controller")
                 collect
                 (goal14-b1-source
                  root
                  (format nil "src/cadr-cli/interactive/~A.lisp" name)))))
    (is (and entries
             (search "(defun add-tui-notice" entries)
             (search "(defun add-tui-warning" entries)
             (search "(defun add-tui-error" entries))
        "B6 entries owner does not retain the interactive output sinks")
    (is (and controller
             (search "(defun open-tui-url" controller)
             (search "(defun make-notification-output-stream" controller)
             (search "(stop-thread-for-cleanup" controller))
        "B6 controller bypasses the URL/output/cleanup owners")
    (dolist (source b6-sources)
      (is (not (null source)) "missing B6 source")
      (when source
        (is (not (search "(defun selector-border-line" source))
            "B6 rebuilt selector border policy outside selector-frame")
        (is (not (search "(defun selector-frame-move-index" source))
            "B6 rebuilt selector navigation outside selector-frame")))))

(test goal14-b6-asdf-loads-state-renderers-and-components-before-controller
  (let* ((root (asdf:system-source-directory "cadr-cli"))
         (source
           (uiop:read-file-string
            (merge-pathnames "cadr-cli.asd" root)))
         (ordered
           '(("(:module \"interactive-components\"" 1)
             ("(:file \"loaders\")" 1)
             ("(:file \"countdown\")" 1)
             ("(:file \"armin\")" 1)
             ("(:file \"daxnuts\")" 1)
             ("(:file \"announcement\")" 1)
             ("(:module \"interactive-controller\"" 1)
             ("(:file \"state\")" 1)
             ("(:file \"entries\")" 1)
             ("(:file \"status\")" 1)
             ("(:file \"extension-ui\")" 1)
             ("(:file \"user-bash\")" 1)
             ("(:file \"transcript\")" 1)
             ("(:file \"tool-rendering\")" 1)
             ("(:file \"pending-messages\")" 1)
             ("(:file \"frame\")" 1)
             ("(:file \"autocomplete\")" 1)
             ("(:file \"themes\")" 1)
             ("(:file \"controller\")" 1)))
         (cursor 0)
         (positions nil))
    (dolist (spec ordered)
      (let ((position
              (loop repeat (second spec)
                    for found = (search (first spec) source :start2 cursor)
                    do (unless found (return nil))
                       (setf cursor (1+ found))
                    finally (return found))))
        (push position positions)))
    (setf positions (nreverse positions))
    (is (every #'identity positions)
        "cadr-cli.asd omits a B6 load boundary: ~S"
        (loop for spec in ordered
              for position in positions
              unless position collect (first spec)))
    (when (every #'identity positions)
      (is (every #'< positions (rest positions))
          "B6 owner load order is not dependency-safe: ~S" positions))))

(test goal14-b7-reusable-tui-internals-have-exact-owners
  (let* ((root (asdf:system-source-directory "cadr-tui"))
         (owners
           '(("components/markdown.lisp"
              "(defun render-inline-markdown"
              "(defun render-markdown"
              "(defun render-truncated-text")
             ("components/image.lisp"
              "(defun render-image-component")
             ("components/tool-block.lisp"
              "(defstruct (tool-block"
              "(defun render-tool-block")
             ("components/status.lisp"
              "(defun render-footer"
              "(defun render-status-bar")
             ("components/select-list.lisp"
              "(defstruct (select-list"
              "(defun render-select-list")
             ("composition/protocol.lisp"
              "(defclass component () ())"
              "(defclass component-container")
             ("composition/text-box.lisp"
              "(defclass text-component"
              "(defclass box-component"
              "(defclass truncated-text-component")
             ("composition/rich-content.lisp"
              "(defclass markdown-component"
              "(defclass image-component")
             ("composition/settings-list.lisp"
              "(defstruct setting-item"
              "(defclass settings-list-component"
              "(defgeneric editor-component-text")
             ("composition/loaders.lisp"
              "(defclass loader-component"
              "(defclass cancellable-loader-component")
             ("composition/root.lisp"
              "(defclass tui-root"
              "(defun tui-show-overlay")
             ("renderer/terminal-protocol.lisp"
              "(defclass terminal ()"
              "(defgeneric terminal-start")
             ("renderer/virtual-terminal.lisp"
              "(defclass virtual-terminal"
              "(defun virtual-terminal-snapshot")
             ("renderer/lifecycle-input.lisp"
              "(defstruct (terminal-renderer"
              "(defun renderer-start"
              "(defun renderer-handle-input")
             ("renderer/main-screen.lisp"
              "(defun clipped-frame-lines"
              "(defun render-main-frame")
             ("renderer/alt-screen.lisp"
              "(defun prepare-alt-line"
              "(defun render-alt-frame"
              "(defun render-frame")))
         (definition-count 0))
    (dolist (owner owners)
      (let ((source
              (goal14-b1-source
               root (format nil "src/cadr-tui/~A" (first owner)))))
        (is (not (null source)) "missing B7 owner ~A" (first owner))
        (when source
          (incf definition-count
                (count-if
                 (lambda (line)
                   (uiop:string-prefix-p "(def" line))
                 (uiop:split-string source :separator '(#\Newline))))
          (dolist (marker (rest owner))
            (is (search marker source)
                "~A does not own ~A" (first owner) marker)))))
    ;; +2 goal 18 I05: renderer-request-canonical-repaint and
    ;; *canonical-repaint-hook* (lifecycle-input.lisp) — the harness
    ;; work-rendered acknowledgement repaints in place instead of
    ;; wiping scrollback.
    ;; +27 goal 18 Part L2.2 (v0.84.1 alt-screen/LaTeX parity):
    ;; +10 markdown.lisp LaTeX owners (latex-placeholder delimiters,
    ;; latex-escaped-p, latex-find-closing-delimiter,
    ;; latex-looks-like-pending-math-p, markdown-latex-inline-span,
    ;; markdown-extract-inline-latex, markdown-restore-inline-latex,
    ;; markdown-latex-block-opening, markdown-latex-block-close-index);
    ;; +14 lifecycle-input.lisp owners (renderer-flash,
    ;; renderer-live-flash-lines, renderer-note-scrollbar-activity,
    ;; multiplexer-mouse-environment-p, mouse-enable-sequence replacing
    ;; the folded +mouse-enable+, renderer-enter/exit-alt-screen-live,
    ;; osc133-prompt-start-line-p, renderer-scroll-to-prompt,
    ;; selection-word-character-class, selection-word-range,
    ;; renderer-note-click, renderer-selection-source-line,
    ;; renderer-line-selection-range, selection-point-before-p);
    ;; +3 renderer/alt-screen.lisp scrollbar owners
    ;; (alt-scrollbar-visible-p, style-alt-scrollbar-cell,
    ;; apply-alt-scrollbar).
    ;; +3 goal 19 Part C: markdown.lisp marked-18 code-span helpers
    ;; (markdown-code-span-run-length, markdown-normalize-code-span-text,
    ;; replace-markdown-code-spans).
    ;; +1 goal 20 12E-6: +kitty-escape-prefix+ (main-screen.lisp), one
    ;; shared Kitty marker instance instead of a per-line format.
    ;; +6 goal 20 v0.84.2 baseline upgrade: the transcript search port
    ;; (renderer-open-search/renderer-close-search in lifecycle-input;
    ;; style-search-match-text, renderer-refresh-search,
    ;; apply-search-highlights, overlay-search-bar in alt-screen.lisp).
    ;; -1 goal 20 sb-cover third-tier: deleted unused
    ;; markdown-ordered-prefix-end (markdown.lisp).
    ;; markdown-list-item-data already parses ordered markers.
    ;; +2 Goal 20 K8: loader-frames/loader-interval-seconds and
    ;; synchronized-update constants; main-screen dropped its
    ;; duplicate Kitty helpers (-2).
    ;; clamp-select-index is offset by a dropped helper in the same
    ;; B7 owner set, so the top-level (def count stays 334.
    ;; +1 Goal 20 P.12.3: renderer-document-line (lifecycle-input.lisp)
    ;; indexes last-document as a vector or list.
    (is (= 335 definition-count)
        "B7 moved a different top-level definition set: ~D"
        definition-count)
    (dolist (relative '("src/cadr-tui/components.lisp"
                        "src/cadr-tui/composition.lisp"
                        "src/cadr-tui/renderer.lisp"))
      (is (not (probe-file (merge-pathnames relative root)))
          "B7 legacy mixed owner remains: ~A" relative))))

(test goal14-b7-reuses-core-cancellation-and-cleanup-before-split
  (let* ((root (asdf:system-source-directory "cadr-tui"))
         (loaders
           (goal14-b1-source root "src/cadr-tui/composition/loaders.lisp"))
         (sources
           (loop for relative in
                 '("components/markdown.lisp" "components/image.lisp"
                   "components/tool-block.lisp" "components/status.lisp"
                   "components/select-list.lisp" "composition/protocol.lisp"
                   "composition/text-box.lisp" "composition/rich-content.lisp"
                   "composition/settings-list.lisp" "composition/loaders.lisp"
                   "composition/root.lisp" "renderer/terminal-protocol.lisp"
                   "renderer/virtual-terminal.lisp" "renderer/lifecycle-input.lisp"
                   "renderer/main-screen.lisp" "renderer/alt-screen.lisp")
                 collect (goal14-b1-source
                          root (format nil "src/cadr-tui/~A" relative)))))
    (is (and loaders
             (search "(stop-thread-for-cleanup thread)" loaders)
             (search "(cadr-core:make-cancellation-state)" loaders))
        "B7 loader owner bypasses the B3 cleanup/cancellation primitives")
    (dolist (source sources)
      (is (not (null source)) "missing B7 source")
      (when source
        (is (not (search "sb-thread:join-thread" source))
            "B7 source reintroduced an unbounded cleanup join")
        (is (not (search "(defun stop-thread-for-cleanup" source))
            "B7 source redefined the B3 cleanup policy")))))

(test goal14-b7-asdf-loads-protocols-before-implementations
  (let* ((root (asdf:system-source-directory "cadr-tui"))
         (source
           (uiop:read-file-string (merge-pathnames "cadr-tui.asd" root)))
         (ordered
           '(("(:module \"components\"" 1)
             ("(:file \"markdown\")" 1)
             ("(:file \"image\")" 1)
             ("(:file \"tool-block\")" 1)
             ("(:file \"status\")" 1)
             ("(:file \"select-list\")" 1)
             ("(:module \"renderer\"" 1)
             ("(:file \"terminal-protocol\")" 1)
             ("(:file \"virtual-terminal\")" 1)
             ("(:file \"lifecycle-input\")" 1)
             ("(:file \"main-screen\")" 1)
             ("(:file \"alt-screen\")" 1)
             ("(:module \"composition\"" 1)
             ("(:file \"protocol\")" 1)
             ("(:file \"text-box\")" 1)
             ("(:file \"rich-content\")" 1)
             ("(:file \"settings-list\")" 1)
             ("(:file \"loaders\")" 1)
             ("(:file \"root\")" 1)))
         (cursor 0)
         (positions nil))
    (dolist (spec ordered)
      (let ((position
              (loop repeat (second spec)
                    for found = (search (first spec) source :start2 cursor)
                    do (unless found (return nil))
                       (setf cursor (1+ found))
                    finally (return found))))
        (push position positions)))
    (setf positions (nreverse positions))
    (is (every #'identity positions)
        "cadr-tui.asd omits a B7 load boundary: ~S"
        (loop for spec in ordered
              for position in positions
              unless position collect (first spec)))
    (when (every #'identity positions)
      (is (every #'< positions (rest positions))
          "B7 owner load order is not dependency-safe: ~S" positions))))

(test goal14-b8-agent-session-storage-and-loop-have-exact-owners
  (let* ((root (asdf:system-source-directory "cadr-agent"))
         (owners
           '(("session/codec.lisp"
              "(defstruct session-entry"
              "(defun message-to-json"
              "(defun message-from-json")
             ("session/journal.lisp"
              "(defun create-session"
              "(defun append-session-entry"
              "(defun session-messages")
             ("session/migration.lisp"
              "(defun parse-session-line"
              "(defun migrate-v1-session-objects"
              "(defun load-session")
             ("session/discovery.lisp"
              "(defun read-session-header-for-discovery"
              "(defun list-sessions"
              "(defun resume-session")
             ("session/export-html.lisp"
              "(defun parse-session-skill-block"
              "(defun export-html-session-data"
              "(defun export-session-html")
             ("storage/protocol.lisp"
              "(defstruct session-metadata"
              "(defgeneric session-storage-append-entry"
              "(defgeneric session-repository-create")
             ("storage/memory.lisp"
              "(defclass memory-session-storage"
              "(defun make-memory-session-storage"
              "(defmethod session-storage-cleanup")
             ("storage/harness.lisp"
              "(defstruct harness-session"
              "(defstruct (memory-session-repository"
              "(defmethod session-repository-fork")
             ("storage/jsonl.lisp"
              "(defclass jsonl-session-storage"
              "(defun create-jsonl-session-storage"
              "(defclass jsonl-session-repository")
             ("loop/events.lisp"
              "(defun run-agent-lifecycle"
              "(defun emit-message-start"
              "(defun assistant-tool-calls")
             ("loop/tool-execution.lisp"
              "(defun make-truncated-tool-result"
              "(defun execute-tool-batch"
              "(defun execute-truncated-tool-batch")
             ("loop/turns.lisp"
              "(defun stream-assistant"
              "(defun commit-agent-turn"
              "(defun run-agent-with-retries")
             ("loop/agent-loop.lisp"
              "(defun run-agent-loop"
              "(defun agent-prompt"
              "(defun agent-continue")))
         (definition-count 0))
    (dolist (owner owners)
      (let ((source
              (goal14-b1-source
               root (format nil "src/cadr-agent/~A" (first owner)))))
        (is (not (null source)) "missing B8 owner ~A" (first owner))
        (when source
          (incf definition-count
                (count-if
                 (lambda (line)
                   (uiop:string-prefix-p "(def" line))
                 (uiop:split-string source :separator '(#\Newline))))
          (dolist (marker (rest owner))
            (is (search marker source)
                "~A does not own ~A" (first owner) marker)))))
    ;; +1 goal 18 Part L: *tool-result-image-normalize-function*
    ;; (loop/tool-execution.lisp, the image normalization seam used by
    ;; the tool-result rendering path).
    ;; +3 Goal 20 K6: agent-message-to-llm, usage-cost-amount,
    ;; put-session-details-and-usage / queue accessors / tail slot.
    ;; +10 Goal 20 session-entry decode: seen bits, visitor put,
    ;; parse-session-record, finalize (drop require-json-field).
    ;; +1 Goal 20 nested message/usage: session-json-message.
    ;; +1 Goal 20 content blocks: session-json-block.
    ;; +1 Goal 20 load finalize: session-type-keyword.
    ;; +1 Goal 20 session octet FSM: parse-session-record-octets.
    ;; +7 Goal 20 journal_append typed emit: write-session-entry-jsonl
    ;; and helpers.
    ;; +3 Goal 20 journal fd reuse: close/open/session-journal-stream.
    ;; +6 Goal 20 journal_append octet emit: buffer + ASCII/string/value
    ;; helpers, emit-session-message-entry, write-session-octets.
    ;; +4 Goal 20 typed session header: session-file-header,
    ;; session-header-ref, session-file-header-to-hash,
    ;; parse-session-header-octets.
    ;; +10 Goal 20 walker SWAR: 6 splat constants + haszero +
    ;; first-msb + octet-find-lf + octet-skip-json-space.
    ;; +1 Goal 20 SWAR ub32: swar-ws-mask (no 64-bit bignum).
    ;; +5 Goal 20 string-window SWAR: quot/bs constants +
    ;; quote-or-bs-mask + ctrl-mask + find-quote-or-backslash.
    (is (= 307 definition-count)
        "B8 moved a different top-level definition set: ~D"
        definition-count)
    (dolist (relative '("src/cadr-agent/session.lisp"
                        "src/cadr-agent/storage.lisp"
                        "src/cadr-agent/loop.lisp"))
      (is (not (probe-file (merge-pathnames relative root)))
          "B8 legacy mixed owner remains: ~A" relative))))

(test goal14-b8-reuses-core-time-id-and-atomic-migration-before-split
  (let* ((root (asdf:system-source-directory "cadr-agent"))
         (codec (goal14-b1-source root "src/cadr-agent/session/codec.lisp"))
         (migration
           (goal14-b1-source root "src/cadr-agent/session/migration.lisp"))
         (protocol
           (goal14-b1-source root "src/cadr-agent/storage/protocol.lisp"))
         (sources
           (loop for relative in
                 '("session/codec.lisp" "session/journal.lisp"
                   "session/migration.lisp" "session/discovery.lisp"
                   "session/export-html.lisp" "storage/protocol.lisp"
                   "storage/memory.lisp" "storage/harness.lisp"
                   "storage/jsonl.lisp" "loop/events.lisp"
                   "loop/tool-execution.lisp" "loop/turns.lisp"
                   "loop/agent-loop.lisp")
                 collect
                 (goal14-b1-source
                  root (format nil "src/cadr-agent/~A" relative)))))
    (is (and codec
             (search "(cadr-ai:uuid-v7)" codec)
             (search "(cadr-core:milliseconds-to-utc-iso8601 milliseconds)"
                     codec))
        "B8 session codec bypasses the existing UUID-v7/B3 time owners")
    (is (and protocol
             (search "(cadr-core:current-utc-iso8601)" protocol))
        "B8 storage protocol bypasses B3 time primitives")
    (is (and migration
             (search "(cadr-core:call-with-atomic-output-file" migration))
        "B8 migration bypasses B3 atomic output")
    (dolist (source sources)
      (is (not (null source)) "missing B8 source")
      (when source
        (is (not (search "rename-file-overwriting-target" source))
            "B8 source reintroduced local atomic replacement policy")))))

(test goal14-b8-asdf-loads-protocols-before-backends-and-loop
  (let* ((root (asdf:system-source-directory "cadr-agent"))
         (source
           (uiop:read-file-string (merge-pathnames "cadr-agent.asd" root)))
         (ordered
           '(("(:module \"session\"" 1)
             ("(:file \"codec\")" 1)
             ("(:file \"journal\")" 1)
             ("(:file \"migration\")" 1)
             ("(:file \"discovery\")" 1)
             ("(:file \"export-html\")" 1)
             ("(:module \"storage\"" 1)
             ("(:file \"protocol\")" 1)
             ("(:file \"memory\")" 1)
             ("(:file \"harness\")" 1)
             ("(:file \"jsonl\")" 1)
             ("(:file \"sqlite-storage\")" 1)
             ("(:module \"loop\"" 1)
             ("(:file \"events\")" 1)
             ("(:file \"tool-execution\")" 1)
             ("(:file \"turns\")" 1)
             ("(:file \"agent-loop\")" 1)))
         (cursor 0)
         (positions nil))
    (dolist (spec ordered)
      (let ((position
              (loop repeat (second spec)
                    for found = (search (first spec) source :start2 cursor)
                    do (unless found (return nil))
                       (setf cursor (1+ found))
                    finally (return found))))
        (push position positions)))
    (setf positions (nreverse positions))
    (is (every #'identity positions)
        "cadr-agent.asd omits a B8 load boundary: ~S"
        (loop for spec in ordered
              for position in positions
              unless position collect (first spec)))
    (when (every #'identity positions)
      (is (every #'< positions (rest positions))
          "B8 owner load order is not dependency-safe: ~S" positions))))

(test goal14-b8-stability-provenance-follows-session-owner
  (let* ((root (asdf:system-source-directory "cadr-agent"))
         (source
           (goal14-b1-source root "scripts/goal11-stability.lisp")))
    (is (not (null source)) "missing Goal 11 stability harness")
    (when source
      (is (search "src/cadr-agent/session/codec.lisp" source)
          "Goal 11 provenance does not follow the B8 session codec owner")
      (is (not (search "src/cadr-agent/session.lisp" source))
          "Goal 11 provenance still hashes the removed B8 aggregate"))))

(test goal14-b9-extension-host-has-exact-owners
  (let* ((root (asdf:system-source-directory "cadr-agent"))
         (owners
           '(("context.lisp"
              "(defstruct extension-snapshot"
              "(defstruct (extension-host"
              "(defstruct (extension-context"
              "(defun extension-context-set-session-name")
             ("api.lisp"
              "(defun active-extension-api-p"
              "(defun extension-api-http-request"
              "(defun copy-extension-value"
              "(defun extension-event-payload")
             ("registration.lisp"
              "(defstruct extension-bundle"
              "(defun register-extension-tool"
              "(defparameter +extension-hook-events+"
              "(defmacro define-tool"
              "(defmacro define-tool-renderer")
             ("snapshot.lisp"
              "(defun make-extension-host"
              "(defun make-extension-snapshot-from-bundles"
              "(defun replace-extension-bundles"
              "(defun call-with-extension-definition")
             ("rendering.lisp"
              "(defun notify-extension-failure"
              "(defun transform-extension-markdown"
              "(defun render-extension-tool-result"
              "(defun invoke-extension-shortcut")
             ("providers.lisp"
              "(defun extension-host-tools"
              "(defun attach-extension-host"
              "(defun extension-host-send-message"
              "(defun apply-extension-provider-overlays"
              "(defun extension-context-register-provider")
             ("commands.lisp"
              "(defun invoke-extension-command"
              "(defun substitute-extension-template"
              "(defun expand-extension-prompt")
             ("lifecycle.lisp"
              "(defun run-extension-hooks"
              "(defparameter +extension-lifecycle-no-result-events+"
              "(defun run-extension-lifecycle-hooks")))
         (definition-count 0))
    (dolist (owner owners)
      (let ((source
              (goal14-b1-source
               root (format nil "src/cadr-agent/extensions/~A" (first owner)))))
        (is (not (null source)) "missing B9 owner ~A" (first owner))
        (when source
          (incf definition-count
                (count-if
                 (lambda (line) (uiop:string-prefix-p "(def" line))
                 (uiop:split-string source :separator '(#\Newline))))
          (dolist (marker (rest owner))
            (is (search marker source)
                "~A does not own ~A" (first owner) marker)))))
    ;; +14 Goal 20 K6: extension-definition-bundle methods,
    ;; assert-extension-deliver-as, render-extension-named.
    (is (= 253 definition-count)
        "B9 moved a different top-level definition set: ~D" definition-count)
    (is (not (probe-file (merge-pathnames
                          "src/cadr-agent/extensions.lisp" root)))
        "B9 legacy mixed owner remains")))

(test goal14-b9-preserves-core-owners-and-frozen-extension-surfaces
  (let* ((root (asdf:system-source-directory "cadr-agent"))
         (context
           (goal14-b1-source root "src/cadr-agent/extensions/context.lisp"))
         (rendering
           (goal14-b1-source root "src/cadr-agent/extensions/rendering.lisp"))
         (registration
           (goal14-b1-source root "src/cadr-agent/extensions/registration.lisp"))
         (package-source (goal14-b1-source root "src/cadr-agent/package.lisp"))
         (sources
           (loop for name in
                 '("context" "api" "registration" "snapshot"
                   "rendering" "providers" "commands" "lifecycle")
                 collect
                 (goal14-b1-source
                  root (format nil "src/cadr-agent/extensions/~A.lisp" name)))))
    (is (and context
             (search "(cadr-core:make-cancellation-state" context)
             (search "(cadr-core:cancellation-aborted-p" context)
             (search "(cadr-core:abort-cancellation" context))
        "B9 context bypasses the B3 cancellation owner")
    (is (and rendering
             (search "(defun notify-extension-failure" rendering)
             (search "(extension-host-notify-function host)" rendering))
        "B9 rendering bypasses the injected extension output sink")
    (dolist (source sources)
      (is (not (null source)) "missing B9 source")
      (when source
        (dolist (forbidden '("sb-thread:join-thread"
                             "rename-file-overwriting-target"
                             "(defmethod print-object"))
          (is (not (search forbidden source))
              "B9 source reintroduced policy ~A" forbidden))))
    (let ((exports
            (goal14-source-block
             package-source "#:define-tool" "#:make-extension-hook-result"))
          (events
            (goal14-source-block
             registration "(defparameter +extension-hook-events+"
             "    :user-bash))")))
      (is (and exports
               (string=
                "61eb1b623f784b3a8f0f6fe6791c65ebe991ff314ed1d969b82f3edd57646f18"
                (goal14-sha256 exports)))
          "B9 changed the frozen extension export text")
      (is (and events
               (string=
                "12f79b21e0e25495cb023baaf21b26f6cf9a891881b26602f6553f80af54887a"
                (goal14-sha256 events)))
          "B9 changed the frozen 34-event source block"))))

(test goal14-b9-asdf-loads-extension-host-in-dependency-order
  (let* ((root (asdf:system-source-directory "cadr-agent"))
         (source (uiop:read-file-string (merge-pathnames "cadr-agent.asd" root)))
         (ordered
           '(("(:module \"extensions\"" 1)
             ("(:file \"context\")" 1)
             ("(:file \"api\")" 1)
             ("(:file \"registration\")" 1)
             ("(:file \"snapshot\")" 1)
             ("(:file \"rendering\")" 1)
             ("(:file \"providers\")" 1)
             ("(:file \"commands\")" 1)
             ("(:file \"lifecycle\")" 1)))
         (cursor 0)
         (positions nil))
    (dolist (spec ordered)
      (let ((position
              (loop repeat (second spec)
                    for found = (search (first spec) source :start2 cursor)
                    do (unless found (return nil))
                       (setf cursor (1+ found))
                    finally (return found))))
        (push position positions)))
    (setf positions (nreverse positions))
    (is (every #'identity positions)
        "cadr-agent.asd omits a B9 load boundary: ~S"
        (loop for spec in ordered
              for position in positions
              unless position collect (first spec)))
    (when (every #'identity positions)
      (is (every #'< positions (rest positions))
          "B9 extension load order is not dependency-safe: ~S" positions))))

(test goal14-b10-ai-capability-transport-runtime-and-support-have-exact-owners
  (let* ((root (asdf:system-source-directory "cadr-ai"))
         (owners
           '(("capabilities/streaming-json.lisp"
              "(defun short-hash"
              "(defun parse-streaming-json")
             ("capabilities/event-stream.lisp"
              "(defclass event-stream"
              "(defun event-stream-result")
             ("capabilities/grammar-tools.lisp"
              "(defun split-deferred-tools"
              "(defun create-grammar-tool-input-properties")
             ("capabilities/session-resources.lisp"
              "(defun register-session-resource-cleanup"
              "(defun cleanup-session-resources")
             ("capabilities/proxy-config.lisp"
              "(defun resolve-http-proxy-url-for-target")
             ("capabilities/image-runtime.lisp"
              "(defstruct images-api-provider"
              "(defun images-models-generate")
             ("transport/http.lisp"
              "(defstruct request-spec"
              "(defun request-sse")
             ("transport/aws-event-stream.lisp"
              "(defun read-aws-event-stream"
              "(defun request-provider-events")
             ("runtime/models.lisp"
              "(define-condition models-runtime-error"
              "(defun models-runtime-stream")
             ("runtime/faux-provider.lisp"
              "(defstruct faux-state"
              "(defun faux-stream")
             ("support/threads.lisp"
              "(defun stop-thread-for-cleanup")
             ("support/release.lisp"
              "(defun cadr-product-slug"
              "(defun cadr-product-display-name"
              "(defun cadr-canonical-repository-url"
              "(defun cadr-default-share-viewer-url"
              "(defun cadr-release-identity")
             ("support/retry.lisp"
              "(defun retryable-assistant-error-p"
              "(defun retry-assistant-call")
             ("support/token-estimation.lisp"
              "(defstruct context-usage-estimate"
              "(defun estimate-context-tokens")
             ("support/overflow.lisp"
              "(defun context-overflow-p")
             ("support/grammar-coercion.lisp"
              "(defstruct grammar-json-buffer"
              "(defun validate-tool-call")
             ("support/uuid.lisp"
              "(defun uuid-v7")))
         (definition-count 0))
    (dolist (owner owners)
      (let ((source
              (goal14-b1-source
               root (format nil "src/cadr-ai/~A" (first owner)))))
        (is (not (null source)) "missing B10 owner ~A" (first owner))
        (when source
          (incf definition-count
                (count-if
                 (lambda (line) (uiop:string-prefix-p "(def" line))
                 (uiop:split-string source :separator '(#\Newline))))
          (dolist (marker (rest owner))
            (is (search marker source)
                "~A does not own ~A" (first owner) marker)))))
    ;; +3 goal 18 I7 tail: baseline auth-guidance helpers in
    ;; support/release.lisp (cadr-docs-directory, provider-login-help-text,
    ;; no-api-key-found-message).
    ;; -2 goal 18 L2.1: the three aligned-pi defparameters nested under
    ;; the read-baseline-anchor multiple-value-bind (no longer column-0
    ;; top-level forms), +1 read-baseline-anchor itself.
    ;; +2 goal 18 sentinel adjudication: no-models-available-message and
    ;; no-model-selected-message joined no-api-key-found-message in
    ;; support/release.lisp as the single message owners.
    ;; +11 goal 20 v0.84.2 baseline upgrade: the strict-schema family in
    ;; capabilities/grammar-tools.lisp (condition, key list, error helper,
    ;; structured/null probes, node/root strictifiers, parameter getter),
    ;; cadr-user-agent in support/release.lisp, and the
    ;; optional-null-normalization pair in support/grammar-coercion.lisp.
    ;; +4 Goal 20 K7: keyed-collection-value, signal-http-timeout,
    ;; call-with-models-runtime-error, faux-stream-block.
    ;; +6 Goal 20 session_compact: uuid entropy pool (two defun + four
    ;; defparameter) copies Node getRandomValues; no /dev/urandom per id.
    (is (= 274 definition-count)
        "B10 moved a different top-level definition set: ~D"
        definition-count)
    (dolist (relative '("src/cadr-ai/capabilities.lisp"
                        "src/cadr-ai/http.lisp"
                        "src/cadr-ai/models-runtime.lisp"
                        "src/cadr-ai/utilities.lisp"))
      (is (not (probe-file (merge-pathnames relative root)))
          "B10 legacy mixed owner remains: ~A" relative))))

(test goal14-b10-preserves-core-owners-and-frozen-ai-surface
  (let* ((root (asdf:system-source-directory "cadr-ai"))
         (threads (goal14-b1-source root "src/cadr-ai/support/threads.lisp"))
         (http (goal14-b1-source root "src/cadr-ai/transport/http.lisp"))
         (models (goal14-b1-source root "src/cadr-ai/runtime/models.lisp"))
         (package-source (goal14-b1-source root "src/cadr-ai/package.lisp"))
         (sources
           (loop for relative in
                 '("capabilities/streaming-json.lisp"
                   "capabilities/event-stream.lisp"
                   "capabilities/grammar-tools.lisp"
                   "capabilities/session-resources.lisp"
                   "capabilities/proxy-config.lisp"
                   "capabilities/image-runtime.lisp"
                   "transport/http.lisp" "transport/aws-event-stream.lisp"
                   "runtime/models.lisp" "runtime/faux-provider.lisp"
                   "support/threads.lisp" "support/release.lisp"
                   "support/retry.lisp" "support/token-estimation.lisp"
                   "support/overflow.lisp" "support/grammar-coercion.lisp"
                   "support/uuid.lisp")
                 collect
                 (goal14-b1-source root (format nil "src/cadr-ai/~A" relative)))))
    (is (and threads
             (search "(cadr-core:stop-thread-for-cleanup" threads))
        "B10 thread compatibility entry point bypasses the B3 owner")
    (is (and http
             (search "(cadr-core:cancellation-predicate-aborted-p" http)
             (search ":read-timeout nil" http)
             (search ":message \"fetch failed\"" http))
        "B10 transport changed cancellation, SSE timeout, or diagnostic policy")
    (is (and models
             (search "(cadr-core:cancellation-predicate-aborted-p" models))
        "B10 runtime model cancellation bypasses the B3 owner")
    (is (and package-source
             (string=
              ;; +1 export #:provider-oauth-subscription-p (goal 18
              ;; provider metadata: bootstrap/commands.lisp consumes
              ;; the isUsingSubscription port).
              ;; +5 goal 20 v0.84.2 baseline upgrade: tool-call-namespace,
              ;; assistant-message-end-turn, make-strict-json-schema,
              ;; get-json-schema-tool-parameters,
              ;; unsupported-strict-json-schema-error.
              "d098e719c558f86f9d66db13bc6a5b59dbfb0d81df4ce8a6354ad9f0b65ec950"
              (goal14-sha256 package-source)))
        "B10 changed the frozen cadr-ai public package text")
    (dolist (source sources)
      (is (not (null source)) "missing B10 source")
      (when source
        (dolist (forbidden '("sb-thread:join-thread"
                             "rename-file-overwriting-target"
                             "(defmethod print-object"))
          (is (not (search forbidden source))
              "B10 source reintroduced policy ~A" forbidden))))))

(test goal14-b10-b11-asdf-loads-ai-owners-in-dependency-order
  (let* ((root (asdf:system-source-directory "cadr-ai"))
         (source (uiop:read-file-string (merge-pathnames "cadr-ai.asd" root)))
         (ordered
           '("(:module \"support\""
             "(:file \"threads\")" "(:file \"release\")"
             "(:file \"retry\")" "(:file \"token-estimation\")"
             "(:file \"overflow\")" "(:file \"grammar-coercion\")"
             "(:file \"uuid\")"
             "(:module \"capabilities\""
             "(:file \"streaming-json\")" "(:file \"event-stream\")"
             "(:file \"grammar-tools\")" "(:file \"session-resources\")"
             "(:file \"proxy-config\")" "(:file \"image-runtime\")"
             "(:file \"sse\")"
             "(:module \"transport\""
             "(:file \"http\")" "(:file \"aws-event-stream\")"
             "(:file \"provider\")" "(:file \"auth\")"
             "(:module \"oauth-core\""
             "(:file \"pkce\")" "(:file \"callback\")"
             "(:file \"page\")" "(:file \"openai-anthropic\")"
             "(:module \"runtime\""
             "(:file \"models\")" "(:file \"faux-provider\")"
             "(:file \"crypto\")" "(:file \"model-data\")"
             "(:module \"auth-implementations\""
             "(:file \"bedrock\")" "(:file \"vertex\")"
             "(:file \"device-code\")" "(:file \"github-copilot\")"
             "(:file \"radius-cloudflare\")"
             "(:module \"oauth-providers\""
             "(:file \"xai\")" "(:file \"kimi\")"
             "(:file \"github-copilot\")" "(:file \"openrouter\")"
             "(:file \"radius\")" "(:file \"openai-device\")"
             "(:file \"anthropic\")"
             "(:file \"images\")"
             "(:module \"providers\""
             "(:file \"anthropic\")" "(:file \"openai\")"
             "(:file \"openai-completions\")" "(:file \"google\")"
             "(:file \"azure-openai\")" "(:file \"codex\")"
             "(:file \"mistral\")" "(:file \"vertex\")"
             "(:file \"bedrock\")" "(:file \"pi-messages\")"
             "(:file \"definitions\")" "(:file \"registry\")"
             "(:file \"runtime-projection\")"
             "(:file \"websocket\")" "(:file \"crash\")"))
         (positions
           (let ((cursor 0))
             (loop for marker in ordered
                   for position = (search marker source :start2 cursor)
                   collect position
                   when position do (setf cursor (1+ position))))))
    (is (every #'identity positions)
        "cadr-ai.asd omits a B10/B11 load boundary: ~S"
        (loop for marker in ordered
              for position in positions
              unless position collect marker))
    (when (every #'identity positions)
      (is (every #'< positions (rest positions))
          "B10/B11 owner load order is not dependency-safe: ~S" positions))))

(test goal14-part-d-organization-gate-is-permanent-and-real-input-driven
  (let* ((root (asdf:system-source-directory "cadr-cli"))
         (checker
           (goal14-b1-source root "scripts/check-code-organization.py"))
         (verify (goal14-b1-source root "scripts/verify.sh"))
         (ledger (goal14-b1-source root "docs/code-organization.md"))
         (manifest
           (goal14-b1-source
            root "docs/code-organization-exemptions.json")))
    (is (not (null checker)) "missing organization checker")
    (is (not (null manifest)) "missing organization exemption manifest")
    (is (and verify
             (search "code organization gate" verify)
             (search "scripts/check-code-organization.py" verify)
             (search "test/code-organization-gate-test.py" verify))
        "verify.sh does not drive both real and synthetic organization input")
    (is (and ledger
             (search "## 7. Permanent organization gate" ledger)
             (search "symptom detector" ledger)
             (search "Future goal preflight" ledger))
        "organization ownership did not become a standing contract")))
