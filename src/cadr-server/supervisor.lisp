(in-package #:cadr-server)

(defstruct live-instance
  record
  process
  (subscribers nil)
  ui-handler)

(defstruct (rpc-stream-handle
            (:constructor
             %make-rpc-stream-handle))
  supervisor
  instance-id
  event-handler
  ui-handler
  (closed-p nil))

(defclass server-supervisor ()
  ((directory
    :initarg :directory
    :reader supervisor-directory)
   (process-factory
    :initarg :process-factory
    :reader supervisor-process-factory)
   (radius
    :initarg :radius
    :reader supervisor-radius)
   (live
    :initform
    (make-hash-table :test #'equal)
    :reader supervisor-live)
   (lock
    :initform
    (sb-thread:make-mutex
     :name "cadr-server-supervisor")
    :reader supervisor-lock)))

(defun make-server-supervisor
    (&key
       (server-directory
         (server-directory))
       (rpc-process-factory
         #'make-rpc-process)
       radius)
  (let* ((presence
           (or radius
               (make-radius-presence
                :directory
                server-directory)))
         (supervisor
           (make-instance
            'server-supervisor
            :directory
            (ensure-server-directory
             server-directory)
            :process-factory
            rpc-process-factory
            :radius presence)))
    (radius-configure-coordinator
     presence
     :get-live-instance
     (lambda (instance-id)
       (supervisor-get-live-instance
        supervisor instance-id))
     :list-live-instances
     (lambda ()
       (supervisor-list-live-instances
        supervisor))
     :update-instance
     (lambda (instance)
       (supervisor-update-instance
        supervisor instance)))
    supervisor))

(defun set-instance-status
    (supervisor live status)
  (let ((record
          (live-instance-record live)))
    (setf
     (instance-record-status record)
     status
     (instance-record-last-seen-at
      record)
     (current-iso8601))
    (upsert-instance
     (supervisor-directory supervisor)
     record)
    record))

(defun update-instance-record
    (supervisor live
     &key
       (session-id nil session-id-p)
       (session-file nil session-file-p)
       (radius-pi-id nil radius-pi-id-p))
  (let ((record
          (live-instance-record live)))
    (when session-id-p
      (setf
       (instance-record-session-id
        record)
       session-id))
    (when session-file-p
      (setf
       (instance-record-session-file
        record)
       session-file))
    (when radius-pi-id-p
      (setf
       (instance-record-radius-pi-id
        record)
       radius-pi-id))
    (setf
     (instance-record-last-seen-at
      record)
     (current-iso8601))
    (upsert-instance
     (supervisor-directory supervisor)
     record)
    record))

(defun clear-rpc-bindings (live)
  (let ((process
          (live-instance-process live)))
    (when process
      (rpc-process-set-event-handler
       process nil)
      (rpc-process-set-ui-handler
       process nil)
      (rpc-process-set-exit-handler
       process nil)))
  (setf
   (live-instance-ui-handler live)
   nil)
  nil)

(defun handle-unexpected-rpc-exit
    (supervisor live cause)
  (declare (ignore cause))
  (let ((active-p
          (sb-thread:with-mutex
              ((supervisor-lock
                supervisor))
            (eq live
                (gethash
                 (instance-record-id
                  (live-instance-record
                   live))
                 (supervisor-live
                  supervisor))))))
    (when
        (and active-p
             (not
              (member
               (instance-record-status
                (live-instance-record
                 live))
               '(:stopping :stopped))))
      (set-instance-status
       supervisor live :error)
      (clear-rpc-bindings live)
      (setf
       (live-instance-process live)
       nil)
      (ignore-errors
        (radius-disconnect-pi
         (supervisor-radius
          supervisor)
         (live-instance-record
          live)))
      (sb-thread:with-mutex
          ((supervisor-lock supervisor))
        (remhash
         (instance-record-id
          (live-instance-record live))
         (supervisor-live
          supervisor)))))
  nil)

(defun bind-rpc-process
    (supervisor live process)
  (setf
   (live-instance-process live)
   process)
  (rpc-process-set-event-handler
   process
   (lambda (event)
     (dolist
         (subscriber
          (copy-list
           (live-instance-subscribers
            live)))
       (funcall subscriber event))))
  (rpc-process-set-ui-handler
   process
   (lambda (request)
     (let ((handler
             (live-instance-ui-handler
              live)))
       (when handler
         (funcall handler request)))))
  (rpc-process-set-exit-handler
   process
   (lambda (cause)
     (handle-unexpected-rpc-exit
      supervisor live cause)))
  process)

(defun get-state-response-p (response)
  (and
   (cadr-ai::json-get
    response "success")
   (string=
    "get_state"
    (cadr-ai::json-get
     response "command"))
   (hash-table-p
    (cadr-ai::json-get
     response "data"))))

(defun sync-instance-record
    (supervisor live)
  (let ((process
          (live-instance-process live)))
    (when process
      (let ((response
              (rpc-process-send
               process
               (ensure-rpc-command-id
                (cadr-ai::json-object
                 "type" "get_state")))))
        (when (get-state-response-p
               response)
          (let ((data
                  (cadr-ai::json-get
                   response "data")))
            (update-instance-record
             supervisor live
             :session-id
             (cadr-ai::json-get
              data "sessionId")
             :session-file
             (cadr-ai::json-get
              data "sessionFile")))))))
  (live-instance-record live))

(defun refresh-session-metadata-p
    (command)
  (member
   (cadr-ai::json-get command "type")
   '("new_session"
     "switch_session"
     "fork"
     "clone"
     "set_session_name"
     "prompt")
   :test #'string=))

(defun supervisor-spawn-instance
    (supervisor &key cwd label)
  (let* ((now (current-iso8601))
         (record
           (make-instance-record
            :id (cadr-ai:uuid-v7)
            :status :starting
            :cwd (namestring
                  (pathname cwd))
            :created-at now
            :last-seen-at now
            :label label))
         (live
           (make-live-instance
            :record record)))
    (sb-thread:with-mutex
        ((supervisor-lock supervisor))
      (setf
       (gethash
        (instance-record-id record)
        (supervisor-live supervisor))
       live))
    (upsert-instance
     (supervisor-directory supervisor)
     record)
    (handler-case
        (progn
          (bind-rpc-process
           supervisor live
           (funcall
            (supervisor-process-factory
             supervisor)
            cwd))
          (sync-instance-record
           supervisor live)
          (let ((registered
                  (radius-register-pi
                   (supervisor-radius
                    supervisor)
                   record)))
            (setf
             (live-instance-record live)
             registered))
          (set-instance-status
           supervisor live :online)
          (clone-instance-record
           (live-instance-record live)))
      (error (cause)
        (set-instance-status
         supervisor live :error)
        (clear-rpc-bindings live)
        (when (live-instance-process live)
          (ignore-errors
            (rpc-process-dispose
             (live-instance-process
              live))))
        (setf
         (live-instance-process live)
         nil)
        (set-instance-status
         supervisor live :stopped)
        (sb-thread:with-mutex
            ((supervisor-lock
              supervisor))
          (remhash
           (instance-record-id record)
           (supervisor-live
            supervisor)))
        (error cause)))))

(defun supervisor-get-live
    (supervisor instance-id)
  (sb-thread:with-mutex
      ((supervisor-lock supervisor))
    (gethash instance-id
             (supervisor-live
              supervisor))))

(defun supervisor-get-live-instance
    (supervisor instance-id)
  (let ((live
          (supervisor-get-live
           supervisor instance-id)))
    (and live
         (clone-instance-record
          (live-instance-record
           live)))))

(defun supervisor-list-live-instances
    (supervisor)
  (sb-thread:with-mutex
      ((supervisor-lock supervisor))
    (loop
      for live being the hash-values
      of (supervisor-live supervisor)
      collect
      (clone-instance-record
       (live-instance-record live)))))

(defun supervisor-update-instance
    (supervisor instance)
  (let ((record
          (clone-instance-record
           instance)))
    (sb-thread:with-mutex
        ((supervisor-lock supervisor))
      (let ((live
              (gethash
               (instance-record-id record)
               (supervisor-live
                supervisor))))
        (when live
          (setf
           (live-instance-record live)
           record))))
    (upsert-instance
     (supervisor-directory supervisor)
     record)
    (clone-instance-record record)))

(defun supervisor-list-instances
    (supervisor)
  (mapcar
   #'clone-instance-record
   (load-instances
    (supervisor-directory
     supervisor))))

(defun supervisor-get-instance
    (supervisor instance-id)
  (or
   (supervisor-get-live-instance
    supervisor instance-id)
   (let ((stored
           (get-stored-instance
            (supervisor-directory
             supervisor)
            instance-id)))
     (and stored
          (clone-instance-record
           stored)))))

(defun supervisor-handle-rpc
    (supervisor instance-id command)
  (let ((live
          (supervisor-get-live
           supervisor instance-id)))
    (when
        (and live
             (live-instance-process
              live))
      (ensure-rpc-command-id command)
      (let ((response
              (rpc-process-send
               (live-instance-process
                live)
               command)))
        (when
            (refresh-session-metadata-p
             command)
          (sync-instance-record
           supervisor live))
        response))))

(defun supervisor-open-rpc-stream
    (supervisor instance-id
     event-handler ui-handler)
  (let ((live
          (supervisor-get-live
           supervisor instance-id)))
    (when
        (and live
             (live-instance-process
              live))
      (pushnew
       event-handler
       (live-instance-subscribers live)
       :test #'eq)
      (setf
       (live-instance-ui-handler live)
       ui-handler)
      (%make-rpc-stream-handle
       :supervisor supervisor
       :instance-id instance-id
       :event-handler event-handler
       :ui-handler ui-handler))))

(defun rpc-stream-send
    (stream command)
  (when
      (rpc-stream-handle-closed-p
       stream)
    (error "RPC stream is closed"))
  (or
   (supervisor-handle-rpc
    (rpc-stream-handle-supervisor
     stream)
    (rpc-stream-handle-instance-id
     stream)
    command)
   (error "Unknown instance: ~A"
          (rpc-stream-handle-instance-id
           stream))))

(defun rpc-stream-handle-ui-response
    (stream response)
  (unless
      (rpc-stream-handle-closed-p
       stream)
    (let ((live
            (supervisor-get-live
             (rpc-stream-handle-supervisor
              stream)
             (rpc-stream-handle-instance-id
              stream))))
      (when
          (and live
               (live-instance-process
                live))
        (rpc-process-handle-ui-response
         (live-instance-process live)
         response))))
  nil)

(defun close-rpc-stream (stream)
  (unless
      (rpc-stream-handle-closed-p
       stream)
    (setf
     (rpc-stream-handle-closed-p
      stream)
     t)
    (let ((live
            (supervisor-get-live
             (rpc-stream-handle-supervisor
              stream)
             (rpc-stream-handle-instance-id
              stream))))
      (when live
        (setf
         (live-instance-subscribers
          live)
         (remove
          (rpc-stream-handle-event-handler
           stream)
          (live-instance-subscribers
           live)
          :test #'eq))
        (when
            (eq
             (live-instance-ui-handler live)
             (rpc-stream-handle-ui-handler
              stream))
          (setf
           (live-instance-ui-handler live)
           nil)))))
  nil)

(defun supervisor-stop-instance
    (supervisor instance-id)
  (let ((live
          (supervisor-get-live
           supervisor instance-id)))
    (when live
      (set-instance-status
       supervisor live :stopping)
      (unwind-protect
           (progn
             (ignore-errors
               (radius-disconnect-pi
                (supervisor-radius
                 supervisor)
                (live-instance-record
                 live)))
             (clear-rpc-bindings live)
             (when
                 (live-instance-process
                  live)
               (rpc-process-dispose
                (live-instance-process
                 live)))
             (setf
              (live-instance-process live)
              nil))
        (setf
         (instance-record-status
          (live-instance-record live))
         :stopped
         (instance-record-last-seen-at
          (live-instance-record live))
         (current-iso8601))
        (sb-thread:with-mutex
            ((supervisor-lock
              supervisor))
          (remhash
           instance-id
           (supervisor-live
            supervisor)))
        (remove-instance
         (supervisor-directory
          supervisor)
         instance-id))
      (clone-instance-record
       (live-instance-record
        live)))))

(defun supervisor-recover-after-restart
    (supervisor)
  (let ((records
          (load-instances
           (supervisor-directory
            supervisor)))
        (now (current-iso8601)))
    (dolist (record records)
      (when
          (member
           (instance-record-status
            record)
           '(:starting :online))
        (setf
         (instance-record-status record)
         :stopped))
      (setf
       (instance-record-last-seen-at
        record)
       now)
      (ignore-errors
        (radius-disconnect-pi
         (supervisor-radius supervisor)
         record)))
    (save-instances
     (supervisor-directory supervisor)
     records)
    records))

(defun supervisor-shutdown
    (supervisor)
  (let ((ids nil))
    (sb-thread:with-mutex
        ((supervisor-lock supervisor))
      (maphash
       (lambda (id live)
         (declare (ignore live))
         (push id ids))
       (supervisor-live supervisor)))
    (dolist (id ids)
      (supervisor-stop-instance
       supervisor id)))
  (radius-stop
   (supervisor-radius supervisor))
  nil)
