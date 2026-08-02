(load (merge-pathnames "support.lisp" *load-truename*))

(defparameter +custom-compaction-model-provider+ "google")
(defparameter +custom-compaction-model-id+ "gemini-2.5-flash")

(defun custom-compaction-message-text (message)
  (cond
    ((typep message 'cadr-ai:user-message)
     (let ((content (cadr-ai:user-message-content message)))
       (if (stringp content)
           content
           (format nil "~{~A~^~%~}"
                   (loop for block in content
                         when (typep block 'cadr-ai:text-content)
                           collect (cadr-ai:text-content-text block))))))
    ((typep message 'cadr-ai:assistant-message)
     (example-assistant-text message))
    ((typep message 'cadr-ai:tool-result-message)
     (example-tool-result-text message))
    (t "")))

(defun custom-compaction-conversation (messages)
  (with-output-to-string (output)
    (dolist (message messages)
      (let ((text (custom-compaction-message-text message)))
        (when (plusp (length (example-trim text)))
          (format output "~A: ~A~%~%"
                  (cond
                    ((typep message 'cadr-ai:user-message) "User")
                    ((typep message 'cadr-ai:assistant-message) "Assistant")
                    (t "Tool"))
                  text))))))

(defun custom-compaction-prompt (conversation previous-summary)
  (format nil
          "You are a conversation summarizer. Create a comprehensive structured Markdown summary that preserves goals, decisions and rationale, code and file changes, current state, blockers, open questions, and next steps.~@[~%~%Previous session summary for context:~%~A~]~%~%The summary replaces the entire conversation history, so retain everything needed to continue effectively.~%~%<conversation>~%~A</conversation>"
          previous-summary conversation))

(cadr-agent:define-event-hook
 :session-before-compact
 :handler
 (lambda (event context)
   (block custom-compaction
     (let* ((payload (cadr-agent:extension-event-payload event))
            (preparation (getf payload :preparation))
            (signal (getf payload :signal))
            (model
              (cadr-agent:extension-context-model-registry-find
               context
               +custom-compaction-model-provider+
               +custom-compaction-model-id+)))
       (cadr-agent:extension-context-notify
        context "Custom compaction extension triggered")
       (unless model
         (cadr-agent:extension-context-notify
          context
          "Could not find Gemini Flash model, using default compaction"
          :level :warning)
         (return-from custom-compaction nil))
       (handler-case
           (let* ((messages
                    (append
                     (copy-list (getf preparation :messages-to-summarize))
                     (copy-list (getf preparation :turn-prefix-messages))))
                  (config
                    (cadr-agent:extension-context-model-registry-resolve-auth
                     context model))
                  (conversation
                    (custom-compaction-conversation messages)))
             (cadr-agent:extension-context-notify
              context
              (format nil
                      "Custom compaction: summarizing ~D messages (~:D tokens) with ~A..."
                      (length messages)
                      (getf preparation :tokens-before)
                      (cadr-ai:model-id model)))
             (let* ((response
                      (cadr-ai:complete-chat
                       (cadr-cli:provider-config-provider config)
                       model
                       (cadr-ai:make-context
                        :messages
                        (list
                         (cadr-ai:make-user-message
                          :content
                          (custom-compaction-prompt
                           conversation
                           (getf preparation :previous-summary)))))
                       :max-tokens 8192
                       :cache-retention :none
                       :abort-p
                       (lambda ()
                         (cadr-agent:extension-cancellation-aborted-p signal))
                       :session-id (cadr-ai:uuid-v7)))
                    (summary (example-assistant-text response)))
               (when (or (cadr-agent:extension-cancellation-aborted-p signal)
                         (zerop (length (example-trim summary))))
                 (unless
                     (cadr-agent:extension-cancellation-aborted-p signal)
                   (cadr-agent:extension-context-notify
                    context
                    "Compaction summary was empty, using default compaction"
                    :level :warning))
                 (return-from custom-compaction nil))
               (list
                :compaction
                (list
                 :summary summary
                 :first-kept-entry-id
                 (getf preparation :first-kept-entry-id)
                 :tokens-before (getf preparation :tokens-before)
                 :usage (cadr-ai:assistant-message-usage response)))))
         (condition (condition)
           (unless (cadr-agent:extension-cancellation-aborted-p signal)
             (cadr-agent:extension-context-notify
              context
              (format nil "Compaction failed: ~A" condition)
              :level :error))
           nil))))))
