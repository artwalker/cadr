(load (merge-pathnames "support.lisp" *load-truename*))

(defun dirty-repo-guard (context action)
  (let* ((result (example-exec "git" '("status" "--porcelain")))
         (changed (count #\Newline (example-exec-output result))))
    (when (and (plusp changed)
               (cadr-agent:extension-context-has-ui-p context)
               (not (cadr-agent:extension-context-confirm
                     context "Uncommitted changes"
                     (format nil "You have ~D uncommitted file(s). ~A anyway?"
                             changed action))))
      (cadr-agent:extension-context-notify
       context "Commit your changes first" :level :warning)
      (cadr-agent:make-extension-hook-result
       :block-p t :reason "Uncommitted changes"))))

(cadr-agent:define-event-hook
 :session-before-switch
 :handler (lambda (event context)
            (declare (ignore event))
            (dirty-repo-guard context "Switch")))
(cadr-agent:define-event-hook
 :session-before-fork
 :handler (lambda (event context)
            (declare (ignore event))
            (dirty-repo-guard context "Fork")))
