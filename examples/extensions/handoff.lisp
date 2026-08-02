(load (merge-pathnames "support.lisp" *load-truename*))

(defparameter +handoff-system-prompt+
  "You are a context transfer assistant. Given a conversation history and the user's goal for a new thread, generate a focused prompt that:\n\n1. Summarizes relevant context from the conversation (decisions made, approaches taken, key findings)\n2. Lists any relevant files that were discussed or modified\n3. Clearly states the next task based on the user's goal\n4. Is self-contained - the new thread should be able to proceed without the old conversation\n\nFormat your response as a prompt the user can send to start the new thread. Be concise but include all necessary context. Do not include any preamble like \"Here's the prompt\" - just output the prompt itself.")

(defun handoff-branch-entries (branch)
  (let ((compaction-position
          (position :compaction branch
                    :key #'cadr-agent:session-entry-type
                    :from-end t)))
    (if (null compaction-position)
        branch
        (let* ((compaction (nth compaction-position branch))
               (kept-position
                 (position (cadr-agent:session-entry-first-kept-id compaction)
                           branch :key #'cadr-agent:session-entry-id
                           :test #'string=)))
          (append
           (list compaction)
           (if (and kept-position (< kept-position compaction-position))
               (subseq branch kept-position compaction-position)
               nil)
           (subseq branch (1+ compaction-position)))))))

(defun handoff-conversation-text (entries)
  (with-output-to-string (output)
    (dolist (entry entries)
      (case (cadr-agent:session-entry-type entry)
        (:compaction
         (format output "Compaction summary: ~A~%~%"
                 (cadr-agent:session-entry-summary entry)))
        (:message
         (let ((text (example-entry-text entry))
               (role (example-entry-role entry)))
           (when (and role (plusp (length (example-trim text))))
             (format output "~:(~A~): ~A~%~%" role text))))))))

(defun handoff-generate (context conversation goal abort-p)
  (let* ((model (cadr-agent:extension-context-model context))
         (config
           (cadr-agent:extension-context-model-registry-resolve-auth
            context model))
         (response
           (cadr-ai:complete-chat
            (cadr-cli:provider-config-provider config)
            model
            (cadr-ai:make-context
             :system-prompt +handoff-system-prompt+
             :messages
             (list
              (cadr-ai:make-user-message
               :content
               (format nil
                       "## Conversation History~%~%~A~%~%## User's Goal for New Thread~%~%~A"
                       conversation goal))))
            :abort-p abort-p :cache-retention :none
            :session-id (cadr-ai:uuid-v7)))
         (text (example-assistant-text response)))
    (and (not (eq :aborted (cadr-ai:assistant-message-stop-reason response)))
         (plusp (length (example-trim text)))
         text)))

(cadr-agent:define-command
 "handoff"
 :description "Transfer context to a new focused session"
 :argument-hint "<goal for new thread>"
 :handler
 (lambda (arguments context)
   (block handoff-handler
     (let ((goal (example-trim arguments)))
       (cond
         ((not (cadr-agent:extension-context-has-ui-p context))
          (cadr-agent:extension-context-notify
           context "handoff requires interactive mode" :level :error))
         ((null (cadr-agent:extension-context-model context))
          (cadr-agent:extension-context-notify
           context "No model selected" :level :error))
         ((zerop (length goal))
          (cadr-agent:extension-context-notify
           context "Usage: /handoff <goal for new thread>" :level :error))
         (t
          (let* ((branch (or (example-session-branch context) nil))
                 (conversation
                   (handoff-conversation-text
                    (handoff-branch-entries branch))))
            (when (zerop (length (example-trim conversation)))
              (cadr-agent:extension-context-notify
               context "No conversation to hand off" :level :error)
              (return-from handoff-handler nil))
            (let ((generated
                    (example-with-loader
                     context "Generating handoff prompt..."
                     (lambda (abort-p)
                       (handoff-generate
                        context conversation goal abort-p)))))
              (unless generated
                (cadr-agent:extension-context-notify context "Cancelled")
                (return-from handoff-handler nil))
              (let ((edited
                      (cadr-agent:extension-context-editor
                       context "Edit handoff prompt" :prefill generated)))
                (unless edited
                  (cadr-agent:extension-context-notify context "Cancelled")
                  (return-from handoff-handler nil))
                (cadr-agent:extension-command-context-new-session
                 context
                 :parent-session
                 (let ((session (cadr-agent:extension-context-session context)))
                   (and session
                        (namestring (cadr-agent:session-path session))))
                 :with-session-function
                 (lambda (replacement-context)
                   (cadr-agent:extension-context-set-editor-text
                    replacement-context edited)
                   (cadr-agent:extension-context-notify
                    replacement-context
                    "Handoff ready. Submit when ready."))))))))))))
