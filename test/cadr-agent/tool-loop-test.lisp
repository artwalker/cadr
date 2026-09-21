(in-package #:cadr-agent/tests)
(in-suite cadr-agent-suite)

(test tool-call-result-and-next-model-turn-complete
  (let* ((executed nil)
         (tool
           (make-tool
            :name "echo"
            :description "Echo"
            :parameters (object-schema "value")
            :execution-mode :parallel
            :executor
            (lambda (call-id arguments)
              (declare (ignore call-id))
              (push (cadr-ai::json-get arguments "value") executed)
              (list (make-text-content :text "echoed")))))
         (*responses*
           (list
            (assistant
             (list
              (make-tool-call
               :id "call_1"
               :name "echo"
               :arguments (cadr-ai::json-object "value" "hello")))
             :tool-use)
            (assistant
             (list (make-text-content :text "done")))))
         (*contexts* nil)
         (events nil))
    (declare (special *responses* *contexts*))
    (let ((agent
            (make-agent
             :provider :mock
             :model (mock-model)
             :tools (list tool)
             :stream-function
             (faux-stream '*responses* '*contexts*)
             :on-event (lambda (event) (push event events)))))
      (agent-prompt agent "echo")
      (is (equal '("hello") executed))
      (let ((transcript (agent-messages-without-system agent)))
        (is (= 4 (length transcript)))
        (is (typep (third transcript) 'tool-result-message))
        (is (not (tool-result-message-is-error
                  (third transcript)))))
      (setf events (nreverse events))
      (is (equal
           '(:agent-start :turn-start :message-start :message-end
             :message-start :message-end
             :tool-execution-start :tool-execution-end
             :message-start :message-end :turn-end
             :turn-start :message-start :message-update :message-end
             :turn-end :agent-end :agent-settled)
           (event-types events)))
      (let ((messages
              (cadr-agent:agent-event-messages
               (find :agent-end events
                     :key #'agent-event-type))))
        (is (= 4 (length messages)))
        (is (typep (first messages) 'cadr-ai:user-message))
        (is (typep (second messages) 'cadr-ai:assistant-message))
        (is (typep (third messages) 'cadr-ai:tool-result-message))
        (is (typep (fourth messages) 'cadr-ai:assistant-message)))
      (let ((second-context (first *contexts*)))
        (is (typep (third (cadr-ai:context-messages second-context))
                   'tool-result-message))))))

(test pairing-agent-tool-loop-observed-stays-put
  ;; scripts/goal20-paired-paths.lisp agent_tool_loop.roundtrip.
  ;; Drives shipped agent-prompt, not a reimplementation.
  (let* ((executed nil)
         (tool
           (make-tool
            :name "echo"
            :description "Echo"
            :parameters (object-schema "value")
            :execution-mode :parallel
            :executor
            (lambda (call-id arguments)
              (declare (ignore call-id))
              (setf executed (cadr-ai::json-get arguments "value"))
              (list (make-text-content :text "echoed")))))
         (*responses*
           (list
            (assistant
             (list
              (make-tool-call
               :id "call_1"
               :name "echo"
               :arguments (cadr-ai::json-object "value" "hello")))
             :tool-use)
            (assistant
             (list (make-text-content :text "done")))))
         (*contexts* nil))
    (declare (special *responses* *contexts*))
    (let ((agent
            (make-agent
             :provider :mock
             :model (mock-model)
             :tools (list tool)
             :auto-compact-p nil
             :stream-function
             (faux-stream '*responses* '*contexts*))))
      (agent-prompt agent "echo")
      (let* ((messages (agent-messages-without-system agent))
             (result (third messages))
             (last (car (last messages))))
        (is (string= "hello" executed))
        (is (= 4 (length messages)))
        (is (not (tool-result-message-is-error result)))
        (is (string=
             "done"
             (text-content-text
              (first (assistant-message-content last)))))))))

(test unknown-invalid-and-length-truncated-tools-become-error-results
  (let ((executions 0))
    (dolist (case '(:unknown :invalid :length))
      (let* ((tool
               (make-tool
                :name "echo"
                :description "Echo"
                :parameters (object-schema "value")
                :executor
                (lambda (call-id arguments)
                  (declare (ignore call-id arguments))
                  (incf executions)
                  (list (make-text-content :text "bad")))))
             (name (if (eq case :unknown) "missing" "echo"))
             (arguments
               (if (eq case :invalid)
                   (cadr-ai::json-object)
                   (cadr-ai::json-object "value" "truncated")))
             (*responses*
               (list
                (assistant
                 (list
                  (make-tool-call
                   :id "call_bad"
                   :name name
                   :arguments arguments))
                 (if (eq case :length) :length :tool-use))
                (assistant
                 (list (make-text-content :text "recovered")))))
             (*contexts* nil))
        (declare (special *responses* *contexts*))
        (let ((agent
                (make-agent
                 :provider :mock
                 :model (mock-model)
                 :tools (list tool)
                 :stream-function
                 (faux-stream '*responses* '*contexts*))))
          (agent-prompt agent "run")
          (let ((result
                  (first-tool-result-message
                   (agent-messages agent))))
            (is (tool-result-message-is-error result))
            (is (plusp (length (text-result result))))))))
    (is (= 0 executions))))

(test all-parallel-tools-finish-by-completion-but-results-stay-in-source-order
  (let* ((finish-order nil)
         (slow-started
           (sb-thread:make-semaphore :count 0))
         (release-slow
           (sb-thread:make-semaphore :count 0))
         (slow
           (make-tool
            :name "slow"
            :description "Slow"
            :parameters (object-schema)
            :execution-mode :parallel
            :executor
            (lambda (call-id arguments)
              (declare (ignore arguments))
              (sb-thread:signal-semaphore slow-started)
              (sb-thread:wait-on-semaphore release-slow)
              (push call-id finish-order)
              (list (make-text-content :text "slow")))))
         (fast
           (make-tool
            :name "fast"
            :description "Fast"
            :parameters (object-schema)
            :execution-mode :parallel
            :executor
            (lambda (call-id arguments)
              (declare (ignore arguments))
              (sb-thread:wait-on-semaphore slow-started)
              (push call-id finish-order)
              (list (make-text-content :text "fast")))))
         (*responses*
           (list
            (assistant
             (list
              (make-tool-call
               :id "slow_1" :name "slow"
               :arguments (cadr-ai::json-object))
              (make-tool-call
               :id "fast_1" :name "fast"
               :arguments (cadr-ai::json-object)))
             :tool-use)
            (assistant (list (make-text-content :text "done")))))
         (*contexts* nil)
         (events nil))
    (declare (special *responses* *contexts*))
    (let ((agent
            (make-agent
             :provider :mock
             :model (mock-model)
             :tools (list slow fast)
             :stream-function
             (faux-stream '*responses* '*contexts*)
             :on-event
             (lambda (event)
               (push event events)
               (when
                   (and
                    (eq :tool-execution-end
                        (agent-event-type event))
                    (string=
                     "fast_1"
                     (cadr-ai:tool-call-id
                      (agent-event-tool-call event))))
                 (sb-thread:signal-semaphore
                  release-slow))))))
      (agent-prompt agent "run")
      (is (equal '("slow_1" "fast_1") finish-order))
      (let ((result-ids
              (loop for message in (agent-messages agent)
                    when (typep message 'tool-result-message)
                      collect
                      (tool-result-message-tool-call-id message))))
        (is (equal '("slow_1" "fast_1") result-ids)))
      (let ((end-ids
              (loop for event in (nreverse events)
                    when (eq :tool-execution-end
                             (agent-event-type event))
                      collect
                      (cadr-ai:tool-call-id
                       (agent-event-tool-call event)))))
        (is (equal '("fast_1" "slow_1") end-ids))))))

(test one-sequential-tool-forces-the-whole-batch-sequential
  (let ((first-done nil)
        (second-saw-first nil))
    (let* ((first
             (make-tool
              :name "first"
              :description "First"
              :parameters (object-schema)
              :execution-mode :sequential
              :executor
              (lambda (call-id arguments)
                (declare (ignore call-id arguments))
                (setf first-done t)
                (list (make-text-content :text "first")))))
           (second
             (make-tool
              :name "second"
              :description "Second"
              :parameters (object-schema)
              :execution-mode :parallel
              :executor
              (lambda (call-id arguments)
                (declare (ignore call-id arguments))
                (setf second-saw-first first-done)
                (list (make-text-content :text "second")))))
           (*responses*
             (list
              (assistant
               (list
                (make-tool-call :id "1" :name "first"
                                :arguments (cadr-ai::json-object))
                (make-tool-call :id "2" :name "second"
                                :arguments (cadr-ai::json-object)))
               :tool-use)
              (assistant (list (make-text-content :text "done")))))
           (*contexts* nil))
      (declare (special *responses* *contexts*))
      (let ((agent
              (make-agent
               :provider :mock
               :model (mock-model)
               :tools (list first second)
               :stream-function
               (faux-stream '*responses* '*contexts*))))
        (agent-prompt agent "run")
        (is (not (null second-saw-first)))))))

(test goal10-busy-parallel-tool-abort-reaches-all-running-executors
  (let ((started
          (sb-thread:make-semaphore :count 0))
        (finished
          (sb-thread:make-semaphore :count 0))
        (executors-finished 0)
        (stream-calls 0)
        (agent nil)
        (worker nil))
    (labels
        ((blocking-tool (name)
           (make-tool
            :name name
            :description name
            :parameters (object-schema)
            :execution-mode :parallel
            :executor
            (lambda (call-id arguments)
              (declare (ignore call-id arguments))
              (sb-thread:signal-semaphore started)
              (loop until
                    (cadr-agent::current-tool-aborted-p)
                    do (sleep 0.001))
              (incf executors-finished)
              (error "Operation aborted")))))
      (let* ((first (blocking-tool "first"))
             (second (blocking-tool "second"))
             (stream
               (lambda
                   (provider model context on-event
                    &key max-tokens temperature abort-p)
                 (declare
                  (ignore provider model context
                          max-tokens temperature))
                 (incf stream-calls)
                 (let ((message
                         (if (= stream-calls 1)
                             (assistant
                              (list
                               (make-tool-call
                                :id "parallel-1" :name "first"
                                :arguments (cadr-ai::json-object))
                               (make-tool-call
                                :id "parallel-2" :name "second"
                                :arguments (cadr-ai::json-object)))
                              :tool-use)
                             (assistant
                              nil
                              (if (and abort-p (funcall abort-p))
                                  :aborted
                                  :stop)))))
                   (funcall
                    on-event
                    (make-stream-event
                     :type :start :message message))
                   message))))
        (setf
         agent
         (make-agent
          :provider :mock
          :model (mock-model)
          :tools (list first second)
          :stream-function stream)
         worker
         (sb-thread:make-thread
          (lambda ()
            (unwind-protect
                 (agent-prompt agent "run both")
              (sb-thread:signal-semaphore finished)))
          :name "cadr-parallel-abort-test"))
        (is (sb-thread:wait-on-semaphore started :timeout 2))
        (is (sb-thread:wait-on-semaphore started :timeout 2))
        (cadr-agent:agent-abort agent)
        (is (sb-thread:wait-on-semaphore finished :timeout 5))
        (sb-thread:join-thread worker)
        (is (= 2 executors-finished))
        (let ((results
                (remove-if-not
                 (lambda (message)
                   (typep message 'tool-result-message))
                 (agent-messages agent))))
          (is (= 2 (length results)))
          (is (every #'tool-result-message-is-error results)))
        (is-false (cadr-agent:agent-busy-p agent))))))

(test goal10-tool-execution-condition-keeps-stack-live-and-retries-with-new-arguments
  (let ((cleanup-ran-p nil)
        (attempts nil)
        (condition-seen-p nil))
    (let* ((tool
             (make-tool
              :name "restartable"
              :description "Restartable"
              :parameters (object-schema "value")
              :execution-mode :sequential
              :executor
              (lambda (call-id arguments)
                (declare (ignore call-id))
                (let ((value
                        (cadr-ai::json-get arguments "value")))
                  (push value attempts)
                  (unwind-protect
                       (if (string= value "bad")
                           (error "executor exploded")
                           (list (make-text-content :text value)))
                    (setf cleanup-ran-p t))))))
           (bundle
             (make-test-extension-bundle
              "restart-condition"
              (lambda ()
                (cadr-agent:define-event-hook
                 :tool-call-error
                 :handler
                 (lambda (event context)
                   (declare (ignore context))
                   (let* ((payload
                            (cadr-agent:extension-event-payload event))
                          (condition (getf payload :condition)))
                     (setf condition-seen-p
                           (typep condition
                                  'cadr-agent:tool-execution-error))
                     (is-false cleanup-ran-p)
                     (is-true
                      (find-restart
                       'cadr-agent:retry-tool-call))
                     (list
                      :action :retry
                      :arguments
                      (cadr-ai::json-object
                       "value" "good"))))))))
           (host (make-test-extension-host (list bundle)))
           (*responses*
             (list
              (assistant
               (list
                (make-tool-call
                 :id "restart-1" :name "restartable"
                 :arguments
                 (cadr-ai::json-object "value" "bad")))
               :tool-use)
              (assistant
               (list (make-text-content :text "done")))))
           (*contexts* nil)
           (agent
             (make-agent
              :provider :mock
              :model (mock-model)
              :tools (list tool)
              :extension-host host
              :stream-function
              (faux-stream '*responses* '*contexts*))))
      (declare (special *responses* *contexts*))
      (agent-prompt agent "run")
      (is-true condition-seen-p)
      (is-true cleanup-ran-p)
      (is (equal '("bad" "good")
                 (nreverse attempts)))
      (let ((result
              (first-tool-result-message
               (agent-messages agent))))
        (is-false (tool-result-message-is-error result))
        (is (string= "good" (text-result result)))))))

(test goal10-schema-failure-skip-preserves-the-old-result-text
  (let ((condition-message nil))
    (let* ((bundle
             (make-test-extension-bundle
              "skip-condition"
              (lambda ()
                (cadr-agent:define-event-hook
                 :tool-call-error
                 :handler
                 (lambda (event context)
                   (declare (ignore context))
                   (setf condition-message
                         (cadr-ai:cadr-error-message
                          (getf
                           (cadr-agent:extension-event-payload event)
                           :condition)))
                   (is-true
                    (find-restart
                     'cadr-agent:skip-tool-call))
                   (list :action :skip))))))
           (host (make-test-extension-host (list bundle)))
           (tool
             (make-tool
              :name "schema"
              :description "Schema"
              :parameters (object-schema "value")
              :executor
              (lambda (call-id arguments)
                (declare (ignore call-id arguments))
                (error "must not execute"))))
           (*responses*
             (list
              (assistant
               (list
                (make-tool-call
                 :id "schema-1" :name "schema"
                 :arguments (cadr-ai::json-object)))
               :tool-use)
              (assistant
               (list (make-text-content :text "done")))))
           (*contexts* nil)
           (agent
             (make-agent
              :provider :mock
              :model (mock-model)
              :tools (list tool)
              :extension-host host
              :stream-function
              (faux-stream '*responses* '*contexts*))))
      (declare (special *responses* *contexts*))
      (agent-prompt agent "run")
      (let ((result
              (first-tool-result-message
               (agent-messages agent))))
        (is-true (tool-result-message-is-error result))
        (is (string= condition-message
                     (text-result result)))))))

(test goal10-abort-restart-commits-error-without-another-provider-request
  (let ((provider-calls 0))
    (let* ((bundle
             (make-test-extension-bundle
              "abort-condition"
              (lambda ()
                (cadr-agent:define-event-hook
                 :tool-call-error
                 :handler
                 (lambda (event context)
                   (declare (ignore event context))
                   (is-true
                    (find-restart
                     'cadr-agent:abort-agent-run))
                   (list
                    :action :abort
                    :reason "stopped by host"))))))
           (host (make-test-extension-host (list bundle)))
           (tool
             (make-tool
              :name "abortable"
              :description "Abortable"
              :parameters (object-schema)
              :execution-mode :sequential
              :executor
              (lambda (call-id arguments)
                (declare (ignore call-id arguments))
                (error "abort this run"))))
           (*responses*
             (list
              (assistant
               (list
                (make-tool-call
                 :id "abort-1" :name "abortable"
                 :arguments (cadr-ai::json-object)))
               :tool-use)
              (assistant
               (list
                (make-text-content
                 :text "must not be requested")))))
           (*contexts* nil)
           (stream (faux-stream '*responses* '*contexts*))
           (agent
             (make-agent
              :provider :mock
              :model (mock-model)
              :tools (list tool)
              :extension-host host
              :stream-function
              (lambda (&rest arguments)
                (incf provider-calls)
                (apply stream arguments)))))
      (declare (special *responses* *contexts*))
      (agent-prompt agent "run")
      (is (= 1 provider-calls))
      (let ((result
              (first-tool-result-message
               (agent-messages agent))))
        (is-true (tool-result-message-is-error result))
        (is (string= "stopped by host"
                     (text-result result)))))))

(test goal12-tool-termination-uses-nonempty-every-semantics-and-keeps-all-results
  (labels
      ((run-case (terminations expect-follow-up-p)
         (let* ((provider-calls 0)
                (tool
                  (make-tool
                   :name "terminate"
                   :description "Return an agent-only termination hint"
                   :parameters (object-schema "value")
                   :execution-mode :parallel
                   :executor
                   (lambda (call-id arguments)
                     (declare (ignore call-id))
                     (let ((value
                             (cadr-ai::json-get
                              arguments "value")))
                       (values
                        (list
                         (make-text-content :text value))
                        (list :value value)
                        (cdr
                         (assoc
                          value terminations
                          :test #'string=)))))))
                (*responses*
                  (list
                   (assistant
                    (loop
                      for entry in terminations
                      for value = (car entry)
                      collect
                      (make-tool-call
                       :id (format nil "call-~A" value)
                       :name "terminate"
                       :arguments
                       (cadr-ai::json-object "value" value)))
                    :tool-use)
                   (assistant
                    (list
                     (make-text-content :text "follow-up")))))
                (*contexts* nil)
                (stream
                  (faux-stream '*responses* '*contexts*))
                (agent
                  (make-agent
                   :provider :mock
                   :model (mock-model)
                   :tools (list tool)
                   :stream-function
                   (lambda (&rest arguments)
                     (incf provider-calls)
                     (apply stream arguments)))))
           (declare (special *responses* *contexts*))
           (agent-prompt agent "run")
           (is (= (if expect-follow-up-p 2 1)
                  provider-calls))
           (let ((results
                   (remove-if-not
                    (lambda (message)
                      (typep message 'tool-result-message))
                    (agent-messages agent))))
             (is (= (length terminations)
                    (length results)))
             (is
              (equal
               (mapcar #'car terminations)
               (mapcar #'text-result results)))))))
    (run-case '(("single" . t)) nil)
    (run-case '(("one" . t) ("two" . t)) nil)
    (run-case '(("one" . t) ("two" . nil)) t)
    (is-false
     (cadr-agent::tool-outcomes-terminate-p
      (make-array 0)))))

(test goal12-tool-termination-uses-after-hook-final-value
  (labels
      ((run-case (executor-terminate-p hook-terminate-p
                  expect-follow-up-p)
         (let* ((provider-calls 0)
                (tool
                  (make-tool
                   :name "after-terminate"
                   :description "Termination override target"
                   :parameters (object-schema)
                   :executor
                   (lambda (call-id arguments)
                     (declare (ignore call-id arguments))
                     (values
                      (list
                       (make-text-content :text "kept"))
                      nil
                      executor-terminate-p))))
                (bundle
                  (make-test-extension-bundle
                   "after-terminate"
                   (lambda ()
                     (cadr-agent:define-event-hook
                      :tool-call-after
                      :handler
                      (lambda (event context)
                        (declare (ignore event context))
                        (cadr-agent:make-extension-hook-result
                         :terminate-p hook-terminate-p))))))
                (host
                  (make-test-extension-host (list bundle)))
                (*responses*
                  (list
                   (assistant
                    (list
                     (make-tool-call
                      :id "after-1"
                      :name "after-terminate"
                      :arguments (cadr-ai::json-object)))
                    :tool-use)
                   (assistant
                    (list
                     (make-text-content :text "follow-up")))))
                (*contexts* nil)
                (stream
                  (faux-stream '*responses* '*contexts*))
                (agent
                  (make-agent
                   :provider :mock
                   :model (mock-model)
                   :tools (list tool)
                   :extension-host host
                   :stream-function
                   (lambda (&rest arguments)
                     (incf provider-calls)
                     (apply stream arguments)))))
           (declare (special *responses* *contexts*))
           (agent-prompt agent "run")
           (is (= (if expect-follow-up-p 2 1)
                  provider-calls))
           (let ((result
                   (find-if
                    (lambda (message)
                      (typep message 'tool-result-message))
                    (agent-messages agent))))
             (is (string= "kept" (text-result result)))))))
    (run-case nil t nil)
    (run-case t nil t)))

(test goal12-tool-partial-updates-are-scoped-ordered-and-not-persisted
  (let ((late-update nil)
        (lifecycle-updates nil)
        (lifecycle-boundaries nil)
        (events nil)
        (*responses*
          (list
           (assistant
            (list
             (make-tool-call
              :id "updates-1"
              :name "updates"
              :arguments (cadr-ai::json-object)))
            :tool-use)
           (assistant
            (list (make-text-content :text "done")))))
        (*contexts* nil))
    (declare (special *responses* *contexts*))
    (let* ((tool
             (make-tool
              :name "updates"
              :description "Emit partial results"
              :parameters (object-schema)
              :executor
              (lambda (call-id arguments)
                (declare (ignore call-id arguments))
                (setf late-update
                      (cadr-agent::current-tool-update-function))
                (cadr-agent::report-tool-update
                 (list (make-text-content :text "partial-1"))
                 '(:step 1))
                (cadr-agent::report-tool-update
                 (list (make-text-content :text "partial-2"))
                 '(:step 2))
                (values
                 (list (make-text-content :text "final"))
                 '(:step :final)))))
           (bundle
             (make-test-extension-bundle
              "observe-updates"
              (lambda ()
                (dolist (event '(:tool-execution-start
                                 :tool-execution-end))
                  (cadr-agent:define-event-hook
                   event
                   :handler
                   (lambda (value context)
                     (declare (ignore context))
                     (push
                      (cadr-agent:extension-event-type value)
                      lifecycle-boundaries))))
                (cadr-agent:define-event-hook
                 :tool-execution-update
                 :handler
                 (lambda (event context)
                   (declare (ignore context))
                   (push
                    (cadr-agent:extension-event-payload event)
                    lifecycle-updates))))))
           (host
             (make-test-extension-host (list bundle)))
           (agent
             (make-agent
              :provider :mock
              :model (mock-model)
              :tools (list tool)
              :extension-host host
              :stream-function
              (faux-stream '*responses* '*contexts*)
              :on-event
              (lambda (event)
                (push event events)))))
      (agent-prompt agent "run")
      (funcall
       late-update
       (list (make-text-content :text "too-late"))
       '(:step :late)
       nil)
      (let ((tool-events
              (remove-if-not
               (lambda (event)
                 (member
                  (agent-event-type event)
                  '(:tool-execution-start
                    :tool-execution-update
                    :tool-execution-end)))
               (nreverse events))))
        (is
         (equal
          '(:tool-execution-start
            :tool-execution-update
            :tool-execution-update
            :tool-execution-end)
          (event-types tool-events)))
        (is
         (equal
          '("partial-1" "partial-2")
          (loop
            for event in tool-events
            when
            (eq :tool-execution-update
                (agent-event-type event))
              collect
              (text-content-text
               (first
                (cadr-agent::tool-execution-result-content
                 (agent-event-tool-result event))))))))
      (is (= 2 (length lifecycle-updates)))
      (is (equal '(:tool-execution-start :tool-execution-end)
                 (nreverse lifecycle-boundaries)))
      (is
       (every
        (lambda (payload)
          (and
           (string= "updates-1"
                    (getf payload :tool-call-id))
           (string= "updates"
                    (getf payload :tool-name))
           (typep
            (getf payload :partial-result)
            'cadr-agent::tool-execution-result)))
        lifecycle-updates))
      (is
       (equal
        '("final")
        (mapcar
         #'text-result
         (remove-if-not
          (lambda (message)
            (typep message 'tool-result-message))
          (agent-messages agent))))))))

(test goal12-tool-update-error-path-closes-the-callback-before-end
  (let ((late-update nil)
        (events nil)
        (*responses*
          (list
           (assistant
            (list
             (make-tool-call
              :id "update-error-1"
              :name "update-error"
              :arguments (cadr-ai::json-object)))
            :tool-use)
           (assistant
            (list (make-text-content :text "recovered")))))
        (*contexts* nil))
    (declare (special *responses* *contexts*))
    (let* ((tool
             (make-tool
              :name "update-error"
              :description "Update and fail"
              :parameters (object-schema)
              :executor
              (lambda (call-id arguments)
                (declare (ignore call-id arguments))
                (setf late-update
                      (cadr-agent::current-tool-update-function))
                (cadr-agent::report-tool-update
                 (list (make-text-content :text "before-error")))
                (error "tool failed"))))
           (agent
             (make-agent
              :provider :mock
              :model (mock-model)
              :tools (list tool)
              :stream-function
              (faux-stream '*responses* '*contexts*)
              :on-event
              (lambda (event)
                (push event events)))))
      (agent-prompt agent "run")
      (funcall
       late-update
       (list (make-text-content :text "after-error"))
       nil nil)
      (let ((tool-events
              (remove-if-not
               (lambda (event)
                 (member
                  (agent-event-type event)
                  '(:tool-execution-start
                    :tool-execution-update
                    :tool-execution-end)))
               (nreverse events))))
        (is
         (equal
          '(:tool-execution-start
            :tool-execution-update
            :tool-execution-end)
          (event-types tool-events))))
      (let ((result
              (find-if
               (lambda (message)
                 (typep message 'tool-result-message))
               (agent-messages agent))))
        (is-true (tool-result-message-is-error result))
        (is (search "tool failed" (text-result result)))))))

(test goal12-tool-retry-gets-a-fresh-signal-and-rejects-prior-updates
  (let ((signals nil)
        (first-update nil)
        (updates nil)
        (*responses*
          (list
           (assistant
            (list
             (make-tool-call
              :id "retry-update-1"
              :name "retry-update"
              :arguments
              (cadr-ai::json-object "value" "bad")))
            :tool-use)
           (assistant
            (list (make-text-content :text "done")))))
        (*contexts* nil))
    (declare (special *responses* *contexts*))
    (let* ((tool
             (make-tool
              :name "retry-update"
              :description "Retry update scoping"
              :parameters (object-schema "value")
              :executor
              (lambda (call-id arguments)
                (declare (ignore call-id))
                (push
                 (cadr-agent::current-tool-cancellation-signal)
                 signals)
                (let ((value
                        (cadr-ai::json-get arguments "value")))
                  (if (string= value "bad")
                      (progn
                        (setf first-update
                              (cadr-agent::current-tool-update-function))
                        (cadr-agent::report-tool-update
                         (list
                          (make-text-content :text "first")))
                        (error "retry me"))
                      (progn
                        (funcall
                         first-update
                         (list
                          (make-text-content :text "late-first"))
                         nil nil)
                        (cadr-agent::report-tool-update
                         (list
                          (make-text-content :text "second")))
                        (values
                         (list
                          (make-text-content :text "done"))
                         nil)))))))
           (bundle
             (make-test-extension-bundle
              "retry-update"
              (lambda ()
                (cadr-agent:define-event-hook
                 :tool-call-error
                 :handler
                 (lambda (event context)
                   (declare (ignore event context))
                   (list
                    :action :retry
                    :arguments
                    (cadr-ai::json-object
                     "value" "good")))))))
           (host (make-test-extension-host (list bundle)))
           (agent
             (make-agent
              :provider :mock
              :model (mock-model)
              :tools (list tool)
              :extension-host host
              :stream-function
              (faux-stream '*responses* '*contexts*)
              :on-event
              (lambda (event)
                (when
                    (eq :tool-execution-update
                        (agent-event-type event))
                  (push
                   (text-content-text
                    (first
                     (cadr-agent::tool-execution-result-content
                      (agent-event-tool-result event))))
                   updates))))))
      (agent-prompt agent "run")
      (is (= 2 (length signals)))
      (is-false (eq (first signals) (second signals)))
      (is (equal '("first" "second")
                 (nreverse updates))))))

(test goal12-user-abort-is-visible-through-the-current-tool-signal
  (let ((started
          (sb-thread:make-semaphore :count 0))
        (finished
          (sb-thread:make-semaphore :count 0))
        (saw-abort-p nil)
        (stream-calls 0)
        (agent nil)
        (worker nil))
    (let ((tool
            (make-tool
             :name "signal-abort"
             :description "Observe user abort"
             :parameters (object-schema)
             :executor
             (lambda (call-id arguments)
               (declare (ignore call-id arguments))
               (let ((signal
                       (cadr-agent::current-tool-cancellation-signal)))
                 (sb-thread:signal-semaphore started)
                 (loop until
                       (cadr-agent:extension-cancellation-aborted-p
                        signal)
                       do (sleep 0.001))
                 (setf saw-abort-p t)
                 (error "Operation aborted"))))))
      (setf
       agent
       (make-agent
        :provider :mock
        :model (mock-model)
        :tools (list tool)
        :stream-function
        (lambda
            (provider model context on-event
             &key max-tokens temperature abort-p)
          (declare
           (ignore provider model context max-tokens
                   temperature abort-p))
          (incf stream-calls)
          (let ((message
                  (if (= stream-calls 1)
                      (assistant
                       (list
                        (make-tool-call
                         :id "signal-abort-1"
                         :name "signal-abort"
                         :arguments
                         (cadr-ai::json-object)))
                       :tool-use)
                      (assistant nil :aborted))))
            (funcall
             on-event
             (make-stream-event
              :type :start :message message))
            message)))
       worker
       (sb-thread:make-thread
        (lambda ()
          (unwind-protect
               (agent-prompt agent "run")
            (sb-thread:signal-semaphore finished)))
        :name "goal12-tool-signal-abort"))
      (is (sb-thread:wait-on-semaphore started :timeout 2))
      (cadr-agent:agent-abort agent)
      (is (sb-thread:wait-on-semaphore finished :timeout 5))
      (sb-thread:join-thread worker)
      (is-true saw-abort-p)
      (let ((result
              (find-if
               (lambda (message)
                 (typep message 'tool-result-message))
               (agent-messages agent))))
        (is-true (tool-result-message-is-error result))
        (is (string= "Operation aborted"
                     (text-result result)))))))

(test goal12-parallel-tool-updates-retain-their-own-call-identity
  (let ((first-reported
          (sb-thread:make-semaphore :count 0))
        (second-reported
          (sb-thread:make-semaphore :count 0))
        (updates nil)
        (*responses*
          (list
           (assistant
            (list
             (make-tool-call
              :id "parallel-update-a"
              :name "update-a"
              :arguments (cadr-ai::json-object))
             (make-tool-call
              :id "parallel-update-b"
              :name "update-b"
              :arguments (cadr-ai::json-object)))
            :tool-use)
           (assistant
            (list (make-text-content :text "done")))))
        (*contexts* nil))
    (declare (special *responses* *contexts*))
    (labels
        ((update-tool (name first-p)
           (make-tool
            :name name
            :description name
            :parameters (object-schema)
            :execution-mode :parallel
            :executor
            (lambda (call-id arguments)
              (declare (ignore arguments))
              (if first-p
                  (progn
                    (cadr-agent::report-tool-update
                     (list
                      (make-text-content :text "a-1")))
                    (sb-thread:signal-semaphore first-reported)
                    (sb-thread:wait-on-semaphore second-reported)
                    (cadr-agent::report-tool-update
                     (list
                      (make-text-content :text "a-2"))))
                  (progn
                    (sb-thread:wait-on-semaphore first-reported)
                    (cadr-agent::report-tool-update
                     (list
                      (make-text-content :text "b-1")))
                    (sb-thread:signal-semaphore second-reported)))
              (values
               (list (make-text-content :text call-id))
               nil)))))
      (let ((agent
              (make-agent
               :provider :mock
               :model (mock-model)
               :tools
               (list
                (update-tool "update-a" t)
                (update-tool "update-b" nil))
               :stream-function
               (faux-stream '*responses* '*contexts*)
               :on-event
               (lambda (event)
                 (when
                     (eq :tool-execution-update
                         (agent-event-type event))
                   (push
                    (list
                     (cadr-ai:tool-call-id
                      (agent-event-tool-call event))
                     (text-content-text
                      (first
                       (cadr-agent::tool-execution-result-content
                        (agent-event-tool-result event)))))
                    updates))))))
        (agent-prompt agent "run")
        (is
         (equal
          '(("parallel-update-a" "a-1")
            ("parallel-update-b" "b-1")
            ("parallel-update-a" "a-2"))
          (nreverse updates)))))))
