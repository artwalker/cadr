(in-package #:cadr-server)

(defclass radius-presence () ())

(defclass dormant-radius-presence
    (radius-presence)
  ())

(defstruct radius-heartbeat
  (lock
   (sb-thread:make-mutex
    :name "cadr-radius-heartbeat"))
  (waitqueue
   (sb-thread:make-waitqueue
    :name "cadr-radius-heartbeat"))
  (stopped-p nil)
  thread)

(defclass http-radius-presence
    (radius-presence)
  ((directory
    :initarg :directory
    :reader radius-directory)
   (token
    :initarg :token
    :reader radius-token)
   (base-url
    :initarg :base-url
    :reader radius-base-url)
   (machine
    :initform nil
    :accessor radius-machine)
   (machine-heartbeat
    :initform nil
    :accessor radius-machine-heartbeat)
   (pi-heartbeats
    :initform
    (make-hash-table :test #'equal)
    :reader radius-pi-heartbeats)
   (lock
    :initform
    (sb-thread:make-mutex
     :name "cadr-radius")
    :reader radius-lock)))

(defgeneric radius-start
    (presence &key label))
(defgeneric radius-stop (presence))
(defgeneric radius-register-pi
    (presence instance))
(defgeneric radius-disconnect-pi
    (presence instance))

(defun make-dormant-radius-presence ()
  (make-instance
   'dormant-radius-presence))

(defmethod radius-start
    ((presence dormant-radius-presence)
     &key label)
  (declare (ignore label))
  nil)

(defmethod radius-stop
    ((presence dormant-radius-presence))
  nil)

(defmethod radius-register-pi
    ((presence dormant-radius-presence)
     instance)
  instance)

(defmethod radius-disconnect-pi
    ((presence dormant-radius-presence)
     instance)
  (declare (ignore instance))
  nil)

(defun radius-auth-path ()
  (merge-pathnames
   ".cadr/auth.json"
   (user-homedir-pathname)))

(defun stored-radius-token ()
  (let ((path (radius-auth-path)))
    (when (probe-file path)
      (let ((credential
              (ignore-errors
                (cadr-ai:read-auth-credential
                 path :radius))))
        (and
         (typep credential
                'cadr-ai:oauth-credential)
         (cadr-ai:oauth-credential-access
          credential))))))

(defun radius-access-token ()
  (or (stored-radius-token)
      (uiop:getenv "RADIUS_API_KEY")))

(defun radius-server-base-url ()
  (or (uiop:getenv
       "CADR_RADIUS_SERVER_URL")
      (uiop:getenv
       "PI_RADIUS_SERVER_URL")
      (let ((root
              (or
               (uiop:getenv
                "CADR_RADIUS_URL")
               (uiop:getenv
                "PI_RADIUS_URL")
               "https://radius.pi.dev/")))
        (format nil "~A~A"
                (string-right-trim "/" root)
                "/v1/"))))

(defun make-radius-presence
    (&key
       (directory (server-directory)))
  (let ((token
          (radius-access-token)))
    (if (and token
             (plusp (length token)))
        (make-instance
         'http-radius-presence
         :directory directory
         :token token
         :base-url
         (radius-server-base-url))
        (make-dormant-radius-presence))))

(defun radius-url (presence path)
  (format nil "~A~A"
          (string-right-trim
           "/" (radius-base-url presence))
          (if (and (plusp (length path))
                   (char= #\/ (char path 0)))
              path
              (concatenate
               'string "/" path))))

(defun radius-post
    (presence path body)
  (cadr-ai:request-json
   (cadr-ai::make-request-spec
    :url (radius-url presence path)
    :method :post
    :headers
    `(("Authorization"
       . ,(format nil
                  "Bearer ~A"
                  (radius-token presence)))
      ("Content-Type"
       . "application/json"))
    :payload body
    :provider :radius)))

(defun stop-radius-heartbeat (state)
  (when state
    (sb-thread:with-mutex
        ((radius-heartbeat-lock state))
      (setf
       (radius-heartbeat-stopped-p state)
       t)
      (sb-thread:condition-broadcast
       (radius-heartbeat-waitqueue
        state))))
  nil)

(defun radius-heartbeat-loop
    (state interval-milliseconds function)
  (loop
    (sb-thread:with-mutex
        ((radius-heartbeat-lock state))
      (when
          (radius-heartbeat-stopped-p state)
        (return))
      (sb-thread:condition-wait
       (radius-heartbeat-waitqueue state)
       (radius-heartbeat-lock state)
       :timeout
       (/ interval-milliseconds
          1000.0))
      (when
          (radius-heartbeat-stopped-p state)
        (return)))
    (handler-case
        (funcall function)
      (error (cause)
        (format
         *error-output*
         "cadr-server: Radius heartbeat failed: ~A~%"
         cause)
        (finish-output *error-output*)))))

(defun start-radius-heartbeat
    (interval-milliseconds function name)
  (let ((state
          (make-radius-heartbeat)))
    (setf
     (radius-heartbeat-thread state)
     (sb-thread:make-thread
      (lambda ()
        (radius-heartbeat-loop
         state interval-milliseconds
         function))
      :name name))
    state))

(defun register-radius-machine
    (presence &optional label)
  (let* ((existing
           (or (radius-machine presence)
               (load-machine
                (radius-directory presence))))
         (response
           (radius-post
            presence
            "machines/register"
            (cadr-ai::json-object
             "machineId"
             (and existing
                  (machine-record-id existing))
             "label" label
             "hostname" (machine-instance)
             "platform" (software-type)
             "arch" (machine-type)
             "version" "0.1.0"
             "capabilities"
             (cadr-ai::json-object
              "spawn" t
              "relay" nil
              "iroh" nil))))
         (now (current-iso8601))
         (record
           (make-machine-record
            :id
            (cadr-ai::json-get
             response "id")
            :created-at
            (if existing
                (machine-record-created-at
                 existing)
                now)
            :last-seen-at now
            :label label)))
    (setf (radius-machine presence)
          record)
    (save-machine
     (radius-directory presence)
     record)
    (values
     record
     (or
      (cadr-ai::json-get
       response "heartbeatIntervalMs")
      30000))))

(defmethod radius-start
    ((presence http-radius-presence)
     &key label)
  (multiple-value-bind
        (machine interval)
      (register-radius-machine
       presence label)
    (stop-radius-heartbeat
     (radius-machine-heartbeat
      presence))
    (setf
     (radius-machine-heartbeat presence)
     (start-radius-heartbeat
      interval
      (lambda ()
        (radius-post
         presence
         (format nil
                 "machines/~A/heartbeat"
                 (machine-record-id
                  (radius-machine
                   presence)))
         (cadr-ai::json-object
          "cwd"
          (namestring
           (radius-directory presence))
          "socketPath"
          (namestring
           (server-socket-path
            (radius-directory
             presence))))))
      "cadr-radius-machine"))
    machine))

(defun install-pi-heartbeat
    (presence instance-id radius-id interval)
  (sb-thread:with-mutex
      ((radius-lock presence))
    (stop-radius-heartbeat
     (gethash instance-id
              (radius-pi-heartbeats
               presence)))
    (setf
     (gethash instance-id
              (radius-pi-heartbeats
               presence))
     (start-radius-heartbeat
      interval
      (lambda ()
        (radius-post
         presence
         (format nil
                 "pis/~A/heartbeat"
                 radius-id)
         (cadr-ai::json-object)))
      (format nil
              "cadr-radius-pi-~A"
              instance-id)))))

(defmethod radius-register-pi
    ((presence http-radius-presence)
     instance)
  (unless (radius-machine presence)
    (radius-start presence))
  (let* ((response
           (radius-post
            presence
            "pis/register"
            (cadr-ai::json-object
             "machineId"
             (machine-record-id
              (radius-machine presence))
             "label"
             (instance-record-label instance)
             "cwd"
             (instance-record-cwd instance)
             "hostname" (machine-instance)
             "pid" (sb-posix:getpid)
             "transport" "local-rpc"
             "capabilities"
             (cadr-ai::json-object
              "rpc" t
              "relay" nil
              "iroh" nil)
             "sessionId"
             (instance-record-session-id
              instance))))
         (radius-id
           (cadr-ai::json-get
            response "id")))
    (setf
     (instance-record-radius-pi-id
      instance)
     radius-id)
    (install-pi-heartbeat
     presence
     (instance-record-id instance)
     radius-id
     (or
      (cadr-ai::json-get
       response "heartbeatIntervalMs")
      30000))
    instance))

(defmethod radius-disconnect-pi
    ((presence http-radius-presence)
     instance)
  (let ((state nil))
    (sb-thread:with-mutex
        ((radius-lock presence))
      (setf
       state
       (gethash
        (instance-record-id instance)
        (radius-pi-heartbeats
         presence)))
      (remhash
       (instance-record-id instance)
       (radius-pi-heartbeats presence)))
    (stop-radius-heartbeat state))
  (when (instance-record-radius-pi-id
         instance)
    (handler-case
        (radius-post
         presence
         (format nil
                 "pis/~A/disconnect"
                 (instance-record-radius-pi-id
                  instance))
         (cadr-ai::json-object))
      (cadr-ai:api-error (cause)
        (unless (= 404
                   (cadr-ai:api-error-status
                    cause))
          (error cause)))))
  nil)

(defmethod radius-stop
    ((presence http-radius-presence))
  (stop-radius-heartbeat
   (radius-machine-heartbeat
    presence))
  (setf
   (radius-machine-heartbeat presence)
   nil)
  (let ((states nil))
    (sb-thread:with-mutex
        ((radius-lock presence))
      (maphash
       (lambda (id state)
         (declare (ignore id))
         (push state states))
       (radius-pi-heartbeats presence))
      (clrhash
       (radius-pi-heartbeats presence)))
    (mapc #'stop-radius-heartbeat
          states))
  (when (radius-machine presence)
    (handler-case
        (radius-post
         presence
         (format nil
                 "machines/~A/disconnect"
                 (machine-record-id
                  (radius-machine
                   presence)))
         (cadr-ai::json-object))
      (cadr-ai:api-error (cause)
        (unless (= 404
                   (cadr-ai:api-error-status
                    cause))
          (error cause)))))
  nil)
