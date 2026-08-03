(in-package #:cadr-agent)

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

