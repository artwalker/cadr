(load (merge-pathnames "support.lisp" *load-truename*))

(cadr-agent:define-event-hook
 :session-start
 :handler
 (lambda (event context)
   (declare (ignore event))
   (cadr-agent:extension-context-set-widget
    context "widget-above" '("Above editor widget"))
   (cadr-agent:extension-context-set-widget
    context "widget-below" '("Below editor widget")
    :placement :below-editor)))
