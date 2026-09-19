(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(test model-setting-key-uses-lowercase-provider-slash-model
  (is (string=
       "openai/gpt-5.5"
       (cadr-cli::model-setting-key :openai "gpt-5.5"))))

(test settings-thinking-levels-persist-and-remove
  (let ((manager (cadr-cli::make-memory-settings-manager)))
    (cadr-cli::settings-set-default-thinking-level manager :high)
    (is (eq :high (cadr-cli::settings-default-thinking-level manager)))
    (cadr-cli::settings-set-model-thinking-level
     manager :openai "gpt-5.5" :minimal)
    (is (eq :minimal
            (cadr-cli::settings-model-thinking-level
             manager :openai "gpt-5.5")))
    (is (equal
         '(("openai/gpt-5.5" . :minimal))
         (cadr-cli::settings-all-model-thinking-levels manager)))
    (cadr-cli::settings-remove-model-thinking-level
     manager :openai "gpt-5.5")
    (is (null
         (cadr-cli::settings-model-thinking-level
          manager :openai "gpt-5.5")))
    (is (null (cadr-cli::settings-all-model-thinking-levels manager)))))

(test set-cli-thinking-level-persists-only-when-requested
  (let* ((manager (cadr-cli::make-memory-settings-manager))
         (agent
           (cadr-agent:make-agent
            :model
            (cadr-ai::make-model
             :provider :openai
             :id "gpt-5.5"
             :context-window 200000
             :reasoning-p t))))
    (cadr-cli::set-cli-thinking-level agent manager :low)
    (is (eq :low (cadr-agent::agent-thinking-level agent)))
    (is (null
         (cadr-cli::settings-value
          manager "defaultThinkingLevel")))
    (cadr-cli::set-cli-thinking-level
     agent manager :high :persist t)
    (is (string=
         "high"
         (cadr-cli::settings-value
          manager "defaultThinkingLevel")))))

(test cli-thinking-level-for-model-switch-prefers-per-model-override
  (let* ((manager (cadr-cli::make-memory-settings-manager))
         (model
           (cadr-ai::make-model
            :provider :openai
            :id "gpt-5.5"
            :context-window 200000
            :reasoning-p t))
         (agent
           (cadr-agent:make-agent
            :model model)))
    (setf (cadr-agent::agent-thinking-level agent) :medium)
    (cadr-cli::settings-set-default-thinking-level manager :high)
    (cadr-cli::settings-set-model-thinking-level
     manager :openai "gpt-5.5" :minimal)
    (is (eq :minimal
            (cadr-cli::cli-thinking-level-for-model-switch
             agent manager model)))
    (cadr-cli::settings-remove-model-thinking-level
     manager :openai "gpt-5.5")
    (is (eq :high
            (cadr-cli::cli-thinking-level-for-model-switch
             agent manager model)))))

(test apply-cli-model-selection-skips-default-model-without-persist
  (with-test-directory (root)
    (let* ((config-path (merge-pathnames "config.json" root))
           (auth-path (merge-pathnames "auth.json" root))
           (settings-path (merge-pathnames "settings.json" root))
           (models-path (merge-pathnames "models.json" root))
           (settings
             (cadr-cli::make-settings-manager
              :global-path settings-path))
           (registry
             (cadr-cli::make-model-registry
              :path models-path
              :credentials
              (cadr-cli::make-file-auth-storage auth-path)))
           (model-a
             (cadr-ai::make-model
              :provider :openai
              :id "model-a"
              :context-window 128000
              :reasoning-p t))
           (model-b
             (cadr-ai::make-model
              :provider :openai
              :id "model-b"
              :context-window 128000
              :reasoning-p t))
           (agent
             (cadr-agent:make-agent
              :model model-a)))
      (setf (cadr-agent::agent-thinking-level agent) :medium)
      (cadr-cli::apply-cli-model-selection
       agent registry model-b settings
       :config-path config-path
       :auth-path auth-path)
      (is (cadr-ai:models-equal-p
           model-b (cadr-agent:agent-model agent)))
      (is (null (cadr-cli::settings-default-model settings)))
      (cadr-cli::apply-cli-model-selection
       agent registry model-b settings
       :config-path config-path
       :auth-path auth-path
       :persist t)
      (is (string=
           "model-b"
           (cadr-cli::settings-default-model settings))))))

(test thinking-selector-filter-and-persist-key
  (let* ((state
           (cadr-cli::make-thinking-selector-state
            :levels '(:off :low :medium :high)
            :current-level :medium
            :default-level :medium)))
    (cadr-cli::thinking-selector-set-query state "high")
    (is (equal '(:high)
               (cadr-cli::thinking-selector-state-filtered-levels
                state)))
    (multiple-value-bind (action level changed-p)
        (cadr-cli::thinking-selector-handle-raw-input
         state
         (string (code-char 19)))
      (is (eq :persist action))
      (is (eq :high level))
      (is (eq t changed-p)))))

(test sdk-settings-effective-thinking-level-resolution
  (let* ((manager
           (cadr-cli::make-memory-sdk-settings-manager))
         (model
           (cadr-ai::make-model
            :provider :openai
            :id "gpt-5.5"
            :context-window 200000
            :reasoning-p t)))
    (cadr-cli::sdk-settings-set
     manager "defaultThinkingLevel" "high")
    (cadr-cli::sdk-settings-set
     manager "modelThinkingLevels"
     (cadr-ai::json-object
      "openai/gpt-5.5" "minimal"))
    (is (eq :minimal
            (cadr-cli::sdk-settings-effective-thinking-level
             manager model)))
    (is (eq :low
            (cadr-cli::sdk-settings-effective-thinking-level
             manager model :low)))))

;; Regression: settings-model-thinking-sort-models must use LABELS so
;; DEFAULT-P can call KEY (FLET bindings are not mutually visible; the
;; g21 gate fail excerpt flagged KEY as an undefined function).
(test settings-model-thinking-sort-models-orders-current-then-default
  (let* ((alpha
           (cadr-ai::make-model
            :provider :anthropic
            :id "claude"
            :context-window 200000
            :reasoning-p t))
         (beta
           (cadr-ai::make-model
            :provider :openai
            :id "gpt-5.5"
            :context-window 200000
            :reasoning-p t))
         (gamma
           (cadr-ai::make-model
            :provider :openai
            :id "o3"
            :context-window 200000
            :reasoning-p t))
         (sorted
           (cadr-cli::settings-model-thinking-sort-models
            (list alpha gamma beta)
            gamma
            :openai
            "gpt-5.5")))
    (is (eq gamma (first sorted)))
    (is (eq beta (second sorted)))
    (is (eq alpha (third sorted)))))

(test model-thinking-submenu-filters-and-escapes-one-step
  (let* ((alpha
           (cadr-ai:make-model
            :provider :openai
            :id "alpha-model"
            :context-window 128000
            :reasoning-p t))
         (beta
           (cadr-ai:make-model
            :provider :openai
            :id "beta-model"
            :context-window 128000
            :reasoning-p t))
         (state
           (cadr-cli::make-settings-selector-state
            :available-models (list alpha beta)
            :options
            (list
             (cadr-cli::make-settings-option
              :id "model-thinking"
              :label "Default thinking level per model"
              :value (list :overrides nil
                           :global-default :low
                           :current-model alpha)
              :submenu :model-thinking)))))
    (cadr-cli::settings-selector-handle-event
     state (cadr-tui:make-input-event :kind :enter))
    (is (eq :model-thinking
            (cadr-cli::settings-selector-state-mode state)))
    (let ((rendered
            (format nil "~{~A~%~}"
                    (cadr-cli::render-settings-selector state 80))))
      (is (search "Step 1/2 · Select a model to configure" rendered))
      (is (search "Type to filter · Enter to select · Esc to go back"
                  rendered))
      (is (find-if
           (lambda (line)
             (and (plusp (length line))
                  (char= #\> (char line 0))))
           (cadr-cli::render-settings-selector state 80))))
    (cadr-cli::settings-selector-handle-event
     state (cadr-tui:make-input-event :kind :text :text "beta"))
    (is (string= "" (cadr-cli::settings-selector-state-query state)))
    (is (string= "beta"
                 (cadr-cli::settings-selector-state-submenu-query state)))
    (let ((options (cadr-cli::settings-selector-submenu-options state)))
      (is (= 1 (length options)))
      (is (search "beta-model"
                  (cadr-cli::settings-option-label (first options)))))
    (cadr-cli::settings-selector-handle-event
     state (cadr-tui:make-input-event :kind :enter))
    (is (eq :model-thinking-level
            (cadr-cli::settings-selector-state-mode state)))
    (let ((rendered
            (format nil "~{~A~%~}"
                    (cadr-cli::render-settings-selector state 100))))
      (is (search
           "Step 2/2 · Select default thinking level for this model"
           rendered))
      (is (not (search "Type to filter" rendered))))
    (cadr-cli::settings-selector-handle-event
     state (cadr-tui:make-input-event :kind :escape))
    (is (eq :model-thinking
            (cadr-cli::settings-selector-state-mode state)))
    (cadr-cli::settings-selector-handle-event
     state (cadr-tui:make-input-event :kind :escape))
    (is (eq :main (cadr-cli::settings-selector-state-mode state)))))

(test settings-submenu-click-selects-the-row
  (let* ((alpha
           (cadr-ai:make-model
            :provider :openai
            :id "alpha-model"
            :context-window 128000
            :reasoning-p t))
         (beta
           (cadr-ai:make-model
            :provider :openai
            :id "beta-model"
            :context-window 128000
            :reasoning-p t))
         (state
           (cadr-cli::make-settings-selector-state
            :available-models (list alpha beta)
            :theme-names '("alpha" "beta")
            :current-theme "alpha"
            :options
            (list
             (cadr-cli::make-settings-option
              :id "model-thinking"
              :label "Default thinking level per model"
              :value (list :overrides nil
                           :global-default :low
                           :current-model alpha)
              :submenu :model-thinking)))))
    (cadr-cli::settings-selector-handle-event
     state (cadr-tui:make-input-event :kind :enter))
    (let* ((lines (cadr-cli::render-settings-selector state 80))
           (row
             (position-if
              (lambda (line) (search "beta-model" line))
              lines)))
      (is (integerp (cadr-cli::settings-selector-state-list-origin state)))
      (is (integerp row))
      (is (null
           (cadr-cli::settings-selector-handle-mouse
            state (list :type :move :button :none) row)))
      (is (zerop
           (cadr-cli::settings-selector-state-submenu-selected state)))
      (is (cadr-cli::settings-selector-handle-mouse
           state (list :type :press :button :left) row))
      (is (search
           "beta-model"
           (cadr-cli::settings-option-label
            (nth
             (cadr-cli::settings-selector-state-submenu-selected state)
             (cadr-cli::settings-selector-submenu-options state)))))
      (is (cadr-cli::settings-selector-handle-mouse
           state (list :type :click :button :left) row))
      (is (eq :model-thinking-level
              (cadr-cli::settings-selector-state-mode state))))
    (setf (cadr-cli::settings-selector-state-mode state) :theme-single
          (cadr-cli::settings-selector-state-submenu-selected state) 0)
    (let* ((lines (cadr-cli::render-settings-selector state 80))
           (row
             (position-if
              (lambda (line) (search "beta" line))
              lines)))
      (is (integerp row))
      (is (cadr-cli::settings-selector-handle-mouse
           state (list :type :press :button :left) row))
      (is (cadr-cli::settings-selector-handle-mouse
           state (list :type :click :button :left) row))
      (is (eq :main (cadr-cli::settings-selector-state-mode state)))
      (is (string=
           "beta"
           (cadr-cli::settings-selector-state-single-theme state))))))

(test thinking-selector-click-selects-the-level
  (let ((state
          (cadr-cli::make-thinking-selector-state
           :levels '(:off :low :high)
           :current-level :off)))
    (let* ((lines (cadr-cli::render-thinking-selector state 80))
           (row
             (position-if
              (lambda (line) (search "high" line))
              lines)))
      (is (integerp
           (cadr-cli::thinking-selector-state-list-origin state)))
      (is (integerp row))
      (is (null
           (cadr-cli::thinking-selector-handle-mouse
            state (list :type :move :button :none) row)))
      (is (eq :off (cadr-cli::thinking-selector-selected-level state)))
      (is (null
           (cadr-cli::thinking-selector-handle-mouse
            state (list :type :press :button :left) 0)))
      (is (eq :off (cadr-cli::thinking-selector-selected-level state)))
      (is (cadr-cli::thinking-selector-handle-mouse
           state (list :type :press :button :left) row))
      (is (eq :high (cadr-cli::thinking-selector-selected-level state)))
      (multiple-value-bind (handled action value)
          (cadr-cli::thinking-selector-handle-mouse
           state (list :type :click :button :left) row)
        (is (not (null handled)))
        (is (eq :select action))
        (is (eq :high value))))))

(test thinking-search-press-inserts-at-the-cursor
  (let ((state
          (cadr-cli::make-thinking-selector-state
           :levels '(:off :low :high)
           :current-level :off)))
    (cadr-cli::thinking-selector-set-query state "hello")
    (cadr-cli::render-thinking-selector state 40)
    (let ((origin (cadr-cli::thinking-selector-state-input-origin state)))
      (is (integerp origin))
      (is (/= origin
              (cadr-cli::thinking-selector-state-list-origin state)))
      (is (null
           (cadr-cli::thinking-selector-handle-mouse
            state (list :type :press :button :left :x 4) 0)))
      (is (= 5 (cadr-cli::thinking-selector-state-query-cursor state)))
      (is (cadr-cli::thinking-selector-handle-mouse
           state (list :type :press :button :left :x 4) origin))
      (is (= 2 (cadr-cli::thinking-selector-state-query-cursor state)))
      (cadr-cli::thinking-selector-handle-event
       state (cadr-tui:make-input-event :kind :text :text "X"))
      (is (string= "heXllo"
                   (cadr-cli::thinking-selector-state-query state)))
      (cadr-cli::thinking-selector-handle-event
       state (cadr-tui:make-input-event :kind :backspace))
      (is (string= "hello"
                   (cadr-cli::thinking-selector-state-query state)))
      (is (= 2 (cadr-cli::thinking-selector-state-query-cursor state))))))

(test settings-submenu-search-press-inserts-at-the-cursor
  (let* ((alpha
           (cadr-ai:make-model
            :provider :openai
            :id "alpha-model"
            :context-window 128000
            :reasoning-p t))
         (state
           (cadr-cli::make-settings-selector-state
            :available-models (list alpha)
            :options
            (list
             (cadr-cli::make-settings-option
              :id "model-thinking"
              :label "Default thinking level per model"
              :value (list :overrides nil
                           :global-default :low
                           :current-model alpha)
              :submenu :model-thinking)))))
    (cadr-cli::settings-selector-handle-event
     state (cadr-tui:make-input-event :kind :enter))
    (cadr-cli::settings-selector-edit-submenu-query state "hello" 5)
    (cadr-cli::render-settings-selector state 80)
    (let ((origin
            (cadr-cli::settings-selector-state-submenu-input-origin state)))
      (is (integerp origin))
      (is (< origin
             (cadr-cli::settings-selector-state-list-origin state)))
      (is (null
           (cadr-cli::settings-selector-handle-mouse
            state (list :type :press :button :left :x 4) 0)))
      (is (= 5 (cadr-cli::settings-selector-state-submenu-query-cursor state)))
      (is (cadr-cli::settings-selector-handle-mouse
           state (list :type :press :button :left :x 4) origin))
      (is (= 2 (cadr-cli::settings-selector-state-submenu-query-cursor state)))
      (cadr-cli::settings-selector-handle-event
       state (cadr-tui:make-input-event :kind :text :text "X"))
      (is (string= "heXllo"
                   (cadr-cli::settings-selector-state-submenu-query state)))
      (cadr-cli::settings-selector-handle-event
       state (cadr-tui:make-input-event :kind :backspace))
      (is (string= "hello"
                   (cadr-cli::settings-selector-state-submenu-query state)))
      (is (= 2
             (cadr-cli::settings-selector-state-submenu-query-cursor state))))))
