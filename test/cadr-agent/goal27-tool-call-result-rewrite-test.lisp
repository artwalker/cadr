(in-package #:cadr-agent/tests)
(in-suite cadr-agent-suite)

(defun goal27-tool-result (agent)
  (find-if
   (lambda (message)
     (typep message 'tool-result-message))
   (agent-messages agent)))

(defun goal27-assistant-tool-call (agent)
  (let ((message
          (find-if
           (lambda (entry)
             (typep entry 'cadr-ai:assistant-message))
           (agent-messages agent))))
    (find-if
     (lambda (block)
       (typep block 'cadr-ai:tool-call))
     (cadr-ai:assistant-message-content message))))

(defun goal27-prompt-with-tool
    (tool bundle arguments &key (follow-up "done"))
  (let ((*responses*
          (list
           (assistant
            (list
             (make-tool-call
              :id "goal27-call"
              :name (cadr-ai:tool-name tool)
              :arguments arguments))
            :tool-use)
           (assistant
            (list (make-text-content :text follow-up)))))
        (*contexts* nil))
    (declare (special *responses* *contexts*))
    (let ((agent
            (make-agent
             :provider :mock
             :model (mock-model)
             :tools (list tool)
             :extension-host
             (make-test-extension-host (list bundle))
             :stream-function
             (faux-stream '*responses* '*contexts*))))
      (agent-prompt agent "run")
      (values agent (first *contexts*)))))

(test goal27-tool-call-alias-rewrites-executed-arguments
  ;; pi@4a080252f types.ts ToolCallEvent: mutate input in place; later
  ;; handlers see it; the assistant message keeps the model's arguments
  ;; because validation cloned them first.
  (let ((executed nil)
        (seen nil))
    (let* ((tool
             (make-tool
              :name "echo"
              :description "Echo"
              :parameters (object-schema "text")
              :executor
              (lambda (call-id arguments)
                (declare (ignore call-id))
                (push (cadr-ai::json-get arguments "text") executed)
                (values
                 (list
                  (make-text-content
                   :text (cadr-ai::json-get arguments "text")))
                 (cadr-ai::json-object)
                 nil
                 nil
                 (cadr-ai:make-usage :input 1 :output 2 :total 3)))))
           (observed-usage nil)
           (bundle
             (make-test-extension-bundle
              "goal27-rewrite"
              (lambda ()
                (cadr-agent:define-event-hook
                 "tool_call"
                 :priority -10
                 :handler
                 (lambda (event context)
                   (declare (ignore context))
                   (cadr-ai::json-put
                    (cadr-ai:tool-call-arguments
                     (cadr-agent:extension-event-tool-call event))
                    "text"
                    "rewritten")
                   nil))
                (cadr-agent:define-event-hook
                 "tool_call"
                 :handler
                 (lambda (event context)
                   (declare (ignore context))
                   (push
                    (cadr-ai::json-get
                     (cadr-ai:tool-call-arguments
                      (cadr-agent:extension-event-tool-call event))
                     "text")
                    seen)
                   nil))
                (cadr-agent:define-event-hook
                 "tool_result"
                 :handler
                 (lambda (event context)
                   (declare (ignore context))
                   (setf observed-usage
                         (cadr-ai:usage-input
                          (cadr-ai:tool-result-message-usage
                           (cadr-agent:extension-event-tool-result
                            event))))
                   (cadr-agent:make-extension-hook-result
                    :content
                    (list (make-text-content :text "patched result"))
                    :details
                    (cadr-ai::json-object "patched" "yes")
                    :usage
                    (cadr-ai:make-usage
                     :input 5 :output 6 :total 11))))))))
      (multiple-value-bind (agent follow-up)
          (goal27-prompt-with-tool
           tool bundle
           (cadr-ai::json-object "text" "hello"))
        (is (equal '("rewritten") executed))
        (is (equal '("rewritten") seen))
        (is (string=
             "hello"
             (cadr-ai::json-get
              (cadr-ai:tool-call-arguments
               (goal27-assistant-tool-call agent))
              "text")))
        (is (= 1 observed-usage))
        (let ((result (goal27-tool-result agent)))
          (is (string= "patched result" (text-result result)))
          (is (string=
               "yes"
               (cadr-ai::json-get
                (cadr-ai:tool-result-message-details result)
                "patched")))
          (is (= 5
                 (cadr-ai:usage-input
                  (cadr-ai:tool-result-message-usage result)))))
        (let ((provider-result
                (find-if
                 (lambda (message)
                   (typep message 'tool-result-message))
                 (cadr-ai:context-messages follow-up))))
          (is (string= "patched result"
                       (text-result provider-result))))))))

(test goal27-tool-result-alias-chains-partial-fields
  ;; pi@4a080252f extensions-runner.test.ts "preserves previous
  ;; modifications when later handlers return partial patches".
  (let ((seen nil))
    (let* ((tool
             (make-tool
              :name "echo"
              :description "Echo"
              :parameters (object-schema)
              :executor
              (lambda (call-id arguments)
                (declare (ignore call-id arguments))
                (list (make-text-content :text "base")))))
           (bundle
             (make-test-extension-bundle
              "goal27-partial"
              (lambda ()
                (cadr-agent:define-event-hook
                 "tool_result"
                 :priority -10
                 :handler
                 (lambda (event context)
                   (declare (ignore event context))
                   (cadr-agent:make-extension-hook-result
                    :content
                    (list (make-text-content :text "first"))
                    :details
                    (cadr-ai::json-object "source" "ext1"))))
                (cadr-agent:define-event-hook
                 "tool_result"
                 :handler
                 (lambda (event context)
                   (declare (ignore context))
                   (push
                    (text-result
                     (cadr-agent:extension-event-tool-result event))
                    seen)
                   (cadr-agent:make-extension-hook-result
                    :is-error t)))))))
      (let ((agent
              (goal27-prompt-with-tool
               tool bundle (cadr-ai::json-object))))
        (is (equal '("first") seen))
        (let ((result (goal27-tool-result agent)))
          (is (string= "first" (text-result result)))
          (is (string=
               "ext1"
               (cadr-ai::json-get
                (cadr-ai:tool-result-message-details result)
                "source")))
          (is (cadr-ai:tool-result-message-is-error result)))))))

(test goal27-tool-result-content-drops-structured-content
  ;; pi@4a080252f agent-loop.test.ts: content alone drops
  ;; structuredContent; details alone keeps it; returning both keeps it.
  (let ((cases
          (list
           (list :content
                 (cadr-agent:make-extension-hook-result
                  :content
                  (list (make-text-content :text "redacted")))
                 nil
                 "redacted")
           (list :structured
                 (cadr-agent:make-extension-hook-result
                  :structured-content
                  (cadr-ai::json-object "value" "replaced"))
                 "replaced"
                 "original")
           (list :both
                 (cadr-agent:make-extension-hook-result
                  :content
                  (list (make-text-content :text "redacted"))
                  :structured-content
                  (cadr-ai::json-object "value" "both"))
                 "both"
                 "redacted")
           (list :details
                 (cadr-agent:make-extension-hook-result
                  :details
                  (cadr-ai::json-object "note" "kept"))
                 "original"
                 "original"))))
    (dolist (case cases)
      (destructuring-bind (label hook expected-structured expected-text)
          case
        (let* ((tool
                 (make-tool
                  :name "echo"
                  :description "Echo"
                  :parameters (object-schema)
                  :executor
                  (lambda (call-id arguments)
                    (declare (ignore call-id arguments))
                    (values
                     (list (make-text-content :text "original"))
                     (cadr-ai::json-object)
                     nil
                     (cadr-ai::json-object "value" "original")))))
               (bundle
                 (make-test-extension-bundle
                  (format nil "goal27-structured-~A" label)
                  (lambda ()
                    (cadr-agent:define-event-hook
                     "tool_result"
                     :handler
                     (lambda (event context)
                       (declare (ignore event context))
                       hook)))))
               (agent
                 (goal27-prompt-with-tool
                  tool bundle (cadr-ai::json-object)))
               (result (goal27-tool-result agent))
               (structured
                 (cadr-ai:tool-result-message-structured-content result)))
          (is (string= expected-text (text-result result)))
          (if expected-structured
              (is (string=
                   expected-structured
                   (cadr-ai::json-get structured "value")))
              (is (null structured))))))))

(test goal27-blocked-tool-call-skips-tool-result
  ;; pi@4a080252f agent-session-model-extension.test.ts and
  ;; agent-loop.test.ts: block prevents execution; afterToolCall does
  ;; not run; the error text is the reason.
  (let ((executions 0)
        (results 0))
    (let* ((tool
             (make-tool
              :name "echo"
              :description "Echo"
              :parameters (object-schema "text")
              :executor
              (lambda (call-id arguments)
                (declare (ignore call-id arguments))
                (incf executions)
                (list (make-text-content :text "ran")))))
           (bundle
             (make-test-extension-bundle
              "goal27-block"
              (lambda ()
                (cadr-agent:define-event-hook
                 "tool_call"
                 :handler
                 (lambda (event context)
                   (declare (ignore event context))
                   (cadr-agent:make-extension-hook-result
                    :block-p t
                    :reason "Blocked by test")))
                (cadr-agent:define-event-hook
                 "tool_result"
                 :handler
                 (lambda (event context)
                   (declare (ignore event context))
                   (incf results)
                   nil))))))
      (let ((agent
              (goal27-prompt-with-tool
               tool bundle
               (cadr-ai::json-object "text" "hello")
               :follow-up "Blocked by test")))
        (is (= 0 executions))
        (is (= 0 results))
        (let ((result (goal27-tool-result agent)))
          (is (cadr-ai:tool-result-message-is-error result))
          (is (string= "Blocked by test" (text-result result))))))))

(test goal27-nested-tool-result-alias-rewrites-the-caller-result
  ;; pi@4a080252f extensions.md: nested calls go through tool_result.
  (let* ((inner
           (make-tool
            :name "inner"
            :description "Inner"
            :parameters (object-schema)
            :executor
            (lambda (call-id arguments)
              (declare (ignore call-id arguments))
              (list (make-text-content :text "inner-ok")))))
         (seen nil)
         (outer
           (make-tool
            :name "outer"
            :description "Outer"
            :parameters (object-schema)
            :executor
            (lambda (call-id arguments)
              (declare (ignore call-id arguments))
              (let ((outcome
                      (cadr-agent:extension-context-execute-tool
                       nil "inner" (cadr-ai::json-object))))
                (push
                 (text-result
                  (cadr-agent::nested-tool-call-outcome-result outcome))
                 seen))
              (list (make-text-content :text "outer-ok")))))
         (bundle
           (make-test-extension-bundle
            "goal27-nested"
            (lambda ()
              (cadr-agent:define-event-hook
               "tool_result"
               :handler
               (lambda (event context)
                 (declare (ignore context))
                 (when (string=
                        "inner"
                        (cadr-ai:tool-result-message-tool-name
                         (cadr-agent:extension-event-tool-result event)))
                   (cadr-agent:make-extension-hook-result
                    :content
                    (list (make-text-content :text "redacted")))))))))
         (host (make-test-extension-host (list bundle)))
         (agent
           (make-agent
            :provider :mock
            :model (mock-model)
            :tools (list outer inner)
            :extension-host host)))
    (cadr-agent::execute-tool-batch
     agent
     (list
      (make-tool-call
       :id "parent"
       :name "outer"
       :arguments (cadr-ai::json-object)))
     :turn-index 0)
    (is (equal '("redacted") seen))))
