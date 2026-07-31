(in-package #:cadr-server)

(defun print-server-usage
    (&optional
       (stream *standard-output*))
  (format
   stream
   "Usage: cadr-server <serve|list|spawn|status|stop|rpc|rpc-stream> [arguments]~%")
  (finish-output stream))

(defun command-argument
    (arguments index description)
  (or (nth index arguments)
      (error "Missing ~A" description)))

(defun print-server-response (response)
  (write-string
   (encode-server-message response)
   *standard-output*)
  (finish-output *standard-output*)
  response)

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
           (format t
                   "cadr-server 0.1.0~%"))
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
             (cadr-ai::json-object
              "type" "spawn"
              "cwd"
              (command-argument
               arguments 1 "cwd")
              "label"
              (nth 2 arguments)))))
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
