(in-package #:cadr-agent)

(defun merge-terminal-assistant-partial
    (message partial)
  (if
      (and
       partial
       (typep message 'cadr-ai:assistant-message)
       (typep partial 'cadr-ai:assistant-message)
       (member
        (cadr-ai:assistant-message-stop-reason message)
        '(:aborted :error)))
      (let* ((message-content
               (cadr-ai:assistant-message-content message))
             (partial-content
               (cadr-ai:assistant-message-content partial))
             (message-usage
               (cadr-ai:assistant-message-usage message))
             (partial-usage
               (cadr-ai:assistant-message-usage partial))
             (inherit-content-p
               (and (null message-content)
                    partial-content))
             (inherit-usage-p
               (and
                (zerop (cadr-ai:usage-total message-usage))
                (plusp (cadr-ai:usage-total partial-usage)))))
        (if (or inherit-content-p inherit-usage-p)
            (let ((merged (copy-structure message)))
              (when inherit-content-p
                (setf
                 (cadr-ai:assistant-message-content merged)
                 (copy-list partial-content)))
              (when inherit-usage-p
                (setf
                 (cadr-ai:assistant-message-usage merged)
                 partial-usage))
              merged)
            message))
      message))

(defun stream-assistant (agent)
  (let* ((started-p nil)
         (last-partial nil)
         (messages (copy-list (agent-messages agent)))
         (context-result
           (run-agent-lifecycle
            agent :context
            (list :messages messages)))
         ;; pi@ecac0a9c4 agent-loop.ts:295 converts agent-level
         ;; messages to LLM messages when building the provider
         ;; context (config.convertToLlm).  Without the conversion,
         ;; bash-execution/custom/branch-summary/compaction-summary
         ;; records never reach the provider: their content is
         ;; invisible to the model and to faux usage accounting.
         (request-messages
           (convert-agent-messages-to-llm
            (or
             (getf context-result :messages)
             messages))))
    (let* ((callback
             (lambda (event)
               (case (cadr-ai:stream-event-type event)
                 (:start
                  (setf
                   started-p t
                   last-partial
                   (cadr-ai:stream-event-message event))
                  (emit-message-start
                   agent
                   (cadr-ai:stream-event-message event)))
                 ((:text-start :text-delta :text-end
                   :thinking-start :thinking-delta :thinking-end
                   :tool-call-start :tool-call-delta :tool-call-end)
                  (setf
                   last-partial
                   (cadr-ai:stream-event-message event))
                  (emit-message-update
                   agent
                   (cadr-ai:stream-event-message event)
                   event)))))
           (abort-p
             (lambda ()
               (agent-aborted-p agent)))
           (message
             (if (agent-aborted-p agent)
                 ;; pi@ecac0a9c4 — an abort already pending when the
                 ;; turn reaches the provider call (the escape-during-
                 ;; tool-execution case) ends the turn with the
                 ;; AbortError text and never invokes the provider;
                 ;; v0.83 made the call and let it abort mid-stream.
                 (cadr-ai:make-assistant-message
                  :api (cadr-ai:model-api (agent-model agent))
                  :provider
                  (cadr-ai:model-provider (agent-model agent))
                  :model (cadr-ai:model-id (agent-model agent))
                  :stop-reason :error
                  :error-message "This operation was aborted")
                 (let ((context
                         (cadr-ai:make-context
                          :system-prompt
                          (current-agent-system-prompt agent)
                          :messages request-messages
                          :tools
                          (registry-tools
                           (agent-tool-registry agent)))))
                   ;; abort-p is a keyword on the stream call, not a
                   ;; one-field plist built to be read back (TS
                   ;; object-literal leftover).
                   (if
                       (eq :off
                           (agent-thinking-level agent))
                       (funcall
                        (agent-stream-function agent)
                        (agent-provider agent)
                        (agent-model agent)
                        context callback
                        :abort-p abort-p)
                       (funcall
                        (agent-stream-function agent)
                        (agent-provider agent)
                        (agent-model agent)
                        context callback
                        :reasoning
                        (agent-thinking-level agent)
                        :abort-p abort-p))))))
      (let ((final
              (merge-terminal-assistant-partial
               message last-partial)))
        (unless started-p
          (emit-message-start agent final))
        (emit-message-end agent final)))))

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
  (let ((messages
          (if *agent-run-new-messages*
              (coerce *agent-run-new-messages* 'list)
              nil)))
    (run-agent-lifecycle
     agent :agent-end
     (list :messages messages))
    (emit-agent-event
     agent :agent-end
     :messages messages
     :will-retry
     (agent-will-retry-p
      agent
      (last-agent-assistant-message agent)))))

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
  (loop with overflow-recovery-attempted-p = nil
    for messages = initial-messages then nil
    for result =
      (let ((*agent-run-new-messages*
              (make-array
               0 :adjustable t :fill-pointer 0)))
        (run-agent-loop agent messages))
    do
    (cond
      ((context-overflow-message-p result)
       (cond
         (overflow-recovery-attempted-p
          (let ((error-message
                  "Context overflow recovery failed after one compact-and-retry attempt. Try reducing context or switching to a larger-context model."))
            (emit-agent-event
             agent :compaction-end
             :reason :overflow
             :result nil
             :aborted nil
             :will-retry nil
             :error-message error-message)
            (emit-session-compact-failed
             agent
             :reason :overflow
             :error-message error-message
             :aborted nil
             :will-retry-p nil
             :from-extension-p nil)
            (return result)))
         ((or (null (agent-session agent))
              (agent-shutdown-p agent))
          (return result))
         (t
          (setf overflow-recovery-attempted-p t)
          ;; The failed assistant message remains durable in the session, but
          ;; baseline continuation removes it from the live provider context.
          (remove-retry-error-from-agent-state agent)
          (if (%compact-agent
               agent :force-p t
               :reason :overflow
               :will-retry-p t)
              (remove-retry-error-from-agent-state agent)
              (return result)))))
      ((and
        (retryable-assistant-error-p result)
        (prepare-agent-retry agent result)))
      ((and
        (typep result 'cadr-ai:assistant-message)
        (eq :error
            (cadr-ai:assistant-message-stop-reason
             result)))
       (let ((final
               (finish-agent-retry-failure
                agent result)))
         (unless
             (or
              (context-overflow-message-p final)
              (agent-shutdown-p agent))
           (maybe-compact-agent agent))
         (return final)))
      (t
       (unless
           (or
            (and
             (typep result 'cadr-ai:assistant-message)
             (eq :aborted
                 (cadr-ai:assistant-message-stop-reason result)))
            (agent-shutdown-p agent))
         (maybe-compact-agent agent))
       (return result)))))
