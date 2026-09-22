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

(defun request-prompt-and-tools (agent original final)
  (cond
    ((agent-system-message-p (first final))
     (let ((head (current-system-message final)))
       (values
        (agent-system-message-content head)
        (or
         (agent-system-message-tools-added head)
         (registry-tools (agent-tool-registry agent))))))
    ((some #'agent-system-message-p original)
     (values nil nil))
    (t
     (values
      (current-agent-system-prompt agent)
      (registry-tools (agent-tool-registry agent))))))

(defun stream-assistant (agent)
  (let* ((started-p nil)
         (last-partial nil)
         (messages (copy-list (agent-messages agent)))
         (context-result
           (run-agent-lifecycle
            agent :context
            (list :messages messages)))
         (after-context
           (or (getf context-result :messages) messages))
         (system-result
           (run-agent-lifecycle
            agent :context-with-system
            (list :messages after-context)))
         (final-messages
           (or (getf system-result :messages) after-context))
         ;; pi@16787ad5b agent-loop.ts:295 converts agent-level
         ;; messages to LLM messages when building the provider
         ;; context (config.convertToLlm).  Without the conversion,
         ;; bash-execution/custom/branch-summary/compaction-summary
         ;; records never reach the provider: their content is
         ;; invisible to the model and to faux usage accounting.
         (request-messages
           (convert-agent-messages-to-llm
            (conversation-messages final-messages))))
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
                 ;; pi@16787ad5b — an abort already pending when the
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
                 (multiple-value-bind
                       (prompt tools)
                     (request-prompt-and-tools
                      agent messages final-messages)
                   (let ((context
                           (cadr-ai:make-context
                            :system-prompt prompt
                            :messages request-messages
                            :tools tools)))
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
                        :abort-p abort-p)))))))
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

(defun agent-activity-outcome (message)
  (cond
    ((and
      (typep message 'cadr-ai:assistant-message)
      (eq :aborted
          (cadr-ai:assistant-message-stop-reason message)))
     :aborted)
    ((and
      (typep message 'cadr-ai:assistant-message)
      (eq :error
          (cadr-ai:assistant-message-stop-reason message)))
     :error)
    (t :completed)))

(defun allocate-boundary-entry-ids (session count)
  (let ((seen (make-hash-table :test #'equal)))
    (loop repeat count
          collect
          (loop
            for id = (make-session-entry-id
                      (session-by-id session))
            unless (gethash id seen)
              do (setf (gethash id seen) t)
              and return id))))

(defun agent-has-queued-messages-p (agent)
  (or (agent-steering-queue agent)
      (agent-follow-up-queue agent)
      (agent-next-turn-queue agent)))

(defun boundary-message-role (message)
  (cond
    ((typep message 'cadr-ai:user-message) :user)
    ((typep message 'cadr-ai:assistant-message) :assistant)
    ((typep message 'cadr-ai:tool-result-message) :tool-result)
    (t nil)))

(defun boundary-can-continue-p (agent boundary)
  (let* ((messages (agent-messages agent))
         (last (car (last messages)))
         (role (and last (boundary-message-role last)))
         (context-can-continue-p
           (and messages (not (eq role :assistant))))
         (queued-p (agent-has-queued-messages-p agent)))
    (or context-can-continue-p
        (if (eq boundary :turn-end)
            queued-p
            (and (eq role :assistant) queued-p)))))

(defun report-invalid-boundary-continuation (agent event)
  (let ((host (agent-extension-host agent)))
    (when host
      (funcall
       (extension-host-notify-function host)
       (format nil
               "~A requested continuation without runnable model context"
               event)
       :error))))

(defun apply-boundary-drafts (agent drafts)
  (when drafts
    (let ((session (agent-session agent)))
      (unless session
        (session-failure
         nil nil
         "Boundary entries require a session"))
      (dolist (draft drafts)
        (ecase (getf draft :type)
          (:custom
           (session-append-custom
            session
            (getf draft :custom-type)
            (getf draft :data)))
          (:custom-message
           (session-append-custom-message
            session
            (getf draft :custom-type)
            (getf draft :content)
            :details (getf draft :details)
            :display-p (getf draft :display-p)))
          (:context-edit
           (session-append-context-edit
            session
            (getf draft :target-id)
            (getf draft :replacement)))
          (:compaction
           (session-append-compaction
            session
            (getf draft :summary)
            nil
            (getf draft :first-kept-id)
            0
            :details (getf draft :details)
            :usage (getf draft :usage)
            :from-hook-p t))))
      (setf (agent-messages agent)
            (session-messages session))))
  drafts)

(defun extension-host-has-hook-p (host event)
  (and
   host
   (gethash
    event
    (extension-snapshot-hooks
     (extension-host-current-snapshot host)))))

(defun continue-after-before-settle-p (agent message)
  (let ((host (agent-extension-host agent)))
    (unless (extension-host-has-hook-p
             host :agent-before-settle)
      (return-from continue-after-before-settle-p
        (agent-has-queued-messages-p agent)))
    (let ((result
            (run-extension-lifecycle-hooks
             host :agent-before-settle
             :payload
             (list
              :outcome
              (agent-activity-outcome message)))))
      (handler-case
          (apply-boundary-drafts
           agent (getf result :entries))
        (condition (condition)
          (funcall
           (extension-host-notify-function host)
           (format nil
                   "agent_before_settle invalid boundary entries: ~A"
                   condition)
           :error)
          (return-from continue-after-before-settle-p nil)))
      (let ((should-continue-p
              (or (getf result :continue)
                  (agent-has-queued-messages-p agent))))
        (cond
          ((and
            should-continue-p
            (not
             (boundary-can-continue-p
              agent :agent-before-settle)))
           (when (getf result :continue)
             (report-invalid-boundary-continuation
              agent "agent_before_settle"))
           nil)
          (t should-continue-p))))))

(defun accept-turn-boundary (agent entries continue-p)
  (handler-case
      (apply-boundary-drafts agent entries)
    (condition (condition)
      (let ((host (agent-extension-host agent)))
        (when host
          (funcall
           (extension-host-notify-function host)
           (format nil
                   "turn_end invalid boundary entries: ~A"
                   condition)
           :error)))
      (return-from accept-turn-boundary nil)))
  (cond
    ((not continue-p) nil)
    ((boundary-can-continue-p agent :turn-end) t)
    (t
     (report-invalid-boundary-continuation
      agent "turn_end")
     nil)))

(defun run-turn-end-hooks
    (agent turn-index message results
     &key message-entry-id tool-result-entry-ids)
  (if (not (agent-extension-host agent))
      (values message nil nil nil)
      (multiple-value-bind
            (replacement appended blocked-p reason
             terminate-p terminate-supplied-p
             entries continue-p)
          (run-extension-hooks
           (agent-extension-host agent)
           :turn-end
           :turn-index turn-index
           :message message
           :tool-results results
           :outcome (agent-activity-outcome message)
           :message-entry-id message-entry-id
           :tool-result-entry-ids tool-result-entry-ids)
        (declare
         (ignore blocked-p reason terminate-p
                 terminate-supplied-p))
        (values
         (or replacement message)
         appended
         entries
         continue-p))))

(defun commit-agent-turn
    (agent message results
     tool-hook-messages turn-hook-messages
     &key message-id result-ids)
  ;; The assistant stream already emitted its message lifecycle. Hooks run
  ;; before this function so only the final payload reaches the session.
  (append-agent-message agent message :id message-id)
  (loop for result in results
        for id in (or result-ids
                      (make-list (length results)
                                 :initial-element nil))
        do (append-agent-message agent result :id id))
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
         (let ((settled
                 (finish-agent-run agent final)))
           (when settled
             (return settled)))))
      (t
       (unless
           (or
            (and
             (typep result 'cadr-ai:assistant-message)
             (eq :aborted
                 (cadr-ai:assistant-message-stop-reason result)))
            (agent-shutdown-p agent))
         (maybe-compact-agent agent))
       (let ((settled
               (finish-agent-run agent result)))
         (when settled
           (return settled)))))))

(defun finish-agent-run (agent result)
  (cond
    ((or
      (agent-shutdown-p agent)
      (and
       (typep result 'cadr-ai:assistant-message)
       (eq :aborted
           (cadr-ai:assistant-message-stop-reason result))))
     result)
    ((continue-after-before-settle-p agent result)
     nil)
    (t result)))
