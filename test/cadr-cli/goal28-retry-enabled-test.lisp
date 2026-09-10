(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun goal28-make-agent-from-retry (retry)
  (cadr-agent:make-agent
   :auto-retry-p (getf retry :enabled-p)
   :auto-retry-max-attempts (getf retry :max-retries)
   :auto-retry-base-delay
   (/ (getf retry :base-delay-ms) 1000)))

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
