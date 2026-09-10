(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun goal28-last-changelog-assert-sibling-settings-readers (manager)
  (is (string=
       "  "
       (cadr-cli::settings-markdown-code-block-indent
        manager)))
  (is (null (cadr-cli::settings-theme-paths manager)))
  (is (null (cadr-cli::settings-skill-paths manager)))
  (is (null (cadr-cli::settings-prompt-paths manager)))
  (is (null (cadr-cli::settings-extension-paths manager))))

(test goal28-last-changelog-version-reaches-startup
  (let ((current-version (cadr-ai::cadr-version))
        (stored-older "0.0.1")
        (entry-newer "0.2.0")
        (entry-older "0.1.0"))
    (with-test-directory (root)
      (let* ((global (merge-pathnames "settings.json" root))
             (changelog
               (merge-pathnames "CHANGELOG.md" root))
             (_
               (write-text
                changelog
                (format
                 nil
                 "# Changelog~%~%## [~A] - 2026-01-02~%~%Newer body.~%~%## [~A] - 2026-01-01~%~%Older body.~%"
                 entry-newer
                 entry-older)))
             (manager
               (cadr-cli::make-settings-manager
                :global-path global))
             (absent-lines
               (cadr-cli::apply-changelog-to-startup-compact-lines
                '("banner")
                manager
                nil
                :changelog-path changelog
                :current-version current-version))
             (absent-state
               (cadr-cli::make-tui-state
                :startup-compact-lines absent-lines)))
        (declare (ignore _))
        (is (null
             (cadr-cli::changelog-for-display
              (cadr-cli::make-settings-manager
               :global-path
               (merge-pathnames "absent-check.json" root))
              nil
              :changelog-path changelog
              :current-version current-version)))
        (is (string=
             current-version
             (cadr-cli::settings-last-changelog-version
              manager)))
        (is (equal '("banner") absent-lines))
        (is (equal
             '("banner")
             (cadr-cli::tui-state-startup-compact-lines
              absent-state)))
        (goal28-last-changelog-assert-sibling-settings-readers manager)))
    (with-test-directory (root)
      (let* ((global (merge-pathnames "settings.json" root))
             (changelog
               (merge-pathnames "CHANGELOG.md" root))
             (_
               (progn
                 (write-text
                  global
                  (format
                   nil
                   "{\"lastChangelogVersion\":~S}"
                   stored-older))
                 (write-text
                  changelog
                  (format
                   nil
                   "# Changelog~%~%## [~A] - 2026-01-02~%~%Newer body.~%~%## [~A] - 2026-01-01~%~%Older body.~%"
                   entry-newer
                   entry-older))))
             (manager
               (cadr-cli::make-settings-manager
                :global-path global))
             (newer-lines
               (cadr-cli::apply-changelog-to-startup-compact-lines
                nil
                manager
                nil
                :changelog-path changelog
                :current-version current-version))
             (newer-state
               (cadr-cli::make-tui-state
                :startup-compact-lines newer-lines))
             (text
               (first
                (cadr-cli::tui-state-startup-compact-lines
                 newer-state))))
        (declare (ignore _))
        (is (= 1 (length newer-lines)))
        (is (search (format nil "## [~A]" entry-newer) text))
        (is (search "Newer body." text))
        (is (search (format nil "## [~A]" entry-older) text))
        (is (search "Older body." text))
        (is (string=
             current-version
             (cadr-cli::settings-last-changelog-version
              manager)))))
    (with-test-directory (root)
      (let* ((global (merge-pathnames "settings.json" root))
             (changelog
               (merge-pathnames "CHANGELOG.md" root))
             (_
               (progn
                 (write-text
                  global
                  (format
                   nil
                   "{\"lastChangelogVersion\":~S}"
                   stored-older))
                 (write-text
                  changelog
                  (format
                   nil
                   "# Changelog~%~%## [~A] - 2026-01-02~%~%Newer body.~%"
                   entry-newer))))
             (manager
               (cadr-cli::make-settings-manager
                :global-path global))
             (resumed-lines
               (cadr-cli::apply-changelog-to-startup-compact-lines
                '("banner")
                manager
                '(#(:already-has-messages))
                :changelog-path changelog
                :current-version current-version)))
        (declare (ignore _))
        (is (null
             (cadr-cli::changelog-for-display
              manager
              '(#(:already-has-messages))
              :changelog-path changelog
              :current-version current-version)))
        (is (equal '("banner") resumed-lines))
        (is (string=
             stored-older
             (cadr-cli::settings-last-changelog-version
              manager)))))))
