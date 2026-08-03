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

(test goal14-b6-interactive-controller-and-components-have-exact-owners
  (let* ((root (asdf:system-source-directory "cadr-cli"))
         (owners
           '(("interactive/state.lisp"
              "(defstruct tui-entry"
              "(defstruct (tui-state")
             ("interactive/status.lisp"
              "(defstruct (tui-render-coordinator"
              "(defun render-tui-status-indicator")
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
              "(defun fit-overlay-lines"
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
    (is (= 224 definition-count)
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
                 '("state" "status" "transcript" "tool-rendering"
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
    (is (= 288 definition-count)
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
    (is (= 251 definition-count)
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
    (is (= 239 definition-count)
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
