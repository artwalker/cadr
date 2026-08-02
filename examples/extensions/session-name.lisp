(load (merge-pathnames "support.lisp" *load-truename*))

(cadr-agent:define-command
 "session-name"
 :description "Set or show session name (usage: /session-name [new name])"
 :handler
 (lambda (arguments context)
   (let ((name (example-trim arguments)))
     (if (plusp (length name))
         (progn
           (cadr-agent:extension-context-set-session-name context name)
           (cadr-agent:extension-context-notify
            context (format nil "Session named: ~A" name)))
         (let ((current
                 (cadr-agent:session-name
                  (cadr-agent:extension-context-session context))))
           (cadr-agent:extension-context-notify
            context (if current (format nil "Session: ~A" current)
                        "No session name set")))))))
