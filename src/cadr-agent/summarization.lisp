(in-package #:cadr-agent)

(defun summarization-retry-policy (agent)
  (cadr-ai:make-retry-policy
   :enabled-p (agent-auto-retry-p agent)
   :max-retries (agent-auto-retry-max-attempts agent)
   :base-delay-milliseconds
   (round (* 1000 (agent-auto-retry-base-delay agent)))
   :max-agent-delay-milliseconds
   (agent-auto-retry-max-delay-ms agent)))

(defun wait-for-summarization-retry (agent seconds)
  (let ((deadline
          (+ (get-internal-real-time)
             (round (* seconds internal-time-units-per-second)))))
    (loop
      (when (agent-aborted-p agent)
        (return nil))
      (let ((remaining
              (/ (- deadline (get-internal-real-time))
                 internal-time-units-per-second)))
        (when (<= remaining 0)
          (return t))
        (sleep (min remaining 0.01d0))))))

(defun make-empty-aborted-summary-response (agent)
  (cadr-ai:make-assistant-message
   :api (and (agent-model agent)
             (cadr-ai:model-api (agent-model agent)))
   :provider (or (and (agent-model agent)
                      (cadr-ai:model-provider (agent-model agent)))
                 (agent-provider agent))
   :model (or (and (agent-model agent)
                   (cadr-ai:model-id (agent-model agent)))
              "")
   :content nil
   :usage (cadr-ai:make-usage)
   :stop-reason :aborted))

(defun complete-summarization
    (agent context max-tokens source &key reason reasoning)
  "The single owner of retry, cache, and routing policy for summary requests."
  (let ((session-id (make-session-id))
        (no-response-p nil))
    (let ((response
            (cadr-ai:retry-assistant-call
             (lambda ()
               (if (agent-aborted-p agent)
                   (make-empty-aborted-summary-response agent)
                   (let ((captured
                           (agent-compaction-request-model agent)))
                     (multiple-value-bind
                           (request-model request-provider
                            request-thinking route-error)
                         (cond
                           ((and captured (virtual-model-p captured))
                            ;; v1.4.0 resolveModel(selectedModel,
                            ;; convertToLlm(this.messages), {reason:"direct"}).
                            ;; The summary prompt is the stream context,
                            ;; not the route input. A later model swap
                            ;; does not replace this selection.
                            (agent-stream-target
                             agent
                             (convert-agent-messages-to-llm
                              (agent-messages agent))
                             :reason :direct
                             :model captured))
                           (captured
                            (values
                             captured
                             (agent-provider agent)
                             (agent-thinking-level agent)
                             nil))
                           (t
                            (agent-stream-target
                             agent
                             (cadr-ai:context-messages context)
                             :reason :direct)))
                       (cond
                         (route-error
                          (cadr-ai:make-assistant-message
                           :api (cadr-ai:model-api (agent-model agent))
                           :provider
                           (cadr-ai:model-provider (agent-model agent))
                           :model (cadr-ai:model-id (agent-model agent))
                           :stop-reason :error
                           :error-message route-error))
                         (t
                          (let ((level
                                  (if (or (and captured
                                               (virtual-model-p captured))
                                          (virtual-model-p
                                           (agent-model agent)))
                                      (and (not (eq request-thinking :off))
                                           request-thinking)
                                      reasoning)))
                          (or
                           (apply
                            (agent-stream-function agent)
                            request-provider
                            request-model
                            context
                            (lambda (event) (declare (ignore event)))
                            :max-tokens max-tokens
                            :cache-retention :none
                            :session-id session-id
                            :abort-p (lambda () (agent-aborted-p agent))
                            (and level (list :reasoning level)))
                           (progn
                             (setf no-response-p t)
                             (make-empty-aborted-summary-response
                              agent))))))))))
             (summarization-retry-policy agent)
             :abort-p (lambda () (agent-aborted-p agent))
             :sleep-function
             (lambda (seconds)
               (wait-for-summarization-retry agent seconds))
             :on-retry-scheduled
             (lambda (attempt maximum delay error-message)
               (emit-agent-event
                agent :summarization-retry-scheduled
                :attempt attempt
                :max-attempts maximum
                :delay-ms delay
                :error-message error-message))
             :on-retry-attempt-start
             (lambda ()
               (emit-agent-event
                agent :summarization-retry-attempt-start
                :source source
                :reason reason))
             :on-retry-finished
             (lambda (success attempt final-error)
               (declare (ignore success attempt final-error))
               (emit-agent-event
                agent :summarization-retry-finished)))))
      (unless no-response-p response))))
