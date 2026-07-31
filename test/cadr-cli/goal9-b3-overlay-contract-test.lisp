(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun goal9-b3-overlay-plain-lines (lines)
  (mapcar #'cadr-tui:strip-terminal-sequences lines))

(defun goal9-b3-overlay-border (width)
  (make-string width :initial-element #\─))

(defun goal9-b3-overlay-screen-snapshot
    (overlay &key (width 80) (rows 40))
  (let* ((state (cadr-cli::make-tui-state :model "mock"))
         (editor (cadr-tui:make-multiline-editor))
         (terminal
           (cadr-tui:make-virtual-terminal
            :columns width :rows rows))
         (renderer (cadr-tui:make-terminal-renderer terminal)))
    (multiple-value-bind (lines row column)
        (cadr-cli::render-tui-state
         state editor width rows :overlay overlay)
      (cadr-tui:render-frame
       renderer lines :cursor-row row :cursor-column column)
      (cadr-tui:virtual-terminal-snapshot terminal))))

(defun goal9-b3-overlay-screen-sha256 (overlay)
  (let ((octets
          (cadr-ai::sha256-bytes
           (cadr-ai::ensure-octets
            (format nil "~{~A~^~%~}"
                    (goal9-b3-overlay-screen-snapshot overlay))))))
    (format nil "~{~2,'0X~}" (coerce octets 'list))))

(defun goal9-b3-overlay-model (provider id name)
  (cadr-ai:make-model
   :id id :name name :provider provider :api :faux))

(defun goal9-b3-overlay-auth-options ()
  (list
   (cadr-cli::make-oauth-selector-option
    :id :openai-codex :name "OpenAI Codex"
    :auth-type :oauth :method-name "OpenAI Codex account"
    :status '(:type :oauth :source "stored credential"))
   (cadr-cli::make-oauth-selector-option
    :id :anthropic :name "Anthropic"
    :auth-type :api-key :method-name "Anthropic API key")))

(defun goal9-b3-overlay-screen-cases ()
  (let* ((one (goal9-b3-overlay-model :faux "one" "One Model"))
         (two (goal9-b3-overlay-model :other "two" "Two Model"))
         (settings-manager (cadr-cli::make-memory-settings-manager))
         (settings-model
           (cadr-ai:make-model
            :id "reasoning" :name "Reasoning"
            :provider :faux :api :openai-responses
            :reasoning-p t))
         (settings-agent
           (cadr-agent:make-agent
            :provider nil :model settings-model))
         (tree
           (cadr-cli::make-tree-selector-state
            :entries
            '((:id "u1" :parent-id nil :type :message
               :role :user :text "hello")
              (:id "a1" :parent-id "u1" :type :message
               :role :assistant :text "answer"))
            :current-leaf-id "a1")))
    (list
     (cons "model"
           (cadr-cli::make-model-selector-state
            :all-models (list one two) :current-model one))
     (cons "model-scoped"
           (cadr-cli::make-model-selector-state
            :all-models (list one two)
            :scoped-models (list two one)
            :current-model one
            :refresh-status-message "Model catalogs refreshed."))
     (cons "settings"
           (cadr-cli::make-cli-settings-selector-state
            settings-manager settings-agent
            (cadr-cli::make-resource-snapshot)
            :supports-images-p nil))
     (cons "resume"
           (cadr-cli::make-session-selector-state
            :current-sessions nil :all-sessions nil :all-loaded-p t))
     (cons "fork"
           (cadr-cli::make-user-message-selector-state
            :items
            (list
             (cadr-tui:make-select-item :label "first" :value "u1")
             (cadr-tui:make-select-item :label "second" :value "u2"))))
     (cons "tree" tree)
     (cons "scoped-models"
           (cadr-cli::make-scoped-models-selector-state
            :all-models (list one two) :enabled-ids '("faux/one")))
     (cons "trust"
           (cadr-cli::make-trust-selector-state
            :cwd "/tmp/project" :project-trusted-p nil))
     (cons "login-method"
           (cadr-cli::make-login-method-selector-state))
     (cons "login-provider"
           (cadr-cli::make-oauth-selector-state
            :mode :login :options (goal9-b3-overlay-auth-options)))
     (cons "logout-provider"
           (cadr-cli::make-oauth-selector-state
            :mode :logout :options (goal9-b3-overlay-auth-options)))
     (cons "api-key"
           (cadr-cli::make-api-key-input-state
            (second (goal9-b3-overlay-auth-options))))
     (cons "import"
           (cadr-cli::make-import-confirmation-list
            "/import '/tmp/session.jsonl'" "/tmp/session.jsonl"))
     (cons "extension-select"
           (cadr-cli::make-framed-select-state
            "Choose one" '("Alpha" "Beta") '("Alpha" "Beta")))
     (cons "extension-custom"
           (cadr-cli::make-extension-custom-ui-state
            :component
            (cadr-tui:make-select-list
             :items
             (list
              (cadr-tui:make-select-item :label "Alpha" :value 1)
              (cadr-tui:make-select-item :label "Beta" :value 2)))
            :done-function (constantly nil))))))

(test goal9-b3-every-overlay-has-an-exact-full-virtual-terminal-snapshot
  (let ((expected
          '(("model" . "B6745E0488E0957C87EBDABC50C3E2500827CCD647B4EEB459CACDCAE924B871")
            ("model-scoped" . "F82A3C2EF46D80A1A7A035028778AF4A71D68500F4952F3DDB3EDA67B555FC67")
            ("settings" . "FBE5F9D316EDAD157A2064D1F716A22580E33866BA31BB3BD5716C738A5FAD50")
            ("resume" . "764F89C0161E4934F63B7C270B3DAE5B9A5D27FC2F5315B69DE09EDC078B0DA9")
            ("fork" . "8E5E858ED0D8FA5B1737A979AA3AB096CD7FA4D57DAC60D6E66CDD1702733839")
            ("tree" . "7B6DF2F1CD06FFF9C3597BAD446717493050EB51ADE70A45475AE0DEE0B31566")
            ("scoped-models" . "69EB80FDF363216B91774219151C59D8FE52212CA677EE1B4772B1120DF0FC97")
            ("trust" . "91476A3411AD79385394054B0F1250067136A28086EEDF83A34C98E481626866")
            ("login-method" . "E8B9832D6CBD13D2E4275992BB026B78B5FC58952AD54BAD2302AD73B922822D")
            ("login-provider" . "D0BBBCD732D1DBD1CC63434C06A87E509817116694C4EC36B732383ABD9ABD6B")
            ("logout-provider" . "8B64091A84F4BF61281FC767B91955066B3C0472E575E864C266D34AE95D1424")
            ("api-key" . "A3E134010EAB3AC193B4F587DB22042515C633BD46A63953382F9B5E1CC2100C")
            ("import" . "9F523B226D7639B0449AE7F3E6E6980F7D1B10B1D17DD03DA4D494E208802E3E")
            ("extension-select" . "493B0D5F9A671AC464143BB174CBA9C73EF06D9C23F96A272B4A6EE6DEDD793C")
            ("extension-custom" . "1DC11B688FAF08EFD7B9BED1D7C5A5DD26396A9ECE368E7DA25BAABC3FD6FE35"))))
    (dolist (case (goal9-b3-overlay-screen-cases))
      (is
       (string=
        (cdr (assoc (car case) expected :test #'string=))
        (goal9-b3-overlay-screen-sha256 (cdr case)))))))

(test goal9-b3-model-overlays-have-complete-baseline-line-contracts
  (let* ((width 80)
         (border (goal9-b3-overlay-border width))
         (one (goal9-b3-overlay-model :faux "one" "One Model"))
         (two (goal9-b3-overlay-model :other "two" "Two Model")))
    (is
     (equal
      (list border ""
            "Only showing models from configured providers. Use /login to add providers."
            "" "> " "" "→ one [faux] ✓" "  two [other]" ""
            "  Model Name: One Model" "" border)
      (goal9-b3-overlay-plain-lines
       (cadr-cli::render-model-selector
        (cadr-cli::make-model-selector-state
         :all-models (list one two) :current-model one)
        width))))
    (is
     (equal
      (list border "" "Scope: all | scoped" "" "> " ""
            "  two [other]" "→ one [faux] ✓" ""
            "  Model Name: One Model" ""
            "  Model catalogs refreshed." "" border)
      (goal9-b3-overlay-plain-lines
       (cadr-cli::render-model-selector
        (cadr-cli::make-model-selector-state
         :all-models (list one two)
         :scoped-models (list two one)
         :current-model one
         :refresh-status-message "Model catalogs refreshed.")
        width))))))

(test goal9-b3-scoped-models-overlay-has-complete-baseline-line-contract
  (let* ((width 80)
         (border (goal9-b3-overlay-border width))
         (one (goal9-b3-overlay-model :faux "one" "One Model"))
         (two (goal9-b3-overlay-model :other "two" "Two Model"))
         (state
           (cadr-cli::make-scoped-models-selector-state
            :all-models (list one two)
            :enabled-ids '("faux/one" "missing/ghost"))))
    (is
     (equal
      (list border "" "Model Configuration"
            "Session-only. ctrl+s to save to settings." "" "> " ""
            "→ one [faux] ✓"
            "  missing/ghost [unavailable] ✗"
            "  two [other] ✗" "" "  Model Name: One Model" ""
            "enter toggle · ctrl+a all · ctrl+x clear · ctrl+p provider · alt+up/alt+down reo"
            border)
      (goal9-b3-overlay-plain-lines
       (cadr-cli::render-scoped-models-selector state width))))))

(test goal9-b3-resume-overlay-includes-query-prompt-and-every-line
  (let* ((now (cadr-ai::unix-milliseconds))
         (width 100)
         (border (goal9-b3-overlay-border width))
         (records
           (list
            (cadr-cli:make-session-search-record
             :id "one" :path "/tmp/one.jsonl" :name "Named One"
             :modified now :first-message "first prompt"
             :all-messages-text "first prompt")
            (cadr-cli:make-session-search-record
             :id "two" :path "/tmp/two.jsonl"
             :modified now :first-message "second prompt"
             :all-messages-text "second prompt")))
         (state
           (cadr-cli::make-session-selector-state
            :current-sessions records :all-sessions records
            :all-loaded-p t :show-rename-hint-p t)))
    (setf (cadr-cli::session-selector-state-query state) "prompt")
    (is
     (equal
      (list "" border ""
            "Resume Session (Current Folder)                  ◉ Current Folder | ○ All  Name: All  Sort: Threaded"
            "tab scope · re:<pattern> regex · \"phrase\" exact"
            "ctrl+s sort · ctrl+n named · ctrl+d delete · ctrl+p path (off) · ctrl+r rename"
            "" "> prompt" ""
            "› Named One                                                                                    0 now"
            "  second prompt                                                                                0 now"
            "" border)
      (goal9-b3-overlay-plain-lines
       (cadr-cli::render-session-selector state width))))))

(test goal9-b3-resume-overlay-search-empty-count-and-viewport-are-complete
  (let* ((now (cadr-ai::unix-milliseconds))
         (width 100)
         (border (goal9-b3-overlay-border width))
         (records
           (append
            (loop for index from 1 to 11
                  collect
                  (cadr-cli:make-session-search-record
                   :id (format nil "session-~2,'0D" index)
                   :path (format nil "/tmp/session-~2,'0D.jsonl" index)
                   :modified (- now index)
                   :first-message (format nil "Session ~2,'0D" index)
                   :all-messages-text (format nil "Session ~2,'0D" index)))
            (list
             (cadr-cli:make-session-search-record
              :id "zzyzx" :path "/tmp/zzyzx.jsonl"
              :modified (- now 100) :first-message "Zzyzx Session"
              :all-messages-text "Zzyzx Session"))))
         (state
           (cadr-cli::make-session-selector-state
            :current-sessions records :all-sessions records
            :all-loaded-p t)))
    (is
     (equal
      (append
       (list "" border ""
             "Resume Session (Current Folder)                  ◉ Current Folder | ○ All  Name: All  Sort: Threaded"
             "tab scope · re:<pattern> regex · \"phrase\" exact"
             "ctrl+s sort · ctrl+n named · ctrl+d delete · ctrl+p path (off)"
             "" "> " "")
       (loop for index from 1 to 10
             for label = (format nil "Session ~2,'0D" index)
             collect
             (concatenate
              'string
              (if (= index 1) "› " "  ")
              label
              (make-string 83 :initial-element #\Space)
              "0 now"))
       (list "  (1/12)" "" border))
      (goal9-b3-overlay-plain-lines
       (cadr-cli::render-session-selector state width))))
    (cadr-cli::session-selector-handle-event
     state
     (cadr-tui:make-input-event :kind :text :text "zzyzx"))
    (is
     (equal
      (list "" border ""
            "Resume Session (Current Folder)                  ◉ Current Folder | ○ All  Name: All  Sort: Threaded"
            "tab scope · re:<pattern> regex · \"phrase\" exact"
            "ctrl+s sort · ctrl+n named · ctrl+d delete · ctrl+p path (off)"
            "" "> zzyzx" ""
            (concatenate 'string "› Zzyzx Session"
                         (make-string 80 :initial-element #\Space)
                         "0 now")
            "" border)
      (goal9-b3-overlay-plain-lines
       (cadr-cli::render-session-selector state width))))
    (let ((empty
            (cadr-cli::make-session-selector-state
             :current-sessions nil :all-sessions nil
             :all-loaded-p t)))
      (is
       (equal
        (list "" border ""
              "Resume Session (Current Folder)                  ◉ Current Folder | ○ All  Name: All  Sort: Threaded"
              "tab scope · re:<pattern> regex · \"phrase\" exact"
              "ctrl+s sort · ctrl+n named · ctrl+d delete · ctrl+p path (off)"
              "" "> " ""
              "  No sessions in current folder. Press Tab to view all."
              "" border)
        (goal9-b3-overlay-plain-lines
         (cadr-cli::render-session-selector empty width)))))))

(test goal9-b3-fork-and-tree-overlays-have-complete-baseline-line-contracts
  (let ((border-80 (goal9-b3-overlay-border 80))
        (border-100 (goal9-b3-overlay-border 100)))
    (is
     (equal
      (list "" "Fork from Message"
            "Select a user message to copy the active path up to that point into a new"
            "session" "" border-80 ""
            "› first user message" "  Message 1 of 2" ""
            "  second user message" "  Message 2 of 2" "" "" border-80)
      (goal9-b3-overlay-plain-lines
       (cadr-cli::render-user-message-selector
        (cadr-cli::make-user-message-selector-state
         :items
         (list
          (cadr-tui:make-select-item :label "first user message" :value "u1")
          (cadr-tui:make-select-item :label "second user message" :value "u2"))
         :initial-selected-value "u1")
        80))))
    (is
     (equal
      (list "" border-100 "  Session Tree"
            "  ↑/↓ move · ←/→ page · ctrl+←/→ branch · ctrl+x copy · shift+l label · shift+t label time"
            "  filters ctrl+d/t/u/l/a · cycle ctrl+o/shift+ctrl+o"
            "  Type to search:" border-100 ""
            "  • user: hello" "› • assistant: answer" "  (2/2)" "" border-100)
      (goal9-b3-overlay-plain-lines
       (cadr-cli::render-tree-selector
        (cadr-cli::make-tree-selector-state
         :entries
         '((:id "u1" :parent-id nil :type :message :role :user :text "hello")
           (:id "a1" :parent-id "u1" :type :message :role :assistant :text "answer"))
         :current-leaf-id "a1")
        100))))))

(test goal9-b3-trust-overlay-has-complete-baseline-line-contract
  (let ((border (goal9-b3-overlay-border 80)))
    (is
     (equal
      (list border "" "Project trust" "/tmp/project/" ""
            "Saved decision: none" "Current session: untrusted" ""
            "→ Trust"
            "  Trust parent folder (/tmp/)" "  Do not trust" ""
            "↑↓ navigate  enter save  escape cancel" "" border)
      (goal9-b3-overlay-plain-lines
       (cadr-cli::render-trust-selector
        (cadr-cli::make-trust-selector-state
         :cwd "/tmp/project" :project-trusted-p nil)
        80))))))

(test goal9-b3-login-overlays-have-complete-baseline-line-contracts
  (let* ((width 80)
         (border (goal9-b3-overlay-border width))
         (options (goal9-b3-overlay-auth-options)))
    (is
     (equal
      (list border "" " Select authentication method:" ""
            " → Sign in with an account"
            "   Sign in with an API key" ""
            " ↑↓ navigate  enter select  escape/ctrl+c cancel" ""
            border)
      (goal9-b3-overlay-plain-lines
       (cadr-cli::render-login-method-selector
        (cadr-cli::make-login-method-selector-state) width))))
    (dolist
        (case
         `((:login
            (,border "" " Select provider to configure:" "" "> " ""
             " → OpenAI Codex [subscription] ✓ configured"
             "   Anthropic [API key] • unconfigured" "" ,border))
           (:logout
            (,border "" " Select provider to logout:" "" "> " ""
             " → OpenAI Codex [subscription] ✓ configured"
             "   Anthropic [API key] • unconfigured" "" ,border))))
      (destructuring-bind (mode expected) case
        (is
         (equal
          expected
          (goal9-b3-overlay-plain-lines
           (cadr-cli::render-oauth-selector
            (cadr-cli::make-oauth-selector-state
             :mode mode :options options)
            width))))))
    (is
     (equal
      (list border " Login to Anthropic" "" " Enter Anthropic API key"
            (concatenate 'string "> "
                         (make-string 78 :initial-element #\Space))
            " (escape/ctrl+c to cancel, enter to submit)" border)
      (goal9-b3-overlay-plain-lines
       (cadr-cli::render-api-key-input-state
       (cadr-cli::make-api-key-input-state (second options)) width))))))

(test goal9-b3-auth-overlays-preserve-baseline-semantic-styles
  (let* ((configured
           (cadr-cli::make-oauth-selector-option
            :id :openai-codex :name "OpenAI Codex"
            :auth-type :oauth
            :status '(:type :oauth :source "stored credential")))
         (mismatch
           (cadr-cli::make-oauth-selector-option
            :id :anthropic :name "Anthropic"
            :auth-type :api-key
            :status '(:type :oauth :source "stored credential")))
         (rendered
           (cadr-cli::render-oauth-selector
            (cadr-cli::make-oauth-selector-state
             :mode :login :options (list configured mismatch))
            80))
         (joined (format nil "~{~A~^~%~}" rendered)))
    (is
     (search
      (cadr-tui:theme-foreground
       :accent
       (cadr-tui:theme-bold
        "Select provider to configure:" :enabled-p t)
       :enabled-p t)
      joined))
    (is
     (search
      (cadr-tui:theme-foreground
       :accent "OpenAI Codex" :enabled-p t)
      joined))
    (is
     (search
      (cadr-tui:theme-foreground
       :success "✓ configured" :enabled-p t)
      joined))
    (is
     (search
      (cadr-tui:theme-foreground
       :warning "subscription configured" :enabled-p t)
      joined)))
  (let* ((option
           (second (goal9-b3-overlay-auth-options)))
         (rendered
           (cadr-cli::render-api-key-input-state
            (cadr-cli::make-api-key-input-state option) 80)))
    (is
     (search
      (cadr-tui:theme-foreground
       :accent
       (cadr-tui:theme-bold
        "Login to Anthropic" :enabled-p t)
       :enabled-p t)
      (second rendered)))
    (is (string= " Enter Anthropic API key"
                 (fourth rendered)))))

(defun goal9-b3-overlay-auth-option (index &key status)
  (cadr-cli::make-oauth-selector-option
   :id (intern (format nil "PROVIDER-~2,'0D" index) :keyword)
   :name (if (= index 10)
             "Zzyzx Provider"
             (format nil "Provider ~2,'0D" index))
   :auth-type (if (oddp index) :oauth :api-key)
   :method-name (format nil "Method ~2,'0D" index)
   :status status))

(test goal9-b3-auth-provider-selector-search-empty-count-and-viewport
  (let* ((width 80)
         (border (goal9-b3-overlay-border width))
         (options
           (loop for index from 1 to 10
                 collect (goal9-b3-overlay-auth-option index)))
         (state
           (cadr-cli::make-oauth-selector-state
            :mode :login :options options)))
    (is
     (equal
      (append
       (list border "" " Select provider to configure:" "" "> " "")
       (loop for index from 1 to 8
             collect
             (format nil " ~AProvider ~2,'0D [~A] • unconfigured"
                     (if (= index 1) "→ " "  ")
                     index
                     (if (oddp index) "subscription" "API key")))
       (list "  (1/10)" "" border))
      (goal9-b3-overlay-plain-lines
       (cadr-cli::render-oauth-selector state width))))
    (cadr-cli::oauth-selector-handle-event
     state
     (cadr-tui:make-input-event :kind :text :text "zzyzx"))
    (is (string= "zzyzx" (cadr-cli::oauth-selector-state-query state)))
    (is
     (equal
      (list border "" " Select provider to configure:" "" "> zzyzx" ""
            " → Zzyzx Provider [API key] • unconfigured" "" border)
      (goal9-b3-overlay-plain-lines
       (cadr-cli::render-oauth-selector state width))))
    (cadr-cli::oauth-selector-handle-event
     state
     (cadr-tui:make-input-event :kind :text :text "missing"))
    (is
     (equal
      (list border "" " Select provider to configure:" "" "> zzyzxmissing" ""
            "  No matching providers" "" border)
      (goal9-b3-overlay-plain-lines
       (cadr-cli::render-oauth-selector state width))))
    (let ((empty-login
            (cadr-cli::make-oauth-selector-state
             :mode :login :options nil))
          (empty-logout
            (cadr-cli::make-oauth-selector-state
             :mode :logout :options nil)))
      (is
       (member "  No providers available"
               (goal9-b3-overlay-plain-lines
                (cadr-cli::render-oauth-selector empty-login width))
               :test #'string=))
      (is
       (member "  No providers logged in. Use /login first."
               (goal9-b3-overlay-plain-lines
                (cadr-cli::render-oauth-selector empty-logout width))
               :test #'string=)))))

(test goal9-b3-logout-provider-options-project-stored-credentials
  (let* ((openai
           (cadr-ai::make-provider-definition
            :id :openai-codex :name "OpenAI Codex"
            :protocol :openai-responses
            :base-url "https://example.invalid"
            :auth-types '(:oauth)
            :default-model "gpt"))
         (options
           (cadr-cli::logout-provider-options
            (list openai)
            '(("openai-codex" . "oauth")
              ("custom-proxy" . "api_key")))))
    (is
     (equal '(:custom-proxy :openai-codex)
            (mapcar #'cadr-cli::oauth-selector-option-id options)))
    (is
     (equal '("custom-proxy" "OpenAI Codex")
            (mapcar #'cadr-cli::oauth-selector-option-name options)))
    (is
     (every
      (lambda (option)
        (string= "stored credential"
                 (getf (cadr-cli::oauth-selector-option-status option)
                       :source)))
      options))))

(test goal9-b3-import-and-extension-overlays-have-complete-baseline-line-contracts
  (let ((border (goal9-b3-overlay-border 80)))
    (is
     (equal
      (list border "" " Import session"
            " Replace current session with /tmp/session.jsonl?" ""
            " → Yes" "   No" ""
            " ↑↓ navigate  enter select  escape/ctrl+c cancel" "" border)
      (goal9-b3-overlay-plain-lines
       (cadr-cli::render-framed-select-state
        (cadr-cli::make-import-confirmation-list
         "/import '/tmp/session.jsonl'" "/tmp/session.jsonl")
        80))))
    (dolist
        (case
         (list
          (list "Choose one" '("Alpha" "Beta"))
          (list (format nil "Confirm action~%Proceed?")
                '("Yes" "No"))))
      (destructuring-bind (title labels) case
        (let* ((state
                 (cadr-cli::make-framed-select-state
                  title labels labels))
               (title-lines
                 (uiop:split-string title :separator '(#\Newline))))
          (is
           (equal
            (append
             (list border "")
             (mapcar (lambda (line)
                       (concatenate 'string " " line))
                     title-lines)
             (list "")
             (loop for label in labels
                   for first-p = t then nil
                   collect
                   (format nil " ~A~A"
                           (if first-p "→ " "  ") label))
             (list "" " ↑↓ navigate  enter select  escape/ctrl+c cancel" "" border))
            (goal9-b3-overlay-plain-lines
             (cadr-cli::render-framed-select-state state 80)))))))))

(test goal9-b3-extension-selector-styles-countdown-keys-and-tool-toggle-are-exact
  (let* ((keybindings
           (cadr-tui:make-keybindings-manager
            :user-bindings
            '(("tui.select.confirm" . ("alt+y"))
              ("tui.select.cancel" . ("alt+x")))))
         (toggle-count 0)
         (state
           (cadr-cli::make-framed-select-state
            "Choose one" '("Alpha" "Beta") '(1 2)
            :message "Pick exactly one"
            :keybindings keybindings
            :toggle-tools-function (lambda () (incf toggle-count)))))
    (setf (cadr-cli::framed-select-state-deadline state) 13d0)
    (let* ((rendered
             (cadr-cli::render-framed-select-state
              state 40 :now 10d0))
           (plain (goal9-b3-overlay-plain-lines rendered)))
      (is
       (equal
        (list
         (goal9-b3-overlay-border 40) ""
         " Choose one (3s)" " Pick exactly one" ""
         " → Alpha" "   Beta" ""
         " ↑↓ navigate  alt+y select  alt+x cancel" ""
         (goal9-b3-overlay-border 40))
        plain))
      (is
       (search
        (cadr-tui:theme-foreground
         :accent
         (cadr-tui:theme-bold "Choose one (3s)" :enabled-p t)
         :enabled-p t)
        (third rendered))))
    (multiple-value-bind (action value handled-p)
        (cadr-cli::framed-select-state-handle-raw-input
         state (format nil "~C[A" #\Escape))
      (is (eq :changed action))
      (is (null value))
      (is (not (null handled-p)))
      (is (= 1
             (cadr-tui::select-list-selected
              (cadr-cli::framed-select-state-select-list state)))))
    (let ((cadr-tui::*kitty-protocol-active-p* nil))
      (multiple-value-bind (action value handled-p)
          (cadr-cli::framed-select-state-handle-raw-input
           state (format nil "~Cy" #\Escape))
        (is (eq :select action))
        (is (= 2 value))
        (is (not (null handled-p)))))
    (multiple-value-bind (action value)
        (cadr-cli::framed-select-state-handle-event
         state (cadr-tui:make-input-event :kind :toggle-tools))
      (is (eq :changed action))
      (is (null value))
      (is (= 1 toggle-count)))))

(test goal9-b3-extension-select-runs-through-the-live-tui-overlay-bridge
  (let ((extension-ui nil)
        (worker nil)
        (result :pending)
        (terminal nil))
    (setf
     terminal
     (make-instance
      'footer-sync-test-terminal
      :columns 80 :rows 14
      :inputs
      (list
       (footer-sync-submit-input "/extension-select")
       (format nil "~C[B~C" #\Escape #\Return)
       (footer-sync-submit-input "/quit"))
      :before-second-read
      (lambda ()
        (loop repeat 200
              until worker
              do (sleep 0.005)
              finally
              (unless worker
                (error "Extension select worker was never started")))
        (sleep 0.02))))
    (cadr-cli::run-tui
     (constantly nil)
     :model "mock"
     :terminal terminal
     :set-extension-ui-function
     (lambda (function)
       (setf extension-ui function))
     :command-function
     (lambda (line)
       (when (string= line "/extension-select")
         (setf
          worker
          (sb-thread:make-thread
           (lambda ()
             (setf result
                   (funcall
                    extension-ui :select
                    '(:title "Choose value"
                      :options ("One" "Two"))))))))
       t))
    (when worker
      (sb-thread:join-thread worker))
    (is (string= "Two" result))))

(test goal9-b3-extension-confirm-runs-through-the-live-tui-overlay-bridge
  (let ((extension-ui nil)
        (worker nil)
        (result :pending))
    (cadr-cli::run-tui
     (constantly nil)
     :model "mock"
     :terminal
     (make-instance
      'footer-sync-test-terminal
      :columns 80 :rows 14
      :inputs
      (list
       (footer-sync-submit-input "/extension-confirm")
       (string #\Return)
       (footer-sync-submit-input "/quit"))
      :before-second-read
      (lambda ()
        (loop repeat 200
              until worker
              do (sleep 0.005)
              finally
              (unless worker
                (error "Extension confirm worker was never started")))
        (sleep 0.02)))
     :set-extension-ui-function
     (lambda (function)
       (setf extension-ui function))
     :command-function
     (lambda (line)
       (when (string= line "/extension-confirm")
         (setf
          worker
          (sb-thread:make-thread
           (lambda ()
             (setf result
                   (funcall
                    extension-ui :confirm
                    '(:title "Confirm action"
                      :message "Proceed?")))))))
       t))
    (when worker
      (sb-thread:join-thread worker))
    (is (eq t result))))

(test goal9-b3-settings-theme-preview-cancel-and-commit-use-the-live-tui-bridge
  (let ((current-theme "dark")
        (previews nil)
        (commits nil)
        (state nil)
        (capabilities
          (cadr-tui:make-terminal-capabilities
           :true-color-p t)))
    (setf
     state
     (cadr-cli::make-settings-selector-state
      :theme-names '("dark" "light")
      :current-theme current-theme
      :options
      (list
       (cadr-cli::make-settings-option
        :id "theme" :label "Theme"
        :description "Color theme for the interface"
        :value current-theme :values '("dark" "light")
        :submenu :theme))
      :change-callback
      (lambda (id value)
        (when (string= id "theme")
          (setf current-theme value)
          (push value commits)))))
    (cadr-tui:set-current-theme
     :dark :capabilities capabilities)
    (unwind-protect
         (progn
           (cadr-cli::run-tui
            (constantly nil)
            :model "mock"
            :terminal
            (make-instance
             'footer-sync-test-terminal
             :columns 80 :rows 18
             :inputs
             (list
              (footer-sync-submit-input "/settings")
              (string #\Return)
              (format nil "~C[B" #\Escape)
              (string (code-char 3))
              (string #\Return)
              (format nil "~C[B" #\Escape)
              (string #\Return)
              (string (code-char 3))
              (footer-sync-submit-input "/quit"))
             :before-second-read (constantly nil))
            :settings-selector-function (lambda () state)
            :theme-function
            (lambda () (list :name current-theme :path nil))
            :preview-theme-function
            (lambda (theme-setting)
              (push theme-setting previews)
              (list :name
                    (if (string= theme-setting "dark/dark")
                        "dark"
                        theme-setting)
                    :path nil)))
           (is (equal '("light") commits))
           (is
            (equal '("light" "dark" "light")
                   (nreverse previews)))
           (is
            (eq :light
                (cadr-tui::terminal-theme-name
                 (cadr-tui:current-theme)))))
      (cadr-tui:reset-current-theme))))

(test goal9-b3-autocomplete-popup-has-complete-line-contract
  (let* ((provider
           (cadr-tui:make-autocomplete-provider
            :commands
            (list
             (cadr-tui:make-autocomplete-command
              :name "alpha" :description "First command")
             (cadr-tui:make-autocomplete-command
              :name "alpine" :description "Second command"))))
         (editor
           (cadr-tui:make-multiline-editor :text "/al")))
    (cadr-tui:editor-set-autocomplete-provider editor provider)
    (setf (cadr-tui::multiline-editor-cursor editor) 3)
    (cadr-tui::editor-refresh-autocomplete editor)
    (cadr-tui:editor-handle-event
     editor (cadr-tui:make-input-event :kind :up))
    (is (= 1 (cadr-tui::multiline-editor-autocomplete-selected editor)))
    (cadr-tui:editor-handle-event
     editor (cadr-tui:make-input-event :kind :down))
    (is (zerop
         (cadr-tui::multiline-editor-autocomplete-selected editor)))
    (is
     (equal
      (list
       (format nil "~80A" "→ alpine      Second command")
       (format nil "~80A" "  alpha       First command"))
      (goal9-b3-overlay-plain-lines
       (cadr-tui::render-editor-autocomplete editor 80))))))

(test goal9-b3-at-path-autocomplete-has-an-exact-full-screen-and-wraps
  (with-test-directory (directory)
    (write-text (merge-pathnames "alpha.txt" directory) "alpha")
    (ensure-directories-exist
     (merge-pathnames "alpine/anchor" directory))
    (let* ((provider
             (cadr-tui:make-autocomplete-provider
              :base-path directory
              :fd-path #P"/root/.local/bin/fd"))
           (editor
             (cadr-tui:make-multiline-editor :text "@a")))
      (cadr-tui:editor-set-autocomplete-provider editor provider)
      (setf (cadr-tui::multiline-editor-cursor editor) 2)
      (cadr-tui::editor-refresh-autocomplete editor :force-p t)
      (let ((initial
              (goal9-b3-overlay-plain-lines
               (cadr-tui::render-editor-autocomplete editor 40))))
        (is
         (equal
          (list
           (format nil "~40A" "→ alpine/")
           (format nil "~40A" "  alpha.txt"))
          initial)))
      (cadr-tui:editor-handle-event
       editor (cadr-tui:make-input-event :kind :up))
      (is (= 1
             (cadr-tui::multiline-editor-autocomplete-selected editor)))
      (cadr-tui:editor-handle-event
       editor (cadr-tui:make-input-event :kind :down))
      (is (zerop
           (cadr-tui::multiline-editor-autocomplete-selected editor)))
      (multiple-value-bind (lines row column)
          (cadr-tui:render-editor editor 40 :terminal-rows 8)
        (let* ((terminal
                 (cadr-tui:make-virtual-terminal
                  :columns 40 :rows 8))
               (renderer
                 (cadr-tui:make-terminal-renderer terminal)))
          (cadr-tui:render-frame
           renderer lines :cursor-row row :cursor-column column)
          (is
           (equal
            '("────────────────────────────────────────"
              "@a                                      "
              "────────────────────────────────────────"
              "→ alpine/                               "
              "  alpha.txt                             "
              ""
              ""
              "")
            (cadr-tui:virtual-terminal-snapshot terminal))))))))

(test goal9-b3-builtin-autocomplete-command-contract-matches-baseline
  (is
   (equal
    '(("settings" "Open settings menu" nil)
      ("model" "Select model (opens selector UI)" "<provider/model>")
      ("scoped-models" "Enable/disable models for Ctrl+P cycling" nil)
      ("export" "Export session (HTML default, or specify path: .html/.jsonl)" nil)
      ("import" "Import and resume a session from a JSONL file" nil)
      ("share" "Share session as a secret GitHub gist" nil)
      ("copy" "Copy last agent message to clipboard" nil)
      ("name" "Set session display name" nil)
      ("session" "Show session info and stats" nil)
      ("changelog" "Show changelog entries" nil)
      ("hotkeys" "Show all keyboard shortcuts" nil)
      ("fork" "Create a new fork from a previous user message" nil)
      ("clone" "Duplicate the current session at the current position" nil)
      ("tree" "Navigate session tree (switch branches)" nil)
      ("trust" "Save project trust decision for future sessions" nil)
      ("login" "Configure provider authentication" "<provider>")
      ("logout" "Remove provider authentication" nil)
      ("new" "Start a new session" nil)
      ("compact" "Manually compact the session context" nil)
      ("resume" "Resume a different session" nil)
      ("reload" "Reload keybindings, extensions, skills, prompts, themes, and context files" nil)
      ("quit" "Quit cadr" nil))
    cadr-cli::+tui-autocomplete-command-specifications+))
  (dolist (forbidden '("sessions" "switch" "branch" "install"))
    (is
     (not
      (member forbidden
              cadr-cli::+tui-autocomplete-command-specifications+
              :key #'first :test #'string=)))))

(test goal9-b3-nonbaseline-command-names-do-not-open-tui-overlays
  (let ((commands nil))
    (cadr-cli::run-tui
     (constantly nil)
     :model "mock"
     :terminal
     (make-instance
      'footer-sync-test-terminal
      :columns 80 :rows 14
      :inputs
      (append
       (mapcar #'footer-sync-submit-input
               '("/sessions" "/switch id" "/branch id" "/install url"))
       (list (footer-sync-submit-input "/quit")))
      :before-second-read (constantly nil))
     :command-function
     (lambda (line)
       (push line commands)
       t))
    (is
     (equal
      '("/sessions" "/switch id" "/branch id" "/install url")
      (nreverse commands)))))

(test goal9-b3-compact-export-and-reload-use-command-status-paths-not-overlays
  (let ((commands nil))
    (cadr-cli::run-tui
     (constantly nil)
     :model "mock"
     :terminal
     (make-instance
      'footer-sync-test-terminal
      :columns 80 :rows 14
      :inputs
      (append
       (mapcar #'footer-sync-submit-input
               '("/compact" "/export" "/reload"))
       (list (footer-sync-submit-input "/quit")))
      :before-second-read (constantly nil))
     :command-function
     (lambda (line)
       (push line commands)
       (format nil "handled ~A" line)))
    (is
     (equal
      '("/compact" "/export" "/reload")
      (nreverse commands)))))

(test goal9-b3-model-and-login-argument-autocomplete-match-baseline-items
  (let* ((model
           (goal9-b3-overlay-model
            :openai-codex "gpt-test" "GPT Test"))
         (auth-options
           (list
            (cadr-cli::make-oauth-selector-option
             :id :openai-codex :name "OpenAI Codex"
             :auth-type :oauth)
            (cadr-cli::make-oauth-selector-option
             :id :openai-codex :name "OpenAI Codex"
             :auth-type :api-key)))
         (provider
           (cadr-cli::make-tui-autocomplete-provider
            :model-items-function
            (lambda ()
              (list
               (cadr-tui:make-select-item
                :label "ignored" :value model)))
            :login-options-function
            (lambda () auth-options))))
    (dolist
        (case
         (list
          (list "/model gpt"
                "openai-codex/gpt-test"
                "gpt-test" "openai-codex")
          (list "/login open"
                "openai-codex"
                "openai-codex"
                "OpenAI Codex · subscription/API key")))
      (destructuring-bind
            (input value label description)
          case
        (let* ((suggestions
                 (cadr-tui:autocomplete-get-suggestions
                  provider (list input) 0 (length input)))
               (item
                 (first
                  (cadr-tui:autocomplete-suggestions-items
                   suggestions))))
          (is (string= value
                       (cadr-tui:autocomplete-item-value item)))
          (is (string= label
                       (cadr-tui:autocomplete-item-label item)))
          (is (string= description
                       (cadr-tui:autocomplete-item-description item))))))))

(defun goal9-b3-assert-select-list-wraps (selector)
  (cadr-tui:select-list-handle-event
   selector (cadr-tui:make-input-event :kind :up))
  (is (= 1 (cadr-tui::select-list-selected selector)))
  (cadr-tui:select-list-handle-event
   selector (cadr-tui:make-input-event :kind :down))
  (is (zerop (cadr-tui::select-list-selected selector))))

(test goal9-b3-login-method-selector-wraps-both-ways
  (goal9-b3-assert-select-list-wraps
   (cadr-cli::login-method-selector-state-select-list
    (cadr-cli::make-login-method-selector-state))))

(test goal9-b3-import-confirmation-selector-wraps-both-ways
  (goal9-b3-assert-select-list-wraps
   (cadr-cli::framed-select-state-select-list
    (cadr-cli::make-import-confirmation-list "line" "path"))))

(test goal9-b3-extension-custom-selector-wraps-both-ways
  (goal9-b3-assert-select-list-wraps
   (cadr-tui:make-select-list
    :items
    (list
     (cadr-tui:make-select-item :label "One" :value 1)
     (cadr-tui:make-select-item :label "Two" :value 2)))))

(defun goal9-b3-assert-state-selector-wraps
    (state handler reader last-index)
  (funcall handler state
           (cadr-tui:make-input-event :kind :up))
  (is (= last-index (funcall reader state)))
  (funcall handler state
           (cadr-tui:make-input-event :kind :down))
  (is (zerop (funcall reader state))))

(test goal9-b3-session-selector-wraps-both-ways
  (let ((now (cadr-ai::unix-milliseconds)))
    (goal9-b3-assert-state-selector-wraps
     (cadr-cli::make-session-selector-state
      :current-sessions
      (list
       (cadr-cli:make-session-search-record
        :id "one" :path "/tmp/one" :modified now)
       (cadr-cli:make-session-search-record
        :id "two" :path "/tmp/two" :modified now)))
     #'cadr-cli::session-selector-handle-event
     #'cadr-cli::session-selector-state-selected 1)))

(test goal9-b3-fork-selector-wraps-both-ways
  (goal9-b3-assert-state-selector-wraps
   (cadr-cli::make-user-message-selector-state
    :items
    (list
     (cadr-tui:make-select-item :label "One" :value "one")
     (cadr-tui:make-select-item :label "Two" :value "two"))
    :initial-selected-value "one")
   #'cadr-cli::user-message-selector-handle-event
   #'cadr-cli::user-message-selector-state-selected 1))

(test goal9-b3-tree-selector-wraps-both-ways
  (let ((state
          (cadr-cli::make-tree-selector-state
           :entries
           '((:id "one" :parent-id nil
              :type :message :role :user :text "one")
             (:id "two" :parent-id "one"
              :type :message :role :assistant :text "two"))
           :current-leaf-id "one")))
    (cadr-cli::tree-selector-handle-event
     state (cadr-tui:make-input-event :kind :up))
    (is (string= "two"
                 (cadr-cli::tree-selector-state-selected-id state)))
    (cadr-cli::tree-selector-handle-event
     state (cadr-tui:make-input-event :kind :down))
    (is (string= "one"
                 (cadr-cli::tree-selector-state-selected-id state)))))

(test goal9-b3-trust-selector-wraps-both-ways
  (goal9-b3-assert-state-selector-wraps
   (cadr-cli::make-trust-selector-state :cwd "/tmp/project")
   #'cadr-cli::trust-selector-handle-event
   #'cadr-cli::trust-selector-state-selected 2))

(test goal9-b3-auth-provider-selector-wraps-both-ways
  (goal9-b3-assert-state-selector-wraps
   (cadr-cli::make-oauth-selector-state
    :options (goal9-b3-overlay-auth-options))
   #'cadr-cli::oauth-selector-handle-event
   #'cadr-cli::oauth-selector-state-selected 1))

(test goal9-b3-model-selector-wraps-both-ways
  (let ((one (goal9-b3-overlay-model :faux "one" "One"))
        (two (goal9-b3-overlay-model :other "two" "Two")))
    (goal9-b3-assert-state-selector-wraps
     (cadr-cli::make-model-selector-state
      :all-models (list one two) :current-model one)
     #'cadr-cli::model-selector-handle-event
     #'cadr-cli::model-selector-state-selected 1)))

(test goal9-b3-scoped-models-selector-wraps-both-ways
  (let ((one (goal9-b3-overlay-model :faux "one" "One"))
        (two (goal9-b3-overlay-model :other "two" "Two")))
    (goal9-b3-assert-state-selector-wraps
     (cadr-cli::make-scoped-models-selector-state
      :all-models (list one two))
     #'cadr-cli::scoped-models-selector-handle-event
     #'cadr-cli::scoped-models-selector-state-selected 1)))
