(load (merge-pathnames "support.lisp" *load-truename*))

(let ((bash (cadr-cli:make-bash-tool (uiop:getcwd))))
  (cadr-agent:define-rich-tool
   "bash"
   :label "Bash (spawn hook)"
   :description (cadr-ai:tool-description bash)
   :parameters (cadr-ai:tool-parameters bash)
   :handler
   (lambda (call-id arguments signal on-update context)
     (declare (ignore signal on-update context))
     (let ((result
             (example-exec
              "sh"
              (list "-c"
                    (format nil
                            "printf '[spawn-hook] ' >&2; exec /bin/bash -lc ~S"
                            (example-argument arguments "command" "")))
              :cwd (namestring (uiop:getcwd)))))
       (values
        (concatenate 'string
                     (example-exec-output result)
                     (example-exec-error result))
        (list :exit-code (example-exec-code result))
        nil)))))
