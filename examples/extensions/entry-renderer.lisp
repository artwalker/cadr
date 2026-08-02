(load (merge-pathnames "support.lisp" *load-truename*))

(cadr-agent:define-component-entry-renderer
 "status-card"
 :renderer
 (lambda (entry options theme)
   (declare (ignore theme))
   (let ((data (getf entry :data)))
     (cadr-tui:make-text-component
      (format nil "Status: ~A~%Detail: ~A~@[~%Recorded: ~A~]"
              (or (getf data :status) "unknown")
              (or (getf data :detail) "")
              (and (getf options :expanded-p)
                   (or (getf data :timestamp) "—")))
      :padding-x 0 :padding-y 0))))

(cadr-agent:define-command
 "status-card"
 :description "Append a rendered custom session entry"
 :handler
 (lambda (arguments context)
   (declare (ignore context))
   (cadr-agent:extension-api-append-entry
    *example-api* "status-card"
    (list :status "ok" :detail (example-trim arguments)
          :timestamp (get-universal-time)))))
