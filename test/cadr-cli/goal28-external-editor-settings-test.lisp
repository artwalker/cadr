(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun goal28-external-editor-env (&key visual editor)
  (lambda (name)
    (cond
      ((string= name "VISUAL") visual)
      ((string= name "EDITOR") editor)
      (t nil))))

(defun goal28-edit-with-resolved-command (manager env)
  (let ((command
          (cadr-cli::settings-external-editor-command
           manager env)))
    (values
     command
     (cadr-cli::edit-in-external-editor
      "draft"
      (lambda (path)
        (write-text
         path
         (concatenate 'string command "-edited"))
        0)))))

(defun goal28-assert-sibling-settings-readers (manager)
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
    (goal28-assert-sibling-settings-readers manager))
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
         (goal28-external-editor-env))))))
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
         (goal28-external-editor-env)))))))
