(load (merge-pathnames "support.lisp" *load-truename*))

(cadr-agent:define-command
 "quit"
 :description "Exit cadr cleanly"
 :handler (lambda (arguments context)
            (declare (ignore arguments))
            (cadr-agent:extension-context-shutdown context)))

(flet ((shutdown-handler
           (call-id arguments signal on-update context)
         (declare (ignore call-id arguments signal on-update))
         (cadr-agent:extension-context-shutdown context)
         (example-result "Shutdown requested" :terminate-p t)))
  (cadr-agent:define-rich-tool
   "finish_and_exit"
   :label "Finish the task and exit cadr"
   :description "Finish the task and exit cadr"
   :parameters (example-empty-schema)
   :handler #'shutdown-handler)
  (cadr-agent:define-rich-tool
   "deploy_and_exit"
   :label "Deploy, then exit cadr"
   :description "Deploy, then exit cadr"
   :parameters (example-empty-schema)
   :handler #'shutdown-handler))
