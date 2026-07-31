(in-package #:cadr-cli)

(defvar *bash-live-output* nil)

(defun bash-live-output-for-mode (mode frontend-output)
  (case mode
    (:repl frontend-output)
    (:tui nil)
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

(defun bash-output-path ()
  (merge-pathnames
   (format nil "cadr-bash-~D-~D.log"
           (get-universal-time)
           (random most-positive-fixnum))
   (uiop:temporary-directory)))

(defun process-deadline (timeout)
  (and timeout
       (+ (get-internal-real-time)
          (round (* timeout internal-time-units-per-second)))))

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
        (sb-thread:join-thread
         reader :timeout 1.0 :default nil)
        (when (sb-thread:thread-alive-p reader)
          (ignore-errors
            (sb-thread:terminate-thread reader)))
        (return))
      (sleep 0.01))
    (unless (sb-thread:thread-alive-p reader)
      (sb-thread:join-thread reader))
    forced-p))

(defun run-bash-command (cwd command timeout)
  (when (and timeout (<= timeout 0))
    (error "timeout must be positive"))
  (let* ((output-path (bash-output-path))
         (group-path
           (pathname
            (format nil "~A.pgid" (namestring output-path))))
         (process
           (uiop:launch-program
            (list
             "/usr/bin/setsid" "--fork" "--wait"
             "/bin/sh" "-c"
             "printf '%s' \"$$\" > \"$1\"; exec /bin/bash -lc \"$2\""
             "cadr-bash-wrapper"
             (namestring group-path)
             command)
            :directory cwd
            :input nil
            :output :stream
            :error-output :output
            :wait nil))
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
         (reader
           (sb-thread:make-thread
            (lambda ()
              (handler-case
                  (with-open-file
                      (full output-path
                            :direction :output
                            :if-exists :supersede
                            :if-does-not-exist :create
                            :external-format :utf-8)
                    (loop for character =
                            (read-char
                             process-output nil :eof)
                          until (eq character :eof)
                          do
                          (setf
                           last-output-time
                           (get-internal-real-time))
                          (write-char character capture)
                          (write-char character full)
                          (when live-output
                            (write-char
                             character live-output)
                            (finish-output
                             live-output))))
                (error (condition)
                  (unless forced-output-close-p
                    (setf reader-error condition)))))
            :name "cadr-bash-output-reader"))
         (timed-out-p nil)
         (exit-code nil))
    (unwind-protect
         (progn
           (loop while (uiop:process-alive-p process)
                 do
                 (when (and deadline
                            (>= (get-internal-real-time)
                                deadline))
                   (setf timed-out-p t)
                   (terminate-process-group group-id)
                   (return))
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
           (when timed-out-p
             (error "Command timed out after ~,2F seconds"
                    timeout))
           (let ((full-output
                   (get-output-stream-string capture)))
             (multiple-value-bind (tail details)
                 (truncate-tail full-output)
               (let ((truncated (getf details :truncated)))
                 (unless truncated
                   (when (probe-file output-path)
                     (delete-file output-path)))
                 (values
                  (list
                   (cadr-ai:make-text-content
                    :text
                    (format nil
                            "~A~:[~;~%~]Process exited with code ~D"
                            tail
                            (plusp (length tail))
                            exit-code)))
                  (list
                   :exit-code exit-code
                   :truncated truncated
                   :full-output-path
                   (and truncated (namestring output-path))))))))
      (when (uiop:process-alive-p process)
        (terminate-process-group group-id))
      (when (sb-thread:thread-alive-p reader)
        (setf forced-output-close-p t)
        (ignore-errors (close process-output))
        (sb-thread:join-thread
         reader :timeout 1.0 :default nil)
        (when (sb-thread:thread-alive-p reader)
          (ignore-errors
            (sb-thread:terminate-thread reader))))
      (when (and (or timed-out-p reader-error)
                 (probe-file output-path))
        (delete-file output-path))
      (when (probe-file group-path)
        (delete-file group-path)))))

(defun execute-bash-tool-command (cwd command timeout)
  (multiple-value-bind (content details)
      (run-bash-command cwd command timeout)
    (let* ((exit-code (getf details :exit-code))
           (text
             (bash-strip-exit-footer
              (cadr-ai:text-content-text (first content))
              exit-code)))
      (when (/= exit-code 0)
        (error
         "~A~:[~;~%~%~]Command exited with code ~D"
         text
         (plusp (length text))
         exit-code))
      (values
       (list
        (cadr-ai:make-text-content
         :text
         (if (plusp (length text))
             text
             "(no output)")))
       details))))

(defun normalized-extension-bash-result (result)
  (let ((output (or (getf result :output) ""))
        (exit-code (or (getf result :exit-code) 0)))
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
      (getf result :full-output-path)))))

(defun execute-user-bash
    (extension-host cwd command
     &key exclude-from-context-p timeout)
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
       (run-bash-command cwd command timeout)))))

(defun make-bash-tool (cwd)
  (cadr-ai:make-tool
   :name "bash"
   :description
   "Execute a bash command in the current working directory. Returns stdout and stderr. Output is truncated to last 2000 lines or 50KB (whichever is hit first). If truncated, full output is saved to a temp file. Optionally provide a timeout in seconds."
   :parameters
   (object-schema
    (cadr-ai::json-object
     "command" (string-property)
     "timeout" (number-property))
    '("command"))
   :execution-mode :sequential
   :executor
   (lambda (call-id arguments)
     (declare (ignore call-id))
     (execute-bash-tool-command
      cwd
      (required-string arguments "command")
      (cadr-ai::json-get arguments "timeout")))))
