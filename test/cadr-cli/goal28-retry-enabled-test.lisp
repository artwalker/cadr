(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun goal28-make-agent-from-retry (retry)
  (cadr-agent:make-agent
   :auto-retry-p (getf retry :enabled-p)
   :auto-retry-max-attempts (getf retry :max-retries)
   :auto-retry-base-delay
   (/ (getf retry :base-delay-ms) 1000)
   :auto-retry-max-delay
   (/ (getf retry :max-agent-delay-ms) 1000)))

(defun goal28-assert-retry-slots (agent enabled max delay &optional (max-delay 60))
  (is (eq enabled (cadr-agent::agent-auto-retry-p agent)))
  (is (= max (cadr-agent::agent-auto-retry-max-attempts agent)))
  (is (= delay (cadr-agent::agent-auto-retry-base-delay agent)))
  (is (= max-delay (cadr-agent::agent-auto-retry-max-delay agent))))

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
                  "baseDelayMs" 4000
                  "maxAgentDelayMs" 5000)))))
   nil 2 4 5)
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

(test max-agent-delay-ms-defaults-in-retry-settings
  (let ((settings
          (cadr-cli::settings-retry-settings
           (cadr-cli::make-memory-settings-manager))))
    (is (= 60000 (getf settings :max-agent-delay-ms)))
    (is (= 60000 (getf settings :max-retry-delay-ms))))
  (let ((settings
          (cadr-cli::sdk-settings-retry-settings
           (cadr-cli::make-memory-sdk-settings-manager))))
    (is (= 60000 (getf settings :max-agent-delay-ms)))
    (is (= 60000 (getf settings :max-retry-delay-ms))))
  (let ((settings
          (cadr-cli::settings-retry-settings
           (cadr-cli::make-memory-settings-manager
            (args "retry"
                  (args "maxAgentDelayMs" 9000
                        "maxRetryDelayMs" 12000))))))
    (is (= 9000 (getf settings :max-agent-delay-ms)))
    (is (= 12000 (getf settings :max-retry-delay-ms)))))
