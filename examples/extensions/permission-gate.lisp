(load (merge-pathnames "support.lisp" *load-truename*))

(cadr-agent:define-event-hook
 :tool-call-before
 :handler
 (lambda (event context)
   (let* ((call (cadr-agent:extension-event-tool-call event))
          (name (and call (cadr-ai:tool-call-name call)))
          (arguments (and call (cadr-ai:tool-call-arguments call)))
          (command (and arguments (gethash "command" arguments))))
     (when (and (string= (or name "") "bash")
                (stringp command)
                (some (lambda (needle) (search needle command :test #'char-equal))
                      '("rm -rf" "git reset --hard" "sudo "))
                (cadr-agent:extension-context-has-ui-p context)
                (not (cadr-agent:extension-context-confirm
                      context "Dangerous command" command)))
       (cadr-agent:make-extension-hook-result
        :block-p t :reason "Command blocked by user")))))
