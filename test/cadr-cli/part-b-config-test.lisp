(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

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
         "reloaded")
       :model-refresh-function
       (lambda ()
         (push :models steps))
       :keybindings-reload-function
       (lambda ()
         (push :keybindings steps)))
      (is (equal
           '(:extensions :resources :prompt
             :models :keybindings)
           (nreverse steps)))
      (is (string=
           "reloaded"
           (cadr-agent::agent-system-prompt agent)))
      (cadr-cli::resolve-config-value
       "!produce" :command-function #'runner)
      (is (= 2 runs)))))

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
          migrated "app.tools.expand")))))

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
