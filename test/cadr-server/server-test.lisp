(in-package #:cadr-server/tests)

(in-suite cadr-server-suite)

(defmacro with-server-directory
    ((directory) &body body)
  `(let* ((base
            (uiop:ensure-directory-pathname
             (uiop:temporary-directory)))
          (,directory
            (merge-pathnames
             (format nil "cadr-server-~36R/"
                     (random most-positive-fixnum))
             base)))
     (ensure-directories-exist
      (merge-pathnames "anchor" ,directory))
     (unwind-protect
          (progn ,@body)
       (uiop:delete-directory-tree
        ,directory
        :validate t
        :if-does-not-exist :ignore))))

(defclass fake-rpc-process ()
  ((event-handler
    :initform nil
    :accessor fake-event-handler)
   (ui-handler
    :initform nil
    :accessor fake-ui-handler)
   (exit-handler
    :initform nil
    :accessor fake-exit-handler)
   (ui-responses
    :initform nil
    :accessor fake-ui-responses)
   (commands
    :initform nil
    :accessor fake-commands)
   (disposed-p
    :initform nil
    :accessor fake-disposed-p)))

(defmethod cadr-server::rpc-process-send
    ((process fake-rpc-process) command)
  (push command (fake-commands process))
  (let ((type
          (cadr-ai::json-get command "type")))
    (if (string= type "get_state")
        (cadr-ai::json-object
         "type" "response"
         "id" (cadr-ai::json-get command "id")
         "success" t
         "command" "get_state"
         "data"
         (cadr-ai::json-object
          "sessionId" "session-1"
          "sessionFile" "/tmp/session.jsonl"))
        (cadr-ai::json-object
         "type" "response"
         "id" (cadr-ai::json-get command "id")
         "success" t
         "command" type))))

(defmethod cadr-server::rpc-process-dispose
    ((process fake-rpc-process))
  (setf (fake-disposed-p process) t)
  nil)

(defmethod cadr-server::rpc-process-set-event-handler
    ((process fake-rpc-process) handler)
  (setf (fake-event-handler process) handler))

(defmethod cadr-server::rpc-process-set-ui-handler
    ((process fake-rpc-process) handler)
  (setf (fake-ui-handler process) handler))

(defmethod cadr-server::rpc-process-set-exit-handler
    ((process fake-rpc-process) handler)
  (setf (fake-exit-handler process) handler))

(defmethod cadr-server::rpc-process-handle-ui-response
    ((process fake-rpc-process) response)
  (push response (fake-ui-responses process))
  nil)

(defun make-test-supervisor
    (directory processes)
  (cadr-server:make-server-supervisor
   :server-directory directory
   :rpc-process-factory
   (lambda (cwd)
     (declare (ignore cwd))
     (let ((process
             (make-instance 'fake-rpc-process)))
       (vector-push-extend process processes)
       process))
   :radius
   (cadr-server::make-dormant-radius-presence)))

(test protocol-and-storage-preserve-baseline-records
  (with-server-directory (directory)
    (let* ((machine
             (cadr-server:make-machine-record
              :id "machine"
              :created-at "2026-07-31T00:00:00Z"
              :label "desk"))
           (instance
             (cadr-server:make-instance-record
              :id "one"
              :status :online
              :cwd "/tmp/work"
              :created-at "2026-07-31T00:00:00Z"
              :session-id "session"))
           (message
             (cadr-ai::json-object
              "type" "spawn"
              "cwd" "/tmp/work"))
           (encoded
             (cadr-server:encode-server-message
              message)))
      (is (char= #\Newline
                 (char encoded
                       (1- (length encoded)))))
      (is (string=
           "spawn"
           (cadr-ai::json-get
            (cadr-server:parse-server-line
             encoded)
            "type")))
      (cadr-server:save-machine directory machine)
      (cadr-server:save-instances
       directory (list instance))
      (let ((loaded-machine
              (cadr-server:load-machine directory))
            (loaded-instance
              (first
               (cadr-server:load-instances
                directory))))
        (is (string=
             "machine"
             (cadr-server:machine-record-id
              loaded-machine)))
        (is (string=
             "desk"
             (cadr-server:machine-record-label
              loaded-machine)))
        (is (eq
             :online
             (cadr-server:instance-record-status
              loaded-instance)))
        (is (string=
             "session"
             (cadr-server:instance-record-session-id
              loaded-instance)))))))

(test supervisor-covers-spawn-rpc-stream-ui-stop-and-recovery
  (with-server-directory (directory)
    (let* ((processes
             (make-array 0
                         :adjustable t
                         :fill-pointer 0))
           (supervisor
             (make-test-supervisor
              directory processes))
           (instance
             (cadr-server:supervisor-spawn-instance
              supervisor
              :cwd "/tmp/work"
              :label "worker"))
           (id
             (cadr-server:instance-record-id
              instance))
           (process
             (aref processes 0))
           (events nil)
           (ui-requests nil)
           (stream
             (cadr-server:supervisor-open-rpc-stream
              supervisor id
              (lambda (event)
                (push event events))
              (lambda (request)
                (push request ui-requests)))))
      (is (eq
           :online
           (cadr-server:instance-record-status
            instance)))
      (is (string=
           "session-1"
           (cadr-server:instance-record-session-id
            instance)))
      (is (= 1
             (length
              (cadr-server:supervisor-list-instances
               supervisor))))
      (let ((event
              (cadr-ai::json-object
               "type" "agent_start"))
            (ui-request
              (cadr-ai::json-object
               "type" "extension_ui_request"
               "id" "ui-1")))
        (funcall (fake-event-handler process)
                 event)
        (funcall (fake-ui-handler process)
                 ui-request)
        (is (eq event (first events)))
        (is (eq ui-request
                (first ui-requests))))
      (let* ((command
               (cadr-ai::json-object
                "type" "prompt"
                "message" "hello"))
             (response
               (cadr-server:rpc-stream-send
                stream command)))
        (is (cadr-ai::json-get
             response "success"))
        (is (stringp
             (cadr-ai::json-get
              command "id"))))
      (let ((ui-response
              (cadr-ai::json-object
               "type" "extension_ui_response"
               "id" "ui-1")))
        (cadr-server:rpc-stream-handle-ui-response
         stream ui-response)
        (is (eq ui-response
                (first
                 (fake-ui-responses process)))))
      (cadr-server:close-rpc-stream stream)
      (let ((stopped
              (cadr-server:supervisor-stop-instance
               supervisor id)))
        (is (eq
             :stopped
             (cadr-server:instance-record-status
              stopped))))
      (is (fake-disposed-p process))
      (is (null
           (cadr-server:supervisor-get-instance
            supervisor id)))
      (cadr-server:save-instances
       directory
       (list
        (cadr-server:make-instance-record
         :id "old-online"
         :status :online
         :cwd "/tmp"
         :created-at "then")
        (cadr-server:make-instance-record
         :id "old-error"
         :status :error
         :cwd "/tmp"
         :created-at "then")))
      (cadr-server:supervisor-recover-after-restart
       supervisor)
      (let ((records
              (cadr-server:load-instances
               directory)))
        (is (eq
             :stopped
             (cadr-server:instance-record-status
              (first records))))
        (is (eq
             :error
             (cadr-server:instance-record-status
              (second records))))))))

(test unexpected-child-exit-converges-to-error
  (with-server-directory (directory)
    (let* ((processes
             (make-array 0
                         :adjustable t
                         :fill-pointer 0))
           (supervisor
             (make-test-supervisor
              directory processes))
           (instance
             (cadr-server:supervisor-spawn-instance
              supervisor :cwd "/tmp"))
           (id
             (cadr-server:instance-record-id
              instance))
           (process
             (aref processes 0)))
      (funcall (fake-exit-handler process)
               (make-condition
                'simple-error
                :format-control "boom"))
      (is (null
           (cadr-server:supervisor-get-live-instance
            supervisor id)))
      (is (eq
           :error
           (cadr-server:instance-record-status
            (cadr-server:supervisor-get-instance
             supervisor id)))))))

(test unix-socket-supports-single-request-errors-streams-and-stale-files
  (with-server-directory (directory)
    (let* ((processes
             (make-array 0
                         :adjustable t
                         :fill-pointer 0))
           (supervisor
             (make-test-supervisor
              directory processes))
           (socket-path
             (merge-pathnames
              "server.sock" directory)))
      (with-open-file
          (stream socket-path
                  :direction :output
                  :if-exists :supersede)
        (write-string "stale" stream))
      (let ((server
              (cadr-server:start-ipc-server
               supervisor socket-path)))
        (unwind-protect
             (progn
               (let* ((spawn
                        (cadr-server:ipc-request
                         socket-path
                         (cadr-ai::json-object
                          "type" "spawn"
                          "cwd" "/tmp/work")))
                      (instance
                        (cadr-ai::json-get
                         spawn "instance"))
                      (id
                        (cadr-ai::json-get
                         instance "id")))
                 (is (cadr-ai::json-get
                      spawn "ok"))
                 (let ((unknown
                         (cadr-server:ipc-request
                          socket-path
                          (cadr-ai::json-object
                           "type" "status"
                           "instanceId" "missing"))))
                   (is (string=
                        "Unknown instance: missing"
                        (cadr-ai::json-get
                         unknown "error"))))
                 (let ((stream
                         (cadr-server:connect-ipc-stream
                          socket-path)))
                   (unwind-protect
                        (progn
                          (write-string
                           (cadr-server:encode-server-message
                            (cadr-ai::json-object
                             "type" "rpc_stream"
                             "instanceId" id))
                           stream)
                          (finish-output stream)
                          (let ((ready
                                  (cadr-server:parse-server-line
                                   (read-line stream))))
                            (is (string=
                                 "rpc_ready"
                                 (cadr-ai::json-get
                                  ready "type"))))
                          (funcall
                           (fake-event-handler
                            (aref processes 0))
                           (cadr-ai::json-object
                            "type" "agent_start"))
                          (let ((event
                                  (cadr-server:parse-server-line
                                   (read-line stream))))
                            (is (string=
                                 "agent_start"
                                 (cadr-ai::json-get
                                  event "type"))))
                          (write-string
                           (cadr-server:encode-server-message
                            (cadr-ai::json-object
                             "type" "get_state"
                             "id" "state-1"))
                           stream)
                          (finish-output stream)
                          (let ((response
                                  (cadr-server:parse-server-line
                                   (read-line stream))))
                            (is (string=
                                 "state-1"
                                 (cadr-ai::json-get
                                  response "id")))))
                     (close stream)))
                 (signals error
                   (cadr-server:start-ipc-server
                    supervisor socket-path))))
          (cadr-server:stop-ipc-server
           server)))
      (is (not (probe-file socket-path))))))
