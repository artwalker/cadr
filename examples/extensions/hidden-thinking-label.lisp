(load (merge-pathnames "support.lisp" *load-truename*))

(defparameter +default-thinking-label+ "Pondering...")

(defvar *hidden-thinking-label* +default-thinking-label+)

(cadr-agent:define-event-hook
 :session-start
 :handler
 (lambda (event context)
   (declare (ignore event))
   (cadr-agent:extension-context-set-hidden-thinking-label
    context *hidden-thinking-label*)
   nil))

(cadr-agent:define-command
 "thinking-label"
 :description "Set the hidden thinking label. Use without args to reset."
 :handler
 (lambda (arguments context)
   (let ((label (example-trim arguments)))
     (if (zerop (length label))
         (progn
           (setf *hidden-thinking-label* +default-thinking-label+)
           (cadr-agent:extension-context-set-hidden-thinking-label
            context nil)
           (cadr-agent:extension-context-notify
            context (format nil "Hidden thinking label reset to: ~A"
                            +default-thinking-label+)))
         (progn
           (setf *hidden-thinking-label* label)
           (cadr-agent:extension-context-set-hidden-thinking-label
            context label)
           (cadr-agent:extension-context-notify
            context (format nil "Hidden thinking label set to: ~A"
                            label)))))))
