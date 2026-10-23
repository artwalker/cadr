(in-package #:cadr-cli)

(defparameter +settings-fallback-keys+
  '(("skill-commands" . "enableSkillCommands")
    ("show-hardware-cursor" . "showHardwareCursor")
    ("editor-padding" . "editorPaddingX")
    ("output-padding" . "outputPad")
    ("autocomplete-max-visible" . "autocompleteMaxVisible")
    ("transport" . "transport")
    ("share-destination" . "sessionShareDestination")
    ("http-idle-timeout" . "httpIdleTimeoutMs")
    ("hide-thinking" . "hideThinkingBlock")
    ("cache-miss-notices" . "showCacheMissNotices")
    ("collapse-changelog" . "collapseChangelog")
    ("quiet-startup" . "quietStartup")
    ("install-telemetry" . "enableInstallTelemetry")
    ("default-project-trust" . "defaultProjectTrust")
    ("double-escape-action" . "doubleEscapeAction")
    ("tree-filter-mode" . "treeFilterMode")
    ("theme" . "theme")))

(defparameter +cache-warming-modes+
  '("off" "streaming" "idle"))

(defun default-agent-directory ()
  ;; Thin forwarder: cadr-core owns the layout decision (including the
  ;; CADR_CODING_AGENT_DIR override); this name stays for CLI callers.
  (cadr-core:coding-agent-directory))

(defun prompt-project-trust
    (directory
     &optional
       (input *standard-input*)
       (output *standard-output*))
  (format
   output
   "Trust project resources in ~A? [y/N] "
   (namestring
    (uiop:ensure-directory-pathname
     directory)))
  (finish-output output)
  (let ((answer
          (read-line input nil "")))
    (member
     (string-downcase
      (string-trim
       '(#\Space #\Tab)
       answer))
     '("y" "yes")
     :test #'string=)))

(defun install-telemetry-enabled-p
    (manager &key (environment :unset))
  ;; pi@4a080252f isInstallTelemetryEnabled. CADR_TELEMETRY wins when the
  ;; variable is set, including an empty string. Unset falls through to
  ;; enableInstallTelemetry. The value check stays inline so it does not
  ;; replace tool-manager's truthy-env-flag-p, which reads a variable name.
  (let ((env
          (if (eq environment :unset)
              (uiop:getenv "CADR_TELEMETRY")
              environment)))
    (if (null env)
        (settings-boolean-value
         manager "enableInstallTelemetry" t)
        (and (stringp env)
             (plusp (length env))
             (or (string= env "1")
                 (member (string-downcase env)
                         '("true" "yes")
                         :test #'string=))
             t))))

(defun settings-boolean-value
    (manager key default &optional nested-key)
  (let ((value
          (if nested-key
              (settings-nested-value
               manager key nested-key :missing)
              (settings-value
               manager key :missing))))
    (if (eq value :missing)
        default
        (eq value t))))

(defun settings-positive-integer-value
    (manager key nested-key default)
  (let ((value
          (settings-nested-value
           manager key nested-key :missing)))
    (if (and (integerp value) (plusp value))
        value
        default)))

(defun settings-compaction-keep-recent-tokens
    (manager &optional model)
  (settings-compaction-token-field
   (settings-value manager "compaction" :missing)
   "keepRecentTokens" model 20000))

(defun settings-compaction-reserve-tokens
    (manager &optional model)
  (settings-compaction-token-field
   (settings-value manager "compaction" :missing)
   "reserveTokens" model 16384))

(defun settings-branch-summary-reserve-tokens
    (manager)
  (settings-positive-integer-value
   manager "branchSummary" "reserveTokens" 16384))

(defun settings-branch-summary-skip-prompt-p
    (manager)
  (settings-boolean-value
   manager "branchSummary" nil "skipPrompt"))

(defun branch-summary-tree-summarize-p
    (manager &key chooser editor)
  (when (settings-branch-summary-skip-prompt-p manager)
    (return-from branch-summary-tree-summarize-p
      (values nil nil nil)))
  (loop
    (let ((choice
            (and chooser
                 (funcall
                  chooser
                  "Summarize branch?"
                  '("No summary"
                    "Summarize"
                    "Summarize with custom prompt")))))
      (cond
        ((null choice)
         (return (values nil t nil)))
        ((string= choice "No summary")
         (return (values nil nil nil)))
        ((string= choice "Summarize with custom prompt")
         (let ((instructions (and editor (funcall editor))))
           (when (and (stringp instructions)
                      (plusp (length instructions)))
             (return (values t nil instructions)))))
        (t
         (return (values t nil nil)))))))

(defun settings-optional-nonempty-string
    (manager key)
  (let ((value (settings-value manager key :missing)))
    (and (stringp value)
         (plusp (length value))
         value)))

(defun settings-shell-path (manager)
  (let ((value
          (settings-optional-nonempty-string
           manager "shellPath")))
    (and value (normalize-path-input value))))

(defun settings-shell-command-prefix (manager)
  (settings-optional-nonempty-string
   manager "shellCommandPrefix"))

(defun settings-session-dir (manager)
  (let ((value
          (settings-optional-nonempty-string
           manager "sessionDir")))
    (and value (normalize-path-input value))))

(defun settings-websocket-connect-timeout-ms (manager)
  (let ((value
          (settings-value
           manager "websocketConnectTimeoutMs"
           :missing)))
    (and (integerp value) (plusp value) value)))

(defun settings-http-proxy (manager)
  (settings-optional-nonempty-string
   manager "httpProxy"))

(defun thinking-budgets-from-json (value)
  (unless (hash-table-p value)
    (return-from thinking-budgets-from-json nil))
  (loop for json-key in '("minimal" "low" "medium" "high")
        for level in '(:minimal :low :medium :high)
        for tokens = (cadr-ai::json-get value json-key :missing)
        ;; Type.Number() keeps 0 and negatives. A missing key stays
        ;; :missing and falls through to the default budget.
        when (realp tokens)
        append (list level tokens)))

(defun settings-thinking-budgets (manager)
  (thinking-budgets-from-json
   (settings-value manager "thinkingBudgets" :missing)))

(defun settings-theme-paths (manager)
  (let ((value (settings-value manager "themes" :missing)))
    (and (vectorp value)
         (every #'stringp value)
         (coerce value 'list))))

(defun settings-skill-paths (manager)
  (let ((value (settings-value manager "skills" :missing)))
    (and (vectorp value)
         (every #'stringp value)
         (coerce value 'list))))

(defun settings-prompt-paths (manager)
  (let ((value (settings-value manager "prompts" :missing)))
    (and (vectorp value)
         (every #'stringp value)
         (coerce value 'list))))

(defun settings-extension-paths (manager)
  (let ((value (settings-value manager "extensions" :missing)))
    (and (vectorp value)
         (every #'stringp value)
         (coerce value 'list))))

(defun stream-function-with-thinking-budgets
    (stream-function thinking-budgets-function)
  (lambda (provider model context on-event &rest options)
    (let ((request-options (copy-list options)))
      (unless (member :thinking-budgets request-options :test #'eq)
        (setf (getf request-options :thinking-budgets)
              (funcall thinking-budgets-function)))
      (apply stream-function
             provider model context on-event request-options))))

(defun stream-function-with-websocket-connect-timeout
    (stream-function timeout-ms-function)
  (lambda (provider model context on-event &rest options)
    (let ((request-options (copy-list options)))
      (unless (member :websocket-connect-timeout-ms request-options
                      :test #'eq)
        (setf (getf request-options :websocket-connect-timeout-ms)
              (funcall timeout-ms-function)))
      (apply stream-function
             provider model context on-event request-options))))

(defun stream-function-with-http-proxy
    (stream-function http-proxy-function)
  (lambda (provider model context on-event &rest options)
    (let ((request-options (copy-list options)))
      (unless (member :http-proxy request-options :test #'eq)
        (setf (getf request-options :http-proxy)
              (funcall http-proxy-function)))
      (apply stream-function
             provider model context on-event request-options))))

(defun stream-function-with-http-idle-timeout
    (stream-function timeout-ms-function)
  (lambda (provider model context on-event &rest options)
    (let* ((request-options (copy-list options))
           (explicit-p
             (member :timeout-ms request-options :test #'eq))
           (explicit
             (and explicit-p
                  (getf request-options :timeout-ms)))
           (idle (funcall timeout-ms-function)))
      ;; pi@4a080252f sdk.ts buildRequestOptions. Request timeoutMs, then
      ;; retry.provider.timeoutMs, then httpIdleTimeoutMs. Idle 0 becomes
      ;; 2147483647. A numeric 0 is a real timeout.
      (unless (and explicit-p (numberp explicit))
        (setf (getf request-options :timeout-ms)
              (if (and (integerp idle) (zerop idle))
                  2147483647
                  idle))
        (setf explicit nil
              explicit-p nil))
      (unless (member :read-timeout request-options :test #'eq)
        (setf (getf request-options :read-timeout)
              (cond
                ;; OpenAI/Anthropic SDKs arm setTimeout(abort, timeout).
                ;; 0 is a real 0ms timeout, not "no timeout".
                ((and explicit-p (realp explicit) (>= explicit 0))
                 (/ explicit 1000))
                ((and explicit-p (numberp explicit))
                 nil)
                (t
                 (and (integerp idle)
                      (plusp idle)
                      (/ idle 1000))))))
      (apply stream-function
             provider model context on-event request-options))))

(defun settings-retry-settings (manager)
  ;; pi@4a080252f getRetrySettings reads the top-level retry object.
  ;; getProviderRetrySettings reads retry.provider and does not fill
  ;; maxRetries. Merging the two objects made provider.maxRetries
  ;; replace the agent count, and the missing provider count became 3.
  (let* ((retry
           (settings-value
            manager "retry" (empty-json-object)))
         (provider
           (and (hash-table-p retry)
                (cadr-ai::json-get
                 retry "provider"
                 (empty-json-object))))
         (retry-table-p (hash-table-p retry)))
    (list
     :enabled-p
     (eq t
         (if retry-table-p
             (cadr-ai::json-get retry "enabled" t)
             t))
     :max-retries
     (retry-provider-number retry "maxRetries" 3)
     :base-delay-ms
     (if retry-table-p
         (cadr-ai::json-get retry "baseDelayMs" 2000)
         2000)
     :max-agent-delay-ms
     (retry-provider-number
      retry "maxAgentDelayMs" 60000)
     :provider-max-retries
     (retry-provider-number provider "maxRetries" nil)
     :max-retry-delay-ms
     (retry-provider-number
      provider "maxRetryDelayMs" 60000)
     :timeout-ms
     (retry-provider-number provider "timeoutMs" nil))))

(defun stream-function-with-provider-retry
    (stream-function retry-settings-function)
  (lambda (provider model context on-event &rest options)
    (let ((request-options (copy-list options))
          (settings (funcall retry-settings-function)))
      ;; pi@4a080252f sdk.ts buildRequestOptions passes
      ;; provider maxRetries through. provider-retry.ts then uses
      ;; options.maxRetries ?? 0, so an unset field is one attempt.
      ;; Agent retries stay on the top-level :max-retries.
      (unless (member :max-retries request-options :test #'eq)
        (let ((retries (getf settings :provider-max-retries)))
          (setf (getf request-options :max-retries)
                (if (realp retries) retries 0))))
      (unless (member :max-retry-delay-ms request-options :test #'eq)
        (setf (getf request-options :max-retry-delay-ms)
              (getf settings :max-retry-delay-ms)))
      (let ((timeout-ms (getf settings :timeout-ms)))
        (when (and (not (member :timeout-ms request-options :test #'eq))
                   (numberp timeout-ms))
          (setf (getf request-options :timeout-ms) timeout-ms)))
      (apply stream-function
             provider model context on-event request-options))))

(defun resolve-session-directory
    (&key cli-directory settings-directory
          (cwd (uiop:getcwd)))
  ;; pi@4a080252f main.ts: --session-dir, then
  ;; CADR_CODING_AGENT_SESSION_DIR, then settings sessionDir.
  ;; An empty environment value does not override settings.
  (let* ((env
           (funcall cadr-core::*path-environment-function*
                    "CADR_CODING_AGENT_SESSION_DIR"))
         (env-directory
           (and (null cli-directory)
                (stringp env)
                (plusp (length env))
                env))
         (chosen (or cli-directory env-directory settings-directory)))
    (if chosen
        (uiop:ensure-directory-pathname
         (merge-pathnames
          (if env-directory
              (cadr-core::expand-config-path-override env-directory)
              (pathname chosen))
          cwd))
        (cadr-agent:default-session-directory))))

(defun settings-show-terminal-progress-p (manager)
  (let ((terminal-settings
          (settings-value
           manager "terminal"
           (empty-json-object))))
    (and
     (hash-table-p terminal-settings)
     (eq t
         (cadr-ai::json-get
          terminal-settings
          "showTerminalProgress"
         nil)))))

(defun settings-show-terminal-images-p (manager)
  (let ((terminal
          (settings-value
           manager "terminal"
           (empty-json-object))))
    (if (hash-table-p terminal)
        (eq t
            (cadr-ai::json-get
             terminal "showImages" t))
        t)))

(defun settings-terminal-image-width-cells (manager)
  (let* ((terminal
           (settings-value
            manager "terminal"
            (empty-json-object)))
         (value
           (and
            (hash-table-p terminal)
            (cadr-ai::json-get
             terminal "imageWidthCells" 60))))
    (if (member value '(60 80 120)) value 60)))

(defun settings-clear-on-shrink-p (manager)
  ;; pi@4a080252f settings-manager.ts:1093-1099 gives an explicit setting
  ;; precedence over the environment and defaults to false.
  (settings-boolean-value
   manager "terminal"
   (string= (or (uiop:getenv "CADR_CLEAR_ON_SHRINK") "") "1")
   "clearOnShrink"))

(defun settings-terminal-theme-mode (manager)
  (let ((configured
          (settings-value manager "theme" nil)))
    (cond
      ((null configured) :detect-once)
      ((parse-auto-theme-setting configured) :auto)
      (t :fixed))))

(defun settings-choice-value
    (manager key choices default)
  (let ((value
          (settings-value manager key default)))
    (if (member value choices :test #'equal)
        value
        default)))

(defun settings-tui-mode (manager)
  ;; pi@4a080252f settings-manager.ts:1256-1257 — only the exact string
  ;; "regular" selects regular; everything else (including unset) is
  ;; SETTINGS_DEFAULTS.tuiMode, which is fullscreen since v1.0.0.
  (if (string= (settings-value manager "tuiMode" "") "regular")
      :regular
      :fullscreen))

(defun parse-default-tools-setting (value)
  ;; pi@4a080252f settings-manager.ts getDefaultTools / resolveDefaultTools:
  ;; a string array resolves plain names and +name/-name overlays; else absent.
  (and (vectorp value)
       (every #'stringp value)
       (resolve-default-tools (coerce value 'list))))

(defun settings-default-tools (manager)
  (parse-default-tools-setting
   (settings-value manager "defaultTools")))

(defun settings-fullscreen-scrollbar (manager)
  ;; pi@4a080252f settings-manager.ts:1138-1141 — "always"/"hidden" pass
  ;; through; everything else falls back to "auto".  No effect in
  ;; regular TUI mode.
  (settings-choice-value
   manager "fullscreenScrollbar" '("auto" "always" "hidden") "auto"))

(defun settings-session-share-destination (manager)
  ;; pi@4a080252f settings-manager.ts getSessionShareDestination
  (settings-choice-value
   manager "sessionShareDestination"
   '("auto" "gist" "radius") "auto"))

(defun settings-fullscreen-exit-output (manager)
  ;; Baseline v1.4.0 settings-manager.ts getFullscreenExitOutput.
  (if (string= (settings-value manager "fullscreenExitOutput" "")
               "resume-hint")
      :resume-hint
      :transcript))

(defun settings-fullscreen-copy-on-select-p (manager)
  ;; pi@4a080252f settings-manager.ts getFullscreenCopyOnSelect: default true.
  (let ((value
          (settings-value manager "fullscreenCopyOnSelect" t)))
    (not (eq value nil))))

(defun settings-fullscreen-wheel-scroll-lines (manager)
  ;; pi@4a080252f settings-manager.ts getFullscreenWheelScrollLines.
  ;; A finite number is floored and clamped to 1..100. Everything else,
  ;; including numeric strings, is the default "auto".
  (let ((value
          (settings-value
           manager "fullscreenWheelScrollLines" :missing)))
    (cond
      ((or (eq value :missing)
           (and (stringp value) (string= value "auto")))
       :auto)
      ((realp value)
       (max 1 (min 100 (floor value))))
      (t :auto))))

(defun settings-assign-fullscreen-wheel-scroll-lines
    (manager value)
  ;; pi@4a080252f setFullscreenWheelScrollLines. The stored value is
  ;; already clamped, so a later read does not reinterpret 0 or 1000.
  (let ((lines
          (cond
            ((or (eq value :auto)
                 (and (stringp value) (string= value "auto")))
             :auto)
            ((realp value)
             (max 1 (min 100 (floor value))))
            ((stringp value)
             (let ((parsed (ignore-errors (parse-integer value))))
               (if parsed
                   (max 1 (min 100 parsed))
                   :auto)))
            (t :auto))))
    (settings-set
     manager "fullscreenWheelScrollLines"
     (if (eq lines :auto) "auto" lines)
     :scope :global)
    lines))

(defun settings-show-hardware-cursor-p
    (manager &key (environment :unset))
  ;; pi@4a080252f getShowHardwareCursor. An explicit boolean wins,
  ;; including false. Only a missing key consults CADR_HARDWARE_CURSOR,
  ;; and only the exact string "1" enables it.
  (let ((value
          (settings-value
           manager "showHardwareCursor" :missing)))
    (if (eq value :missing)
        (let ((env
                (if (eq environment :unset)
                    (uiop:getenv "CADR_HARDWARE_CURSOR")
                    environment)))
          (and (stringp env) (string= env "1") t))
        (eq value t))))

(defun settings-terminal-capability-overrides (manager)
  ;; pi@4a080252f settings-manager.ts getTerminalCapabilityOverrides.
  (let ((terminal
          (settings-value manager "terminal"))
        (overrides nil))
    (when (hash-table-p terminal)
      (when (cadr-ai::json-present-p terminal "images")
        (let ((images
                (cadr-ai::json-get terminal "images")))
          (cond
            ((or (string= images "kitty")
                 (string= images "iterm2"))
             (setf (getf overrides :images)
                   (intern (string-upcase images) :keyword)))
            ((or (eq images nil)
                 (eq images :false)
                 (string= images "none"))
             (setf (getf overrides :images) nil)))))
      (when (cadr-ai::json-present-p terminal "trueColor")
        (let ((value
                (cadr-ai::json-get terminal "trueColor")))
          (when (or (eq value t) (eq value nil))
            (setf (getf overrides :true-color-p) value))))
      (when (cadr-ai::json-present-p terminal "hyperlinks")
        (let ((value
                (cadr-ai::json-get terminal "hyperlinks")))
          (when (or (eq value t) (eq value nil))
            (setf (getf overrides :hyperlinks-p) value)))))
    overrides))

(defun settings-mermaid-rendering-mode (manager)
  ;; pi@4a080252f settings-manager.ts:1252-1255 — markdown.mermaid is
  ;; nested; "off"/"final" pass through, anything else is "streaming".
  (let ((mode
          (settings-nested-value
           manager "markdown" "mermaid" "streaming")))
    (if (member mode '("off" "final" "streaming")
                :test #'string=)
        mode
        "streaming")))

(defun settings-markdown-code-block-indent (manager)
  (let ((value
          (settings-nested-value
           manager "markdown" "codeBlockIndent" :missing)))
    (if (stringp value)
        value
        "  ")))

(defun settings-last-changelog-version (manager)
  (let ((value
          (settings-value
           manager "lastChangelogVersion" :missing)))
    (and (stringp value) value)))

(defun settings-external-editor-command
    (manager &optional (environment-function #'uiop:getenv)
                       (windows-p (uiop:os-windows-p)))
  ;; v1.4.0 settings-manager.ts getExternalEditorCommand: a trimmed
  ;; externalEditor string, else VISUAL, else EDITOR, else notepad
  ;; when process.platform is win32 and nano otherwise. Env values
  ;; are not trimmed; only an empty string is absent.
  (let ((configured
          (settings-value manager "externalEditor" :missing)))
    (if (and (stringp configured)
             (plusp
              (length
               (string-trim
                '(#\Space #\Tab #\Newline #\Return)
                configured))))
        configured
        (or (let ((visual
                    (funcall environment-function "VISUAL")))
              (and (stringp visual)
                   (plusp (length visual))
                   visual))
            (let ((editor
                    (funcall environment-function "EDITOR")))
              (and (stringp editor)
                   (plusp (length editor))
                   editor))
            (if windows-p
                "notepad"
                "nano")))))

(defun settings-npm-command (manager)
  (let ((value (settings-value manager "npmCommand" :missing)))
    (and (vectorp value)
         (plusp (length value))
         (every #'stringp value)
         (plusp (length (aref value 0)))
         (coerce value 'list))))

(defun http-idle-timeout-label (timeout-ms)
  (or
   (cdr
    (assoc timeout-ms
           '((30000 . "30 sec")
             (60000 . "1 min")
             (120000 . "2 min")
             (300000 . "5 min")
             (0 . "disabled"))))
   (format nil "~,3G sec"
           (/ timeout-ms 1000.0))))

(defun settings-cache-warming-mode (manager)
  ;; Baseline settings-manager.ts getCacheWarmingMode: globalSettings only.
  (let ((mode
          (cadr-ai::json-get
           (settings-manager-global manager)
           "cacheWarming"
           :missing)))
    (if (and (not (eq mode :missing))
             (member mode +cache-warming-modes+ :test #'equal))
        mode
        "streaming")))

(defun settings-set-cache-warming-mode (manager mode)
  (unless (member mode +cache-warming-modes+ :test #'equal)
    (error "Invalid cacheWarming mode ~S" mode))
  (settings-set manager "cacheWarming" mode :scope :global)
  mode)

(defun default-project-trust-label (value)
  (cond
    ((string= value "always") "Always trust")
    ((string= value "never") "Never trust")
    (t "Ask")))

(defun cli-thinking-level-for-model-switch
    (agent settings-manager model
     &optional explicit-level)
  (if explicit-level
      explicit-level
      (or (and model
               (settings-model-thinking-level
                settings-manager
                (cadr-ai:model-provider model)
                (cadr-ai:model-id model)))
          (settings-default-thinking-level settings-manager)
          (cadr-agent::agent-thinking-level agent)
          +default-thinking-level+)))

(defun model-thinking-overrides-summary (settings-manager)
  (let ((count
          (length
           (settings-all-model-thinking-levels
            settings-manager))))
    (if (zerop count)
        "none"
        (format nil "~D configured" count))))

(defun set-cli-thinking-level
    (agent settings-manager level
     &key (persist nil))
  (let* ((previous
           (cadr-agent::agent-thinking-level agent))
         (effective
           (cadr-ai:clamp-thinking-level
            (cadr-agent:agent-model agent)
            level)))
    (unless (eq previous effective)
      (setf
       (cadr-agent::agent-thinking-level agent)
       effective)
      (when (cadr-agent:agent-session agent)
        (cadr-agent:session-append-thinking-level-change
         (cadr-agent:agent-session agent)
         (string-downcase
          (symbol-name effective))))
      (run-session-lifecycle
       agent :thinking-level-select
       :level effective
       :previous-level previous))
    (when persist
      (settings-set-default-thinking-level
       settings-manager level))
    effective))

(defun sync-agent-settings-from-manager
    (agent settings-manager)
  (setf
   (cadr-agent::agent-auto-compact-p agent)
   (settings-boolean-value
    settings-manager
    "compaction" t "enabled")
   (cadr-agent::agent-compaction-settings-function agent)
   (lambda (model)
     (values
      (settings-compaction-reserve-tokens
       settings-manager model)
      (settings-compaction-keep-recent-tokens
       settings-manager model)
      (settings-boolean-value
       settings-manager "compaction" t "enabled")))
   (cadr-agent::agent-compaction-keep-recent-tokens
    agent)
   (settings-compaction-keep-recent-tokens
    settings-manager)
   (cadr-agent::agent-compaction-reserve-tokens
    agent)
   (settings-compaction-reserve-tokens
    settings-manager)
   (cadr-agent:agent-steering-mode agent)
   (if
       (string=
        "all"
        (settings-choice-value
         settings-manager "steeringMode"
         '("one-at-a-time" "all")
         "one-at-a-time"))
       :all
       :one-at-a-time)
   (cadr-agent:agent-follow-up-mode agent)
   (if
       (string=
        "all"
        (settings-choice-value
         settings-manager "followUpMode"
         '("one-at-a-time" "all")
         "one-at-a-time"))
       :all
       :one-at-a-time))
  agent)

(defun reload-cli-runtime
    (agent settings-manager
     &key
       extension-reload-function
       resource-reload-function
       system-prompt-function
       model-refresh-function
       keybindings-reload-function
       completion-function)
  (run-session-lifecycle
   agent :session-shutdown
   :reason :reload)
  (settings-reload settings-manager)
  (clear-config-value-cache)
  (sync-agent-settings-from-manager
   agent settings-manager)
  (when extension-reload-function
    (funcall extension-reload-function))
  (let ((resources
          (and resource-reload-function
               (funcall
                resource-reload-function))))
    (when system-prompt-function
      (multiple-value-bind (prompt options)
          (funcall system-prompt-function resources)
        (cadr-agent::replace-agent-system-prompt
         agent prompt options)))
    (when (typep resources 'resource-snapshot)
      (cadr-agent::replace-agent-prompt-catalogs
       agent
       (resource-snapshot-skills resources)
       (resource-snapshot-prompts resources)))
    (when model-refresh-function
      (funcall model-refresh-function))
    (when keybindings-reload-function
      (funcall keybindings-reload-function))
    (run-session-lifecycle
     agent :session-start
     :reason :reload)
    (when completion-function
      (funcall
       completion-function
       "Reloaded keybindings, extensions, skills, prompts, themes, and context files"))
    resources))

(defun make-cli-settings-selector-state
    (settings-manager agent resources
     &key keybindings available-models
       (supports-images-p
         (not
          (null
           (cadr-tui:terminal-capabilities-images
            (cadr-tui:get-terminal-capabilities))))))
  (let* ((terminal
           (settings-value
            settings-manager
            "terminal"
            (empty-json-object)))
         (theme-names
           (remove-duplicates
            (append
             '("system" "dark" "light")
             (loop
               for theme
                 in (and resources
                         (resource-snapshot-themes
                          resources))
               for name = (getf theme :name)
               when (stringp name)
                 collect name))
            :test #'string=))
         (current-theme
           (let ((configured
                   (settings-value
                    settings-manager "theme" "dark")))
             (if (or (member configured theme-names
                             :test #'string=)
                     (parse-auto-theme-setting configured))
                 configured
                 "dark")))
         (follow-up-key
           (format-key-text
            (or
             (and keybindings
                  (first
                   (cadr-tui:keybinding-keys
                    keybindings "app.message.followUp")))
             (and keybindings
                  (let ((binding
                          (assoc
                           "app.message.followUp"
                           (cadr-tui::keybindings-manager-user-bindings
                            keybindings)
                           :test #'string=)))
                    (let ((value (cdr binding)))
                      (if (listp value)
                          (first value)
                          value))))
             "alt+enter")
            :capitalize-p t))
         (first-option
           (make-settings-option
            :id "autocompact"
            :label "Auto-compact"
            :description
            "Automatically compact context when it gets too large"
            :value
            (cadr-agent::agent-auto-compact-p agent)
            :values (list t nil)))
         (rest-options
           (list
            (make-settings-option
             :id "auto-resize-images"
             :label "Auto-resize images"
             :description
             "Resize large images to 2000x2000 max for better model compatibility"
             :value
             (settings-auto-resize-images-p
              settings-manager)
             :values (list t nil))
            (make-settings-option
             :id "block-images"
             :label "Block images"
             :description
             "Prevent images from being sent to LLM providers"
             :value
             (settings-block-images-p
              settings-manager)
             :values (list t nil))
            (make-settings-option
             :id "skill-commands"
             :label "Skill commands"
             :description
             "Register skills as /skill:name commands"
             :value
             (settings-boolean-value
              settings-manager
              "enableSkillCommands" t)
             :values (list t nil))
            (make-settings-option
             :id "show-hardware-cursor"
             :label "Show hardware cursor"
             :description
             "Show the terminal cursor while still positioning it for IME support"
             :value
             (settings-show-hardware-cursor-p
              settings-manager)
             :values (list t nil))
            (make-settings-option
             :id "editor-padding"
             :label "Editor padding"
             :description
             "Horizontal padding for input editor (0-3)"
             :value
             (settings-choice-value
              settings-manager "editorPaddingX"
              '(0 1 2 3) 0)
             :values '(0 1 2 3))
            (make-settings-option
             :id "output-padding"
             :label "Output padding"
             :description
             "Horizontal padding for transcript content."
             :value
             (settings-output-padding
              settings-manager)
             :values '(0 1))
            (make-settings-option
             :id "autocomplete-max-visible"
             :label "Autocomplete max items"
             :description
             "Max visible items in autocomplete dropdown (3-20)"
             :value
             (settings-choice-value
              settings-manager
              "autocompleteMaxVisible"
              '(3 5 7 10 15 20) 5)
             :values '(3 5 7 10 15 20))
            (make-settings-option
             :id "clear-on-shrink"
             :label "Clear on shrink"
             :description
             "Clear empty rows when content shrinks (may cause flicker)"
            :value
             (settings-clear-on-shrink-p
              settings-manager)
             :values (list t nil))
            (make-settings-option
             :id "terminal-progress"
             :label "Terminal progress"
             :description
             "Show OSC 9;4 progress indicators in the terminal tab bar"
             :value
             (if (hash-table-p terminal)
                 (eq t
                     (cadr-ai::json-get
                      terminal "showTerminalProgress"
                      nil))
                 nil)
             :values (list t nil))
            (make-settings-option
             :id "steering-mode"
             :label "Steering mode"
             :description
             "Enter while streaming queues steering messages. 'one-at-a-time': deliver one, wait for response. 'all': deliver all at once."
             :value
             (cadr-agent:agent-steering-mode agent)
             :values '(:one-at-a-time :all))
            (make-settings-option
             :id "follow-up-mode"
             :label "Follow-up mode"
             :description
             (format
              nil
              "~A queues follow-up messages until agent stops. 'one-at-a-time': deliver one, wait for response. 'all': deliver all at once."
              follow-up-key)
             :value
             (cadr-agent:agent-follow-up-mode agent)
             :values '(:one-at-a-time :all))
            (make-settings-option
             :id "transport"
             :label "Transport"
             :description
             "Preferred transport for providers that support multiple transports"
             :value
             (settings-choice-value
              settings-manager "transport"
              '("sse" "websocket"
                "websocket-cached" "auto")
              "auto")
             :values
             '("sse" "websocket"
               "websocket-cached" "auto"))
            (make-settings-option
             :id "share-destination"
             :label "Session share destination"
             :description
             "Where to upload sessions with /share (auto prefers Radius when authenticated, otherwise GitHub Gist)"
             :value
             (settings-session-share-destination
              settings-manager)
             :values '("auto" "gist" "radius"))
            (make-settings-option
             :id "http-idle-timeout"
             :label "HTTP idle timeout"
             :description
             "Maximum idle gap while waiting for HTTP headers or body chunks. Disable for local models that pause longer than five minutes."
             :value
             (settings-http-idle-timeout-ms
              settings-manager)
             :values
             '(30000 60000 120000 300000 0)
             :format-function
             #'http-idle-timeout-label)
            (make-settings-option
             :id "cache-warming-mode"
             :label "Cache warming"
             :description
             "off; streaming while the agent runs; idle also between runs while continuation stays profitable"
             :value
             (settings-cache-warming-mode settings-manager)
             :values +cache-warming-modes+)
            (make-settings-option
             :id "hide-thinking"
             :label "Hide thinking"
             :description
             "Hide thinking blocks in assistant responses"
             :value
             (settings-boolean-value
              settings-manager
              "hideThinkingBlock" nil)
            :values (list t nil))
           ;; pi@4a080252f settings-selector.ts:539-546
           (make-settings-option
            :id "mermaid-rendering"
            :label "Mermaid diagrams"
            :description
            "Render Mermaid code blocks as Unicode diagrams"
            :value
            (settings-mermaid-rendering-mode settings-manager)
            :values '("off" "final" "streaming"))
           (make-settings-option
            :id "cache-miss-notices"
             :label "Cache miss notices"
             :description
             "Show transcript notices for significant prompt-cache misses"
             :value
             (settings-boolean-value
              settings-manager
              "showCacheMissNotices" nil)
             :values (list t nil))
            (make-settings-option
             :id "collapse-changelog"
             :label "Collapse changelog"
             :description
             "Show condensed changelog after updates"
             :value
             (settings-boolean-value
              settings-manager
              "collapseChangelog" nil)
             :values (list t nil))
            (make-settings-option
             :id "quiet-startup"
             :label "Quiet startup"
             :description
             "Disable verbose printing at startup (header: keep only the startup header)"
             :value
             (let ((quiet
                     (settings-quiet-startup
                      settings-manager)))
               (cond
                 ((eq quiet t) "true")
                 ((eq quiet :header) "header")
                 (t "false")))
             :values (list "true" "header" "false"))
            (make-settings-option
             :id "install-telemetry"
             :label "Install telemetry"
             :description
             "Send an anonymous version/update ping after changelog-detected updates"
             :value
             (settings-boolean-value
              settings-manager
              "enableInstallTelemetry" t)
             :values (list t nil))
            (make-settings-option
             :id "default-project-trust"
             :label "Default project trust"
             :description
             "Fallback behavior when no extension or saved trust decision decides project trust"
             :value
             (settings-choice-value
              settings-manager
              "defaultProjectTrust"
              '("ask" "always" "never")
              "ask")
             :values '("ask" "always" "never")
             :format-function
             #'default-project-trust-label)
            (make-settings-option
             :id "double-escape-action"
             :label "Double-escape action"
             :description
             "Action when pressing Escape twice with empty editor"
             :value
             (settings-choice-value
              settings-manager
              "doubleEscapeAction"
              '("tree" "fork" "none")
              "tree")
             :values '("tree" "fork" "none"))
            (make-settings-option
             :id "tree-filter-mode"
             :label "Tree filter mode"
             :description
             "Default filter when opening /tree"
             :value
             (settings-choice-value
              settings-manager
              "treeFilterMode"
              '("default" "no-tools" "user-only"
                "labeled-only" "all")
              "default")
             :values
             '("default" "no-tools" "user-only"
               "labeled-only" "all"))
            (make-settings-option
             :id "warnings"
             :label "Warnings"
             :description
             "Enable or disable individual warnings"
             :value
             (list
              :anthropic-extra-usage
              (settings-boolean-value
               settings-manager
               "warnings" t
               "anthropicExtraUsage"))
             :format-function
             (lambda (value)
               (declare (ignore value))
               "configure")
             :submenu :warnings)
            (make-settings-option
             :id "model-thinking"
             :label "Default thinking level per model"
             :description
             (format
              nil
              "Override the default thinking level for specific models. ~A cycles in-session."
              (format-key-text
               (or
                (and keybindings
                     (first
                      (cadr-tui:keybinding-keys
                       keybindings "app.thinking.cycle")))
                "ctrl+t")
               :capitalize-p t))
             :value
             (list
              :overrides
              (settings-all-model-thinking-levels
               settings-manager)
              :current-model
              (cadr-agent:agent-model agent)
              :default-provider
              (settings-default-provider settings-manager)
              :default-model
              (settings-default-model settings-manager)
              :global-default
              (or
               (settings-default-thinking-level
                settings-manager)
               +default-thinking-level+))
             :format-function
             (lambda (value)
               (declare (ignore value))
               (model-thinking-overrides-summary
                settings-manager))
             :submenu :model-thinking)
           ;; pi@4a080252f settings-selector.ts:634-646
           (make-settings-option
            :id "tui-mode"
            :label "TUI mode"
            :description
            "Interface layout; regular mode uses the terminal's normal scrollback"
            :value
            (string-downcase
             (symbol-name
              (settings-tui-mode settings-manager)))
            :values '("regular" "fullscreen"))
           (make-settings-option
            :id "fullscreen-exit-output"
            :label "Fullscreen exit output"
            :description
            "Print the transcript or only a session resume hint when exiting fullscreen mode"
            :value
            (string-downcase
             (symbol-name
              (settings-fullscreen-exit-output settings-manager)))
            :values '("transcript" "resume-hint"))
           (make-settings-option
            :id "fullscreen-scrollbar"
            :label "Fullscreen scrollbar"
            :description
            "Scrollbar behavior in fullscreen mode; has no effect in regular mode"
            :value
            (settings-fullscreen-scrollbar settings-manager)
            :values '("auto" "always" "hidden"))
           (make-settings-option
            :id "fullscreen-copy-on-select"
            :label "Fullscreen copy on select"
            :description
            "Automatically copy selected text in fullscreen mode; disable to copy selections with Ctrl+X"
            :value
            (if (settings-fullscreen-copy-on-select-p
                 settings-manager)
                "true"
                "false")
            :values '("true" "false"))
           (make-settings-option
            :id "fullscreen-wheel-scroll-lines"
            :label "Fullscreen wheel scrolling"
            :description
            "Lines per mouse-wheel event in fullscreen mode; 'auto' speeds up fast wheel spins where the terminal does not"
            :value
            (let ((lines
                    (settings-fullscreen-wheel-scroll-lines
                     settings-manager)))
              (if (eq lines :auto)
                  "auto"
                  (princ-to-string lines)))
            :values
            (let* ((current
                     (settings-fullscreen-wheel-scroll-lines
                      settings-manager))
                   (numbers
                     (remove-duplicates
                      (append
                       '(1 2 3 5 10)
                       (and (integerp current)
                            (list current)))
                      :test #'=)))
              (cons
               "auto"
               (mapcar #'princ-to-string
                       (sort (copy-list numbers) #'<)))))
           (make-settings-option
            :id "theme"
             :label "Theme"
             :description
             "Color theme for the interface"
             :value current-theme
             :values theme-names
             :submenu :theme)))
         (options
           (append
            (list first-option)
            (when supports-images-p
              (list
               (make-settings-option
                :id "show-images"
                :label "Show images"
                :description "Render images inline in terminal"
                :value
                (settings-show-terminal-images-p
                 settings-manager)
                :values (list t nil))
               (make-settings-option
                :id "image-width-cells"
                :label "Image width"
                :description
                "Preferred inline image width in terminal cells"
                :value
                (settings-terminal-image-width-cells
                 settings-manager)
                :values '(60 80 120))))
            rest-options)))
      (make-settings-selector-state
     :options options
     :theme-names theme-names
     :current-theme current-theme
     :terminal-theme
     (theme-detection-theme
      (detect-background-from-environment))
     :keybindings keybindings
     :available-models
     (copy-list (or available-models nil))
     :change-callback
     (lambda (id value)
       (cond
         ((string= id "autocompact")
          (settings-set-nested
           settings-manager
           "compaction" "enabled" value
           :scope :global)
          (setf
           (cadr-agent::agent-auto-compact-p agent)
           value))
         ((string= id "auto-resize-images")
          (settings-set-nested
           settings-manager
           "images" "autoResize" value
           :scope :global))
         ((string= id "show-images")
          (settings-set-nested
           settings-manager
           "terminal" "showImages" value
           :scope :global))
         ((string= id "image-width-cells")
          (settings-set-nested
           settings-manager
           "terminal" "imageWidthCells" value
           :scope :global))
         ((string= id "block-images")
          (settings-set-nested
           settings-manager
           "images" "blockImages" value
           :scope :global))
         ((string= id "clear-on-shrink")
          (settings-set-nested
           settings-manager
           "terminal" "clearOnShrink" value
           :scope :global))
         ((string= id "terminal-progress")
          (settings-set-nested
           settings-manager
           "terminal" "showTerminalProgress"
           value :scope :global))
         ((string= id "anthropic-extra-usage")
          (settings-set-nested
           settings-manager
           "warnings" "anthropicExtraUsage"
           value :scope :global))
         ((string= id "mermaid-rendering")
          (settings-set-nested
           settings-manager
           "markdown" "mermaid" value
           :scope :global))
         ((string= id "tui-mode")
          ;; pi@4a080252f interactive-mode.ts:4557-4567: switch the
          ;; running renderer first, persist only on success.
          (if *tui-mode-switch-hook*
              (when (funcall *tui-mode-switch-hook* value)
                (settings-set
                 settings-manager "tuiMode" value
                 :scope :global))
              (settings-set
               settings-manager "tuiMode" value
               :scope :global)))
         ((string= id "fullscreen-exit-output")
          (settings-set
           settings-manager "fullscreenExitOutput" value
           :scope :global))
         ((string= id "fullscreen-scrollbar")
          (settings-set
           settings-manager "fullscreenScrollbar" value
           :scope :global))
         ((string= id "fullscreen-copy-on-select")
          (let ((enabled (string= value "true")))
            (settings-set
             settings-manager "fullscreenCopyOnSelect" enabled
             :scope :global)
            (when *fullscreen-copy-on-select-hook*
              (funcall *fullscreen-copy-on-select-hook* enabled))))
         ((string= id "fullscreen-wheel-scroll-lines")
          (let ((lines
                  (settings-assign-fullscreen-wheel-scroll-lines
                   settings-manager value)))
            (when *fullscreen-wheel-scroll-lines-hook*
              (funcall
               *fullscreen-wheel-scroll-lines-hook*
               lines))))
         ((string= id "steering-mode")
          (setf
           (cadr-agent:agent-steering-mode agent)
           value)
          (settings-set
           settings-manager "steeringMode"
           (string-downcase
            (symbol-name value))
           :scope :global))
         ((string= id "follow-up-mode")
          (setf
           (cadr-agent:agent-follow-up-mode agent)
           value)
          (settings-set
           settings-manager "followUpMode"
           (string-downcase
            (symbol-name value))
           :scope :global))
         ((string= id "cache-warming-mode")
          (settings-set-cache-warming-mode
           settings-manager value))
         ((string= id "model-thinking-level")
          (let* ((model-key (getf value :model-key))
                 (model
                   (find model-key available-models
                         :key
                         (lambda (candidate)
                           (model-setting-key
                            (cadr-ai:model-provider candidate)
                            (cadr-ai:model-id candidate)))
                         :test #'string=))
                 (level (getf value :level)))
            (when model
              (if (eq level :clear)
                  (settings-remove-model-thinking-level
                   settings-manager
                   (cadr-ai:model-provider model)
                   (cadr-ai:model-id model))
                  (settings-set-model-thinking-level
                   settings-manager
                   (cadr-ai:model-provider model)
                   (cadr-ai:model-id model)
                   level))
              (when
                  (and
                   (cadr-agent:agent-model agent)
                   (cadr-ai:models-equal-p
                    model
                    (cadr-agent:agent-model agent)))
                (set-cli-thinking-level
                 agent settings-manager
                 (if (eq level :clear)
                     (or
                      (settings-default-thinking-level
                       settings-manager)
                      +default-thinking-level+)
                     level))))))
         ((string= id "quiet-startup")
          (settings-set
           settings-manager "quietStartup"
           (cond
             ((equal value "header") "header")
             ((equal value "true") t)
             (t nil))
           :scope :global))
         (t
          (let ((key
                  (cdr
                   (assoc
                    id +settings-fallback-keys+
                    :test #'string=))))
            (when key
              (settings-set
               settings-manager key value
               :scope :global)))))))))

(defun resolve-cli-system-prompt
    (command snapshot tools cwd)
  (let* ((snapshot-system
           (resource-snapshot-system-prompt-path
            snapshot))
         (custom-source
           (or
            (cli-arguments-system-prompt command)
            snapshot-system))
         (append-sources
           (append
            (when
                (resource-snapshot-append-system-prompt-path
                 snapshot)
              (list
               (resource-snapshot-append-system-prompt-path
                snapshot)))
            (cli-arguments-append-system-prompts
             command)))
         (append-text
           (when append-sources
             (format
              nil "~{~A~^~%~%~}"
              (mapcar
               (lambda (source)
                 (resolve-system-prompt source "append system prompt"))
               append-sources))))
         (options
            (list
            :custom-prompt
            (and custom-source
                 (resolve-system-prompt custom-source "system prompt"))
            :selected-tools
            (mapcar #'cadr-ai:tool-name tools)
            :tool-snippets
            (tool-prompt-snippets tools)
            :prompt-guidelines
            (tool-prompt-guidelines tools)
            :append-system-prompt append-text
            :cwd
            (namestring
             (uiop:ensure-directory-pathname cwd))
            :context-files
            (resource-snapshot-context-files snapshot)
            :skills
            (resource-snapshot-skills snapshot))))
    (values
     (apply #'build-system-prompt options)
     (copy-tree options))))

(defun settings-compaction-token-field
    (compaction field model default)
  ;; pi@4a080252f settings-manager.ts getCompactionTokenSetting.
  ;; Override, then the ordinary compaction field, then DEFAULT.
  ;; Each present value must be a non-negative safe integer. Zero is
  ;; valid. An invalid ordinary value errors even when the matching
  ;; model override is valid. enabled stays outside this lookup.
  (labels ((js-text (value)
             (cond
               ((cadr-ai::json-null-p value) "null")
               ((eq value t) "true")
               ((null value) "false")
               ((stringp value) value)
               ((integerp value)
                (write-to-string value :base 10))
               ((rationalp value)
                (cadr-ai::terminating-rational-json-text value))
               ((floatp value)
                (cond
                  ((sb-ext:float-nan-p value) "NaN")
                  ((sb-ext:float-infinity-p value)
                   (if (minusp value) "-Infinity" "Infinity"))
                  (t
                   (cadr-ai::terminating-rational-json-text
                    (rationalize value)))))
               ((hash-table-p value) "[object Object]")
               ((vectorp value)
                (with-output-to-string (out)
                  (loop for item across value
                        for first-p = t then nil
                        do (unless first-p
                             (write-char #\, out))
                           (write-string (js-text item) out))))
               (t (princ-to-string value))))
           (safe-integer-p (value)
             (and (integerp value)
                  (<= 0 value 9007199254740991)))
           (present (object key)
             (if (hash-table-p object)
                 (cadr-ai::json-get object key :missing)
                 :missing)))
    (let* ((compaction
             (if (hash-table-p compaction) compaction nil))
           (ordinary (present compaction field)))
      (unless (or (eq ordinary :missing)
                  (safe-integer-p ordinary))
        (error
         "Invalid compaction.~A setting: ~A. Expected a non-negative safe integer."
         field (js-text ordinary)))
      (let* ((model-key
               (and model
                    (model-setting-key
                     (cadr-ai:model-provider model)
                     (cadr-ai:model-id model))))
             (overrides
               (present compaction "modelOverrides"))
             (entry
               (if (and model-key (hash-table-p overrides))
                   (present overrides model-key)
                   :missing)))
        (unless (or (eq entry :missing)
                    (hash-table-p entry))
          (error
           "Invalid compaction.modelOverrides[\"~A\"] setting: ~A. Expected an object."
           model-key (js-text entry)))
        (let ((override
                (if (hash-table-p entry)
                    (present entry field)
                    :missing)))
          (unless (or (eq override :missing)
                      (safe-integer-p override))
            (error
             "Invalid compaction.modelOverrides[\"~A\"].~A setting: ~A. Expected a non-negative safe integer."
             model-key field (js-text override)))
          (cond
            ((not (eq override :missing)) override)
            ((not (eq ordinary :missing)) ordinary)
            (t default)))))))
