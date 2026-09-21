(in-package #:cadr-cli)

(defclass agent-session ()
  ((agent
    :initarg :agent
    :reader agent-session-agent)
   (session-manager
    :initarg :session-manager
    :reader agent-session-session-manager)
   (settings-manager
    :initarg :settings-manager
    :reader agent-session-settings-manager)
   (resource-loader
    :initarg :resource-loader
    :reader agent-session-resource-loader)
   (model-runtime
    :initarg :model-runtime
    :reader agent-session-model-runtime)
   (cwd
    :initarg :cwd
    :reader agent-session-cwd)
   (listeners
    :initarg :listeners
    :accessor agent-session-listeners)
   (listener-lock
    :initarg :listener-lock
    :reader agent-session-listener-lock)
   (disposed-p
    :initform nil
    :accessor agent-session-disposed-p)))

(defun assert-agent-session-live (session)
  (when (agent-session-disposed-p session)
    (error
     'cadr-agent:agent-shutdown-error
     :message "Agent session has been disposed"))
  session)

(defun agent-session-prompt
    (session prompt
     &key (streaming-behavior :prompt)
          (source :interactive))
  (assert-agent-session-live session)
  (ecase streaming-behavior
    (:prompt
     (cadr-agent:agent-prompt
      (agent-session-agent session) prompt
      :source source))
    ((:steer :follow-up)
     ;; Reuse apply-input-or-queue so SDK steer/follow-up run
     ;; :input hooks like interactive TUI and RPC (pi #8718).
     (apply-input-or-queue
      (agent-session-agent session)
      prompt source streaming-behavior))
    (:next-turn
     (cadr-agent:agent-next-turn
      (agent-session-agent session) prompt))))

(defun agent-session-subscribe
    (session function)
  (assert-agent-session-live session)
  (unless (functionp function)
    (error
     'cadr-ai:configuration-error
     :message "Agent session subscriber must be a function"))
  (let ((token (cons function nil)))
    (sb-thread:with-mutex
        ((agent-session-listener-lock session))
      (setf
       (agent-session-listeners session)
       (append
        (agent-session-listeners session)
        (list token))))
    (let ((active-p t)
          (lock
            (sb-thread:make-mutex
             :name "cadr SDK unsubscribe")))
      (lambda ()
        (sb-thread:with-mutex (lock)
          (when active-p
            (setf active-p nil)
            (sb-thread:with-mutex
                ((agent-session-listener-lock
                  session))
              (setf
               (agent-session-listeners session)
               (delete
                token
                (agent-session-listeners session)
                :test #'eq)))))
        nil))))

(defun agent-session-messages (session)
  (copy-list
   (cadr-agent:agent-messages
    (agent-session-agent session))))

(defun agent-session-id (session)
  (let ((persistent
          (cadr-agent:agent-session
           (agent-session-agent session))))
    (and persistent
         (cadr-agent:session-id persistent))))

(defun agent-session-file (session)
  (let* ((persistent
           (cadr-agent:agent-session
            (agent-session-agent session)))
         (path
           (and persistent
                (cadr-agent:session-path persistent))))
    (and path (namestring path))))

(defun agent-session-bind-extensions
    (session &optional context)
  (declare (ignore context))
  (assert-agent-session-live session)
  (let ((loader
          (agent-session-resource-loader session)))
    (when loader
      (let ((host
              (sdk-resource-loader-extension-host
               loader)))
        (when host
          (cadr-agent::attach-extension-host
           host (agent-session-agent session)))))
    (and loader
         (sdk-resource-loader-extensions loader))))

(defun agent-session-dispose (session)
  (unless (agent-session-disposed-p session)
    (setf (agent-session-disposed-p session) t)
    (let* ((agent (agent-session-agent session))
           (host
             (cadr-agent::agent-extension-host agent)))
      (when host
        (cadr-agent::run-extension-lifecycle-hooks
         host :session-shutdown
         :payload '(:reason :quit)))
      (cadr-agent:agent-shutdown agent))
    (sb-thread:with-mutex
        ((agent-session-listener-lock session))
      (setf (agent-session-listeners session) nil)))
  nil)

(defun sdk-session-restored-selection
    (persistent model-runtime)
  (when persistent
    (let ((entry
            (find :model-change
                  (cadr-agent:session-entries
                   persistent)
                  :key
                  #'cadr-agent:session-entry-type
                  :from-end t)))
      (when entry
        (sdk-model-runtime-model
         model-runtime
         (cadr-agent:session-entry-provider entry)
         (cadr-agent:session-entry-model-id
          entry))))))

(defun sdk-session-restored-thinking
    (persistent)
  (when persistent
    (let ((entry
            (find :thinking-level-change
                  (cadr-agent:session-entries
                   persistent)
                  :key
                  #'cadr-agent:session-entry-type
                  :from-end t)))
      (when entry
        (let ((value
                (cadr-agent:session-entry-thinking-level
                 entry)))
          (and value
               (intern
                (string-upcase value)
                :keyword)))))))

(defun sdk-select-initial-model
    (runtime settings persistent explicit-model)
  (if explicit-model
      (values explicit-model nil)
      (let* ((restored
               (sdk-session-restored-selection
                persistent runtime))
             (saved-provider
               (sdk-settings-default-provider settings))
             (saved-model-id
               (sdk-settings-default-model settings))
             (saved
               (and saved-provider saved-model-id
                    (sdk-model-runtime-model
                     runtime saved-provider
                     saved-model-id)))
             (available
               (sdk-model-runtime-available-models
                runtime))
             (model
               (or restored saved (first available))))
        (values
         model
         (cond
           ((and persistent
                 (not (null
                       (cadr-agent:session-messages
                        persistent)))
                 (null restored))
            (if model
                (format nil
                        "Could not restore the saved model. Using ~A/~A"
                        (provider-key
                         (cadr-ai:model-provider model))
                        (cadr-ai:model-id model))
                "Could not restore the saved model"))
           ((null model)
            (format-no-models-available-message))
           (t nil))))))

(defun sdk-tool-filter
    (explicit-tools no-tools exclude-tools &optional default-tool-names)
  (let ((excluded
          (copy-list exclude-tools))
        (default-names
          (or default-tool-names +default-coding-tool-names+)))
    (lambda (candidates)
      (remove-if
       (lambda (tool)
         (let* ((name (cadr-ai:tool-name tool))
                (builtin-p
                  (member
                   name +builtin-coding-tool-names+
                   :test #'string=)))
           (or
            (member name excluded :test #'string=)
            (if explicit-tools
                (not
                 (member name explicit-tools
                         :test #'string=))
                (case no-tools
                  (:all t)
                  (:builtin builtin-p)
                  ((nil)
                   (and builtin-p
                        (not
                         (member
                          name
                          default-names
                          :test #'string=)))))))))
       candidates))))

(defun sdk-build-agent-system-prompt
    (loader tools cwd)
  (let ((options
          (list
           :custom-prompt
           (sdk-resource-loader-system-prompt loader)
           :selected-tools
           (mapcar #'cadr-ai:tool-name tools)
           :tool-snippets (tool-prompt-snippets tools)
           :prompt-guidelines
           (tool-prompt-guidelines tools)
           :append-system-prompt
           (let ((append
                   (sdk-resource-loader-append-system-prompt
                    loader)))
             (and append
                  (format nil "~{~A~^~%~%~}" append)))
           :cwd (namestring cwd)
           :context-files
           (sdk-resource-loader-context-files loader)
           :skills
           (sdk-resource-loader-skills loader))))
    (values
     (apply #'build-system-prompt options)
     (copy-tree options))))

(defun sdk-apply-agent-settings
    (agent settings)
  (setf
   (cadr-agent::agent-auto-compact-p agent)
   (sdk-settings-compaction-enabled-p settings)
   (cadr-agent::agent-compaction-keep-recent-tokens
    agent)
   (sdk-settings-compaction-keep-recent-tokens
    settings)
   (cadr-agent::agent-compaction-reserve-tokens
    agent)
   (sdk-settings-compaction-reserve-tokens
    settings)
   (cadr-agent:agent-steering-mode agent)
   (if (string=
        "all"
        (sdk-settings-value
         settings "steeringMode"
         "one-at-a-time"))
       :all :one-at-a-time)
   (cadr-agent:agent-follow-up-mode agent)
   (if (string=
        "all"
        (sdk-settings-value
         settings "followUpMode"
         "one-at-a-time"))
       :all :one-at-a-time))
  agent)

(defun sdk-agent-session-dispatch
    (event on-event lock source listeners-fn)
  (when on-event
    (funcall on-event event))
  (let ((snapshot
          (sb-thread:with-mutex (lock)
            (copy-list
             (if listeners-fn
                 (funcall listeners-fn source)
                 source)))))
    (dolist (entry snapshot)
      (funcall (car entry) event))))

(defun create-agent-session
    (&key
       (cwd (uiop:getcwd))
       (agent-directory
         (cadr-core:coding-agent-directory))
       model-runtime model provider thinking-level
       scoped-models
       no-tools tools exclude-tools custom-tools
       resource-loader session-manager
       settings-manager session-start-event
       stream-function on-event)
  (declare (ignore scoped-models session-start-event))
  (let* ((resolved-cwd
           (uiop:ensure-directory-pathname
            (uiop:ensure-absolute-pathname cwd)))
         (resolved-agent
           (uiop:ensure-directory-pathname
            (uiop:ensure-absolute-pathname
             agent-directory)))
         (settings
           (or settings-manager
               (make-sdk-settings-manager
                :global-path
                (merge-pathnames
                 "settings.json" resolved-agent)
                :project-path
                (merge-pathnames
                 "settings.json"
                 (cadr-core:project-config-directory resolved-cwd)))))
         (runtime
           (or model-runtime
               (make-sdk-model-runtime
                :auth-path
                (merge-pathnames
                 "auth.json" resolved-agent)
                :models-path
                (merge-pathnames
                 "models.json" resolved-agent))))
         (manager
           (or session-manager
               (session-manager-create
                resolved-cwd
                (resolve-session-directory
                 :settings-directory
                 (sdk-settings-session-dir settings)
                 :cwd resolved-cwd))))
         (persistent
           (session-manager-resolve manager))
         (loader
           (or resource-loader
               (make-sdk-resource-loader
                :cwd resolved-cwd
                :agent-directory resolved-agent
                :settings-manager settings)))
         (_loader
           (unless
               (sdk-resource-loader-snapshot loader)
             (sdk-resource-loader-reload loader)))
         (fallback nil)
         (selected-model nil)
         (selected-thinking nil)
         (provider-config nil)
         (tool-filter
           (sdk-tool-filter
            tools no-tools exclude-tools
            (and settings
                 (parse-default-tools-setting
                  (sdk-settings-value settings "defaultTools")))))
         (base-tools
           (append
            (make-all-coding-tools
             resolved-cwd
             :command-prefix
             (and settings
                  (sdk-settings-shell-command-prefix settings))
             :shell-path
             (and settings
                  (sdk-settings-shell-path settings)))
            (copy-list custom-tools)))
         (selected-tools
           (funcall tool-filter base-tools))
         (listeners nil)
         (listener-lock
           (sb-thread:make-mutex
            :name "cadr SDK subscribers"))
         (wrapper nil)
         (wrapper-cell (cons nil nil)))
    (declare (ignore _loader))
    (multiple-value-setq (selected-model fallback)
      (sdk-select-initial-model
       runtime settings persistent model))
    (setf
     selected-thinking
     (if selected-model
         (cadr-ai:clamp-thinking-level
          selected-model
          (sdk-settings-effective-thinking-level
           settings selected-model
           thinking-level
           (sdk-session-restored-thinking
            persistent)))
         :off))
    (when (and selected-model
               (null stream-function))
      (setf
       provider-config
       (sdk-model-runtime-provider-config
        runtime selected-model
        :allow-missing-auth-p t)))
    (let* ((extension-host
             (sdk-resource-loader-extension-host loader))
           (system-prompt-values
             (multiple-value-list
              (sdk-build-agent-system-prompt
               loader selected-tools resolved-cwd)))
           (retry-settings
             (sdk-settings-retry-settings settings))
           (agent
             (cadr-agent:make-agent
              :provider
              (or provider
                  (and provider-config
                       (provider-config-provider
                        provider-config)))
              :model selected-model
              :system-prompt
              (first system-prompt-values)
              :system-prompt-options
              (second system-prompt-values)
              :tools base-tools
              :tool-filter-function tool-filter
              :extension-host extension-host
              :session persistent
              :stream-function
              (stream-function-with-provider-retry
               (stream-function-with-http-proxy
                (stream-function-with-http-idle-timeout
                 (stream-function-with-websocket-connect-timeout
                  (stream-function-with-thinking-budgets
                  (or stream-function
                      (sdk-model-runtime-stream-function
                       runtime))
                  (lambda ()
                    (sdk-settings-thinking-budgets settings)))
                 (lambda ()
                   (sdk-settings-websocket-connect-timeout-ms
                    settings)))
                 (lambda ()
                   (sdk-settings-http-idle-timeout-ms
                    settings)))
                (lambda ()
                  (sdk-settings-http-proxy settings)))
               (lambda ()
                 (sdk-settings-retry-settings settings)))
              :auto-retry-p
              (getf retry-settings :enabled-p)
              :auto-retry-max-attempts
              (getf retry-settings :max-retries)
              :auto-retry-base-delay
              (/ (getf retry-settings :base-delay-ms) 1000)
              :on-event
              (lambda (event)
                (sdk-agent-session-dispatch
                 event on-event listener-lock
                 (or (car wrapper-cell) listeners)
                 (and (car wrapper-cell)
                      #'agent-session-listeners))))))
      (when extension-host
        (setf
         (cadr-agent::extension-host-reload-function extension-host)
         (lambda ()
           (sdk-resource-loader-reload loader)
           (multiple-value-bind (prompt options)
               (sdk-build-agent-system-prompt
                loader
                (cadr-agent::registry-tools
                 (cadr-agent::agent-tool-registry agent))
                resolved-cwd)
             (cadr-agent::replace-agent-system-prompt
              agent prompt options))
           (cadr-agent::replace-agent-prompt-catalogs
            agent
            (sdk-resource-loader-skills loader)
            (sdk-resource-loader-prompts loader))
           (sdk-resource-loader-extensions loader))))
      (setf wrapper
            (make-instance
             'agent-session
             :agent agent
             :session-manager manager
             :settings-manager settings
             :resource-loader loader
             :model-runtime runtime
             :cwd resolved-cwd
             :listeners listeners
             :listener-lock listener-lock)
            (car wrapper-cell) wrapper)
      (setf (cadr-agent::agent-thinking-level agent)
            selected-thinking)
      (setf
       (cadr-agent::agent-on-event agent)
       (lambda (event)
         (sdk-agent-session-dispatch
          event on-event listener-lock wrapper
          #'agent-session-listeners)))
      (cadr-agent::replace-agent-prompt-catalogs
       agent
       (sdk-resource-loader-skills loader)
       (sdk-resource-loader-prompts loader))
      (sdk-apply-agent-settings agent settings)
      (values
       wrapper
       (sdk-resource-loader-extensions loader)
       fallback))))

;;; Reusable service bootstrap
