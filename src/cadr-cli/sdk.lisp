(in-package #:cadr-cli)

;;; Session persistence selection

(defclass session-manager ()
  ((mode
    :initarg :mode
    :reader session-manager-mode)
   (cwd
    :initarg :cwd
    :reader session-manager-cwd)
   (directory
    :initarg :directory
    :reader session-manager-directory)
   (path
    :initarg :path
    :initform nil
    :reader session-manager-path)
   (resolved
    :initform :unresolved
    :accessor session-manager-resolved)
   (lock
    :initform
    (sb-thread:make-mutex
     :name "cadr SDK session manager")
    :reader session-manager-lock)))

(defun make-session-manager
    (mode cwd &key directory path)
  (make-instance
   'session-manager
   :mode mode
   :cwd
   (uiop:ensure-directory-pathname
    (uiop:ensure-absolute-pathname cwd))
   :directory
   (uiop:ensure-directory-pathname
    (uiop:ensure-absolute-pathname
     (or directory
         (cadr-agent:default-session-directory))))
   :path path))

(defun session-manager-in-memory
    (&optional (cwd (uiop:getcwd)))
  (make-session-manager :memory cwd))

(defun session-manager-create
    (&optional (cwd (uiop:getcwd))
      (directory
        (cadr-agent:default-session-directory)))
  (make-session-manager
   :create cwd :directory directory))

(defun session-manager-continue-recent
    (&optional (cwd (uiop:getcwd))
      (directory
        (cadr-agent:default-session-directory)))
  (make-session-manager
   :continue cwd :directory directory))

(defun session-manager-open (path)
  (let ((resolved
          (uiop:ensure-absolute-pathname path)))
    (make-session-manager
     :open
     (uiop:pathname-directory-pathname resolved)
     :directory
     (uiop:pathname-directory-pathname resolved)
     :path resolved)))

(defun session-manager-list
    (&optional cwd
      (directory
        (cadr-agent:default-session-directory)))
  (cadr-agent:list-sessions
   :directory directory :cwd cwd))

(defun session-manager-resolve (manager)
  (sb-thread:with-mutex
      ((session-manager-lock manager))
    (when (eq :unresolved
              (session-manager-resolved manager))
      (setf
       (session-manager-resolved manager)
       (ecase (session-manager-mode manager)
         (:memory nil)
         (:create
          (cadr-agent:create-session
           :directory
           (session-manager-directory manager)
           :cwd (session-manager-cwd manager)))
         (:continue
          (or
           (cadr-agent:continue-session
            :directory
            (session-manager-directory manager)
            :cwd (session-manager-cwd manager))
           (cadr-agent:create-session
            :directory
            (session-manager-directory manager)
            :cwd (session-manager-cwd manager))))
         (:open
          (cadr-agent:load-session
           (session-manager-path manager))))))
    (session-manager-resolved manager)))

;;; AgentSession facade

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
     &key (streaming-behavior :prompt))
  (assert-agent-session-live session)
  (ecase streaming-behavior
    (:prompt
     (cadr-agent:agent-prompt
      (agent-session-agent session) prompt))
    (:steer
     (cadr-agent:agent-steer
      (agent-session-agent session) prompt))
    (:follow-up
     (cadr-agent:agent-follow-up
      (agent-session-agent session) prompt))
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
  (let ((persistent
          (cadr-agent:agent-session
           (agent-session-agent session))))
    (and persistent
         (namestring
          (cadr-agent:session-path persistent)))))

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
    (explicit-tools no-tools exclude-tools)
  (let ((excluded
          (copy-list exclude-tools)))
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
                          +default-coding-tool-names+
                          :test #'string=)))))))))
       candidates))))

(defun sdk-build-agent-system-prompt
    (loader tools cwd)
  (build-system-prompt
   :custom-prompt
   (sdk-resource-loader-system-prompt loader)
   :append-system-prompt
   (let ((append
           (sdk-resource-loader-append-system-prompt
            loader)))
     (and append
          (format nil "~{~A~^~%~%~}" append)))
   :selected-tools
   (mapcar #'cadr-ai:tool-name tools)
   :tool-snippets (tool-prompt-snippets tools)
   :prompt-guidelines
   (tool-prompt-guidelines tools)
   :context-files
   (sdk-resource-loader-context-files loader)
   :skills
   (sdk-resource-loader-skills loader)
   :cwd (namestring cwd)))

(defun sdk-apply-agent-settings
    (agent settings)
  (setf
   (cadr-agent::agent-auto-compact-p agent)
   (sdk-settings-compaction-enabled-p settings)
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

(defun create-agent-session
    (&key
       (cwd (uiop:getcwd))
       (agent-directory
         (merge-pathnames
          ".cadr/" (user-homedir-pathname)))
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
                 ".cadr/settings.json"
                 resolved-cwd))))
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
               (session-manager-create resolved-cwd)))
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
            tools no-tools exclude-tools))
         (base-tools
           (append
            (make-all-coding-tools resolved-cwd)
            (copy-list custom-tools)))
         (selected-tools
           (funcall tool-filter base-tools))
         (listeners nil)
         (listener-lock
           (sb-thread:make-mutex
            :name "cadr SDK subscribers"))
         (wrapper nil))
    (declare (ignore _loader))
    (multiple-value-setq (selected-model fallback)
      (sdk-select-initial-model
       runtime settings persistent model))
    (setf
     selected-thinking
     (if selected-model
         (cadr-ai:clamp-thinking-level
          selected-model
          (or thinking-level
              (sdk-session-restored-thinking
               persistent)
              (sdk-settings-default-thinking-level
               settings)))
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
           (agent
             (cadr-agent:make-agent
              :provider
              (or provider
                  (and provider-config
                       (provider-config-provider
                        provider-config)))
              :model selected-model
              :system-prompt
              (sdk-build-agent-system-prompt
               loader selected-tools resolved-cwd)
              :tools base-tools
              :tool-filter-function tool-filter
              :extension-host extension-host
              :session persistent
              :stream-function
              (or stream-function
                  (sdk-model-runtime-stream-function
                   runtime))
              :on-event
              (lambda (event)
                (when on-event
                  (funcall on-event event))
                (let ((snapshot
                        (sb-thread:with-mutex
                            (listener-lock)
                          (copy-list listeners))))
                  (dolist (entry snapshot)
                    (funcall (car entry) event)))))))
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
             :listener-lock listener-lock))
      (setf (cadr-agent::agent-thinking-level agent)
            selected-thinking)
      ;; The closure and the object share LISTENERS through this explicit
      ;; indirection: subscribe mutates the object, so mirror it before each
      ;; dispatch without replacing the event spine.
      (setf
       (cadr-agent::agent-on-event agent)
       (lambda (event)
         (when on-event
           (funcall on-event event))
         (let ((snapshot
                 (sb-thread:with-mutex
                     (listener-lock)
                   (copy-list
                    (agent-session-listeners
                     wrapper)))))
           (dolist (entry snapshot)
             (funcall (car entry) event)))))
      (sdk-apply-agent-settings agent settings)
      (values
       wrapper
       (sdk-resource-loader-extensions loader)
       fallback))))

;;; Reusable service bootstrap

(defclass agent-session-services ()
  ((cwd
    :initarg :cwd
    :reader agent-session-services-cwd)
   (agent-directory
    :initarg :agent-directory
    :reader agent-session-services-agent-directory)
   (model-runtime
    :initarg :model-runtime
    :reader agent-session-services-model-runtime)
   (settings-manager
    :initarg :settings-manager
    :reader agent-session-services-settings-manager)
   (resource-loader
    :initarg :resource-loader
    :reader agent-session-services-resource-loader)
   (diagnostics
    :initarg :diagnostics
    :reader agent-session-services-diagnostics)))

(defun create-agent-session-services
    (&key
       (cwd (uiop:getcwd))
       (agent-directory
         (merge-pathnames
          ".cadr/" (user-homedir-pathname)))
       model-runtime settings-manager resource-loader)
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
                 ".cadr/settings.json"
                 resolved-cwd))))
         (runtime
           (or model-runtime
               (make-sdk-model-runtime
                :auth-path
                (merge-pathnames
                 "auth.json" resolved-agent)
                :models-path
                (merge-pathnames
                 "models.json" resolved-agent))))
         (loader
           (or resource-loader
               (make-sdk-resource-loader
                :cwd resolved-cwd
                :agent-directory resolved-agent
                :settings-manager settings))))
    (unless (sdk-resource-loader-snapshot loader)
      (sdk-resource-loader-reload loader))
    (make-instance
     'agent-session-services
     :cwd resolved-cwd
     :agent-directory resolved-agent
     :model-runtime runtime
     :settings-manager settings
     :resource-loader loader
     :diagnostics
     (append
      (sdk-resource-loader-diagnostics loader)
      (let ((error
              (model-registry-error
               (sdk-model-runtime-registry runtime))))
        (and error (list error)))))))

(defun create-agent-session-from-services
    (services &rest options
     &key &allow-other-keys)
  (apply
   #'create-agent-session
   :cwd (agent-session-services-cwd services)
   :agent-directory
   (agent-session-services-agent-directory
    services)
   :model-runtime
   (agent-session-services-model-runtime services)
   :settings-manager
   (agent-session-services-settings-manager services)
   :resource-loader
   (agent-session-services-resource-loader services)
   options))

;;; Replaceable session runtime protocol

(defclass function-agent-session-runtime-factory ()
  ((function
    :initarg :function
    :reader function-agent-session-runtime-factory-function)))

(defgeneric invoke-agent-session-runtime-factory
    (factory &key cwd agent-directory session-manager
                  session-start-event))

(defmethod invoke-agent-session-runtime-factory
    ((factory function-agent-session-runtime-factory)
     &key cwd agent-directory session-manager
       session-start-event)
  (funcall
   (function-agent-session-runtime-factory-function
    factory)
   :cwd cwd
   :agent-directory agent-directory
   :session-manager session-manager
   :session-start-event session-start-event))

(defclass agent-session-runtime ()
  ((factory
    :initarg :factory
    :reader agent-session-runtime-factory)
   (cwd
    :initarg :cwd
    :reader agent-session-runtime-cwd)
   (agent-directory
    :initarg :agent-directory
    :reader agent-session-runtime-agent-directory)
   (session-manager
    :initarg :session-manager
    :accessor agent-session-runtime-session-manager)
   (current-session
    :initarg :session
    :initform nil)
   (diagnostics
    :initarg :diagnostics
    :initform nil
    :accessor agent-session-runtime-diagnostics)
   (services
    :initarg :services
    :initform nil
    :accessor agent-session-runtime-services)
   (disposed-p
    :initform nil
    :accessor agent-session-runtime-disposed-p)
   (lock
    :initform
    (sb-thread:make-mutex
     :name "cadr agent session runtime")
    :reader agent-session-runtime-lock)))

(defun normalize-agent-session-runtime-factory
    (factory)
  (etypecase factory
    (function
     (make-instance
      'function-agent-session-runtime-factory
      :function factory))
    (standard-object factory)))

(defun agent-session-runtime-session (runtime)
  (sb-thread:with-mutex
      ((agent-session-runtime-lock runtime))
    (slot-value runtime 'current-session)))

(defgeneric agent-session-runtime-replace
    (runtime session-manager &key session-start-event))

(defmethod agent-session-runtime-replace
    ((runtime agent-session-runtime)
     session-manager &key session-start-event)
  (when (agent-session-runtime-disposed-p runtime)
    (error
     'cadr-agent:agent-shutdown-error
     :message "Agent session runtime has been disposed"))
  (multiple-value-bind
        (next diagnostics services)
      (invoke-agent-session-runtime-factory
       (agent-session-runtime-factory runtime)
       :cwd (agent-session-runtime-cwd runtime)
       :agent-directory
       (agent-session-runtime-agent-directory runtime)
       :session-manager session-manager
       :session-start-event session-start-event)
    (unless (typep next 'agent-session)
      (error
       'cadr-ai:configuration-error
       :message
       "Session runtime factory must return an AGENT-SESSION"))
    (let ((previous nil))
      (sb-thread:with-mutex
          ((agent-session-runtime-lock runtime))
        (when (agent-session-runtime-disposed-p runtime)
          (agent-session-dispose next)
          (error
           'cadr-agent:agent-shutdown-error
           :message
           "Agent session runtime has been disposed"))
        (setf
         previous
         (slot-value runtime 'current-session)
         (slot-value runtime 'current-session)
         next
         (agent-session-runtime-session-manager runtime)
         session-manager
         (agent-session-runtime-diagnostics runtime)
         (copy-list diagnostics)
         (agent-session-runtime-services runtime)
         services))
      (when previous
        (agent-session-dispose previous))
      next)))

(defun create-agent-session-runtime
    (factory &key
       (cwd (uiop:getcwd))
       (agent-directory
         (merge-pathnames
          ".cadr/" (user-homedir-pathname)))
       session-manager session-start-event)
  (let* ((resolved-cwd
           (uiop:ensure-directory-pathname
            (uiop:ensure-absolute-pathname cwd)))
         (manager
           (or session-manager
               (session-manager-create resolved-cwd)))
         (runtime
           (make-instance
            'agent-session-runtime
            :factory
            (normalize-agent-session-runtime-factory
             factory)
            :cwd resolved-cwd
            :agent-directory
            (uiop:ensure-directory-pathname
             (uiop:ensure-absolute-pathname
              agent-directory))
            :session-manager manager)))
    (agent-session-runtime-replace
     runtime manager
     :session-start-event session-start-event)
    runtime))

(defun agent-session-runtime-new-session
    (runtime &key session-start-event)
  (let* ((current
           (agent-session-runtime-session-manager
            runtime))
         (manager
           (if (eq :memory
                   (session-manager-mode current))
               (session-manager-in-memory
                (agent-session-runtime-cwd runtime))
               (session-manager-create
                (agent-session-runtime-cwd runtime)
                (session-manager-directory current)))))
    (agent-session-runtime-replace
     runtime manager
     :session-start-event session-start-event)))

(defun agent-session-runtime-switch-session
    (runtime path &key session-start-event)
  (agent-session-runtime-replace
   runtime (session-manager-open path)
   :session-start-event session-start-event))

(defun agent-session-runtime-dispose (runtime)
  (let ((session nil))
    (sb-thread:with-mutex
        ((agent-session-runtime-lock runtime))
      (unless (agent-session-runtime-disposed-p runtime)
        (setf
         (agent-session-runtime-disposed-p runtime) t
         session
         (slot-value runtime 'current-session)
         (slot-value runtime 'current-session) nil)))
    (when session
      (agent-session-dispose session)))
  nil)
