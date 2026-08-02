(load (merge-pathnames "support.lisp" *load-truename*))

(defun confirm-destructive-action (context title message)
  (if (not (cadr-agent:extension-context-has-ui-p context))
      nil
      (unless (cadr-agent:extension-context-confirm context title message)
        (cadr-agent:extension-context-notify context "Action cancelled")
        (cadr-agent:make-extension-hook-result :block-p t :reason "Cancelled by user"))))

(cadr-agent:define-event-hook
 :session-before-switch
 :handler
 (lambda (event context)
   (confirm-destructive-action
    context "Clear session?"
    (if (eq :new (example-event-value event :reason))
        "Start a new session and clear the current conversation?"
        "Switch sessions and replace the current conversation?"))))

(cadr-agent:define-event-hook
 :session-before-fork
 :handler
 (lambda (event context)
   (confirm-destructive-action
    context "Fork session?"
    (format nil "Fork from entry ~A?"
            (or (example-event-value event :entry-id) "unknown")))))
