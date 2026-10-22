(in-package #:cadr-agent/tests)
(in-suite cadr-agent-suite)

(defun goal24-seed-compactable-session (session)
  (cadr-agent:session-append-message
   session
   (cadr-ai:make-user-message
    :content (make-string 80 :initial-element #\x)))
  (cadr-agent:session-append-message
   session
   (compaction-test-response
    (make-string 80 :initial-element #\y) :stop))
  (cadr-agent:session-append-message
   session
   (cadr-ai:make-user-message :content "keep")))

(test goal24-cancels-summarization-authentication
  ;; Baseline #9777 cancels summarization authentication: getAuth hangs
  ;; on AbortSignal; abort must abort that signal; compaction_end.aborted.
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((auth-started (sb-thread:make-semaphore :count 0))
           (auth-signal nil)
           (auth-aborted-p nil)
           (events nil)
           (session
             (cadr-agent:create-session
              :directory sessions :cwd cwd
              :id "goal24-auth-abort"))
           (compact-result :unset)
           (agent nil))
      (goal24-seed-compactable-session session)
      (setf agent
            (cadr-agent:make-agent
             :provider :mock
             :model (compaction-test-model)
             :session session
             :compaction-keep-recent-tokens 1
             :summarization-auth-function
             (lambda (auth-agent model signal)
               (declare (ignore auth-agent model))
               (setf auth-signal signal)
               (sb-thread:signal-semaphore auth-started)
               (let* ((state
                        (cadr-agent::%extension-cancellation-signal-state
                         signal))
                      (wait-result
                        (cadr-core:wait-for-cancellation
                         state :timeout 5.0d0)))
                 (setf auth-aborted-p (eq :aborted wait-result))
                 (error "Authentication aborted")))
             :on-event (lambda (event) (push event events))
             :stream-function
             (lambda (&rest arguments)
               (declare (ignore arguments))
               (error "aborted auth must not summarize"))))
      (let ((thread
              (sb-thread:make-thread
               (lambda ()
                 (setf compact-result
                       (cadr-agent:compact-agent
                        agent :force-p t :reason :threshold)))
               :name "goal24-auth-compact")))
        (sb-thread:wait-on-semaphore auth-started :timeout 5)
        (let ((started
                (count :compaction-start events
                       :key #'cadr-agent:agent-event-type))
              (was-compacting
                (not
                 (null
                  (cadr-agent::agent-compaction-cancellation
                   agent)))))
          (cadr-agent:agent-abort agent)
          (sb-thread:join-thread thread :timeout 5)
          (is (= 1 started))
          (is-true was-compacting)
          (is-true auth-aborted-p)
          (is-true
           (and auth-signal
                (cadr-agent:extension-cancellation-aborted-p
                 auth-signal)))
          (is-false compact-result)
          (let ((end
                  (find :compaction-end events
                        :key #'cadr-agent:agent-event-type)))
            (is (not (null end)))
            (is-true (cadr-agent:agent-event-aborted end))))))))

(test goal24-cancels-synchronously-from-compaction-start
  ;; Baseline #9777 cancels synchronously from compaction_start.
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((summary-calls 0)
           (events nil)
           (session
             (cadr-agent:create-session
              :directory sessions :cwd cwd
              :id "goal24-sync-abort"))
           (agent nil))
      (goal24-seed-compactable-session session)
      (setf agent
            (cadr-agent:make-agent
             :provider :mock
             :model (compaction-test-model)
             :session session
             :compaction-keep-recent-tokens 1
             :summarization-auth-function
             (lambda (&rest arguments)
               (declare (ignore arguments))
               (error "sync abort must not reach summarization auth"))
             :on-event
             (lambda (event)
               (push event events)
               (when
                   (eq :compaction-start
                       (cadr-agent:agent-event-type event))
                 (cadr-agent:agent-abort-compaction agent)))
             :stream-function
             (lambda (&rest arguments)
               (declare (ignore arguments))
               (incf summary-calls)
               (error "sync abort must not summarize"))))
      (is-false
       (cadr-agent:compact-agent
        agent :force-p t :reason :threshold))
      (is (zerop summary-calls))
      (let ((end
              (find :compaction-end events
                    :key #'cadr-agent:agent-event-type)))
        (is (not (null end)))
        (is-true (cadr-agent:agent-event-aborted end))))))

(test goal24-reports-auth-abort-text-as-failure
  ;; Baseline #9777: AbortError / "Compaction cancelled" text without a
  ;; real abort signal is a failure (aborted false), not cancelled.
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (dolist
        (message
         '("Compaction cancelled"
           "auth failed"))
      (let* ((events nil)
             (session
               (cadr-agent:create-session
                :directory sessions :cwd cwd
                :id
                (format nil "goal24-auth-fail-~A"
                        (sxhash message))))
             (agent nil))
        (goal24-seed-compactable-session session)
        (setf agent
              (cadr-agent:make-agent
               :provider :mock
               :model (compaction-test-model)
               :session session
               :compaction-keep-recent-tokens 1
               :summarization-auth-function
               (lambda (&rest arguments)
                 (declare (ignore arguments))
                 (error "~A" message))
               :on-event (lambda (event) (push event events))
               :stream-function
               (lambda (&rest arguments)
                 (declare (ignore arguments))
                 (error "auth failure must not summarize"))))
        (is-false
         (cadr-agent:compact-agent
          agent :force-p t :reason :threshold))
        (let ((end
                (find :compaction-end events
                      :key #'cadr-agent:agent-event-type)))
          (is (not (null end)))
          (is-false (cadr-agent:agent-event-aborted end))
          (is
           (search
            message
            (cadr-agent:agent-event-error-message end))))))))

(test goal24-reports-extension-cancellation-as-aborted
  ;; Baseline #9777: session_before_compact cancel → aborted true.
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((events nil)
           (bundle
             (make-test-extension-bundle
              "goal24-before-compact-cancel"
              (lambda ()
                (cadr-agent:define-event-hook
                 :session-before-compact
                 :handler
                 (lambda (event context)
                   (declare (ignore event context))
                   '(:cancel-p t))))))
           (host (make-test-extension-host (list bundle)))
           (session
             (cadr-agent:create-session
              :directory sessions :cwd cwd
              :id "goal24-extension-cancel"))
           (agent nil))
      (goal24-seed-compactable-session session)
      (setf agent
            (cadr-agent:make-agent
             :provider :mock
             :model (compaction-test-model)
             :session session
             :extension-host host
             :compaction-keep-recent-tokens 1
             :on-event (lambda (event) (push event events))
             :stream-function
             (lambda (&rest arguments)
               (declare (ignore arguments))
               (error "extension cancel must not summarize"))))
      (is-false
       (cadr-agent:compact-agent
        agent :force-p t :reason :threshold))
      (let ((end
              (find :compaction-end events
                    :key #'cadr-agent:agent-event-type)))
        (is (not (null end)))
        (is-true (cadr-agent:agent-event-aborted end))))))
