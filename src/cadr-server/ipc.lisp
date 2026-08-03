(in-package #:cadr-server)

(defstruct ipc-server
  socket
  path
  supervisor
  thread
  (stopping-p nil)
  (clients nil)
  (clients-lock
   (sb-thread:make-mutex
    :name "cadr-server-ipc-clients")))

(defun make-local-socket ()
  (make-instance
   'sb-bsd-sockets:local-socket
   :type :stream
   :protocol 0))

(defun local-socket-stream (socket)
  (sb-bsd-sockets:socket-make-stream
   socket
   :input t
   :output t
   :element-type 'character
   :external-format :utf-8
   :buffering :none))

(defun connect-ipc-stream (socket-path)
  (let ((socket
          (make-local-socket)))
    (handler-case
        (progn
          (sb-bsd-sockets:socket-connect
           socket
           (namestring
            (pathname socket-path)))
          (local-socket-stream
           socket))
      (error (cause)
        (ignore-errors
          (sb-bsd-sockets:socket-close
           socket))
        (error cause)))))

(defun ipc-socket-live-p (path)
  (handler-case
      (let ((stream
              (connect-ipc-stream path)))
        (close stream)
        t)
    (error () nil)))

(defun remove-stale-ipc-socket (path)
  (when (probe-file path)
    (if (ipc-socket-live-p path)
        (error
         "server is already running: ~A"
         (namestring path))
        (delete-file path)))
  nil)

(defun write-ipc-message
    (stream lock message)
  (sb-thread:with-mutex (lock)
    (write-string
     (encode-server-message message)
     stream)
    (finish-output stream)))

(defun serve-rpc-stream
    (supervisor stream request response)
  (let* ((instance-id
           (cadr-ai::json-get
            request "instanceId"))
         (write-lock
           (sb-thread:make-mutex
            :name
            "cadr-server-ipc-stream-write"))
         (rpc-stream
           (supervisor-open-rpc-stream
            supervisor instance-id
            (lambda (event)
              (write-ipc-message
               stream write-lock event))
            (lambda (ui-request)
              (write-ipc-message
               stream write-lock
               ui-request)))))
    (unless rpc-stream
      (write-ipc-message
       stream write-lock
       (unknown-instance-response
        instance-id))
      (return-from serve-rpc-stream
        nil))
    (unwind-protect
         (progn
           (write-ipc-message
            stream write-lock response)
           (loop
             for line =
             (read-line stream nil nil)
             while line
             unless
             (zerop
              (length
               (string-trim
                '(#\Space #\Tab
                  #\Return #\Newline)
                line)))
               do
                  (handler-case
                      (let ((message
                              (parse-server-line
                               line)))
                        (if
                            (string=
                             "extension_ui_response"
                             (cadr-ai::json-get
                              message "type"))
                            (rpc-stream-handle-ui-response
                             rpc-stream message)
                            (write-ipc-message
                             stream write-lock
                             (rpc-stream-send
                              rpc-stream
                              message))))
                    (error (cause)
                      (write-ipc-message
                       stream write-lock
                       (error-response
                        (princ-to-string
                         cause)))))))
      (close-rpc-stream
       rpc-stream))))

(defun serve-ipc-client
    (supervisor socket)
  (let ((stream
          (local-socket-stream socket)))
    (unwind-protect
         (handler-case
             (let ((line
                     (read-line
                      stream nil nil)))
               (when line
                 (let* ((request
                          (parse-server-line
                           line))
                        (response
                          (handle-server-request
                           supervisor request)))
                   (if
                       (and
                        (string=
                         "rpc_stream"
                         (cadr-ai::json-get
                          request "type"))
                        (cadr-ai::json-get
                         response "ok")
                        (string=
                         "rpc_ready"
                         (cadr-ai::json-get
                          response "type")))
                       (serve-rpc-stream
                        supervisor stream
                        request response)
                       (progn
                         (write-string
                          (encode-server-message
                           response)
                          stream)
                         (finish-output
                          stream))))))
           (error (cause)
             (ignore-errors
               (write-string
                (encode-server-message
                 (error-response
                  (princ-to-string cause)))
                stream)
               (finish-output stream))))
      (ignore-errors
        (close stream)))))

(defun register-ipc-client
    (server thread)
  (sb-thread:with-mutex
      ((ipc-server-clients-lock
        server))
    (push thread
          (ipc-server-clients
           server))))

(defun ipc-accept-loop (server)
  (loop
    until
    (ipc-server-stopping-p server)
    do
       (handler-case
           (multiple-value-bind
                 (client address)
               (sb-bsd-sockets:socket-accept
                (ipc-server-socket
                 server))
             (declare (ignore address))
             (let ((thread
                     (sb-thread:make-thread
                      (lambda ()
                        (serve-ipc-client
                         (ipc-server-supervisor
                          server)
                         client))
                      :name
                      "cadr-server-ipc-client")))
               (register-ipc-client
                server thread)))
         (error (cause)
           (unless
               (ipc-server-stopping-p
                server)
             (format
              *error-output*
              "cadr-server: socket accept failed: ~A~%"
              cause)
             (finish-output
              *error-output*))))))

(defun start-ipc-server
    (supervisor
     &optional
       (socket-path
         (server-socket-path
          (supervisor-directory
           supervisor))))
  (let ((path
          (pathname socket-path)))
    (ensure-directories-exist path)
    (remove-stale-ipc-socket path)
    (let ((socket
            (make-local-socket)))
      (handler-case
          (progn
            (sb-bsd-sockets:socket-bind
             socket
             (namestring path))
            (sb-bsd-sockets:socket-listen
             socket 64)
            (let ((server
                    (make-ipc-server
                     :socket socket
                     :path path
                     :supervisor
                     supervisor)))
              (setf
               (ipc-server-thread server)
               (sb-thread:make-thread
                (lambda ()
                  (ipc-accept-loop
                   server))
                :name
                "cadr-server-ipc-accept"))
              server))
        (error (cause)
          (ignore-errors
            (sb-bsd-sockets:socket-close
             socket))
          (when (probe-file path)
            (delete-file path))
          (error cause))))))

(defun stop-ipc-server (server)
  (setf
   (ipc-server-stopping-p server)
   t)
  (ignore-errors
    (let ((stream
            (connect-ipc-stream
             (ipc-server-path server))))
      (close stream)))
  (ignore-errors
    (sb-bsd-sockets:socket-close
     (ipc-server-socket server)))
  (let ((thread
          (ipc-server-thread server)))
    (cadr-core:stop-thread-for-cleanup
     thread :timeout 0.5d0))
  (when
      (probe-file
       (ipc-server-path server))
    (delete-file
     (ipc-server-path server)))
  nil)

(defun ipc-request
    (socket-path request)
  (let ((stream
          (connect-ipc-stream
           socket-path)))
    (unwind-protect
         (progn
           (write-string
            (encode-server-message
             request)
            stream)
           (finish-output stream)
           (let ((line
                   (read-line
                    stream nil nil)))
             (unless line
               (error
                "Server socket closed before a response was received: ~A"
                (namestring
                 (pathname socket-path))))
             (parse-server-line line)))
      (close stream))))
