(load (merge-pathnames "support.lisp" *load-truename*))

(dolist (tool
         (append
          (cadr-cli:make-coding-tools (uiop:getcwd))
          (list
           (cadr-cli:make-find-tool (uiop:getcwd))
           (cadr-cli:make-grep-tool (uiop:getcwd))
           (cadr-cli:make-ls-tool (uiop:getcwd)))))
  (let ((copy tool))
    (cadr-agent:define-rich-tool
     (cadr-ai:tool-name copy)
     :label (cadr-ai:tool-name copy)
     :description (cadr-ai:tool-description copy)
     :parameters (cadr-ai:tool-parameters copy)
     :render-shell :self
     :handler
     (lambda (call-id arguments signal on-update context)
       (declare (ignore signal on-update context))
       (example-execute-tool copy call-id arguments))
     :render-call
     (lambda (arguments render-context theme)
       (declare (ignore render-context theme))
       (format nil "$ ~A ~S" (cadr-ai:tool-name copy) arguments))
     :render-result
     (lambda (result options render-context theme)
       (declare (ignore render-context theme))
       (let ((text (example-tool-result-text result)))
         (if (getf options :expanded-p)
             text
             (if (member (cadr-ai:tool-name copy)
                         '("find" "grep" "ls") :test #'string=)
                 (let ((count
                         (count-if #'plusp
                                   (mapcar #'length
                                           (uiop:split-string
                                            text :separator '(#\Newline))))))
                   (if (plusp count)
                       (format nil " → ~D ~A"
                               count
                               (cond
                                 ((string= (cadr-ai:tool-name copy) "find") "files")
                                 ((string= (cadr-ai:tool-name copy) "grep") "matches")
                                 (t "entries")))
                       ""))
                 "")))))))
