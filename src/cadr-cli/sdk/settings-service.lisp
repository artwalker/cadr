(in-package #:cadr-cli)

(defclass sdk-settings-manager ()
  ((backend
    :initarg :backend
    :reader sdk-settings-manager-backend)
   (overrides
    :initarg :overrides
    :initform (empty-json-object)
    :accessor sdk-settings-manager-overrides)))

(defun make-sdk-settings-manager
    (&key global-path project-path
          (project-trusted-p t))
  (make-instance
   'sdk-settings-manager
   :backend
   (make-settings-manager
    :global-path global-path
    :project-path project-path
    :project-trusted-p project-trusted-p)))

(defun make-memory-sdk-settings-manager
    (&optional initial)
  (make-instance
   'sdk-settings-manager
   :backend
   (make-memory-settings-manager initial)))

(defun sdk-settings-effective-object (manager)
  (merge-json-objects
   (settings-effective-object
    (sdk-settings-manager-backend manager))
   (sdk-settings-manager-overrides manager)))

(defun sdk-settings-value
    (manager key &optional default)
  (cadr-ai::json-get
   (sdk-settings-effective-object manager)
   key default))

(defun sdk-settings-apply-overrides
    (manager overrides)
  (unless (hash-table-p overrides)
    (error
     'cadr-ai:configuration-error
     :message "SDK settings overrides must be a JSON object"))
  (setf
   (sdk-settings-manager-overrides manager)
   (merge-json-objects
    (sdk-settings-manager-overrides manager)
    overrides))
  manager)

(defun sdk-settings-set
    (manager key value &key (scope :global))
  (settings-set
   (sdk-settings-manager-backend manager)
   key value :scope scope))

(defun sdk-settings-remove
    (manager key &key (scope :global))
  (settings-remove
   (sdk-settings-manager-backend manager)
   key :scope scope))

(defun sdk-settings-reload (manager)
  (settings-reload
   (sdk-settings-manager-backend manager))
  manager)

(defun sdk-settings-flush (manager)
  ;; The native backend writes synchronously and atomically.  Keep the SDK
  ;; durability boundary explicit even though there is no pending promise.
  manager)

(defun sdk-settings-drain-errors (manager)
  (settings-drain-errors
   (sdk-settings-manager-backend manager)))

(defun sdk-nonempty-setting-string
    (manager key)
  (let ((value (sdk-settings-value manager key)))
    (and (stringp value)
         (plusp (length value))
         value)))

(defun sdk-settings-default-provider (manager)
  (sdk-nonempty-setting-string
   manager "defaultProvider"))

(defun sdk-settings-default-model (manager)
  (sdk-nonempty-setting-string
   manager "defaultModel"))

(defun sdk-settings-default-thinking-level
    (manager)
  (let ((value
          (sdk-settings-value
           manager "defaultThinkingLevel"
           "medium")))
    (if (and (stringp value)
             (valid-thinking-level-p value))
        (intern (string-upcase value) :keyword)
        +default-thinking-level+)))

(defun sdk-settings-boolean
    (manager key default &optional nested-key)
  (let ((value (sdk-settings-value manager key :missing)))
    (when (and nested-key (hash-table-p value))
      (setf value
            (cadr-ai::json-get
             value nested-key :missing)))
    (if (eq value :missing)
        default
        (eq value t))))

(defun sdk-settings-compaction-enabled-p
    (manager)
  (sdk-settings-boolean
   manager "compaction" t "enabled"))

(defun sdk-settings-enabled-tools (manager)
  (let ((value
          (sdk-settings-value manager "tools" nil)))
    (cond
      ((vectorp value) (coerce value 'list))
      ((and (listp value)
            (every #'stringp value))
       (copy-list value))
      (t nil))))

(defun sdk-settings-retry-settings (manager)
  (let* ((retry
           (sdk-settings-value
            manager "retry" (empty-json-object)))
         (provider
           (and (hash-table-p retry)
                (cadr-ai::json-get
                 retry "provider"
                 (empty-json-object))))
         (source
           (if (hash-table-p provider)
               (merge-json-objects retry provider)
               retry)))
    (list
     :enabled-p
     (if (hash-table-p source)
         (eq t (cadr-ai::json-get source "enabled" t))
         t)
     :max-retries
     (if (hash-table-p source)
         (cadr-ai::json-get source "maxRetries" 3)
         3)
     :base-delay-ms
     (if (hash-table-p source)
         (cadr-ai::json-get source "baseDelayMs" 2000)
         2000)
     :max-retry-delay-ms
     (if (hash-table-p source)
         (cadr-ai::json-get
          source "maxRetryDelayMs" 60000)
         60000)
     :timeout-ms
     (if (hash-table-p source)
         (cadr-ai::json-get source "timeoutMs")
         nil))))

(defun sdk-settings-http-idle-timeout-ms
    (manager)
  (let ((value
          (sdk-settings-value
           manager "httpIdleTimeoutMs" 300000)))
    (unless (and (integerp value) (>= value 0))
      (error
       'cadr-ai:configuration-error
       :message
       (format nil
               "Invalid httpIdleTimeoutMs setting: ~S"
               value)))
    value))
