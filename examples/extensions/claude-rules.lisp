(load (merge-pathnames "support.lisp" *load-truename*))

(defparameter *claude-rule-files* nil)

(defun example-claude-rule-files (directory &optional (prefix ""))
  (when (probe-file directory)
    (let ((files nil))
      (dolist (path (uiop:directory-files directory "*.md"))
        (push (concatenate 'string prefix (file-namestring path)) files))
      (dolist (child (uiop:subdirectories directory))
        (let* ((name
                 (car (last (pathname-directory child))))
               (next-prefix
                 (format nil "~A~A/" prefix name)))
          (setf files
                (nconc files
                       (example-claude-rule-files child next-prefix)))))
      (sort files #'string<))))

(cadr-agent:define-event-hook
 :session-start
 :handler
 (lambda (event context)
   (declare (ignore event))
   (setf *claude-rule-files*
         (example-claude-rule-files
          (merge-pathnames ".claude/rules/"
                           (cadr-agent:extension-context-cwd context))))
   (when *claude-rule-files*
     (cadr-agent:extension-context-notify
      context
      (format nil "Found ~D rule(s) in .claude/rules/"
              (length *claude-rule-files*))))))

(cadr-agent:define-event-hook
 :before-agent-start
 :handler
 (lambda (event context)
   (declare (ignore context))
   (when *claude-rule-files*
     (list
      :system-prompt
      (format nil
              "~A~%~%## Project Rules~%~%The following project rules are available in .claude/rules/:~%~%~{- .claude/rules/~A~%~}~%When working on tasks related to these rules, use the read tool to load the relevant rule files for guidance."
              (example-event-value event :system-prompt)
              *claude-rule-files*)))))
