(in-package #:cadr-agent/tests)
(in-suite cadr-agent-suite)

(test goal24-abort-skips-post-run-auto-compaction
  ;; Baseline #9340 (de2de549b): abort on assistant message_end must not
  ;; start post-run threshold compaction. Settings mirror the pi harness
  ;; (auto-compact on, small keep-recent, retry disabled) so compaction
  ;; would run without the abort.
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((session
             (cadr-agent:create-session
              :directory sessions :cwd cwd
              :id "goal24-abort-skips-auto-compact"))
           (_old-user
             (cadr-agent:session-append-message
              session
              (cadr-ai:make-user-message
               :content (make-string 120 :initial-element #\x))))
           (_old-assistant
             (cadr-agent:session-append-message
              session
              (cadr-ai:make-assistant-message
               :content
               (list (cadr-ai:make-text-content :text "old"))
               :api :openai-responses :provider :openai :model "tiny"
               :usage (cadr-ai:make-usage :input 70 :total 70)
               :stop-reason :stop)))
           (*responses*
             (list
              (cadr-ai:make-assistant-message
               :content
               (list
                (cadr-ai:make-text-content
                 :text (make-string 80 :initial-element #\e)))
               :api :openai-responses :provider :openai :model "tiny"
               :usage (cadr-ai:make-usage)
               :stop-reason :error
               :error-message "Synthetic network failure")
              (compaction-test-response "history summary" :stop)
              (compaction-test-response "turn prefix summary" :stop)))
           (*contexts* nil)
           (events nil)
           (agent nil))
      (declare
       (ignore _old-user _old-assistant)
       (special *responses* *contexts*))
      (setf agent
            (cadr-agent:make-agent
             :provider :mock
             :model (compaction-test-model)
             :session session
             :auto-compact-p t
             :auto-retry-p nil
             :compaction-reserve-tokens 20
             :compaction-keep-recent-tokens 1
             :stream-function
             (faux-stream '*responses* '*contexts*)
             :on-event
             (lambda (event)
               (push event events)
               (when
                   (and
                    (eq :message-end
                        (cadr-agent:agent-event-type event))
                    (typep
                     (cadr-agent:agent-event-message event)
                     'cadr-ai:assistant-message))
                 (cadr-agent:agent-abort-compaction agent)
                 (cadr-agent:agent-abort agent)))))
      (let ((result
              (cadr-agent:agent-prompt
               agent (make-string 80 :initial-element #\z))))
        (is
         (eq :error
             (cadr-ai:assistant-message-stop-reason result)))
        (is
         (zerop
          (count :compaction-start events
                 :key #'cadr-agent:agent-event-type)))
        (is
         (zerop
          (count :compaction
                 (cadr-agent:session-entries session)
                 :key #'cadr-agent:session-entry-type)))))))

(test goal24-will-retry-false-when-abort-requested
  (let* ((message
           (retry-error-message "network error"))
         (agent
           (cadr-agent:make-agent
            :provider :mock
            :model (mock-model)
            :auto-retry-p t
            :auto-retry-max-attempts 3)))
    (is-true (cadr-agent::agent-will-retry-p agent message))
    (setf (cadr-agent::agent-abort-requested-p agent) t)
    (is-false (cadr-agent::agent-will-retry-p agent message))))
