(load (merge-pathnames "support.lisp" *load-truename*))

(cadr-agent:define-event-hook
 :session-start
 :handler
 (lambda (event context)
   (declare (ignore event))
   (cadr-agent:extension-context-set-working-message
    context "Cooking tokens...")
   (cadr-agent:extension-context-set-working-indicator
    context :frames '("◐" "◓" "◑" "◒") :interval-ms 100)))
