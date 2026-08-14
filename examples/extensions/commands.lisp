(load (merge-pathnames "support.lisp" *load-truename*))

(defun example-command-public-source (command)
  (let ((source (getf command :source)))
    (cond
      ((member source '(:extension "extension") :test #'equal) "extension")
      ((member source '(:prompt :prompt-template "prompt") :test #'equal) "prompt")
      ((member source '(:skill "skill") :test #'equal) "skill")
      (t nil))))

(defun example-format-command-line (command)
  (let ((description (getf command :description)))
    (if (and description (plusp (length description)))
        (format nil "/~A - ~A" (getf command :name) description)
        (format nil "/~A" (getf command :name)))))

(defun example-command-source-path (command)
  (getf (getf command :source-info) :path))

(cadr-agent:define-command
 "commands"
 :description "List available slash commands"
 :argument-hint "[extension|prompt|skill]"
 :handler
 (lambda (arguments context)
   (let* ((filter (example-trim arguments))
          (commands (cadr-agent:extension-api-get-commands *example-api*))
          (filtered
            (if (zerop (length filter))
                commands
                (remove-if-not
                 (lambda (command)
                   (string-equal filter (example-command-public-source command)))
                 commands))))
     (if (null filtered)
         (cadr-agent:extension-context-notify
          context
          (if (zerop (length filter))
              "No commands found"
              (format nil "No ~A commands found" filter)))
         (let ((items nil))
           (dolist (group '(("extension" "Extensions")
                            ("prompt" "Prompts")
                            ("skill" "Skills")))
             (let ((group-commands
                     (remove-if-not
                      (lambda (command)
                        (string= (first group)
                                 (example-command-public-source command)))
                      filtered)))
               (when group-commands
                 (push (format nil "--- ~A ---" (second group)) items)
                 (dolist (command group-commands)
                   (push (example-format-command-line command) items)))))
           (let ((selected
                   (cadr-agent:extension-context-select
                    context "Available Commands" (nreverse items))))
             (when (and selected
                        (not (uiop:string-prefix-p "---" selected)))
               (let* ((slash-name
                        (first (uiop:split-string selected :separator " - ")))
                      (name
                        (if (and (plusp (length slash-name))
                                 (char= (char slash-name 0) #\/))
                            (subseq slash-name 1)
                            slash-name))
                      (command
                        (find name commands
                              :key (lambda (entry) (getf entry :name))
                              :test #'string=))
                      (path (and command (example-command-source-path command))))
                 (when (and path
                            (cadr-agent:extension-context-confirm
                             context name
                             (format nil "View source path?~%~A" path)))
                   (cadr-agent:extension-context-notify context path))))))))))
