(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun goal28-prompts-search-namestrings (loader)
  (mapcar
   #'namestring
   (cadr-cli::default-resource-loader-prompt-search-paths
    loader)))

(test goal28-prompts-settings-reach-existing-loader
  (with-test-directory (root)
    (let* ((agent (merge-pathnames "agent/" root))
           (cwd (merge-pathnames "project/" root))
           (expected-discovery
             (namestring
              (merge-pathnames "prompts/" agent)))
           (manager
             (cadr-cli::make-memory-settings-manager
              (args "theme" "dark")))
           (loader
             (cadr-cli::make-default-resource-loader
              :cwd cwd
              :agent-directory agent
              :explicit-prompt-paths
              (cadr-cli::settings-prompt-paths manager)))
           (paths
             (goal28-prompts-search-namestrings loader)))
      (ensure-directories-exist cwd)
      (ensure-directories-exist agent)
      (is (null (cadr-cli::settings-prompt-paths manager)))
      (is (string= expected-discovery (first paths)))
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
              (merge-pathnames "prompts/" agent)))
           (expected-extra "/tmp/cadr-g28-prompts-custom/")
           (_
             (write-text
              global
              "{\"prompts\":[\"/tmp/cadr-g28-prompts-custom/\"],\"theme\":\"dark\"}"))
           (manager
             (cadr-cli::make-settings-manager
              :global-path global))
           (loader
             (cadr-cli::make-default-resource-loader
              :cwd cwd
              :agent-directory agent
              :explicit-prompt-paths
              (cadr-cli::settings-prompt-paths manager)))
           (paths
             (goal28-prompts-search-namestrings loader))
           (loaded
             (progn
               (ensure-directories-exist expected-extra)
               (write-text
                (merge-pathnames
                 "g28-custom.md"
                 expected-extra)
                (format nil "---~%description: Goal 28 prompts settings fixture~%---~%body~%"))
               (cadr-cli::load-prompts-at-paths
                (cadr-cli::default-resource-loader-prompt-search-paths
                 loader)))))
      (declare (ignore _))
      (ensure-directories-exist cwd)
      (ensure-directories-exist agent)
      (unwind-protect
           (progn
             (is (equal (list expected-extra)
                        (cadr-cli::settings-prompt-paths manager)))
             (is (string= expected-discovery (first paths)))
             (is (find expected-extra paths :test #'string=))
             (is (find
                  "g28-custom"
                  loaded
                  :key #'cadr-agent:prompt-template-name
                  :test #'string=)))
        (uiop:delete-directory-tree
         (uiop:ensure-directory-pathname expected-extra)
         :validate t
         :if-does-not-exist :ignore))))
  (let* ((settings
           (cadr-cli::make-memory-sdk-settings-manager
            (args
             "prompts"
             (cadr-ai::json-array
              "/tmp/cadr-g28-prompts-custom/")
             "theme" "dark")))
         (agent
           (uiop:ensure-directory-pathname
            (merge-pathnames
             "agent/"
             (uiop:temporary-directory))))
         (expected-discovery
           (namestring
            (merge-pathnames "prompts/" agent)))
         (expected-extra "/tmp/cadr-g28-prompts-custom/")
         (loader
           (cadr-cli::make-default-resource-loader
            :cwd (uiop:getcwd)
            :agent-directory agent
            :explicit-prompt-paths
            (cadr-cli:sdk-settings-prompt-paths settings)))
         (paths
           (goal28-prompts-search-namestrings loader)))
    (is (equal (list expected-extra)
               (cadr-cli:sdk-settings-prompt-paths settings)))
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
    (is (null (cadr-cli:sdk-settings-thinking-budgets settings)))
    (is (null (cadr-cli:sdk-settings-skill-paths settings)))
    (is (null (cadr-cli:sdk-settings-theme-paths settings)))))
