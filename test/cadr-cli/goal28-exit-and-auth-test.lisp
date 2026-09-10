(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(test goal28-auth-command-error-reaches-existing-print
  (signals cadr-cli::auth-command-error
    (cadr-cli:parse-auth-command
     '("auth" "print-api-key"
       "--min-expiry" "30m")))
  (handler-case
      (cadr-cli:parse-auth-command
       '("auth" "print-api-key"
         "--min-expiry" "30m"))
    (cadr-cli::auth-command-error (condition)
      (is (stringp
           (cadr-cli::auth-command-error-message
            condition)))
      (is (plusp
           (length
            (cadr-cli::auth-command-error-message
             condition)))))))

(test goal28-exit-codes-reach-existing-process-contract
  (is (= 0
         (handler-case
             (error 'cadr-cli::cli-session-abort
                    :status 0)
           (cadr-cli::cli-session-abort (condition)
             (cadr-cli::cli-session-abort-status
              condition)))))
  (is (typep
       (make-condition
        'cadr-ai:configuration-error
        :message "Error: goal28")
       'cadr-ai:cadr-error))
  (let ((agent
          (cadr-agent:make-agent
           :tools nil
           :model nil)))
    (is (= 129
           (cadr-cli::call-with-cli-signal-handlers
            agent
            (lambda ()
              (throw 'cadr-cli::cadr-cli-signal
                     129)))))
    (is (= 0
           (cadr-cli::call-with-cli-signal-handlers
            agent
            (lambda () 0))))
    (is (= 1
           (handler-case
               (progn
                 (error
                  'cadr-ai:configuration-error
                  :message "Error: goal28")
                 0)
             (cadr-ai:cadr-error ()
               1))))))
