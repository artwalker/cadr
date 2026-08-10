(in-package #:cadr-agent/tests)
(in-suite cadr-agent-suite)

(test goal18-nil-model-prompt-fails-with-baseline-guidance
  ;; Baseline agent-session.ts:1181-1192 — with the unknown sentinel
  ;; model the auth check fails before any append, throwing
  ;; formatNoApiKeyFoundMessage("unknown").
  (let ((agent
          (make-agent
           :provider :mock
           :model nil)))
    (handler-case
        (progn
          (cadr-agent:agent-prompt agent "hello")
          (is nil "nil-model prompt did not signal"))
      (cadr-ai:configuration-error (condition)
        (is (string=
             (cadr-ai::no-api-key-found-message "unknown")
             (cadr-ai:cadr-error-message condition)))
        (is (search
             "No API key found for the selected model."
             (cadr-ai:cadr-error-message condition)))))
    (is (null (agent-messages agent))
        "nil-model prompt must not append the user message")))

(test goal11-agent-message-append-maintains-o1-tail-invariant
  (let* ((initial
           (list
            (cadr-ai:make-user-message :content "first")))
         (agent
           (make-agent
            :provider :mock
            :model (mock-model)
            :messages initial))
         (first-tail
           (cadr-agent::agent-messages-tail agent)))
    (is (eq (agent-messages agent)
            (cadr-agent::agent-messages-tail-head agent)))
    (is (eq first-tail (last (agent-messages agent))))
    (cadr-agent::agent-append-message
     agent
     (cadr-ai:make-user-message :content "second"))
    (is (eq (cdr first-tail)
            (cadr-agent::agent-messages-tail agent)))
    (is (null
         (cdr (cadr-agent::agent-messages-tail agent))))
    (is (equal '("first" "second")
               (mapcar
                #'cadr-ai:user-message-content
                (agent-messages agent))))
    ;; Public accessors allow callers to replace the list. The next append
    ;; repairs the private tail once and then resumes constant-time appends.
    (let ((replacement
            (list
             (cadr-ai:make-user-message :content "replacement"))))
      (setf (agent-messages agent) replacement)
      (cadr-agent::agent-append-message
       agent
       (cadr-ai:make-user-message :content "after-replacement"))
      (is (eq replacement
              (cadr-agent::agent-messages-tail-head agent)))
      (is (equal '("replacement" "after-replacement")
                 (mapcar
                  #'cadr-ai:user-message-content
                  (agent-messages agent)))))))

(test simple-turn-emits-reference-lifecycle-order
  (let ((*responses*
          (list
           (assistant
            (list (make-text-content :text "Hello")))))
        (*contexts* nil)
        (events nil))
    (declare (special *responses* *contexts*))
    (let ((agent
            (make-agent
             :provider :mock
             :model (mock-model)
             :stream-function
             (faux-stream '*responses* '*contexts*)
             :on-event (lambda (event) (push event events)))))
      (agent-prompt agent "Hi")
      (setf events (nreverse events))
      (is (equal
           '(:agent-start :turn-start
             :message-start :message-end
             :message-start :message-update :message-end
             :turn-end :agent-end :agent-settled)
           (event-types events)))
      (is (= 2 (length (agent-messages agent))))
      (is (string= "Hello"
                   (text-content-text
                    (first
                     (assistant-message-content
                      (second (agent-messages agent))))))))))

(test goal17-agent-end-messages-exclude-preexisting-context
  (let* ((old-user
           (cadr-ai:make-user-message :content "old request"))
         (old-assistant
           (assistant
            (list (make-text-content :text "old answer"))))
         (*responses*
           (list
            (assistant
             (list (make-text-content :text "new answer")))))
         (*contexts* nil)
         (events nil))
    (declare (special *responses* *contexts*))
    (let ((agent
            (make-agent
             :provider :mock
             :model (mock-model)
             :messages (list old-user old-assistant)
             :stream-function
             (faux-stream '*responses* '*contexts*)
             :on-event (lambda (event) (push event events)))))
      (agent-prompt agent "new request")
      (let* ((event
               (find :agent-end events
                     :key #'agent-event-type))
             (messages
               (cadr-agent:agent-event-messages event)))
        (is (= 2 (length messages)))
        (is
         (string=
          "new request"
          (cadr-ai:user-message-content (first messages))))
        (is
         (string=
          "new answer"
          (cadr-ai:text-content-text
           (first
            (cadr-ai:assistant-message-content
             (second messages))))))
        (is-false (member old-user messages :test #'eq))
        (is-false (member old-assistant messages :test #'eq))))))

(test error-and-abort-stop-the-run-cleanly
  (dolist (reason '(:error :aborted))
    (let ((*responses* (list (assistant nil reason)))
          (*contexts* nil)
          (events nil))
      (declare (special *responses* *contexts*))
      (let ((agent
              (make-agent
               :provider :mock
               :model (mock-model)
               :stream-function
               (faux-stream '*responses* '*contexts*)
               :on-event (lambda (event) (push event events)))))
        (agent-prompt agent "Hi")
        (is (= 2 (length (agent-messages agent))))
        (is (= 1 (count :turn-end (event-types events))))
        (is (= 1 (count :agent-end (event-types events))))))))

(test goal17-terminal-abort-preserves-last-partial-content-and-usage
  ;; Fixed pi@74caa2649 faux.ts:288-297,313-344 turns the last partial into
  ;; the aborted terminal message.  Providers may return a sparse terminal
  ;; object, so the agent must preserve content and usage already observed.
  (let* ((partial
           (make-assistant-message
            :api :mock :provider :openai :model "mock"
            :content
            (list (make-text-content :text "partial response"))
            :usage
            (cadr-ai:make-usage
             :input 1300 :output 14 :cache-write 1300)
            :stop-reason :pending))
         (terminal
           (make-assistant-message
            :api :mock :provider :openai :model "mock"
            :stop-reason :aborted
            :error-message "Request was aborted"))
         (agent
           (make-agent
            :provider :mock
            :model (mock-model)
            :stream-function
            (lambda (provider model context on-event &rest options)
              (declare
               (ignore provider model context options))
              (funcall
               on-event
               (make-stream-event
                :type :start :message partial))
              (funcall
               on-event
               (make-stream-event
                :type :text-delta
                :delta "partial response"
                :message partial))
              terminal))))
    (agent-prompt agent "stop this stream")
    (let ((committed (car (last (agent-messages agent)))))
      (is (eq :aborted
              (assistant-message-stop-reason committed)))
      (is (string= "Request was aborted"
                   (cadr-ai:assistant-message-error-message
                    committed)))
      (is (string= "partial response"
                   (text-content-text
                    (first
                     (assistant-message-content committed)))))
      (is (= 1300
             (cadr-ai:usage-input
              (cadr-ai:assistant-message-usage committed))))
      (is (= 14
             (cadr-ai:usage-output
              (cadr-ai:assistant-message-usage committed))))
      (is (= 1300
             (cadr-ai:usage-cache-write
              (cadr-ai:assistant-message-usage committed)))))))

(test goal17-provider-error-terminal-payload-remains-authoritative
  (let* ((partial
           (make-assistant-message
            :api :mock :provider :openai :model "mock"
            :content
            (list (make-text-content :text "partial response"))
            :usage (cadr-ai:make-usage :input 1300)
            :stop-reason :pending))
         (terminal
           (make-assistant-message
            :api :mock :provider :openai :model "mock"
            :content
            (list (make-text-content :text "provider final"))
            :usage (cadr-ai:make-usage :input 17 :output 3)
            :stop-reason :error
            :error-message "render transport failed"))
         (agent
           (make-agent
            :provider :mock
            :model (mock-model)
            :stream-function
            (lambda (provider model context on-event &rest options)
              (declare
               (ignore provider model context options))
              (funcall
               on-event
               (make-stream-event
                :type :start :message partial))
              terminal))))
    (agent-prompt agent "trigger provider error")
    (let ((committed (car (last (agent-messages agent)))))
      (is (eq :error
              (assistant-message-stop-reason committed)))
      (is (string= "render transport failed"
                   (cadr-ai:assistant-message-error-message
                    committed)))
      (is (string= "provider final"
                   (text-content-text
                    (first
                     (assistant-message-content committed)))))
      (is (= 17
             (cadr-ai:usage-input
              (cadr-ai:assistant-message-usage committed))))
      (is (= 3
             (cadr-ai:usage-output
              (cadr-ai:assistant-message-usage committed)))))))
