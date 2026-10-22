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

(test goal27-sighup-and-sigterm-follow-v140
  ;; pi@4a080252 interactive-mode.ts registerSignalHandlers and
  ;; shutdown({fromSignal:true}): a real SIGHUP (except win32) or
  ;; SIGTERM kills detached children, emits session_shutdown before
  ;; terminal cleanup, ignores a second signal, and returns 0.
  ;; print-mode.ts and rpc-mode.ts return 129 and 143 and do not emit
  ;; session_shutdown from this handler.
  (let* ((order nil)
         (host (cadr-agent::make-extension-host))
         (bundle
           (cadr-agent::make-extension-bundle
            :id "gap29-sighup"
            :path "/tmp/gap29-sighup.lisp"))
         (agent
           (cadr-agent:make-agent
            :tools nil
            :model nil
            :extension-host host))
         (detached-pid 2147483646))
    (cadr-agent::call-with-extension-registration
     bundle
     (lambda ()
       (cadr-agent:define-event-hook
        :session-shutdown
        :handler
        (lambda (value context)
          (declare (ignore value context))
          (push :session-shutdown order)
          nil))))
    (cadr-agent::replace-extension-bundles host (list bundle))
    (labels ((raise (signal)
               (sb-posix:kill (sb-posix:getpid) signal)
               (sleep 1))
             (tracked-p ()
               (gethash
                detached-pid
                cadr-cli::*tracked-detached-child-pids*)))
      (unwind-protect
           (progn
             #-win32
             (progn
               (cadr-cli:track-detached-child-pid detached-pid)
               (let ((continued nil))
                 (is (= 0
                        (cadr-cli::call-with-cli-signal-handlers
                         agent
                         (lambda ()
                           (unwind-protect
                                (progn
                                  (raise sb-unix:sighup)
                                  (setf continued t))
                             (push :terminal order)
                             (raise sb-unix:sighup)))
                         :interactive-p t)))
                 (is (null continued))
                 (is (equal order '(:terminal :session-shutdown)))
                 (is (null (tracked-p)))))
             (setf order nil)
             (cadr-cli:track-detached-child-pid detached-pid)
             (is (= 0
                    (cadr-cli::call-with-cli-signal-handlers
                     agent
                     (lambda ()
                       (raise sb-unix:sigterm)
                       :continued)
                     :interactive-p t)))
             (is (equal order '(:session-shutdown)))
             (is (null (tracked-p)))
             (setf order nil)
             #-win32
             (progn
               (cadr-cli:track-detached-child-pid detached-pid)
               (is (= 129
                      (cadr-cli::call-with-cli-signal-handlers
                       agent
                       (lambda ()
                         (raise sb-unix:sighup)
                         0))))
               (is (null order))
               (is (null (tracked-p))))
             (cadr-cli:track-detached-child-pid detached-pid)
             (is (= 143
                    (cadr-cli::call-with-cli-signal-handlers
                     agent
                     (lambda ()
                       (raise sb-unix:sigterm)
                       0))))
             (is (null order))
             (is (null (tracked-p)))
             (is (= 0
                    (cadr-cli::call-with-cli-signal-handlers
                     agent
                     (lambda () 0)
                     :interactive-p t)))
             (is (null order)))
        (cadr-cli:untrack-detached-child-pid detached-pid)))))
