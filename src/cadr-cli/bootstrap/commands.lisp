(in-package #:cadr-cli)

(defun make-agent-event-renderer (&optional
                                    (output *standard-output*))
  (let ((current-message nil)
        (printed-p nil))
    (lambda (event)
      (let ((type (cadr-agent:agent-event-type event))
            (message (cadr-agent:agent-event-message event))
            (stream-event
              (cadr-agent:agent-event-stream-event event)))
        (cond
          ((and (eq type :message-start)
                (typep message 'cadr-ai:assistant-message))
           (setf current-message message
                 printed-p nil))
          ((and (eq type :message-update)
                (eq message current-message)
                stream-event
                (eq :text-delta
                    (cadr-ai:stream-event-type stream-event)))
           (unless printed-p
             (format output "~&assistant> ")
             (setf printed-p t))
           (write-string
            (or (cadr-ai:stream-event-delta stream-event) "")
            output)
           (finish-output output))
          ((and (eq type :message-end)
                (eq message current-message))
           (when printed-p
             (terpri output)
             (finish-output output))
           (when (and (not printed-p)
                      (member
                       (cadr-ai:assistant-message-stop-reason message)
                       '(:error :aborted)))
             (format
              output "error> ~A~%"
              (or
               (cadr-ai:assistant-message-error-message message)
               (cadr-ai:assistant-message-stop-reason message)))
             (finish-output output))
           (setf current-message nil
                 printed-p nil))
          ((eq type :compaction-start)
           (format output "~&session> compacting context...~%")
           (finish-output output))
          ((eq type :compaction-end)
           (if (cadr-agent:agent-event-error-message event)
               (format
                output "~&error> ~A~%"
                (cadr-agent:agent-event-error-message event))
               (format output "~&session> context compacted~%"))
           (finish-output output))
          ((eq type :compaction-error)
           (format
            output "~&error> ~A~%"
            (cadr-agent:agent-event-error-message event))
           (finish-output output)))))))

(defun process-cli-file-arguments
    (paths &optional (cwd (uiop:getcwd)))
  (let ((text
          (make-array
           0 :element-type 'character
           :adjustable t :fill-pointer 0))
        (images nil))
    (dolist (raw paths)
      (let ((path
              (resolve-readable-tool-path
               cwd raw)))
        (unless
            (zerop
             (with-open-file
                 (stream path
                         :direction :input
                         :element-type
                         '(unsigned-byte 8))
               (file-length stream)))
          (multiple-value-bind
                (bytes mime-type hints)
              (process-image-file path)
            (if mime-type
                (progn
                  (format
                   text
                   "<file name=\"~A\">~{~A~^~%~}</file>~%"
                   (namestring path)
                   hints)
                  (push
                   (cadr-ai:make-image-content
                    :mime-type mime-type
                    :data
                    (encode-base64-bytes bytes))
                   images))
                (format
                 text
                 "<file name=\"~A\">~%~A~%</file>~%"
                 (namestring path)
                 (uiop:read-file-string
                  path :external-format :utf-8)))))))
    (values
     (coerce text 'string)
     (nreverse images))))

(defun call-with-cli-signal-handlers (agent function)
  #+sbcl
  (catch 'cadr-cli-signal
    (sb-sys:with-interrupt-bindings
      (flet ((exit-on-signal (exit-code)
               (lambda (signal code context)
                 (declare (ignore signal code context))
                 (cadr-agent:agent-abort agent)
                 (throw 'cadr-cli-signal exit-code))))
        (sb-sys:enable-interrupt
         sb-unix:sigterm
         (exit-on-signal 143))
        #-win32
        (sb-sys:enable-interrupt
         sb-unix:sighup
         (exit-on-signal 129)))
      (funcall function)))
  #-sbcl
  (funcall function))

(defun model-scope-startup-line
    (scoped-model-entries keybindings
     &key verbose-p quiet-startup-p)
  (when
      (and scoped-model-entries
           (or verbose-p (not quiet-startup-p)))
    (let* ((models
             (mapcar
              (lambda (entry)
                (let ((model (getf entry :model))
                      (thinking (getf entry :thinking)))
                  (format nil "~A~@[:~(~A~)~]"
                          (cadr-ai:model-id model)
                          thinking)))
              scoped-model-entries))
           (cycle-keys
             (cadr-tui:keybinding-keys
              keybindings "app.model.cycleForward"))
           (cycle-hint
             (if cycle-keys
                 (cadr-tui:theme-foreground
                  :muted
                  (format nil " (~A to cycle)"
                          (format-key-text
                           (format nil "~{~A~^/~}" cycle-keys)
                           :capitalize-p t)))
                 "")))
      (concatenate
       'string
       (cadr-tui:theme-foreground
        :dim
        (format nil "Model scope: ~{~A~^, ~}" models))
       cycle-hint))))

(defun model-cycle-target-entry
    (entries current-model direction)
  (let ((count (length entries)))
    (when (> count 1)
      (let* ((current-index
               (or
                (position
                 current-model entries
                 :key (lambda (entry)
                        (getf entry :model))
                 :test #'cadr-ai:models-equal-p)
                0))
             (next-index
               (mod
                (+ current-index
                   (if (eq direction :backward) -1 1))
                count)))
        (nth next-index entries)))))

(defun check-for-new-cadr-version-for-command (command)
  (if (cli-arguments-offline-p command)
      (check-for-new-cadr-version
       (cadr-ai::cadr-version)
       :offline-value "1")
      ;; Do not pass NIL here: omitting the keyword preserves the
      ;; CADR_OFFLINE environment default owned by the version checker.
      (check-for-new-cadr-version
       (cadr-ai::cadr-version))))

(defun cli-handler (command)
  (let* ((input-terminal-p
           (cadr-tui:terminal-stream-p
            *standard-input* :input))
         (output-terminal-p
           (cadr-tui:terminal-stream-p
            *standard-output* :output))
         (mode
           (resolve-cli-mode
            command
            input-terminal-p
            output-terminal-p))
         (tui-p (eq mode :tui))
         (repl-p (eq mode :repl))
         (event-consumer nil)
         (notice-consumer nil)
         (status-consumer nil)
         (warning-consumer nil)
         (auth-url-consumer nil)
         (auth-prompt-consumer nil)
         (auth-event-consumer nil)
         (model-consumer nil)
         (abort-requested-p nil)
         (startup-scope-line nil)
         (frontend-output
           (if tui-p
               (make-notification-output-stream
                (lambda (text)
                  (when notice-consumer
                    (funcall notice-consumer text))))
               (if repl-p
                   *standard-output*
                   *error-output*)))
         (startup-cwd (uiop:getcwd))
         (session-directory
           (if
               (cli-arguments-session-directory
                command)
               (uiop:ensure-directory-pathname
                (merge-pathnames
                 (pathname
                  (cli-arguments-session-directory
                   command))
                 startup-cwd))
               (cadr-agent:default-session-directory)))
         (session
           (resolve-cli-session
            :continue-p
            (cli-arguments-continue-p command)
            :resume-id
            (cli-arguments-resume command)
            :resume-selector-p
            (cli-arguments-resume-p command)
            :no-session-p
            (cli-arguments-no-session-p command)
            :session-path
            (cli-arguments-session command)
            :session-id
            (cli-arguments-session-id command)
            :fork-source
            (cli-arguments-fork command)
            :cwd startup-cwd
            :directory session-directory))
         (cwd
           (if session
               (uiop:ensure-directory-pathname
                (pathname
                 (cadr-agent:session-cwd session)))
               startup-cwd))
         (config
           (resolve-provider-config
            :provider
            (or (cli-arguments-provider command) "openai")
            :model (cli-arguments-model command)
            :reasoning (cli-arguments-thinking command)
            :base-url (cli-arguments-base-url command)
            :api-key (cli-arguments-api-key command)
            :allow-missing-auth-p t))
         (renderer (make-agent-event-renderer))
         (extension-manager
           (make-cli-extension-manager
            :cwd cwd
            :output frontend-output
            :mode mode
            :explicit-paths
            (cli-arguments-extensions command)
            :no-discovery-p
            (cli-arguments-no-extensions-p command)
            :secret-function
            (lambda ()
              (provider-config-secrets config))))
         (_extension-report
           (reload-cli-extensions extension-manager))
         (agent-directory
           (default-agent-directory))
         (trust-store
           (make-project-trust-store
            (merge-pathnames
             "trust.json" agent-directory)))
         (project-trusted-p
           (resolve-project-trusted
            trust-store cwd
            :override
            (cli-arguments-project-trust-override
             command)
            :override-supplied-p
            (cli-arguments-project-trust-override-supplied-p
             command)
            :extension-host
            (cli-extension-manager-host
             extension-manager)
            :default :ask
            :has-ui-p
            (or tui-p repl-p)
            :prompt-function
            (lambda (directory)
              (prompt-project-trust
               directory))))
         (settings-manager
           (make-settings-manager
            :global-path
            (merge-pathnames
             "settings.json" agent-directory)
            :project-path
            (merge-pathnames
             "settings.json"
             (cadr-core:project-config-directory cwd))
            :project-trusted-p project-trusted-p))
         (model-registry
           (make-model-registry
            :path
            (merge-pathnames
             "models.json" agent-directory)
            :credentials
            (make-file-auth-storage
             (default-auth-path))))
         (available-models
           (model-registry-available-models
            model-registry
            :explicit-provider
            (cli-arguments-provider command)
            :api-key
            (cli-arguments-api-key command)))
         (scope-patterns
           (or
            (cli-arguments-models command)
            (let ((configured
                    (settings-enabled-models
                     settings-manager)))
              (unless (eq configured :all)
                configured))))
         (scope-resolution
           (if scope-patterns
               (multiple-value-list
                (resolve-scoped-models-with-diagnostics
                 (%make-model-registry
                  :models available-models)
                 scope-patterns))
               (list nil nil)))
         (scoped-model-entries
           (first scope-resolution))
         (scope-diagnostics
           (second scope-resolution))
         (current-enabled-model-ids
           (if scope-patterns
               (enabled-model-ids-for-patterns
                scoped-model-entries
                scope-diagnostics)
               :all))
         (existing-session-p
           (and
            session
            (plusp
             (length
              (cadr-agent:session-messages
               session)))))
         (initial-scope-entry
           (initial-scoped-model-entry
            scoped-model-entries
            (settings-default-provider
             settings-manager)
            (settings-default-model
             settings-manager)
            :existing-session-p
            existing-session-p
            :explicit-model-p
            (not
             (null
              (cli-arguments-model command)))))
         (restored-model
           (and
            (null
             (cli-arguments-model command))
            existing-session-p
            (session-restored-model
             session model-registry
             available-models)))
         (saved-default-model
           (and
            (null
             (cli-arguments-model command))
            (null
             (cli-arguments-provider command))
            (settings-default-provider
             settings-manager)
            (settings-default-model
             settings-manager)
            (let ((candidate
                    (model-registry-find
                     model-registry
                     (settings-default-provider
                      settings-manager)
                     (settings-default-model
                      settings-manager))))
              (and
               candidate
               (find
                candidate
                available-models
                :test
                #'cadr-ai:models-equal-p)))))
         (startup-model
           (or
            (getf initial-scope-entry :model)
            restored-model
            saved-default-model
            (and
             (null
              (cli-arguments-model command))
             (null
              (cli-arguments-provider command))
             (first available-models))))
         (startup-thinking
           (and initial-scope-entry
                (getf initial-scope-entry
                      :thinking)))
         (_startup-model-config
           (when startup-model
             (setf
              config
              (provider-config-for-model
               model-registry startup-model
               :api-key
               (and
                (cli-arguments-provider command)
                (string-equal
                 (provider-key
                  (cadr-ai:model-provider
                   startup-model))
                 (provider-key
                  (cli-arguments-provider command)))
                (cli-arguments-api-key command))
               :base-url
               (and
                (cli-arguments-provider command)
                (string-equal
                 (provider-key
                  (cadr-ai:model-provider
                   startup-model))
                 (provider-key
                  (cli-arguments-provider command)))
                (cli-arguments-base-url
                 command))
               :allow-missing-auth-p t))))
         (_scope-diagnostic-report
           (dolist (diagnostic scope-diagnostics)
             (format
              frontend-output
              "Warning: ~A~%"
              (getf diagnostic :message))
             (finish-output frontend-output)))
         (package-global-root
           (merge-pathnames
            "packages/" agent-directory))
         (package-project-root
           (merge-pathnames
            "packages/"
            (cadr-core:project-config-directory cwd)))
         (package-records
           (materialize-package-records
            (configured-package-records
             settings-manager
             :global-base agent-directory
             :project-base
             (cadr-core:project-config-directory cwd))
            package-global-root
            package-project-root))
         (package-resources
           (package-resource-paths
            package-records))
         (_package-extension-report
           (progn
             (setf
              (cli-extension-manager-configured-package-paths
               extension-manager)
              (unless
                  (cli-arguments-no-extensions-p
                   command)
                (append
                 (mapcar
                  (lambda (path)
                    (cons :project path))
                  (getf package-resources
                        :project-extensions))
                 (mapcar
                  (lambda (path)
                    (cons :global path))
                  (getf package-resources
                        :global-extensions)))))
             (reload-cli-extensions
              extension-manager)))
         (resource-loader
           (make-default-resource-loader
            :cwd cwd
            :agent-directory agent-directory
            :project-trusted-p
            project-trusted-p
            :no-context-files-p
            (cli-arguments-no-context-files-p
             command)
            :no-skills-p
            (cli-arguments-no-skills-p command)
            :no-prompts-p
            (cli-arguments-no-prompt-templates-p
             command)
            :no-themes-p
            (cli-arguments-no-themes-p command)
            :explicit-skill-paths
            (cli-arguments-skills command)
            :explicit-prompt-paths
            (cli-arguments-prompt-templates command)
            :explicit-theme-paths
            (cli-arguments-themes command)
            :package-global-skill-paths
            (getf package-resources
                  :global-skills)
            :package-project-skill-paths
            (getf package-resources
                  :project-skills)
            :package-global-prompt-paths
            (getf package-resources
                  :global-prompts)
            :package-project-prompt-paths
            (getf package-resources
                  :project-prompts)
            :package-global-theme-paths
            (getf package-resources
                  :global-themes)
            :package-project-theme-paths
            (getf package-resources
                  :project-themes)
            :extension-host
            (cli-extension-manager-host
             extension-manager)))
         (resources
           (reload-resources resource-loader))
         (baseline-tools
           (make-all-coding-tools cwd))
         (builtin-names
           +builtin-coding-tool-names+)
         (tool-filter
           (lambda (tools)
             (if
                 (cli-arguments-no-tools-p
                  command)
                 nil
                 (select-coding-tools
                  tools
                  :allow
                  (or
                   (cli-arguments-tools command)
                   (append
                    +default-coding-tool-names+
                    (mapcar
                     #'cadr-ai:tool-name
                     (remove-if
                      (lambda (tool)
                        (member
                         (cadr-ai:tool-name tool)
                         builtin-names
                         :test #'string=))
                      tools))))
                  :exclude
                  (cli-arguments-exclude-tools
                   command)
                  :no-builtin-p
                  (cli-arguments-no-builtin-tools-p
                   command)
                  :builtin-names builtin-names))))
         (selected-baseline-tools
           (funcall tool-filter baseline-tools))
         (system-prompt-values
           (multiple-value-list
            (resolve-cli-system-prompt
             command resources
             selected-baseline-tools cwd)))
         (agent
           (cadr-agent:make-agent
            :provider (provider-config-provider config)
            :model (provider-config-model config)
            :system-prompt
            (first system-prompt-values)
            :system-prompt-options
            (second system-prompt-values)
            :tools baseline-tools
            :tool-filter-function tool-filter
            :extension-host
            (cli-extension-manager-host
             extension-manager)
            :stream-function
            (make-extension-aware-stream-function
             (cli-extension-manager-host
              extension-manager)
             :session-id
             (and session
                  (cadr-agent:session-id
                   session)))
            :session session
            :auto-compact-p
            (settings-boolean-value
             settings-manager
             "compaction" t "enabled")
            :abort-p
            (lambda () abort-requested-p)
            :on-event
            (lambda (event)
              (when event-consumer
                (funcall event-consumer event)))))
         (anthropic-warning-state
           (make-anthropic-warning-state)))
    (declare
     (ignore _extension-report
             _package-extension-report
             _startup-model-config
             _scope-diagnostic-report))
    (sync-agent-settings-from-manager
     agent settings-manager)
    (cadr-tui:set-keybindings
     (cadr-tui:make-keybindings-manager
      :user-bindings
      (settings-keybindings
       settings-manager)))
    (when (or
           (cli-arguments-thinking command)
           startup-thinking
           (let ((configured
                   (settings-value
                    settings-manager
                    "defaultThinkingLevel")))
             (and
              (stringp configured)
              (valid-thinking-level-p configured))))
      (setf
       (cadr-agent::agent-thinking-level agent)
       (cadr-ai:clamp-thinking-level
        (cadr-agent:agent-model agent)
        (or
         (cli-arguments-thinking command)
         startup-thinking
         (intern
          (string-upcase
           (settings-value
            settings-manager
            "defaultThinkingLevel"))
          :keyword)))))
    (when (cli-arguments-name command)
      (let ((name
              (string-trim
               '(#\Space #\Tab #\Newline #\Return)
               (cli-arguments-name command))))
        (when (zerop (length name))
          (error
           'cadr-ai:configuration-error
           :message "--name requires a non-empty value"))
        (when session
          (cadr-agent:session-set-name
           session name))))
    (labels
        ((anthropic-warning ()
           (maybe-anthropic-subscription-warning
            anthropic-warning-state
            (cadr-ai:model-provider
             (provider-config-model config))
            (settings-effective-object
             settings-manager)
            (lambda ()
              (let ((provider
                      (provider-config-provider
                       config)))
                (if
                    (cadr-ai::provider-oauth-access-token
                     provider)
                    :oauth
                    (cadr-ai::provider-api-key
                     provider))))))
         (config-subscription-p ()
           (let ((provider
                   (provider-config-provider config)))
             (or
              (and
               provider
               (cadr-ai::provider-oauth-access-token
                provider))
              (string-equal
               (provider-key
                (provider-config-name config))
               "kimi-coding"))))
         (valid-context-assistant-entry-p (entry)
           (and
            (eq
             :message
             (cadr-agent:session-entry-type entry))
            (let ((message
                    (cadr-agent:session-entry-message
                     entry)))
              (and
               (typep
                message
                'cadr-ai:assistant-message)
               (not
                (member
                 (cadr-ai:assistant-message-stop-reason
                  message)
                 '(:aborted :error)))
               (plusp
                (cadr-ai:usage-total
                 (cadr-ai:assistant-message-usage
                  message)))))))
         (current-context-percent ()
           (let* ((model
                    (cadr-agent:agent-model agent))
                  (window
                    (cadr-ai:model-context-window model))
                  (current
                    (cadr-agent:agent-session agent))
                  (entries
                    (and
                     current
                     (cadr-agent::session-path-entries
                      current)))
                  (compaction
                    (and
                     entries
                     (cadr-agent::latest-compaction-entry
                      entries)))
                  (compaction-position
                    (and
                     compaction
                     (position compaction entries
                               :test #'eq))))
             (when
                 (and
                  (plusp window)
                  (or
                   (null compaction)
                   (find-if
                    #'valid-context-assistant-entry-p
                    entries
                    :start
                    (1+ compaction-position))))
               (let ((estimate
                       (cadr-agent::context-estimated-tokens
                        (cadr-agent:agent-messages agent))))
                 (* 100d0
                    (/ estimate window))))))
         (current-cache-hit-rate ()
           (let ((current
                   (cadr-agent:agent-session agent)))
             (when current
               (loop
                 for entry in
                 (reverse
                  (cadr-agent:session-entries
                   current))
                 when
                   (and
                    (eq
                     :message
                     (cadr-agent:session-entry-type
                      entry))
                    (typep
                     (cadr-agent:session-entry-message
                      entry)
                     'cadr-ai:assistant-message))
                   do
                   (let* ((usage
                            (cadr-ai:assistant-message-usage
                             (cadr-agent:session-entry-message
                              entry)))
                          (prompt
                            (+ (cadr-ai:usage-input usage)
                               (cadr-ai:usage-cache-read
                                usage)
                               (cadr-ai:usage-cache-write
                                usage))))
                     (return
                       (and
                        (plusp prompt)
                        (* 100d0
                           (/ (cadr-ai:usage-cache-read
                               usage)
                              prompt)))))))))
         (current-footer-state ()
           (let* ((model
                    (cadr-agent:agent-model agent))
                  (current
                    (cadr-agent:agent-session agent))
                  (stats
                    (and
                     current
                     (session-command-stats current)))
                  (providers
                    (remove-duplicates
                     (mapcar
                      #'cadr-ai:model-provider
                      (if scoped-model-entries
                          (mapcar
                           (lambda (entry)
                             (getf entry :model))
                           scoped-model-entries)
                          available-models))
                     :test #'eq))
                  (messages
                    (and
                     current
                     (cadr-agent:session-messages
                      current))))
             (list
              :model (cadr-ai:model-id model)
              :provider
              (provider-config-name config)
              :thinking
              (and
               (cadr-ai:model-reasoning-p model)
               (cadr-agent::agent-thinking-level
                agent))
              :context-window
              (cadr-ai:model-context-window model)
              :context-percent
              (current-context-percent)
              :session-name
              (and
               current
               (cadr-agent:session-name current))
              :multiple-providers-p
              (> (length providers) 1)
              :subscription-p
              (not (null (config-subscription-p)))
              :auto-compact-p
              (cadr-agent::agent-auto-compact-p agent)
              :input (or (getf stats :input) 0)
              :output (or (getf stats :output) 0)
              :cache-read
              (or (getf stats :cache-read) 0)
              :cache-write
              (or (getf stats :cache-write) 0)
              :latest-cache-hit-rate
              (current-cache-hit-rate)
              :cost (or (getf stats :cost) 0d0)
              :cost-known-p
              (some
               (lambda (message)
                 (and
                  (typep
                   message
                   'cadr-ai:assistant-message)
                  (ignore-errors
                    (cadr-ai:find-model-metadata
                     (cadr-ai:assistant-message-provider
                      message)
                     (cadr-ai:assistant-message-model
                      message)))))
               messages))))
         (authentication-status (provider)
           (model-registry-authentication-status
            model-registry provider))
         (current-login-options ()
           (model-registry-login-options
            model-registry #'authentication-status))
         (runtime-auth-notify (event)
           (if auth-event-consumer
               (funcall auth-event-consumer event)
               (case (getf event :type)
                 (:auth-url
                  (when auth-url-consumer
                    (funcall auth-url-consumer
                             (getf event :url)))
                  (when (and status-consumer
                             (getf event :instructions))
                    (funcall status-consumer
                             (getf event :instructions))))
                 (:device-code
                  (when auth-url-consumer
                    (funcall auth-url-consumer
                             (getf event :verification-uri)))
                  (when status-consumer
                    (funcall
                     status-consumer
                     (format nil "Device code: ~A"
                             (getf event :user-code)))))
                 ((:info :progress)
                  (when status-consumer
                    (funcall status-consumer
                             (getf event :message))))))
           nil)
         (runtime-auth-interaction (&key supplied-value)
           (cadr-ai:make-runtime-auth-interaction
            :prompt-function
            (lambda (prompt)
              (if supplied-value
                  supplied-value
                  (if auth-prompt-consumer
                      (funcall auth-prompt-consumer prompt)
                      (error
                       'cadr-ai:configuration-error
                       :message
                       "Interactive authentication prompt is unavailable"))))
            :notify-function #'runtime-auth-notify
            :abort-p (lambda () abort-requested-p)))
         (stored-logout-options ()
           (logout-provider-options
            (cadr-ai:list-provider-definitions)
            (auth-storage-list
             (model-registry-credentials model-registry))))
         (refresh-auth (provider action)
           (let ((previous-auth-source
                   (provider-config-auth-source
                    config)))
             (refresh-available-models)
             (if
                 (and
                  (eq action :login)
                  (or
                   (eq previous-auth-source :none)
                   (not
                    (eq
                     provider
                     (cadr-ai:model-provider
                      (provider-config-model
                       config))))))
                 (let* ((native-p
                          (model-registry-native-provider-p
                           model-registry provider))
                        (definition
                          (and
                           (not native-p)
                           (cadr-ai:find-provider-definition
                            provider)))
                        (model
                          (if native-p
                              (find
                               provider available-models
                               :key #'cadr-ai:model-provider
                               :test #'eq)
                              (model-registry-find
                               model-registry
                               provider
                               (cadr-ai:provider-definition-default-model
                                definition)))))
                   (if
                       (and model
                            (find
                             model available-models
                             :test
                             #'cadr-ai:models-equal-p))
                       (progn
                         (select-model model)
                         ;; Report the selection so the login completion
                         ;; message can carry the baseline "Selected <id>."
                         (cadr-ai:model-id model))
                       ;; The login handler turns this marker into the
                       ;; baseline "no default model is configured"
                       ;; caveat; the login itself already succeeded.
                       :no-default-model))
                 (let ((updated
                         (resolve-provider-config
                          :provider
                          (provider-config-name config)
                          :model
                          (cadr-ai:model-id
                           (provider-config-model config))
                          :base-url
                          (cli-arguments-base-url command)
                          :api-key
                          (cli-arguments-api-key command)
                          :allow-missing-auth-p t)))
                   (setf
                    config updated
                    (cadr-agent:agent-provider agent)
                    (provider-config-provider updated)
                    (cadr-agent:agent-model agent)
                    (provider-config-model updated))))))
         (select-logout-provider (provider)
           (auth-storage-delete
            (model-registry-credentials model-registry)
            provider)
           (refresh-auth provider :logout)
           provider)
         (run-prompt (prompt)
           (let ((*bash-live-output*
                   (bash-live-output-for-mode
                    mode frontend-output)))
             (cadr-agent:agent-prompt
              agent prompt
              :source
              (if (eq mode :rpc)
                  :rpc
                  :interactive))))
         (run-user-bash (command exclude-p)
           (if (eq mode :tui)
               (let ((*bash-live-output*
                       (bash-live-output-for-mode
                        mode frontend-output)))
                 (record-user-bash-result
                  agent
                  (execute-user-bash-for-tui
                   (cli-extension-manager-host extension-manager)
                   cwd command
                   :exclude-from-context-p exclude-p
                   :abort-p (lambda () abort-requested-p))))
               (multiple-value-bind (content details)
                   (execute-user-bash
                    (cli-extension-manager-host extension-manager)
                    cwd command
                    :exclude-from-context-p exclude-p
                    :abort-p (lambda () abort-requested-p))
                 (record-user-bash-result
                  agent
                  (make-user-bash-result-from-execution
                   command exclude-p content details))
                 (if content
                     (cadr-ai:text-content-text (first content))
                     ""))))
         (refresh-package-resources ()
           (setf
            package-records
            (materialize-package-records
             (configured-package-records
              settings-manager
              :global-base agent-directory
              :project-base
              (cadr-core:project-config-directory cwd))
             package-global-root
             package-project-root)
            package-resources
            (package-resource-paths
             package-records)
            (cli-extension-manager-configured-package-paths
             extension-manager)
            (unless
                (cli-arguments-no-extensions-p command)
              (append
               (mapcar
                (lambda (path)
                  (cons :project path))
                (getf package-resources
                      :project-extensions))
               (mapcar
                (lambda (path)
                  (cons :global path))
                (getf package-resources
                      :global-extensions))))
            (default-resource-loader-package-global-skill-paths
             resource-loader)
            (getf package-resources :global-skills)
            (default-resource-loader-package-project-skill-paths
             resource-loader)
            (getf package-resources :project-skills)
            (default-resource-loader-package-global-prompt-paths
             resource-loader)
            (getf package-resources :global-prompts)
            (default-resource-loader-package-project-prompt-paths
             resource-loader)
            (getf package-resources :project-prompts)
            (default-resource-loader-package-global-theme-paths
             resource-loader)
            (getf package-resources :global-themes)
            (default-resource-loader-package-project-theme-paths
             resource-loader)
            (getf package-resources :project-themes))
           package-resources)
         (current-theme-summary ()
           (let* ((configured
                    (settings-value
                     settings-manager
                     "theme" nil))
                  (background
                    (theme-detection-theme
                     (detect-background-from-environment)))
                  (name
                    (or
                     (and
                      configured
                      (resolve-theme-setting
                       configured background))
                     (string-downcase
                      (symbol-name background)))))
             (or
              (find
               name
               (resource-snapshot-themes resources)
               :key
               (lambda (theme)
                 (getf theme :name))
               :test #'string=)
              (list :name name :path nil))))
         (handle-command (line)
           (or
            (handle-native-auth-command
             model-registry line
             (runtime-auth-interaction)
             :output frontend-output
             :on-change #'refresh-auth)
            (handle-auth-command
             line
             :output frontend-output
             :auth-url-function
             auth-url-consumer
             :auth-prompt-function
             auth-prompt-consumer
             :on-change #'refresh-auth)
            (handle-session-command
             line agent
             :directory session-directory
             :cwd cwd
             :output frontend-output
             :status-function status-consumer
             :ansi-theme-p tui-p
             :model-price-function
             (lambda (provider model-id)
               (handler-case
                   (cadr-ai:model-metadata-cache-read-price
                    (cadr-ai:find-model-metadata
                     provider model-id))
                 (cadr-ai:configuration-error () 0d0)))
             :keybindings
             (settings-keybindings
              settings-manager)
             :export-options-function
             (lambda ()
               (let ((theme
                       (current-theme-summary)))
                 (list
                  :theme-name (getf theme :name)
                  :theme-object (getf theme :object)))))
            (if
                (string=
                 (string-trim
                  '(#\Space #\Tab #\Newline #\Return)
                  line)
                "/reload")
                (progn
                  (setf
                   resources
                   (reload-cli-runtime
                    agent settings-manager
                    :extension-reload-function
                    (lambda ()
                      (refresh-package-resources)
                      (reload-cli-extensions
                       extension-manager))
                    :resource-reload-function
                    (lambda ()
                      (reload-resources
                       resource-loader))
                    :system-prompt-function
                    (lambda (snapshot)
                      (resolve-cli-system-prompt
                       command snapshot
                       (cadr-agent::registry-tools
                        (cadr-agent::agent-tool-registry
                         agent))
                       cwd))
                    :model-refresh-function
                    (lambda ()
                      (refresh-available-models)
                      (refresh-agent-model-from-registry
                       agent model-registry
                       :api-key
                       (cli-arguments-api-key command)
                       :base-url
                       (cli-arguments-base-url command))
                      (update-session-scope
                       current-enabled-model-ids))
                    :keybindings-reload-function
                    (lambda ()
                      (cadr-tui:set-keybindings
                       (cadr-tui:make-keybindings-manager
                        :user-bindings
                        (settings-keybindings
                         settings-manager))))
                    :completion-function
                    (lambda (message)
                      (if status-consumer
                          (funcall status-consumer message)
                          (progn
                            (format frontend-output "~A~%" message)
                            (finish-output frontend-output))))))
                  t)
                (handle-extension-command
                 line extension-manager))))
         (expand-template (line)
           (expand-cli-extension-prompt
            extension-manager line))
         (model-items ()
           (loop
             for model in available-models
             collect
             (cadr-tui:make-select-item
              :label
              (format nil "~(~A~) / ~A"
                      (cadr-ai:model-provider model)
                      (cadr-ai:model-id model))
              :value model)))
         (refresh-available-models ()
           (refresh-model-registry model-registry)
           (setf
            available-models
            (model-registry-available-models
             model-registry
             :explicit-provider
             (cli-arguments-provider command)
             :api-key
             (cli-arguments-api-key command)))
           available-models)
         (select-model
             (model &key (source :interactive)
                         (thinking-level nil thinking-level-p))
           (let ((updated
                   (apply
                    #'apply-cli-model-selection
                    agent model-registry model
                    settings-manager
                    (append
                     (list
                      :api-key
                      (and
                       (cli-arguments-provider command)
                       (string-equal
                        (provider-key
                         (cadr-ai:model-provider model))
                        (provider-key
                         (cli-arguments-provider command)))
                       (cli-arguments-api-key command))
                      :base-url
                      (and
                       (cli-arguments-provider command)
                       (string-equal
                        (provider-key
                         (cadr-ai:model-provider model))
                        (provider-key
                         (cli-arguments-provider command)))
                       (cli-arguments-base-url command))
                      :source source)
                     (when thinking-level-p
                       (list :thinking-level thinking-level))))))
             (setf config updated)
             (let* ((model-id
                      (cadr-ai:model-id
                       (provider-config-model updated)))
                    (warning
                      (anthropic-warning)))
               (when model-consumer
                 (funcall
                  model-consumer model-id
                  (provider-config-name
                   updated)
                  (cadr-ai:model-context-window
                   (provider-config-model updated))
                  (and
                   (cadr-ai:model-reasoning-p
                    (provider-config-model updated))
                   (cadr-agent::agent-thinking-level
                    agent))
                  (if
                      (config-subscription-p)
                      t
                      :not-subscription)))
               (when
                   (and warning
                        warning-consumer)
                 (funcall
                  warning-consumer warning))
               model-id)))
         (cycle-model (direction)
           (refresh-available-models)
           (let* ((scoped-p
                    (not (null scoped-model-entries)))
                  (entries
                    (if scoped-p
                        (remove-if-not
                         (lambda (entry)
                           (find
                            (getf entry :model)
                            available-models
                            :test #'cadr-ai:models-equal-p))
                         scoped-model-entries)
                        (mapcar
                         (lambda (model)
                           (list :model model :thinking nil))
                         available-models)))
                  (count (length entries)))
             (when (<= count 1)
               (return-from cycle-model
                 (if scoped-p
                     "Only one model in scope"
                     "Only one model available")))
             (let* ((next
                      (model-cycle-target-entry
                       entries
                       (cadr-agent:agent-model agent)
                       direction))
                    (model (getf next :model))
                    (thinking (getf next :thinking)))
               (if thinking
                   (select-model
                    model :source :cycle
                    :thinking-level thinking)
                   (select-model model :source :cycle))
               (let ((effective-thinking
                       (cadr-agent::agent-thinking-level agent)))
                 (format
                  nil "Switched to ~A~A"
                  (or (cadr-ai::model-name model)
                      (cadr-ai:model-id model))
                  (if
                      (and (cadr-ai:model-reasoning-p model)
                           (not (eq effective-thinking :off)))
                      (format nil " (thinking: ~(~A~))"
                              effective-thinking)
                      ""))))))
         (resolve-model-reference (reference)
           (refresh-available-models)
           (exact-model-reference-match
            reference
            (if scoped-model-entries
                (mapcar
                 (lambda (entry)
                   (getf entry :model))
                 scoped-model-entries)
                available-models)))
         (model-selector (&optional query)
           (refresh-available-models)
           (let ((selector
                   (make-model-selector-state
                    :all-models available-models
                    :scoped-models
                    (mapcar
                     (lambda (entry)
                       (getf entry :model))
                     scoped-model-entries)
                    :current-model
                    (cadr-agent:agent-model agent)
                    :refresh-status-message
                    (and
                     (null
                      (model-registry-error
                       model-registry))
                     "Model catalogs refreshed.")
                    :keybindings
                    (make-models-selector-keybindings
                     (settings-keybindings
                      settings-manager)))))
             (when query
               (model-selector-set-query
                selector query))
             selector))
         (update-session-scope (enabled-ids)
           (setf
            current-enabled-model-ids
            (if (eq enabled-ids :all)
                :all
                (copy-list enabled-ids))
            scoped-model-entries
            (mapcar
             (lambda (model)
               (list :model model
                     :thinking nil))
             (session-scoped-models
              available-models enabled-ids))))
         (persist-model-scope (enabled-ids)
           (settings-set-enabled-models
            settings-manager enabled-ids)
           (when status-consumer
             (funcall
              status-consumer
              "Model selection saved to settings")))
         (scoped-models-selector ()
           (refresh-available-models)
           (when
               (or available-models
                   (and
                    (listp current-enabled-model-ids)
                    current-enabled-model-ids))
             (make-scoped-models-selector-state
              :all-models available-models
              :enabled-ids
              current-enabled-model-ids
              :change-callback
              #'update-session-scope
              :persist-callback
              #'persist-model-scope
              :keybindings
              (make-models-selector-keybindings
               (settings-keybindings
                settings-manager)))))
         (trust-selector ()
           (make-trust-selector-state
            :cwd cwd
            :saved-entry
            (project-trust-entry
             trust-store cwd)
            :project-trusted-p
            project-trusted-p
            :keybindings
            (cadr-tui:make-keybindings-manager
             :user-bindings
             (settings-keybindings
              settings-manager))))
         (settings-selector ()
           (make-cli-settings-selector-state
            settings-manager agent resources
            :keybindings
            (cadr-tui:make-keybindings-manager
             :user-bindings
             (settings-keybindings
              settings-manager))))
         (select-trust (selection)
           (project-trust-set-many
            trust-store
            (getf selection :updates))
           (when status-consumer
             (funcall
              status-consumer
              (format
               nil
               "Saved trust decision: ~A. Restart cadr for this to take effect."
               (if
                   (getf selection :trusted-p)
                   "trusted"
                   "untrusted"))))
           (getf selection :trusted-p))
         (confirm-import (line)
           (handle-session-command
            line agent
            :directory session-directory
            :cwd cwd
            :output frontend-output
            :confirm-function
            (lambda (title message)
              (declare (ignore title message))
              t)))
         (fork-items ()
           (loop
             for item in
             (session-user-messages-for-forking
              (cadr-agent:agent-session agent))
             collect
             (cadr-tui:make-select-item
              :label (getf item :text)
              :value (getf item :entry-id))))
         (select-fork-entry (entry-id)
           (multiple-value-bind
                 (fork selected-text)
               (fork-agent-session
                agent entry-id
                session-directory)
             (if (eq fork :cancelled)
                 (values nil nil nil nil)
                 (values
                  (cadr-agent:session-id fork)
                  (copy-list
                   (cadr-agent:session-messages
                    fork))
                  (cadr-agent:session-path fork)
                  selected-text))))
         (start-new-session ()
           (let ((new
                   (new-agent-session
                    agent session-directory cwd)))
             (if (eq new :cancelled)
                 (values nil nil nil)
                 (values
                  (cadr-agent:session-id new)
                  (copy-list
                   (cadr-agent:session-messages new))
                  (cadr-agent:session-path new)))))
         (clone-current-session ()
           (let ((clone
                   (clone-agent-session
                    agent session-directory)))
             (if (or (null clone)
                     (eq clone :cancelled))
                 (values nil nil nil)
                 (values
                  (cadr-agent:session-id clone)
                  (copy-list
                   (cadr-agent:session-messages clone))
                  (cadr-agent:session-path clone)))))
         (session-items ()
           (loop
             for candidate in
             (cadr-agent:list-sessions
              :directory session-directory
              :cwd cwd)
             collect
             (cadr-tui:make-select-item
              :label
              (format nil "~A  ~D messages"
                      (cadr-agent:session-id
                       candidate)
                      (length
                       (cadr-agent:session-messages
                        candidate)))
              :value candidate)))
         (all-session-items ()
           (loop
             for candidate in
             (cadr-agent:list-sessions
              :directory session-directory)
             collect
             (cadr-tui:make-select-item
              :label
              (format nil "~A  ~D messages"
                      (cadr-agent:session-id
                       candidate)
                      (length
                       (cadr-agent:session-messages
                        candidate)))
              :value candidate)))
         (current-session-display-state ()
           (let ((current
                   (cadr-agent:agent-session
                    agent)))
             (session-compaction-display-state current)))
         (select-session (candidate)
           (switch-agent-session agent candidate)
           (values
            (cadr-agent:session-id candidate)
            (cadr-agent:session-messages
             candidate)
            (cadr-agent:session-path candidate)))
         (current-session-tree ()
           (session-tree-selector-data
            (cadr-agent:agent-session agent)))
         (select-tree-entry (entry-id)
           (multiple-value-bind
                 (messages cancelled-p)
               (cadr-agent:agent-navigate-tree
                agent entry-id)
             (unless cancelled-p
               messages)))
         (set-tree-label (entry-id label)
           (let ((session
                   (cadr-agent:agent-session agent)))
             (unless session
               (error
                'cadr-ai:configuration-error
                :message
                "The agent has no persistent session"))
             (cadr-agent:session-set-label
              session entry-id label)))
         (extension-command-records ()
           (let* ((host
                    (cli-extension-manager-host extension-manager))
                  (snapshot
                    (cadr-agent::extension-host-current-snapshot host)))
             (append
              (loop for (name description argument-hint)
                    in +tui-autocomplete-command-specifications+
                    collect
                    (list :name name :description description
                          :argument-hint argument-hint
                          :source :builtin))
              (loop for definition in
                    (cadr-agent::extension-snapshot-commands snapshot)
                    collect
                    (list
                     :name
                     (cadr-agent::extension-command-definition-name definition)
                     :description
                     (cadr-agent::extension-command-definition-description definition)
                     :argument-hint
                     (cadr-agent::extension-command-definition-argument-hint definition)
                     :source :extension
                     :source-info
                     (list
                      :path
                      (cadr-agent::extension-definition-origin definition))))
              (loop for definition in
                    (cadr-agent::extension-snapshot-templates snapshot)
                    collect
                    (list
                     :name
                     (cadr-agent::extension-template-definition-name definition)
                     :description
                     (cadr-agent::extension-template-definition-description definition)
                     :argument-hint
                     (cadr-agent::extension-template-definition-argument-hint definition)
                     :source :prompt-template
                     :source-info
                     (list
                      :path
                      (cadr-agent::extension-definition-origin definition)))))))
         (extension-tool-records ()
           (let ((host
                   (cli-extension-manager-host extension-manager)))
             (loop for tool in (cadr-agent::merged-agent-tools agent)
                   for name = (cadr-ai:tool-name tool)
                   for metadata =
                     (cadr-agent::extension-host-tool-metadata host name)
                   collect
                   (list
                    :name name
                    :description (cadr-ai:tool-description tool)
                    :parameters (cadr-ai:tool-parameters tool)
                    :label (or (getf metadata :label) name)
                    :prompt-snippet (getf metadata :prompt-snippet)
                    :prompt-guidelines
                    (copy-list (getf metadata :prompt-guidelines))
                    :source (or (getf metadata :source) :builtin)))))
         (extension-context-usage ()
           (let* ((model (cadr-agent:agent-model agent))
                  (window (cadr-ai:model-context-window model))
                  (tokens
                    (cadr-agent::context-estimated-tokens
                     (cadr-agent:agent-messages agent))))
             (and
              (plusp window)
              (list :tokens tokens
                    :context-window window
                    :percent (* 100d0 (/ tokens window))))))
         (extension-new-session (arguments)
           (let* ((parent-session (getf arguments :parent-session))
                  (setup-function (getf arguments :setup-function))
                  (with-session-function
                    (getf arguments :with-session-function))
                  (source-context (getf arguments :source-context)))
             (when setup-function
               (funcall
                setup-function
                (session-manager-create cwd session-directory)))
             (let ((new
                     (new-agent-session
                      agent session-directory cwd
                      :parent-session parent-session)))
               (if (eq new :cancelled)
                   '(:cancelled t)
                   (progn
                     (when source-context
                       (setf
                        (cadr-agent::%extension-context-active-p
                         source-context)
                        nil))
                     (when with-session-function
                       (let ((replacement
                               (cadr-agent::%make-extension-context
                                :host
                                (cadr-agent::%extension-context-host
                                 source-context)
                                :source-path
                                (cadr-agent::%extension-context-source-path
                                 source-context)
                                :bundle
                                (cadr-agent::%extension-context-bundle
                                 source-context)
                                :kind :command)))
                         (unwind-protect
                              (funcall with-session-function replacement)
                           (setf
                            (cadr-agent::%extension-context-active-p replacement)
                            nil))))
                     '(:cancelled nil))))))
         (extension-action (action arguments)
           (case action
             (:model (cadr-agent:agent-model agent))
             (:scoped-models
              (mapcar (lambda (entry) (getf entry :model))
                      scoped-model-entries))
             (:thinking-level
              (cadr-agent::agent-thinking-level agent))
             (:signal
              (cadr-agent:make-extension-cancellation-signal
               :aborted-function
               (lambda () (cadr-agent::agent-aborted-p agent))
               :abort-function
               (lambda () (cadr-agent:agent-abort agent))))
             (:abort (cadr-agent:agent-abort agent))
             (:shutdown (cadr-agent:agent-shutdown agent))
             (:has-pending-messages-p
              (or (cadr-agent::agent-steering-queue agent)
                  (cadr-agent::agent-follow-up-queue agent)
                  (cadr-agent::agent-next-turn-queue agent)))
             (:context-usage (extension-context-usage))
             (:system-prompt (cadr-agent::agent-system-prompt agent))
             (:system-prompt-options
              (list :cwd (namestring cwd)
                    :selected-tools
                    (cadr-agent::extension-host-current-active-tools
                     (cli-extension-manager-host extension-manager))))
             (:new-session (extension-new-session arguments))
             (:model-registry-find
              (model-registry-find
               model-registry (first arguments) (second arguments)))
             (:model-registry-resolve-auth
              (provider-config-for-model
               model-registry (first arguments)
               :allow-missing-auth-p nil))
             (:commands (extension-command-records))
             (:all-tools (extension-tool-records))
             (:set-thinking-level
              (cadr-agent:agent-set-thinking-level
               agent
               (cadr-ai:clamp-thinking-level
                (cadr-agent:agent-model agent)
                (first arguments))))
             (:set-model
              (handler-case
                  (progn
                    (provider-config-for-model
                     model-registry (first arguments)
                     :allow-missing-auth-p nil)
                    (select-model (first arguments))
                    t)
                (condition () nil)))
             (:get-session-name
              (let ((current (cadr-agent:agent-session agent)))
                (and current (cadr-agent:session-name current))))
             (:append-entry
              (let ((current (cadr-agent:agent-session agent)))
                (when current
                  (let ((entry
                          (cadr-agent:session-append-custom
                           current (first arguments) (second arguments)))
                        (ui-function
                          (cadr-agent::extension-host-ui-function
                           (cli-extension-manager-host extension-manager))))
                    (when ui-function
                      (funcall
                       ui-function :append-custom-entry
                       (list :custom-type (first arguments)
                             :data (second arguments))))
                    entry))))
             (:set-label
              (set-tree-label (first arguments) (second arguments)))
             (otherwise
              (error 'cadr-agent:extension-execution-error
                     :message
                     (format nil "Unsupported extension action: ~(~A~)"
                             action))))))
      (setf
       (cadr-agent::extension-host-action-function
        (cli-extension-manager-host extension-manager))
       #'extension-action)
      (call-with-remote-repl
       agent
       (cli-arguments-slynk-port command)
       (lambda (remote-repl-port)
         (declare (ignore remote-repl-port))
         (call-with-cli-signal-handlers
          agent
          (lambda ()
            (case mode
           (:tui
            (setf
             startup-scope-line
             (model-scope-startup-line
              scoped-model-entries
              (cadr-tui:get-keybindings)
              :verbose-p
              (cli-arguments-verbose-p command)
              :quiet-startup-p
              (settings-value
               settings-manager "quietStartup" nil)))
            (when startup-scope-line
              (write-line startup-scope-line)
              (finish-output))
            (multiple-value-bind
                  (file-text file-images)
                (process-cli-file-arguments
                 (cli-arguments-file-arguments
                  command)
                 cwd)
              (multiple-value-bind
                    (initial messages)
                  (build-cli-print-prompts
                   command nil
                   :file-text file-text
                   :file-images file-images)
                (when initial
                  (run-prompt initial))
                (dolist (message messages)
                  (run-prompt message))))
            (multiple-value-bind
                  (startup-compact
                   startup-expanded)
                (if
                    (or
                     (cli-arguments-verbose-p command)
                     (not
                      (settings-value
                       settings-manager
                       "quietStartup" nil)))
                    (make-tui-startup-lines resources)
                    (values nil nil))
              (run-tui
           #'run-prompt
           :command-function #'handle-command
           :template-function #'expand-template
           :bash-function #'run-user-bash
           :set-event-consumer
           (lambda (consumer)
             (setf event-consumer consumer))
           :set-notice-consumer
           (lambda (consumer)
             (setf notice-consumer consumer))
           :set-status-consumer
           (lambda (consumer)
             (setf status-consumer consumer))
           :set-warning-consumer
           (lambda (consumer)
             (setf warning-consumer consumer))
           :set-auth-url-consumer
           (lambda (consumer)
             (setf auth-url-consumer consumer))
           :set-auth-event-consumer
           (lambda (consumer)
             (setf auth-event-consumer consumer))
           :set-auth-prompt-consumer
           (lambda (consumer)
             (setf auth-prompt-consumer consumer))
           :set-model-consumer
           (lambda (consumer)
             (setf model-consumer consumer))
           :set-extension-ui-function
           (lambda (function)
             (setf
              (cadr-agent::extension-host-ui-function
               (cli-extension-manager-host
                extension-manager))
              function))
           :version-update-check-function
           (lambda ()
             (check-for-new-cadr-version-for-command
              command))
           :package-update-check-function
           (lambda ()
             (check-for-available-package-updates
              package-records
              :offline-p
              (or
               (cli-arguments-offline-p command)
               (offline-mode-p))))
           :footer-state-function
           #'current-footer-state
           :footer-cwd cwd
           :available-provider-count
           (length
            (remove-duplicates
             (mapcar
              #'cadr-ai:model-provider
              available-models)
             :test #'eq))
           :subscription-p
           (not (null (config-subscription-p)))
           :autocomplete-max-visible
           (settings-choice-value
            settings-manager
            "autocompleteMaxVisible"
            '(3 5 7 10 15 20) 5)
           :show-terminal-progress-function
           (lambda ()
             (settings-show-terminal-progress-p
              settings-manager))
           :theme-function
           #'current-theme-summary
           :preview-theme-function
           (lambda (theme-setting)
             (let* ((background
                      (theme-detection-theme
                       (detect-background-from-environment)))
                    (name
                      (or
                       (resolve-theme-setting
                        theme-setting background)
                       (string-downcase
                        (symbol-name background)))))
               (or
                (find
                 name
                 (resource-snapshot-themes resources)
                 :key
                 (lambda (theme)
                   (getf theme :name))
                 :test #'string=)
                (list :name name :path nil))))
           :theme-mode-function
           (lambda ()
             (settings-terminal-theme-mode
              settings-manager))
           :detected-theme-function
           (lambda (background)
             (let* ((configured
                      (settings-value
                       settings-manager
                       "theme" nil))
                    (name
                      (or
                       (and
                        configured
                        (resolve-theme-setting
                         configured background))
                       (string-downcase
                        (symbol-name
                         background)))))
               (or
                (find
                 name
                 (resource-snapshot-themes
                  resources)
                 :key
                 (lambda (theme)
                   (getf theme :name))
                 :test #'string=)
                (list :name name :path nil))))
           :all-themes-function
           (lambda ()
             (let ((themes
                     (copy-list
                      (resource-snapshot-themes
                       resources))))
               (dolist (name '("light" "dark"))
                 (unless
                     (find
                      name themes
                      :key
                      (lambda (theme)
                        (getf theme :name))
                      :test #'string=)
                   (push
                    (list :name name :path nil)
                    themes)))
               (nreverse themes)))
           :get-theme-function
           (lambda (name)
             (or
              (find
               name
               (resource-snapshot-themes resources)
               :key
               (lambda (theme)
                 (getf theme :name))
               :test #'string=)
              (and
               (member name '("dark" "light")
                       :test #'string=)
               (list :name name :path nil))))
           :set-theme-function
           (lambda (theme)
             (let* ((name
                      (cond
                        ((stringp theme) theme)
                        ((hash-table-p theme)
                         (cadr-ai::json-get
                          theme "name"))
                        ((listp theme)
                         (getf theme :name))))
                    (known
                      (and
                       (stringp name)
                       (or
                        (member
                         name '("dark" "light")
                         :test #'string=)
                        (find
                         name
                         (resource-snapshot-themes
                          resources)
                         :key
                         (lambda (entry)
                           (getf entry :name))
                         :test #'string=)))))
               (if known
                   (progn
                     (settings-set
                      settings-manager
                      "theme" name
                      :scope :global)
                     (list :success t))
                   (list
                    :success nil
                    :error
                    (format nil
                            "Theme not found: ~A"
                            name)))))
           :session-state-function
           #'current-session-display-state
           :busy-input-function
           (lambda (text)
             (multiple-value-bind
                   (message handled-p)
                 (cadr-agent::apply-agent-input-hooks
                  agent text :interactive
                  :streaming-behavior :steer)
               (unless handled-p
                 (cadr-agent:agent-steer
                  agent message))))
           :follow-up-input-function
           (lambda (text)
             (multiple-value-bind
                   (message handled-p)
                 (cadr-agent::apply-agent-input-hooks
                  agent text :interactive
                  :streaming-behavior :follow-up)
               (unless handled-p
                 (cadr-agent:agent-follow-up
                  agent message))))
           :dequeue-function
           (lambda ()
             (multiple-value-bind (steering follow-up)
                 (cadr-agent::clear-live-agent-queues
                  agent)
               (mapcar
                (lambda (message)
                  (cadr-ai::content-text
                   (cadr-ai:user-message-content
                    message)))
                (append steering follow-up))))
           :cycle-model-function #'cycle-model
           :model-items-function #'model-items
           :login-options-function #'current-login-options
           :model-selector-function
           #'model-selector
           :scoped-models-selector-function
           #'scoped-models-selector
           :trust-selector-function
           #'trust-selector
           :settings-selector-function
           #'settings-selector
           :extension-host
           (cli-extension-manager-host
            extension-manager)
           :fork-items-function #'fork-items
           :session-items-function #'session-items
           :all-session-items-function
           #'all-session-items
           :tree-state-function
           #'current-session-tree
           :api-key-login-function
           (lambda (provider key)
             (if
                 (model-registry-native-provider-p
                  model-registry provider)
                 (model-registry-login-native-provider
                  model-registry provider
                  (runtime-auth-interaction
                   :supplied-value key)
                  :auth-type :api-key)
                 (model-registry-login-api-key
                  model-registry provider key))
             ;; Report the selection outcome and the credential path so
             ;; the caller can render the baseline completion text.
             (values
              (refresh-auth provider :login)
              (namestring
               (if (typep
                    (model-registry-credentials model-registry)
                    'file-auth-storage)
                   (file-auth-storage-path
                    (model-registry-credentials model-registry))
                   (default-auth-path)))))
           :auth-status-function #'authentication-status
           :logout-options-function #'stored-logout-options
           :on-model-selected #'select-model
           :on-logout-selected #'select-logout-provider
           :resolve-model-reference-function
           #'resolve-model-reference
           :on-trust-selected #'select-trust
           :on-import-confirmed #'confirm-import
           :on-fork-selected #'select-fork-entry
           :on-clone-session #'clone-current-session
           :on-new-session #'start-new-session
           :on-session-selected #'select-session
           :on-tree-selected #'select-tree-entry
           :on-tree-label #'set-tree-label
           :tree-copy-function #'default-copy-text
           :current-session-path
           (and
            (cadr-agent:agent-session agent)
            (cadr-agent:session-path
             (cadr-agent:agent-session agent)))
           :session-selector-keybindings-function
           (lambda ()
             (make-session-selector-keybindings
              (settings-keybindings
               settings-manager)))
           :tree-selector-keybindings-function
           (lambda ()
             (make-tree-selector-keybindings
              (settings-keybindings
               settings-manager)))
           :abort-function
           (lambda ()
             (setf abort-requested-p t)
             (cadr-agent:agent-abort agent))
           :reset-abort-function
           (lambda ()
             (setf abort-requested-p nil))
           :model
           (cadr-ai:model-id
            (cadr-agent:agent-model agent))
           :provider
           (provider-config-name config)
           :thinking
           (model-footer-thinking-level
            (cadr-agent:agent-model agent)
            (cadr-agent::agent-thinking-level
             agent))
           :cwd
           (format-cwd-for-footer
            (namestring
             (uiop:ensure-directory-pathname
              cwd))
            (namestring
             (uiop:ensure-directory-pathname
              (user-homedir-pathname))))
           :branch
           (ignore-errors
             (let ((paths
                     (find-git-footer-paths
                      cwd)))
               (and paths
                    (resolve-git-footer-branch
                     paths))))
           :session-name
           (and
            (cadr-agent:agent-session agent)
            (cadr-agent:session-name
             (cadr-agent:agent-session
              agent)))
           :context-window
           (cadr-ai:model-context-window
            (cadr-agent:agent-model agent))
           :session
           (and
            (cadr-agent:agent-session agent)
            (cadr-agent:session-id
             (cadr-agent:agent-session agent)))
           :messages
           (copy-list
            (session-display-messages
             (cadr-agent:agent-session agent)))
           :project-trust-warning
           (project-trust-warning-text
            project-trusted-p cwd)
           :startup-compact-lines
           startup-compact
           :startup-expanded-lines
           startup-expanded
           :alt-p
           (cli-arguments-alt-p command)
           :show-hardware-cursor-p
           (or
            (settings-value
             settings-manager
             "showHardwareCursor" nil)
            (string=
             (or
              (uiop:getenv
               "CADR_HARDWARE_CURSOR")
              "")
             "1"))
           :clear-on-shrink-p
           (settings-clear-on-shrink-p
            settings-manager)
           :initial-notices
           (let ((warning
                   (anthropic-warning)))
             (and warning
                  (list warning)))
           :initial-statuses
           (let ((status
                   (session-compaction-status
                    (cadr-agent:agent-session agent))))
             (and status
                  (list status)))))
            (let ((active-session
                    (cadr-agent:agent-session agent)))
              (when active-session
                (write-session-resume-hint
                 active-session session-directory
                 :output *standard-output*
                 :terminal-p output-terminal-p
                 :default-session-directory-p
                 (same-session-file-p
                  session-directory
                  (cadr-agent:default-session-directory)))))
            0)
           (:repl
            (setf event-consumer renderer)
            (multiple-value-bind
                  (file-text file-images)
                (process-cli-file-arguments
                 (cli-arguments-file-arguments
                  command)
                 cwd)
              (multiple-value-bind
                    (initial messages)
                  (build-cli-print-prompts
                   command nil
                   :file-text file-text
                   :file-images file-images)
                (when initial
                  (run-prompt initial))
                (dolist (message messages)
                  (run-prompt message))))
            (run-repl
             #'run-prompt
             :command-function #'handle-command
             :template-function #'expand-template
             :bash-function #'run-user-bash
             :render-response nil)
            0)
           ((:text :json)
            (multiple-value-bind
                  (file-text file-images)
                (process-cli-file-arguments
                 (cli-arguments-file-arguments
                  command)
                 cwd)
              (multiple-value-bind
                 (initial messages)
                  (build-cli-print-prompts
                   command
                   (unless input-terminal-p
                     (let ((text
                             (uiop:slurp-stream-string
                              *standard-input*)))
                       (and
                        (plusp (length text))
                        text)))
                   :file-text file-text
                   :file-images file-images)
                (run-print-mode
                 agent initial messages
                 :mode mode))))
              (:rpc
               (run-rpc-mode
                agent extension-manager
                :input *standard-input*
                :output *standard-output*
                :error-output *error-output*))))))))))
