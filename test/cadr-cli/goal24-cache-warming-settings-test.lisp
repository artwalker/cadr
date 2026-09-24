(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(test goal24-cache-warming-defaults-to-streaming-ignoring-project
  (with-test-directory (root)
    (let* ((agent-dir (merge-pathnames "agent/" root))
           (project-dir (merge-pathnames "project/" root))
           (global (merge-pathnames "settings.json" agent-dir))
           (project
             (merge-pathnames ".pi/settings.json" project-dir)))
      (ensure-directories-exist global)
      (ensure-directories-exist project)
      (is (string=
           "streaming"
           (cadr-cli::settings-cache-warming-mode
            (cadr-cli::make-settings-manager
             :global-path global
             :project-path project))))
      (write-text project "{\"cacheWarming\":\"idle\"}")
      (is (string=
           "streaming"
           (cadr-cli::settings-cache-warming-mode
            (cadr-cli::make-settings-manager
             :global-path global
             :project-path project))))
      (write-text global "{\"cacheWarming\":\"idle\"}")
      (is (string=
           "idle"
           (cadr-cli::settings-cache-warming-mode
            (cadr-cli::make-settings-manager
             :global-path global
             :project-path project))))
      (write-text global "{\"cacheWarming\":\"bogus\"}")
      (is (string=
           "streaming"
           (cadr-cli::settings-cache-warming-mode
            (cadr-cli::make-settings-manager
             :global-path global
             :project-path project)))))))

(test goal24-cache-warming-persists-mode-globally
  (with-test-directory (root)
    (let* ((agent-dir (merge-pathnames "agent/" root))
           (project-dir (merge-pathnames "project/" root))
           (global (merge-pathnames "settings.json" agent-dir))
           (project
             (merge-pathnames ".pi/settings.json" project-dir)))
      (ensure-directories-exist global)
      (ensure-directories-exist project)
      (let ((manager
              (cadr-cli::make-settings-manager
               :global-path global
               :project-path project)))
        (cadr-cli::settings-set-cache-warming-mode
         manager "off")
        (is (string=
             "off"
             (cadr-cli::settings-cache-warming-mode
              (cadr-cli::make-settings-manager
               :global-path global
               :project-path project))))
        (is (string=
             "off"
             (cadr-ai::json-get
              (cadr-ai::parse-json (read-text global))
              "cacheWarming")))))))
