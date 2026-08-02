(load (merge-pathnames "support.lisp" *load-truename*))

(cadr-agent:define-event-hook
 :agent-start
 :handler
 (lambda (event context)
   (declare (ignore event))
   (cadr-agent:extension-context-set-status
    context "system-prompt"
    (format nil "System: ~D chars"
            (length (or (cadr-agent:extension-context-system-prompt context) ""))))))
(cadr-agent:define-event-hook
 :session-shutdown
 :handler (lambda (event context)
            (declare (ignore event))
            (cadr-agent:extension-context-set-status context "system-prompt" nil)))
