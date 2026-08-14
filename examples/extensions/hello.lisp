(load (merge-pathnames "support.lisp" *load-truename*))

(cadr-agent:define-rich-tool
 "hello"
 :label "Hello"
 :description "A simple greeting tool"
 :parameters (example-object-schema "name" "string" "Name to greet")
 :handler
 (lambda (call-id arguments signal on-update context)
   (declare (ignore call-id signal on-update context))
   (let ((name (example-argument arguments "name" "world")))
     (example-text-result
      (format nil "Hello, ~A!" name)
      (list :greeted name)))))
