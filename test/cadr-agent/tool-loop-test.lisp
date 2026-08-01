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
      (is (= 4 (length (agent-messages agent))))
      (is (typep (third (agent-messages agent))
                 'tool-result-message))
      (is (not (tool-result-message-is-error
                (third (agent-messages agent)))))
      (is (equal
           '(:agent-start :turn-start :message-start :message-end
             :message-start :message-end
             :tool-execution-start :tool-execution-end
             :message-start :message-end :turn-end
             :turn-start :message-start :message-update :message-end
             :turn-end :agent-end :agent-settled)
           (event-types (nreverse events))))
      (let ((second-context (first *contexts*)))
        (is (typep (third (cadr-ai:context-messages second-context))
                   'tool-result-message))))))

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
          (let ((result (third (agent-messages agent))))
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
      (let ((result (third (agent-messages agent))))
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
      (let ((result (third (agent-messages agent))))
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
      (let ((result (third (agent-messages agent))))
        (is-true (tool-result-message-is-error result))
        (is (string= "stopped by host"
                     (text-result result)))))))
