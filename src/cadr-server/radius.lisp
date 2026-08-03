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
  (interval-milliseconds 30000)
  (delay-milliseconds 30000)
  (consecutive-not-found-count 0)
  (transient-failure-count 0)
  radius-id
  thread)

(defparameter +radius-not-found-retry-threshold+
  3)
(defparameter +radius-backoff-base-milliseconds+
  1000)
(defparameter +radius-backoff-max-milliseconds+
  30000)

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
   (machine-label
    :initform nil
    :accessor radius-machine-label)
   (pi-heartbeats
    :initform
    (make-hash-table :test #'equal)
    :reader radius-pi-heartbeats)
   (lock
    :initform
    (sb-thread:make-mutex
     :name "cadr-radius")
    :reader radius-lock)
   (get-live-instance-function
    :initform (constantly nil)
    :accessor radius-get-live-instance-function)
   (list-live-instances-function
    :initform (constantly nil)
    :accessor radius-list-live-instances-function)
   (update-instance-function
    :initform (constantly nil)
    :accessor radius-update-instance-function)))

(cadr-core:define-redacted-print-object
    (http-radius-presence value stream)
  (format stream ":base-url ~A :token [REDACTED]"
          (radius-base-url value)))

(defgeneric radius-start
    (presence &key label))
(defgeneric radius-stop (presence))
(defgeneric radius-register-pi
    (presence instance))
(defgeneric radius-disconnect-pi
    (presence instance))

(defun radius-configure-coordinator
    (presence
     &key get-live-instance
       list-live-instances
       update-instance)
  (when
      (typep presence
             'http-radius-presence)
    (setf
     (radius-get-live-instance-function
      presence)
     (or get-live-instance
         (constantly nil))
     (radius-list-live-instances-function
      presence)
     (or list-live-instances
         (constantly nil))
     (radius-update-instance-function
      presence)
     (or update-instance
         (constantly nil))))
  presence)

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

(defun radius-not-found-error-p (cause)
  (and
   (typep cause 'cadr-ai:api-error)
   (= 404
      (cadr-ai:api-error-status
       cause))))

(defun radius-backoff-delay
    (failure-count)
  (let* ((exponential
           (min
            +radius-backoff-max-milliseconds+
            (* +radius-backoff-base-milliseconds+
               (expt
                2
                (max 0
                     (1- failure-count))))))
         (jitter-limit
           (max 250
                (ceiling exponential 4))))
    (min
     +radius-backoff-max-milliseconds+
     (+ exponential
        (random jitter-limit)))))

(defun record-radius-heartbeat-success
    (state)
  (setf
   (radius-heartbeat-consecutive-not-found-count
    state)
   0
   (radius-heartbeat-transient-failure-count
    state)
   0)
  (radius-heartbeat-interval-milliseconds
   state))

(defun record-radius-heartbeat-error
    (state cause)
  (if (radius-not-found-error-p cause)
      (progn
        (setf
         (radius-heartbeat-transient-failure-count
          state)
         0)
        (incf
         (radius-heartbeat-consecutive-not-found-count
          state))
        (if
            (>=
             (radius-heartbeat-consecutive-not-found-count
              state)
             +radius-not-found-retry-threshold+)
            (values :reregister nil)
            (values
             :retry
             (radius-heartbeat-interval-milliseconds
              state))))
      (progn
        (incf
         (radius-heartbeat-transient-failure-count
          state))
        (values
         :retry
         (radius-backoff-delay
          (radius-heartbeat-transient-failure-count
           state))))))

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
    (state function)
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
       (/ (radius-heartbeat-delay-milliseconds
           state)
          1000.0))
      (when
          (radius-heartbeat-stopped-p state)
        (return)))
    (setf
     (radius-heartbeat-delay-milliseconds
      state)
     (or
      (handler-case
          (funcall function state)
        (error (cause)
          (format
           *error-output*
           "cadr-server: Radius heartbeat failed: ~A~%"
           cause)
          (finish-output *error-output*)
          (multiple-value-bind
                (action delay)
              (record-radius-heartbeat-error
               state cause)
            (declare (ignore action))
            delay)))
      (radius-heartbeat-interval-milliseconds
       state)))))

(defun start-radius-heartbeat
    (interval-milliseconds function name
     &key radius-id)
  (let ((state
          (make-radius-heartbeat
           :interval-milliseconds
           interval-milliseconds
           :delay-milliseconds
           interval-milliseconds
           :radius-id radius-id)))
    (setf
     (radius-heartbeat-thread state)
     (sb-thread:make-thread
      (lambda ()
        (radius-heartbeat-loop
         state function))
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
             "version" (cadr-ai::cadr-version)
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

(defun record-radius-recovery-error
    (state)
  (incf
   (radius-heartbeat-transient-failure-count
    state))
  (radius-backoff-delay
   (radius-heartbeat-transient-failure-count
    state)))

(defun log-radius-retry
    (scope action state delay cause)
  (format
   *error-output*
   "cadr-server: ~A ~A failed (attempt ~A); retrying in ~Ams: ~A~%"
   scope action
   (radius-heartbeat-transient-failure-count
    state)
   delay cause)
  (finish-output *error-output*))

(defun radius-reregister-pi
    (presence instance-id)
  (let ((instance
          (funcall
           (radius-get-live-instance-function
            presence)
           instance-id)))
    (unless instance
      (let ((state nil))
        (sb-thread:with-mutex
            ((radius-lock presence))
          (setf
           state
           (gethash
            instance-id
            (radius-pi-heartbeats
             presence)))
          (remhash
           instance-id
           (radius-pi-heartbeats
            presence)))
        (stop-radius-heartbeat state))
      (return-from radius-reregister-pi
        nil))
    (let ((registered
            (radius-register-pi
             presence instance)))
      (funcall
       (radius-update-instance-function
        presence)
       registered)
      t)))

(defun radius-reregister-machine-and-pis
    (presence)
  (radius-start
   presence
   :label
   (radius-machine-label presence))
  (dolist
      (instance
       (funcall
        (radius-list-live-instances-function
         presence)))
    (handler-case
        (radius-reregister-pi
         presence
         (instance-record-id instance))
      (error (cause)
        (format
         *error-output*
         "cadr-server: Radius Pi ~A re-registration failed: ~A~%"
         (instance-record-id instance)
         cause)
        (finish-output *error-output*))))
  t)

(defun heartbeat-radius-machine
    (presence state)
  (handler-case
      (progn
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
             presence)))))
        (record-radius-heartbeat-success
         state))
    (error (cause)
      (multiple-value-bind
            (action delay)
          (record-radius-heartbeat-error
           state cause)
        (if (eq action :retry)
            (progn
              (unless
                  (radius-not-found-error-p
                   cause)
                (log-radius-retry
                 "Radius machine"
                 "heartbeat"
                 state delay cause))
              delay)
            (handler-case
                (progn
                  (radius-reregister-machine-and-pis
                   presence)
                  (record-radius-heartbeat-success
                   state))
              (error (recovery-cause)
                (let ((recovery-delay
                        (record-radius-recovery-error
                         state)))
                  (log-radius-retry
                   "Radius machine"
                   "re-registration"
                   state recovery-delay
                   recovery-cause)
                  recovery-delay))))))))

(defun heartbeat-radius-pi
    (presence instance-id state)
  (handler-case
      (progn
        (radius-post
         presence
         (format nil
                 "pis/~A/heartbeat"
                 (radius-heartbeat-radius-id
                  state))
         (cadr-ai::json-object))
        (record-radius-heartbeat-success
         state))
    (error (cause)
      (multiple-value-bind
            (action delay)
          (record-radius-heartbeat-error
           state cause)
        (if (eq action :retry)
            (progn
              (unless
                  (radius-not-found-error-p
                   cause)
                (log-radius-retry
                 (format nil
                         "Radius Pi ~A"
                         instance-id)
                 "heartbeat"
                 state delay cause))
              delay)
            (handler-case
                (if
                    (radius-reregister-pi
                     presence instance-id)
                    (record-radius-heartbeat-success
                     state)
                    (let ((retry-delay
                            (radius-backoff-delay 1)))
                      (format
                       *error-output*
                       "cadr-server: Radius Pi ~A re-registration skipped; retrying in ~Ams~%"
                       instance-id retry-delay)
                      (finish-output
                       *error-output*)
                      retry-delay))
              (error (recovery-cause)
                (let ((recovery-delay
                        (record-radius-recovery-error
                         state)))
                  (log-radius-retry
                   (format nil
                           "Radius Pi ~A"
                           instance-id)
                   "re-registration"
                   state recovery-delay
                   recovery-cause)
                  recovery-delay))))))))

(defmethod radius-start
    ((presence http-radius-presence)
     &key label)
  (multiple-value-bind
        (machine interval)
      (register-radius-machine
       presence label)
    (setf
     (radius-machine-label presence)
     label)
    (stop-radius-heartbeat
     (radius-machine-heartbeat
      presence))
    (setf
     (radius-machine-heartbeat presence)
     (start-radius-heartbeat
      interval
      (lambda (state)
        (heartbeat-radius-machine
         presence state))
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
      (lambda (state)
        (heartbeat-radius-pi
         presence instance-id state))
      (format nil
              "cadr-radius-pi-~A"
              instance-id)
      :radius-id radius-id))))

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
