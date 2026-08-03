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
    ("tree" "Navigate session tree (switch branches)" nil)
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

(defparameter +reserved-extension-shortcut-keys+
  '("escape" "ctrl+c" "ctrl+d" "ctrl+z"))

(defun effective-extension-shortcuts (host)
  (remove-if
   (lambda (definition)
     (member
      (cadr-agent::extension-shortcut-definition-key
       definition)
      +reserved-extension-shortcut-keys+
      :test #'string-equal))
   (cadr-agent::extension-host-shortcuts host)))

(defun find-extension-shortcut-for-input
    (host input)
  (find-if
   (lambda (definition)
     (cadr-tui:matches-key
      input
      (cadr-agent::extension-shortcut-definition-key
       definition)))
   (effective-extension-shortcuts host)))
