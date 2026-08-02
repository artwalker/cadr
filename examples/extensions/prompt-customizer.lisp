(load (merge-pathnames "support.lisp" *load-truename*))

(defun prompt-customizer-skill-name (skill)
  (cond
    ((typep skill 'cadr-agent:skill) (cadr-agent:skill-name skill))
    ((and (listp skill) (getf skill :name)) (getf skill :name))
    (t nil)))

(defun prompt-customizer-guidance (options base-prompt)
  (let ((tools (getf options :selected-tools))
        (parts nil))
    (labels ((has-tool-p (name)
               (member name tools :test #'string=))
             (add (&rest lines)
               (setf parts (nconc parts lines))))
      (when (has-tool-p "read")
        (add
         "• Use the `read` tool for file contents (supports text and images)."
         "  - For large files, use `offset` and `limit` to read in chunks."))
      (when (has-tool-p "bash")
        (add "• Execute commands with the `bash` tool. Use it for file operations like `ls`, `find`, `grep`."))
      (when (has-tool-p "edit")
        (add "• Use the `edit` tool for precise text replacements in files. Match exact content including whitespace."))
      (when (has-tool-p "write")
        (add "• Use the `write` tool to create new files or overwrite existing ones completely."))
      (let ((skill-names
              (remove nil
                      (mapcar #'prompt-customizer-skill-name
                              (getf options :skills)))))
        (when skill-names
          (add
           (format nil "~%Available skills: ~{~A~^, ~}" skill-names)
           "Use skill documentation for best practices on specific tools.")))
      (if parts
          (format nil "~A~%~%## Tool Guidance~%~%~{~A~^~%~}~%"
                  base-prompt parts)
          base-prompt))))

(defun prompt-customizer-append-section (options)
  (let ((extension
          (format nil
                  "~%## Extension-Added Context~%~%This prompt includes tool guidance and skill information loaded dynamically.~%If you have additional requirements, configure them via --append-system-prompt or project context files.~%"))
        (user (getf options :append-system-prompt)))
    (if user
        (format nil "~A~%~%~A" user extension)
        extension)))

(cadr-agent:define-event-hook
 :before-agent-start
 :handler
 (lambda (event context)
   (declare (ignore context))
   (let* ((payload (cadr-agent:extension-event-payload event))
          (options (getf payload :system-prompt-options))
          (base (getf payload :system-prompt)))
     (list
      :system-prompt
      (concatenate
       'string
       (prompt-customizer-guidance options base)
       (prompt-customizer-append-section options))))))
