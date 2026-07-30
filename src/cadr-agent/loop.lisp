(in-package #:cadr-agent)

(defun append-agent-message (agent message)
  (when (agent-session agent)
    (session-append-message
     (agent-session agent) message))
  (setf (agent-messages agent)
        (nconc (agent-messages agent) (list message)))
  message)

(defun assistant-tool-calls (message)
  (remove-if-not
   (lambda (block) (typep block 'cadr-ai:tool-call))
   (cadr-ai:assistant-message-content message)))

(defun make-truncated-tool-result (call)
  (make-error-tool-result
   call
   (format
    nil
    "Tool call ~S was not executed: the response hit the output token limit, so its arguments may be truncated. Re-issue the tool call with complete arguments."
    (cadr-ai:tool-call-name call))))

(defun emit-tool-outcome (agent outcome)
  (emit-agent-event
   agent :tool-execution-end
   :tool-call (tool-outcome-call outcome)
   :tool-result (tool-outcome-result outcome)))

(defun finalize-tool-outcome (agent outcome turn-index)
  (if (not (agent-extension-host agent))
      outcome
      (multiple-value-bind
            (replacement appended blocked-p reason)
          (run-extension-hooks
           (agent-extension-host agent)
           :tool-call-after
           :turn-index turn-index
           :tool-call (tool-outcome-call outcome)
           :tool-result (tool-outcome-result outcome))
        (declare (ignore blocked-p reason))
        (setf
         (tool-outcome-result outcome) replacement
         (tool-outcome-appended-messages outcome)
         (nconc
          (tool-outcome-appended-messages outcome)
          appended))
        outcome)))

(defun complete-tool-outcome (agent outcome turn-index)
  (let ((final
          (finalize-tool-outcome
           agent outcome turn-index)))
    (emit-tool-outcome agent final)
    final))

(defun tool-outcomes-values (agent outcomes)
  (let ((results nil))
    (loop for outcome across outcomes
          for result = (tool-outcome-result outcome)
          do (emit-agent-event agent :message-start
                               :message result)
             (emit-agent-event agent :message-end
                               :message result)
             (push result results))
    (values
     (nreverse results)
     (loop
       for outcome across outcomes
       append
       (copy-list
        (tool-outcome-appended-messages outcome))))))

(defun execute-tool-batch
    (agent calls &key turn-index)
  (dolist (call calls)
    (emit-agent-event agent :tool-execution-start
                      :tool-call call))
  (let* ((prepared
           (mapcar
            (lambda (call)
              (prepare-tool-execution
               agent call :turn-index turn-index))
            calls))
         (parallel-p
           (every
            (lambda (entry)
              (or (typep entry 'tool-outcome)
                  (eq :parallel
                      (cadr-ai:tool-execution-mode
                       (prepared-tool-call-tool entry)))))
            prepared))
         (outcomes
           (make-array (length prepared)
                       :initial-element nil)))
    (if parallel-p
        (let ((threads nil))
          (loop for entry in prepared
                for index from 0
                do
                (if (typep entry 'tool-outcome)
                    (progn
                      (setf
                       (aref outcomes index)
                       (complete-tool-outcome
                        agent entry turn-index)))
                    (let ((thread-entry entry)
                          (thread-index index))
                      (push
                       (sb-thread:make-thread
                        (lambda ()
                          (let ((outcome
                                  (complete-tool-outcome
                                   agent
                                   (execute-prepared-tool
                                    thread-entry)
                                   turn-index)))
                            (setf (aref outcomes thread-index)
                                  outcome)))
                        :name
                        (format nil "cadr-tool-~A"
                                (cadr-ai:tool-call-name
                                 (prepared-tool-call-call
                                  thread-entry))))
                       threads))))
          (dolist (thread threads)
            (sb-thread:join-thread thread)))
        (loop for entry in prepared
              for index from 0
              for outcome =
                (complete-tool-outcome
                 agent
                 (if (typep entry 'tool-outcome)
                     entry
                     (execute-prepared-tool entry))
                 turn-index)
              do (setf (aref outcomes index) outcome)))
    (tool-outcomes-values agent outcomes)))

(defun execute-truncated-tool-batch
    (agent calls &key turn-index)
  (let ((outcomes
          (make-array (length calls)
                      :initial-element nil)))
    (loop for call in calls
          for index from 0
          do
          (emit-agent-event
           agent :tool-execution-start
           :tool-call call)
          (setf
           (aref outcomes index)
           (complete-tool-outcome
            agent
            (make-truncated-tool-result call)
            turn-index)))
    (tool-outcomes-values agent outcomes)))

(defun stream-assistant (agent)
  (maybe-compact-agent agent)
  (let ((started-p nil))
    (let ((message
            (funcall
             (agent-stream-function agent)
             (agent-provider agent)
             (agent-model agent)
             (cadr-ai:make-context
              :system-prompt (agent-system-prompt agent)
              :messages (copy-list
                         (agent-messages agent))
              :tools
              (registry-tools (agent-tool-registry agent)))
             (lambda (event)
               (case (cadr-ai:stream-event-type event)
                 (:start
                  (setf started-p t)
                  (emit-agent-event
                   agent :message-start
                   :message (cadr-ai:stream-event-message event)))
                 ((:text-start :text-delta :text-end
                   :thinking-start :thinking-delta :thinking-end
                   :tool-call-start :tool-call-delta :tool-call-end)
                  (emit-agent-event
                   agent :message-update
                   :message (cadr-ai:stream-event-message event)
                   :stream-event event))))
             :abort-p (agent-abort-p agent))))
      (unless started-p
        (emit-agent-event agent :message-start :message message))
      (emit-agent-event agent :message-end :message message)
      message)))

(defun turn-limit-message (agent)
  (cadr-ai:make-assistant-message
   :api (cadr-ai:model-api (agent-model agent))
   :provider (cadr-ai:model-provider (agent-model agent))
   :model (cadr-ai:model-id (agent-model agent))
   :stop-reason :error
   :error-message
   (format nil "Agent exceeded the ~D-turn limit"
           (agent-max-turns agent))))

(defun append-agent-message-with-events
    (agent message)
  (append-agent-message agent message)
  (emit-agent-event agent :message-start
                    :message message)
  (emit-agent-event agent :message-end
                    :message message)
  message)

(defun append-agent-messages-with-events
    (agent messages)
  (dolist (message messages)
    (append-agent-message-with-events
     agent message))
  messages)

(defun begin-agent-turn
    (agent turn-index message)
  (emit-agent-event agent :turn-start)
  (if (not (agent-extension-host agent))
      (when message
        (append-agent-message-with-events
         agent message))
      (multiple-value-bind
            (replacement appended blocked-p reason)
          (run-extension-hooks
           (agent-extension-host agent)
           :turn-start
           :turn-index turn-index
           :message message)
        (declare (ignore blocked-p reason))
        (when replacement
          (append-agent-message-with-events
           agent replacement))
        (append-agent-messages-with-events
         agent appended))))

(defun run-turn-end-hooks
    (agent turn-index message results)
  (if (not (agent-extension-host agent))
      (values message nil)
      (multiple-value-bind
            (replacement appended blocked-p reason)
          (run-extension-hooks
           (agent-extension-host agent)
           :turn-end
           :turn-index turn-index
           :message message
           :tool-results results)
        (declare (ignore blocked-p reason))
        (values replacement appended))))

(defun commit-agent-turn
    (agent message results
     tool-hook-messages turn-hook-messages)
  ;; The assistant stream already emitted its message lifecycle. Hooks run
  ;; before this function so only the final payload reaches the session.
  (append-agent-message agent message)
  (dolist (result results)
    (append-agent-message agent result))
  (append-agent-messages-with-events
   agent tool-hook-messages)
  (append-agent-messages-with-events
   agent turn-hook-messages))

(defun run-agent-loop (agent user-message)
  (emit-agent-event agent :agent-start)
  (begin-agent-turn agent 1 user-message)
  (loop with overflow-recovery-attempted-p = nil
        for turn from 1
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
              (emit-agent-event agent :agent-end)
              (return-from run-agent-loop
                final-message))))
        (let* ((session (agent-session agent))
               (parent-leaf-id
                 (and session
                      (session-leaf-id session)))
               (streamed-message
                 (stream-assistant agent))
               (calls
                 (assistant-tool-calls
                  streamed-message))
               (results nil)
               (tool-hook-messages nil)
               (retry-overflow-p nil)
               (terminal-p
                 (member
                  (cadr-ai:assistant-message-stop-reason
                   streamed-message)
                  '(:error :aborted))))
          (when (and calls (not terminal-p))
            (multiple-value-setq
                (results tool-hook-messages)
              (if
                  (eq
                   :length
                   (cadr-ai:assistant-message-stop-reason
                    streamed-message))
                  (execute-truncated-tool-batch
                   agent calls :turn-index turn)
                  (execute-tool-batch
                   agent calls :turn-index turn))))
          (multiple-value-bind
                (message turn-hook-messages)
              (run-turn-end-hooks
               agent turn streamed-message results)
            (commit-agent-turn
             agent message results
             tool-hook-messages
             turn-hook-messages)
            (emit-agent-event
             agent :turn-end :message message
             :tool-results results)
            (when
                (and session
                     parent-leaf-id
                     (not overflow-recovery-attempted-p)
                     (context-overflow-message-p
                      streamed-message))
              (let ((error-leaf-id
                      (session-leaf-id session)))
                (setf
                 overflow-recovery-attempted-p t)
                (session-branch
                 session parent-leaf-id)
                (setf
                 (agent-messages agent)
                 (session-messages session))
                (if
                    (compact-agent agent :force-p t)
                    (progn
                      (setf retry-overflow-p t)
                      (begin-agent-turn
                       agent (1+ turn) nil))
                    (progn
                      (session-branch
                       session error-leaf-id)
                      (setf
                       (agent-messages agent)
                       (session-messages session))))))
            (unless retry-overflow-p
              (when terminal-p
                (emit-agent-event agent :agent-end)
                (return message))
              (if calls
                  (begin-agent-turn
                   agent (1+ turn) nil)
                  (progn
                    (emit-agent-event agent :agent-end)
                    (return message))))))))

(defun agent-prompt (agent prompt)
  (let ((message
          (etypecase prompt
            (string (cadr-ai:make-user-message :content prompt))
            (cadr-ai:user-message prompt))))
    (sb-thread:with-mutex
        ((agent-state-lock agent))
      (when (agent-busy-p agent)
        (error 'agent-busy-error
               :message "Agent is already processing a prompt"))
      (setf (agent-busy-p agent) t))
    (unwind-protect
         (run-agent-loop agent message)
      (sb-thread:with-mutex
          ((agent-state-lock agent))
        (setf (agent-busy-p agent) nil)))))
