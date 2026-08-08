(in-package #:cadr-cli)

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
         (cadr-core:coding-agent-directory))
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
         (cadr-core:coding-agent-directory))
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
