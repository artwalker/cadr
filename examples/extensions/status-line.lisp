(load (merge-pathnames "support.lisp" *load-truename*))

(cadr-agent:define-event-hook
 :session-start
 :handler (lambda (event context)
            (declare (ignore event))
            (cadr-agent:extension-context-set-status context "status-demo" "Ready")))
(cadr-agent:define-event-hook
 :turn-start
 :handler (lambda (event context)
            (declare (ignore event))
            (cadr-agent:extension-context-set-status context "status-demo" "⠋ Working")))
(cadr-agent:define-event-hook
 :turn-end
 :handler (lambda (event context)
            (declare (ignore event))
            (cadr-agent:extension-context-set-status context "status-demo" "✓ Done")))
