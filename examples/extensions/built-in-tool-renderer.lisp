(load (merge-pathnames "support.lisp" *load-truename*))

(dolist (tool (cadr-cli:make-coding-tools (uiop:getcwd)))
  (let ((copy tool))
    (cadr-agent:define-rich-tool
     (cadr-ai:tool-name copy)
     :label (string-capitalize (cadr-ai:tool-name copy))
     :description (cadr-ai:tool-description copy)
     :parameters (cadr-ai:tool-parameters copy)
     :handler
     (lambda (call-id arguments signal on-update context)
       (declare (ignore signal on-update context))
       (example-execute-tool copy call-id arguments))
     :render-call
     (lambda (arguments render-context theme)
       (declare (ignore theme))
       (format nil "~A ~S~@[ · ~A~]"
               (cadr-ai:tool-name copy) arguments
               (getf render-context :cwd)))
     :render-result
     (lambda (result render-options render-context theme)
       (declare (ignore render-options render-context theme))
       (example-tool-result-text result)))))
