(in-package #:cadr-cli)

(defun make-import-confirmation-list
    (line path)
  (make-framed-select-state
   "Import session"
   '("Yes" "No")
   (list
    (list :confirmed-p t
          :line line
          :path path)
    (list :confirmed-p nil
          :line line
          :path path))
   :message
   (format nil "Replace current session with ~A?" path)))

(defparameter +tui-autocomplete-command-specifications+
  '(("settings" "Open settings menu" nil)
    ("model" "Select model (opens selector UI)"
     "<provider/model>")
    ("tree" "Navigate session tree (switch branches)" nil)
    ("thinking" "Set thinking level" "<level>")
    ("scoped-models"
     "Enable/disable models for Ctrl+P cycling" nil)
    ("export"
     "Export session (HTML default, or specify path: .html/.jsonl)"
     nil)
    ("import"
     "Import and resume a session from a JSONL file" nil)
    ("share" "Share session as a secret GitHub gist" nil)
    ("copy" "Copy last agent message to clipboard" nil)
    ("name" "Set session display name" nil)
    ("session" "Show session info and stats" nil)
    ("changelog" "Show changelog entries" nil)
    ("hotkeys" "Show all keyboard shortcuts" nil)
    ("fork"
     "Create a new fork from a previous user message" nil)
    ("clone"
     "Duplicate the current session at the current position" nil)
    ("trust"
     "Save project trust decision for future sessions" nil)
    ("login" "Configure provider authentication" "<provider>")
    ("logout" "Remove provider authentication" nil)
    ("new" "Start a new session" nil)
    ("compact" "Manually compact the session context" nil)
    ("resume" "Resume a different session" nil)
    ("reload"
     "Reload keybindings, extensions, skills, prompts, themes, and context files"
     nil)
    ("quit" "Quit cadr" nil)))

(defun prefix-autocomplete-description
    (description source scope)
  (flet ((scope-prefix (scope)
           (cond
             ((or (eq scope :user)
                  (equal scope "user"))
              "u")
             ((or (eq scope :project)
                  (equal scope "project"))
              "p")
             (t "t"))))
    (when (or (null source) (null scope))
      (return-from prefix-autocomplete-description
        description))
    (let* ((trimmed
             (string-trim
              '(#\Space #\Tab #\Newline #\Return)
              source))
           (prefix (scope-prefix scope))
           (parsed (parse-package-source trimmed))
           (tag
             (cond
               ((or (string= trimmed "auto")
                    (string= trimmed "local")
                    (string= trimmed "cli"))
                prefix)
               ((and (>= (length trimmed) 4)
                     (string= "npm:" trimmed :end2 4))
                (format nil "~A:~A" prefix trimmed))
               ((eq :git (package-source-type parsed))
                (format nil "~A:git:~A/~A~A"
                        prefix
                        (package-source-host parsed)
                        (package-source-path parsed)
                        (if (package-source-ref parsed)
                            (format nil "@~A"
                                    (package-source-ref
                                     parsed))
                            "")))
               (t prefix))))
      (if (and description
               (plusp (length description)))
          (format nil "[~A] ~A" tag description)
          (format nil "[~A]" tag)))))

(defun resource-slash-commands
    (skills prompts skill-commands-p
     &optional extension-commands source-info-function)
  (flet ((builtin-name-p (name)
           (member name
                   +tui-autocomplete-command-specifications+
                   :key #'first
                   :test #'string=))
         (prefixed (description path)
           (if (or (null source-info-function)
                   (null path))
               description
               (multiple-value-bind (source scope)
                   (funcall source-info-function path)
                 (prefix-autocomplete-description
                  description source scope)))))
    (nconc
     (loop for template in prompts
           collect
           (cadr-tui:make-autocomplete-command
            :name
            (cadr-agent:prompt-template-name template)
            :description
            (prefixed
             (cadr-agent:prompt-template-description
              template)
             (cadr-agent:prompt-template-file-path
              template))))
     (loop for command in extension-commands
           for name =
             (cadr-agent::extension-command-definition-name
              command)
           unless (builtin-name-p name)
             collect
             (cadr-tui:make-autocomplete-command
              :name
              (cadr-agent::extension-command-lookup-name
               command)
              :description
              (prefixed
               (cadr-agent::extension-command-definition-description
                command)
               (let ((bundle
                       (cadr-agent::extension-command-definition-bundle
                        command)))
                 (and bundle
                      (cadr-agent::extension-bundle-path
                       bundle))))
              :argument-hint
              (cadr-agent::extension-command-definition-argument-hint
               command)))
     (when skill-commands-p
       (loop for skill in skills
             collect
             (cadr-tui:make-autocomplete-command
              :name
              (format nil "skill:~A"
                      (cadr-agent:skill-name skill))
              :description
              (prefixed
               (cadr-agent:skill-description skill)
               (cadr-agent:skill-file-path skill))))))))

(defun tui-builtin-slash-command-p (command)
  (member
   (cadr-tui::autocomplete-command-name command)
   +tui-autocomplete-command-specifications+
   :key #'first
   :test #'string=))

(defun replace-extra-autocomplete-commands
    (provider extra)
  (let ((commands
          (append
           (remove-if-not
            #'tui-builtin-slash-command-p
            (cadr-tui::autocomplete-provider-commands
             provider))
           extra)))
    (setf
     (cadr-tui::autocomplete-provider-commands
      provider)
     commands
     (cadr-tui::autocomplete-provider-command-items
      provider)
     (mapcar
      #'cadr-tui::command-autocomplete-item
      commands))
    provider))

(defun find-tui-fd-program ()
  (loop for directory
        in (uiop:split-string
            (or (uiop:getenv "PATH") "")
            :separator '(#\:))
        when (plusp (length directory))
          do
          (dolist (name '("fd" "fdfind"))
            (let ((candidate
                    (merge-pathnames
                     name
                     (uiop:ensure-directory-pathname
                      directory))))
              (when (probe-file candidate)
                (return-from find-tui-fd-program
                  candidate))))))

(defun tui-model-autocomplete-items
    (model-items-function prefix)
  (let* ((models
           (loop for item in (and model-items-function
                                  (funcall model-items-function))
                 for model = (cadr-tui:select-item-value item)
                 when (typep model 'cadr-ai:model)
                   collect model))
         (filtered
           (cadr-tui::fuzzy-filter
            models prefix
            (lambda (model)
              (format nil "~(~A~)/~A ~A"
                      (cadr-ai:model-provider model)
                      (cadr-ai:model-id model)
                      (cadr-ai::model-name model))))))
    (loop for model in filtered
          for provider =
            (format nil "~(~A~)"
                    (cadr-ai:model-provider model))
          for id = (cadr-ai:model-id model)
          collect
          (cadr-tui:make-autocomplete-item
           :value (format nil "~A/~A" provider id)
           :label id
           :description provider))))

(defun tui-login-autocomplete-records (options)
  (let ((records nil))
    (dolist (option options)
      (let* ((id
               (format nil "~(~A~)"
                       (oauth-selector-option-id option)))
             (record
               (find id records
                     :key (lambda (entry) (getf entry :id))
                     :test #'string=)))
        (if record
            (pushnew
             (oauth-selector-option-auth-type option)
             (getf record :auth-types))
            (push
             (list
              :id id
              :name (oauth-selector-option-name option)
              :auth-types
              (list
               (oauth-selector-option-auth-type option)))
             records))))
    (sort records #'string<
          :key (lambda (entry) (getf entry :name)))))

(defun tui-auth-type-label (auth-type)
  (if (eq auth-type :oauth)
      "subscription"
      "API key"))

(defun tui-login-autocomplete-items
    (login-options-function prefix)
  (let* ((records
           (tui-login-autocomplete-records
            (and login-options-function
                 (funcall login-options-function))))
         (filtered
           (cadr-tui::fuzzy-filter
            records prefix
            (lambda (record)
              (format nil "~A ~A ~{~A~^ ~}"
                      (getf record :id)
                      (getf record :name)
                      (mapcar
                       #'tui-auth-type-label
                       (getf record :auth-types)))))))
    (loop for record in filtered
          for id = (getf record :id)
          for name = (getf record :name)
          for types =
            (sort
             (copy-list (getf record :auth-types))
             #'<
             :key
             (lambda (auth-type)
               (if (eq auth-type :oauth) 0 1)))
          for auth-label =
            (format nil "~{~A~^/~}"
                    (mapcar #'tui-auth-type-label types))
          collect
          (cadr-tui:make-autocomplete-item
           :value id
           :label id
           :description
           (if (string= name id)
               auth-label
               (format nil "~A · ~A" name auth-label))))))

(defun make-tui-autocomplete-provider
    (&key
       (base-path (uiop:getcwd))
       model-items-function
       (login-options-function
         (lambda ()
           (login-provider-options
            (cadr-ai:list-provider-definitions)))))
  (cadr-tui:make-autocomplete-provider
   :commands
   (loop for (name description argument-hint)
         in +tui-autocomplete-command-specifications+
         collect
         (cadr-tui:make-autocomplete-command
          :name name
          :description description
          :argument-hint argument-hint
          :argument-completer
          (cond
            ((string= name "model")
             (lambda (prefix)
               (tui-model-autocomplete-items
                model-items-function prefix)))
            ((string= name "login")
             (lambda (prefix)
               (tui-login-autocomplete-items
                login-options-function prefix))))))
   :base-path base-path
   :fd-path
   (find-tui-fd-program)))

(defparameter +reserved-extension-shortcut-actions+
  ;; Baseline core/extensions/runner.ts:71-89
  ;; RESERVED_KEYBINDINGS_FOR_EXTENSION_CONFLICTS.
  '("app.interrupt" "app.clear" "app.exit" "app.suspend"
    "app.thinking.cycle" "app.model.cycleForward"
    "app.model.cycleBackward" "app.model.select" "app.tools.expand"
    "app.thinking.toggle" "app.editor.external" "app.message.copy"
    "app.message.followUp" "tui.input.submit" "tui.select.confirm"
    "tui.select.cancel" "tui.input.copy" "tui.editor.deleteToLineEnd"))

(defun extension-shortcut-path (definition)
  (let ((bundle
          (cadr-agent::extension-shortcut-definition-bundle
           definition)))
    (if bundle
        (cadr-agent::extension-bundle-path bundle)
        "<inline>")))

(defun builtin-shortcut-key-map (keybindings)
  "Baseline buildBuiltinKeybindings: map each lowercase key to
(action . restrict-override-p); a reserved action wins key collisions
regardless of declaration order."
  (let ((map (make-hash-table :test #'equal)))
    (dolist (entry (cadr-tui::keybindings-manager-resolved keybindings))
      (let ((action (car entry))
            (restrict-p
              (member (car entry)
                      +reserved-extension-shortcut-actions+
                      :test #'string=)))
        (dolist (key (cdr entry))
          (let* ((normalized (string-downcase key))
                 (existing (gethash normalized map)))
            (unless (and existing (cdr existing) (not restrict-p))
              (setf (gethash normalized map)
                    (cons action restrict-p)))))))
    map))

(defun resolve-extension-shortcuts (host keybindings)
  "Baseline ExtensionRunner.getShortcuts (runner.ts:493-540): fold
extension shortcuts over the resolved keybindings.  Reserved built-in
keys skip the extension shortcut; other built-in collisions and
extension-extension collisions resolve to the later registration, each
with a diagnostic.  Returns (values shortcuts diagnostics)."
  (let ((builtins (builtin-shortcut-key-map keybindings))
        (resolved nil)
        (diagnostics nil))
    (dolist (definition (cadr-agent::extension-host-shortcuts host))
      (let* ((key
               (cadr-agent::extension-shortcut-definition-key
                definition))
             (normalized (string-downcase key))
             (path (extension-shortcut-path definition))
             (builtin (gethash normalized builtins)))
        (cond
          ((and builtin (cdr builtin))
           (push
            (list :type :warning
                  :path path
                  :message
                  (format
                   nil
                   "Extension shortcut '~A' from ~A conflicts with built-in shortcut. Skipping."
                   key path))
            diagnostics))
          (t
           (when builtin
             (push
              (list :type :warning
                    :path path
                    :message
                    (format
                     nil
                     "Extension shortcut conflict: '~A' is built-in shortcut for ~A and ~A. Using ~A."
                     key (car builtin) path path))
              diagnostics))
           (let ((existing
                   (find normalized resolved
                         :key
                         (lambda (entry)
                           (string-downcase
                            (cadr-agent::extension-shortcut-definition-key
                             entry))))))
             (when existing
               (push
                (list :type :warning
                      :path path
                      :message
                      (format
                       nil
                       "Extension shortcut conflict: '~A' registered by both ~A and ~A. Using ~A."
                       key
                       (extension-shortcut-path existing)
                       path path))
                diagnostics)
               (setf resolved (delete existing resolved)))
             (push definition resolved))))))
    (values (nreverse resolved) (nreverse diagnostics))))

(defun effective-extension-shortcuts (host)
  (resolve-extension-shortcuts host (cadr-tui:get-keybindings)))

(defun refresh-extension-shortcut-diagnostics (manager)
  "Recompute the baseline shortcut-conflict diagnostics for the
manager's current extension host and fold them into its startup
issues, replacing any previous shortcut entries.  Interactive mode
only — baseline print/rpc never calls getShortcuts (runner.ts:493 is
reached from interactive-mode.ts:1825/5885), so non-interactive
startup must not report these."
  (multiple-value-bind (shortcuts diagnostics)
      (resolve-extension-shortcuts
       (cli-extension-manager-host manager)
       (cadr-tui:get-keybindings))
    (declare (ignore shortcuts))
    (setf
     (cli-extension-manager-startup-issues manager)
     (nconc
      (remove :shortcut
              (cli-extension-manager-startup-issues manager)
              :key (lambda (issue) (getf issue :source)))
      (mapcar
       (lambda (issue)
         (list :type :warning
               :source :shortcut
               :path (getf issue :path)
               :message (getf issue :message)))
       diagnostics)))
    diagnostics))

(defun find-extension-shortcut-for-input
    (host input)
  (find-if
   (lambda (definition)
     (cadr-tui:matches-key
      input
      (cadr-agent::extension-shortcut-definition-key
       definition)))
   (effective-extension-shortcuts host)))
