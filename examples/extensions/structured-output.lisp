(load (merge-pathnames "support.lisp" *load-truename*))

(cadr-agent:define-rich-tool
 "structured_output"
 :label "Structured Output"
 :description "Return a validated release decision and terminate the run"
 :prompt-snippet "Use structured_output for the final release decision"
 :parameters
 (example-object-schema
  "status" "string" "Release status"
  "summary" "string" "Decision summary")
 :constrained-sampling '(:kind :json-schema)
 :render-shell :self
 :handler
 (lambda (call-id arguments signal on-update context)
   (declare (ignore call-id signal on-update context))
   (example-result
    (format nil "~A: ~A"
            (example-argument arguments "status" "unknown")
            (example-argument arguments "summary" ""))
    :details arguments
    :terminate-p t))
 :render-call
 (lambda (arguments render-context theme)
   (declare (ignore render-context theme))
   (format nil "Release decision: ~A"
           (example-argument arguments "status" "unknown")))
 :render-result
 (lambda (result options render-context theme)
   (declare (ignore options render-context theme))
   (example-tool-result-text result)))
