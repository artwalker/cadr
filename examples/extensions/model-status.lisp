(load (merge-pathnames "support.lisp" *load-truename*))

(cadr-agent:define-event-hook
 :model-select
 :handler
 (lambda (event context)
   (let ((model (example-event-value event :model))
         (previous (example-event-value event :previous-model))
         (source (example-event-value event :source)))
     (unless (eq source :restore)
       (cadr-agent:extension-context-notify
        context
        (format nil "Model: ~A/~A"
                (cadr-ai:model-provider model)
                (cadr-ai:model-id model))))
     (cadr-agent:extension-context-set-status
      context "model" (format nil "🤖 ~A" (cadr-ai:model-id model)))
     (format *trace-output* "[model_select] ~A → ~A/~A (~(~A~))~%"
             (if previous
                 (format nil "~A/~A"
                         (cadr-ai:model-provider previous)
                         (cadr-ai:model-id previous))
                 "none")
             (cadr-ai:model-provider model)
             (cadr-ai:model-id model)
             source))))
