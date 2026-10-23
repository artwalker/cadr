(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun goal28-make-agent-from-retry (retry)
  (cadr-agent:make-agent
   :auto-retry-p (getf retry :enabled-p)
   :auto-retry-max-attempts (getf retry :max-retries)
   :auto-retry-base-delay
   (/ (getf retry :base-delay-ms) 1000)
   :auto-retry-max-delay-ms
   (getf retry :max-agent-delay-ms)))

(defun goal28-assert-retry-slots (agent enabled max delay)
  (is (eq enabled (cadr-agent::agent-auto-retry-p agent)))
  (is (= max (cadr-agent::agent-auto-retry-max-attempts agent)))
  (is (= delay (cadr-agent::agent-auto-retry-base-delay agent))))

(test goal28-retry-enabled-reaches-existing-agent
  (goal28-assert-retry-slots (cadr-agent:make-agent) t 3 2)
  (goal28-assert-retry-slots
   (goal28-make-agent-from-retry
    (cadr-cli::settings-retry-settings
     (cadr-cli::make-memory-settings-manager)))
   t 3 2)
  (goal28-assert-retry-slots
   (goal28-make-agent-from-retry
    (cadr-cli::settings-retry-settings
     (cadr-cli::make-memory-settings-manager
      (args "retry"
            (args "enabled" nil
                  "maxRetries" 2
                  "baseDelayMs" 4000)))))
   nil 2 4)
  (goal28-assert-retry-slots
   (goal28-make-agent-from-retry
    (cadr-cli::sdk-settings-retry-settings
     (cadr-cli::make-memory-sdk-settings-manager)))
   t 3 2)
  (goal28-assert-retry-slots
   (goal28-make-agent-from-retry
    (cadr-cli::sdk-settings-retry-settings
     (cadr-cli::make-memory-sdk-settings-manager
      (args "retry"
            (args "enabled" nil
                  "maxRetries" 2
                  "baseDelayMs" 4000)))))
   nil 2 4))

(defun goal23-retry-caps (manager sdk-p)
  (getf
   (if sdk-p
       (cadr-cli:sdk-settings-retry-settings manager)
       (cadr-cli::settings-retry-settings manager))
   :max-agent-delay-ms))

(test goal23-max-agent-delay-ms-reaches-the-agent
  ;; packages/coding-agent/test/settings-manager.test.ts
  ;; "defaults and overrides agent retry delay cap".
  (dolist (sdk-p '(nil t))
    (let ((empty
            (if sdk-p
                (cadr-cli::make-memory-sdk-settings-manager)
                (cadr-cli::make-memory-settings-manager))))
      (is (= 60000 (goal23-retry-caps empty sdk-p)))
      (is (= 60000
             (cadr-agent::agent-auto-retry-max-delay-ms
              (goal28-make-agent-from-retry
               (if sdk-p
                   (cadr-cli:sdk-settings-retry-settings empty)
                   (cadr-cli::settings-retry-settings empty)))))))
    (let ((manager
            (if sdk-p
                (cadr-cli::make-memory-sdk-settings-manager
                 (args "retry"
                       (args "enabled" t
                             "maxRetries" 10
                             "baseDelayMs" 500
                             "maxAgentDelayMs" 5000)))
                (cadr-cli::make-memory-settings-manager
                 (args "retry"
                       (args "enabled" t
                             "maxRetries" 10
                             "baseDelayMs" 500
                             "maxAgentDelayMs" 5000))))))
      (is (= 5000 (goal23-retry-caps manager sdk-p)))
      (is (= 10
             (getf
              (if sdk-p
                  (cadr-cli:sdk-settings-retry-settings manager)
                  (cadr-cli::settings-retry-settings manager))
              :max-retries)))
      (is (= 5000
             (cadr-agent::agent-auto-retry-max-delay-ms
              (goal28-make-agent-from-retry
               (if sdk-p
                   (cadr-cli:sdk-settings-retry-settings manager)
                   (cadr-cli::settings-retry-settings manager))))))))
  (dolist (sdk-p '(nil t))
    (let ((zero
            (if sdk-p
                (cadr-cli::make-memory-sdk-settings-manager
                 (args "retry" (args "maxAgentDelayMs" 0)))
                (cadr-cli::make-memory-settings-manager
                 (args "retry" (args "maxAgentDelayMs" 0)))))
          (missing
            (if sdk-p
                (cadr-cli::make-memory-sdk-settings-manager
                 (args "retry"
                       (args "maxAgentDelayMs" 'null)))
                (cadr-cli::make-memory-settings-manager
                 (args "retry"
                       (args "maxAgentDelayMs" 'null))))))
      (is (= 0 (goal23-retry-caps zero sdk-p)))
      (is (= 60000 (goal23-retry-caps missing sdk-p)))))
  (with-test-directory (root)
    (let* ((global (merge-pathnames "global.json" root))
           (project (merge-pathnames "project.json" root)))
      (write-text
       global
       "{\"retry\":{\"maxAgentDelayMs\":5000,\"maxRetries\":3,\"provider\":{\"maxRetryDelayMs\":45000}}}")
      (write-text
       project
       "{\"retry\":{\"maxRetries\":1}}")
      (dolist (sdk-p '(nil t))
        (let ((manager
                (if sdk-p
                    (cadr-cli::make-sdk-settings-manager
                     :global-path global
                     :project-path project)
                    (cadr-cli::make-settings-manager
                     :global-path global
                     :project-path project))))
          (is (= 5000 (goal23-retry-caps manager sdk-p)))
          (is (= 1
                 (getf
                  (if sdk-p
                      (cadr-cli:sdk-settings-retry-settings manager)
                      (cadr-cli::settings-retry-settings manager))
                  :max-retries)))
          (is (= 45000
                 (getf
                  (if sdk-p
                      (cadr-cli:sdk-settings-retry-settings manager)
                      (cadr-cli::settings-retry-settings manager))
                  :max-retry-delay-ms)))))
      (write-text project "{\"retry\":{\"maxAgentDelayMs\":7000}}")
      (let ((untrusted
              (cadr-cli::make-settings-manager
               :global-path global
               :project-path project
               :project-trusted-p nil)))
        (is (= 5000 (goal23-retry-caps untrusted nil))))
      (write-text
       global
       "{\"retry\":{\"maxDelayMs\":1000}}")
      (write-text project "{}")
      (let ((manager
              (cadr-cli::make-settings-manager
               :global-path global
               :project-path project)))
        (is (= 60000 (goal23-retry-caps manager nil)))
        (is (= 1000
               (getf
                (cadr-cli::settings-retry-settings manager)
                :max-retry-delay-ms)))))))
