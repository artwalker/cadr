(load (merge-pathnames "support.lisp" *load-truename*))

(defvar *border-status-working-p* nil)

(cadr-agent:define-event-hook
 :agent-start
 :handler (lambda (event context)
            (declare (ignore event context))
            (setf *border-status-working-p* t)))
(cadr-agent:define-event-hook
 :agent-end
 :handler (lambda (event context)
            (declare (ignore event context))
            (setf *border-status-working-p* nil)))
(cadr-agent:define-event-hook
 :session-shutdown
 :handler
 (lambda (event context)
   (declare (ignore event context))
   (setf *border-status-working-p* nil)))
(cadr-agent:define-event-hook
 :session-start
 :handler
 (lambda (event context)
   (declare (ignore event))
   (cadr-agent:extension-context-set-working-visible context nil)
   (cadr-agent:extension-context-set-footer
    context
    (lambda (tui theme footer-data)
      (declare (ignore tui theme footer-data))
      (cadr-tui:make-spacer-component 0)))
   (cadr-agent:extension-context-set-editor-component
    context
    (lambda (tui theme keybindings)
      (declare (ignore tui keybindings))
      (let ((fg (getf theme :fg)))
        (make-instance
         'example-editor-component
         :label
         (format nil "~:[idle~;working~] · thinking ~A · context ~A"
                 *border-status-working-p*
                 (cadr-agent:extension-api-get-thinking-level *example-api*)
                 (or (cadr-agent:extension-context-context-usage context) "—"))
         :style-function
         (lambda (text) (funcall fg :accent text))))))))
