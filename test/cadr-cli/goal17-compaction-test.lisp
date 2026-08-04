(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(test goal17-compaction-status-distinguishes-reason-and-configured-interrupt-key
  (let ((previous (cadr-tui:get-keybindings)))
    (unwind-protect
         (progn
           (cadr-tui:set-keybindings
            (cadr-tui:make-keybindings-manager
             :user-bindings
             '(("app.interrupt" . ("ctrl+x")))))
           (dolist
               (case
                '((:manual
                   "Compacting context... (ctrl+x to cancel)")
                  (:threshold
                   "Auto-compacting... (ctrl+x to cancel)")
                  (:overflow
                   "Context overflow detected, Auto-compacting... (ctrl+x to cancel)")))
             (destructuring-bind (reason expected) case
               (let ((state (cadr-cli::make-tui-state)))
                 (cadr-cli::tui-handle-agent-event
                  state
                  (cadr-agent::make-agent-event
                   :type :compaction-start
                   :reason reason))
                 (is
                  (string=
                   expected
                   (cadr-cli::tui-state-status-message state)))))))
      (cadr-tui:set-keybindings previous))))

(test goal17-summarization-retry-status-restores-the-originating-indicator
  (let ((state (cadr-cli::make-tui-state)))
    (cadr-cli::tui-handle-agent-event
     state
     (cadr-agent::make-agent-event
      :type :summarization-retry-scheduled
      :attempt 1 :max-attempts 3 :delay-ms 2000
      :error-message "terminated"))
    (is
     (string=
      "Retrying (1/3) in 2s..."
      (cadr-cli::tui-state-status-message state)))
    (cadr-cli::tui-handle-agent-event
     state
     (cadr-agent::make-agent-event
      :type :summarization-retry-attempt-start
      :source :compaction
      :reason :overflow))
    (is
     (string=
      "Context overflow detected, Auto-compacting... (escape to cancel)"
      (cadr-cli::tui-state-status-message state)))))
