(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(test pairing-cli-settings-create-stays-put
  ;; scripts/goal20-paired-paths.lisp cli_settings.create.
  ;; Drives shipped make-settings-manager, not a reimplementation.
  (let* ((root (asdf:system-source-directory "cadr-cli"))
         (global
           (merge-pathnames
            "test/fixtures/goal20-paired-paths/settings-global.json"
            root))
         (project
           (merge-pathnames
            "test/fixtures/goal20-paired-paths/settings-project.json"
            root))
         (manager
           (cadr-cli::make-settings-manager
            :global-path global
            :project-path project
            :project-trusted-p t)))
    (is (string= "light" (cadr-cli::settings-value manager "theme")))
    (is (string=
         "claude-sonnet-4-5"
         (cadr-cli::settings-value manager "defaultModel")))
    (is (= 8192
           (cadr-cli::settings-nested-value
            manager "compaction" "reserveTokens")))
    (is (= 42 (cadr-cli::settings-http-idle-timeout-ms manager)))
    (is (cadr-cli::settings-manager-project-trusted-p manager))))

(defun write-json (path object)
  (write-text path
              (format nil "~A~%"
                      (cadr-ai::stringify-json object))))

(test config-values-resolve-templates-commands-and-cache
  (let ((runs 0)
        (environment
          '(("LEFT" . "left")
            ("RIGHT" . "right"))))
    (cadr-cli::clear-config-value-cache)
    (is (string=
         "literal-key"
         (cadr-cli::resolve-config-value
          "literal-key"
          :environment environment)))
    (is (string=
         "left_right"
         (cadr-cli::resolve-config-value
          "${LEFT}_$RIGHT"
          :environment environment)))
    (is (string=
         "$LEFT"
         (cadr-cli::resolve-config-value
          "$$LEFT"
          :environment environment)))
    (is (string=
         "!literal-right"
         (cadr-cli::resolve-config-value
          "$!literal-$RIGHT"
          :environment environment)))
    (flet ((runner (command)
             (declare (ignore command))
             (incf runs)
             (values " value " 0)))
      (is (string=
           "value"
           (cadr-cli::resolve-config-value
            "!produce" :command-function #'runner)))
      (is (string=
           "value"
           (cadr-cli::resolve-config-value
            "!produce" :command-function #'runner)))
      (is (= 1 runs))
      (cadr-cli::clear-config-value-cache)
      (cadr-cli::resolve-config-value
       "!produce" :command-function #'runner)
      (is (= 2 runs)))))

(test reload-clears-command-cache-and-refreshes-runtime-surfaces-in-order
  (let* ((runs 0)
         (steps nil)
         (completion-message nil)
         (manager
           (cadr-cli::make-memory-settings-manager))
         (model
           (cadr-ai:make-model
            :id "reload"
            :name "Reload"
            :provider :faux
            :api :openai-responses
            :base-url "https://example.invalid"
            :max-tokens 1024))
         (agent
           (cadr-agent:make-agent
            :provider nil
            :model model)))
    (flet ((runner (command)
             (declare (ignore command))
             (incf runs)
             (values
              (princ-to-string runs)
              0)))
      (cadr-cli::clear-config-value-cache)
      (cadr-cli::resolve-config-value
       "!produce" :command-function #'runner)
      (cadr-cli::resolve-config-value
       "!produce" :command-function #'runner)
      (is (= 1 runs))
      (cadr-cli::reload-cli-runtime
       agent manager
       :extension-reload-function
       (lambda ()
         (push :extensions steps))
       :resource-reload-function
       (lambda ()
         (push :resources steps)
         :snapshot)
       :system-prompt-function
       (lambda (resources)
         (is (eq :snapshot resources))
         (push :prompt steps)
         (values "reloaded"
                 '(:custom-prompt "reloaded"
                   :selected-tools ("read"))))
       :model-refresh-function
       (lambda ()
         (push :models steps))
       :keybindings-reload-function
       (lambda ()
         (push :keybindings steps))
       :completion-function
       (lambda (message)
         (push :completion steps)
         (setf completion-message message)))
      (is (equal
           '(:extensions :resources :prompt
             :models :keybindings :completion)
           (nreverse steps)))
      (is (string=
           "Reloaded keybindings, extensions, skills, prompts, themes, and context files"
           completion-message))
      (is (string=
           "reloaded"
           (cadr-agent::agent-system-prompt agent)))
      (is (equal
           '(:custom-prompt "reloaded"
             :selected-tools ("read"))
           (cadr-agent:agent-system-prompt-options agent)))
      (cadr-cli::resolve-config-value
       "!produce" :command-function #'runner)
      (is (= 2 runs)))))

(test cli-system-prompt-builder-returns-all-structured-options-with-identical-text
  (with-test-directory (root)
    (let* ((context-path (merge-pathnames "AGENTS.md" root))
           (append-path (merge-pathnames "APPEND.md" root))
           (skill
             (cadr-agent:make-skill
              :name "demo" :description "Demo"
              :content "skill body" :file-path "/tmp/SKILL.md"))
           (tool
             (cadr-ai:make-tool
              :name "read" :description "Read"
              :parameters (cadr-ai::json-object "type" "object")
              :executor (lambda (&rest values)
                          (declare (ignore values)))))
           (command (cadr-cli::make-cli-arguments))
           (snapshot
             (cadr-cli::make-resource-snapshot
              :append-system-prompt-path append-path
              :context-files (list context-path)
              :skills (list skill))))
      (write-text context-path "context")
      (write-text append-path "append")
      (multiple-value-bind (prompt options)
          (cadr-cli::resolve-cli-system-prompt
           command snapshot (list tool) root)
        (dolist (key '(:custom-prompt :selected-tools :tool-snippets
                       :prompt-guidelines :append-system-prompt :cwd
                       :context-files :skills))
          (is (member key options)))
        (is (equal '("read") (getf options :selected-tools)))
        (is (string= "append" (getf options :append-system-prompt)))
        (is (string= prompt
                     (apply #'cadr-cli:build-system-prompt options)))))))

(test settings-manager-merges-preserves-external-edits-and-enforces-trust
  (with-test-directory (root)
    (let* ((global (merge-pathnames "agent/settings.json" root))
           (project
             (merge-pathnames "project/.cadr/settings.json" root)))
      (write-json
       global
       (args
        "theme" "dark"
        "enabledModels" (vector "openai/gpt")
        "images" (args "autoResize" nil)
        "custom" "keep"))
      (write-json
       project
       (args
        "theme" "light"
        "images" (args "blockImages" t)
        "httpIdleTimeoutMs" 42))
      (let ((manager
              (cadr-cli::make-settings-manager
               :global-path global
               :project-path project
               :project-trusted-p t)))
        (is (string=
             "light"
             (cadr-cli::settings-value
              manager "theme")))
        (is (eq t
                (cadr-ai::json-get
                 (cadr-cli::settings-value
                  manager "images")
                 "blockImages")))
        (is (= 42
               (cadr-cli::settings-http-idle-timeout-ms
                manager)))
        (write-json
         global
         (args
          "theme" "dark"
          "enabledModels" (vector "openai/gpt")
          "externallyAdded" "survives"))
        (cadr-cli::settings-set
         manager "outputPad" 0 :scope :global)
        (let ((persisted
                (cadr-ai::parse-json
                 (read-text global))))
          (is (string=
               "survives"
               (cadr-ai::json-get
                persisted "externallyAdded")))
          (is (= 0
                 (cadr-ai::json-get
                  persisted "outputPad"))))
        (write-json
         global
         (args
          "images"
          (args
           "autoResize" t
           "externallyAdded" "survives")
          "outputPad" 0))
        (cadr-cli::settings-set-nested
         manager "images" "blockImages" t
         :scope :global)
        (let* ((persisted
                 (cadr-ai::parse-json
                  (read-text global)))
               (images
                 (cadr-ai::json-get
                  persisted "images")))
          (is (eq t
                  (cadr-ai::json-get
                   images "autoResize")))
          (is (eq t
                  (cadr-ai::json-get
                   images "blockImages")))
          (is (string=
               "survives"
               (cadr-ai::json-get
                images "externallyAdded"))))
        (write-text global "{malformed")
        (cadr-cli::settings-reload manager)
        (is (= 0
               (cadr-cli::settings-value
                manager "outputPad")))
        (is (not
             (null
              (cadr-cli::settings-drain-errors
               manager)))))
      (let ((untrusted
              (cadr-cli::make-settings-manager
               :global-path global
               :project-path project
               :project-trusted-p nil)))
        (is (null
             (cadr-cli::settings-value
              untrusted "httpIdleTimeoutMs")))
        (signals error
          (cadr-cli::settings-set
           untrusted "theme" "light"
           :scope :project))))))

(test settings-defaults-and-keybinding-migration
  (let ((manager
          (cadr-cli::make-memory-settings-manager)))
    (is (= 300000
           (cadr-cli::settings-http-idle-timeout-ms
            manager)))
    (is (= 1
           (cadr-cli::settings-output-padding
            manager)))
    (is (not
         (cadr-cli::settings-block-images-p manager))))
  (let* ((raw
           (args
            "cursorUp" (vector "up" "ctrl+p")
            "expandTools" "ctrl+x"
            "app.tools.expand" "ctrl+y"))
         (migrated
           (cadr-cli::migrate-keybindings raw)))
    (is (null
         (cadr-ai::json-get migrated "cursorUp")))
    (is (equalp
         #("up" "ctrl+p")
         (cadr-ai::json-get
          migrated "tui.editor.cursorUp")))
    (is (string=
         "ctrl+y"
         (cadr-ai::json-get
          migrated "app.tools.expand"))))
  (let ((manager
          (cadr-cli::make-memory-settings-manager)))
    (cadr-cli::settings-set
     manager "keybindings"
     (args
      "app.model.cycleForward" #()
      "app.model.cycleBackward" #("ctrl+shift+g")))
    (let ((bindings (cadr-cli::settings-keybindings manager)))
      (is
       (member
        '("app.model.cycleForward")
        bindings :test #'equal))
      (is
       (equal
        '("ctrl+shift+g")
        (cdr
         (assoc
          "app.model.cycleBackward"
          bindings :test #'string=)))))))

(test goal18-keybindings-file-precedes-settings-and-migrates-legacy-names
  ;; Baseline core/keybindings.ts:349-366 — KeybindingsManager.create
  ;; reads <agentDir>/keybindings.json (migrating legacy names); per the
  ;; goal 18 adjudication the file coexists with the settings.json
  ;; keybindings key and takes precedence when present.
  (with-test-directory (root)
    (let* ((agent-dir (merge-pathnames "agent/" root))
           (manager
             (cadr-cli::make-memory-settings-manager)))
      (ensure-directories-exist agent-dir)
      (cadr-cli::settings-set
       manager "keybindings"
       (args "app.model.cycleBackward" "ctrl+shift+g"))
      ;; No file: the settings value applies.
      (is
       (equal
        '("ctrl+shift+g")
        (cdr
         (assoc
          "app.model.cycleBackward"
          (cadr-cli::resolve-user-keybindings manager agent-dir)
          :test #'string=))))
      ;; File present: it wins, and legacy names migrate.
      (write-text
       (merge-pathnames "keybindings.json" agent-dir)
       "{\"cursorUp\": [\"ctrl+k\"], \"app.tools.expand\": \"ctrl+y\"}")
      (let ((bindings
              (cadr-cli::resolve-user-keybindings manager agent-dir)))
        (is
         (equal
          '("ctrl+k")
          (cdr
           (assoc "tui.editor.cursorUp" bindings :test #'string=))))
        (is
         (equal
          '("ctrl+y")
          (cdr
           (assoc "app.tools.expand" bindings :test #'string=))))
        (is
         (null
          (assoc
           "app.model.cycleBackward" bindings :test #'string=))))
      ;; Malformed file: baseline loadRawConfig treats it as absent.
      (write-text
       (merge-pathnames "keybindings.json" agent-dir)
       "{ not json ")
      (is
       (equal
        '("ctrl+shift+g")
        (cdr
         (assoc
          "app.model.cycleBackward"
          (cadr-cli::resolve-user-keybindings manager agent-dir)
          :test #'string=)))))))
(test goal15-clear-on-shrink-setting-precedes-environment-and-defaults-off
  ;; pi@914cf1472 settings-manager.ts:1093-1099: an explicit terminal setting
  ;; wins, the environment is only a fallback, and the default is false.
  #+sbcl
  (let ((previous (uiop:getenv "CADR_CLEAR_ON_SHRINK")))
    (unwind-protect
         (let ((manager (cadr-cli::make-memory-settings-manager)))
           (sb-posix:unsetenv "CADR_CLEAR_ON_SHRINK")
           (is (null (cadr-cli::settings-clear-on-shrink-p manager)))
           (sb-posix:setenv "CADR_CLEAR_ON_SHRINK" "1" 1)
           (is (eq t (cadr-cli::settings-clear-on-shrink-p manager)))
           (cadr-cli::settings-set
            manager "terminal"
            (args "clearOnShrink" nil))
           (is (null (cadr-cli::settings-clear-on-shrink-p manager)))
           (sb-posix:setenv "CADR_CLEAR_ON_SHRINK" "0" 1)
           (cadr-cli::settings-set
            manager "terminal"
            (args "clearOnShrink" t))
           (is (eq t (cadr-cli::settings-clear-on-shrink-p manager))))
      (if previous
          (sb-posix:setenv "CADR_CLEAR_ON_SHRINK" previous 1)
          (sb-posix:unsetenv "CADR_CLEAR_ON_SHRINK")))))

(test model-settings-preserve-order-unavailable-ids-and-remove-all-sentinel
  (with-test-directory (root)
    (let* ((path
             (merge-pathnames "settings.json" root))
           (manager
             (cadr-cli::make-settings-manager
              :global-path path)))
      (cadr-cli::settings-set-enabled-models
       manager
       '("faux/unavailable" "faux/two"
         "faux/one"))
      (is (equal
           '("faux/unavailable" "faux/two"
             "faux/one")
           (cadr-cli::settings-enabled-models
            manager)))
      (cadr-cli::settings-set-default-model-and-provider
       manager "faux" "two")
      (is (string=
           "faux"
           (cadr-cli::settings-default-provider
            manager)))
      (is (string=
           "two"
           (cadr-cli::settings-default-model
            manager)))
      (cadr-cli::settings-set-enabled-models
       manager :all)
      (let ((persisted
              (cadr-ai::parse-json
               (read-text path))))
        (multiple-value-bind (value present-p)
            (gethash "enabledModels" persisted)
          (declare (ignore value))
          (is (null present-p)))
        (is (string=
             "faux"
             (cadr-ai::json-get
              persisted "defaultProvider")))
        (is (string=
             "two"
             (cadr-ai::json-get
              persisted "defaultModel")))))))

(test resource-loader-honors-trust-precedence-and-context-options
  (with-test-directory (root)
    (let* ((agent-dir (merge-pathnames "agent/" root))
           (cwd (merge-pathnames "project/sub/" root))
           (project-root (merge-pathnames "project/" root)))
      (write-text
       (merge-pathnames "skills/shared/SKILL.md" agent-dir)
       (format nil
               "---~%name: shared~%description: global~%---~%global"))
      (write-text
       (merge-pathnames "prompts/review.md" agent-dir)
       "global review")
      (write-text
       (merge-pathnames ".cadr/skills/shared/SKILL.md"
                        project-root)
       (format nil
               "---~%name: shared~%description: project~%---~%project"))
      (write-text
       (merge-pathnames ".cadr/prompts/review.md"
                        project-root)
       "project review")
      (write-text
       (merge-pathnames "AGENTS.md" project-root)
       "context")
      (write-text
       (merge-pathnames ".cadr/SYSTEM.md" project-root)
       "system")
      (let* ((loader
               (cadr-cli::make-default-resource-loader
                :cwd cwd
                :agent-directory agent-dir
                :project-trusted-p t))
             (snapshot
               (cadr-cli::reload-resources loader)))
        (is (= 1
               (length
                (cadr-cli::resource-snapshot-skills
                 snapshot))))
        (is (search
             "project"
             (cadr-agent::skill-content
              (first
               (cadr-cli::resource-snapshot-skills
                snapshot)))))
        (is (= 1
               (length
                (cadr-cli::resource-snapshot-prompts
                 snapshot))))
        (is (search
             "project review"
             (cadr-agent::prompt-template-content
              (first
               (cadr-cli::resource-snapshot-prompts
                snapshot)))))
        (is (equal
             (truename
              (merge-pathnames "AGENTS.md" project-root))
             (truename
              (first
               (cadr-cli::resource-snapshot-context-files
                snapshot)))))
        (is (equal
             (truename
              (merge-pathnames ".cadr/SYSTEM.md"
                               project-root))
             (truename
              (cadr-cli::resource-snapshot-system-prompt-path
               snapshot)))))
      (let* ((loader
               (cadr-cli::make-default-resource-loader
                :cwd cwd
                :agent-directory agent-dir
                :project-trusted-p nil
                :no-context-files-p t))
             (snapshot
               (cadr-cli::reload-resources loader)))
        (is (search
             "global"
             (cadr-agent::skill-content
              (first
               (cadr-cli::resource-snapshot-skills
                snapshot)))))
        (is (null
             (cadr-cli::resource-snapshot-context-files
              snapshot)))
        (is (null
             (cadr-cli::resource-snapshot-system-prompt-path
              snapshot)))))))

(test project-trust-store-inherits-and-detects-project-resources
  (with-test-directory (root)
    (let* ((path (merge-pathnames "agent/trust.json" root))
           (parent (merge-pathnames "trusted/" root))
           (child (merge-pathnames "trusted/child/" root))
           (store
             (cadr-cli::make-project-trust-store path)))
      (ensure-directories-exist
       (merge-pathnames "anchor" child))
      (is (null
           (cadr-cli::project-trust-get
            store child)))
      (cadr-cli::project-trust-set
       store parent t)
      (is (eq t
              (cadr-cli::project-trust-get
               store child)))
      (cadr-cli::project-trust-set
       store child nil)
      (is (eq t
              (cadr-cli::project-trust-get
               store child)))
      (write-json
       (merge-pathnames ".cadr/settings.json" child)
       (args))
      (is
       (cadr-cli::trust-requiring-project-resources-p
        child)))))

(test explicit-resources-survive-discovery-disable-flags
  (with-test-directory (root)
    (let* ((agent (merge-pathnames "agent/" root))
           (cwd (merge-pathnames "project/" root))
           (skill
             (merge-pathnames
              "explicit/skill/SKILL.md" root))
           (prompt
             (merge-pathnames
              "explicit/prompts/review.md" root))
           (theme
             (merge-pathnames
              "explicit/themes/custom.json" root)))
      (write-text
       skill
       (format nil
               "---~%name: skill~%description: Explicit~%---~%body"))
      (write-text prompt "Review explicitly")
      (write-json
       theme
       (args "name" "custom"
             "colors" (args "text" "#fff")))
      (ensure-directories-exist
       (merge-pathnames "anchor" cwd))
      (let* ((loader
               (cadr-cli::make-default-resource-loader
                :cwd cwd
                :agent-directory agent
                :no-skills-p t
                :no-prompts-p t
                :no-themes-p t
                :explicit-skill-paths
                (list (namestring skill))
                :explicit-prompt-paths
                (list (namestring prompt))
                :explicit-theme-paths
                (list (namestring theme))))
             (snapshot
               (cadr-cli::reload-resources loader)))
        (is (equal
             '("skill")
             (mapcar
              #'cadr-agent:skill-name
              (cadr-cli::resource-snapshot-skills
               snapshot))))
        (is (equal
             '("review")
             (mapcar
              #'cadr-agent:prompt-template-name
              (cadr-cli::resource-snapshot-prompts
               snapshot))))
        (is (equal
             '("custom")
             (mapcar
              (lambda (entry)
                (getf entry :name))
              (cadr-cli::resource-snapshot-themes
               snapshot))))))))

(test deterministic-test-entrypoint-accounts-for-all-nine-suites
  (let* ((root (asdf:system-source-directory "cadr-cli"))
         (script (merge-pathnames "scripts/test-cl.sh" root))
         (source (uiop:read-file-string script)))
    (dolist (system '("cadr-core" "cadr-ai" "cadr-agent" "cadr-tui" "cadr-cli"
                      "cadr-storage" "cadr-server" "cadr-evals"
                      "cadr-protocol"))
      (is (= 1
             (count-substring
              (format nil "(asdf:test-system \"~A\" :force t)" system)
              source))))
    (dolist (contract '("did != 9" "pass_lines != 9" "skip_lines != 9"
                        "fail_lines != 9" "checks != pass + skip + fail"
                        "cadr test summary: systems=%d checks=%d pass=%d skip=%d fail=%d"
                        "write-test-check-anchor.py"
                        "CADR_TEST_CHECK_LEDGER"))
      (is (search contract source)))
    (with-test-directory (temporary)
      (let ((fake-sbcl (merge-pathnames "fake-sbcl" temporary))
            (quicklisp (merge-pathnames "setup.lisp" temporary))
            (ledger (merge-pathnames "test-matrix.md" temporary)))
        (write-text
         fake-sbcl
         (format nil
                 "#!/bin/sh~%i=0~%while [ \"$i\" -lt 9 ]; do~%  printf ' Did 3 checks.\\n    Pass: 3 (100%%)\\n    Skip: 0 ( 0%%)\\n    Fail: 0 ( 0%%)\\n'~%  i=$((i + 1))~%done~%"))
        (write-text quicklisp "")
        (write-text
         ledger
         (format nil
                 "# fixture~%<!-- GOAL20_TEST_CHECKS systems=9 checks=27 pass=27 skip=0 fail=0 -->~%"))
        (uiop:run-program (list "chmod" "+x" (namestring fake-sbcl)))
        (flet ((run-test-cl (extra-arg ledger-path)
                 (multiple-value-list
                  (uiop:run-program
                   (append
                    (list
                     "env"
                     (format nil "SBCL=~A" (namestring fake-sbcl))
                     (format nil "QUICKLISP_SETUP=~A" (namestring quicklisp))
                     (format nil "CADR_TEST_CHECK_LEDGER=~A" (namestring ledger-path))
                     (namestring script))
                    (when extra-arg (list extra-arg)))
                   :output :string :error-output :string
                   :ignore-error-status t))))
          ;; Read-only default: a matching fixture passes and the ledger
          ;; file is not rewritten (goal 20, 11a).
          (destructuring-bind (output errors status)
              (run-test-cl nil ledger)
            (is (zerop status) "~A" errors)
            (is (search
                 "cadr test summary: systems=9 checks=27 pass=27 skip=0 fail=0"
                 output))
            (is (search "test-check-anchor: systems=9 checks=27" output)))
          ;; The read-only default must go red on a dirty ledger.
          (let ((dirty (merge-pathnames "dirty-test-matrix.md" temporary)))
            (write-text
             dirty
             (format nil
                     "# fixture~%<!-- GOAL20_TEST_CHECKS systems=9 checks=26 pass=26 skip=0 fail=0 -->~%"))
            (destructuring-bind (output errors status)
                (run-test-cl nil dirty)
              (declare (ignore output))
              (is (not (zerop status))
                  "read-only test-cl.sh must fail on a drifted ledger: ~A"
                  errors)))
          ;; --record remains the explicit write path.
          (destructuring-bind (output errors status)
              (run-test-cl "--record" ledger)
            (declare (ignore errors))
            (is (zerop status))
            (is (search "changed=no" output))))))))
