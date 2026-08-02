(load (merge-pathnames "support.lisp" *load-truename*))

(cadr-agent:define-rich-tool
 "hello"
 :label "Hello"
 :description "Say hello to a named person"
 :prompt-snippet "Use hello for a friendly greeting"
 :prompt-guidelines '("Preserve the supplied name exactly.")
 :parameters (example-object-schema "name" "string" "Name to greet")
 :handler
 (lambda (call-id arguments signal on-update context)
   (declare (ignore call-id signal on-update context))
   (example-result
    (format nil "Hello, ~A!" (example-argument arguments "name" "world"))
    :details '(:kind :greeting))))
