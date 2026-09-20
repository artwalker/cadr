(in-package #:cadr-cli)

(defparameter +powershell-utf8-output-prefix+
  "try { [Console]::OutputEncoding=[System.Text.Encoding]::UTF8 } catch {}
")

(defun run-powershell-command (cwd command timeout)
  (declare (ignore timeout))
  (let* ((config (get-powershell-config))
         (full-command
           (concatenate 'string +powershell-utf8-output-prefix+ command)))
    (when (cadr-agent::current-tool-aborted-p)
      (error "Command aborted"))
    (multiple-value-bind (stdout stderr exit-code)
        (uiop:run-program
         (append
          (list (shell-config-shell config))
          (shell-config-arguments config)
          (list full-command))
         :directory cwd
         :output :string
         :error-output :string
         :ignore-error-status t)
      (let* ((full-output
               (cond
                 ((and (zerop (length stdout)) (plusp (length stderr)))
                  stderr)
                 ((and (plusp (length stdout)) (plusp (length stderr)))
                  (format nil "~A~%~A" stdout stderr))
                 (t stdout))))
        (multiple-value-bind (tail details)
            (truncate-tail full-output)
          (values
           (list
            (cadr-ai:make-text-content
             :text
             (format nil
                      "~A~:[~;~%~]Process exited with code ~D"
                      tail
                      (plusp (length tail))
                      exit-code)))
           (append (list :exit-code exit-code) details)))))))

(defun execute-powershell-tool-command (cwd command timeout)
  (multiple-value-bind (content details)
      (run-powershell-command cwd command timeout)
    (let* ((exit-code (getf details :exit-code))
           (text
             (bash-strip-exit-footer
              (cadr-ai:text-content-text (first content))
              exit-code)))
      (when (/= exit-code 0)
        (error
         (append-bash-status
          (if (plusp (length text)) text "(no output)")
          (format nil "Command exited with code ~D" exit-code))))
      (values
       (list
        (cadr-ai:make-text-content
         :text (if (plusp (length text)) text "(no output)")))
       details))))

(defun execute-powershell-tool-command-with-context
    (context cwd command timeout)
  (multiple-value-bind (result operation-error)
      (cadr-agent:execution-tool-exec
       context
       (concatenate 'string +powershell-utf8-output-prefix+ command)
       :cwd (namestring (uiop:ensure-directory-pathname cwd))
       :timeout timeout)
    (when operation-error
      (error
       "~A"
       (cadr-agent:harness-operation-error-message operation-error)))
    (let* ((stdout (cadr-agent:execution-result-stdout result))
           (stderr (cadr-agent:execution-result-stderr result))
           (output
             (cond
               ((zerop (length stderr)) stdout)
               ((zerop (length stdout)) stderr)
               (t (format nil "~A~%~A" stdout stderr))))
           (exit-code (cadr-agent:execution-result-exit-code result)))
      (unless (zerop exit-code)
        (error
         (append-bash-status
          output
          (format nil "Command exited with code ~D" exit-code))))
      (values
       (list (cadr-ai:make-text-content :text output))
       (list :exit-code exit-code)))))

(defun make-powershell-tool (cwd &key context)
  (cadr-ai:make-tool
   :name "powershell"
   :description
   "Execute a PowerShell command in the current working directory. Returns stdout and stderr. Output is truncated to last 2000 lines or 50KB (whichever is hit first). If truncated, full output is saved to a temp file. Optionally provide a timeout in seconds."
   :parameters
   (object-schema
    (cadr-ai::json-object
     "command" (string-property "PowerShell command to execute")
     "timeout"
     (number-property
      "Timeout in seconds (optional, no default timeout)"))
    '("command"))
   :constrained-sampling '(:type :json-schema :strict :prefer)
   :execution-mode :sequential
   :executor
   (lambda (call-id arguments)
     (declare (ignore call-id))
     (let ((command (required-string arguments "command"))
           (timeout (cadr-ai::json-get arguments "timeout")))
       (if context
           (execute-powershell-tool-command-with-context
            context cwd command timeout)
           (execute-powershell-tool-command cwd command timeout))))))
