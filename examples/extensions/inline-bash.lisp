(load (merge-pathnames "support.lisp" *load-truename*))

(cadr-agent:define-event-hook
 :input
 :handler
 (lambda (event context)
   (let* ((text (or (example-event-value event :text) ""))
          (start (search "$(" text)))
     (if (null start)
         nil
         (let ((end (position #\) text :start (+ start 2))))
           (if (null end)
               nil
               (let* ((command (subseq text (+ start 2) end))
                      (result
                        (example-exec
                         "bash" (list "-lc" command)
                         :cwd (namestring
                               (cadr-agent:extension-context-cwd context))))
                      (expanded (example-trim (example-exec-output result))))
                 (when (cadr-agent:extension-context-has-ui-p context)
                   (cadr-agent:extension-context-notify
                    context (format nil "Expanded inline command: ~A" command)))
                 (list :action :transform
                       :text (concatenate
                              'string (subseq text 0 start) expanded
                              (subseq text (1+ end)))
                       :images (example-event-value event :images)))))))))
