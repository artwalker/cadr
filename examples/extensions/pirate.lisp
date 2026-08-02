(load (merge-pathnames "support.lisp" *load-truename*))

(defparameter *pirate-mode* nil)

(cadr-agent:define-command
 "pirate"
 :description "Toggle pirate mode (agent speaks like a pirate)"
 :handler
 (lambda (arguments context)
   (declare (ignore arguments))
   (setf *pirate-mode* (not *pirate-mode*))
   (cadr-agent:extension-context-notify
    context (if *pirate-mode*
                "Arrr! Pirate mode enabled!"
                "Pirate mode disabled"))))

(cadr-agent:define-event-hook
 :before-agent-start
 :handler
 (lambda (event context)
   (declare (ignore context))
   (when *pirate-mode*
     (list
      :system-prompt
      (format nil
              "~A~%~%IMPORTANT: You are now in PIRATE MODE. You must:~%- Speak like a stereotypical pirate in all responses~%- Use phrases like \"Arrr!\", \"Ahoy!\", \"Shiver me timbers!\", \"Avast!\", \"Ye scurvy dog!\"~%- Replace \"my\" with \"me\", \"you\" with \"ye\", \"your\" with \"yer\"~%- Refer to the user as \"matey\" or \"landlubber\"~%- End sentences with nautical expressions~%- Still complete the actual task correctly, just in pirate speak~%"
              (example-event-value event :system-prompt))))))
