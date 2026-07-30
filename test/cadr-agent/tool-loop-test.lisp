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
         (slow
           (make-tool
            :name "slow"
            :description "Slow"
            :parameters (object-schema)
            :execution-mode :parallel
            :executor
            (lambda (call-id arguments)
              (declare (ignore arguments))
              (sleep 0.08)
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
             :on-event (lambda (event) (push event events)))))
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
                (sleep 0.04)
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
