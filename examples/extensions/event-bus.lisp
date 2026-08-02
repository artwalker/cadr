(load (merge-pathnames "support.lisp" *load-truename*))

(cadr-agent:extension-api-events-on
 *example-api* "my:notification"
 (lambda (payload)
   (declare (ignore payload))))

(cadr-agent:define-command
 "emit"
 :description "Emit an extension-local event"
 :handler
 (lambda (arguments context)
   (declare (ignore context))
   (cadr-agent:extension-api-events-emit
    *example-api* "my:notification"
    (list :message (example-trim arguments) :from "/emit command"))))

(cadr-agent:define-event-hook
 :session-start
 :handler
 (lambda (event context)
   (declare (ignore event context))
   (cadr-agent:extension-api-events-emit
    *example-api* "my:notification"
    '(:message "Session started" :from "session_start"))))
