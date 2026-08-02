(load (merge-pathnames "support.lisp" *load-truename*))

(defun summarize-content-texts (content)
  (cond
    ((stringp content) (list content))
    ((or (listp content) (vectorp content))
     (loop for block across (coerce content 'vector)
           when (typep block 'cadr-ai:text-content)
             collect (cadr-ai:text-content-text block)))
    (t nil)))

(defun summarize-conversation-text (entries)
  (with-output-to-string (output)
    (let ((first-p t))
      (dolist (entry entries)
        (let ((message (cadr-agent:session-entry-message entry)))
          (when (or (typep message 'cadr-ai:user-message)
                    (typep message 'cadr-ai:assistant-message))
            (let* ((user-p (typep message 'cadr-ai:user-message))
                   (content
                     (if user-p
                         (cadr-ai:user-message-content message)
                         (cadr-ai:assistant-message-content message)))
                   (texts (summarize-content-texts content))
                   (tool-lines
                     (unless user-p
                       (loop for block in content
                             when (typep block 'cadr-ai:tool-call)
                               collect
                               (format nil "Tool ~A was called with args ~A"
                                       (cadr-ai:tool-call-name block)
                                       (cadr-ai::stringify-json
                                        (cadr-ai:tool-call-arguments block)))))))
              (when (or texts tool-lines)
                (unless first-p (format output "~%~%"))
                (setf first-p nil)
                (when texts
                  (format output "~A: ~A"
                          (if user-p "User" "Assistant")
                          (example-trim
                           (format nil "~{~A~^~%~}" texts))))
                (dolist (line tool-lines)
                  (format output "~@[~%~]~A" texts line))))))))))

(defun summarize-prompt (conversation)
  (format nil
          "Summarize this conversation so I can resume it later.~%Include goals, key decisions, progress, open questions, and next steps.~%Keep it concise and structured with headings.~%~%<conversation>~%~A~%</conversation>"
          conversation))

(defun summarize-response-text (message)
  (with-output-to-string (output)
    (dolist (block (cadr-ai:assistant-message-content message))
      (when (typep block 'cadr-ai:text-content)
        (when (plusp (file-position output))
          (terpri output))
        (write-string (cadr-ai:text-content-text block) output)))))

(cadr-agent:define-command
 "summarize"
 :description "Summarize the current conversation in a custom UI"
 :handler
 (lambda (arguments context)
   (declare (ignore arguments))
   (block summarize-handler
   (let ((conversation
           (summarize-conversation-text
            (or (example-session-branch context) nil))))
     (if (zerop (length (example-trim conversation)))
         (cadr-agent:extension-context-notify
          context "No conversation text found" :level :warning)
         (progn
           (cadr-agent:extension-context-notify
            context "Preparing summary...")
           (let ((model
                   (cadr-agent:extension-context-model-registry-find
                    context "openai" "gpt-5.2")))
             (unless model
               (cadr-agent:extension-context-notify
                context "Model openai/gpt-5.2 not found" :level :warning)
               (return-from summarize-handler nil))
             (handler-case
                 (let* ((config
                          (cadr-agent:extension-context-model-registry-resolve-auth
                           context model))
                        (message
                          (cadr-ai:complete-chat
                           (cadr-cli:provider-config-provider config)
                           model
                           (cadr-ai:make-context
                            :messages
                            (list
                             (cadr-ai:make-user-message
                              :content
                              (list
                               (cadr-ai:make-text-content
                                :text (summarize-prompt conversation))))))
                           :reasoning :high
                           :cache-retention :none
                           :session-id (cadr-ai:uuid-v7)))
                        (summary (summarize-response-text message)))
                   (example-show-dialog
                    context "Conversation Summary"
                    (list summary)))
               (condition (condition)
                 (cadr-agent:extension-context-notify
                  context (princ-to-string condition) :level :warning))))))))))
