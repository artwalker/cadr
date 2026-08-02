(load (merge-pathnames "support.lisp" *load-truename*))

(cadr-agent:define-command
 "commands"
 :description "Browse all registered commands and their source"
 :argument-hint "[extension|prompt|builtin]"
 :handler
 (lambda (arguments context)
   (let* ((filter (example-trim arguments))
          (commands (cadr-agent:extension-api-get-commands *example-api*))
          (visible
            (if (zerop (length filter))
                commands
                (remove-if-not
                 (lambda (command)
                   (string-equal filter (princ-to-string (getf command :source))))
                 commands))))
     (if visible
         (example-show-dialog
          context "Available Commands"
          (mapcar
           (lambda (command)
             (format nil "/~A — ~A"
                     (getf command :name)
                     (or (getf command :description) "")))
           visible))
         (cadr-agent:extension-context-notify
          context
          (if (zerop (length filter))
              "No commands found"
              (format nil "No ~A commands found" filter)))))))
