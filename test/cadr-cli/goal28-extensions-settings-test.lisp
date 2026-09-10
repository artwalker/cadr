(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun goal28-extensions-explicit-namestrings (manager)
  (copy-list
   (cadr-cli::cli-extension-manager-explicit-paths manager)))

(defun goal28-extensions-discovery-namestring (manager)
  (namestring
   (cadr-cli::cli-extension-manager-global-directory manager)))

(test goal28-extensions-settings-reach-existing-loader
  (with-test-directory (root)
    (let* ((agent (merge-pathnames "agent/" root))
           (cwd (merge-pathnames "project/" root))
           (expected-discovery
             (namestring
              (uiop:ensure-directory-pathname
               (merge-pathnames "extensions/" agent))))
           (manager
             (cadr-cli::make-memory-settings-manager
              (args "theme" "dark")))
           (extension-manager
             (cadr-cli::make-cli-extension-manager
              :cwd cwd
              :global-directory
              (merge-pathnames "extensions/" agent)
              :explicit-paths
              (cadr-cli::settings-extension-paths manager)
              :output (make-broadcast-stream)))
           (paths
             (goal28-extensions-explicit-namestrings
              extension-manager)))
      (ensure-directories-exist cwd)
      (ensure-directories-exist agent)
      (is (null (cadr-cli::settings-extension-paths manager)))
      (is (null paths))
      (is (string=
           expected-discovery
           (goal28-extensions-discovery-namestring
            extension-manager)))
      (is (null (cadr-cli::settings-prompt-paths manager)))
      (is (null (cadr-cli::settings-skill-paths manager)))
      (is (null (cadr-cli::settings-theme-paths manager)))
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
      (is (null (cadr-cli::settings-shell-path manager)))
      (is (null (cadr-cli::settings-session-dir manager)))
      (is (null (cadr-cli::settings-http-proxy manager)))
      (is (null
           (cadr-cli::settings-websocket-connect-timeout-ms
            manager)))
      (is (null (cadr-cli::settings-thinking-budgets manager)))))
  (with-test-directory (root)
    (let* ((global (merge-pathnames "settings.json" root))
           (agent (merge-pathnames "agent/" root))
           (cwd (merge-pathnames "project/" root))
           (expected-discovery
             (namestring
              (uiop:ensure-directory-pathname
               (merge-pathnames "extensions/" agent))))
           (expected-extra "/tmp/cadr-g28-extensions-custom/")
           (_
             (write-text
              global
              "{\"extensions\":[\"/tmp/cadr-g28-extensions-custom/\"],\"theme\":\"dark\"}"))
           (manager
             (cadr-cli::make-settings-manager
              :global-path global))
           (extension-manager
             (cadr-cli::make-cli-extension-manager
              :cwd cwd
              :global-directory
              (merge-pathnames "extensions/" agent)
              :explicit-paths
              (cadr-cli::settings-extension-paths manager)
              :output (make-broadcast-stream)))
           (paths
             (goal28-extensions-explicit-namestrings
              extension-manager)))
      (declare (ignore _))
      (ensure-directories-exist cwd)
      (ensure-directories-exist agent)
      (is (equal (list expected-extra)
                 (cadr-cli::settings-extension-paths manager)))
      (is (equal (list expected-extra) paths))
      (is (string=
           expected-discovery
           (goal28-extensions-discovery-namestring
            extension-manager)))))
  (let* ((settings
           (cadr-cli::make-memory-sdk-settings-manager
            (args
             "extensions"
             (cadr-ai::json-array
              "/tmp/cadr-g28-extensions-custom/")
             "theme" "dark")))
         (agent
           (uiop:ensure-directory-pathname
            (merge-pathnames
             "agent/"
             (uiop:temporary-directory))))
         (expected-discovery
           (namestring
            (uiop:ensure-directory-pathname
             (merge-pathnames "extensions/" agent))))
         (expected-extra "/tmp/cadr-g28-extensions-custom/")
         (extension-manager
           (cadr-cli::make-cli-extension-manager
            :cwd (uiop:getcwd)
            :global-directory
            (merge-pathnames "extensions/" agent)
            :explicit-paths
            (cadr-cli:sdk-settings-extension-paths settings)
            :output (make-broadcast-stream)))
         (paths
           (goal28-extensions-explicit-namestrings
            extension-manager)))
    (is (equal (list expected-extra)
               (cadr-cli:sdk-settings-extension-paths settings)))
    (is (equal (list expected-extra) paths))
    (is (string=
         expected-discovery
         (goal28-extensions-discovery-namestring
          extension-manager)))
    (is (eq t
            (cadr-cli:sdk-settings-compaction-enabled-p
             settings)))
    (is (= 16384
           (cadr-cli:sdk-settings-branch-summary-reserve-tokens
            settings)))
    (is (null (cadr-cli:sdk-settings-shell-path settings)))
    (is (null (cadr-cli:sdk-settings-session-dir settings)))
    (is (null (cadr-cli:sdk-settings-http-proxy settings)))
    (is (null
         (cadr-cli:sdk-settings-websocket-connect-timeout-ms
          settings)))
    (is (null (cadr-cli:sdk-settings-thinking-budgets settings)))
    (is (null (cadr-cli:sdk-settings-prompt-paths settings)))
    (is (null (cadr-cli:sdk-settings-skill-paths settings)))
    (is (null (cadr-cli:sdk-settings-theme-paths settings)))))
