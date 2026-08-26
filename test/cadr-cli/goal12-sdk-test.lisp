(in-package #:cadr-cli/tests)

(in-suite cadr-cli-suite)

(defun goal12-sdk-model ()
  (cadr-ai:make-model
   :id "sdk-faux"
   :name "SDK Faux"
   :provider :faux
   :api :openai-responses
   :base-url "https://example.invalid"
   :max-tokens 1024
   :context-window 8192
   :supports-tools-p t))

(defun goal12-sdk-stream
    (provider model context on-event &rest options)
  (declare (ignore provider model context options))
  (let ((message
          (cadr-ai:make-assistant-message
           :content
           (list
            (cadr-ai:make-text-content
             :text "sdk-response"))
           :api :openai-responses
           :provider :faux
           :model "sdk-faux"
           :stop-reason :stop)))
    (funcall on-event
             (cadr-ai:make-stream-event
              :type :start :message message))
    (funcall on-event
             (cadr-ai:make-stream-event
              :type :text-delta
              :delta "sdk-response"
              :message message))
    (funcall on-event
             (cadr-ai:make-stream-event
              :type :done :message message
              :reason :stop))
    message))

(defun goal12-sdk-session
    (directory &key session-manager resource-loader
                    settings-manager)
  (cadr-cli::create-agent-session
   :cwd directory
   :agent-directory
   (merge-pathnames "agent/" directory)
   :model (goal12-sdk-model)
   :provider :faux
   :thinking-level :off
   :stream-function #'goal12-sdk-stream
   :session-manager
   (or session-manager
       (cadr-cli::session-manager-in-memory
        directory))
   :resource-loader resource-loader
   :settings-manager settings-manager
   :no-tools :all))

(test goal12-sdk-session-facade-prompts-subscribes-and-disposes-in-process
  (with-test-directory (temporary)
    (multiple-value-bind
          (session extensions fallback)
        (goal12-sdk-session temporary)
      (declare (ignore extensions))
      (is (null fallback))
      (let* ((types nil)
            (unsubscribe
              (cadr-cli::agent-session-subscribe
               session
               (lambda (event)
                 (push
                  (cadr-agent:agent-event-type event)
                  types)))))
        (is (string=
             "sdk-response"
             (cadr-ai:text-content-text
              (first
               (cadr-ai:assistant-message-content
                (cadr-cli::agent-session-prompt
                 session "hello"))))))
        (is (member :message-update types))
        (is (= 2
               (length
                (cadr-cli::agent-session-messages
                 session))))
        (funcall unsubscribe)
        (cadr-cli::agent-session-dispose session)
        (is
         (cadr-agent:agent-shutdown-p
          (cadr-cli::agent-session-agent
           session)))))))

(test goal12-sdk-session-facade-selects-tools-and-keeps-memory-session-fileless
  (with-test-directory (temporary)
    (multiple-value-bind (session)
        (cadr-cli::create-agent-session
         :cwd temporary
         :agent-directory
         (merge-pathnames "agent/" temporary)
         :model (goal12-sdk-model)
         :provider :faux
         :thinking-level :off
         :stream-function #'goal12-sdk-stream
         :session-manager
         (cadr-cli::session-manager-in-memory temporary)
         :tools '("read" "grep" "find" "ls"))
      (is (null
           (cadr-cli::agent-session-file session)))
      (is
       (equal
        '("read" "grep" "find" "ls")
        (mapcar
         #'cadr-ai:tool-name
         (cadr-agent::registry-tools
          (cadr-agent::agent-tool-registry
           (cadr-cli::agent-session-agent
            session))))))
      (cadr-cli::agent-session-dispose session))))

(test goal12-sdk-session-manager-covers-memory-create-continue-open-and-list
  (with-test-directory (temporary)
    (let* ((directory
             (merge-pathnames "sessions/" temporary))
           (manager
             (cadr-cli::session-manager-create
              temporary directory)))
      (multiple-value-bind (session)
          (goal12-sdk-session
           temporary :session-manager manager)
        (cadr-cli::agent-session-prompt session "persist")
        (let ((path
                (cadr-cli::agent-session-file session)))
          (is (probe-file path))
          (cadr-cli::agent-session-dispose session)
          (is (= 1
                 (length
                  (cadr-cli::session-manager-list
                   temporary directory))))
          (is
           (typep
            (cadr-cli::session-manager-resolve
             (cadr-cli::session-manager-continue-recent
              temporary directory))
            'cadr-agent:session))
          (is
           (string=
            (namestring (truename path))
            (namestring
             (truename
              (cadr-agent:session-path
               (cadr-cli::session-manager-resolve
                (cadr-cli::session-manager-open
                 path))))))))))))

(test goal12-sdk-resource-loader-supports-overrides-reload-and-diagnostics
  (with-test-directory (temporary)
    (let* ((agent-directory
             (merge-pathnames "agent/" temporary))
           (project-config
             (merge-pathnames ".cadr/" temporary)))
      (write-text
       (merge-pathnames "SYSTEM.md" project-config)
       "base system")
      (write-text
       (merge-pathnames "APPEND_SYSTEM.md" project-config)
       "base append")
      (write-text
       (merge-pathnames "AGENTS.md" agent-directory)
       "agent context")
      (write-text
       (merge-pathnames "AGENTS.md" temporary)
       "base context")
      (let* ((custom-skill
               (cadr-agent:make-skill
                :name "sdk-skill"
                :description "SDK skill"
                :content "instructions"
                :file-path "/virtual/SKILL.md"))
             (custom-prompt
               (cadr-agent:make-prompt-template
                :name "sdk-prompt"
                :description "SDK prompt"
                :content "prompt body"))
             (loader
               (cadr-cli::make-sdk-resource-loader
                :cwd temporary
                :agent-directory agent-directory
                :system-prompt-override
                (lambda (base)
                  (format nil "override(~A)" base))
                :append-system-prompt-override
                (lambda (base)
                  (append base '("sdk append")))
                :skills-override
                (lambda (items diagnostics)
                  (values
                   (append items (list custom-skill))
                   diagnostics))
                :prompts-override
                (lambda (items diagnostics)
                  (values
                   (append items (list custom-prompt))
                   diagnostics))
                :context-files-override
                (lambda (items)
                  (append
                   items
                   (list
                    (list :path "/virtual/AGENTS.md"
                          :content "sdk context")))))))
        (cadr-cli::sdk-resource-loader-reload loader)
        (is (string=
             "override(base system)"
             (cadr-cli::sdk-resource-loader-system-prompt
              loader)))
        (is (equal
             '("base append" "sdk append")
             (cadr-cli::sdk-resource-loader-append-system-prompt
              loader)))
        (is
         (find "sdk-skill"
               (cadr-cli::sdk-resource-loader-skills loader)
               :key #'cadr-agent:skill-name
               :test #'string=))
        (is
         (find "sdk-prompt"
               (cadr-cli::sdk-resource-loader-prompts loader)
               :key #'cadr-agent:prompt-template-name
               :test #'string=))
        (is (= 3
               (length
                (cadr-cli::sdk-resource-loader-context-files
                 loader))))
        (is (null
             (cadr-cli::sdk-resource-loader-diagnostics
              loader)))))))

(test goal12-sdk-model-runtime-supports-catalog-custom-provider-and-runtime-auth
  (with-test-directory (temporary)
    (let* ((auth-path
             (merge-pathnames "agent/auth.json" temporary))
           (models-path
             (merge-pathnames "agent/models.json" temporary))
           (runtime
             (cadr-cli::make-sdk-model-runtime
              :auth-path auth-path
              :models-path models-path)))
      (is
       (cadr-cli::sdk-model-runtime-model
        runtime :anthropic "claude-opus-4-5"))
      (cadr-cli::sdk-model-runtime-set-api-key
       runtime :anthropic "runtime-only")
      (is
       (eq :api-key
           (cadr-ai:runtime-auth-check-type
            (cadr-cli::sdk-model-runtime-check-auth
             runtime :anthropic))))
      (is (not (probe-file auth-path)))
      (let* ((custom-model
               (cadr-ai:make-model
                :id "custom-model"
                :provider :sdk-custom
                :api :openai-responses
                :base-url "https://custom.invalid"
                :max-tokens 1024))
             (provider
               (cadr-ai:make-runtime-provider
                :id :sdk-custom
                :name "SDK custom"
                :models (list custom-model)
                :api-key-auth-p t
                :auth-resolver
                (lambda (credential environment overrides)
                  (declare (ignore environment overrides))
                  (when credential
                    (cadr-ai:make-runtime-auth-result
                     :api-key
                     (cadr-ai:api-key-credential-key
                      credential)
                     :source "runtime"
                     :type :api-key))))))
        (cadr-cli::sdk-model-runtime-register-provider
         runtime provider)
        (cadr-cli::sdk-model-runtime-set-api-key
         runtime :sdk-custom "custom-key")
        (is
         (eq custom-model
             (cadr-cli::sdk-model-runtime-model
              runtime :sdk-custom "custom-model")))
        (is
         (find custom-model
               (cadr-cli::sdk-model-runtime-available-models
                runtime))))
      (cadr-cli::sdk-model-runtime-remove-api-key
       runtime :anthropic)
      (is (null
           (cadr-cli::sdk-model-runtime-check-auth
            runtime :anthropic))))))

(test goal12-sdk-model-runtime-oauth-login-uses-shared-atomic-auth-store
  (with-test-directory (temporary)
    (let* ((auth-path
             (merge-pathnames "agent/auth.json" temporary))
           (runtime
             (cadr-cli::make-sdk-model-runtime
              :auth-path auth-path
              :models-path nil))
           (provider
             (cadr-ai:make-runtime-provider
              :id :sdk-oauth
              :name "SDK OAuth"
              :models nil
              :oauth-auth-p t
              :oauth-login-function
              (lambda (interaction)
                (declare (ignore interaction))
                (cadr-ai:make-oauth-credential
                 :provider :sdk-oauth
                 :access "secret-access"
                 :refresh "secret-refresh"
                 :expires 4102444800000))
              :oauth-to-auth-function
              (lambda (credential)
                (cadr-ai:make-runtime-auth-result
                 :api-key
                 (cadr-ai:oauth-credential-access credential)
                 :source "OAuth"
                 :type :oauth)))))
      (cadr-cli::sdk-model-runtime-register-provider
       runtime provider)
      (cadr-cli::sdk-model-runtime-login
       runtime :sdk-oauth :oauth
       (cadr-ai:make-runtime-auth-interaction))
      (is (probe-file auth-path))
      (let ((credential
              (cadr-cli:auth-storage-read
               (cadr-cli:make-file-auth-storage auth-path)
               :sdk-oauth)))
        (is (typep credential 'cadr-ai:oauth-credential))
        (is (string= "secret-refresh"
                     (cadr-ai:oauth-credential-refresh
                      credential)))))))

(test goal12-extension-oauth-projects-session-local-login-methods-and-persists-atomically
  (with-test-directory (temporary)
    (let* ((cadr-cli::*native-extension-host* nil)
           (auth-path
             (merge-pathnames "agent/auth.json" temporary))
           (storage
             (cadr-cli:make-file-auth-storage auth-path))
           (registry
             (cadr-cli:make-model-registry
              :path nil :credentials storage))
           (runtime
             (cadr-cli::model-registry-native-runtime registry))
           (prompts nil)
           (notifications nil)
           (provider
             (cadr-ai:make-runtime-provider
              :id :extension-oauth
              :name "Extension OAuth"
              :models nil
              :api-key-auth-p t
              :oauth-auth-p t
              :api-key-login-function
              (lambda (interaction)
                (cadr-ai:make-api-key-credential
                 :provider :extension-oauth
                 :key
                 (cadr-ai:runtime-auth-interaction-prompt
                  interaction
                  '(:type :secret :message "API key"))))
              :oauth-login-function
              (lambda (interaction)
                (cadr-ai:runtime-auth-interaction-notify
                 interaction
                 '(:type :auth-url
                   :url "https://auth.invalid/start"
                   :instructions "Open the URL"))
                (let ((code
                        (cadr-ai:runtime-auth-interaction-prompt
                         interaction
                         '(:type :manual-code
                           :message "Authorization code"
                           :placeholder "paste code"))))
                  (is (string= "callback-code" code))
                  (cadr-ai:make-oauth-credential
                   :provider :extension-oauth
                   :access "oauth-access-secret"
                   :refresh "oauth-refresh-secret"
                   :expires 4102444800000))))))
      (cadr-ai:models-runtime-set-provider runtime provider)
      (let ((records
              (cadr-cli::model-registry-native-login-records
               registry)))
        (is (= 1 (length records)))
        (is (eq :extension-oauth
                (getf (first records) :id)))
        (is (string= "Extension OAuth"
                     (getf (first records) :name)))
        (is (equal '(:oauth :api-key)
                   (getf (first records) :auth-types))))
      (let ((credential
              (cadr-cli::model-registry-login-native-provider
               registry :extension-oauth
               (cadr-ai:make-runtime-auth-interaction
                :prompt-function
                (lambda (prompt)
                  (push prompt prompts)
                  "callback-code")
                :notify-function
                (lambda (event)
                  (push event notifications)))
               :auth-type :oauth)))
        (is (typep credential 'cadr-ai:oauth-credential))
        (is (= 1 (length prompts)))
        (is (= 1 (length notifications))))
      (let ((stored
              (cadr-cli:auth-storage-read
               storage :extension-oauth)))
        (is (typep stored 'cadr-ai:oauth-credential))
        (is (string= "oauth-refresh-secret"
                     (cadr-ai:oauth-credential-refresh stored))))
      (let ((output (make-string-output-stream)))
        (is
         (cadr-cli::handle-native-auth-command
          registry "/login extension-oauth"
          (cadr-ai:make-runtime-auth-interaction
           :prompt-function (constantly "callback-code")
           :notify-function (constantly nil))
          :output output))
        (let ((visible (get-output-stream-string output)))
          (is (search "Logged in to Extension OAuth. Credentials saved to " visible))
          (dolist (secret '("callback-code"
                            "oauth-access-secret"
                            "oauth-refresh-secret"))
            (is (not (search secret visible))))))
      ;; Reload removes the session-local provider projection, never the
      ;; credential already stored for a later reload of that extension.
      (cadr-ai:models-runtime-clear-providers runtime)
      (is (null
           (cadr-cli::model-registry-native-login-records registry)))
      (is (typep
           (cadr-cli:auth-storage-read storage :extension-oauth)
           'cadr-ai:oauth-credential)))))

(test goal12-sdk-settings-manager-preserves-disk-memory-and-override-precedence
  (with-test-directory (temporary)
    (let* ((global
             (merge-pathnames "agent/settings.json" temporary))
           (project
             (merge-pathnames ".cadr/settings.json" temporary))
           (manager
             (cadr-cli::make-sdk-settings-manager
              :global-path global
              :project-path project)))
      (cadr-cli::sdk-settings-set
       manager "defaultThinkingLevel" "low")
      (cadr-cli::sdk-settings-set
       manager "defaultModel" "disk-model")
      (cadr-cli::sdk-settings-apply-overrides
       manager
       (args
        "defaultModel" "override-model"
        "compaction" (args "enabled" nil)
        "retry" (args "enabled" t
                      "maxRetries" 5)))
      (is (string= "override-model"
                   (cadr-cli::sdk-settings-default-model
                    manager)))
      (is (string= "disk-model"
                   (cadr-ai::json-get
                    (cadr-ai::parse-json
                     (read-text global))
                    "defaultModel")))
      (is (eq :low
              (cadr-cli::sdk-settings-default-thinking-level
               manager)))
      (is (null
           (cadr-cli::sdk-settings-compaction-enabled-p
            manager)))
      (is (= 5
             (getf
              (cadr-cli::sdk-settings-retry-settings
               manager)
              :max-retries)))
      (is (eq manager
              (cadr-cli::sdk-settings-flush manager)))
      (is (null
           (cadr-cli::sdk-settings-drain-errors
            manager))))
    (let ((memory
            (cadr-cli::make-memory-sdk-settings-manager
             (args "defaultModel" "memory-model"))))
      (is (string= "memory-model"
                   (cadr-cli::sdk-settings-default-model
                    memory))))))

(test goal12-sdk-session-runtime-atomically-replaces-and-disposes-old-session
  (with-test-directory (temporary)
    (let* ((created 0)
           (factory
             (lambda (&key cwd agent-directory session-manager
                           session-start-event)
               (declare (ignore agent-directory session-start-event))
               (incf created)
               (multiple-value-bind (session extensions fallback)
                   (goal12-sdk-session
                    cwd :session-manager session-manager)
                 (declare (ignore extensions fallback))
                 (values session
                         (list
                          (format nil "created-~D"
                                  created))))))
           (runtime
             (cadr-cli::create-agent-session-runtime
              factory
              :cwd temporary
              :agent-directory
              (merge-pathnames "agent/" temporary)
              :session-manager
              (cadr-cli::session-manager-in-memory
               temporary)))
           (first
             (cadr-cli::agent-session-runtime-session
              runtime)))
      (is (= 1 created))
      (is (equal '("created-1")
                 (cadr-cli::agent-session-runtime-diagnostics
                  runtime)))
      (let ((second
              (cadr-cli::agent-session-runtime-new-session
               runtime)))
        (is (= 2 created))
        (is (not (eq first second)))
        (is
         (cadr-agent:agent-shutdown-p
          (cadr-cli::agent-session-agent first)))
        (is (eq second
                (cadr-cli::agent-session-runtime-session
                 runtime))))
      (cadr-cli::agent-session-runtime-dispose runtime)
      (is (null
           (cadr-cli::agent-session-runtime-session
            runtime))))))

(test goal12-sdk-services-reuse-a-single-explicit-bootstrap
  (with-test-directory (temporary)
    (let* ((settings
             (cadr-cli::make-memory-sdk-settings-manager))
           (resources
             (cadr-cli::make-sdk-resource-loader
              :cwd temporary
              :agent-directory
              (merge-pathnames "agent/" temporary)
              :no-extensions-p t
              :no-skills-p t
              :no-prompts-p t
              :no-themes-p t
              :no-context-files-p t))
           (services
             (cadr-cli::create-agent-session-services
              :cwd temporary
              :agent-directory
              (merge-pathnames "agent/" temporary)
              :settings-manager settings
              :resource-loader resources)))
      (multiple-value-bind (session extensions fallback)
          (cadr-cli::create-agent-session-from-services
           services
           :session-manager
           (cadr-cli::session-manager-in-memory temporary)
           :model (goal12-sdk-model)
           :provider :faux
           :thinking-level :off
           :stream-function #'goal12-sdk-stream
           :no-tools :all)
        (declare (ignore extensions fallback))
        (is (eq resources
                (cadr-cli::agent-session-resource-loader
                 session)))
        (is (eq settings
                (cadr-cli::agent-session-settings-manager
                 session)))
        (is (null
             (cadr-cli::agent-session-services-diagnostics
              services)))
        (cadr-cli::agent-session-dispose session)))))

(test goal12-sdk-default-tools-setting-selects-initial-builtin-tools
  ;; Mirrors default-tools-setting.test.ts (v0.84.2): the defaultTools
  ;; setting replaces the built-in default selection; explicit options
  ;; keep precedence.
  (with-test-directory (temporary)
    (multiple-value-bind (session)
        (cadr-cli::create-agent-session
         :cwd temporary
         :agent-directory (merge-pathnames "agent/" temporary)
         :model (goal12-sdk-model)
         :provider :faux
         :thinking-level :off
         :stream-function #'goal12-sdk-stream
         :session-manager
         (cadr-cli::session-manager-in-memory temporary)
         :settings-manager
         (cadr-cli::make-memory-sdk-settings-manager
          (cadr-ai::json-object
           "defaultTools" (vector "grep" "find"))))
      (is (equal '("find" "grep")
                 (sort
                  (mapcar
                   #'cadr-ai:tool-name
                   (cadr-agent::registry-tools
                    (cadr-agent::agent-tool-registry
                     (cadr-cli::agent-session-agent session))))
                  #'string<)))
      (cadr-cli::agent-session-dispose session))
    ;; Explicit :tools still wins over the setting.
    (multiple-value-bind (session)
        (cadr-cli::create-agent-session
         :cwd temporary
         :agent-directory (merge-pathnames "agent/" temporary)
         :model (goal12-sdk-model)
         :provider :faux
         :thinking-level :off
         :stream-function #'goal12-sdk-stream
         :session-manager
         (cadr-cli::session-manager-in-memory temporary)
         :settings-manager
         (cadr-cli::make-memory-sdk-settings-manager
          (cadr-ai::json-object
           "defaultTools" (vector "grep")))
         :tools '("read"))
      (is (equal '("read")
                 (mapcar
                  #'cadr-ai:tool-name
                  (cadr-agent::registry-tools
                   (cadr-agent::agent-tool-registry
                    (cadr-cli::agent-session-agent session))))))
      (cadr-cli::agent-session-dispose session))))
