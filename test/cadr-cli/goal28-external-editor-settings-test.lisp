(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun goal28-external-editor-env (&key visual editor)
  (lambda (name)
    (cond
      ((string= name "VISUAL") visual)
      ((string= name "EDITOR") editor)
      (t nil))))

(defun goal28-edit-with-resolved-command
    (manager env &optional (windows-p nil))
  (let ((command
          (cadr-cli::settings-external-editor-command
           manager env windows-p)))
    (values
     command
     (cadr-cli::edit-in-external-editor
      "draft"
      (lambda (path)
        (write-text
         path
         (concatenate 'string command "-edited"))
        0)))))

(defun goal28-external-editor-assert-sibling-settings-readers (manager)
  (is (null
       (cadr-cli::settings-last-changelog-version manager)))
  (is (string=
       "  "
       (cadr-cli::settings-markdown-code-block-indent
        manager)))
  (is (null (cadr-cli::settings-theme-paths manager)))
  (is (null (cadr-cli::settings-skill-paths manager)))
  (is (null (cadr-cli::settings-prompt-paths manager)))
  (is (null (cadr-cli::settings-extension-paths manager))))

(test goal28-external-editor-settings-reach-existing-editor
  (let ((manager (cadr-cli::make-memory-settings-manager)))
    (multiple-value-bind (command result)
        (goal28-edit-with-resolved-command
         manager
         (goal28-external-editor-env
          :visual "vim"
          :editor "emacs"))
      (is (string= "vim" command))
      (is (string= "vim-edited" result)))
    (multiple-value-bind (command result)
        (goal28-edit-with-resolved-command
         manager
         (goal28-external-editor-env :editor "emacs"))
      (is (string= "emacs" command))
      (is (string= "emacs-edited" result)))
    (multiple-value-bind (command result)
        (goal28-edit-with-resolved-command
         manager
         (goal28-external-editor-env))
      (is (string= "nano" command))
      (is (string= "nano-edited" result)))
    (goal28-external-editor-assert-sibling-settings-readers manager))
  (with-test-directory (root)
    (let* ((global (merge-pathnames "settings.json" root))
           (_
             (write-text
              global
              "{\"externalEditor\":\"code --wait\"}"))
           (manager
             (cadr-cli::make-settings-manager
              :global-path global)))
      (declare (ignore _))
      (multiple-value-bind (command result)
          (goal28-edit-with-resolved-command
           manager
           (goal28-external-editor-env
            :visual "vim"
            :editor "emacs"))
        (is (string= "code --wait" command))
        (is (string= "code --wait-edited" result)))))
  (with-test-directory (root)
    (let* ((global (merge-pathnames "settings.json" root))
           (_
             (write-text
              global
              "{\"externalEditor\":\"   \"}"))
           (manager
             (cadr-cli::make-settings-manager
              :global-path global)))
      (declare (ignore _))
      (is
       (string=
        "nano"
        (cadr-cli::settings-external-editor-command
         manager
         (goal28-external-editor-env)
         nil)))))
  (with-test-directory (root)
    (let* ((global (merge-pathnames "settings.json" root))
           (_
             (write-text
              global
              "{\"externalEditor\":1}"))
           (manager
             (cadr-cli::make-settings-manager
              :global-path global)))
      (declare (ignore _))
      (is
       (string=
        "nano"
        (cadr-cli::settings-external-editor-command
         manager
         (goal28-external-editor-env)
         nil))))))

(test goal27-external-editor-platform-defaults
  ;; v1.4.0 settings-manager.test.ts: win32 notepad; darwin and linux nano.
  ;; Configured command, VISUAL, then EDITOR beat that default.
  ;; Env values stay untrimmed; only "" is absent.
  (let ((manager (cadr-cli::make-memory-settings-manager))
        (absent (goal28-external-editor-env)))
    (is (string=
         "notepad"
         (cadr-cli::settings-external-editor-command
          manager absent t)))
    (is (string=
         "nano"
         (cadr-cli::settings-external-editor-command
          manager absent nil)))
    (is (string=
         "vim"
         (cadr-cli::settings-external-editor-command
          manager
          (goal28-external-editor-env
           :visual "vim" :editor "emacs")
          t)))
    (is (string=
         "emacs"
         (cadr-cli::settings-external-editor-command
          manager
          (goal28-external-editor-env :editor "emacs")
          t)))
    (is (string=
         " "
         (cadr-cli::settings-external-editor-command
          manager
          (goal28-external-editor-env :visual " ")
          t)))
    (is (string=
         "emacs"
         (cadr-cli::settings-external-editor-command
          manager
          (goal28-external-editor-env :visual "" :editor "emacs")
          t))))
  (with-test-directory (root)
    (let* ((global (merge-pathnames "settings.json" root))
           (_
             (write-text
              global
              "{\"externalEditor\":\"code --wait\"}"))
           (manager
             (cadr-cli::make-settings-manager
              :global-path global)))
      (declare (ignore _))
      (is
       (string=
        "code --wait"
        (cadr-cli::settings-external-editor-command
         manager
         (goal28-external-editor-env
          :visual "vim" :editor "emacs")
         t)))))
  (with-test-directory (root)
    (dolist (payload '("{\"externalEditor\":\"   \"}"
                       "{\"externalEditor\":1}"))
      (let* ((global (merge-pathnames "settings.json" root))
             (_ (write-text global payload))
             (manager
               (cadr-cli::make-settings-manager
                :global-path global)))
        (declare (ignore _))
        (is
         (string=
          "notepad"
          (cadr-cli::settings-external-editor-command
           manager
           (goal28-external-editor-env)
           t)))))))
