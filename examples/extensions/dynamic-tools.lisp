(load (merge-pathnames "support.lisp" *load-truename*))

(defvar *dynamic-tool-names* (make-hash-table :test #'equal))

(defun register-dynamic-echo-tool (context name prefix)
  (unless (gethash name *dynamic-tool-names*)
    (setf (gethash name *dynamic-tool-names*) t)
    (cadr-agent:extension-context-register-tool
     context
     (cadr-ai:make-tool
      :name name
      :description "Echo text with a dynamic prefix"
      :parameters (example-object-schema "text" "string" "Text to echo")
      :executor
      (lambda (call-id arguments)
        (declare (ignore call-id))
        (example-text-result
         (concatenate 'string prefix
                      (example-argument arguments "text" "")))))
     :label (format nil "Echo ~A" name)
     :prompt-snippet "Use this dynamically registered echo tool"
     :prompt-guidelines '("Preserve the input text exactly."))))

(cadr-agent:define-event-hook
 :session-start
 :handler
 (lambda (event context)
   (declare (ignore event))
   (register-dynamic-echo-tool context "echo_session" "[session] ")
   (cadr-agent:extension-context-notify
    context "Registered dynamic tool: echo_session")))

(cadr-agent:define-command
 "add-echo-tool"
 :description "Register a named echo tool at runtime"
 :argument-hint "<tool_name>"
 :handler
 (lambda (arguments context)
   (let ((name (string-downcase (example-trim arguments))))
     (if (or (zerop (length name))
             (not (every (lambda (character)
                           (or (alphanumericp character)
                               (char= character #\_)))
                         name)))
         (cadr-agent:extension-context-notify
          context
          "Usage: /add-echo-tool <tool_name> (letters, numbers, underscores)"
          :level :warning)
         (if (gethash name *dynamic-tool-names*)
             (cadr-agent:extension-context-notify
              context (format nil "Tool already registered: ~A" name)
              :level :warning)
             (progn
               (register-dynamic-echo-tool
                context name (format nil "[~A] " name))
               (cadr-agent:extension-context-notify
                context (format nil "Registered dynamic tool: ~A" name))))))))
