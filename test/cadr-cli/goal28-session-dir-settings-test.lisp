(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(test goal28-session-dir-settings-reach-existing-resolver
  (let* ((manager (cadr-cli::make-memory-settings-manager))
         (expected-default
           (namestring
            (cadr-agent:default-session-directory)))
         (resolved-absent
           (cadr-cli::resolve-session-directory
            :settings-directory
            (cadr-cli::settings-session-dir manager)
            :cwd (uiop:getcwd)))
         (created-absent
           (cadr-cli::session-manager-create
            (uiop:getcwd) resolved-absent)))
    (is (null (cadr-cli::settings-session-dir manager)))
    (is (string= expected-default
                 (namestring resolved-absent)))
    (is (string=
         expected-default
         (namestring
          (cadr-cli::session-manager-directory
           created-absent))))
    (is (eq t (cadr-cli::settings-boolean-value
               manager "compaction" t "enabled")))
    (is (= 20000
           (cadr-cli::settings-compaction-keep-recent-tokens
            manager)))
    (is (= 16384
           (cadr-cli::settings-compaction-reserve-tokens
            manager)))
    (is (= 16384
           (cadr-cli::settings-branch-summary-reserve-tokens
            manager)))
    (is (eq nil
            (cadr-cli::settings-branch-summary-skip-prompt-p
             manager)))
    (is (null (cadr-cli::settings-shell-path manager)))
    (is (null
         (cadr-cli::settings-shell-command-prefix manager))))
  (with-test-directory (root)
    (let* ((global (merge-pathnames "settings.json" root))
           (expected-custom
             "/tmp/cadr-g28-session-dir-custom/")
           (_
             (write-text
              global
              "{\"sessionDir\":\"/tmp/cadr-g28-session-dir-custom\"}"))
           (manager
             (cadr-cli::make-settings-manager
              :global-path global))
           (resolved
             (cadr-cli::resolve-session-directory
              :settings-directory
              (cadr-cli::settings-session-dir manager)
              :cwd root))
           (created
             (cadr-cli::session-manager-create
              root resolved)))
      (declare (ignore _))
      (is (string=
           "/tmp/cadr-g28-session-dir-custom"
           (cadr-cli::settings-session-dir manager)))
      (is (string= expected-custom (namestring resolved)))
      (is (string=
           expected-custom
           (namestring
            (cadr-cli::session-manager-directory
             created))))))
  (let* ((settings
           (cadr-cli::make-memory-sdk-settings-manager
            (args
             "sessionDir"
             "/tmp/cadr-g28-session-dir-custom")))
         (expected-custom
           "/tmp/cadr-g28-session-dir-custom/")
         (resolved
           (cadr-cli::resolve-session-directory
            :settings-directory
            (cadr-cli:sdk-settings-session-dir settings)
            :cwd (uiop:getcwd)))
         (created
           (cadr-cli::session-manager-create
            (uiop:getcwd) resolved)))
    (is (string=
         "/tmp/cadr-g28-session-dir-custom"
         (cadr-cli:sdk-settings-session-dir settings)))
    (is (string= expected-custom (namestring resolved)))
    (is (string=
         expected-custom
         (namestring
          (cadr-cli::session-manager-directory
           created))))
    (is (eq t
            (cadr-cli:sdk-settings-compaction-enabled-p
             settings)))
    (is (= 20000
           (cadr-cli:sdk-settings-compaction-keep-recent-tokens
            settings)))
    (is (= 16384
           (cadr-cli:sdk-settings-branch-summary-reserve-tokens
            settings)))
    (is (null
         (cadr-cli:sdk-settings-shell-path settings)))))
