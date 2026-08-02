(load (merge-pathnames "support.lisp" *load-truename*))

(defparameter +default-thinking-label+ "Thinking...")

(cadr-agent:define-event-hook
 :session-start
 :handler
 (lambda (event context)
   (declare (ignore event))
   (cadr-agent:extension-context-set-hidden-thinking-label
    context +default-thinking-label+)))

(cadr-agent:define-command
 "thinking-label"
 :description "Set or reset the hidden thinking label"
 :handler
 (lambda (arguments context)
   (let ((label (example-trim arguments)))
     (if (zerop (length label))
         (progn
           (cadr-agent:extension-context-set-hidden-thinking-label context nil)
           (cadr-agent:extension-context-notify
            context (format nil "Hidden thinking label reset to: ~A"
                            +default-thinking-label+)))
         (progn
           (cadr-agent:extension-context-set-hidden-thinking-label context label)
           (cadr-agent:extension-context-notify
            context (format nil "Hidden thinking label set to: ~A" label)))))))
