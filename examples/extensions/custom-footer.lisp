(load (merge-pathnames "support.lisp" *load-truename*))

(cadr-agent:define-command
 "footer"
 :description "Toggle the custom footer"
 :handler
 (let ((enabled-p nil))
   (lambda (arguments context)
     (declare (ignore arguments))
     (setf enabled-p (not enabled-p))
     (if enabled-p
         (progn
           (cadr-agent:extension-context-set-footer
            context
            (lambda (tui theme footer-data)
              (declare (ignore tui theme footer-data))
              (cadr-tui:make-text-component
               "cadr custom footer · extension statuses stay live"
               :padding-x 1 :padding-y 0)))
           (cadr-agent:extension-context-notify context "Custom footer enabled"))
         (progn
           (cadr-agent:extension-context-set-footer context nil)
           (cadr-agent:extension-context-notify context "Default footer restored"))))))
