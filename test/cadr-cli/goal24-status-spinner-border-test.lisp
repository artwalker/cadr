(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun goal24-plain-lines (lines)
  (mapcar #'cadr-tui:strip-terminal-sequences lines))

(defun goal24-border-status-line-p (needle spinner plain-lines)
  (find-if
   (lambda (line)
     (and (search needle line)
          (search spinner line)
          (find #\─ line)))
   plain-lines))

(defun goal24-standalone-status-line-p (needle plain-lines)
  (find-if
   (lambda (line)
     (and (search needle line)
          (not (find #\─ line))))
   plain-lines))

(test goal24-default-editor-embeds-compaction-status-in-border
  (let ((state (cadr-cli::make-tui-state)))
    (cadr-cli::tui-handle-agent-event
     state
     (cadr-agent::make-agent-event
      :type :compaction-start
      :reason :manual))
    (multiple-value-bind (lines row column)
        (cadr-cli::render-tui-state
         state (cadr-tui:make-multiline-editor) 80 20
         :busy-p t :spinner-frame "⠋" :full-document-p t)
      (declare (ignore row column))
      (let ((plain (goal24-plain-lines lines)))
        (is (goal24-border-status-line-p
             "Compacting context..." "⠋" plain))
        (is (null
             (goal24-standalone-status-line-p
              "Compacting context..." plain)))))))

(test goal24-default-editor-embeds-retry-status-in-border
  (let ((state (cadr-cli::make-tui-state)))
    (cadr-cli::tui-handle-agent-event
     state
     (cadr-agent::make-agent-event
      :type :summarization-retry-scheduled
      :attempt 1 :max-attempts 3 :delay-ms 2000
      :error-message "terminated"))
    (multiple-value-bind (lines row column)
        (cadr-cli::render-tui-state
         state (cadr-tui:make-multiline-editor) 80 20
         :busy-p t :spinner-frame "⠋" :full-document-p t)
      (declare (ignore row column))
      (let ((plain (goal24-plain-lines lines)))
        (is (goal24-border-status-line-p
             "Retrying (1/3) in 2s..." "⠋" plain))
        (is (null
             (goal24-standalone-status-line-p
              "Retrying (1/3) in 2s..." plain)))))))

(test goal24-default-editor-embeds-branch-summary-status-in-border
  (let ((state (cadr-cli::make-tui-state)))
    (setf (cadr-cli::tui-state-status-message state)
          (cadr-cli::summarization-status-message
           :branch-summary nil))
    (multiple-value-bind (lines row column)
        (cadr-cli::render-tui-state
         state (cadr-tui:make-multiline-editor) 80 20
         :busy-p t :spinner-frame "⠋" :full-document-p t)
      (declare (ignore row column))
      (let ((plain (goal24-plain-lines lines)))
        (is (goal24-border-status-line-p
             "Summarizing branch..." "⠋" plain))
        (is (null
             (goal24-standalone-status-line-p
              "Summarizing branch..." plain)))))))

(test goal24-custom-editor-keeps-standalone-compaction-status
  (let ((state (cadr-cli::make-tui-state))
        (editor (cadr-tui:make-spacer-component :lines 1)))
    (cadr-cli::tui-handle-agent-event
     state
     (cadr-agent::make-agent-event
      :type :compaction-start
      :reason :manual))
    (multiple-value-bind (lines row column)
        (cadr-cli::render-tui-state
         state editor 80 20 :busy-p t :spinner-frame "⠋"
         :full-document-p t)
      (declare (ignore row column))
      (let ((plain (goal24-plain-lines lines)))
        (is (goal24-standalone-status-line-p
             "Compacting context..." plain))
        (is (null
             (goal24-border-status-line-p
              "Compacting context..." "⠋" plain)))))))
