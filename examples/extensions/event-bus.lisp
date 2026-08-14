(load (merge-pathnames "support.lisp" *load-truename*))

(defvar *example-event-bus-context* nil)

(cadr-agent:define-event-hook
 :session-start
 :handler
 (lambda (event context)
   (declare (ignore event))
   (setf *example-event-bus-context* context)
   (cadr-agent:extension-api-events-emit
    *example-api* "my:notification"
    '(:message "Session started" :from "event-bus-example"))))

(cadr-agent:extension-api-events-on
 *example-api* "my:notification"
 (lambda (payload)
   (let ((context *example-event-bus-context*))
     (when context
       (cadr-agent:extension-context-notify
        context
        (format nil "Event from ~A: ~A"
                (or (getf payload :from) "")
                (or (getf payload :message) "")))))))

(cadr-agent:define-command
 "emit"
 :description "Emit my:notification event (usage: /emit message)"
 :handler
 (lambda (arguments context)
   (setf *example-event-bus-context* context)
   (let ((message (example-trim arguments)))
     (cadr-agent:extension-api-events-emit
      *example-api* "my:notification"
      (list :message (if (plusp (length message)) message "hello")
            :from "/emit command")))))
