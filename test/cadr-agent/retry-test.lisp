(in-package #:cadr-agent/tests)
(in-suite cadr-agent-suite)

(defun retry-error-message (text)
  (make-assistant-message
   :content nil
   :api :openai-responses
   :provider :openai
   :model "mock"
   :stop-reason :error
   :error-message text))

(test explicit-provider-and-transport-guidance-remains-retryable
  (dolist
      (message
       '("Network connection lost."
         "getaddrinfo ENOTFOUND api.example.com"
         "EAI_AGAIN api.example.com"
         "You can retry your request, or contact support."
         "{\"message\":\"Try your request again.\"}"))
    (is
     (cadr-agent::retryable-assistant-error-p
      (retry-error-message message)))))

(test v130-transient-wording-retries-and-subscription-limits-do-not
  (dolist
      (message
       '("The service is temporarily unavailable. Please retry later."
         "Service unavailable: The service is temporarily unavailable."
         "Unable to forward upstream stream"
         "The upstream provider returned an error"
         "The pending stream has been canceled"
         "520 status code (no body)"
         "subscription_sharing_usage_unavailable: Usage cannot be checked."
         "The system is currently experiencing high demand"))
    (is
     (cadr-agent::retryable-assistant-error-p
      (retry-error-message message))))
  (is
   (not
    (cadr-agent::retryable-assistant-error-p
     (retry-error-message
      "OpenAI API error (429): {\"code\":\"subscription_sharing_usage_limit_exceeded\",\"message\":\"Usage limit reached.\"}")))))

(test chatgpt-business-workspace-limit-is-not-retried-by-the-session-loop
  ;; Same sentence as packages/ai/test/retry.test.ts at v1.4.0.
  ;; The session loop keeps its own copy of the non-retryable set.
  (is
   (not
    (cadr-agent::retryable-assistant-error-p
     (retry-error-message
      "OpenAI API error (429): {\"code\":\"subscription_sharing_workplace_individual_usage_limit_exceeded\",\"message\":\"Usage limit reached.\"}")))))

(test v140-session-retry-matches-gateway-vertex-and-codex-disconnect
  ;; Session loop mirrors packages/ai/src/utils/retry.ts at v1.4.0.
  (dolist
      (message
       '("request to https://oauth2.googleapis.com/token failed, reason:"
         "upstream_error: Upstream request failed"
         "upstream_stream_read_error: Upstream response stream was interrupted"
         "Upstream HTTP/2 stream failed"
         "stream disconnected before completion: stream closed before response.completed"
         "524 status code (no body)"))
    (is
     (cadr-agent::retryable-assistant-error-p
      (retry-error-message message))))
  (dolist
      (message
       '("401 {\"type\":\"error\",\"error\":{\"type\":\"authentication_error\",\"message\":\"invalid x-api-key\"},\"request_id\":\"req_011CU503xyz\"}"
         "400 image exceeds 5 MB maximum: 5316784 bytes > 5242880 bytes"))
    (is
     (not
      (cadr-agent::retryable-assistant-error-p
       (retry-error-message message))))))

(test transient-assistant-errors-retry-and-report-recovery
  (let ((*responses*
          (list
           (retry-error-message "overloaded_error")
           (assistant
            (list
             (make-text-content :text "recovered")))))
        (*contexts* nil)
        (events nil))
    (declare (special *responses* *contexts*))
    (let ((agent
            (make-agent
             :provider :mock
             :model (mock-model)
             :stream-function
             (faux-stream '*responses* '*contexts*)
             :on-event
             (lambda (event)
               (push event events)))))
      (setf
       (cadr-agent::agent-auto-retry-max-attempts agent)
       3
       (cadr-agent::agent-auto-retry-base-delay agent)
       0)
      (agent-prompt agent "retry me")
      (setf events (nreverse events))
      (is (= 2 (length *contexts*)))
      (is
       (equal
        '(t nil)
        (loop for event in events
              when
              (eq :agent-end
                  (agent-event-type event))
                collect
                (cadr-agent::agent-event-will-retry
                 event))))
      (let ((runs
              (loop for event in events
                    when (eq :agent-end
                             (agent-event-type event))
                      collect (cadr-agent:agent-event-messages event))))
        (is (= 2 (length (first runs))))
        (is (typep (first (first runs))
                   'cadr-ai:user-message))
        (is (eq :error
                (cadr-ai:assistant-message-stop-reason
                 (second (first runs)))))
        (is (= 1 (length (second runs))))
        (is
         (string=
          "recovered"
          (cadr-ai:text-content-text
           (first
            (cadr-ai:assistant-message-content
             (first (second runs))))))))
      (is
       (equal
        '((:start 1 3 0 "overloaded_error")
          (:end t 1 nil))
        (loop for event in events
              when
              (eq :auto-retry-start
                  (agent-event-type event))
                collect
                (list
                 :start
                 (cadr-agent::agent-event-attempt event)
                 (cadr-agent::agent-event-max-attempts event)
                 (cadr-agent::agent-event-delay-ms event)
                 (cadr-agent:agent-event-error-message
                  event))
              when
              (eq :auto-retry-end
                  (agent-event-type event))
                collect
                (list
                 :end
                 (cadr-agent::agent-event-success event)
                 (cadr-agent::agent-event-attempt event)
                 (cadr-agent::agent-event-final-error
                  event)))))
      (is (= 2 (length (agent-messages agent))))
      (is (null *responses*))
      (is
       (= 1
          (count
           :agent-settled events
           :key #'agent-event-type))))))

(test retry-budget-exhaustion-and-nonretryable-errors
  (let ((*responses*
          (list
           (retry-error-message "503 service unavailable")
           (retry-error-message "network connection lost")
           (retry-error-message "524 status code")))
        (*contexts* nil)
        (events nil))
    (declare (special *responses* *contexts*))
    (let ((agent
            (make-agent
             :provider :mock
             :model (mock-model)
             :stream-function
             (faux-stream '*responses* '*contexts*)
             :on-event
             (lambda (event)
               (push event events)))))
      (setf
       (cadr-agent::agent-auto-retry-max-attempts agent)
       2
       (cadr-agent::agent-auto-retry-base-delay agent)
       0)
      (agent-prompt agent "retry me")
      (setf events (nreverse events))
      (is (= 3 (length *contexts*)))
      (is
       (equal
        '(t t nil)
        (loop for event in events
              when
              (eq :agent-end
                  (agent-event-type event))
                collect
                (cadr-agent::agent-event-will-retry
                 event))))
      (let ((final
              (find
               :auto-retry-end events
               :key #'agent-event-type)))
        (is (not (null final)))
        (is
         (not
          (cadr-agent::agent-event-success final)))
        (is (= 2
               (cadr-agent::agent-event-attempt final)))
        (is
         (string=
          "524 status code"
          (cadr-agent::agent-event-final-error
           final))))))
  (dolist
      (text
       '("invalid_api_key"
         "429 quota exceeded"
         "billing limit reached"
         "context_length_exceeded"))
    (let ((*responses*
            (list (retry-error-message text)))
          (*contexts* nil)
          (events nil))
      (declare (special *responses* *contexts*))
      (let ((agent
              (make-agent
               :provider :mock
               :model (mock-model)
               :stream-function
               (faux-stream '*responses* '*contexts*)
               :on-event
               (lambda (event)
                 (push event events)))))
        (setf
         (cadr-agent::agent-auto-retry-base-delay agent)
         0)
        (agent-prompt agent "do not retry"))
      (is (= 1 (length *contexts*)))
      (is
       (null
        (find
         :auto-retry-start events
         :key #'agent-event-type))))))

(test abort-retry-interrupts-backoff-and-settles-agent
  (let* ((responses
           (list
            (retry-error-message
             "getaddrinfo ENOTFOUND api.invalid")))
         (contexts nil)
         (events nil)
         (retry-started
           (sb-thread:make-semaphore :count 0))
         (agent nil)
         (thread nil))
    (setf
     agent
     (make-agent
      :provider :mock
      :model (mock-model)
      :stream-function
      (lambda
          (provider model context on-event
           &key max-tokens temperature abort-p)
        (declare
         (ignore
          provider model max-tokens temperature
          abort-p))
        (push context contexts)
        (let ((message (pop responses)))
          (funcall
           on-event
           (make-stream-event
            :type :start
            :message message))
          message))
      :on-event
      (lambda (event)
        (push event events)
        (when
            (eq :auto-retry-start
                (agent-event-type event))
          (sb-thread:signal-semaphore
           retry-started)))))
    (setf
     (cadr-agent::agent-auto-retry-max-attempts agent)
     3
     (cadr-agent::agent-auto-retry-base-delay agent)
     10)
    (setf
     thread
     (sb-thread:make-thread
      (lambda ()
        (agent-prompt agent "cancel retry"))
      :name "cadr-agent-retry-abort-test"))
    (sb-thread:wait-on-semaphore retry-started)
    (cadr-agent::agent-abort-retry agent)
    (sb-thread:join-thread thread)
    (setf events (nreverse events))
    (is (= 1 (length contexts)))
    (is
     (not
      (cadr-agent:agent-busy-p agent)))
    (let ((final
            (find
             :auto-retry-end events
             :key #'agent-event-type)))
      (is (not (null final)))
      (is
       (not
        (cadr-agent::agent-event-success final)))
      (is
       (string=
        "Retry cancelled"
        (cadr-agent::agent-event-final-error
         final))))))
