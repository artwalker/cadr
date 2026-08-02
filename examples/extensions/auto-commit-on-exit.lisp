(load (merge-pathnames "support.lisp" *load-truename*))

(cadr-agent:define-event-hook
 :session-shutdown
 :handler
 (lambda (event context)
   (declare (ignore event))
   (when (cadr-agent:extension-context-has-ui-p context)
     (let ((status (example-exec "git" '("status" "--porcelain"))))
       (when (plusp (length (example-trim (example-exec-output status))))
         (example-exec "git" '("add" "-A"))
         (let ((commit
                 (example-exec
                  "git" '("commit" "-m" "chore: auto-commit session changes"))))
           (when (zerop (example-exec-code commit))
             (cadr-agent:extension-context-notify
              context "Auto-committed: chore: auto-commit session changes"))))))))
