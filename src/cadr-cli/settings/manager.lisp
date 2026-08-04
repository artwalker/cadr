(in-package #:cadr-cli)

(defstruct (settings-manager
            (:constructor %make-settings-manager))
  global-path
  project-path
  (project-trusted-p t :type boolean)
  (global (empty-json-object) :type hash-table)
  (project (empty-json-object) :type hash-table)
  (global-overrides (empty-json-object)
                    :type hash-table)
  (project-overrides (empty-json-object)
                     :type hash-table)
  (errors nil :type list)
  (lock
    (sb-thread:make-mutex
     :name "cadr settings manager")))

(defun make-settings-manager
    (&key global-path project-path
          (project-trusted-p t))
  (let ((manager
          (%make-settings-manager
           :global-path global-path
           :project-path project-path
           :project-trusted-p project-trusted-p)))
    (settings-reload manager)
    manager))

(defun make-memory-settings-manager
    (&optional initial)
  (let ((manager
          (%make-settings-manager
           :global
           (if initial
               (copy-json-object initial)
               (empty-json-object)))))
    manager))

(defun settings-record-error
    (manager scope condition)
  (push (list :scope scope
              :condition condition)
        (settings-manager-errors manager)))

(defun reload-settings-scope
    (manager scope path)
  (when path
    (multiple-value-bind (object error)
        (read-settings-object path)
      (if error
          (settings-record-error
           manager scope error)
          (ecase scope
            (:global
             (setf
              (settings-manager-global manager)
              (merge-json-objects
               object
               (settings-manager-global-overrides
                manager))))
            (:project
             (setf
              (settings-manager-project manager)
              (merge-json-objects
               object
               (settings-manager-project-overrides
                manager)))))))))

(defun settings-reload (manager)
  (sb-thread:with-mutex
      ((settings-manager-lock manager))
    (reload-settings-scope
     manager :global
     (settings-manager-global-path manager))
    (if (settings-manager-project-trusted-p manager)
        (reload-settings-scope
         manager :project
         (settings-manager-project-path manager))
        (setf (settings-manager-project manager)
              (empty-json-object))))
  manager)

(defun settings-effective-object (manager)
  (merge-json-objects
   (settings-manager-global manager)
   (if (settings-manager-project-trusted-p manager)
       (settings-manager-project manager)
       (empty-json-object))))

(defun settings-value (manager key &optional default)
  (cadr-ai::json-get
   (settings-effective-object manager)
   key default))

(defun settings-set
    (manager key value &key (scope :global))
  (when (and (eq scope :project)
             (not
              (settings-manager-project-trusted-p
               manager)))
    (error "Project settings are not trusted"))
  (sb-thread:with-mutex
      ((settings-manager-lock manager))
    (let* ((path
             (ecase scope
               (:global
                (settings-manager-global-path manager))
               (:project
                (settings-manager-project-path manager))))
           (current
             (ecase scope
               (:global
                (settings-manager-global manager))
               (:project
                (settings-manager-project manager))))
           (base current))
      (when path
        (multiple-value-bind (disk error)
            (read-settings-object path)
          (when error
            (settings-record-error
             manager scope error)
            (error error))
          (setf base disk)))
      (let ((next (copy-json-object base)))
        (cadr-ai::json-put next key value)
        (when path
          (write-settings-object path next))
        (ecase scope
          (:global
           (setf
            (settings-manager-global manager)
            next)
           (cadr-ai::json-put
            (settings-manager-global-overrides manager)
            key value))
          (:project
           (setf
            (settings-manager-project manager)
            next)
           (cadr-ai::json-put
            (settings-manager-project-overrides manager)
            key value))))))
  value)

(defun settings-nested-value
    (manager key nested-key &optional default)
  (let ((object
          (settings-value
           manager key (empty-json-object))))
    (if (hash-table-p object)
        (cadr-ai::json-get
         object nested-key default)
        default)))

(defun settings-set-nested
    (manager key nested-key value
     &key (scope :global))
  (when (and (eq scope :project)
             (not
              (settings-manager-project-trusted-p
               manager)))
    (error "Project settings are not trusted"))
  (sb-thread:with-mutex
      ((settings-manager-lock manager))
    (let* ((path
             (ecase scope
               (:global
                (settings-manager-global-path manager))
               (:project
                (settings-manager-project-path manager))))
           (current
             (ecase scope
               (:global
                (settings-manager-global manager))
               (:project
                (settings-manager-project manager))))
           (base current))
      (when path
        (multiple-value-bind (disk error)
            (read-settings-object path)
          (when error
            (settings-record-error
             manager scope error)
            (error error))
          (setf base disk)))
      (let* ((next
               (copy-json-object base))
             (old-nested
               (cadr-ai::json-get
                next key (empty-json-object)))
             (next-nested
               (if (hash-table-p old-nested)
                   (copy-json-object old-nested)
                   (empty-json-object))))
        (cadr-ai::json-put
         next-nested nested-key value)
        (cadr-ai::json-put next key next-nested)
        (when path
          (write-settings-object path next))
        (ecase scope
          (:global
           (setf
            (settings-manager-global manager)
            next)
           (cadr-ai::json-put
            (settings-manager-global-overrides manager)
            key next-nested))
          (:project
           (setf
            (settings-manager-project manager)
            next)
           (cadr-ai::json-put
            (settings-manager-project-overrides manager)
            key next-nested))))))
  value)

(defun settings-remove
    (manager key &key (scope :global))
  (when (and (eq scope :project)
             (not
              (settings-manager-project-trusted-p
               manager)))
    (error "Project settings are not trusted"))
  (sb-thread:with-mutex
      ((settings-manager-lock manager))
    (let* ((path
             (ecase scope
               (:global
                (settings-manager-global-path manager))
               (:project
                (settings-manager-project-path manager))))
           (current
             (ecase scope
               (:global
                (settings-manager-global manager))
               (:project
                (settings-manager-project manager))))
           (base current))
      (when path
        (multiple-value-bind (disk error)
            (read-settings-object path)
          (when error
            (settings-record-error
             manager scope error)
            (error error))
          (setf base disk)))
      (let ((next (copy-json-object base)))
        (remhash key next)
        (when path
          (write-settings-object path next))
        (ecase scope
          (:global
           (setf
            (settings-manager-global manager)
            next)
           (remhash
            key
            (settings-manager-global-overrides
             manager)))
          (:project
           (setf
            (settings-manager-project manager)
            next)
           (remhash
            key
            (settings-manager-project-overrides
             manager)))))))
  nil)

(defun settings-drain-errors (manager)
  (prog1
      (nreverse (settings-manager-errors manager))
    (setf (settings-manager-errors manager) nil)))

(defun settings-http-idle-timeout-ms (manager)
  (let ((value
          (settings-value
           manager "httpIdleTimeoutMs"
           300000)))
    (unless (and (integerp value)
                 (>= value 0))
      (error "Invalid httpIdleTimeoutMs setting: ~S"
             value))
    value))

(defun settings-output-padding (manager)
  (let ((value
          (settings-value manager "outputPad" 1)))
    (if (member value '(0 1)) value 1)))

(defun settings-block-images-p (manager)
  (eq t
      (cadr-ai::json-get
       (settings-value
        manager "images"
        (empty-json-object))
       "blockImages")))

(defun settings-enabled-models (manager)
  (let ((value
          (settings-value
           manager "enabledModels" :missing)))
    (cond
      ((or (eq value :missing)
           (null value))
       :all)
      ((vectorp value)
       (coerce value 'list))
      ((and
        (listp value)
        (every #'stringp value))
       (copy-list value))
      (t
       (error
        "Invalid enabledModels setting: ~S"
        value)))))

(defun settings-set-enabled-models
    (manager enabled-ids)
  (if (eq enabled-ids :all)
      (settings-remove
       manager "enabledModels"
       :scope :global)
      (settings-set
       manager "enabledModels"
       (coerce enabled-ids 'vector)
       :scope :global))
  enabled-ids)

(defun settings-default-provider (manager)
  (let ((value
          (settings-value
           manager "defaultProvider")))
    (and (stringp value)
         (plusp (length value))
         value)))

(defun settings-default-model (manager)
  (let ((value
          (settings-value
           manager "defaultModel")))
    (and (stringp value)
         (plusp (length value))
         value)))

(defun settings-set-default-model-and-provider
    (manager provider model-id)
  (settings-set
   manager "defaultProvider" provider
   :scope :global)
  (settings-set
   manager "defaultModel" model-id
   :scope :global)
  model-id)

(defparameter *legacy-keybinding-names*
  '(("cursorUp" . "tui.editor.cursorUp")
    ("cursorDown" . "tui.editor.cursorDown")
    ("selectConfirm" . "tui.select.confirm")
    ("expandTools" . "app.tools.expand")
    ("interrupt" . "app.interrupt")))

(defun migrate-keybindings (object)
  (let ((result (copy-json-object object)))
    (dolist (mapping *legacy-keybinding-names*)
      (let ((old (car mapping))
            (new (cdr mapping)))
        (multiple-value-bind (old-value old-p)
            (gethash old result)
          (when old-p
            (multiple-value-bind (new-value new-p)
                (gethash new result)
              (declare (ignore new-value))
              (unless new-p
                (setf (gethash new result)
                      old-value)))
            (remhash old result)))))
    result))

(defun settings-keybindings (manager)
  (let ((object
          (migrate-keybindings
           (settings-value
            manager "keybindings"
            (empty-json-object))))
        (bindings nil))
    (maphash
     (lambda (name value)
       (let ((keys
               (cond
                 ((stringp value)
                  (list value))
                 ((vectorp value)
                  (coerce value 'list))
                 ((listp value)
                  (copy-list value))
                 (t nil))))
         (when
             (and (or (stringp value)
                      (vectorp value)
                      (listp value))
                  (every #'stringp keys))
           (push
            (cons name keys)
            bindings))))
     object)
    (nreverse bindings)))
