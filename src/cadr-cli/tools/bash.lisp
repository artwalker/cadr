(in-package #:cadr-cli)

(defvar *bash-live-output* nil)

(defstruct user-bash-result
  (command "" :type string)
  (output "" :type string)
  exit-code
  (cancelled-p nil :type boolean)
  (truncated-p nil :type boolean)
  full-output-path
  (exclude-from-context-p nil :type boolean))

(define-condition user-bash-aborted (error)
  ((message
    :initarg :message
    :reader user-bash-aborted-message)
   (content
    :initarg :content
    :reader user-bash-aborted-content)
   (details
    :initarg :details
    :reader user-bash-aborted-details))
  (:report
   (lambda (condition stream)
     (write-string
      (user-bash-aborted-message condition)
      stream))))

(defun bash-live-output-for-mode (mode frontend-output)
  (case mode
    (:repl frontend-output)
    ;; RUN-TUI installs an entry-local stream.  Preserve it through the
    ;; bootstrap's mode projection instead of replacing it with NIL.
    (:tui *bash-live-output*)
    (otherwise *error-output*)))

(defun bash-strip-exit-footer (text exit-code)
  (let ((footer
          (format nil
                  "Process exited with code ~D"
                  exit-code)))
    (cond
      ((string= text footer)
       "")
      ((and
        (> (length text) (length footer))
        (string=
         footer text
         :start2 (- (length text)
                    (length footer))))
       (let ((end
               (- (length text)
                  (length footer))))
         (if (and
              (plusp end)
              (char= #\Newline
                     (char text (1- end))))
             (subseq text 0 (1- end))
             (subseq text 0 end))))
      (t text))))

(defun bash-strip-status-footer (text status)
  (cond
    ((string= text status) "")
    ((and (> (length text) (length status))
          (string= status text
                   :start2 (- (length text) (length status))))
     (string-right-trim
      '(#\Space #\Tab #\Newline #\Return)
      (subseq text 0 (- (length text) (length status)))))
    (t text)))

(defun bash-strip-truncation-footer (text)
  (let ((footer-start
          (and (plusp (length text))
               (char= #\] (char text (1- (length text))))
               (search (format nil "~%~%[") text :from-end t))))
    (if (and footer-start
             (search "Full output: " text :start2 footer-start))
        (string-right-trim
         '(#\Space #\Tab #\Newline #\Return)
         (subseq text 0 footer-start))
        text)))

(defun make-user-bash-result-from-execution
    (command exclude-from-context-p content details)
  (let* ((exit-code (getf details :exit-code))
         (raw-output
           (if content
               (cadr-ai:text-content-text (first content))
               ""))
         (without-exit
           (if (numberp exit-code)
               (bash-strip-exit-footer raw-output exit-code)
               raw-output)))
    (make-user-bash-result
     :command command
     :output (bash-strip-truncation-footer without-exit)
     :exit-code exit-code
     :cancelled-p (not (null (getf details :cancelled)))
     :truncated-p (not (null (getf details :truncated)))
     :full-output-path (getf details :full-output-path)
     :exclude-from-context-p
     (not (null exclude-from-context-p)))))

(defun record-user-bash-result (agent result)
  ;; Fixed pi@4a080252f agent-session.ts:2803-2824 records the direct shell
  ;; message immediately when the agent is idle. TUI dispatch serializes idle
  ;; direct commands, so the same one-step append preserves ordering here.
  (when (and agent (user-bash-result-p result))
    (cadr-agent::append-agent-message
     agent
     (cadr-agent:make-bash-execution-message
      :command (user-bash-result-command result)
      :output (user-bash-result-output result)
      :exit-code (user-bash-result-exit-code result)
      :cancelled-p (user-bash-result-cancelled-p result)
      :truncated-p (user-bash-result-truncated-p result)
      :full-output-path
      (user-bash-result-full-output-path result)
      :exclude-from-context-p
      (user-bash-result-exclude-from-context-p result))))
  result)

(defun execute-user-bash-for-tui
    (extension-host cwd command
     &key exclude-from-context-p timeout abort-p
       command-prefix custom-shell-path)
  (handler-case
      (multiple-value-bind (content details)
          (execute-user-bash
           extension-host cwd command
           :exclude-from-context-p exclude-from-context-p
           :timeout timeout :abort-p abort-p
           :command-prefix command-prefix
           :custom-shell-path custom-shell-path)
        (make-user-bash-result-from-execution
         command exclude-from-context-p content details))
    (user-bash-aborted (condition)
      (make-user-bash-result-from-execution
       command exclude-from-context-p
       (user-bash-aborted-content condition)
       (user-bash-aborted-details condition)))
    (error (condition)
      (let ((message (format nil "~A" condition)))
        (if (or (string= message "Command aborted")
                (uiop:string-suffix-p
                 message (format nil "~%Command aborted")))
            (make-user-bash-result
             :command command
             :output
             (bash-strip-truncation-footer
              (bash-strip-status-footer message "Command aborted"))
             :exit-code nil
             :cancelled-p t
             :exclude-from-context-p
             (not (null exclude-from-context-p)))
            (error condition))))))

(defun bash-output-path ()
  (merge-pathnames
   (format nil "cadr-bash-~A.log"
           (cadr-ai:octets-hex
            (cadr-ai::secure-random-bytes 8)))
   (uiop:temporary-directory)))

(defun process-deadline (timeout)
  (and timeout
       (+ (get-internal-real-time)
          (round (* timeout internal-time-units-per-second)))))

(defun bash-truncation-notice
    (details output-path full-output)
  (when (getf details :truncated)
    (let* ((total-lines (getf details :total-lines))
           (output-lines (getf details :output-lines))
           (start-line (- total-lines output-lines -1))
           (end-line total-lines))
      (cond
        ((getf details :last-line-partial)
         (let* ((lines
                  (cadr-agent::harness-text-lines full-output))
                (last-line (or (car (last lines)) "")))
           (format
            nil
            "[Showing last ~A of line ~D (line is ~A). Full output: ~A]"
            (format-byte-size (getf details :output-bytes))
            end-line
            (format-byte-size (utf8-length last-line))
            output-path)))
        ((eq (getf details :truncated-by) :lines)
         (format
          nil
          "[Showing lines ~D-~D of ~D. Full output: ~A]"
          start-line end-line total-lines output-path))
        (t
         (format
          nil
          "[Showing lines ~D-~D of ~D (~A limit). Full output: ~A]"
          start-line end-line total-lines
          (format-byte-size +maximum-output-bytes+)
          output-path))))))

(defun append-bash-status (text status)
  (format nil "~A~:[~;~%~%~]~A"
          text (plusp (length text)) status))

(defun read-process-group-id (path)
  (loop repeat 100
        when (probe-file path)
          do (let ((text
                     (ignore-errors
                       (uiop:read-file-string path))))
               (when (and text (plusp (length text)))
                 (return
                   (parse-integer text :junk-allowed t))))
        do (sleep 0.01)
        finally (error "Bash process group did not initialize")))

(defun terminate-process-group (group-id)
  (flet ((signal-group (signal)
           (ignore-errors
             (uiop:run-program
              (list "/bin/kill" signal "--"
                    (format nil "-~D" group-id))
              :ignore-error-status t
              :output nil
              :error-output nil))))
    (signal-group "-TERM")
    (sleep 0.05)
    ;; The setsid wrapper can exit after its foreground shell receives TERM
    ;; while a descendant that ignores TERM keeps the process group alive.
    ;; Always send KILL to the group after the grace period.
    (signal-group "-KILL")))

(defun join-bash-output-reader
    (reader stream group-id last-output-time
     &key (idle-grace 0.15))
  (let ((forced-p nil)
        (grace-ticks
          (round
           (* idle-grace
              internal-time-units-per-second))))
    (loop
      while (sb-thread:thread-alive-p reader)
      do
      (when
          (>= (- (get-internal-real-time)
                 (funcall last-output-time))
              grace-ticks)
        (setf forced-p t)
        (terminate-process-group group-id)
        (ignore-errors (close stream))
        (cadr-core:stop-thread-for-cleanup
         reader :timeout 1.0d0)
        (return))
      (sleep 0.01))
    (unless (sb-thread:thread-alive-p reader)
      (cadr-core:stop-thread-for-cleanup reader))
    forced-p))

(defun bash-command-with-prefix (prefix command)
  (if (and (stringp prefix) (plusp (length prefix)))
      (format nil "~A~%~A" prefix command)
      command))

(defstruct bash-output-sanitizer
  (pending "" :type string))

(defun bash-sanitize-output-text (text)
  ;; pi@4a080252f bash-executor.ts appendText
  (remove #\Return
          (sanitize-binary-output (strip-ansi text))))

(defun bash-take-output-chunk (sanitizer chunk)
  (multiple-value-bind (complete pending)
      (split-incomplete-ansi-suffix
       (concatenate 'string
                    (bash-output-sanitizer-pending sanitizer)
                    chunk))
    (setf (bash-output-sanitizer-pending sanitizer) pending)
    (bash-sanitize-output-text complete)))

(defun bash-flush-output (sanitizer)
  (let ((rest (bash-output-sanitizer-pending sanitizer)))
    (setf (bash-output-sanitizer-pending sanitizer) "")
    (bash-sanitize-output-text rest)))

(defun write-sanitized-bash-output
    (text capture full live-output)
  (when (plusp (length text))
    (write-string text capture)
    (write-string text full)
    (when live-output
      (write-string text live-output)
      (finish-output live-output))))

(defun run-bash-command
    (cwd command timeout
     &key
       (abort-p
         #'cadr-agent::current-tool-aborted-p)
       command-prefix
       custom-shell-path
       environment)
  (when (and timeout (<= timeout 0))
    (error "timeout must be positive"))
  (when (and abort-p (funcall abort-p))
    (error "Command aborted"))
  (let* ((command
           (bash-command-with-prefix command-prefix command))
         (shell
           (if custom-shell-path
               (shell-config-shell
                (get-shell-config custom-shell-path))
               "/bin/bash"))
         (output-path (bash-output-path))
         (group-path
           (pathname
            (format nil "~A.pgid" (namestring output-path))))
         (process
           (apply #'uiop:launch-program
            (list
             "/usr/bin/setsid" "--fork" "--wait"
             "/bin/sh" "-c"
             "printf '%s' \"$$\" > \"$1\"; /usr/bin/env --default-signal=PIPE \"$3\" -lc \"$2\" 2>&1; exit $?"
             "cadr-bash-wrapper"
             (namestring group-path)
             command
             shell)
            :directory cwd
            :input nil
            :output :stream
            ;; Command stderr is redirected to stdout inside the session.
            ;; Keep setsid's own diagnostics on its separate null stderr so
            ;; wrapper lifecycle races can never enter the tool result.
            :error-output nil
            :wait nil
            (when environment
              (list :environment environment))))
         (group-id (read-process-group-id group-path))
         (deadline (process-deadline timeout))
         (capture (make-string-output-stream))
         (live-output *bash-live-output*)
         (process-output
           (uiop:process-info-output process))
         (last-output-time
           (get-internal-real-time))
         (forced-output-close-p nil)
         (reader-error nil)
         (preserve-output-p nil)
         (reader
           (sb-thread:make-thread
            (lambda ()
              (handler-case
                  (let ((full (exclusive-output-stream output-path))
                        (sanitizer (make-bash-output-sanitizer)))
                    (unwind-protect
                        (progn
                    ;; Match Node's pipe `data` contract: block for the first
                    ;; character, then drain the currently available burst
                    ;; into one bounded callback chunk.  Per-character flushes
                    ;; turn a normal command into thousands of render requests.
                    ;; An escape sequence split across bursts stays pending
                    ;; until its terminator, then strip-ansi removes it.
                    (let ((buffer (make-string 4096)))
                      (loop
                        for first =
                          (read-char process-output nil :eof)
                        until (eq first :eof)
                        do
                        (setf (char buffer 0) first)
                        (let ((count 1)
                              (eof-p nil))
                          (loop while (< count (length buffer))
                                for next =
                                  (read-char-no-hang
                                   process-output nil :eof)
                                do
                                (cond
                                  ((eq next :eof)
                                   (setf eof-p t)
                                   (return))
                                  ((null next)
                                   (return))
                                  (t
                                   (setf (char buffer count) next)
                                   (incf count))))
                          (setf
                           last-output-time
                           (get-internal-real-time))
                          (write-sanitized-bash-output
                           (bash-take-output-chunk
                            sanitizer (subseq buffer 0 count))
                           capture full live-output)
                          (when eof-p
                            (return)))))
                      (write-sanitized-bash-output
                       (bash-flush-output sanitizer)
                       capture full live-output)
                      (when (open-stream-p full)
                        (close full)))))
                (error (condition)
                  (unless forced-output-close-p
                    (setf reader-error condition)))))
            :name "cadr-bash-output-reader"))
         (aborted-p nil)
         (timed-out-p nil)
         (exit-code nil))
    (unwind-protect
         (progn
           (loop while (uiop:process-alive-p process)
                 do
                 (cond
                   ((and abort-p (funcall abort-p))
                    (setf aborted-p t)
                    (terminate-process-group group-id)
                    (return))
                   ((and deadline
                         (>= (get-internal-real-time)
                             deadline))
                    (setf timed-out-p t)
                    (terminate-process-group group-id)
                    (return)))
                 (sleep 0.01))
           (setf exit-code
                 (or (uiop:wait-process process)
                     128))
           (setf
            forced-output-close-p
            (join-bash-output-reader
             reader process-output group-id
             (lambda () last-output-time)))
           (when reader-error
             (error reader-error))
           (let ((full-output
                   (get-output-stream-string capture)))
             (multiple-value-bind (tail details)
                 (truncate-tail full-output)
               (let* ((truncated (getf details :truncated))
                      (notice
                        (bash-truncation-notice
                         details (namestring output-path)
                         full-output))
                      (text
                        (if notice
                            (format nil "~A~%~%~A"
                                    tail notice)
                            tail)))
                 (setf preserve-output-p truncated)
                 (unless preserve-output-p
                   (when (probe-file output-path)
                     (delete-file output-path)))
                 (when aborted-p
                   (error
                    'user-bash-aborted
                    :message
                    (append-bash-status
                     text "Command aborted")
                    :content
                    (list
                     (cadr-ai:make-text-content
                      :text text))
                    :details
                    (append
                     (list :exit-code nil :cancelled t)
                     details
                     (list
                      :full-output-path
                      (and truncated
                           (namestring output-path))))))
                 (when timed-out-p
                   (error
                    (append-bash-status
                     text
                     (format nil
                             "Command timed out after ~A seconds"
                             timeout))))
                 (values
                  (list
                   (cadr-ai:make-text-content
                    :text
                    (format nil
                            "~A~:[~;~%~]Process exited with code ~D"
                            text
                            (plusp (length text))
                            exit-code)))
                  (append
                   (list :exit-code exit-code)
                   details
                   (list
                    :full-output-path
                    (and truncated
                         (namestring output-path)))))))))
      (when (uiop:process-alive-p process)
        (terminate-process-group group-id))
      (when (sb-thread:thread-alive-p reader)
        (setf forced-output-close-p t)
        (ignore-errors (close process-output))
        (cadr-core:stop-thread-for-cleanup
         reader :timeout 1.0d0))
      (when (and reader-error
                 (not preserve-output-p)
                 (probe-file output-path))
        (delete-file output-path))
      (when (probe-file group-path)
        (delete-file group-path)))))

(defun execute-bash-tool-command
    (cwd command timeout
     &key command-prefix custom-shell-path environment)
  (multiple-value-bind (content details)
      (run-bash-command
       cwd command timeout
       :command-prefix command-prefix
       :custom-shell-path custom-shell-path
       :environment environment)
    (let* ((exit-code (getf details :exit-code))
           (text
             (bash-strip-exit-footer
              (cadr-ai:text-content-text (first content))
              exit-code)))
      (when (/= exit-code 0)
        (error
         (append-bash-status
          (if (plusp (length text)) text "(no output)")
          (format nil "Command exited with code ~D"
                  exit-code))))
      (values
       (list
        (cadr-ai:make-text-content
         :text
         (if (plusp (length text))
             text
             "(no output)")))
       details))))

(defun execute-bash-tool-command-with-context
    (context cwd command timeout)
  (multiple-value-bind (result operation-error)
      (cadr-agent:execution-tool-exec
       context command :cwd (namestring (uiop:ensure-directory-pathname cwd))
       :timeout timeout)
    (when operation-error
      (let ((message (cadr-agent:harness-operation-error-message operation-error)))
        (error
         "~A"
         (case (cadr-agent:harness-operation-error-code operation-error)
           (:timeout (format nil "Command timed out after ~A seconds" timeout))
           (:aborted "Command aborted")
           (otherwise message)))))
    (let* ((stdout (cadr-agent:execution-result-stdout result))
           (stderr (cadr-agent:execution-result-stderr result))
           (output
             (cond
               ((zerop (length stderr)) stdout)
               ((zerop (length stdout)) stderr)
               (t (format nil "~A~:[~;~%~]~A"
                          stdout
                          (not (char= #\Newline (char stdout (1- (length stdout)))))
                          stderr))))
           (exit-code (cadr-agent:execution-result-exit-code result)))
      (when (null exit-code)
        (error "~A"
               (append-bash-status
                (if (plusp (length output)) output "(no output)")
                "Command terminated without an exit code")))
      (unless (zerop exit-code)
        (error "~A"
               (append-bash-status
                (if (plusp (length output)) output "(no output)")
                (format nil "Command exited with code ~D" exit-code))))
      (values
       (list (cadr-ai:make-text-content
              :text (if (plusp (length output)) output "(no output)")))
       (list :exit-code exit-code)))))

(defun normalized-extension-bash-result (result)
  (let ((output (or (getf result :output) ""))
        (exit-code (getf result :exit-code)))
    (when (and (null exit-code)
               (not (getf result :cancelled-p)))
      (error
       (append-bash-status
        (if (plusp (length output)) output "(no output)")
        "Command terminated without an exit code")))
    (let ((exit-code (or exit-code 0)))
      (values
       (list
        (cadr-ai:make-text-content
         :text
         (format nil
                 "~A~:[~;~%~]Process exited with code ~D"
                 output
                 (plusp (length output))
                 exit-code)))
       (list
        :exit-code exit-code
        :cancelled (getf result :cancelled-p)
        :truncated (getf result :truncated-p)
        :full-output-path
        (getf result :full-output-path))))))

(defun execute-user-bash
    (extension-host cwd command
     &key exclude-from-context-p timeout abort-p
       command-prefix custom-shell-path)
  (let ((interception
          (and extension-host
               (cadr-agent::run-extension-lifecycle-hooks
                extension-host :user-bash
                :payload
                (list
                 :command command
                 :exclude-from-context-p
                 (not
                  (null exclude-from-context-p))
                 :cwd
                 (namestring
                  (uiop:ensure-directory-pathname
                   cwd)))))))
    (cond
      ((getf interception :result)
       (normalized-extension-bash-result
        (getf interception :result)))
      ((functionp (getf interception :operations))
       (multiple-value-bind (result details)
           (funcall
            (getf interception :operations)
            command cwd timeout)
         (if (and
              (listp result)
              (or (null result)
                  (keywordp (first result))))
             (normalized-extension-bash-result
              result)
             (values result details))))
      (t
       (run-bash-command
        cwd command timeout
        :abort-p abort-p
        :command-prefix command-prefix
        :custom-shell-path custom-shell-path)))))

(defparameter +shell-session-env-names+
  '("CADR_SESSION_ID"
    "CADR_SESSION_FILE"
    "CADR_PROVIDER"
    "CADR_MODEL"
    "CADR_REASONING_LEVEL"))

(defparameter +shell-session-prompt-guideline+
  "You can inspect CADR_* environment variables for current model and session details.")

(defvar *shell-session-tools* (make-hash-table :test 'eq))

(defun shell-session-tool-p (tool)
  (gethash tool *shell-session-tools*))

(defun note-shell-session-tool (tool expose-p)
  (if expose-p
      (setf (gethash tool *shell-session-tools*) t)
      (remhash tool *shell-session-tools*))
  tool)

(defun shell-env-strings (alist)
  (mapcar
   (lambda (pair)
     (format nil "~A=~A" (car pair) (cdr pair)))
   alist))

(defun shell-session-name (value)
  (cond
    ((and (stringp value) (plusp (length value))) value)
    ((and value (symbolp value))
     (string-downcase (symbol-name value)))
    (t nil)))

(defun absolute-session-file (path)
  (when path
    (let ((text (namestring path)))
      (when (plusp (length text))
        (namestring
         (uiop:ensure-absolute-pathname
          (pathname path)
          (uiop:getcwd)))))))

(defun shell-session-bindings (agent)
  ;; Resolved when the command starts. The selected model is the one
  ;; on the agent, including a virtual model, not a routed upstream id.
  (let ((session (and agent (cadr-agent:agent-session agent)))
        (model (and agent (cadr-agent:agent-model agent)))
        (level (and agent (cadr-agent::agent-thinking-level agent)))
        (bindings nil))
    (when session
      (let ((id (cadr-agent:session-id session)))
        (when (and (stringp id) (plusp (length id)))
          (push (cons "CADR_SESSION_ID" id) bindings)))
      (let ((file
              (absolute-session-file
               (cadr-agent:session-path session))))
        (when file
          (push (cons "CADR_SESSION_FILE" file) bindings))))
    (when model
      (let ((provider
              (shell-session-name
               (cadr-ai:model-provider model)))
            (id (cadr-ai:model-id model)))
        (when provider
          (push (cons "CADR_PROVIDER" provider) bindings))
        (when (and (stringp id) (plusp (length id)))
          (push (cons "CADR_MODEL" id) bindings))))
    (let ((reasoning (shell-session-name level)))
      (when reasoning
        (push (cons "CADR_REASONING_LEVEL" reasoning) bindings)))
    bindings))

(defun strip-shell-session-env (alist)
  (remove-if
   (lambda (pair)
     (member (car pair) +shell-session-env-names+
             :test #'string=))
   alist))

(defun shell-session-environment
    (&key (expose-p t)
          (agent cadr-agent::*tool-search-agent*))
  (let ((base (strip-shell-session-env (get-shell-env))))
    (if (and expose-p agent)
        (append (shell-session-bindings agent) base)
        base)))

(defun resolve-shell-spawn-context
    (command cwd &key (expose-p t) spawn-hook)
  (let ((context
          (list :command command
                :cwd cwd
                :env (shell-session-environment :expose-p expose-p))))
    (if (null spawn-hook)
        context
        (let ((updated (funcall spawn-hook context)))
          (if (listp updated)
              (list :command
                    (or (getf updated :command)
                        (getf context :command))
                    :cwd
                    (or (getf updated :cwd)
                        (getf context :cwd))
                    :env
                    (or (getf updated :env)
                        (getf context :env)))
              context)))))

(defun make-bash-tool
    (cwd &key context command-prefix shell-path
              (expose-session-environment t)
              spawn-hook)
  (note-shell-session-tool
   (cadr-ai:make-tool
   :name "bash"
   :description
   "Execute a bash command in the current working directory. Returns stdout and stderr. Output is truncated to last 2000 lines or 50KB (whichever is hit first). If truncated, full output is saved to a temp file. Optionally provide a timeout in seconds."
   :parameters
   (object-schema
    (cadr-ai::json-object
     "command" (string-property "Bash command to execute")
     "timeout"
     (number-property
      "Timeout in seconds (optional, no default timeout)"))
    '("command"))
   :constrained-sampling (experimental-tool-sampling)
   :execution-mode :sequential
   :executor
   (lambda (call-id arguments)
     (declare (ignore call-id))
     (let* ((command (required-string arguments "command"))
            (timeout (cadr-ai::json-get arguments "timeout"))
            (spawn
              (resolve-shell-spawn-context
               (bash-command-with-prefix command-prefix command)
               (effective-tool-cwd cwd)
               :expose-p expose-session-environment
               :spawn-hook spawn-hook)))
       (if context
           (let ((cadr-agent::*execution-spawn-environment*
                   (shell-env-strings (getf spawn :env))))
             (execute-bash-tool-command-with-context
              context (getf spawn :cwd) (getf spawn :command)
              timeout))
           (execute-bash-tool-command
            (getf spawn :cwd) (getf spawn :command) timeout
            :custom-shell-path shell-path
            :environment (shell-env-strings (getf spawn :env)))))))
   expose-session-environment))
