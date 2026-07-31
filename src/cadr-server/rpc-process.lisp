(in-package #:cadr-server)

(defgeneric rpc-process-send
    (process command))
(defgeneric rpc-process-dispose
    (process))
(defgeneric rpc-process-set-event-handler
    (process handler))
(defgeneric rpc-process-set-ui-handler
    (process handler))
(defgeneric rpc-process-set-exit-handler
    (process handler))
(defgeneric rpc-process-handle-ui-response
    (process response))

(defstruct pending-rpc
  (lock
   (sb-thread:make-mutex
    :name "cadr-server-rpc-pending"))
  (waitqueue
   (sb-thread:make-waitqueue
    :name "cadr-server-rpc-pending"))
  (done-p nil)
  response
  error)

(defclass rpc-process-instance ()
  ((process
    :initarg :process
    :reader rpc-child-process)
   (input
    :initarg :input
    :reader rpc-child-input)
   (output
    :initarg :output
    :reader rpc-child-output)
   (error-output
    :initarg :error-output
    :reader rpc-child-error-output)
   (pending
    :initform
    (make-hash-table :test #'equal)
    :reader rpc-child-pending)
   (pending-lock
    :initform
    (sb-thread:make-mutex
     :name "cadr-server-rpc-pending-map")
    :reader rpc-child-pending-lock)
   (write-lock
    :initform
    (sb-thread:make-mutex
     :name "cadr-server-rpc-write")
    :reader rpc-child-write-lock)
   (state-lock
    :initform
    (sb-thread:make-mutex
     :name "cadr-server-rpc-state")
    :reader rpc-child-state-lock)
   (event-handler
    :initform nil
    :accessor rpc-child-event-handler)
   (ui-handler
    :initform nil
    :accessor rpc-child-ui-handler)
   (exit-handler
    :initform nil
    :accessor rpc-child-exit-handler)
   (stderr-text
    :initform
    (make-array
     0 :element-type 'character
     :adjustable t :fill-pointer 0)
    :accessor rpc-child-stderr-text)
   (exited-p
    :initform nil
    :accessor rpc-child-exited-p)
   (disposed-p
    :initform nil
    :accessor rpc-child-disposed-p)
   (reader-thread
    :initform nil
    :accessor rpc-child-reader-thread)
   (stderr-thread
    :initform nil
    :accessor rpc-child-stderr-thread)
   (wait-thread
    :initform nil
    :accessor rpc-child-wait-thread)))

(defun rpc-command-id ()
  (format nil
          "server_~A_~A"
          (get-universal-time)
          (cadr-ai:uuid-v7)))

(defun ensure-rpc-command-id (command)
  (unless
      (cadr-ai::json-get command "id")
    (cadr-ai::json-put
     command "id" (rpc-command-id)))
  command)

(defun pending-rpc-complete
    (pending &key response error)
  (sb-thread:with-mutex
      ((pending-rpc-lock pending))
    (setf
     (pending-rpc-response pending)
     response
     (pending-rpc-error pending)
     error
     (pending-rpc-done-p pending)
     t)
    (sb-thread:condition-broadcast
     (pending-rpc-waitqueue pending))))

(defun reject-pending-rpc
    (process cause)
  (let ((pending nil))
    (sb-thread:with-mutex
        ((rpc-child-pending-lock process))
      (maphash
       (lambda (id entry)
         (declare (ignore id))
         (push entry pending))
       (rpc-child-pending process))
      (clrhash
       (rpc-child-pending process)))
    (dolist (entry pending)
      (pending-rpc-complete
       entry :error cause))))

(defun rpc-process-error
    (process control &rest arguments)
  (error "~?~@[ Stderr: ~A~]"
         control arguments
         (let ((text
                 (rpc-child-stderr-text
                  process)))
           (and (plusp (length text))
                (coerce text 'string)))))

(defun handle-rpc-child-line
    (process line)
  (let* ((message
           (parse-server-line line))
         (type
           (cadr-ai::json-get
            message "type")))
    (cond
      ((string= type "response")
       (let* ((id
                (cadr-ai::json-get
                 message "id"))
              (pending
                (and id
                     (sb-thread:with-mutex
                         ((rpc-child-pending-lock
                           process))
                       (prog1
                           (gethash
                            id
                            (rpc-child-pending
                             process))
                         (remhash
                          id
                          (rpc-child-pending
                           process)))))))
         (when pending
           (pending-rpc-complete
            pending :response message))))
      ((string= type
                "extension_ui_request")
       (let ((handler
               (rpc-child-ui-handler
                process)))
         (when handler
           (funcall handler message))))
      (t
       (let ((handler
               (rpc-child-event-handler
                process)))
         (when handler
           (funcall handler message)))))))

(defun rpc-child-reader-loop (process)
  (handler-case
      (loop
        for line =
        (read-line
         (rpc-child-output process)
         nil nil)
        while line
        unless
        (zerop
         (length
          (string-trim
           '(#\Space #\Tab #\Return)
           line)))
          do
             (handler-case
                 (handle-rpc-child-line
                  process line)
               (error (cause)
                 (reject-pending-rpc
                  process cause))))
    (error (cause)
      (unless
          (rpc-child-disposed-p process)
        (reject-pending-rpc
         process cause)))))

(defun rpc-child-stderr-loop (process)
  (handler-case
      (loop
        for character =
        (read-char
         (rpc-child-error-output process)
         nil nil)
        while character
        do
           (vector-push-extend
            character
            (rpc-child-stderr-text process)))
    (error () nil)))

(defun wait-rpc-child-process (process)
  (uiop:wait-process process))

(defun rpc-child-wait-loop (process)
  (let* ((status
           (wait-rpc-child-process
            (rpc-child-process process)))
         (cause
           (make-condition
            'simple-error
            :format-control
            "RPC process exited (status=~A)"
            :format-arguments
            (list status)))
         (handler nil))
    (sb-thread:with-mutex
        ((rpc-child-state-lock process))
      (setf
       (rpc-child-exited-p process)
       t
       handler
       (rpc-child-exit-handler
        process)))
    (reject-pending-rpc process cause)
    (when (and handler
               (not
                (rpc-child-disposed-p
                 process)))
      (funcall handler cause))))

(defun rpc-child-command ()
  (or
   (uiop:getenv
    "CADR_SERVER_CADR_PATH")
   (uiop:getenv
    "PI_SERVER_CADR_PATH")
   "cadr"))

(defun make-rpc-process
    (cwd)
  (let* ((process
           (uiop:launch-program
            (list (rpc-child-command)
                  "--mode" "rpc")
            :directory cwd
            :input :stream
            :output :stream
            :error-output :stream
            :wait nil))
         (instance
           (make-instance
            'rpc-process-instance
            :process process
            :input
            (uiop:process-info-input
             process)
            :output
            (uiop:process-info-output
             process)
            :error-output
            (uiop:process-info-error-output
             process))))
    (setf
     (rpc-child-reader-thread instance)
     (sb-thread:make-thread
      (lambda ()
        (rpc-child-reader-loop
         instance))
      :name "cadr-server-rpc-reader")
     (rpc-child-stderr-thread instance)
     (sb-thread:make-thread
      (lambda ()
        (rpc-child-stderr-loop
         instance))
      :name "cadr-server-rpc-stderr")
     (rpc-child-wait-thread instance)
     (sb-thread:make-thread
      (lambda ()
        (rpc-child-wait-loop
         instance))
      :name "cadr-server-rpc-wait"))
    instance))

(defmethod rpc-process-send
    ((process rpc-process-instance)
     command)
  (ensure-rpc-command-id command)
  (when (rpc-child-exited-p process)
    (rpc-process-error
     process
     "RPC process is not running."))
  (let* ((id
           (cadr-ai::json-get command "id"))
         (pending
           (make-pending-rpc)))
    (sb-thread:with-mutex
        ((rpc-child-pending-lock process))
      (setf
       (gethash id
                (rpc-child-pending process))
       pending))
    (handler-case
        (sb-thread:with-mutex
            ((rpc-child-write-lock process))
          (write-string
           (encode-server-message command)
           (rpc-child-input process))
          (finish-output
           (rpc-child-input process)))
      (error (cause)
        (sb-thread:with-mutex
            ((rpc-child-pending-lock process))
          (remhash
           id
           (rpc-child-pending process)))
        (pending-rpc-complete
         pending :error cause)))
    (sb-thread:with-mutex
        ((pending-rpc-lock pending))
      (loop until
            (pending-rpc-done-p pending)
            do
               (sb-thread:condition-wait
                (pending-rpc-waitqueue
                 pending)
                (pending-rpc-lock
                 pending))))
    (when (pending-rpc-error pending)
      (error
       (pending-rpc-error pending)))
    (pending-rpc-response pending)))

(defmethod rpc-process-handle-ui-response
    ((process rpc-process-instance)
     response)
  (unless (rpc-child-exited-p process)
    (sb-thread:with-mutex
        ((rpc-child-write-lock process))
      (write-string
       (encode-server-message response)
       (rpc-child-input process))
      (finish-output
       (rpc-child-input process))))
  nil)

(defmethod rpc-process-set-event-handler
    ((process rpc-process-instance)
     handler)
  (setf
   (rpc-child-event-handler process)
   handler))

(defmethod rpc-process-set-ui-handler
    ((process rpc-process-instance)
     handler)
  (setf
   (rpc-child-ui-handler process)
   handler))

(defmethod rpc-process-set-exit-handler
    ((process rpc-process-instance)
     handler)
  (setf
   (rpc-child-exit-handler process)
   handler))

(defmethod rpc-process-dispose
    ((process rpc-process-instance))
  (setf
   (rpc-child-disposed-p process)
   t
   (rpc-child-event-handler process)
   nil
   (rpc-child-ui-handler process)
   nil
   (rpc-child-exit-handler process)
   nil)
  (reject-pending-rpc
   process
   (make-condition
    'simple-error
    :format-control
    "RPC process disposed"))
  (when
      (uiop:process-alive-p
       (rpc-child-process process))
    (uiop:terminate-process
     (rpc-child-process process)
     :urgent nil))
  (ignore-errors
    (wait-rpc-child-process
     (rpc-child-process process)))
  nil)
