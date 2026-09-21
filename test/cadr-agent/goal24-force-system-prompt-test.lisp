(in-package #:cadr-agent/tests)
(in-suite cadr-agent-suite)

;;; Locks packages/coding-agent/test/system-prompt-updates.test.ts
;;; "a forced prompt is sent as the leading prompt for the run and never
;;; recorded" against baseline v0.86.1 agent-session.ts
;;; _installAgentForcedPromptProjection.

(defun goal24-force-system-messages (context)
  (remove-if-not
   #'cadr-ai:system-message-p
   (cadr-ai:context-messages context)))

(defun goal24-force-loadout-function ()
  (let ((calls 0))
    (lambda (agent options messages)
      (declare (ignore options messages))
      (incf calls)
      (let ((tool
              (first
               (cadr-agent::merged-agent-tools agent))))
        (cond
          ((= calls 1)
           ;; make-agent may already seed a tools-only system head
           ;; (create-initial-system-message). Still emit the first
           ;; structured sections patch for this turn.
           (cadr-ai:make-system-message
            :content ""
            :sections
            '(("preamble" . "You are A.")
              ("cwd" . "<cwd>\n/tmp\n</cwd>"))
            :tools-added
            (when tool
              (list (cadr-ai:to-tool-declaration tool)))
            :timestamp 1))
          ((= calls 3)
           (cadr-ai:make-system-message
            :content ""
            :sections
            '(("plan_mode"
               . "<plan_mode>\nPlan only.\n</plan_mode>"))
            :timestamp 3))
          (t nil))))))

(test goal24-project-forced-system-prompt-collapses-to-leading-head
  (let* ((tool
           (cadr-ai:make-tool
            :name "read"
            :description "Read a file."
            :parameters
            (cadr-ai::json-object
             "type" "object"
             "properties" (cadr-ai::json-object))))
         (messages
           (list
            (cadr-ai:make-system-message
             :content ""
             :sections
             '(("preamble" . "You are A.")
               ("cwd" . "<cwd>\n/tmp\n</cwd>"))
             :tools-added
             (list (cadr-ai:to-tool-declaration tool))
             :timestamp 10)
            (cadr-ai:make-system-message
             :content ""
             :sections
             '(("plan_mode" . "<plan_mode>\nPlan only.\n</plan_mode>"))
             :timestamp 20)
            (cadr-ai:make-user-message :content "hi" :timestamp 30)))
         (projected
           (cadr-ai:project-forced-system-prompt
            messages "Exact prompt.")))
    (is (= 2 (length projected)))
    (is (typep (first projected) 'cadr-ai:system-message))
    (is (string= "Exact prompt."
                 (cadr-ai:system-message-content (first projected))))
    (is (null (cadr-ai:system-message-sections (first projected))))
    (is (= 10 (cadr-ai:system-message-timestamp (first projected))))
    (is (= 1 (length (cadr-ai:system-message-tools-added
                      (first projected)))))
    (is (string=
         "read"
         (cadr-ai:tool-name
          (first (cadr-ai:system-message-tools-added
                  (first projected))))))
    (is (typep (second projected) 'cadr-ai:user-message))))

(test goal24-before-agent-start-system-prompt-forces-leading-not-section-patch
  (let* ((*responses*
           (list
            (assistant
             (list (make-text-content :text "one")))
            (assistant
             (list (make-text-content :text "two")))
            (assistant
             (list (make-text-content :text "three")))))
         (*contexts* nil)
         (turn 0)
         (bundle
           (make-test-extension-bundle
            "goal24-force-system-prompt"
            (lambda ()
              (cadr-agent:define-event-hook
               :before-agent-start
               :handler
               (lambda (event context)
                 (declare (ignore event context))
                 (incf turn)
                 (when (= turn 2)
                   (list :system-prompt "Exact prompt.")))))))
         (host (make-test-extension-host (list bundle)))
         (read-tool
           (cadr-ai:make-tool
            :name "read"
            :description "Read a file."
            :parameters
            (cadr-ai::json-object
             "type" "object"
             "properties" (cadr-ai::json-object))
            :executor
            (lambda (&rest args)
              (declare (ignore args))
              (list :content nil :details nil))))
         (agent
           (make-agent
            :provider :mock
            :model (mock-model)
            :system-prompt "base-system"
            :tools (list read-tool)
            :prepare-prompt-loadout-function
            (goal24-force-loadout-function)
            :extension-host host
            :stream-function
            (faux-stream '*responses* '*contexts*))))
    (declare (special *responses* *contexts*))
    (agent-prompt agent "one")
    (agent-prompt agent "two")
    (agent-prompt agent "three")
    (is (= 3 (length *contexts*)))
    (let* ((contexts (reverse *contexts*))
           (unforced-1 (first contexts))
           (forced (second contexts))
           (unforced-3 (third contexts))
           (forced-systems (goal24-force-system-messages forced))
           (recorded
             (remove-if-not
              #'cadr-ai:system-message-p
              (agent-messages agent))))
      ;; Forced turn collapses to one leading system message with the
      ;; exact text. Mid-convo section patches stay out of that request.
      (is (>= (length (goal24-force-system-messages unforced-1)) 1))
      (is (= 1 (length forced-systems)))
      (is (>= (length (goal24-force-system-messages unforced-3)) 2))
      (is (string=
           "Exact prompt."
           (cadr-ai:system-message-content
            (first forced-systems))))
      (is (null (cadr-ai:system-message-sections
                 (first forced-systems))))
      (is (null (cadr-ai:context-system-prompt forced)))
      ;; Transcript records structured sections only, never the forced text.
      (is
       (notany
        (lambda (message)
          (search
           "Exact prompt."
           (cadr-ai:content-text
            (cadr-ai:system-message-content message))))
        recorded))
      (is
       (some
        (lambda (message)
          (assoc "preamble"
                 (cadr-ai:system-message-sections message)
                 :test #'string=))
        recorded))
      (is
       (some
        (lambda (message)
          (assoc "plan_mode"
                 (cadr-ai:system-message-sections message)
                 :test #'string=))
        recorded)))))
