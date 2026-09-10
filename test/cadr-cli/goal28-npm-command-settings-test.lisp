(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun goal28-npm-command-assert-sibling-settings-readers (manager)
  (is (string=
       "  "
       (cadr-cli::settings-markdown-code-block-indent
        manager)))
  (is (null (cadr-cli::settings-last-changelog-version
             manager)))
  (is (string=
       "nano"
       (cadr-cli::settings-external-editor-command
        manager
        (lambda (name)
          (declare (ignore name))
          nil))))
  (is (null (cadr-cli::settings-theme-paths manager)))
  (is (null (cadr-cli::settings-skill-paths manager)))
  (is (null (cadr-cli::settings-prompt-paths manager)))
  (is (null (cadr-cli::settings-extension-paths manager))))

(test goal28-npm-command-settings-reach-existing-argv
  (with-test-directory (root)
    (let* ((install-root
             (merge-pathnames "packages/" root))
           (prefix
             (namestring
              (uiop:ensure-directory-pathname
               install-root)))
           (manager
             (cadr-cli::make-memory-settings-manager)))
      (is (null (cadr-cli::settings-npm-command manager)))
      (is (equal
           (list
            "npm" "install" "--prefix" prefix
            "--no-save" "--legacy-peer-deps"
            "@scope/pkg")
           (cadr-cli::package-npm-install-argv
            '("@scope/pkg") install-root
            :npm-command
            (cadr-cli::settings-npm-command manager))))
      (goal28-npm-command-assert-sibling-settings-readers manager)))
  (with-test-directory (root)
    (let* ((global (merge-pathnames "settings.json" root))
           (install-root
             (merge-pathnames "packages/" root))
           (prefix
             (namestring
              (uiop:ensure-directory-pathname
               install-root)))
           (_
             (write-text
              global
              "{\"npmCommand\":[\"mise\",\"exec\",\"node@20\",\"--\",\"npm\"]}"))
           (manager
             (cadr-cli::make-settings-manager
              :global-path global)))
      (declare (ignore _))
      (is (equal
           '("mise" "exec" "node@20" "--" "npm")
           (cadr-cli::settings-npm-command manager)))
      (is (equal
           (list
            "mise" "exec" "node@20" "--" "npm"
            "install" "--prefix" prefix
            "--no-save" "--legacy-peer-deps"
            "@scope/pkg")
           (cadr-cli::package-npm-install-argv
            '("@scope/pkg") install-root
            :npm-command
            (cadr-cli::settings-npm-command manager)))))))
