(load (merge-pathnames "support.lisp" *load-truename*))

(cadr-agent:define-command
 "overlay-test"
 :description "Exercise overlay focus, anchors, sizing, and handles"
 :handler
 (lambda (arguments context)
   (declare (ignore arguments))
   (let ((handle nil))
     (cadr-agent:extension-context-custom-component
      context
      (lambda (tui theme keybindings done)
        (declare (ignore tui theme keybindings))
        (make-instance
         'example-dialog-component
         :title "Overlay Test"
         :lines '("Overlay remains interactive and centered."
                  "The returned handle can hide, show, focus, and unfocus it.")
         :options '("Accept" "Cancel") :done done))
      :overlay-p t
      :overlay-options
      '(:width 52 :max-height 14 :anchor :center :margin 1
        :focus t :non-capturing nil)
      :on-handle (lambda (value) (setf handle value)))
     (when handle
       (cadr-agent:extension-context-notify
        context
        (format nil "Overlay hidden: ~:[false~;true~]"
                (cadr-tui:overlay-handle-hidden-p handle)))))))
