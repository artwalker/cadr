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
  ;; Runtime-only overrides (e.g. --use-theme): merged last, never
  ;; written to disk.
  (runtime-overrides (empty-json-object)
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
   (merge-json-objects
    (settings-manager-global manager)
    (if (settings-manager-project-trusted-p manager)
        (settings-manager-project manager)
        (empty-json-object)))
   (settings-manager-runtime-overrides manager)))

(defun settings-override-runtime-value (manager key value)
  ;; Set a runtime-only override: visible through the effective object,
  ;; never persisted.
  (sb-thread:with-mutex
      ((settings-manager-lock manager))
    (cadr-ai::json-put
     (settings-manager-runtime-overrides manager)
     key value))
  value)

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

(defun settings-auto-resize-images-p (manager)
  (let ((images
          (settings-value
           manager "images"
           (empty-json-object))))
    (if (hash-table-p images)
        (eq t
            (cadr-ai::json-get
             images "autoResize" t))
        t)))

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

(defun add-persisted-default-to-non-empty-scope (manager model)
  ;; pi@13cbf77df agent-session.ts _addPersistedDefaultToNonEmptyScope:
  ;; a Ctrl+S default joins a non-empty enabledModels list so the
  ;; saved default stays selectable after restart.
  (let ((enabled (settings-enabled-models manager)))
    (when (and (listp enabled) (plusp (length enabled)))
      (let ((reference
              (model-setting-key
               (cadr-ai:model-provider model)
               (cadr-ai:model-id model))))
        (unless (find reference enabled :test #'string-equal)
          (settings-set-enabled-models
           manager
           (append enabled (list reference)))))))
  model)

(defun model-setting-key (provider model-id)
  (format nil "~(~A~)/~A"
          (if (symbolp provider)
              (symbol-name provider)
              provider)
          model-id))

(defun settings-default-thinking-level (manager)
  (let ((value
          (settings-value manager "defaultThinkingLevel")))
    (when (and (stringp value)
               (valid-thinking-level-p value))
      (intern (string-upcase value) :keyword))))

(defun settings-set-default-thinking-level (manager level)
  (settings-set
   manager "defaultThinkingLevel"
   (string-downcase (symbol-name level))
   :scope :global)
  level)

(defun settings-model-thinking-level
    (manager provider model-id)
  (let ((value
          (settings-nested-value
           manager "modelThinkingLevels"
           (model-setting-key provider model-id))))
    (when (and (stringp value)
               (valid-thinking-level-p value))
      (intern (string-upcase value) :keyword))))

(defun settings-all-model-thinking-levels (manager)
  (let ((object
          (settings-value
           manager "modelThinkingLevels"
           (empty-json-object)))
        (result nil))
    (when (hash-table-p object)
      (maphash
       (lambda (key value)
         (when (and (stringp value)
                    (valid-thinking-level-p value))
           (push
            (cons key
                  (intern (string-upcase value) :keyword))
            result)))
       object))
    (nreverse result)))

(defun settings-set-model-thinking-level
    (manager provider model-id level)
  (settings-set-nested
   manager "modelThinkingLevels"
   (model-setting-key provider model-id)
   (string-downcase (symbol-name level))
   :scope :global)
  level)

(defun settings-remove-model-thinking-level
    (manager provider model-id)
  (sb-thread:with-mutex
      ((settings-manager-lock manager))
    (let* ((path
             (settings-manager-global-path manager))
           (current
             (settings-manager-global manager))
           (base current))
      (when path
        (multiple-value-bind (disk error)
            (read-settings-object path)
          (when error
            (settings-record-error manager :global error)
            (error error))
          (setf base disk)))
      (let* ((next (copy-json-object base))
             (nested
               (cadr-ai::json-get
                next "modelThinkingLevels"
                (empty-json-object)))
             (next-nested
               (if (hash-table-p nested)
                   (copy-json-object nested)
                   (empty-json-object))))
        (remhash
         (model-setting-key provider model-id)
         next-nested)
        (if (zerop (hash-table-count next-nested))
            (remhash "modelThinkingLevels" next)
            (cadr-ai::json-put
             next "modelThinkingLevels" next-nested))
        (when path
          (write-settings-object path next))
        (setf (settings-manager-global manager) next)
        (let ((overrides
                (cadr-ai::json-get
                 (settings-manager-global-overrides manager)
                 "modelThinkingLevels"
                 (empty-json-object))))
          (when (hash-table-p overrides)
            (remhash
             (model-setting-key provider model-id)
             overrides))))))
  nil)

(defparameter *legacy-keybinding-names*
  ;; Baseline core/keybindings.ts:209-268 KEYBINDING_NAME_MIGRATIONS,
  ;; in baseline declaration order.
  '(("cursorUp" . "tui.editor.cursorUp")
    ("cursorDown" . "tui.editor.cursorDown")
    ("cursorLeft" . "tui.editor.cursorLeft")
    ("cursorRight" . "tui.editor.cursorRight")
    ("cursorWordLeft" . "tui.editor.cursorWordLeft")
    ("cursorWordRight" . "tui.editor.cursorWordRight")
    ("cursorLineStart" . "tui.editor.cursorLineStart")
    ("cursorLineEnd" . "tui.editor.cursorLineEnd")
    ("jumpForward" . "tui.editor.jumpForward")
    ("jumpBackward" . "tui.editor.jumpBackward")
    ("pageUp" . "tui.editor.pageUp")
    ("pageDown" . "tui.editor.pageDown")
    ("deleteCharBackward" . "tui.editor.deleteCharBackward")
    ("deleteCharForward" . "tui.editor.deleteCharForward")
    ("deleteWordBackward" . "tui.editor.deleteWordBackward")
    ("deleteWordForward" . "tui.editor.deleteWordForward")
    ("deleteToLineStart" . "tui.editor.deleteToLineStart")
    ("deleteToLineEnd" . "tui.editor.deleteToLineEnd")
    ("yank" . "tui.editor.yank")
    ("yankPop" . "tui.editor.yankPop")
    ("undo" . "tui.editor.undo")
    ("newLine" . "tui.input.newLine")
    ("submit" . "tui.input.submit")
    ("tab" . "tui.input.tab")
    ("copy" . "tui.input.copy")
    ("selectUp" . "tui.select.up")
    ("selectDown" . "tui.select.down")
    ("selectPageUp" . "tui.select.pageUp")
    ("selectPageDown" . "tui.select.pageDown")
    ("selectConfirm" . "tui.select.confirm")
    ("selectCancel" . "tui.select.cancel")
    ("interrupt" . "app.interrupt")
    ("clear" . "app.clear")
    ("exit" . "app.exit")
    ("suspend" . "app.suspend")
    ("cycleThinkingLevel" . "app.thinking.cycle")
    ("cycleModelForward" . "app.model.cycleForward")
    ("cycleModelBackward" . "app.model.cycleBackward")
    ("selectModel" . "app.model.select")
    ("expandTools" . "app.tools.expand")
    ("toggleThinking" . "app.thinking.toggle")
    ("toggleSessionNamedFilter" . "app.session.toggleNamedFilter")
    ("externalEditor" . "app.editor.external")
    ("followUp" . "app.message.followUp")
    ("dequeue" . "app.message.dequeue")
    ("pasteImage" . "app.clipboard.pasteImage")
    ("newSession" . "app.session.new")
    ("tree" . "app.session.tree")
    ("fork" . "app.session.fork")
    ("resume" . "app.session.resume")
    ("treeFoldOrUp" . "app.tree.foldOrUp")
    ("treeUnfoldOrDown" . "app.tree.unfoldOrDown")
    ("treeEditLabel" . "app.tree.editLabel")
    ("treeToggleLabelTimestamp" . "app.tree.toggleLabelTimestamp")
    ("toggleSessionPath" . "app.session.togglePath")
    ("toggleSessionSort" . "app.session.toggleSort")
    ("renameSession" . "app.session.rename")
    ("deleteSession" . "app.session.delete")
    ("deleteSessionNoninvasive" . "app.session.deleteNoninvasive")))

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

(defun keybinding-object-to-bindings (object)
  (let ((bindings nil))
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

(defun settings-keybindings (manager)
  (keybinding-object-to-bindings
   (migrate-keybindings
    (settings-value
     manager "keybindings"
     (empty-json-object)))))

(defun keybindings-file-bindings (agent-directory)
  "Baseline core/keybindings.ts:330-338,360-366 — load
<agentDir>/keybindings.json, migrating legacy names.  Returns NIL when
the file is absent, unreadable, malformed, or not a JSON object
(baseline loadRawConfig treats all of those as no bindings)."
  (let ((path
          (merge-pathnames
           "keybindings.json"
           (uiop:ensure-directory-pathname agent-directory))))
    (when (probe-file path)
      (let ((parsed
              (handler-case
                  (cadr-ai::parse-json
                   (uiop:read-file-string path))
                (condition () nil))))
        (and (hash-table-p parsed)
             (keybinding-object-to-bindings
              (migrate-keybindings parsed)))))))

(defun resolve-user-keybindings
    (manager agent-directory)
  "Baseline core/keybindings.ts:349-353 — the user keybinding source is
<agentDir>/keybindings.json.  Per the goal 18 adjudication the file
coexists with the settings.json keybindings key and takes precedence
when present."
  (or
   (keybindings-file-bindings agent-directory)
   (settings-keybindings manager)))
