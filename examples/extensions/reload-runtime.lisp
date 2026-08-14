(load (merge-pathnames "support.lisp" *load-truename*))

(cadr-agent:define-command
 "reload-runtime"
 :description "Reload extensions, skills, prompts, themes, and context files"
 :handler
 (lambda (arguments context)
   (declare (ignore arguments))
   (cadr-agent:extension-context-reload context)))

(cadr-agent:define-rich-tool
 "reload_runtime"
 :label "Reload Runtime"
 :description "Reload extensions, skills, prompts, themes, and context files"
 :parameters (example-empty-schema)
 :handler
 (lambda (call-id arguments signal on-update context)
   (declare (ignore call-id arguments signal on-update context))
   (cadr-agent:extension-api-send-user-message
    *example-api* "/reload-runtime" :deliver-as :follow-up)
   (example-text-result
    "Queued /reload-runtime as a follow-up command.")))
