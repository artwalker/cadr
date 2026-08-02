(load (merge-pathnames "support.lisp" *load-truename*))

(cadr-agent:define-event-hook
 :session-start
 :handler
 (lambda (event context)
   (declare (ignore event))
   (cadr-agent:extension-context-set-header
    context
    (lambda (tui theme)
      (declare (ignore tui theme))
      (cadr-tui:make-text-component
       "CADR — custom extension header" :padding-x 1 :padding-y 0)))))

(cadr-agent:define-command
 "builtin-header"
 :description "Restore the built-in header"
 :handler
 (lambda (arguments context)
   (declare (ignore arguments))
   (cadr-agent:extension-context-set-header context nil)
   (cadr-agent:extension-context-notify context "Built-in header restored")))
