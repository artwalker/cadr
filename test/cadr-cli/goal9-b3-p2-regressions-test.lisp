(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun goal9-b3-plain-lines (lines)
  (mapcar #'cadr-tui:strip-terminal-sequences lines))

(defun goal9-b3-full-width-line (value width)
  ;; Baseline Text/TruncatedText rows are exact-width; keep this oracle
  ;; independent of Cadr's selector implementation.
  (let* ((limited (if (> (length value) width)
                      (subseq value 0 width)
                      value))
         (padding
           (max 0 (- width (cadr-tui:visible-width limited)))))
    (concatenate
     'string limited
     (make-string padding :initial-element #\Space))))

(defun goal9-b3-full-width-input-line (value width)
  ;; Baseline Input reserves one software-cursor cell even at end-of-input.
  (goal9-b3-full-width-line
   (concatenate 'string "> " value " ")
   width))

(test goal9-b3-model-overlay-copy-matches-unscoped-baseline
  (let* ((width 80)
         (border
           (make-string width :initial-element #\─))
         (model
           (cadr-ai:make-model
            :id "faux-model" :name "Faux Model"
            :provider :faux :api :faux))
         (state
           (cadr-cli::make-model-selector-state
            :all-models (list model)
            :current-model model))
         (plain
           (goal9-b3-plain-lines
            (cadr-cli::render-model-selector
             state width))))
    (is
     (equal
      (list
       border
       ""
       (goal9-b3-full-width-line
        "Only showing models from configured providers. Use /login to add providers."
        width)
       ""
       (goal9-b3-full-width-input-line "" width)
       ""
       (goal9-b3-full-width-line "→ faux-model [faux] ✓" width)
       ""
       (goal9-b3-full-width-line "  Model Name: Faux Model" width)
       ""
       border)
      plain))))

(test goal9-b3-tree-help-copy-preserves-arrow-glyphs-and-filter-abbreviations
  (let* ((width 120)
         (border
           (make-string width :initial-element #\─))
         (state
           (cadr-cli::make-tree-selector-state
            :entries
            '((:id "u1" :parent-id nil
               :type :message :role :user :text "hello"))
            :current-leaf-id "u1"))
         (plain
           (goal9-b3-plain-lines
            (cadr-cli::render-tree-selector
             state width))))
    (is
     (equal
      (list
       ""
       border
       (goal9-b3-full-width-line "   Session Tree" width)
       "  ↑/↓ move · ←/→ page · ctrl+←/→ branch · ctrl+x copy · shift+l label · shift+t label time · filters ctrl+d/t/u/l/a"
       "  cycle ctrl+o/shift+ctrl+o"
       "  Type to search:"
       border
       ""
       "› • user: hello"
       "  (1/1)"
       ""
       border)
      plain))))

(test goal9-b3-tree-tool-results-render-call-labels-not-raw-output
  (with-test-directory (root)
    (let* ((sessions (merge-pathnames "sessions/" root))
           (cwd (merge-pathnames "project/" root))
           (_ (ensure-directories-exist
               (merge-pathnames "anchor" cwd)))
           (session
             (cadr-agent:create-session
              :directory sessions :cwd cwd :id "tree-tools"))
           (assistant
             (cadr-ai:make-assistant-message
              :content
              (list
               (cadr-ai:make-tool-call
                :id "bash-1" :name "bash"
                :arguments
                (cadr-ai::json-object
                 "command" "printf 'ok'"))
               (cadr-ai:make-tool-call
                :id "read-1" :name "read"
                :arguments
                (cadr-ai::json-object
                 "path" "README.md")))
              :api :faux :provider :faux :model "faux"
              :stop-reason :tool-use))
           (bash-result
             (cadr-ai:make-tool-result-message
              :tool-call-id "bash-1" :tool-name "bash"
              :content
              (list
               (cadr-ai:make-text-content
                :text "RAW BASH OUTPUT MUST NOT APPEAR"))))
           (read-result
             (cadr-ai:make-tool-result-message
              :tool-call-id "read-1" :tool-name "read"
              :content
              (list
               (cadr-ai:make-text-content
                :text "RAW FILE CONTENT MUST NOT APPEAR")))))
      (declare (ignore _))
      (dolist (message (list assistant bash-result read-result))
        (cadr-agent:session-append-message session message))
      (multiple-value-bind (entries leaf-id)
          (cadr-cli::session-tree-selector-data session)
        (let* ((state
                 (cadr-cli::make-tree-selector-state
                  :entries entries :current-leaf-id leaf-id
                  :filter :all))
               (plain
                 (goal9-b3-plain-lines
                  (cadr-cli::tree-selector-render-lines
                   state 200))))
          (is
           (equal
            '("  • [bash: printf 'ok']"
              "› • [read: README.md]"
              "  (2/2) [all]")
            plain)))))))

(test goal9-b3-cold-startup-content-is-top-aligned
  (let* ((version-line
           (format nil "cadr v~A" (cadr-ai::cadr-version)))
         (width 60)
         (rows 16)
         (blank-row
           (make-string width :initial-element #\Space))
         (border
           (make-string width :initial-element #\─))
         (state
           (cadr-cli::make-tui-state
            :model "faux"
            :startup-compact-lines
            (list
             version-line
             "escape interrupt · ctrl+c/ctrl+d clear/exit")))
         (editor (cadr-tui:make-multiline-editor)))
    (multiple-value-bind (lines row column)
        (cadr-cli::render-tui-state
         state editor width rows)
      (is (= 6 row))
      (is (zerop column))
      (is
       (equal
        (list
         ""
         (format nil " ~A~A" version-line
                 (make-string (- width 1 (length version-line))
                              :initial-element #\Space))
         (format nil " escape interrupt · ctrl+c/ctrl+d clear/exit~A"
                 (make-string
                  (- width
                     (length " escape interrupt · ctrl+c/ctrl+d clear/exit"))
                  :initial-element #\Space))
         ""
         ""
         border
         blank-row
         border
         ""
         "0.0%/0 (auto)                                           faux")
        (goal9-b3-plain-lines lines))))))

(test goal9-b3-settings-overlay-is-an-exact-baseline-screen
  (let* ((manager (cadr-cli::make-memory-settings-manager))
         (model
           (cadr-ai:make-model
            :id "reasoning" :name "Reasoning"
            :provider :faux :api :openai-responses
            :reasoning-p t))
         (agent
           (cadr-agent:make-agent
            :provider nil :model model))
         (state
           (cadr-cli::make-cli-settings-selector-state
            manager agent
            (cadr-cli::make-resource-snapshot)
            :supports-images-p nil))
         (width 80)
         (border
           (make-string width :initial-element #\─))
         (options
           (cadr-cli::settings-selector-state-options state)))
    (is (= 25 (length options)))
    (is
     (equal
      '("autocompact" "auto-resize-images" "block-images"
        "skill-commands" "show-hardware-cursor" "editor-padding"
        "output-padding" "autocomplete-max-visible" "clear-on-shrink"
        "terminal-progress" "steering-mode" "follow-up-mode" "transport"
        "http-idle-timeout" "hide-thinking" "cache-miss-notices"
        "collapse-changelog" "quiet-startup" "install-telemetry"
        "default-project-trust" "double-escape-action" "tree-filter-mode"
        "warnings" "thinking" "theme")
      (mapcar #'cadr-cli::settings-option-id options)))
    (is
     (uiop:string-prefix-p
      "alt+enter queues follow-up messages"
      (cadr-cli::settings-option-description
       (find "follow-up-mode" options
             :key #'cadr-cli::settings-option-id
             :test #'string=))))
    (is
     (equal
      (list
       border
       (goal9-b3-full-width-input-line "" width)
       ""
       "→ Auto-compact            true"
       "  Auto-resize images      true"
       "  Block images            false"
       "  Skill commands          true"
       "  Show hardware cursor    false"
       "  Editor padding          0"
       "  Output padding          1"
       "  Autocomplete max items  5"
       "  Clear on shrink         false"
       "  Terminal progress       false"
       "  (1/25)"
       ""
       "  Automatically compact context when it gets too large"
       ""
       "  Type to search · Enter/Space to change · Esc to cancel"
       border)
      (goal9-b3-plain-lines
       (cadr-cli::render-settings-selector state width))))))

(test goal9-b3-settings-overlay-retains-the-complete-ansi-screen-contract
  (let ((capabilities
          (cadr-tui:make-terminal-capabilities
           :true-color-p t)))
    (cadr-tui:set-current-theme
     :dark :capabilities capabilities)
    (unwind-protect
         (let* ((state
                  (cadr-cli::make-settings-selector-state
                   :options
                   (list
                    (cadr-cli::make-settings-option
                     :id "autocompact"
                     :label "Auto-compact"
                     :description "Automatically compact context"
                     :value t :values (list t nil)))))
                (width 40)
                (rendered
                  (cadr-cli::render-settings-selector state width)))
           (is
            (equal
             (list
              (format nil "~C[38;2;95;135;255m~A~C[39m"
                      #\Escape
                      (make-string width :initial-element #\─)
                      #\Escape)
              (concatenate
               'string
               "> "
               (format nil "~C[7m ~C[27m" #\Escape #\Escape)
               (make-string 37 :initial-element #\Space))
              ""
              (format nil
                      "~C[38;2;138;190;183m→ ~C[39m~C[38;2;138;190;183mAuto-compact~C[39m  ~C[38;2;138;190;183mtrue~C[39m"
                      #\Escape #\Escape #\Escape #\Escape
                      #\Escape #\Escape)
              ""
              (format nil
                      "~C[38;2;102;102;102m  Automatically compact context~C[39m"
                      #\Escape #\Escape)
              ""
              (format nil
                      "~C[38;2;102;102;102m  Type to search · Enter/Space to cha~C[0m...~C[0m"
                      #\Escape #\Escape #\Escape)
              (format nil "~C[38;2;95;135;255m~A~C[39m"
                      #\Escape
                      (make-string width :initial-element #\─)
                      #\Escape))
             rendered))
           (is
            (every
             (lambda (line)
               (or (string= line "")
                   (search (string #\Escape) line)))
             rendered)))
      (cadr-tui:reset-current-theme))))

(test goal9-b3-settings-overlay-wraps-and-searches-through-its-real-input-path
  (let* ((changes nil)
         (state
           (cadr-cli::make-settings-selector-state
            :options
            (loop for index below 25
                  collect
                  (cadr-cli::make-settings-option
                   :id (format nil "setting-~D" index)
                   :label (if (= index 24)
                              "Terminal progress"
                              (format nil "Setting ~D" index))
                   :description (format nil "Description ~D" index)
                   :value (evenp index)
                   :values (list t nil)))
            :change-callback
            (lambda (id value)
              (push (list id value) changes)))))
    (multiple-value-bind (action value handled-p)
        (cadr-cli::settings-selector-handle-raw-input
         state (format nil "~C[A" #\Escape))
      (declare (ignore value))
      (is (eq :changed action))
      (is (not (null handled-p))))
    (is (= 24 (cadr-cli::settings-selector-state-selected state)))
    (multiple-value-bind (action value handled-p)
        (cadr-cli::settings-selector-handle-raw-input
         state (format nil "~C[B" #\Escape))
      (declare (ignore value))
      (is (eq :changed action))
      (is (not (null handled-p))))
    (is (zerop (cadr-cli::settings-selector-state-selected state)))
    (dolist (character (coerce "term" 'list))
      (cadr-cli::settings-selector-handle-event
       state
       (cadr-tui:make-input-event
        :kind :text :text (string character))))
    (is (string= "term" (cadr-cli::settings-selector-state-query state)))
    (is
     (equal
      '("Terminal progress")
      (mapcar
       #'cadr-cli::settings-option-label
       (cadr-cli::settings-selector-visible-options state))))
    (is
     (equal
      (list "────────────" (goal9-b3-full-width-input-line "term" 12)
        "" "→ Terminal p" "" "  Descript"
        "  ion 24" "" "  Type to..." "────────────")
      (goal9-b3-plain-lines
       (cadr-cli::render-settings-selector state 12))))
    (cadr-cli::settings-selector-handle-event
     state (cadr-tui:make-input-event :kind :backspace))
    (is (string= "ter" (cadr-cli::settings-selector-state-query state)))
    (setf (cadr-cli::settings-selector-state-query state) "")
    (cadr-cli::settings-selector-apply-filter state)
    (cadr-cli::settings-selector-handle-event
     state (cadr-tui:make-input-event :kind :text :text " "))
    (is (equal '(("setting-0" nil)) changes))))

(test goal9-b3-settings-capability-and-submenus-match-baseline-contract
  (let* ((manager (cadr-cli::make-memory-settings-manager))
         (model
           (cadr-ai:make-model
            :id "reasoning" :name "Reasoning"
            :provider :faux :api :openai-responses
            :reasoning-p t))
         (agent
           (cadr-agent:make-agent :provider nil :model model))
         (with-images
           (cadr-cli::make-cli-settings-selector-state
            manager agent (cadr-cli::make-resource-snapshot)
            :supports-images-p t)))
    (is (= 27
           (length
            (cadr-cli::settings-selector-state-options with-images))))
    (is
     (equal
      '("autocompact" "show-images" "image-width-cells"
        "auto-resize-images" "block-images" "skill-commands"
        "show-hardware-cursor")
      (mapcar
       #'cadr-cli::settings-option-id
       (subseq
       (cadr-cli::settings-selector-state-options with-images)
        0 7))))
    (setf (cadr-cli::settings-selector-state-selected with-images) 1)
    (cadr-cli::settings-selector-handle-event
     with-images (cadr-tui:make-input-event :kind :enter))
    (is
     (null
      (cadr-cli::settings-nested-value
       manager "terminal" "showImages" :missing)))
    (setf (cadr-cli::settings-selector-state-selected with-images) 2)
    (cadr-cli::settings-selector-handle-event
     with-images (cadr-tui:make-input-event :kind :enter))
    (is
     (= 80
        (cadr-cli::settings-nested-value
         manager "terminal" "imageWidthCells" -1))))
  (let* ((width 80)
         (border (make-string width :initial-element #\─))
         (changes nil)
         (state
           (cadr-cli::make-settings-selector-state
            :theme-names '("dark" "light")
            :current-theme "dark"
            :options
            (list
             (cadr-cli::make-settings-option
              :id "warnings" :label "Warnings"
              :description "Enable or disable individual warnings"
              :value '(:anthropic-extra-usage t)
              :format-function
              (lambda (value)
                (declare (ignore value))
                "configure")
              :submenu :warnings)
             (cadr-cli::make-settings-option
              :id "thinking" :label "Thinking level"
              :description
              "Reasoning depth for thinking-capable models"
              :value :low :values '(:off :low :high)
              :submenu :thinking)
             (cadr-cli::make-settings-option
              :id "theme" :label "Theme"
              :description "Color theme for the interface"
              :value "dark" :values '("dark" "light")
              :submenu :theme))
            :change-callback
            (lambda (id value)
              (push (list id value) changes)))))
    (cadr-cli::settings-selector-handle-event
     state (cadr-tui:make-input-event :kind :enter))
    (is
     (equal
      (list
       border
       "→ Anthropic extra usage  true"
       ""
       "  Warn when Anthropic subscription auth may use paid extra usage"
       ""
       "  Enter/Space to change · Esc to cancel"
       border)
      (goal9-b3-plain-lines
       (cadr-cli::render-settings-selector state width))))
    (cadr-cli::settings-selector-handle-event
     state (cadr-tui:make-input-event :kind :enter))
    (is (equal '(("anthropic-extra-usage" nil)) changes))
    (cadr-cli::settings-selector-handle-event
     state (cadr-tui:make-input-event :kind :escape))
    (cadr-cli::settings-selector-handle-event
     state (cadr-tui:make-input-event :kind :down))
    (cadr-cli::settings-selector-handle-event
     state (cadr-tui:make-input-event :kind :enter))
    (is
     (equal
      (list
       border (goal9-b3-full-width-line "Thinking Level" width) ""
       "Select reasoning depth for thinking-capable models" ""
       "  off         No reasoning"
       "→ low         Light reasoning (~2k tokens)"
       "  high        Deep reasoning (~16k tokens)"
       "" "  Enter to select · Esc to go back" border)
      (goal9-b3-plain-lines
       (cadr-cli::render-settings-selector state width))))
    (cadr-cli::settings-selector-handle-event
     state (cadr-tui:make-input-event :kind :up))
    (is (= 0 (cadr-cli::settings-selector-state-submenu-selected state)))
    (cadr-cli::settings-selector-handle-event
     state (cadr-tui:make-input-event :kind :up))
    (is (= 2 (cadr-cli::settings-selector-state-submenu-selected state)))
    (cadr-cli::settings-selector-handle-event
     state (cadr-tui:make-input-event :kind :escape))
    (cadr-cli::settings-selector-handle-event
     state (cadr-tui:make-input-event :kind :down))
    (cadr-cli::settings-selector-handle-event
     state (cadr-tui:make-input-event :kind :enter))
    (is
     (equal
      (list
       border (goal9-b3-full-width-line "Theme" width) ""
       "Select a theme, or choose Automatic to follow terminal appearance."
       ""
       "  Automatic   Use separate themes for light and dark terminal appearance"
       "→ dark"
       "  light"
       "" "  Enter to select · Esc to go back" border)
      (goal9-b3-plain-lines
       (cadr-cli::render-settings-selector state width))))
    (cadr-cli::settings-selector-handle-event
     state (cadr-tui:make-input-event :kind :up))
    (cadr-cli::settings-selector-handle-event
     state (cadr-tui:make-input-event :kind :enter))
    (is
     (equal
      (list
       border (goal9-b3-full-width-line "Automatic Theme" width) ""
       (goal9-b3-full-width-line
        "Choose themes for terminal light and dark appearance." width)
       "Light/dark detection requires terminal support."
       ""
       "→ Light theme  dark"
       "  Dark theme   dark"
       "  Apply        save and go back"
       "  Change mode  switch to single theme"
       ""
       "  Theme to use in automatic mode when the terminal is light"
       "" "  Enter/Space to change · Esc to cancel" border)
       (goal9-b3-plain-lines
       (cadr-cli::render-settings-selector state width))))))

(test goal9-b3-every-settings-submenu-wraps-at-both-boundaries
  (let ((state
          (cadr-cli::make-settings-selector-state
           :theme-names '("dark" "light")
           :current-theme "dark"
           :options
           (list
            (cadr-cli::make-settings-option
             :id "warnings" :label "Warnings"
             :value '(:anthropic-extra-usage t)
             :submenu :warnings)
            (cadr-cli::make-settings-option
             :id "thinking" :label "Thinking"
             :value :low :values '(:off :low :high)
             :submenu :thinking)
            (cadr-cli::make-settings-option
             :id "theme" :label "Theme"
             :value "dark" :values '("dark" "light")
             :submenu :theme)))))
    (dolist (mode '(:warnings :thinking :theme-single
                    :theme-automatic :theme-light :theme-dark))
      (setf (cadr-cli::settings-selector-state-mode state) mode
            (cadr-cli::settings-selector-state-submenu-selected state) 0)
      (let ((last-index
              (1-
               (length
                (cadr-cli::settings-selector-submenu-options state)))))
        (cadr-cli::settings-selector-handle-event
         state (cadr-tui:make-input-event :kind :up))
        (is (= last-index
               (cadr-cli::settings-selector-state-submenu-selected state)))
        (cadr-cli::settings-selector-handle-event
         state (cadr-tui:make-input-event :kind :down))
        (is (zerop
             (cadr-cli::settings-selector-state-submenu-selected state)))))))

(test goal9-b3-settings-raw-input-wraps-submenus-and-uses-configured-follow-up-key
  (let* ((keybindings
           (cadr-tui:make-keybindings-manager
            :user-bindings
            '(("app.message.followUp" . ("alt+f")))))
         (manager (cadr-cli::make-memory-settings-manager))
         (model
           (cadr-ai:make-model
            :id "reasoning" :name "Reasoning"
            :provider :faux :api :openai-responses
            :reasoning-p t))
         (agent
           (cadr-agent:make-agent :provider nil :model model))
         (full
           (cadr-cli::make-cli-settings-selector-state
            manager agent (cadr-cli::make-resource-snapshot)
            :supports-images-p nil
            :keybindings keybindings))
         (follow-up
           (find "follow-up-mode"
                 (cadr-cli::settings-selector-state-options full)
                 :key #'cadr-cli::settings-option-id
                 :test #'string=))
         (state
           (cadr-cli::make-settings-selector-state
            :theme-names '("dark" "light")
            :current-theme "dark"
            :keybindings keybindings
            :options
            (list
             (cadr-cli::make-settings-option
              :id "theme" :label "Theme"
              :value "dark" :values '("dark" "light")
              :submenu :theme)))))
    (is
     (uiop:string-prefix-p
      "alt+f queues follow-up messages"
      (cadr-cli::settings-option-description follow-up)))
    (cadr-cli::settings-selector-handle-event
     state (cadr-tui:make-input-event :kind :enter))
    (setf (cadr-cli::settings-selector-state-submenu-selected state) 0)
    (multiple-value-bind (action value handled-p)
        (cadr-cli::settings-selector-handle-raw-input
         state (format nil "~C[A" #\Escape))
      (is (eq :changed action))
      (is (equal '(:id "theme-preview" :value "light") value))
      (is (not (null handled-p))))
    (is (= 2 (cadr-cli::settings-selector-state-submenu-selected state)))
    (multiple-value-bind (action value handled-p)
        (cadr-cli::settings-selector-handle-raw-input
         state (format nil "~C[B" #\Escape))
      (is (eq :changed action))
      (is (equal '(:id "theme-preview" :value "dark/dark") value))
      (is (not (null handled-p))))
    (is (zerop
         (cadr-cli::settings-selector-state-submenu-selected state)))))

(test goal9-b3-settings-automatic-theme-drafts-reset-after-cancel
  (let ((state
          (cadr-cli::make-settings-selector-state
           :theme-names '("dark" "light")
           :current-theme "dark/dark"
           :terminal-theme :light
           :options
           (list
            (cadr-cli::make-settings-option
             :id "theme" :label "Theme"
             :value "dark/dark" :values '("dark" "light")
             :submenu :theme)))))
    (cadr-cli::settings-selector-handle-event
     state (cadr-tui:make-input-event :kind :enter))
    (cadr-cli::settings-selector-handle-event
     state (cadr-tui:make-input-event :kind :enter))
    (cadr-cli::settings-selector-handle-event
     state (cadr-tui:make-input-event :kind :down))
    (cadr-cli::settings-selector-handle-event
     state (cadr-tui:make-input-event :kind :enter))
    (is
     (string= "light/dark"
              (cadr-cli::settings-selector-automatic-theme-setting
               state)))
    (cadr-cli::settings-selector-handle-event
     state (cadr-tui:make-input-event :kind :escape))
    (is (eq :main (cadr-cli::settings-selector-state-mode state)))
    (cadr-cli::settings-selector-handle-event
     state (cadr-tui:make-input-event :kind :enter))
    (is
     (string= "dark/dark"
              (cadr-cli::settings-selector-automatic-theme-setting
               state)))
    (setf (cadr-cli::settings-selector-state-submenu-selected state) 3)
    (multiple-value-bind (action preview)
        (cadr-cli::settings-selector-handle-event
         state (cadr-tui:make-input-event :kind :enter))
      (is (eq :changed action))
      (is (equal '(:id "theme-preview" :value "dark") preview)))))
