(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(test goal24-max-agent-delay-settings-default
  (dolist
      (settings
       (list
        (cadr-cli::settings-retry-settings
         (cadr-cli::make-memory-settings-manager))
        (cadr-cli::sdk-settings-retry-settings
         (cadr-cli::make-memory-sdk-settings-manager))))
    (is (= 60000 (getf settings :max-agent-delay-ms)))))

(test goal24-max-agent-delay-settings-override
  (dolist
      (settings
       (list
        (cadr-cli::settings-retry-settings
         (cadr-cli::make-memory-settings-manager
          (args "retry"
                (args "maxAgentDelayMs" 5000))))
        (cadr-cli::sdk-settings-retry-settings
         (cadr-cli::make-memory-sdk-settings-manager
          (args "retry"
                (args "maxAgentDelayMs" 5000))))))
    (is (= 5000 (getf settings :max-agent-delay-ms)))))

(test goal24-max-agent-delay-ignores-provider-merge
  (let ((settings
          (cadr-cli::settings-retry-settings
           (cadr-cli::make-memory-settings-manager
            (args "retry"
                  (args "maxAgentDelayMs" 5000
                        "provider"
                        (args "maxAgentDelayMs"
                              999)))))))
    (is (= 5000 (getf settings :max-agent-delay-ms)))))
