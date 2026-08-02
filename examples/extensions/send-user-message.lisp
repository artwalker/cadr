(load (merge-pathnames "support.lisp" *load-truename*))

(defun example-send-user-command (context arguments mode)
  (let ((text (example-trim arguments)))
    (if (zerop (length text))
        (cadr-agent:extension-context-notify
         context (format nil "Usage: /~(~A~) <message>" mode)
         :level :warning)
        (case mode
          (:ask
           (if (cadr-agent:extension-context-idle-p context)
               (cadr-agent:extension-api-send-user-message *example-api* text)
               (cadr-agent:extension-context-notify
                context "Agent is busy. Use /steer or /followup instead."
                :level :warning)))
          (:steer
           (cadr-agent:extension-api-send-user-message
            *example-api* text
            :deliver-as
            (unless (cadr-agent:extension-context-idle-p context) :steer)))
          (:followup
           (cadr-agent:extension-api-send-user-message
            *example-api* text
            :deliver-as
            (unless (cadr-agent:extension-context-idle-p context) :follow-up))
           (unless (cadr-agent:extension-context-idle-p context)
             (cadr-agent:extension-context-notify context "Follow-up queued")))))))

(cadr-agent:define-command
 "ask" :description "Send a user message to the agent"
 :handler (lambda (arguments context)
            (example-send-user-command context arguments :ask)))
(cadr-agent:define-command
 "steer" :description "Send a steering message (interrupts current processing)"
 :handler (lambda (arguments context)
            (example-send-user-command context arguments :steer)))
(cadr-agent:define-command
 "followup" :description "Queue a follow-up message (waits for current processing)"
 :handler (lambda (arguments context)
            (example-send-user-command context arguments :followup)))
(cadr-agent:define-command
 "askwith" :description "Send a user message with structured content"
 :handler
 (lambda (arguments context)
   (let ((text (example-trim arguments)))
     (cond
       ((zerop (length text))
        (cadr-agent:extension-context-notify
         context "Usage: /askwith <message>" :level :warning))
       ((not (cadr-agent:extension-context-idle-p context))
        (cadr-agent:extension-context-notify
         context "Agent is busy" :level :warning))
       (t
        (cadr-agent:extension-api-send-user-message
         *example-api*
         (list
          (cadr-ai:make-text-content
           :text (format nil "User request: ~A" text))
          (cadr-ai:make-text-content
           :text "Please respond concisely."))))))))
