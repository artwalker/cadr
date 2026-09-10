(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(test goal28-shell-path-and-command-prefix-reach-existing-call-sites
  (let* ((manager (cadr-cli::make-memory-settings-manager))
         (discovered
           (cadr-cli::shell-config-shell
            (cadr-cli::get-shell-config)))
         (from-absent-settings
           (cadr-cli::get-shell-config
            (cadr-cli::settings-shell-path manager))))
    (is (null (cadr-cli::settings-shell-path manager)))
    (is (null
         (cadr-cli::settings-shell-command-prefix manager)))
    (is (string=
         discovered
         (cadr-cli::shell-config-shell from-absent-settings)))
    (is (string=
         "printf hi"
         (cadr-cli::bash-command-with-prefix
          (cadr-cli::settings-shell-command-prefix manager)
          "printf hi")))
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
             manager))))
  (with-test-directory (root)
    (let* ((global (merge-pathnames "settings.json" root))
           (expected-shell "/bin/bash")
           (expected-prefix "shopt -s expand_aliases")
           (expected-command
             (format nil "shopt -s expand_aliases~%printf hi"))
           (_
             (write-text
              global
              "{\"shellPath\":\"/bin/bash\",\"shellCommandPrefix\":\"shopt -s expand_aliases\"}"))
           (manager
             (cadr-cli::make-settings-manager
              :global-path global)))
      (declare (ignore _))
      (is (string= expected-shell
                   (cadr-cli::settings-shell-path manager)))
      (is (string=
           expected-shell
           (cadr-cli::shell-config-shell
            (cadr-cli::get-shell-config
             (cadr-cli::settings-shell-path manager)))))
      (is (string= expected-prefix
                   (cadr-cli::settings-shell-command-prefix
                    manager)))
      (is (string=
           expected-command
           (cadr-cli::bash-command-with-prefix
            (cadr-cli::settings-shell-command-prefix manager)
            "printf hi")))))
  (with-test-directory (root)
    (let* ((global (merge-pathnames "settings.json" root))
           (missing
             (namestring
              (merge-pathnames "no-such-shell" root)))
           (_
             (write-text
              global
              (format
               nil
               "{\"shellPath\":~S}"
               missing)))
           (manager
             (cadr-cli::make-settings-manager
              :global-path global))
           (message
             (handler-case
                 (progn
                   (cadr-cli::get-shell-config
                    (cadr-cli::settings-shell-path manager))
                   nil)
               (error (condition)
                 (princ-to-string condition)))))
      (declare (ignore _))
      (is (search "Custom shell path not found" message))
      (is (search missing message))))
  (let* ((settings
           (cadr-cli::make-memory-sdk-settings-manager
            (args
             "shellPath" "/bin/bash"
             "shellCommandPrefix"
             "shopt -s expand_aliases")))
         (expected-shell "/bin/bash")
         (expected-command
           (format nil "shopt -s expand_aliases~%printf hi")))
    (is (string= expected-shell
                 (cadr-cli:sdk-settings-shell-path settings)))
    (is (string=
         expected-shell
         (cadr-cli::shell-config-shell
          (cadr-cli::get-shell-config
           (cadr-cli:sdk-settings-shell-path settings)))))
    (is (string=
         expected-command
         (cadr-cli::bash-command-with-prefix
          (cadr-cli:sdk-settings-shell-command-prefix settings)
          "printf hi")))
    (is (eq t
            (cadr-cli:sdk-settings-compaction-enabled-p
             settings)))
    (is (= 20000
           (cadr-cli:sdk-settings-compaction-keep-recent-tokens
            settings)))
    (is (= 16384
           (cadr-cli:sdk-settings-branch-summary-reserve-tokens
            settings)))))
