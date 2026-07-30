(in-package #:cadr-cli)

(defparameter *config-value-cache*
  (make-hash-table :test #'equal))
(defparameter *config-value-cache-lock*
  (sb-thread:make-mutex
   :name "cadr config value cache"))

(defun clear-config-value-cache ()
  (sb-thread:with-mutex
      (*config-value-cache-lock*)
    (clrhash *config-value-cache*))
  nil)

(defun config-environment-value (name environment)
  (or (cdr (assoc name environment :test #'string=))
      (uiop:getenv name)))

(defun config-name-start-p (character)
  (or (alpha-char-p character)
      (char= character #\_)))

(defun config-name-character-p (character)
  (or (config-name-start-p character)
      (digit-char-p character)))

(defun resolve-config-template (config environment)
  (with-output-to-string (output)
    (loop with index = 0
          while (< index (length config))
          for character = (char config index)
          do
          (if (char/= character #\$)
              (progn
                (write-char character output)
                (incf index))
              (let ((next-index (1+ index)))
                (cond
                  ((= next-index (length config))
                   (write-char #\$ output)
                   (incf index))
                  ((member (char config next-index)
                           '(#\$ #\!))
                   (write-char
                    (char config next-index)
                    output)
                   (incf index 2))
                  ((char= (char config next-index)
                          #\{)
                   (let ((end
                           (position #\} config
                                     :start (+ index 2))))
                     (if (null end)
                         (progn
                           (write-char #\$ output)
                           (incf index))
                         (let* ((name
                                  (subseq config
                                          (+ index 2) end))
                                (valid-p
                                  (and
                                   (plusp (length name))
                                   (config-name-start-p
                                    (char name 0))
                                   (every
                                    #'config-name-character-p
                                    name))))
                           (if valid-p
                               (let ((value
                                       (config-environment-value
                                        name environment)))
                                 (unless value
                                   (return-from
                                       resolve-config-template
                                     nil))
                                 (write-string value output))
                               (write-string
                                (subseq config index
                                        (1+ end))
                                output))
                           (setf index (1+ end))))))
                  ((config-name-start-p
                    (char config next-index))
                   (let ((end next-index))
                     (loop while
                           (and
                            (< end (length config))
                            (config-name-character-p
                             (char config end)))
                           do (incf end))
                     (let ((value
                             (config-environment-value
                              (subseq config next-index end)
                              environment)))
                       (unless value
                         (return-from
                             resolve-config-template nil))
                       (write-string value output))
                     (setf index end)))
                  (t
                   (write-char #\$ output)
                   (incf index))))))))

(defun default-config-command (command)
  (multiple-value-bind (output error-output status)
      (uiop:run-program
       (list "/bin/sh" "-c" command)
       :output :string
       :error-output :string
       :ignore-error-status t)
    (declare (ignore error-output))
    (values output status)))

(defun execute-config-command (config command-function)
  (handler-case
      (multiple-value-bind (output status)
          (funcall command-function (subseq config 1))
        (let ((trimmed
                (and output
                     (string-trim
                      '(#\Space #\Tab
                        #\Newline #\Return)
                      output))))
          (and (or (null status)
                   (zerop status))
               trimmed
               (plusp (length trimmed))
               trimmed)))
    (condition () nil)))

(defun resolve-config-value
    (config &key environment
                   (command-function
                     #'default-config-command)
                   uncached-p)
  (if (uiop:string-prefix-p "!" config)
      (if uncached-p
          (execute-config-command
           config command-function)
          (sb-thread:with-mutex
              (*config-value-cache-lock*)
            (multiple-value-bind (value found-p)
                (gethash config
                         *config-value-cache*)
              (if found-p
                  value
                  (setf
                   (gethash config
                            *config-value-cache*)
                   (execute-config-command
                    config command-function))))))
      (resolve-config-template config environment)))

(defun copy-json-object (object)
  (cadr-ai::copy-json-value object))

(defun empty-json-object ()
  (cadr-ai::json-object))

(defun merge-json-objects (base overrides)
  (let ((result
          (if (hash-table-p base)
              (copy-json-object base)
              (empty-json-object))))
    (when (hash-table-p overrides)
      (maphash
       (lambda (key value)
         (let ((current
                 (cadr-ai::json-get result key)))
           (cadr-ai::json-put
            result key
            (if (and (hash-table-p current)
                     (hash-table-p value))
                (merge-json-objects
                 current value)
                (copy-json-object value)))))
       overrides))
    result))

(defun read-settings-object (path)
  (if (not (probe-file path))
      (values (empty-json-object) nil)
      (handler-case
          (let ((object
                  (cadr-ai::parse-json
                   (uiop:read-file-string
                    path :external-format :utf-8))))
            (unless (hash-table-p object)
              (error "settings file must contain an object"))
            (values object nil))
        (condition (condition)
          (values nil condition)))))

(defun write-settings-object (path object)
  (atomic-write-utf8
   path
   (format nil "~A~%"
           (cadr-ai::stringify-json object))))

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
             (and keys
                  (every #'stringp keys))
           (push
            (cons name keys)
            bindings))))
     object)
    (nreverse bindings)))

(defstruct (project-trust-store
            (:constructor make-project-trust-store
                (path)))
  path
  (lock
    (sb-thread:make-mutex
     :name "cadr project trust")))

(defun trust-object (store)
  (multiple-value-bind (object error)
      (read-settings-object
       (project-trust-store-path store))
    (if error
        (empty-json-object)
        object)))

(defun canonical-directory-name (path)
  (namestring
   (or
    (ignore-errors
      (truename
       (uiop:ensure-directory-pathname path)))
    (uiop:ensure-absolute-pathname
     (uiop:ensure-directory-pathname path)))))

(defun parent-directory (directory)
  (let* ((path
           (uiop:ensure-directory-pathname directory))
         (parent
           (uiop:pathname-parent-directory-pathname
            path)))
    (unless (equal (namestring path)
                   (namestring parent))
      parent)))

(defun project-trust-entry
    (store directory)
  (sb-thread:with-mutex
      ((project-trust-store-lock store))
    (let ((object (trust-object store)))
      (loop for current =
            (uiop:ensure-directory-pathname directory)
              then (parent-directory current)
            while current
            for key = (canonical-directory-name current)
            do
            (multiple-value-bind (value found-p)
                (gethash key object)
              (when found-p
                (return
                  (list
                   :path key
                   :decision value))))
            finally (return nil)))))

(defun project-trust-get (store directory)
  (let ((entry
          (project-trust-entry
           store directory)))
    (if entry
        (values (getf entry :decision) t)
        (values nil nil))))

(defun project-trust-set-many
    (store updates)
  (sb-thread:with-mutex
      ((project-trust-store-lock store))
    (let ((object (trust-object store)))
      (dolist (update updates)
        (let ((key
                (canonical-directory-name
                 (getf update :path)))
              (decision
                (getf update :decision)))
          (if (eq decision :remove)
              (remhash key object)
              (setf
               (gethash key object)
               (not (null decision))))))
      (write-settings-object
       (project-trust-store-path store)
       object)))
  updates)

(defun project-trust-set
    (store directory decision
     &key store-negative-p)
  (sb-thread:with-mutex
      ((project-trust-store-lock store))
    (let* ((object (trust-object store))
           (key (canonical-directory-name directory)))
      (if (and (null decision)
               (not store-negative-p))
          (remhash key object)
          (setf (gethash key object)
                (not (null decision))))
      (write-settings-object
       (project-trust-store-path store)
       object)))
  decision)

(defun trust-requiring-project-resources-p (directory)
  (let ((root
          (uiop:ensure-directory-pathname directory)))
    (some
     #'probe-file
     (list
      (merge-pathnames ".cadr/settings.json" root)
      (merge-pathnames ".cadr/extensions/" root)
      (merge-pathnames ".cadr/skills/" root)
      (merge-pathnames ".agents/skills/" root)))))

(defun resolve-project-trusted
    (store directory
     &key override override-supplied-p
       extension-host
       (default :ask)
       has-ui-p
       prompt-function)
  (when override-supplied-p
    (return-from resolve-project-trusted
      (not (null override))))
  (unless
      (trust-requiring-project-resources-p
       directory)
    (return-from resolve-project-trusted t))
  (when extension-host
    (let ((result
            (cadr-agent::run-extension-lifecycle-hooks
             extension-host :project-trust
             :payload
             (list
              :cwd
              (canonical-directory-name
               directory)))))
      (when result
        (let ((decision
                (getf result :trusted)))
          (when (member decision '(:yes :no))
            (let ((trusted-p (eq decision :yes)))
              (when (getf result :remember-p)
                (project-trust-set
                 store directory trusted-p
                 :store-negative-p
                 (not trusted-p)))
              (return-from resolve-project-trusted
                trusted-p)))))))
  (multiple-value-bind (stored found-p)
      (project-trust-get store directory)
    (when found-p
      (return-from resolve-project-trusted stored)))
  (case default
    (:always
     (return-from resolve-project-trusted t))
    (:never
     (return-from resolve-project-trusted nil))
    (:ask nil)
    (otherwise
     (error "Invalid default project trust: ~S"
            default)))
  (if (and has-ui-p prompt-function)
      (let ((decision
              (funcall prompt-function directory)))
        (when (member decision '(t nil))
          (project-trust-set
           store directory decision
           :store-negative-p
           (not decision)))
        (not (null decision)))
      nil))
