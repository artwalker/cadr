(in-package #:cadr-server)

(defun server-version-line ()
  (format nil "cadr-server ~A"
          (cadr-ai::cadr-version)))

(defun print-server-usage
    (&optional
       (stream *standard-output*))
  (format
   stream
   "Usage:~%  cadr-server serve~%  cadr-server list~%  cadr-server spawn [--cwd <path>] [--label <label>]~%  cadr-server status <instance-id>~%  cadr-server stop <instance-id>~%  cadr-server rpc <instance-id> <json-command>~%  cadr-server rpc-stream <instance-id>~%")
  (finish-output stream))

(defun command-argument
    (arguments index description)
  (or (nth index arguments)
      (error "Missing ~A" description)))

(defun server-option-value
    (arguments option)
  (let ((position
          (position option arguments
                    :test #'string=)))
    (and position
         (nth (1+ position)
              arguments))))

(defun spawn-request-from-arguments
    (arguments)
  (cadr-ai::json-object
   "type" "spawn"
   "cwd"
   (or
    (server-option-value
     arguments "--cwd")
    (namestring
     (uiop:getcwd)))
   "label"
   (server-option-value
    arguments "--label")))

(defun print-server-response (response)
  (write-string
   (encode-server-message response)
   *standard-output*)
  (finish-output *standard-output*)
  nil)

(defun run-server ()
  (let* ((supervisor
           (make-server-supervisor))
         (server nil))
    (unwind-protect
         (progn
           (supervisor-recover-after-restart
            supervisor)
           (radius-start
            (supervisor-radius
             supervisor))
           (setf
            server
            (start-ipc-server
             supervisor))
           (format
            *standard-output*
            "cadr-server listening on ~A~%"
            (namestring
             (ipc-server-path server)))
           (finish-output
            *standard-output*)
           (loop
             (sleep 3600)))
      (when server
        (stop-ipc-server server))
      (supervisor-shutdown
       supervisor))))

(defun run-rpc-stream-client
    (socket-path instance-id)
  (let ((stream
          (connect-ipc-stream
           socket-path)))
    (unwind-protect
         (progn
           (write-string
            (encode-server-message
             (cadr-ai::json-object
              "type" "rpc_stream"
              "instanceId"
              instance-id))
            stream)
           (finish-output stream)
           (sb-thread:make-thread
            (lambda ()
              (loop
                for line =
                (read-line
                 *standard-input*
                 nil nil)
                while line
                do
                   (write-line line stream)
                   (finish-output stream)))
            :name
            "cadr-server-rpc-stream-input")
           (loop
             for line =
             (read-line stream nil nil)
             while line
             do
                (write-line
                 line *standard-output*)
                (finish-output
                 *standard-output*)))
      (close stream))))

(defun main ()
  (let* ((arguments
           (uiop:command-line-arguments))
         (command
           (first arguments))
         (socket-path
           (server-socket-path)))
    (handler-case
        (cond
          ((or (null command)
               (member
                command
                '("-h" "--help" "help")
                :test #'string=))
           (print-server-usage))
          ((member command
                   '("-v" "--version")
                   :test #'string=)
           (format t "~A~%"
                   (server-version-line)))
          ((string= command "serve")
           (run-server))
          ((string= command "list")
           (print-server-response
            (ipc-request
             socket-path
             (cadr-ai::json-object
              "type" "list"))))
          ((string= command "spawn")
           (print-server-response
            (ipc-request
             socket-path
             (spawn-request-from-arguments
              arguments))))
          ((string= command "status")
           (print-server-response
            (ipc-request
             socket-path
             (cadr-ai::json-object
              "type" "status"
              "instanceId"
              (command-argument
               arguments 1
               "instance id")))))
          ((string= command "stop")
           (print-server-response
            (ipc-request
             socket-path
             (cadr-ai::json-object
              "type" "stop"
              "instanceId"
              (command-argument
               arguments 1
               "instance id")))))
          ((string= command "rpc")
           (print-server-response
            (ipc-request
             socket-path
             (cadr-ai::json-object
              "type" "rpc"
              "instanceId"
              (command-argument
               arguments 1
               "instance id")
              "command"
              (parse-server-line
               (command-argument
                arguments 2
                "RPC JSON"))))))
          ((string= command "rpc-stream")
           (run-rpc-stream-client
            socket-path
            (command-argument
             arguments 1
             "instance id")))
          (t
           (error
            "Unknown command: ~A"
            command)))
      (error (cause)
        (format
         *error-output*
         "cadr-server: ~A~%"
         cause)
        (finish-output
         *error-output*)
        (uiop:quit 1)))))

(defun server-executable-main ()
  (uiop:quit (or (main) 0)))
