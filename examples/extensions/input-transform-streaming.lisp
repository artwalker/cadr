(load (merge-pathnames "support.lisp" *load-truename*))

(cadr-agent:define-event-hook
 :input
 :handler
 (lambda (event context)
   (declare (ignore context))
   (let* ((payload (cadr-agent:extension-event-payload event))
          (text (getf payload :text)))
     (if (or (eq :steer (getf payload :streaming-behavior))
             (not (cl-ppcre:scan "(?i)\\b(changes?|diff|modified)\\b" text)))
         '(:action :continue)
         (let* ((result (example-exec "git" '("diff" "--stat")))
                (output (example-trim (example-exec-output result))))
           (if (or (not (zerop (example-exec-code result)))
                   (zerop (length output)))
               '(:action :continue)
               (list :action :transform
                     :text
                     (format nil "~A~%~%Current uncommitted changes:~%```~%~A~%```"
                             text output))))))))
