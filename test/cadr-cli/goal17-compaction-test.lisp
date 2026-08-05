(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defclass goal17-scripted-terminal
    (cadr-tui::virtual-terminal)
  ((inputs :initarg :inputs
           :accessor goal17-scripted-terminal-inputs)))

(defmethod cadr-tui:terminal-read-input
    ((terminal goal17-scripted-terminal))
  (or (pop (goal17-scripted-terminal-inputs terminal)) ""))

(test goal17-user-bash-result-is-rendered-through-the-tui
  (let ((terminal
          (make-instance
           'goal17-scripted-terminal
           :columns 80 :rows 16
           :inputs
           (list
            (format nil "!render~C" #\Return)
            (format nil "/quit~C" #\Return)))))
    (cadr-cli::run-tui
     (constantly nil)
     :bash-function
     (lambda (command exclude-p)
       (declare (ignore command exclude-p))
       "Output truncated. Full output: /tmp/fixed.log")
     :model "faux"
     :terminal terminal)
    (is
     (search
      "Output truncated. Full output: /tmp/fixed.log"
      (format nil "~{~A~^~%~}"
              (cadr-tui:virtual-terminal-snapshot terminal))))))

(test goal17-bash-collapsed-preview-uses-the-configured-expand-key
  (let* ((block
           (cadr-tui:make-tool-block
            :name "bash" :summary "printf lines"
            :output
            (format nil "~{line-~D~^~%~}"
                    (loop for index from 1 to 8 collect index))
            :status :complete :collapsed-p t
            :expand-key-text "ctrl+x"))
         (text
           (format nil "~{~A~^~%~}"
                   (mapcar
                    #'cadr-tui:strip-terminal-sequences
                    (cadr-tui:render-tool-block block 72)))))
    (is (search "... (3 earlier lines, ctrl+x to expand)" text))
    (is (null (search "earlier lines, to expand" text)))))

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

(test goal17-threshold-compaction-failure-copy-is-not-reprefixed
  (let ((state (cadr-cli::make-tui-state)))
    (cadr-cli::tui-handle-agent-event
     state
     (cadr-agent::make-agent-event
      :type :compaction-end
      :reason :threshold
      :error-message
      "Auto-compaction failed: Summarization failed: invalid request"))
    (is
     (string=
      "Auto-compaction failed: Summarization failed: invalid request"
      (cadr-cli::tui-entry-text
       (car (last (cadr-cli::tui-state-entries state))))))))
