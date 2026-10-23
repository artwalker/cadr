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
       (goal9-b3-full-width-line "→ ✓ faux-model [faux]" width)
       ""
       (goal9-b3-full-width-line "  Model Name: Faux Model" width)
       ""
       (goal9-b3-full-width-line
        "  Enter to select · Ctrl+S to set as default · Escape/Ctrl+C to cancel"
        width)
       border)
      plain))))

(test model-selector-hint-wraps-at-the-baseline-text-width
  ;; v1.4.0 model-selector.ts Text(hint, 0, 0) word-wraps. At 48 columns
  ;; the cancel clause is the next row.
  (let* ((width 48)
         (model
           (cadr-ai:make-model
            :id "faux-1" :name "Faux" :provider :faux :api :faux))
         (plain
           (goal9-b3-plain-lines
            (cadr-cli::render-model-selector
             (cadr-cli::make-model-selector-state
              :all-models (list model)
              :current-model model)
             width)))
         (hint
           (position-if
            (lambda (line) (search "to set as default" line))
            plain))
         (cancel
           (position-if
            (lambda (line) (search "Escape/Ctrl+C to cancel" line))
            plain)))
    (is (and hint cancel (= cancel (1+ hint))))
    (is (null
         (find "default · E" plain :test #'search)))))

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

(test gap76-seeded-transcript-tree-selects-the-assistant
  ;; pi@4a080252f tree-selector.ts default filter hides
  ;; thinking_level_change. AgentSession does not append a system
  ;; message at construction, so a seeded user/assistant transcript
  ;; plus that hidden leaf selects the assistant at (2/2).
  ;; getEntryDisplayText writes "user: " / "assistant: " and the
  ;; active-path marker "• ".
  (with-test-directory (root)
    (let* ((sessions (merge-pathnames "sessions/" root))
           (cwd (merge-pathnames "project/" root))
           (_ (ensure-directories-exist
               (merge-pathnames "anchor" cwd)))
           (session
             (cadr-agent:create-session
              :directory sessions :cwd cwd :id "gap76-tree"))
           (tool
             (cadr-ai:make-tool
              :name "read"
              :description "Read a file."
              :parameters
              (cadr-ai::json-object
               "type" "object"
               "properties" (cadr-ai::json-object)))))
      (declare (ignore _))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-user-message
        :content "overlay question" :timestamp 1))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-assistant-message
        :content
        (list (cadr-ai:make-text-content :text "overlay answer"))
        :api :faux :provider :faux :model "faux-1"
        :stop-reason :stop :timestamp 2))
      (cadr-agent:make-agent
       :provider :faux
       :model
       (cadr-ai:make-model
        :id "faux-1" :name "Faux" :provider :faux :api :faux)
       :system-prompt "Render differential fixed system prompt."
       :tools (list tool)
       :session session)
      (cadr-agent:session-append-thinking-level-change
       session "high")
      (multiple-value-bind (entries leaf-id)
          (cadr-cli::session-tree-selector-data session)
        (let ((plain
                (mapcar
                 (lambda (line)
                   (string-right-trim
                    " "
                    (cadr-tui:strip-terminal-sequences line)))
                 (cadr-cli::tree-selector-render-lines
                  (cadr-cli::make-tree-selector-state
                   :entries entries
                   :current-leaf-id leaf-id)
                  80))))
          (is (equal
               '("  • user: overlay question"
                 "› • assistant: overlay answer"
                 "  (2/2)")
               plain))
          (is (not (find-if
                    (lambda (line) (search "[nil]" line))
                    plain))))))))

(test gap76-system-message-preview-uses-the-role-name
  ;; pi@4a080252f tree-selector.ts getEntryDisplayText falls through
  ;; to `[${role}]` for a system message. Default mode does not treat
  ;; it as a settings entry, so the row stays visible.
  (with-test-directory (root)
    (let* ((sessions (merge-pathnames "sessions/" root))
           (cwd (merge-pathnames "project/" root))
           (_ (ensure-directories-exist
               (merge-pathnames "anchor" cwd)))
           (session
             (cadr-agent:create-session
              :directory sessions :cwd cwd :id "gap76-system")))
      (declare (ignore _))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-system-message
        :content ""
        :tools-added
        (list
         (cadr-ai:make-tool
          :name "read"
          :description "Read a file."
          :parameters
          (cadr-ai::json-object
           "type" "object"
           "properties" (cadr-ai::json-object))))
        :timestamp 1))
      (multiple-value-bind (entries leaf-id)
          (cadr-cli::session-tree-selector-data session)
        (let ((plain
                (mapcar
                 (lambda (line)
                   (string-right-trim
                    " "
                    (cadr-tui:strip-terminal-sequences line)))
                 (cadr-cli::tree-selector-render-lines
                  (cadr-cli::make-tree-selector-state
                   :entries entries
                   :current-leaf-id leaf-id)
                  80))))
          (is (equal '("› • [system]" "  (1/1)") plain))
          (is (not (find-if
                    (lambda (line) (search "[nil]" line))
                    plain))))))))

(test goal9-b3-cold-startup-content-is-top-aligned
  (let* ((version-line
          (format nil "cadr v~A" (cadr-ai::cadr-version)))
         (logo-line
           (concatenate 'string "▀▀█  "
                        (subseq version-line (length "cadr "))))
         (hint-line
           (concatenate 'string "█▀ █ "
                        "escape interrupt · ctrl+c/ctrl+d clear/exit"))
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
         (format nil " ~A~A" logo-line
                 (make-string (- width 1 (length logo-line))
                              :initial-element #\Space))
         (format nil " ~A~A" hint-line
                 (make-string
                  (- width 1 (length hint-line))
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
    (is (= 33 (length options)))
    (is
     (equal
      '("autocompact" "auto-resize-images" "block-images"
        "skill-commands" "show-hardware-cursor" "editor-padding"
        "output-padding" "autocomplete-max-visible" "clear-on-shrink"
        "terminal-progress" "steering-mode" "follow-up-mode" "transport"
        "share-destination" "http-idle-timeout"
        "cache-warming-mode" "hide-thinking"
        "mermaid-rendering"
        "cache-miss-notices" "collapse-changelog" "quiet-startup"
        "install-telemetry" "default-project-trust" "double-escape-action"
        "tree-filter-mode" "warnings" "model-thinking"
        "tui-mode" "fullscreen-exit-output" "fullscreen-scrollbar"
        "fullscreen-copy-on-select" "fullscreen-wheel-scroll-lines"
        "theme")
      (mapcar #'cadr-cli::settings-option-id options)))
    (is
     (uiop:string-prefix-p
      "Alt+Enter queues follow-up messages"
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
       "→ Auto-compact                      true"
       "  Auto-resize images                true"
       "  Block images                      false"
       "  Skill commands                    true"
       "  Show hardware cursor              false"
       "  Editor padding                    0"
       "  Output padding                    1"
       "  Autocomplete max items            5"
       "  Clear on shrink                   false"
       "  Terminal progress                 false"
       "  (1/33)"
       ""
       "  Automatically compact context when it gets too large"
       ""
       "  Type to search · Enter/Space to change · Esc to cancel"
       border)
      (goal9-b3-plain-lines
       (cadr-cli::render-settings-selector state width))))))

(test goal27-settings-value-column-follows-v140-settings-list
  ;; v1.4.0 packages/tui/src/components/settings-list.ts renderMainList
  ;; (the Math.min(36, longest label) line). Pads with that width, then
  ;; two spaces, then the value. A label past 36 does not widen the
  ;; column. A shorter menu stays at its own longest label. The width
  ;; comes from every item, including rows outside the visible slice.
  (let* ((plain
           (lambda (lines)
             (mapcar #'cadr-tui:strip-terminal-sequences lines)))
         (rows
           (lambda (options &optional (all options))
             (funcall
              plain
              (cadr-cli::render-settings-option-list
               options all 0 90 10)))))
    (is
     (equal
      '("→ A                                     yes"
        "  XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX  no")
      (subseq
       (funcall
        rows
        (list
         (cadr-cli::make-settings-option
          :id "short" :label "A" :value "yes")
         (cadr-cli::make-settings-option
          :id "long" :label (make-string 40 :initial-element #\X)
          :value "no")))
       0 2)))
    (is
     (equal
      '("→ Hi     yes"
        "  Short  no")
      (subseq
       (funcall
        rows
        (list
         (cadr-cli::make-settings-option
          :id "hi" :label "Hi" :value "yes")
         (cadr-cli::make-settings-option
          :id "short" :label "Short" :value "no")))
       0 2)))
    (is
     (string=
      "→ Hi                                yes"
      (first
       (funcall
        rows
        (list
         (cadr-cli::make-settings-option
          :id "hi" :label "Hi" :value "yes"))
        (list
         (cadr-cli::make-settings-option
          :id "hi" :label "Hi" :value "yes")
         (cadr-cli::make-settings-option
          :id "model"
          :label "Default thinking level per model"
          :value "low"))))))))

(test goal27-settings-submenu-columns-follow-v140-select-list
  ;; v1.4.0 packages/tui/src/components/select-list.ts renderItem clamps
  ;; the primary column and truncates the label to that width minus 2.
  ;; packages/tui/test/select-list.test.ts locks the shared starts.
  ;; settings-submenu.ts uses 12–32. settings-selector.ts MODEL_PICKER_LAYOUT
  ;; is 12–46. Thinking and theme labels include the check or two spaces.
  (let ((plain
          (lambda (lines)
            (mapcar #'cadr-tui:strip-terminal-sequences lines))))
    (labels ((at (line text)
               (let ((index (search text line)))
                 (is (integerp index))
                 (if (integerp index)
                     (cadr-tui:visible-width (subseq line 0 index))
                     -1)))
             (option (label description)
               (cadr-cli::make-settings-option
                :id label :label label :description description
                :value label)))
    (let* ((long "very-long-command-name-that-needs-truncation")
           (lines
             (funcall
              plain
              (cadr-cli::settings-select-list-lines
               (list (option "short" "short description")
                     (option long "long description"))
               80 0))))
      (is (= 34 (at (first lines) "short description")))
      (is (= 34 (at (second lines) "long description")))
      (is (search "very-long-command-name-that-ne" (second lines)))
      (is (null (search "needs-truncation" (second lines)))))
    (let ((lines
            (funcall
             plain
             (cadr-cli::settings-select-list-lines
              (list
               (option "very-long-command-name-that-needs-truncation"
                       "first")
               (option "short" "second"))
              80 0
              :min-primary 12 :max-primary 20))))
      (is (= 22 (at (first lines) "first")))
      (is (= 22 (at (second lines) "second"))))
    (let ((lines
            (funcall
             plain
             (cadr-cli::settings-select-list-lines
              (list (option "a" "first") (option "bb" "second"))
              80 0
              :min-primary 12 :max-primary 20))))
      (is (= 14 (at (first lines) "first")))
      (is (= 14 (at (second lines) "second"))))
    (let* ((short
             (cadr-ai:make-model
              :provider :openai :id "gpt-4o"
              :context-window 128000 :reasoning-p t))
           (long-model
             (cadr-ai:make-model
              :provider :amazon-bedrock
              :id "amazon.nova-2-lite-v1:0"
              :context-window 128000 :reasoning-p t))
           (state
             (cadr-cli::make-settings-selector-state
              :available-models (list short long-model)
              :options
              (list
               (cadr-cli::make-settings-option
                :id "model-thinking"
                :label "Default thinking level per model"
                :value (list :overrides
                             (list (cons "openai/gpt-4o" :high)
                                   (cons "amazon-bedrock/amazon.nova-2-lite-v1:0"
                                         :low))
                             :current-model short)
                :submenu :model-thinking)))))
      (setf (cadr-cli::settings-selector-state-mode state) :model-thinking)
      (let ((lines
              (funcall
               plain
               (cadr-cli::render-settings-selector state 80))))
        (is (= 44 (at (find-if (lambda (line) (search "gpt-4o" line)) lines)
                      "high")))
        (is (= 44
               (at (find-if
                    (lambda (line)
                      (search "amazon.nova-2-lite-v1:0" line))
                    lines)
                   "low")))
        (is (search "amazon.nova-2-lite-v1:0 [amazon-bedrock]"
                    (find-if
                     (lambda (line)
                       (search "amazon.nova-2-lite-v1:0" line))
                     lines)))))
    (let* ((overflow
             (cadr-ai:make-model
              :provider :openai
              :id (make-string 60 :initial-element #\x)
              :context-window 128000 :reasoning-p t))
           (short
             (cadr-ai:make-model
              :provider :openai :id "gpt-4o"
              :context-window 128000 :reasoning-p t))
           (state
             (cadr-cli::make-settings-selector-state
              :available-models (list short overflow)
              :options
              (list
               (cadr-cli::make-settings-option
                :id "model-thinking"
                :label "Default thinking level per model"
                :value (list :overrides
                             (list (cons "openai/gpt-4o" :high)
                                   (cons (format nil "openai/~A"
                                                 (cadr-ai:model-id overflow))
                                         :low))
                             :current-model short)
                :submenu :model-thinking)))))
      (setf (cadr-cli::settings-selector-state-mode state) :model-thinking)
      (let* ((lines
               (funcall
                plain
                (cadr-cli::render-settings-selector state 80)))
             (long-line
               (find-if
                (lambda (line) (search "xxxx" line))
                lines)))
        (is (= 48 (at long-line "low")))
        (is (= 48
               (at (find-if (lambda (line) (search "gpt-4o" line)) lines)
                   "high")))
        (is (search (make-string 44 :initial-element #\x) long-line))
        (is (null (search (make-string 45 :initial-element #\x) long-line)))))
    (let* ((model
             (cadr-ai:make-model
              :provider :openai :id "gpt-4o"
              :context-window 128000 :reasoning-p t))
           (key "openai/gpt-4o")
           (state
             (cadr-cli::make-settings-selector-state
              :available-models (list model)
              :options
              (list
               (cadr-cli::make-settings-option
                :id "model-thinking"
                :label "Default thinking level per model"
                :value (list :overrides (list (cons key :high))
                             :global-default :medium)
                :submenu :model-thinking)))))
      (setf (cadr-cli::settings-selector-state-mode state)
            :model-thinking-level
            (cadr-cli::settings-selector-state-model-thinking-key state)
            key)
      (let ((lines
              (funcall
               plain
               (cadr-cli::render-settings-selector state 80))))
        (is (find-if
             (lambda (line) (search "✓ high" line))
             lines))
        (is (find-if
             (lambda (line) (search "  off" line))
             lines))
        (is (= 22
               (at (find-if
                    (lambda (line)
                      (search "Deep reasoning (~16k tokens)" line))
                    lines)
                   "Deep reasoning (~16k tokens)")))
        (is (= 22
               (at (find-if
                    (lambda (line) (search "(clear override)" line))
                    lines)
                   "Revert to global default (medium)")))))
    (let ((state
            (cadr-cli::make-settings-selector-state
             :theme-names '("system" "dark" "light")
             :current-theme "dark")))
      (setf (cadr-cli::settings-selector-state-mode state) :theme-single)
      (let ((lines
              (funcall
               plain
               (cadr-cli::render-settings-selector state 80))))
        (is (= 15
               (at (find-if
                    (lambda (line)
                      (search "Use separate themes" line))
                    lines)
                   "Use separate themes for light and dark terminal appearance")))
        (is (= 15
               (at (find-if
                    (lambda (line)
                      (search "Theme created from your terminal's colors" line))
                    lines)
                   "Theme created from your terminal's colors")))
        (is (equal '("system" "/" "dark" "light")
                   (mapcar #'cadr-cli::settings-option-value
                           (cadr-cli::settings-selector-submenu-options
                            state))))
        (is (find-if (lambda (line) (search "✓ dark" line)) lines))
        (is (some
             (lambda (line)
               (search
                "Select a theme, or choose automatic to follow terminal appearance."
                line))
             lines))))
    (let ((state
            (cadr-cli::make-settings-selector-state
             :theme-names '("system" "dark" "light")
             :current-theme "dark"
             :options
             (list
              (cadr-cli::make-settings-option
               :id "theme" :label "Theme" :value "dark"
               :values '("system" "dark" "light")
               :submenu :theme)))))
      (cadr-cli::settings-selector-open-submenu
       state
       (first (cadr-cli::settings-selector-state-options state)))
      (cadr-cli::settings-selector-handle-event
       state (cadr-tui:make-input-event :kind :up))
      (cadr-cli::settings-selector-handle-event
       state (cadr-tui:make-input-event :kind :enter))
      (is (eq :theme-automatic
              (cadr-cli::settings-selector-state-mode state)))
      (cadr-cli::settings-selector-handle-event
       state (cadr-tui:make-input-event :kind :enter))
      (is (eq :theme-light
              (cadr-cli::settings-selector-state-mode state)))
      (cadr-cli::settings-selector-handle-event
       state (cadr-tui:make-input-event :kind :escape))
      (is (eq :theme-automatic
              (cadr-cli::settings-selector-state-mode state)))
      (is (zerop
           (cadr-cli::settings-selector-state-submenu-selected state)))
      (cadr-cli::settings-selector-handle-event
       state (cadr-tui:make-input-event :kind :down))
      (cadr-cli::settings-selector-handle-event
       state (cadr-tui:make-input-event :kind :enter))
      (is (eq :theme-dark
              (cadr-cli::settings-selector-state-mode state)))))))

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
              (format nil "~C[38;2;95;168;204m~A~C[39m"
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
                      "~C[38;2;167;152;215m→ ~C[39m~C[38;2;167;152;215mAuto-compact~C[39m  ~C[38;2;167;152;215mtrue~C[39m"
                      #\Escape #\Escape #\Escape #\Escape
                      #\Escape #\Escape)
              ""
              (format nil
                      "~C[38;2;126;136;142m  Automatically compact context~C[39m"
                      #\Escape #\Escape)
              ""
              (format nil
                      "~C[38;2;126;136;142m  Type to search · Enter/Space to cha~C[0m...~C[0m"
                      #\Escape #\Escape #\Escape)
              (format nil "~C[38;2;95;168;204m~A~C[39m"
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
    (is (= 35
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
              :id "model-thinking"
              :label "Default thinking level per model"
              :description
              "Override the default thinking level for specific models."
              :value (list :overrides nil :global-default :low)
              :submenu :model-thinking)
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
       border (goal9-b3-full-width-line "Per-Model Thinking Level" width) ""
       (goal9-b3-full-width-line
        "Step 1/2 · Select a model to configure" width)
       ""
       (goal9-b3-full-width-input-line "" width)
       ""
       "→ No models available  Log in to a provider or configure an API key first"
       ""
       (goal9-b3-full-width-line
        "  Type to filter · Enter to select · Esc to go back" width)
       border)
      (goal9-b3-plain-lines
       (cadr-cli::render-settings-selector state width))))
    (cadr-cli::settings-selector-handle-event
     state (cadr-tui:make-input-event :kind :up))
    (is (= 0 (cadr-cli::settings-selector-state-submenu-selected state)))
    (cadr-cli::settings-selector-handle-event
     state (cadr-tui:make-input-event :kind :up))
    (is (= 0 (cadr-cli::settings-selector-state-submenu-selected state)))
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
       (goal9-b3-full-width-line
        "Select a theme, or choose automatic to follow terminal appearance."
        width)
       ""
       "    automatic  Use separate themes for light and dark terminal appearance"
       "→ ✓ dark"
       "    light"
       ""
       (goal9-b3-full-width-line
        "  Enter to select · Esc to go back" width)
       border)
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
       (goal9-b3-full-width-line
        "Light/dark detection requires terminal support." width)
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
             :id "model-thinking" :label "Model thinking"
             :value (list :overrides nil :global-default :low)
             :submenu :model-thinking)
            (cadr-cli::make-settings-option
             :id "theme" :label "Theme"
             :value "dark" :values '("dark" "light")
             :submenu :theme)))))
    (dolist (mode '(:warnings :model-thinking :theme-single
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
      "Alt+F queues follow-up messages"
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
