(load (merge-pathnames "support.lisp" *load-truename*))

(cadr-agent:define-event-hook
 :session-start
 :handler
 (lambda (event context)
   (declare (ignore event))
   (cadr-agent:extension-context-set-editor-component
    context
    (lambda (tui theme keybindings)
      (declare (ignore tui keybindings))
      (let ((fg (getf theme :fg)))
        (make-instance
         'example-editor-component
         :label "Rainbow editor"
         :style-function
         (lambda (text) (funcall fg :accent text))))))))
