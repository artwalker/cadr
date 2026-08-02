(load (merge-pathnames "support.lisp" *load-truename*))

(cadr-agent:define-event-hook
 :tool-call-before
 :handler
 (lambda (event context)
   (let* ((call (cadr-agent:extension-event-tool-call event))
          (name (and call (cadr-ai:tool-call-name call)))
          (arguments (and call (cadr-ai:tool-call-arguments call)))
          (path (and arguments (gethash "path" arguments))))
     (when (and (member name '("write" "edit") :test #'string=)
                (stringp path)
                (or (search ".git/" path) (search ".env" path)))
       (cadr-agent:extension-context-notify
        context (format nil "Blocked write to protected path: ~A" path)
        :level :warning)
       (cadr-agent:make-extension-hook-result
        :block-p t :reason "Protected path")))))
