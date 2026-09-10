(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun goal28-themes-search-namestrings (loader)
  (mapcar
   #'namestring
   (cadr-cli::default-resource-loader-theme-search-paths
    loader)))

(test goal28-themes-settings-reach-existing-loader
  (with-test-directory (root)
    (let* ((agent (merge-pathnames "agent/" root))
           (cwd (merge-pathnames "project/" root))
           (expected-discovery
             (namestring
              (merge-pathnames "themes/" agent)))
           (manager
             (cadr-cli::make-memory-settings-manager
              (args "theme" "dark")))
           (loader
             (cadr-cli::make-default-resource-loader
              :cwd cwd
              :agent-directory agent
              :explicit-theme-paths
              (cadr-cli::settings-theme-paths manager)))
           (paths
             (goal28-themes-search-namestrings loader)))
      (ensure-directories-exist cwd)
      (ensure-directories-exist agent)
      (is (null (cadr-cli::settings-theme-paths manager)))
      (is (string= "dark" (cadr-cli::settings-value manager "theme")))
      (is (string= expected-discovery (first paths)))
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
              (merge-pathnames "themes/" agent)))
           (expected-extra "/tmp/cadr-g28-themes-custom.json")
           (_
             (write-text
              global
              "{\"themes\":[\"/tmp/cadr-g28-themes-custom.json\"],\"theme\":\"dark\"}"))
           (manager
             (cadr-cli::make-settings-manager
              :global-path global))
           (loader
             (cadr-cli::make-default-resource-loader
              :cwd cwd
              :agent-directory agent
              :explicit-theme-paths
              (cadr-cli::settings-theme-paths manager)))
           (paths
             (goal28-themes-search-namestrings loader))
           (loaded
             (progn
               (write-text
                expected-extra
                "{\"name\":\"g28-custom\",\"colors\":{\"text\":\"#fff\"}}")
               (cadr-cli::load-themes-at-paths
                (cadr-cli::default-resource-loader-theme-search-paths
                 loader)))))
      (declare (ignore _))
      (ensure-directories-exist cwd)
      (ensure-directories-exist agent)
      (unwind-protect
           (progn
             (is (equal (list expected-extra)
                        (cadr-cli::settings-theme-paths manager)))
             (is (string=
                  "dark"
                  (cadr-cli::settings-value manager "theme")))
             (is (string= expected-discovery (first paths)))
             (is (find expected-extra paths :test #'string=))
             (is (find
                  "g28-custom"
                  loaded
                  :key (lambda (entry) (getf entry :name))
                  :test #'string=)))
        (when (probe-file expected-extra)
          (delete-file expected-extra)))))
  (let* ((settings
           (cadr-cli::make-memory-sdk-settings-manager
            (args
             "themes"
             (cadr-ai::json-array
              "/tmp/cadr-g28-themes-custom.json")
             "theme" "dark")))
         (agent
           (uiop:ensure-directory-pathname
            (merge-pathnames
             "agent/"
             (uiop:temporary-directory))))
         (expected-discovery
           (namestring
            (merge-pathnames "themes/" agent)))
         (expected-extra "/tmp/cadr-g28-themes-custom.json")
         (loader
           (cadr-cli::make-default-resource-loader
            :cwd (uiop:getcwd)
            :agent-directory agent
            :explicit-theme-paths
            (cadr-cli:sdk-settings-theme-paths settings)))
         (paths
           (goal28-themes-search-namestrings loader)))
    (is (equal (list expected-extra)
               (cadr-cli:sdk-settings-theme-paths settings)))
    (is (string= expected-discovery (first paths)))
    (is (find expected-extra paths :test #'string=))
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
    (is (null (cadr-cli:sdk-settings-thinking-budgets settings)))))
