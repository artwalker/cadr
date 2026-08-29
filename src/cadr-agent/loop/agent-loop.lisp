(in-package #:cadr-agent)

(defun run-agent-loop (agent initial-messages)
  (run-agent-lifecycle agent :agent-start)
  (emit-agent-event agent :agent-start)
  (begin-agent-turn agent 1 initial-messages)
  (loop for turn from 1
        do
        (when (> turn (agent-max-turns agent))
          (let ((message (turn-limit-message agent)))
            (multiple-value-bind
                  (final-message appended)
                (run-turn-end-hooks
                 agent turn message nil)
              (append-agent-message-with-events
               agent final-message)
              (append-agent-messages-with-events
               agent appended)
              (emit-agent-event
               agent :turn-end
               :message final-message
               :tool-results nil)
              (emit-agent-end agent)
              (return-from run-agent-loop
                final-message))))
        ;; pi@b79e4cc83 agent-loop.ts #8782: compact before the next
        ;; provider request once a turn has already completed, so
        ;; threshold compaction runs between tool rounds.
        (when (> turn 1)
          (maybe-compact-agent agent))
        (let* ((streamed-message (stream-assistant agent))
               (calls
                 (assistant-tool-calls streamed-message))
               (results nil)
               (tool-hook-messages nil)
               (terminal-p
                 (member
                  (cadr-ai:assistant-message-stop-reason
                   streamed-message)
                  '(:error :aborted))))
          (when (and calls (not terminal-p))
            (multiple-value-bind
                  (batch-results batch-hook-messages
                   abort-from-tool-p terminate-from-tool-p)
                (if
                    (eq
                     :length
                     (cadr-ai:assistant-message-stop-reason
                      streamed-message))
                    (execute-truncated-tool-batch
                     agent calls :turn-index turn)
                    (execute-tool-batch
                     agent calls :turn-index turn))
              (setf
               results batch-results
               tool-hook-messages batch-hook-messages)
              (when (or abort-from-tool-p
                        terminate-from-tool-p)
                (setf terminal-p t))))
          (multiple-value-bind
                (message turn-hook-messages)
              (run-turn-end-hooks
               agent turn streamed-message results)
            (commit-agent-turn
             agent message results
             tool-hook-messages
             turn-hook-messages)
            (emit-agent-event
             agent :turn-end
             :message message
             :tool-results results)
            (flush-agent-pending-custom-messages agent)
            ;; Early terminal exit. LOOP's RETURN would leave the
            ;; whole loop; fall through to the next turn instead.
            (if terminal-p
                (progn
                  (emit-agent-end agent)
                  (return-from run-agent-loop message))
                (let ((steering
                        (drain-agent-queue
                         agent :steering)))
                  (if (or calls steering)
                      (begin-agent-turn
                       agent (1+ turn) steering)
                      (let ((follow-up
                              (drain-agent-queue
                               agent :follow-up)))
                        (if follow-up
                            (begin-agent-turn
                             agent (1+ turn) follow-up)
                            (progn
                              (emit-agent-end agent)
                              (let ((late-follow-up
                                      (drain-agent-queue
                                       agent :follow-up)))
                                (if late-follow-up
                                    (begin-agent-turn
                                     agent (1+ turn)
                                     late-follow-up)
                                    (return-from
                                        run-agent-loop
                                      message)))))))))))))

(defun call-with-agent-run (agent function)
    (sb-thread:with-mutex
        ((agent-state-lock agent))
      (when (agent-shutdown-p agent)
        (shutdown-agent-error))
      (when (agent-busy-p agent)
        (error 'agent-busy-error
               :message "Agent is already processing a prompt"))
      (setf
       (agent-busy-p agent) t
       (agent-operation-count agent)
       (1+ (agent-operation-count agent))
       (agent-operation-threads agent)
       (cons
        sb-thread:*current-thread*
        (agent-operation-threads agent))
       (agent-abort-requested-p agent) nil
       (agent-retry-attempt agent) 0
       (agent-retry-in-progress-p agent) nil
       (agent-retry-abort-requested-p agent) nil))
    (unwind-protect
         (funcall function)
      (progn
        (let ((session (agent-session agent)))
          (when session
            (close-session-journal-stream session)))
        (flush-agent-pending-custom-messages agent)
        (run-agent-lifecycle agent :agent-settled)
        (emit-agent-event agent :agent-settled)
        (sb-thread:with-mutex
            ((agent-state-lock agent))
          (setf
           (agent-busy-p agent) nil
           (agent-operation-count agent)
           (1- (agent-operation-count agent))
           (agent-operation-threads agent)
           (delete
            sb-thread:*current-thread*
            (agent-operation-threads agent)
            :count 1
            :test #'eq))
          (sb-thread:condition-broadcast
           (agent-idle-condition agent))))))

(defun agent-navigate-tree
    (agent entry-id
     &key summarize-p custom-instructions
       replace-instructions-p label)
  (call-with-agent-operation
   agent
   (lambda ()
     (when (agent-busy-p agent)
       (error
        'agent-busy-error
        :message
        "Cannot navigate the session tree while the agent is running"))
     (let ((session (agent-session agent)))
       (unless session
         (error
          'session-error
          :message
          "Cannot navigate without a persistent session"))
       (let* ((old-leaf-id (session-leaf-id session))
              (target-entry (session-entry-at session entry-id)))
         (unless target-entry
           (error 'session-error
                  :message (format nil "Entry ~A not found" entry-id)))
         (when (and old-leaf-id (string= old-leaf-id entry-id))
           (return-from agent-navigate-tree
             (values (copy-list (agent-messages agent)) nil nil nil)))
         (multiple-value-bind (entries common-ancestor-id)
             (collect-entries-for-branch-summary
              session old-leaf-id entry-id)
           (let* ((preparation
                    (list
                     :target-id entry-id
                     :old-leaf-id old-leaf-id
                     :common-ancestor-id common-ancestor-id
                     :entries-to-summarize entries
                     :user-wants-summary-p (not (null summarize-p))
                     :custom-instructions custom-instructions
                     :replace-instructions-p
                     (not (null replace-instructions-p))
                     :label label))
                  (before
                    (run-agent-lifecycle
                     agent :session-before-tree
                     (list
                      :preparation preparation
                      :signal
                      (make-extension-cancellation-signal)))))
         (when (getf before :cancel-p)
           (return-from agent-navigate-tree
             (values nil t nil nil)))
         (let* ((summary-text (getf before :summary))
                (summary-details (getf before :details))
                (summary-usage (getf before :usage))
                (from-hook-p (not (null summary-text))))
           (when (and (null summary-text) summarize-p entries)
             (let ((result
                     (generate-branch-summary
                      agent entries
                      :custom-instructions
                      (or (getf before :custom-instructions)
                          custom-instructions)
                      :replace-instructions-p
                      (if (member :replace-instructions-p before)
                          (getf before :replace-instructions-p)
                          replace-instructions-p))))
               (unless result
                 (return-from agent-navigate-tree
                   (values nil t nil nil)))
               (setf summary-text (branch-summary-result-summary result)
                     summary-usage (branch-summary-result-usage result)
                     summary-details
                     (list :read-files
                           (branch-summary-result-read-files result)
                           :modified-files
                           (branch-summary-result-modified-files result)))))
         (assert-agent-not-shutdown agent)
         (let* ((user-target-p
                  (and (eq :message (session-entry-type target-entry))
                       (typep (session-entry-message target-entry)
                              'cadr-ai:user-message)))
                (custom-target-p
                  (eq :custom-message (session-entry-type target-entry)))
                (new-leaf-id
                  (if (or user-target-p custom-target-p)
                      (session-entry-parent-id target-entry)
                      entry-id))
                (editor-text
                  (cond
                    (user-target-p
                     (content-text
                      (cadr-ai:user-message-content
                       (session-entry-message target-entry)) ""))
                    (custom-target-p
                     (content-text (session-entry-content target-entry) ""))))
                (summary-entry nil))
         (if new-leaf-id
             (session-branch session new-leaf-id)
             (setf (session-leaf-id session) nil))
         (when (and summary-text
                    (plusp (length summary-text)))
           (let ((summary-id
                   (session-append-branch-summary
                    session old-leaf-id summary-text
                    :details summary-details
                    :usage summary-usage
                    :from-hook-p from-hook-p)))
             (setf summary-entry (session-entry-at session summary-id))))
         (setf
          (agent-messages agent)
          (session-messages session))
         (run-agent-lifecycle
          agent :session-tree
          (list
           :target-id entry-id
           :new-leaf-id (session-leaf-id session)
           :old-leaf-id old-leaf-id
           :summary-entry summary-entry
           :from-hook-p from-hook-p
           :messages
           (copy-list
            (agent-messages agent))))
         (values
          (copy-list
           (agent-messages agent))
          nil
          editor-text
          summary-entry))))))))))

(defun user-message-input-values (message)
  (let ((content
          (cadr-ai:user-message-content message)))
    (if (stringp content)
        (values content nil)
        (values
         (with-output-to-string (output)
           (loop for block in content
                 when
                 (typep block 'cadr-ai:text-content)
                   do
                   (write-string
                    (cadr-ai:text-content-text block)
                    output)))
         (remove-if-not
          (lambda (block)
            (typep block 'cadr-ai:image-content))
          content)))))

(defun apply-agent-input-hooks
    (agent message source &key streaming-behavior)
  (let ((normalized
          (normalize-agent-queue-message message)))
    (multiple-value-bind (text images)
        (user-message-input-values normalized)
      (let* ((payload
               (list
                :text text
                :images images
                :source source))
             (payload
               (if streaming-behavior
                   (append
                    payload
                    (list
                     :streaming-behavior
                     streaming-behavior))
                   payload))
             (result
               (run-agent-lifecycle
                agent :input payload))
             (action
               (or
                (getf result :action)
                :continue)))
        (when (eq action :handled)
          (return-from apply-agent-input-hooks
            (values nil t)))
        (let ((final-text
                (if (eq action :transform)
                    (getf result :text)
                    text))
              (final-images
                (if (eq action :transform)
                    (getf result :images)
                    images)))
          (values
           (cadr-ai:make-user-message
            :content
            (if final-images
                (nconc
                 (list
                  (cadr-ai:make-text-content
                   :text final-text))
                 (copy-list final-images))
                final-text))
           nil))))))

(defun prepare-agent-prompt
    (agent message source)
  (multiple-value-bind (final-message handled-p)
      (apply-agent-input-hooks
       agent message source)
    (when handled-p
      (return-from prepare-agent-prompt
        (values nil nil t)))
    (multiple-value-bind (final-text final-images)
        (user-message-input-values final-message)
      (let* ((before-result
               (run-agent-lifecycle
                agent :before-agent-start
                (list
                 :prompt final-text
                 :images final-images
                 :system-prompt
                 (agent-system-prompt agent)
                 :system-prompt-options
                 (copy-tree
                  (agent-system-prompt-options agent))))))
        (values
         (nconc
          (drain-agent-queue agent :next-turn)
          (list final-message)
          (copy-list
           (getf before-result :messages))
          (drain-agent-queue agent :steering))
         (let ((sentinel (list :missing)))
           (let ((system-prompt
                   (getf
                    before-result
                    :system-prompt sentinel)))
             (if (eq system-prompt sentinel)
                 (agent-system-prompt agent)
                 system-prompt)))
         nil)))))

(defun agent-prompt
    (agent prompt
     &key
       (source :interactive)
       preflight-function)
    (let ((message
          (normalize-agent-queue-message prompt)))
    (call-with-agent-run
     agent
     (lambda ()
       (ensure-agent-session-started agent)
       (flush-agent-pending-custom-messages agent)
       (maybe-compact-agent agent)
       (multiple-value-bind
             (messages system-prompt handled-p)
           (prepare-agent-prompt
            agent message source)
         (if handled-p
             (progn
               (when preflight-function
                 (funcall preflight-function))
               (assert-agent-not-shutdown agent)
               nil)
              (progn
               ;; Baseline agent-session.ts:1181-1192 — the sentinel
               ;; model (agent.ts DEFAULT_MODEL, provider "unknown") has
               ;; no configured auth, so the first send fails with the
               ;; auth-guidance text after extension/template expansion
               ;; and before any LLM work; the message is never
               ;; appended.
               (unless (agent-model agent)
                 (error
                  'cadr-ai:configuration-error
                  :message
                  (cadr-ai::no-api-key-found-message "unknown")))
               (when preflight-function
                 (funcall preflight-function))
               (assert-agent-not-shutdown agent)
               (let ((*agent-run-system-prompt*
                       system-prompt))
                 (run-agent-with-retries
                  agent messages)))))))))

(defun agent-continue (agent)
  (assert-agent-not-shutdown agent)
  (let ((messages (agent-messages agent)))
    (unless messages
      (error
       'cadr-ai:configuration-error
       :message "No messages to continue from"))
    (let ((last (car (last messages))))
      (if (typep last 'cadr-ai:assistant-message)
          (let ((queued
                  (or
                   (drain-agent-queue agent :steering)
                   (drain-agent-queue agent :follow-up))))
            (unless queued
              (error
               'cadr-ai:configuration-error
               :message
               "Cannot continue from an assistant message without queued work"))
            (call-with-agent-run
             agent
             (lambda ()
               (run-agent-with-retries
                agent queued))))
          (call-with-agent-run
           agent
           (lambda ()
             (run-agent-with-retries
              agent
              (drain-agent-queue agent :steering))))))))
