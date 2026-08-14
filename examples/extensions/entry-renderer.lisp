(load (merge-pathnames "support.lisp" *load-truename*))

(cadr-agent:define-component-entry-renderer
 "status-card"
 :renderer
 (lambda (entry options theme)
   (let* ((data (getf entry :data))
          (message (or (getf data :message) "No data"))
          (tag
            (handler-case
                (example-theme-fg theme :accent "[status]")
              (error () "[status]")))
          (text (format nil "~A ~A" tag message)))
     (when (getf options :expanded-p)
       (let ((stamp (getf data :timestamp)))
         (when stamp
           (setf text
                 (format nil "~A~%~A" text
                         (handler-case
                             (example-theme-fg
                              theme :dim
                              (example-clock-date-time-string stamp))
                           (error () "")))))))
     (cadr-tui:make-text-component text :padding-x 1 :padding-y 1))))

(cadr-agent:define-command
 "status-card"
 :description "Render a durable status card that is not sent to the LLM"
 :handler
 (lambda (arguments context)
   (declare (ignore context))
   (let ((message (example-trim arguments)))
     (cadr-agent:extension-api-append-entry
      *example-api* "status-card"
      (list :message
            (if (zerop (length message)) "Status card" message)
            :timestamp (example-unix-milliseconds))))))
