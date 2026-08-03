(in-package #:cadr-cli)

(defun default-agent-directory ()
  (merge-pathnames
   ".cadr/"
   (user-homedir-pathname)))

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

(defun default-project-trust-label (value)
  (cond
    ((string= value "always") "Always trust")
    ((string= value "never") "Never trust")
    (t "Ask")))

(defun set-cli-thinking-level
    (agent settings-manager level)
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
      (when
          (or
           (cadr-ai:model-reasoning-p
            (cadr-agent:agent-model agent))
           (not (eq effective :off)))
        (settings-set
         settings-manager
         "defaultThinkingLevel"
         (string-downcase
          (symbol-name effective))
         :scope :global))
      (run-session-lifecycle
       agent :thinking-level-select
       :level effective
       :previous-level previous))
    effective))

(defun sync-agent-settings-from-manager
    (agent settings-manager)
  (setf
   (cadr-agent::agent-auto-compact-p agent)
   (settings-boolean-value
    settings-manager
    "compaction" t "enabled")
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
     &key keybindings
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
         (images
           (settings-value
            settings-manager
            "images"
            (empty-json-object)))
         (theme-names
           (remove-duplicates
            (cons
             "dark"
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
            "alt+enter"))
         (options
           (list
            (make-settings-option
             :id "autocompact"
             :label "Auto-compact"
             :description
             "Automatically compact context when it gets too large"
             :value
             (cadr-agent::agent-auto-compact-p agent)
             :values (list t nil))
            (make-settings-option
             :id "auto-resize-images"
             :label "Auto-resize images"
             :description
             "Resize large images to 2000x2000 max for better model compatibility"
             :value
             (if (hash-table-p images)
                 (eq t
                     (cadr-ai::json-get
                      images "autoResize" t))
                 t)
             :values (list t nil))
            (make-settings-option
             :id "block-images"
             :label "Block images"
             :description
             "Prevent images from being sent to LLM providers"
             :value
             (if (hash-table-p images)
                 (eq t
                     (cadr-ai::json-get
                      images "blockImages" nil))
                 nil)
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
             (settings-boolean-value
              settings-manager
              "showHardwareCursor" nil)
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
             "Horizontal padding for user messages, assistant messages, and thinking"
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
             (if (hash-table-p terminal)
                 (eq t
                     (cadr-ai::json-get
                      terminal "clearOnShrink" nil))
                 nil)
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
             :id "hide-thinking"
             :label "Hide thinking"
             :description
             "Hide thinking blocks in assistant responses"
             :value
             (settings-boolean-value
              settings-manager
              "hideThinkingBlock" nil)
             :values (list t nil))
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
             "Disable verbose printing at startup"
             :value
             (settings-boolean-value
              settings-manager
              "quietStartup" nil)
             :values (list t nil))
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
             :id "thinking"
             :label "Thinking level"
             :description
             "Reasoning depth for thinking-capable models"
             :value
             (cadr-agent::agent-thinking-level agent)
             :values
             (cadr-ai:supported-thinking-levels
              (cadr-agent:agent-model agent))
             :submenu :thinking)
            (make-settings-option
             :id "theme"
             :label "Theme"
             :description
             "Color theme for the interface"
             :value current-theme
             :values theme-names
             :submenu :theme))))
    (when supports-images-p
      (setf
       options
       (append
        (subseq options 0 1)
        (list
         (make-settings-option
          :id "show-images"
          :label "Show images"
          :description "Render images inline in terminal"
          :value
          (if (hash-table-p terminal)
              (eq t
                  (cadr-ai::json-get
                   terminal "showImages" t))
              t)
          :values (list t nil))
         (make-settings-option
          :id "image-width-cells"
          :label "Image width"
          :description
          "Preferred inline image width in terminal cells"
          :value
          (let ((value
                  (and
                   (hash-table-p terminal)
                   (cadr-ai::json-get
                    terminal "imageWidthCells" 60))))
            (if (member value '(60 80 120)) value 60))
          :values '(60 80 120)))
        (subseq options 1))))
    (make-settings-selector-state
     :options options
     :theme-names theme-names
     :current-theme current-theme
     :terminal-theme
     (theme-detection-theme
      (detect-background-from-environment))
     :keybindings keybindings
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
         ((string= id "thinking")
          (set-cli-thinking-level
           agent settings-manager value))
         (t
          (let ((key
                  (cdr
                   (assoc
                    id
                    '(("skill-commands"
                       . "enableSkillCommands")
                      ("show-hardware-cursor"
                       . "showHardwareCursor")
                      ("editor-padding"
                       . "editorPaddingX")
                      ("output-padding"
                       . "outputPad")
                      ("autocomplete-max-visible"
                       . "autocompleteMaxVisible")
                      ("transport" . "transport")
                      ("http-idle-timeout"
                       . "httpIdleTimeoutMs")
                      ("hide-thinking"
                       . "hideThinkingBlock")
                      ("cache-miss-notices"
                       . "showCacheMissNotices")
                      ("collapse-changelog"
                       . "collapseChangelog")
                      ("quiet-startup"
                       . "quietStartup")
                      ("install-telemetry"
                       . "enableInstallTelemetry")
                      ("default-project-trust"
                       . "defaultProjectTrust")
                      ("double-escape-action"
                       . "doubleEscapeAction")
                      ("tree-filter-mode"
                       . "treeFilterMode")
                      ("theme" . "theme"))
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
               #'resolve-system-prompt
               append-sources))))
         (options
           (list
            :custom-prompt
            (and custom-source
                 (resolve-system-prompt custom-source))
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
