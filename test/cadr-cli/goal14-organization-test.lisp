(in-package #:cadr-cli/tests)

(in-suite cadr-cli-suite)

(defun goal14-b1-source (root relative)
  (let ((path (merge-pathnames relative root)))
    (and (probe-file path)
         (uiop:read-file-string path))))

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
             "(:file \"transcript\")"
             "(:file \"status\")"
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
             ("models/credential-print.lisp" "(define-condition credential-print-error")
             ("packages/source.lisp" "(defstruct package-source")
             ("packages/settings.lisp" "(defun settings-package-entries")
             ("packages/manifest.lisp" "(defun read-package-pi-manifest")
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
    (is (= 100 definition-count)
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
