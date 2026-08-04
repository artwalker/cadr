(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun goal9-b3-overlay-plain-lines (lines)
  (mapcar #'cadr-tui:strip-terminal-sequences lines))

(defun goal9-b3-overlay-border (width)
  (make-string width :initial-element #\─))

(defun goal9-b3-overlay-input-line (value width)
  ;; pi's Input owns the complete terminal row.  Keep this exact contract
  ;; separate from the SHA so trailing cells cannot silently disappear.
  (let* ((prefix (concatenate 'string "> " value))
         (padding
           (max 0 (- width (cadr-tui:visible-width prefix)))))
    (concatenate
     'string prefix
     (make-string padding :initial-element #\Space))))

(defun goal9-b3-overlay-text-line (value width)
  ;; pi@74caa2649 Text/TruncatedText owns the complete row.  This oracle is
  ;; intentionally implemented from the baseline width contract instead of
  ;; calling Cadr's selector helpers.
  (let* ((limited
           (if (> (length value) width)
               (subseq value 0 width)
               value))
         (padding
           (max 0 (- width (cadr-tui:visible-width limited)))))
    (concatenate
     'string limited
     (make-string padding :initial-element #\Space))))

(defun goal9-b3-overlay-screen-snapshot
    (overlay &key (width 80) (rows 60))
  (let* ((state
           (cadr-cli::make-tui-state
            :model "mock"
            :messages
            (list
             (cadr-ai:make-user-message
              :content "overlay transcript user")
             (cadr-ai:make-assistant-message
              :api :openai-responses
              :provider :openai
              :model "mock"
              :content
              (list
               (cadr-ai:make-text-content
                :text "overlay transcript assistant"))
              :stop-reason :stop))))
         (editor (cadr-tui:make-multiline-editor))
         (terminal
           (cadr-tui:make-virtual-terminal
            :columns width :rows rows))
         (renderer (cadr-tui:make-terminal-renderer terminal)))
    (cadr-tui:editor-set-text
     editor "OVERLAY-EDITOR-MUST-BE-HIDDEN")
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

(test goal15-overlay-cursor-contract-follows-the-focused-input-component
  ;; Fixed pi@74caa2649 input components own the cursor.  Selectors without an
  ;; Input/Focusable component return no cursor metadata at all; they do not
  ;; invent a (0, 0) cursor that the terminal renderer can accidentally show.
  (let ((expected
          '(("model" 4 2)
            ("model-scoped" 5 2)
            ("settings" 1 2)
            ("resume" 7 2)
            ("fork" nil nil)
            ("tree" nil nil)
            ("scoped-models" 5 2)
            ("trust" nil nil)
            ("login-method" nil nil)
            ("login-provider" 4 2)
            ("logout-provider" 4 2)
            ("api-key" 4 2)
            ("import" nil nil)
            ("extension-select" nil nil)
            ("extension-custom" nil nil))))
    (dolist (case (goal9-b3-overlay-screen-cases))
      (destructuring-bind (name expected-row expected-column)
          (assoc (car case) expected :test #'string=)
        (declare (ignore name))
        (multiple-value-bind (lines row column)
            (cadr-cli::render-tui-overlay-lines (cdr case) 80 0d0)
          (declare (ignore lines))
          (is (eql expected-row row))
          (is (eql expected-column column)))))))

(test goal15-overlay-viewport-crops-the-natural-document-and-hides-offscreen-cursor
  ;; pi@74caa2649 Tui.ts:1076-1151 lays components out at natural height,
  ;; then the terminal viewport selects the visible rows.  A focused Input
  ;; above that viewport does not leak a synthetic cursor onto the screen.
  (let* ((models
           (loop for index below 14
                 collect
                 (goal9-b3-overlay-model
                  :faux
                  (format nil "model-~2,'0D" index)
                  (format nil "Model ~D" index))))
         (overlay
           (cadr-cli::make-model-selector-state
            :all-models models
            :current-model (first models)))
         (terminal
           (cadr-tui:make-virtual-terminal
            :columns 80 :rows 10))
         (renderer
           (cadr-tui:make-terminal-renderer
            terminal :alt-p t
            :show-hardware-cursor-p t)))
    (multiple-value-bind (lines row column)
        (cadr-cli::render-tui-overlay-lines overlay 80 0d0)
      (is (= 21 (length lines)))
      (is (= 4 row))
      (let ((output
              (cadr-tui:render-frame
               renderer lines
               :cursor-row row :cursor-column column)))
        (is (= 11 (cadr-tui:renderer-viewport-top renderer)))
        (is (search (format nil "~C[?25l" #\Escape) output))
        (is (null (search (format nil "~C[?25h" #\Escape) output)))
        (is
         (equal
          (mapcar
           (lambda (line)
             (string-right-trim
              '(#\Space)
              (cadr-tui:strip-terminal-sequences line)))
           (last lines 10))
          (mapcar
           (lambda (line)
             (string-right-trim '(#\Space) line))
           (cadr-tui:virtual-terminal-snapshot terminal))))))))

(defparameter +goal9-b3-overlay-baseline-semantic-oracles+
  ;; Each row is copied from the fixed pi@74caa2649 component contract named
  ;; in its second field.  The ordered strings are intentionally independent
  ;; of Cadr's SHA fixtures and rendering implementation.
  '(("model"
     "components/model-selector.ts:91-130,162-185,248-307"
     ("Only showing models from configured providers. Use /login to add providers."
      ">" "→ one [faux] ✓" "two [other]" "Model Name: One Model"))
    ("model-scoped"
     "components/model-selector.ts:91-130,162-185,248-307"
     ("Scope: all | scoped" "tab scope (all/scoped)" ">"
      "two [other]" "→ one [faux] ✓"
      "Model Name: One Model" "Model catalogs refreshed."))
    ("settings"
     "components/settings-selector.ts:472-738; packages/tui/src/components/settings-list.ts:80-165,237-249"
     (">" "→ Auto-compact" "Auto-resize images" "Block images"
      "Skill commands" "Show hardware cursor" "Editor padding"
      "Output padding" "Autocomplete max items" "Clear on shrink"
      "Terminal progress" "(1/25)"
      "Automatically compact context when it gets too large"
      "Type to search · Enter/Space to change · Esc to cancel"))
    ("resume"
     "components/session-selector.ts:119-175,414-519,685-746"
     ("Resume Session (Current Fold" "tab scope · re:<pattern> regex"
      "ctrl+s sort · ctrl+n named · ctrl+d delete · ctrl+p path (off)"
      ">" "No sessions in current folder. Press Tab to view all."))
    ("fork"
     "components/user-message-selector.ts:14-78,110-148"
     ("Fork from Message"
      "Select a user message to copy the active path up to that point into a new"
      "session" "first" "Message 1 of 2" "second" "Message 2 of 2"))
    ("tree"
     "components/tree-selector.ts:664-851,1156-1252,1328-1385"
     ("Session Tree" "↑/↓ move · ←/→ page · ctrl+←/→ branch"
      "filters ctrl+d/t/u/l/a" "Type to search:"
      "user: hello" "assistant: answer" "(2/2)"))
    ("scoped-models"
     "components/scoped-models-selector.ts:91-180,202-252"
     ("Model Configuration" "Session-only. ctrl+s to save to settings."
      ">" "→ one [faux] ✓" "two [other] ✗" "Model Name: One Model"
      "enter toggle · ctrl+a all · ctrl+x clear · ctrl+p provider"))
    ("trust"
     "components/trust-selector.ts:32-115"
     ("Project trust" "/tmp/project" "Saved decision: none"
      "Current session: untrusted" "→ Trust" "Trust parent folder (/tmp)"
      "Do not trust" "↑↓ navigate  enter save  escape/ctrl+c cancel"))
    ("login-method"
     "interactive-mode.ts:5014-5039; components/extension-selector.ts:18-78"
     ("Select authentication method:" "→ Sign in with an account"
      "Sign in with an API key"
      "↑↓ navigate  enter select  escape/ctrl+c cancel"))
    ("login-provider"
     "components/oauth-selector.ts:51-160"
     ("Select provider to configure:" ">"
      "→ OpenAI Codex [subscription] ✓ configured"
      "Anthropic [API key] • unconfigured"))
    ("logout-provider"
     "components/oauth-selector.ts:51-160"
     ("Select provider to logout:" ">"
      "→ OpenAI Codex [subscription] ✓ configured"
      "Anthropic [API key] • unconfigured"))
    ("api-key"
     "components/login-dialog.ts:30-71,154-167"
     ("Login to Anthropic" "Enter API key" ">"
      "escape/ctrl+c to cancel, enter to submit"))
    ("import"
     "interactive-mode.ts:2244-2281,2299-2305,5523; components/extension-selector.ts:18-78"
     ("Import session" "Replace current session with /tmp/session.jsonl?"
      "→ Yes" "No" "↑↓ navigate  enter select  escape/ctrl+c cancel"))
    ("extension-select"
     "interactive-mode.ts:2244-2281,2299-2305; components/extension-selector.ts:18-78"
     ("Choose one" "→ Alpha" "Beta"
      "↑↓ navigate  enter select  escape/ctrl+c cancel"))
    ("extension-custom"
     "interactive-mode.ts:2494-2563; packages/tui/src/components/select-list.ts:74-137"
     ("→ Alpha" "Beta"))))

(defun goal9-b3-overlay-screen-text-lines (overlay)
  (mapcar
   (lambda (line)
     (string-right-trim
      " "
      (cadr-tui:strip-terminal-sequences line)))
   (goal9-b3-overlay-screen-snapshot overlay :rows 60)))

(defun goal9-b3-overlay-assert-lines-in-order
    (lines needles &key (start 0))
  (let ((positions nil))
    (dolist (needle needles)
      (let ((position
              (position-if
               (lambda (line) (search needle line))
               lines :start start)))
        (is (not (null position)))
        (when position
          (push position positions)
          (setf start (1+ position)))))
    (nreverse positions)))

(test goal9-b3-every-overlay-sha-has-a-baseline-derived-semantic-oracle
  (let* ((cases (goal9-b3-overlay-screen-cases))
         (case-names (mapcar #'car cases))
         (oracle-names
           (mapcar #'car
                   +goal9-b3-overlay-baseline-semantic-oracles+)))
    ;; This equality is the policy gate: adding or renaming an overlay SHA
    ;; without a direct baseline oracle fails even if a new hash is supplied.
    (is (equal case-names oracle-names))
    (dolist (case cases)
      (let* ((name (car case))
             (oracle
               (assoc
                name
                +goal9-b3-overlay-baseline-semantic-oracles+
                :test #'string=))
             (lines
               (goal9-b3-overlay-screen-text-lines (cdr case)))
             (common
               (goal9-b3-overlay-assert-lines-in-order
                lines
                '("overlay transcript user"
                  "overlay transcript assistant")))
             (surface
               (goal9-b3-overlay-assert-lines-in-order
                lines (third oracle)
                :start (1+ (second common))))
             (footer
               (position-if
                (lambda (line) (search "mock" line))
                lines :start (1+ (car (last surface))))))
        (is (= 60 (length lines)))
        (is (not (null oracle)))
        (is (not (null footer)))
        (is (null
             (find-if
              (lambda (line)
                (search "OVERLAY-EDITOR-MUST-BE-HIDDEN" line))
              lines)))))))

(test goal9-b3-every-overlay-has-an-exact-full-virtual-terminal-snapshot
  (let ((expected
          '(("model" . "828CFA77C89D3FA8E84E4ACC72FC9AFC797E8C82A26AEFA3FE0FC46438195869")
            ("model-scoped" . "9031A4EA00CFEAA9E9A931B0A493414B76AAB46BEC10A0C81204003DAA466DB1")
            ("settings" . "DB40F8BBA31200DB8C5BE49E59B2AE01EDA11F935B002DF230F96BA6F4133CC4")
            ("resume" . "DE1B4941BEAC9C1087885B26E7F97093682758FCDE492FCC4429385C01E548C8")
            ("fork" . "AA7D9886BCA3858198561FA431CA5DC5028A608B4EA200AA2F65FE9B50072D2E")
            ("tree" . "B0ECA829983C7840B4026E9C3F102D5D62AE7ED8CAB7412D5E7CC086DA59C117")
            ("scoped-models" . "02E5671BF390A2AF5F0DFCC6ED75A2ACC410A45D642197715148793D9CD51D46")
            ("trust" . "3D484AC3838FAE5ADA7A490D6274C6BD1C78FCC2F0BD196026F33EA1A4631A7E")
            ("login-method" . "305B0BB2D1C67D71D7851B1EF450E992212C08F8A680CC6DF00AA23CE3B033C0")
            ("login-provider" . "5CA87C165CDB0E54D1D8A1FB03379A4CE5BC0363904D1E243935F513956EBA20")
            ("logout-provider" . "5B88F48EC8368B4395CC5CDCBEE9CBF86B564CD0924F48282ED8E9DE81308212")
            ("api-key" . "E465C3E57FB209D3B040B3D8ABC217D916DD147642AEC3B538BABF5135254185")
            ("import" . "B836156D2E481FCB62CF14A058B69A6F2E9D1723E47C4A29B496A0F58CB134AC")
            ("extension-select" . "BD71C617E1CE9E9A9CB32B6EEDFDC575600FB69772F4BA2CC866E36DA2C7BD9F")
            ("extension-custom" . "A85DF2C8310E88D1BEA5B9AE84CBF6735FBC83CBC1116082E52A2CBB9A76A2EC"))))
    (dolist (case (goal9-b3-overlay-screen-cases))
      (is
       (string=
        (cdr (assoc (car case) expected :test #'string=))
       (goal9-b3-overlay-screen-sha256 (cdr case)))))))

(test goal10-every-overlay-snapshot-preserves-nonempty-transcript
  (dolist (case (goal9-b3-overlay-screen-cases))
    (let ((screen
            (format
             nil "~{~A~^~%~}"
             (goal9-b3-overlay-screen-snapshot
              (cdr case) :rows 60))))
      (is (search "overlay transcript user" screen))
      (is (search "overlay transcript assistant" screen))
      (is (null
           (search "OVERLAY-EDITOR-MUST-BE-HIDDEN" screen))))))

(test goal9-b3-model-overlays-have-complete-baseline-line-contracts
  (let* ((width 80)
         (border (goal9-b3-overlay-border width))
         (one (goal9-b3-overlay-model :faux "one" "One Model"))
         (two (goal9-b3-overlay-model :other "two" "Two Model")))
    (is
     (equal
      (list border ""
            (goal9-b3-overlay-text-line
             "Only showing models from configured providers. Use /login to add providers."
             width)
            "" (goal9-b3-overlay-input-line "" width) ""
            (goal9-b3-overlay-text-line "→ one [faux] ✓" width)
            (goal9-b3-overlay-text-line "  two [other]" width) ""
            (goal9-b3-overlay-text-line "  Model Name: One Model" width)
            "" border)
      (goal9-b3-overlay-plain-lines
       (cadr-cli::render-model-selector
        (cadr-cli::make-model-selector-state
         :all-models (list one two) :current-model one)
        width))))
    (is
     (equal
      (list border ""
            (goal9-b3-overlay-text-line "Scope: all | scoped" width)
            (goal9-b3-overlay-text-line "tab scope (all/scoped)" width) ""
            (goal9-b3-overlay-input-line "" width) ""
            (goal9-b3-overlay-text-line "  two [other]" width)
            (goal9-b3-overlay-text-line "→ one [faux] ✓" width) ""
            (goal9-b3-overlay-text-line "  Model Name: One Model" width) ""
            (goal9-b3-overlay-text-line "  Model catalogs refreshed." width)
            "" border)
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
      (list border ""
            (goal9-b3-overlay-text-line "Model Configuration" width)
            (goal9-b3-overlay-text-line
             "Session-only. ctrl+s to save to settings." width) ""
            (goal9-b3-overlay-input-line "" width) ""
            (goal9-b3-overlay-text-line "→ one [faux] ✓" width)
            (goal9-b3-overlay-text-line
             "  missing/ghost [unavailable] ✗" width)
            (goal9-b3-overlay-text-line "  two [other] ✗" width) ""
            (goal9-b3-overlay-text-line "  Model Name: One Model" width) ""
            (goal9-b3-overlay-text-line
             "  enter toggle · ctrl+a all · ctrl+x clear · ctrl+p provider · alt+up/alt+down  "
             width)
            (goal9-b3-overlay-text-line
             "reorder · ctrl+s save · 1/2 enabled · 1 unavailable" width)
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
            "" (goal9-b3-overlay-input-line "prompt" width) ""
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
             "" (goal9-b3-overlay-input-line "" width) "")
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
            "" (goal9-b3-overlay-input-line "zzyzx" width) ""
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
              "" (goal9-b3-overlay-input-line "" width) ""
              "  No sessions in current folder. Press Tab to view all."
              "" border)
        (goal9-b3-overlay-plain-lines
         (cadr-cli::render-session-selector empty width)))))))

(test goal9-b3-fork-and-tree-overlays-have-complete-baseline-line-contracts
  (let ((border-80 (goal9-b3-overlay-border 80))
        (border-100 (goal9-b3-overlay-border 100)))
    (is
     (equal
      (list "" (goal9-b3-overlay-text-line " Fork from Message" 80)
            (goal9-b3-overlay-text-line
             " Select a user message to copy the active path up to that point into a new"
             80)
            (goal9-b3-overlay-text-line " session" 80) "" border-80 ""
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
      (list "" border-100
            (goal9-b3-overlay-text-line "   Session Tree" 100)
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
      (list border ""
            (goal9-b3-overlay-text-line " Project trust" 80)
            (goal9-b3-overlay-text-line " /tmp/project" 80) ""
            (goal9-b3-overlay-text-line " Saved decision: none" 80)
            (goal9-b3-overlay-text-line " Current session: untrusted" 80) ""
            (goal9-b3-overlay-text-line " → Trust" 80)
            (goal9-b3-overlay-text-line "   Trust parent folder (/tmp)" 80)
            (goal9-b3-overlay-text-line "   Do not trust" 80) ""
            (goal9-b3-overlay-text-line
             " ↑↓ navigate  enter save  escape/ctrl+c cancel" 80)
            "" border)
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
      (list border ""
            (goal9-b3-overlay-text-line
             " Select authentication method:" width) ""
            (goal9-b3-overlay-text-line
             " → Sign in with an account" width)
            (goal9-b3-overlay-text-line
             "   Sign in with an API key" width) ""
            (goal9-b3-overlay-text-line
             " ↑↓ navigate  enter select  escape/ctrl+c cancel" width) ""
            border)
      (goal9-b3-overlay-plain-lines
       (cadr-cli::render-login-method-selector
        (cadr-cli::make-login-method-selector-state) width))))
    (dolist
        (case
         `((:login
            (,border ""
             ,(goal9-b3-overlay-text-line
               " Select provider to configure:" width) ""
             ,(concatenate 'string "> "
                           (make-string 78 :initial-element #\Space)) ""
             ,(goal9-b3-overlay-text-line
               " → OpenAI Codex [subscription] ✓ configured" width)
             ,(goal9-b3-overlay-text-line
               "   Anthropic [API key] • unconfigured" width) "" ,border))
           (:logout
            (,border ""
             ,(goal9-b3-overlay-text-line
               " Select provider to logout:" width) ""
             ,(concatenate 'string "> "
                           (make-string 78 :initial-element #\Space)) ""
             ,(goal9-b3-overlay-text-line
               " → OpenAI Codex [subscription] ✓ configured" width)
             ,(goal9-b3-overlay-text-line
               "   Anthropic [API key] • unconfigured" width) "" ,border))))
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
      (list border
            (goal9-b3-overlay-text-line " Login to Anthropic" width)
            ""
            (goal9-b3-overlay-text-line " Enter API key" width)
            (concatenate 'string "> "
                         (make-string 78 :initial-element #\Space))
            (goal9-b3-overlay-text-line
             " (escape/ctrl+c to cancel, enter to submit)" width)
            border)
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
    (is (string=
         (goal9-b3-overlay-text-line
          " Enter API key" 80)
         (cadr-tui:strip-terminal-sequences
          (fourth rendered))))
    (is (search
         (cadr-tui:theme-foreground
          :text "Enter API key" :enabled-p t)
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
       (list border ""
             (goal9-b3-overlay-text-line
              " Select provider to configure:" width) ""
             (concatenate 'string "> "
                          (make-string 78 :initial-element #\Space)) "")
       (loop for index from 1 to 8
             collect
             (goal9-b3-overlay-text-line
              (format nil " ~AProvider ~2,'0D [~A] • unconfigured"
                      (if (= index 1) "→ " "  ")
                      index
                      (if (oddp index) "subscription" "API key"))
              width))
       (list (goal9-b3-overlay-text-line "   (1/10)" width)
             "" border))
      (goal9-b3-overlay-plain-lines
       (cadr-cli::render-oauth-selector state width))))
    (cadr-cli::oauth-selector-handle-event
     state
     (cadr-tui:make-input-event :kind :text :text "zzyzx"))
    (is (string= "zzyzx" (cadr-cli::oauth-selector-state-query state)))
    (is
     (equal
      (list border ""
            (goal9-b3-overlay-text-line
             " Select provider to configure:" width) ""
            (concatenate 'string "> zzyzx"
                         (make-string 73 :initial-element #\Space)) ""
            (goal9-b3-overlay-text-line
             " → Zzyzx Provider [API key] • unconfigured" width)
            "" border)
      (goal9-b3-overlay-plain-lines
       (cadr-cli::render-oauth-selector state width))))
    (cadr-cli::oauth-selector-handle-event
     state
     (cadr-tui:make-input-event :kind :text :text "missing"))
    (is
     (equal
      (list border ""
            (goal9-b3-overlay-text-line
             " Select provider to configure:" width) ""
            (concatenate 'string "> zzyzxmissing"
                         (make-string 66 :initial-element #\Space)) ""
            (goal9-b3-overlay-text-line
             "   No matching providers" width) "" border)
      (goal9-b3-overlay-plain-lines
       (cadr-cli::render-oauth-selector state width))))
    (let ((empty-login
            (cadr-cli::make-oauth-selector-state
             :mode :login :options nil))
          (empty-logout
            (cadr-cli::make-oauth-selector-state
             :mode :logout :options nil)))
      (is
       (member (goal9-b3-overlay-text-line
                "   No providers available" width)
               (goal9-b3-overlay-plain-lines
                (cadr-cli::render-oauth-selector empty-login width))
               :test #'string=))
      (is
       (member (goal9-b3-overlay-text-line
                "   No providers logged in. Use /login first." width)
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
            (goal9-b3-overlay-text-line
             " ↑↓ navigate  enter select  escape/ctrl+c cancel" 80)
            "" border)
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
             (list
              ""
              (goal9-b3-overlay-text-line
               " ↑↓ navigate  enter select  escape/ctrl+c cancel" 80)
              "" border))
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
         (goal9-b3-overlay-text-line
          " ↑↓ navigate  alt+y select  alt+x" 40)
         (goal9-b3-overlay-text-line " cancel" 40)
         ""
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
        (overlay-opened
          (sb-thread:make-semaphore :count 0))
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
        (sb-thread:wait-on-semaphore overlay-opened))))
    (cadr-cli::run-tui
     (constantly nil)
     :model "mock"
     :terminal terminal
     :set-extension-ui-function
     (lambda (function)
       (setf extension-ui function))
     :extension-overlay-opened-function
     (lambda ()
       (sb-thread:signal-semaphore overlay-opened))
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
        (result :pending)
        (overlay-opened
          (sb-thread:make-semaphore :count 0)))
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
        (sb-thread:wait-on-semaphore overlay-opened)))
     :set-extension-ui-function
     (lambda (function)
       (setf extension-ui function))
     :extension-overlay-opened-function
     (lambda ()
       (sb-thread:signal-semaphore overlay-opened))
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

(test goal12-extension-oauth-prompt-bridge-blocks-worker-and-returns-input
  (let ((prompt-function nil)
        (worker nil)
        (result :pending)
        (worker-complete
          (sb-thread:make-semaphore :count 0))
        (overlay-opened
          (sb-thread:make-semaphore :count 0)))
    (cadr-cli::run-tui
     (constantly nil)
     :model "mock"
     :terminal
     (make-instance
      'footer-sync-test-terminal
      :columns 80 :rows 14
      :inputs
      (list
       (footer-sync-submit-input "/oauth-prompt")
       (footer-sync-wait-for-screen-text
        "Authorization code")
       (footer-sync-submit-input "callback-code")
       (footer-sync-submit-input "/quit"))
      :before-second-read
      (lambda ()
        (sb-thread:wait-on-semaphore overlay-opened)))
     :set-auth-prompt-consumer
     (lambda (function)
       (setf prompt-function function))
     :extension-overlay-opened-function
     (lambda ()
       (sb-thread:signal-semaphore overlay-opened))
     :command-function
     (lambda (line)
       (when (string= line "/oauth-prompt")
         (setf
          worker
          (sb-thread:make-thread
           (lambda ()
             (setf
              result
              (funcall
               prompt-function
               '(:type :manual-code
                 :message "Authorization code"
                 :placeholder "paste code")))))))
       t))
    (when worker
      (sb-thread:join-thread worker))
    (is (string= "callback-code" result))))

(test goal12-extension-oauth-prompt-bridge-cancel-returns-nil
  (let ((prompt-function nil)
        (worker nil)
        (result :pending)
        (worker-complete
          (sb-thread:make-semaphore :count 0))
        (overlay-opened
          (sb-thread:make-semaphore :count 0)))
    (cadr-cli::run-tui
     (constantly nil)
     :model "mock"
     :terminal
     (make-instance
      'footer-sync-test-terminal
      :columns 80 :rows 14
      :inputs
      (list
       (footer-sync-submit-input "/oauth-prompt")
       (footer-sync-wait-for-screen-text "Secret")
       (string #\Escape)
       (lambda (terminal)
         (declare (ignore terminal))
         (sb-thread:wait-on-semaphore
          worker-complete :timeout 2))
       (footer-sync-submit-input "/quit"))
      :before-second-read
      (lambda ()
        (sb-thread:wait-on-semaphore overlay-opened)))
     :set-auth-prompt-consumer
     (lambda (function)
       (setf prompt-function function))
     :extension-overlay-opened-function
     (lambda ()
       (sb-thread:signal-semaphore overlay-opened))
     :command-function
     (lambda (line)
       (when (string= line "/oauth-prompt")
         (setf
          worker
          (sb-thread:make-thread
           (lambda ()
             (unwind-protect
                  (setf
                   result
                   (funcall
                    prompt-function
                    '(:type :secret :message "Secret")))
               (sb-thread:signal-semaphore
                worker-complete))))))
       t))
    (when worker
      (sb-thread:join-thread worker))
    (is (null result))))

(test goal12-extension-login-options-feed-selector-and-autocomplete-locally
  (let ((commands nil)
        (options
          (list
           (cadr-cli::make-oauth-selector-option
            :id :extension-oauth
            :name "Extension OAuth"
            :auth-type :oauth
            :method-name "Extension OAuth account"))))
    (cadr-cli::run-tui
     (constantly nil)
     :model "mock"
     :terminal
     (make-instance
      'footer-sync-test-terminal
      :columns 80 :rows 16
      :inputs
      (list
       (footer-sync-submit-input "/login")
       (footer-sync-wait-for-screen-text
        "Sign in with an account")
       (string #\Return)
       (footer-sync-wait-for-screen-text "Extension OAuth")
       (string #\Return)
       (footer-sync-submit-input "/quit"))
      :before-second-read (constantly nil))
     :login-options-function (lambda () options)
     :command-function
     (lambda (line)
       (push line commands)
       t))
    (is (equal '("/login extension-oauth")
               (remove "/quit" commands :test #'string=)))))

(test goal12-live-tui-custom-component-receives-runtime-theme-keybindings-handle-and-dispose
  (let ((extension-ui nil)
        (worker nil)
        (result :pending)
        (factory-values nil)
        (handle nil)
        (component nil)
        (overlay-opened
          (sb-thread:make-semaphore :count 0)))
    (cadr-cli::run-tui
     (constantly nil)
     :model "mock"
     :terminal
     (make-instance
      'footer-sync-test-terminal
      :columns 80 :rows 16
      :inputs
      (list
       (footer-sync-submit-input "/custom-component")
       (footer-sync-wait-for-screen-text "Goal 12 overlay")
       (string #\Return)
       (footer-sync-submit-input "/quit"))
      :before-second-read
      (lambda ()
        (sb-thread:wait-on-semaphore overlay-opened)))
     :set-extension-ui-function
     (lambda (function)
       (setf extension-ui function))
     :extension-overlay-opened-function
     (lambda ()
       (sb-thread:signal-semaphore overlay-opened))
     :command-function
     (lambda (line)
       (when (string= line "/custom-component")
         (setf
          worker
          (sb-thread:make-thread
           (lambda ()
             (setf
              result
              (funcall
               extension-ui :custom-component
               (list
                :factory
                (lambda (tui theme keybindings done)
                  (setf
                   factory-values
                   (list tui theme keybindings done)
                   component
                   (make-instance
                    'goal12-extension-component
                    :text "Goal 12 overlay"
                    :done-function done))
                  component)
                :overlay-p t
                :overlay-options
                (lambda ()
                  '(:width 32 :anchor :top-right
                    :margin 1 :non-capturing-p nil))
                :on-handle
                (lambda (value)
                  (setf handle value)))))))))
       t))
    (when worker
      (sb-thread:join-thread worker))
    (is (eq :closed result))
    (is (typep (first factory-values) 'cadr-tui:tui-root))
    (is (functionp (getf (second factory-values) :fg)))
    (is (typep (third factory-values)
               'cadr-tui:keybindings-manager))
    (is (functionp (fourth factory-values)))
    (is (typep handle 'cadr-tui:overlay-handle))
    (is (cadr-tui:overlay-handle-hidden-p handle))
    (is (goal12-extension-component-disposed-p component))))

(test goal12-live-tui-composition-controls-preserve-editor-text-and-replace-components
  (let ((extension-ui nil)
        (observed-editor-factory nil)
        (observed-editor-text nil))
    (cadr-cli::run-tui
     (constantly nil)
     :model "mock"
     :terminal
     (make-instance
      'footer-sync-test-terminal
      :columns 80 :rows 16
      :inputs
      (list
       (footer-sync-submit-input "/compose")
       (footer-sync-wait-for-screen-text "extension-header")
       (footer-sync-wait-for-screen-text "extension-footer")
       (footer-sync-wait-for-screen-text "draft")
       (lambda (terminal)
         (declare (ignore terminal))
         (funcall extension-ui :set-editor-text '(:text ""))
         t)
       (footer-sync-submit-input "/quit"))
      :before-second-read (constantly nil))
     :set-extension-ui-function
     (lambda (function)
       (setf extension-ui function))
     :command-function
     (lambda (line)
       (when (string= line "/compose")
         (funcall
          extension-ui :set-editor-text '(:text "draft"))
         (funcall
          extension-ui :set-header
          (list
           :factory
           (lambda (tui theme)
             (declare (ignore tui theme))
             (cadr-tui:make-text-component
              "extension-header" :padding-x 0 :padding-y 0))))
         (funcall
          extension-ui :set-footer
          (list
           :factory
           (lambda (tui theme provider)
             (declare (ignore tui theme provider))
             (cadr-tui:make-text-component
              "extension-footer" :padding-x 0 :padding-y 0))))
         (let ((factory
                 (lambda (tui theme keybindings)
                   (declare (ignore tui theme keybindings))
                   (cadr-tui:make-single-line-input :prompt "> "))))
           (funcall extension-ui :set-editor-component
                    (list :factory factory))
           (setf observed-editor-factory
                 (funcall extension-ui :get-editor-component nil)))
         (setf observed-editor-text
               (funcall extension-ui :get-editor-text nil)))
       t))
    (is (functionp observed-editor-factory))
    (is (string= "draft" observed-editor-text))))

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
    (let* ((fd
             (make-fake-fd-program
              directory '("alpha.txt" "alpine/")))
           (provider
             (cadr-tui:make-autocomplete-provider
              :base-path directory
              :fd-path fd))
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
