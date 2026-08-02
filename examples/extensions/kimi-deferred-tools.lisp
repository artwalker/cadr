(load (merge-pathnames "support.lisp" *load-truename*))

(cadr-agent:define-rich-tool
 "Calculator"
 :label "Calculator"
 :description "Evaluate simple arithmetic expressions"
 :parameters (example-object-schema "expression" "string" "Arithmetic expression")
 :handler
 (lambda (call-id arguments signal on-update context)
   (declare (ignore call-id signal on-update context))
   (let ((expression (example-argument arguments "expression" "0")))
     (if (every (lambda (character)
                  (or (digit-char-p character)
                      (find character "+-*/(). " :test #'char=)))
                expression)
         (example-result (format nil "Expression accepted: ~A" expression))
         (example-result "Only arithmetic characters are accepted")))))

(cadr-agent:define-rich-tool
 "tool_search"
 :label "Tool Search"
 :description "Activate deferred tools by name"
 :parameters (example-object-schema "names" "string" "Comma-separated tool names")
 :handler
 (lambda (call-id arguments signal on-update context)
   (declare (ignore call-id signal on-update context))
   (let* ((requested
            (uiop:split-string
             (example-argument arguments "names" "") :separator '(#\,)))
          (available
            (mapcar (lambda (tool) (getf tool :name))
                    (cadr-agent:extension-api-get-all-tools *example-api*)))
          (added
            (intersection requested available :test #'string=))
          (active (cadr-agent:extension-api-get-active-tools *example-api*)))
     (cadr-agent:extension-api-set-active-tools
      *example-api* (remove-duplicates (append active added) :test #'string=))
     (example-result (format nil "Activated: ~{~A~^, ~}" added)))))

(cadr-agent:define-event-hook
 :session-start
 :handler
 (lambda (event context)
   (declare (ignore event context))
   (cadr-agent:extension-api-set-active-tools *example-api* '("tool_search"))))
