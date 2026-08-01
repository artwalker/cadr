(in-package #:cadr-agent)

(defvar *agent-run-system-prompt* :use-agent-system-prompt)

(defparameter +non-retryable-assistant-error-pattern+
  (cl-ppcre:create-scanner
   "(GoUsageLimitError|FreeUsageLimitError|Monthly usage limit reached|available balance|insufficient_quota|out of budget|quota exceeded|billing)"
   :case-insensitive-mode t))

(defparameter +retryable-assistant-error-pattern+
  (cl-ppcre:create-scanner
   "(overloaded|rate.?limit|too many requests|429|500|502|503|504|524|service.?unavailable|server.?error|internal.?error|provider.?returned.?error|network.?error|connection.?error|connection.?refused|connection.?lost|other side closed|fetch failed|getaddrinfo|ENOTFOUND|EAI_AGAIN|upstream.?connect|reset before headers|socket hang up|socket connection was closed|timed? out|timeout|terminated|websocket.?closed|websocket.?error|ended without|stream ended before message_stop|stream ended before a terminal response event|http2 request did not get a response|retry delay|you can retry your request|try your request again|please retry your request|ResourceExhausted)"
   :case-insensitive-mode t))

(defun retryable-assistant-error-p (message)
  (when
      (and
       (typep message 'cadr-ai:assistant-message)
       (eq :error
           (cadr-ai:assistant-message-stop-reason
            message))
       (cadr-ai:assistant-message-error-message
        message)
       (not (context-overflow-message-p message)))
    (let ((text
            (cadr-ai:assistant-message-error-message
             message)))
      (and
       (not
        (cl-ppcre:scan
         +non-retryable-assistant-error-pattern+
         text))
       (not
        (null
         (cl-ppcre:scan
          +retryable-assistant-error-pattern+
          text)))))))

(defun agent-will-retry-p (agent message)
  (and
   (agent-auto-retry-p agent)
   (< (agent-retry-attempt agent)
      (agent-auto-retry-max-attempts agent))
   (retryable-assistant-error-p message)))

(defun last-agent-assistant-message (agent)
  (find-if
   (lambda (message)
     (typep message 'cadr-ai:assistant-message))
   (agent-messages agent)
   :from-end t))

(defun run-agent-lifecycle (agent event &optional payload)
  (let ((host (agent-extension-host agent)))
    (and
     host
     (run-extension-lifecycle-hooks
      host event :payload payload))))

(defun ensure-agent-session-started (agent)
  (let ((host (agent-extension-host agent)))
    (when
        (and host
             (not
              (extension-host-session-started-p host)))
      (setf
       (extension-host-session-started-p host)
       t)
      (run-extension-lifecycle-hooks
       host :session-start
       :payload '(:reason :startup)))))

(defun current-agent-system-prompt (agent)
  (if (eq *agent-run-system-prompt*
          :use-agent-system-prompt)
      (agent-system-prompt agent)
      *agent-run-system-prompt*))

(defun lifecycle-message-end (agent message)
  (let ((result
          (run-agent-lifecycle
           agent :message-end
           (list :message message))))
    (or (getf result :message) message)))

(defun emit-message-start (agent message)
  (run-agent-lifecycle
   agent :message-start
   (list :message message))
  (emit-agent-event
   agent :message-start :message message))

(defun emit-message-update
    (agent message stream-event)
  (run-agent-lifecycle
   agent :message-update
   (list
    :message message
    :assistant-message-event stream-event))
  (emit-agent-event
   agent :message-update
   :message message
   :stream-event stream-event))

(defun emit-message-end (agent message)
  (let ((final
          (lifecycle-message-end agent message)))
    (emit-agent-event
     agent :message-end :message final)
    (when
        (and
         (typep final 'cadr-ai:assistant-message)
         (not
          (eq :error
              (cadr-ai:assistant-message-stop-reason
               final)))
         (plusp (agent-retry-attempt agent)))
      (let ((attempt
              (agent-retry-attempt agent)))
        (setf (agent-retry-attempt agent) 0)
        (emit-agent-event
         agent :auto-retry-end
         :success t
         :attempt attempt)))
    final))

(defun ensure-agent-messages-tail (agent)
  (let ((messages (agent-messages agent)))
    (cond
      ((null messages)
       (setf
        (agent-messages-tail agent) nil
        (agent-messages-tail-head agent) nil))
      ((or
        (not
         (eq messages
             (agent-messages-tail-head agent)))
        (null (agent-messages-tail agent))
        (not
         (null
          (cdr (agent-messages-tail agent)))))
       (setf
        (agent-messages-tail agent) (last messages)
        (agent-messages-tail-head agent) messages))))
  (agent-messages-tail agent))

(defun append-agent-message (agent message)
  (when (agent-session agent)
    (session-append-message
     (agent-session agent) message))
  (let ((cell (list message)))
    (if (agent-messages agent)
        (setf
         (cdr (ensure-agent-messages-tail agent)) cell
         (agent-messages-tail agent) cell)
        (setf
         (agent-messages agent) cell
         (agent-messages-tail agent) cell
         (agent-messages-tail-head agent) cell)))
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
  (let ((call (tool-outcome-call outcome))
        (result (tool-outcome-result outcome)))
    (run-agent-lifecycle
     agent :tool-execution-end
     (list
      :tool-call-id (cadr-ai:tool-call-id call)
      :tool-name (cadr-ai:tool-call-name call)
      :result result
      :error-p
      (cadr-ai:tool-result-message-is-error result))))
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
          do
          (let* ((initial
                   (tool-outcome-result outcome))
                 (result
                   (progn
                     (emit-message-start
                      agent initial)
                     (emit-message-end
                      agent initial))))
            (setf
             (tool-outcome-result outcome)
             result)
            (push result results)))
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
    (run-agent-lifecycle
     agent :tool-execution-start
     (list
      :tool-call-id (cadr-ai:tool-call-id call)
      :tool-name (cadr-ai:tool-call-name call)
      :arguments (cadr-ai:tool-call-arguments call)))
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
          (run-agent-lifecycle
           agent :tool-execution-start
           (list
            :tool-call-id (cadr-ai:tool-call-id call)
            :tool-name (cadr-ai:tool-call-name call)
            :arguments
            (cadr-ai:tool-call-arguments call)))
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
  (let* ((started-p nil)
         (messages (copy-list (agent-messages agent)))
         (context-result
           (run-agent-lifecycle
            agent :context
            (list :messages messages)))
         (request-messages
           (or
            (getf context-result :messages)
            messages)))
    (let* ((callback
             (lambda (event)
               (case (cadr-ai:stream-event-type event)
                 (:start
                  (setf started-p t)
                  (emit-message-start
                   agent
                   (cadr-ai:stream-event-message event)))
                 ((:text-start :text-delta :text-end
                   :thinking-start :thinking-delta :thinking-end
                   :tool-call-start :tool-call-delta :tool-call-end)
                  (emit-message-update
                   agent
                   (cadr-ai:stream-event-message event)
                   event)))))
           (options
             (list
              :abort-p
              (lambda ()
                (agent-aborted-p agent))))
           (message
             (let ((context
                     (cadr-ai:make-context
                      :system-prompt
                      (current-agent-system-prompt agent)
                      :messages request-messages
                      :tools
                      (registry-tools
                       (agent-tool-registry agent)))))
               (if
                   (eq :off
                       (agent-thinking-level agent))
                   (funcall
                    (agent-stream-function agent)
                    (agent-provider agent)
                    (agent-model agent)
                    context callback
                    :abort-p (second options))
                   (funcall
                    (agent-stream-function agent)
                    (agent-provider agent)
                    (agent-model agent)
                    context callback
                    :reasoning
                    (agent-thinking-level agent)
                    :abort-p (second options))))))
      (unless started-p
        (emit-message-start agent message))
      (emit-message-end agent message))))

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
  (emit-message-start agent message)
  (let ((final (emit-message-end agent message)))
    (append-agent-message agent final)
    final))

(defun append-agent-messages-with-events
    (agent messages)
  (dolist (message messages)
    (append-agent-message-with-events
     agent message))
  messages)

(defun begin-agent-turn-message
    (agent turn-index message)
  (if (not (agent-extension-host agent))
      (append-agent-message-with-events
       agent message)
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

(defun begin-agent-turn
    (agent turn-index messages)
  (emit-agent-event agent :turn-start)
  (dolist
      (message
       (cond
         ((null messages) nil)
         ((listp messages) messages)
         (t (list messages))))
    (begin-agent-turn-message
     agent turn-index message)))

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

(defun emit-agent-end (agent)
  (run-agent-lifecycle
   agent :agent-end
   (list :messages
         (copy-list (agent-messages agent))))
  (emit-agent-event
   agent :agent-end
   :messages (copy-list (agent-messages agent))
   :will-retry
   (agent-will-retry-p
    agent
    (last-agent-assistant-message agent))))

(defun remove-retry-error-from-agent-state (agent)
  (let ((messages (agent-messages agent)))
    (when
        (and
         messages
         (typep
          (car (last messages))
          'cadr-ai:assistant-message))
      (setf
       (agent-messages agent)
       (butlast messages))))
  agent)

(defun wait-for-agent-retry (agent delay)
  (let ((deadline
          (+ (get-internal-real-time)
             (round
              (* delay
                 internal-time-units-per-second)))))
    (sb-thread:with-mutex
        ((agent-state-lock agent))
      (loop
        (when (agent-retry-abort-requested-p agent)
          (return nil))
        (let ((remaining
                (/ (- deadline
                      (get-internal-real-time))
                   internal-time-units-per-second)))
          (when (<= remaining 0)
            (return t))
          (unless
              (sb-thread:condition-wait
               (agent-retry-condition agent)
               (agent-state-lock agent)
               :timeout remaining)
            (return t)))))))

(defun prepare-agent-retry (agent message)
  (unless (agent-will-retry-p agent message)
    (return-from prepare-agent-retry nil))
  (incf (agent-retry-attempt agent))
  (let* ((attempt
           (agent-retry-attempt agent))
         (delay
           (* (agent-auto-retry-base-delay agent)
              (expt 2 (1- attempt))))
         (delay-ms
           (round (* delay 1000))))
    (remove-retry-error-from-agent-state agent)
    (sb-thread:with-mutex
        ((agent-state-lock agent))
      (setf
       (agent-retry-in-progress-p agent) t
       (agent-retry-abort-requested-p agent) nil))
    (emit-agent-event
     agent :auto-retry-start
     :attempt attempt
     :max-attempts
     (agent-auto-retry-max-attempts agent)
     :delay-ms delay-ms
     :error-message
     (or
      (cadr-ai:assistant-message-error-message
       message)
      "Unknown error"))
    (let ((completed-p
            (wait-for-agent-retry agent delay)))
      (sb-thread:with-mutex
          ((agent-state-lock agent))
        (setf
         (agent-retry-in-progress-p agent) nil
         (agent-retry-abort-requested-p agent) nil))
      (unless completed-p
        (setf (agent-retry-attempt agent) 0)
        (emit-agent-event
         agent :auto-retry-end
         :success nil
         :attempt attempt
         :final-error "Retry cancelled"))
      completed-p)))

(defun finish-agent-retry-failure (agent message)
  (when (plusp (agent-retry-attempt agent))
    (let ((attempt
            (agent-retry-attempt agent)))
      (setf (agent-retry-attempt agent) 0)
      (emit-agent-event
       agent :auto-retry-end
       :success nil
       :attempt attempt
       :final-error
       (and
        (typep message 'cadr-ai:assistant-message)
        (cadr-ai:assistant-message-error-message
         message)))))
  message)

(defun run-agent-with-retries
    (agent initial-messages)
  (loop
    for messages = initial-messages then nil
    for result = (run-agent-loop agent messages)
    do
    (cond
      ((and
        (retryable-assistant-error-p result)
        (prepare-agent-retry agent result)))
      ((and
        (typep result 'cadr-ai:assistant-message)
        (eq :error
            (cadr-ai:assistant-message-stop-reason
             result)))
       (return
        (finish-agent-retry-failure
         agent result)))
      (t
       (return result)))))

(defun run-agent-loop (agent initial-messages)
  (run-agent-lifecycle agent :agent-start)
  (emit-agent-event agent :agent-start)
  (begin-agent-turn agent 1 initial-messages)
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
              (emit-agent-end agent)
              (return-from run-agent-loop
                final-message))))
        (let* ((session (agent-session agent))
               (parent-leaf-id
                 (and session
                      (session-leaf-id session)))
               (streamed-message (stream-assistant agent))
               (calls
                 (assistant-tool-calls streamed-message))
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
             agent :turn-end
             :message message
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
                (session-branch session parent-leaf-id)
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
              (cond
                (terminal-p
                 (emit-agent-end agent)
                 (return-from run-agent-loop message))
                (t
                 (let ((steering
                         (drain-agent-queue
                          agent :steering)))
                   (cond
                     ((or calls steering)
                      (begin-agent-turn
                       agent (1+ turn) steering))
                     (t
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
                                     agent
                                     (1+ turn)
                                     late-follow-up)
                                    (return-from
                                        run-agent-loop
                                      message))))))))))))))))

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

(defun agent-navigate-tree (agent entry-id)
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
       (let ((before
               (run-agent-lifecycle
                agent :session-before-tree
                (list
                 :target-id entry-id
                 :summarize-p nil))))
         (when (getf before :cancel-p)
           (return-from agent-navigate-tree
             (values nil t)))
         (assert-agent-not-shutdown agent)
         (session-branch session entry-id)
         (setf
          (agent-messages agent)
          (session-messages session))
         (run-agent-lifecycle
          agent :session-tree
          (list
           :target-id entry-id
           :messages
           (copy-list
            (agent-messages agent))))
         (values
          (copy-list
           (agent-messages agent))
          nil))))))

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
                 :system-prompt-options nil))))
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
