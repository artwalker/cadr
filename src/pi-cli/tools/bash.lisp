(in-package #:pi-cli)

(defvar *bash-live-output* nil)

(defun bash-output-path ()
  (merge-pathnames
   (format nil "pi-cl-bash-~D-~D.log"
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
             "pi-cl-bash-wrapper"
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
                    (let ((stream
                            (uiop:process-info-output process)))
                      (loop for character =
                              (read-char stream nil :eof)
                            until (eq character :eof)
                            do (write-char character capture)
                               (write-char character full)
                               (when live-output
                                 (write-char
                                  character live-output)
                                 (finish-output
                                  live-output)))))
                (error (condition)
                  (setf reader-error condition))))
            :name "pi-bash-output-reader"))
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
           (sb-thread:join-thread reader)
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
                   (pi-ai:make-text-content
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
        (sb-thread:join-thread reader))
      (when (and (or timed-out-p reader-error)
                 (probe-file output-path))
        (delete-file output-path))
      (when (probe-file group-path)
        (delete-file group-path)))))

(defun make-bash-tool (cwd)
  (pi-ai:make-tool
   :name "bash"
   :description
   "Run a Bash command in the project directory and return merged output."
   :parameters
   (object-schema
    (pi-ai::json-object
     "command" (string-property)
     "timeout" (number-property))
    '("command"))
   :execution-mode :sequential
   :executor
   (lambda (call-id arguments)
     (declare (ignore call-id))
     (run-bash-command
      cwd
      (required-string arguments "command")
      (pi-ai::json-get arguments "timeout")))))
