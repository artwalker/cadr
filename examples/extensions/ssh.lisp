(load (merge-pathnames "support.lisp" *load-truename*))

(defvar *ssh-target* nil)
(defvar *ssh-remote-cwd* nil)
(defparameter *ssh-local-cwd* (uiop:getcwd))

(defun ssh-command (command &key timeout-ms)
  (unless *ssh-target*
    (error "SSH target is not configured"))
  (let ((result
          (example-call-program
           "ssh"
           (list "-o" "BatchMode=yes" "-o" "ConnectTimeout=10"
                 *ssh-target* command)
           :timeout-ms (or timeout-ms 120000))))
    (unless (zerop (example-exec-code result))
      (error "SSH failed (~D): ~A"
             (example-exec-code result)
             (example-exec-error result)))
    (example-exec-output result)))

(defun ssh-remote-path (path)
  (let* ((local (namestring (truename *ssh-local-cwd*)))
         (text (or path ".")))
    (if (uiop:string-prefix-p local text)
        (concatenate 'string *ssh-remote-cwd* (subseq text (length local)))
        (if (and (plusp (length text)) (char= (char text 0) #\/))
            text
            (format nil "~A/~A" (string-right-trim "/" *ssh-remote-cwd*) text)))))

(defun ssh-write-text (path content)
  (let* ((bytes (sb-ext:string-to-octets content :external-format :utf-8))
         (base64 (cadr-cli::encode-base64-bytes bytes))
         (remote (ssh-remote-path path)))
    (ssh-command
     (format nil "mkdir -p ~A && printf %s ~A | base64 -d > ~A"
             (cadr-cli::shell-quote
              (namestring (make-pathname :directory
                                         (pathname-directory remote))))
             (cadr-cli::shell-quote base64)
             (cadr-cli::shell-quote remote)))))

(defun ssh-execute-tool (name call-id arguments signal on-update context)
  (when (cadr-agent:extension-cancellation-aborted-p signal)
    (return-from ssh-execute-tool (example-result "SSH command cancelled")))
  (if (null *ssh-target*)
      (let ((tool
              (find name
                    (cadr-cli:make-coding-tools
                     (cadr-agent:extension-context-cwd context))
                    :key #'cadr-ai:tool-name :test #'string=)))
        (example-execute-tool tool call-id arguments))
      (progn
        (funcall on-update (format nil "Running ~A via SSH…" name))
        (cond
          ((string= name "read")
           (let* ((path (ssh-remote-path
                         (example-argument arguments "path" "")))
                  (offset (max 0 (or (example-argument arguments "offset" 0) 0)))
                  (limit (example-argument arguments "limit" nil))
                  (range
                    (if limit
                        (format nil "~D,~Dp" (max 1 offset)
                                (+ (max 1 offset) limit -1))
                        (format nil "~D,$p" (max 1 offset)))))
             (example-result
              (ssh-command
               (format nil "sed -n ~A ~A"
                       (cadr-cli::shell-quote range)
                       (cadr-cli::shell-quote path))))))
          ((string= name "write")
           (let ((path (example-argument arguments "path" ""))
                 (content (example-argument arguments "content" "")))
             (ssh-write-text path content)
             (example-result
              (format nil "Successfully wrote ~D bytes to ~A"
                      (cadr-cli::utf16-code-unit-length content) path))))
          ((string= name "edit")
           (let* ((path (example-argument arguments "path" ""))
                  (old (example-argument arguments "oldText" ""))
                  (new (example-argument arguments "newText" ""))
                  (remote (ssh-remote-path path))
                  (content
                    (ssh-command
                     (format nil "cat ~A" (cadr-cli::shell-quote remote))))
                  (start (search old content)))
             (unless start
               (error "Could not find the exact text in ~A" path))
             (when (search old content :start2 (+ start (length old)))
               (error "Found multiple matches for the text in ~A" path))
             (ssh-write-text
              path
              (concatenate 'string (subseq content 0 start) new
                           (subseq content (+ start (length old)))))
             (example-result (format nil "Successfully replaced text in ~A" path))))
          ((string= name "bash")
           (let* ((command (example-argument arguments "command" ""))
                  (timeout (example-argument arguments "timeout" 120))
                  (output
                    (ssh-command
                     (format nil "cd ~A && ~A"
                             (cadr-cli::shell-quote *ssh-remote-cwd*) command)
                     :timeout-ms (* 1000 timeout))))
             (example-result output)))
          (t (error "Unsupported SSH tool: ~A" name))))))

(cadr-agent:define-flag
 "ssh" :description "SSH remote: user@host or user@host:/path"
 :type :string :default nil)

(dolist (tool (cadr-cli:make-coding-tools *ssh-local-cwd*))
  (let ((copy tool))
    (cadr-agent:define-rich-tool
     (cadr-ai:tool-name copy)
     :label (cadr-ai:tool-name copy)
     :description (cadr-ai:tool-description copy)
     :parameters (cadr-ai:tool-parameters copy)
     :execution-mode (cadr-ai:tool-execution-mode copy)
     :handler
     (lambda (call-id arguments signal on-update context)
       (ssh-execute-tool (cadr-ai:tool-name copy)
                         call-id arguments signal on-update context)))))

(cadr-agent:define-event-hook
 :session-start
 :handler
 (lambda (event context)
   (declare (ignore event))
   (let ((argument
           (cadr-agent:extension-api-get-flag *example-api* "ssh")))
     (when (and (stringp argument) (plusp (length argument)))
       (let ((colon (position #\: argument :from-end t)))
         (if colon
             (setf *ssh-target* (subseq argument 0 colon)
                   *ssh-remote-cwd* (subseq argument (1+ colon)))
             (setf *ssh-target* argument
                   *ssh-remote-cwd* (example-trim (ssh-command "pwd")))))
       (cadr-agent:extension-context-set-status
        context "ssh" (format nil "SSH: ~A:~A" *ssh-target* *ssh-remote-cwd*))
       (cadr-agent:extension-context-notify
        context (format nil "SSH mode: ~A:~A" *ssh-target* *ssh-remote-cwd*))))))

(cadr-agent:define-event-hook
 :user-bash
 :handler
 (lambda (event context)
   (declare (ignore context))
   (when *ssh-target*
     (let ((command (or (example-event-value event :command) "")))
       (list
        :operations
        (lambda (ignored-command ignored-cwd timeout)
          (declare (ignore ignored-command ignored-cwd))
          (let ((output
                  (ssh-command
                   (format nil "cd ~A && ~A"
                           (cadr-cli::shell-quote *ssh-remote-cwd*) command)
                   :timeout-ms (and timeout (* timeout 1000)))))
            (values output (list :exit-code 0)))))))))

(cadr-agent:define-event-hook
 :before-agent-start
 :handler
 (lambda (event context)
   (declare (ignore context))
   (when *ssh-target*
     (list
      :system-prompt
      (cadr-ai::replace-all
       (example-event-value event :system-prompt)
       (format nil "Current working directory: ~A" (namestring *ssh-local-cwd*))
       (format nil "Current working directory: ~A (via SSH: ~A)"
               *ssh-remote-cwd* *ssh-target*))))))
