(load (merge-pathnames "support.lisp" *load-truename*))

(cadr-agent:define-rich-tool
 "question"
 :label "Question"
 :description "Ask the user to select or enter an answer"
 :parameters
 (example-object-schema
  "question" "string" "Question to ask"
  "options" "string" "Pipe-separated choices")
 :handler
 (lambda (call-id arguments signal on-update context)
   (declare (ignore call-id signal on-update))
   (if (not (cadr-agent:extension-context-has-ui-p context))
       (example-result "Question requires TUI mode")
       (let* ((question (example-argument arguments "question" "Question"))
              (options
                (remove-if
                 (lambda (item) (zerop (length item)))
                 (mapcar #'example-trim
                         (uiop:split-string
                          (example-argument arguments "options" "Yes|No")
                          :separator '(#\|)))))
              (answer
                (cadr-agent:extension-context-select
                 context question (append options '("Custom answer")))))
         (if (string= answer "Custom answer")
             (example-result
              (or (cadr-agent:extension-context-input
                   context "Custom answer" :placeholder "Type answer")
                  "Cancelled"))
             (example-result (or answer "Cancelled")))))))
