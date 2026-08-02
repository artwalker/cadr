(load (merge-pathnames "support.lisp" *load-truename*))

(defparameter +qna-system-prompt+
  "You are a question extractor. Given text from a conversation, extract any questions that need answering and format them for the user to fill in.\n\nOutput format:\n- List each question on its own line, prefixed with \"Q: \"\n- After each question, add a blank line for the answer prefixed with \"A: \"\n- If no questions are found, output \"No questions found in the last message.\"\n\nKeep questions in the order they appeared. Be concise.")

(defun qna-last-assistant-message (context)
  (loop for entry in (reverse (or (example-session-branch context) nil))
        for message = (cadr-agent:session-entry-message entry)
        when (typep message 'cadr-ai:assistant-message)
          return message))

(defun qna-extract (context text abort-p)
  (let* ((model (cadr-agent:extension-context-model context))
         (config
           (cadr-agent:extension-context-model-registry-resolve-auth
            context model))
         (response
           (cadr-ai:complete-chat
            (cadr-cli:provider-config-provider config)
            model
            (cadr-ai:make-context
             :system-prompt +qna-system-prompt+
             :messages (list (cadr-ai:make-user-message :content text)))
            :abort-p abort-p
            :session-id (cadr-ai:uuid-v7)))
         (result (example-assistant-text response)))
    (and (not (eq :aborted (cadr-ai:assistant-message-stop-reason response)))
         (plusp (length (example-trim result)))
         result)))

(cadr-agent:define-command
 "qna"
 :description "Extract questions from last assistant message into editor"
 :handler
 (lambda (arguments context)
   (declare (ignore arguments))
   (block qna-handler
     (cond
       ((not (cadr-agent:extension-context-has-ui-p context))
        (cadr-agent:extension-context-notify
         context "qna requires interactive mode" :level :error))
       ((null (cadr-agent:extension-context-model context))
        (cadr-agent:extension-context-notify
         context "No model selected" :level :error))
       (t
        (let ((message (qna-last-assistant-message context)))
          (unless message
            (cadr-agent:extension-context-notify
             context "No assistant messages found" :level :error)
            (return-from qna-handler nil))
          (unless (eq :stop (cadr-ai:assistant-message-stop-reason message))
            (cadr-agent:extension-context-notify
             context
             (format nil "Last assistant message incomplete (~(~A~))"
                     (cadr-ai:assistant-message-stop-reason message))
             :level :error)
            (return-from qna-handler nil))
          (let ((text (example-assistant-text message)))
            (when (zerop (length (example-trim text)))
              (cadr-agent:extension-context-notify
               context "No assistant messages found" :level :error)
              (return-from qna-handler nil))
            (let ((result
                    (example-with-loader
                     context
                     (format nil "Extracting questions using ~A..."
                             (cadr-ai:model-id
                              (cadr-agent:extension-context-model context)))
                     (lambda (abort-p)
                       (qna-extract context text abort-p)))))
              (if result
                  (progn
                    (cadr-agent:extension-context-set-editor-text
                     context result)
                    (cadr-agent:extension-context-notify
                     context "Questions loaded. Edit and submit when ready."))
                  (cadr-agent:extension-context-notify
                   context "Cancelled"))))))))))
