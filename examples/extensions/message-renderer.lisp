(load (merge-pathnames "support.lisp" *load-truename*))

(cadr-agent:define-component-message-renderer
 "status-update"
 :renderer
 (lambda (message options theme)
   (declare (ignore theme))
   (let ((content (or (getf message :content) "")))
     (cadr-tui:make-text-component
      (format nil "[status] ~A~@[~%details: ~S~]"
              content
              (and (getf options :expanded-p)
                   (getf message :details)))
      :padding-x (or (getf options :output-pad) 0)
      :padding-y 0))))

(cadr-agent:define-command
 "status"
 :description "Send a custom rendered status message"
 :handler
 (lambda (arguments context)
   (declare (ignore context))
   (cadr-agent:extension-api-send-message
    *example-api*
    (list :custom-type "status-update"
          :content (or (example-trim arguments) "ready")
          :details '(:source :extension)
          :display-p t))))
