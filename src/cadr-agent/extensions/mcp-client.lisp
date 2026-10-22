(in-package #:cadr-agent)

;;; pi@4a080252f McpClient. One state string and one pending-request
;;; table own the session. Resources stay out; that is a separate gap.

(defparameter +mcp-default-request-timeout-ms+ 30000)
(defparameter +mcp-max-list-pages+ 1000)

(defstruct mcp-box
  (lock (sb-thread:make-mutex :name "mcp box"))
  (waitqueue (sb-thread:make-waitqueue :name "mcp box"))
  value
  (ready-p nil :type boolean))

(defun mcp-box-put (box value)
  (sb-thread:with-mutex ((mcp-box-lock box))
    (unless (mcp-box-ready-p box)
      (setf (mcp-box-value box) value
            (mcp-box-ready-p box) t)
      (sb-thread:condition-notify (mcp-box-waitqueue box))))
  value)

(defun mcp-box-wait (box)
  (sb-thread:with-mutex ((mcp-box-lock box))
    (loop until (mcp-box-ready-p box)
          do (sb-thread:condition-wait
              (mcp-box-waitqueue box)
              (mcp-box-lock box)))
    (mcp-box-value box)))

(defstruct mcp-pending
  id
  box
  timeout-ms
  timer-cancel
  abort
  on-abort
  (cancellable-p t :type boolean)
  on-progress
  progress-token
  send-abort)

(defstruct (mcp-client (:constructor %make-mcp-client))
  (name "" :type string)
  (version "" :type string)
  title
  capabilities
  protocol-version-request
  (request-timeout-ms +mcp-default-request-timeout-ms+ :type real)
  roots
  scheduler
  (state "idle" :type string)
  transport
  (next-id 1 :type integer)
  server-info
  server-capabilities
  instructions
  protocol-version
  (pending (make-hash-table :test #'equal))
  (progress (make-hash-table :test #'equal))
  (incoming (make-hash-table :test #'equal))
  (handlers (make-hash-table :test #'equal))
  (notifications (make-hash-table :test #'equal))
  (error-listeners nil :type list)
  (close-listeners nil :type list)
  (disposers nil :type list)
  (lock (sb-thread:make-mutex :name "mcp client")))

(defun mcp-real-schedule (delay-ms thunk)
  (let ((timer (sb-ext:make-timer thunk :thread t :name "mcp timeout")))
    (sb-ext:schedule-timer timer (/ delay-ms 1000.0))
    (lambda ()
      (ignore-errors (sb-ext:unschedule-timer timer)))))

(defun make-mcp-client (&key (name "") (version "") title capabilities
                             protocol-version
                             (request-timeout-ms +mcp-default-request-timeout-ms+)
                             roots scheduler)
  (let ((client
          (%make-mcp-client
           :name name
           :version version
           :title title
           :capabilities capabilities
           :protocol-version-request protocol-version
           :request-timeout-ms request-timeout-ms
           :roots roots
           :scheduler scheduler)))
    (setf (gethash "ping" (mcp-client-handlers client))
          (lambda (params abort)
            (declare (ignore params abort))
            (mcp-obj)))
    (when roots
      (setf (gethash "roots/list" (mcp-client-handlers client))
            (lambda (params abort)
              (declare (ignore params abort))
              (mcp-obj "roots"
                       (coerce (mcp-client-current-roots client) 'vector)))))
    client))

(defun mcp-client-current-roots (client)
  (let ((roots (mcp-client-roots client)))
    (copy-list (if (functionp roots) (funcall roots) roots))))

(defun mcp-client-emit-error (client error)
  (let ((normalized
          (if (typep error 'error)
              error
              (make-condition 'simple-error
                              :format-control "~A"
                              :format-arguments (list error))))
        (listeners nil))
    (sb-thread:with-mutex ((mcp-client-lock client))
      (setf listeners (copy-list (mcp-client-error-listeners client))))
    (dolist (listener listeners)
      (funcall listener normalized))))

(defun mcp-client-on-error (client listener)
  (sb-thread:with-mutex ((mcp-client-lock client))
    (push listener (mcp-client-error-listeners client)))
  (lambda ()
    (sb-thread:with-mutex ((mcp-client-lock client))
      (setf (mcp-client-error-listeners client)
            (remove listener (mcp-client-error-listeners client))))))

(defun mcp-client-on-close (client listener)
  (sb-thread:with-mutex ((mcp-client-lock client))
    (push listener (mcp-client-close-listeners client)))
  (lambda ()
    (sb-thread:with-mutex ((mcp-client-lock client))
      (setf (mcp-client-close-listeners client)
            (remove listener (mcp-client-close-listeners client))))))

(defun mcp-client-on-notification (client method listener)
  (sb-thread:with-mutex ((mcp-client-lock client))
    (push listener (gethash method (mcp-client-notifications client))))
  (lambda ()
    (sb-thread:with-mutex ((mcp-client-lock client))
      (setf (gethash method (mcp-client-notifications client))
            (remove listener
                    (gethash method (mcp-client-notifications client)))))))

(defun mcp-client-set-request-handler (client method handler)
  (sb-thread:with-mutex ((mcp-client-lock client))
    (setf (gethash method (mcp-client-handlers client)) handler))
  (lambda ()
    (sb-thread:with-mutex ((mcp-client-lock client))
      (when (eq (gethash method (mcp-client-handlers client)) handler)
        (remhash method (mcp-client-handlers client))))))

(defun mcp-require-transport (client allow-connecting)
  (let ((transport (mcp-client-transport client))
        (state (mcp-client-state client)))
    (if (and transport
             (or (string= state "connected")
                 (and allow-connecting (string= state "connecting"))))
        transport
        (error 'mcp-connection-closed-error
               :message (format nil "MCP client is ~A" state)))))

(defun mcp-cancel-timer (entry)
  (let ((cancel (mcp-pending-timer-cancel entry)))
    (when cancel
      (setf (mcp-pending-timer-cancel entry) nil)
      (funcall cancel))))

(defun mcp-arm-timeout (client id entry)
  (mcp-cancel-timer entry)
  (let ((delay (mcp-pending-timeout-ms entry)))
    (when (and (realp delay) (plusp delay))
      (setf (mcp-pending-timer-cancel entry)
            (funcall (or (mcp-client-scheduler client) #'mcp-real-schedule)
                     delay
                     (lambda ()
                       (mcp-cancel-pending
                        client id
                        (make-condition 'mcp-timeout-error :timeout-ms delay)
                        (mcp-pending-cancellable-p entry)
                        "Request timed out")))))))

(defun mcp-remove-pending (client id entry)
  (remhash id (mcp-client-pending client))
  (mcp-cancel-timer entry)
  (when (mcp-pending-progress-token entry)
    (remhash (mcp-pending-progress-token entry) (mcp-client-progress client)))
  (when (mcp-pending-send-abort entry)
    (mcp-abort (mcp-pending-send-abort entry))))

(defun mcp-cancel-pending (client id error notify-p reason)
  (let ((entry nil)
        (transport nil))
    (sb-thread:with-mutex ((mcp-client-lock client))
      (setf entry (gethash id (mcp-client-pending client)))
      (when entry
        (mcp-remove-pending client id entry)
        (setf transport (mcp-client-transport client))))
    (unless entry
      (return-from mcp-cancel-pending nil))
    (mcp-box-put (mcp-pending-box entry) (cons :error error))
    (when (and notify-p transport)
      (let ((params (mcp-obj "requestId" id)))
        (when (and (stringp reason) (plusp (length reason)))
          (setf params (mcp-put params "reason" reason)))
        (handler-case
            (mcp-transport-send
             transport
             (mcp-obj "jsonrpc" "2.0"
                      "method" "notifications/cancelled"
                      "params" params))
          (error (send-error)
            (mcp-client-emit-error client send-error)))))
    t))

(defun mcp-reject-all (client error)
  (let ((entries nil))
    (sb-thread:with-mutex ((mcp-client-lock client))
      (maphash (lambda (id entry)
                 (declare (ignore id))
                 (push entry entries))
               (mcp-client-pending client))
      (dolist (entry entries)
        (mcp-remove-pending client (mcp-pending-id entry) entry)))
    (dolist (entry entries)
      (mcp-box-put (mcp-pending-box entry) (cons :error error)))))

(defun mcp-mark-closed (client error)
  (let ((listeners nil)
        (incoming nil)
        (was-closed nil))
    (sb-thread:with-mutex ((mcp-client-lock client))
      (setf was-closed (string= (mcp-client-state client) "closed")
            (mcp-client-state client) "closed")
      (maphash (lambda (id abort)
                 (declare (ignore id))
                 (push abort incoming))
               (mcp-client-incoming client))
      (clrhash (mcp-client-incoming client))
      (unless was-closed
        (setf listeners (copy-list (mcp-client-close-listeners client)))))
    (mcp-reject-all client error)
    (dolist (abort incoming)
      (mcp-abort abort error))
    (dolist (listener listeners)
      (handler-case (funcall listener)
        (error (listener-error)
          (mcp-client-emit-error client listener-error))))))

(defun mcp-dispose-transport-listeners (client)
  (let ((disposers nil))
    (sb-thread:with-mutex ((mcp-client-lock client))
      (setf disposers (mcp-client-disposers client)
            (mcp-client-disposers client) nil))
    (dolist (dispose disposers)
      (funcall dispose))))

(defun mcp-client-close (client)
  (let ((transport nil))
    (sb-thread:with-mutex ((mcp-client-lock client))
      (setf transport (mcp-client-transport client)
            (mcp-client-transport client) nil))
    (mcp-dispose-transport-listeners client)
    (mcp-mark-closed client (make-condition 'mcp-connection-closed-error))
    (when transport
      (mcp-transport-close transport)))
  nil)

(defun mcp-abort-reason-text (abort)
  (if (null abort)
      "Aborted"
      (let ((reason (mcp-abort-reason abort)))
        (cond
          ((stringp reason) reason)
          ((null reason) "Aborted")
          (t (princ-to-string reason))))))

(defun mcp-with-progress-meta (params id)
  (let* ((base (or params (mcp-obj)))
         (meta (mcp-get base "_meta"))
         (merged (if (mcp-object-p meta)
                     (list* :json-object (copy-list (cdr meta)))
                     (mcp-obj))))
    (mcp-put base "_meta" (mcp-put merged "progressToken" id))))

(defun mcp-request-internal (client method params
                             &key abort timeout-ms on-progress allow-connecting)
  (when (and abort (mcp-abort-aborted-p abort))
    (error 'mcp-abort-error))
  (let ((id nil)
        (entry nil)
        (transport nil)
        (message nil))
    (sb-thread:with-mutex ((mcp-client-lock client))
      (setf transport (mcp-require-transport client allow-connecting)
            id (mcp-client-next-id client)
            (mcp-client-next-id client) (1+ id))
      (when on-progress
        (setf params (mcp-with-progress-meta params id)))
      (setf message
            (if params
                (mcp-obj "jsonrpc" "2.0" "id" id "method" method "params" params)
                (mcp-obj "jsonrpc" "2.0" "id" id "method" method))
            entry
            (make-mcp-pending
             :id id
             :box (make-mcp-box)
             :timeout-ms (or timeout-ms (mcp-client-request-timeout-ms client))
             :abort abort
             :cancellable-p (not (string= method "initialize"))
             :on-progress on-progress
             :progress-token (and on-progress id)
             :send-abort (make-mcp-abort)))
      (setf (gethash id (mcp-client-pending client)) entry)
      (when on-progress
        (setf (gethash id (mcp-client-progress client)) id))
      (mcp-arm-timeout client id entry))
    (when abort
      (let ((on-abort
              (lambda ()
                (mcp-cancel-pending
                 client id
                 (make-condition 'mcp-abort-error)
                 (not (string= method "initialize"))
                 (mcp-abort-reason-text abort)))))
        (setf (mcp-pending-on-abort entry) on-abort)
        (mcp-abort-subscribe abort on-abort)))
    (handler-case
        (mcp-transport-send transport message :abort (mcp-pending-send-abort entry))
      (error (send-error)
        (mcp-cancel-pending client id send-error nil nil)))
    (let ((outcome (mcp-box-wait (mcp-pending-box entry))))
      (if (eq (car outcome) :ok)
          (cdr outcome)
          (error (cdr outcome))))))

(defun mcp-notify-internal (client method params &key allow-connecting)
  (let ((transport nil)
        (message nil))
    (sb-thread:with-mutex ((mcp-client-lock client))
      (setf transport (mcp-require-transport client allow-connecting)
            message
            (if params
                (mcp-obj "jsonrpc" "2.0" "method" method "params" params)
                (mcp-obj "jsonrpc" "2.0" "method" method))))
    (mcp-transport-send transport message)
    nil))

(defun mcp-client-request (client method &optional params
                           &key abort timeout-ms on-progress)
  (mcp-request-internal client method params
                        :abort abort
                        :timeout-ms timeout-ms
                        :on-progress on-progress))

(defun mcp-client-notify (client method &optional params)
  (mcp-notify-internal client method params))

(defun mcp-client-ping (client &key abort timeout-ms)
  (mcp-client-request client "ping" nil :abort abort :timeout-ms timeout-ms)
  nil)

(defun mcp-validate-initialize (value)
  (unless (and (mcp-object-p value)
               (stringp (mcp-get value "protocolVersion"))
               (mcp-object-p (mcp-get value "capabilities"))
               (mcp-object-p (mcp-get value "serverInfo"))
               (stringp (mcp-get (mcp-get value "serverInfo") "name"))
               (stringp (mcp-get (mcp-get value "serverInfo") "version"))
               (or (not (nth-value 1 (mcp-get value "instructions")))
                   (stringp (mcp-get value "instructions"))))
    (mcp-invalid "Invalid MCP initialize result"))
  value)

(defun mcp-client-connect (client transport)
  (unless (string= (mcp-client-state client) "idle")
    (error "Cannot connect MCP client in ~A state" (mcp-client-state client)))
  (setf (mcp-client-state client) "connecting"
        (mcp-client-transport client) transport
        (mcp-client-disposers client)
        (list
         (mcp-transport-on-message
          transport (lambda (message) (mcp-handle-message client message)))
         (mcp-transport-on-error
          transport (lambda (error) (mcp-client-emit-error client error)))
         (mcp-transport-on-close
          transport
          (lambda ()
            (mcp-mark-closed client
                             (make-condition 'mcp-connection-closed-error))))))
  (handler-case
      (progn
        (mcp-transport-start transport)
        (let* ((capabilities
                 (if (mcp-object-p (mcp-client-capabilities client))
                     (list* :json-object
                            (copy-list (cdr (mcp-client-capabilities client))))
                     (mcp-obj)))
               (info (mcp-obj "name" (mcp-client-name client)
                              "version" (mcp-client-version client))))
          (when (and (mcp-client-roots client)
                     (not (nth-value 1 (mcp-get capabilities "roots"))))
            (setf capabilities (mcp-put capabilities "roots" (mcp-obj))))
          (when (mcp-client-title client)
            (setf info (mcp-put info "title" (mcp-client-title client))))
          (let ((result
                  (mcp-validate-initialize
                   (mcp-request-internal
                    client "initialize"
                    (mcp-obj "protocolVersion"
                             (or (mcp-client-protocol-version-request client)
                                 +mcp-latest-protocol-version+)
                             "capabilities" capabilities
                             "clientInfo" info)
                    :allow-connecting t))))
            (unless (member (mcp-get result "protocolVersion")
                            +mcp-supported-protocol-versions+
                            :test #'string=)
              (error "MCP server selected unsupported protocol version ~A"
                     (mcp-get result "protocolVersion")))
            (setf (mcp-client-protocol-version client)
                  (mcp-get result "protocolVersion")
                  (mcp-client-server-info client)
                  (mcp-get result "serverInfo")
                  (mcp-client-server-capabilities client)
                  (mcp-get result "capabilities")
                  (mcp-client-instructions client)
                  (mcp-get result "instructions"))
            (mcp-transport-set-protocol-version
             transport (mcp-get result "protocolVersion"))
            (mcp-notify-internal client "notifications/initialized" nil
                                 :allow-connecting t)
            (setf (mcp-client-state client) "connected")
            result)))
    (error (condition)
      (ignore-errors (mcp-client-close client))
      (error condition))))

(defun mcp-handle-response (client message)
  (let ((id (mcp-get message "id"))
        (entry nil))
    (sb-thread:with-mutex ((mcp-client-lock client))
      (setf entry (gethash id (mcp-client-pending client)))
      (when entry
        (mcp-remove-pending client id entry)))
    (unless entry
      (mcp-client-emit-error
       client
       (make-condition 'simple-error
                       :format-control "Received response for unknown MCP request ~A"
                       :format-arguments (list id)))
      (return-from mcp-handle-response nil))
    (if (nth-value 1 (mcp-get message "error"))
        (let ((object (mcp-get message "error")))
          (multiple-value-bind (data present) (mcp-get object "data")
            (mcp-box-put
             (mcp-pending-box entry)
             (cons :error
                   (make-condition 'mcp-error
                                   :code (mcp-get object "code")
                                   :message (mcp-get object "message")
                                   :data data
                                   :data-p present)))))
        (mcp-box-put (mcp-pending-box entry)
                     (cons :ok (mcp-get message "result"))))))

(defun mcp-send-result (client id result)
  (handler-case
      (let ((transport (mcp-client-transport client)))
        (when transport
          (mcp-transport-send
           transport
           (mcp-obj "jsonrpc" "2.0" "id" id "result" (or result (mcp-obj))))))
    (error (send-error)
      (mcp-client-emit-error client send-error))))

(defun mcp-send-failure (client id condition)
  (handler-case
      (let ((transport (mcp-client-transport client))
            (object
              (if (typep condition 'mcp-error)
                  (let ((object (mcp-obj "code" (mcp-error-code condition)
                                         "message" (mcp-error-message condition))))
                    (when (mcp-error-data-p condition)
                      (setf object
                            (mcp-put object "data" (mcp-error-data condition))))
                    object)
                  (mcp-obj "code" +mcp-internal-error+
                           "message" (princ-to-string condition)))))
        (when transport
          (mcp-transport-send
           transport
           (mcp-obj "jsonrpc" "2.0" "id" id "error" object))))
    (error (send-error)
      (mcp-client-emit-error client send-error))))

(defun mcp-handle-request (client message)
  (let ((id (mcp-get message "id"))
        (method (mcp-get message "method"))
        (handler nil))
    (sb-thread:with-mutex ((mcp-client-lock client))
      (setf handler (gethash method (mcp-client-handlers client))))
    (unless handler
      (mcp-send-failure
       client id
       (make-condition 'mcp-error
                       :code +mcp-method-not-found+
                       :message (format nil "Method not found: ~A" method)))
      (return-from mcp-handle-request nil))
    (let ((abort (make-mcp-abort)))
      (sb-thread:with-mutex ((mcp-client-lock client))
        (setf (gethash id (mcp-client-incoming client)) abort))
      (unwind-protect
           (handler-case
               (mcp-send-result
                client id
                (funcall handler (mcp-get message "params") abort))
             (mcp-error (condition)
               (mcp-send-failure client id condition))
             (error (condition)
               (mcp-send-failure client id condition)))
        (sb-thread:with-mutex ((mcp-client-lock client))
          (remhash id (mcp-client-incoming client)))))))

(defun mcp-handle-progress (client params)
  (unless (and (mcp-object-p params)
               (mcp-jsonrpc-id-p (mcp-get params "progressToken"))
               (numberp (mcp-get params "progress")))
    (return-from mcp-handle-progress nil))
  (let ((token (mcp-get params "progressToken"))
        (entry nil)
        (id nil))
    (sb-thread:with-mutex ((mcp-client-lock client))
      (setf id (gethash token (mcp-client-progress client))
            entry (and id (gethash id (mcp-client-pending client))))
      (when entry
        (mcp-arm-timeout client id entry)))
    (when entry
      (handler-case
          (when (mcp-pending-on-progress entry)
            (funcall (mcp-pending-on-progress entry) params))
        (error (condition)
          (mcp-client-emit-error client condition))))))

(defun mcp-handle-cancelled (client params)
  (when (and (mcp-object-p params)
             (mcp-jsonrpc-id-p (mcp-get params "requestId")))
    (let ((abort nil))
      (sb-thread:with-mutex ((mcp-client-lock client))
        (setf abort (gethash (mcp-get params "requestId")
                              (mcp-client-incoming client))))
      (when abort
        (mcp-abort abort (mcp-get params "reason"))))))

(defun mcp-dispatch-notification (client method params)
  (let ((listeners nil))
    (sb-thread:with-mutex ((mcp-client-lock client))
      (setf listeners
            (copy-list (gethash method (mcp-client-notifications client)))))
    (dolist (listener listeners)
      (handler-case (funcall listener params)
        (error (condition)
          (mcp-client-emit-error client condition))))))

(defun mcp-handle-message (client message)
  (cond
    ((mcp-jsonrpc-response-p message)
     (mcp-handle-response client message))
    ((mcp-jsonrpc-request-p message)
     (mcp-handle-request client message))
    ((mcp-jsonrpc-notification-p message)
     (let ((method (mcp-get message "method")))
       (cond
         ((string= method "notifications/progress")
          (mcp-handle-progress client (mcp-get message "params")))
         ((string= method "notifications/cancelled")
          (mcp-handle-cancelled client (mcp-get message "params"))))
       (mcp-dispatch-notification client method (mcp-get message "params"))))
    (t
     (mcp-client-emit-error
      client
      (make-condition 'mcp-error
                      :code +mcp-invalid-request+
                      :message "Received invalid JSON-RPC message")))))

(defun mcp-validate-list-page (method key value predicate)
  (let ((items (and (mcp-object-p value) (mcp-get value key))))
    (unless (and (mcp-object-p value) (mcp-json-sequence-p items))
      (mcp-invalid (format nil "Invalid MCP ~A result" method)))
    (loop for item across (coerce items 'vector)
          do (unless (and (mcp-object-p item) (funcall predicate item))
               (mcp-invalid (format nil "Invalid entry in MCP ~A result" method))))
    (multiple-value-bind (cursor present) (mcp-get value "nextCursor")
      (when (or (not present)
                (eq cursor 'null)
                (and (stringp cursor) (zerop (length cursor))))
        (return-from mcp-validate-list-page
          (list :items (coerce items 'list) :next nil)))
      (unless (stringp cursor)
        (mcp-invalid (format nil "Invalid MCP ~A cursor" method)))
      (list :items (coerce items 'list) :next cursor))))

(defun mcp-tool-p (tool)
  (and (stringp (mcp-get tool "name"))
       (mcp-object-p (mcp-get tool "inputSchema"))))

(defun mcp-list-page (client method key predicate cursor &key abort timeout-ms on-progress)
  (mcp-validate-list-page
   method key
   (mcp-client-request
    client method
    (when cursor (mcp-obj "cursor" cursor))
    :abort abort :timeout-ms timeout-ms :on-progress on-progress)
   predicate))

(defun mcp-list-all (client method key predicate &key abort timeout-ms on-progress)
  (let ((items nil)
        (seen nil)
        (cursor nil))
    (loop for page-number from 0 below +mcp-max-list-pages+
          for page = (mcp-list-page client method key predicate cursor
                                    :abort abort
                                    :timeout-ms timeout-ms
                                    :on-progress on-progress)
          do (setf items (append items (getf page :items)))
             (let ((next (getf page :next)))
               (unless next
                 (return-from mcp-list-all items))
               (when (member next seen :test #'string=)
                 (error "MCP ~A returned duplicate cursor: ~A" method next))
               (push next seen)
               (setf cursor next)))
    (error "MCP ~A exceeded ~A pages" method +mcp-max-list-pages+)))

(defun mcp-list-tools (client &key abort timeout-ms on-progress)
  (mcp-list-all client "tools/list" "tools" #'mcp-tool-p
                :abort abort :timeout-ms timeout-ms :on-progress on-progress))

(defun mcp-validate-tool-result (value)
  (unless (mcp-object-p value)
    (mcp-invalid "Invalid MCP tools/call result"))
  (multiple-value-bind (content present) (mcp-get value "content")
    (when (and present (not (mcp-json-sequence-p content)))
      (mcp-invalid "Invalid MCP tools/call result"))
    (if present
        value
        (mcp-put value "content" #()))))

(defun mcp-call-tool (client name &optional arguments
                      &key abort timeout-ms on-progress)
  (mcp-validate-tool-result
   (mcp-client-request
    client "tools/call"
    (if arguments
        (mcp-obj "name" name "arguments" arguments)
        (mcp-obj "name" name))
    :abort abort
    :timeout-ms timeout-ms
    :on-progress on-progress)))

(defstruct (mcp-memory-transport (:constructor %make-mcp-memory-transport))
  peer
  (started-p nil :type boolean)
  (closed-p nil :type boolean)
  (close-emitted-p nil :type boolean)
  (message-listeners nil :type list)
  (error-listeners nil :type list)
  (close-listeners nil :type list)
  (queue nil :type list)
  (worker nil)
  (queue-lock (sb-thread:make-mutex :name "mcp memory queue"))
  (queue-wait (sb-thread:make-waitqueue :name "mcp memory queue"))
  (lock (sb-thread:make-mutex :name "mcp memory")))

(defun make-mcp-memory-pair ()
  (let ((left (%make-mcp-memory-transport))
        (right (%make-mcp-memory-transport)))
    (setf (mcp-memory-transport-peer left) right
          (mcp-memory-transport-peer right) left)
    (values left right)))

(defun mcp-memory-pump (transport)
  (loop
    (let ((message
            (sb-thread:with-mutex ((mcp-memory-transport-queue-lock transport))
              (loop while (null (mcp-memory-transport-queue transport))
                    do (sb-thread:condition-wait
                        (mcp-memory-transport-queue-wait transport)
                        (mcp-memory-transport-queue-lock transport)))
              (pop (mcp-memory-transport-queue transport)))))
      (when (eq message :stop)
        (return))
      (unless (mcp-memory-transport-closed-p transport)
        (mcp-memory-emit transport 'message-listeners message)))))

(defun mcp-memory-enqueue (transport message)
  (sb-thread:with-mutex ((mcp-memory-transport-queue-lock transport))
    (setf (mcp-memory-transport-queue transport)
          (nconc (mcp-memory-transport-queue transport) (list message)))
    (unless (mcp-memory-transport-worker transport)
      (setf (mcp-memory-transport-worker transport)
            (sb-thread:make-thread
             (lambda () (mcp-memory-pump transport))
             :name "mcp memory deliver")))
    (sb-thread:condition-notify (mcp-memory-transport-queue-wait transport)))
  nil)

(defun mcp-memory-emit (transport slot value)
  (let ((listeners nil))
    (sb-thread:with-mutex ((mcp-memory-transport-lock transport))
      (setf listeners (copy-list (slot-value transport slot))))
    (dolist (listener listeners)
      (funcall listener value))))

(defmethod mcp-transport-on-message ((transport mcp-memory-transport) listener)
  (sb-thread:with-mutex ((mcp-memory-transport-lock transport))
    (push listener (mcp-memory-transport-message-listeners transport)))
  (lambda ()
    (sb-thread:with-mutex ((mcp-memory-transport-lock transport))
      (setf (mcp-memory-transport-message-listeners transport)
            (remove listener
                    (mcp-memory-transport-message-listeners transport))))))

(defmethod mcp-transport-on-error ((transport mcp-memory-transport) listener)
  (sb-thread:with-mutex ((mcp-memory-transport-lock transport))
    (push listener (mcp-memory-transport-error-listeners transport)))
  (lambda ()
    (sb-thread:with-mutex ((mcp-memory-transport-lock transport))
      (setf (mcp-memory-transport-error-listeners transport)
            (remove listener
                    (mcp-memory-transport-error-listeners transport))))))

(defmethod mcp-transport-on-close ((transport mcp-memory-transport) listener)
  (sb-thread:with-mutex ((mcp-memory-transport-lock transport))
    (push listener (mcp-memory-transport-close-listeners transport)))
  (lambda ()
    (sb-thread:with-mutex ((mcp-memory-transport-lock transport))
      (setf (mcp-memory-transport-close-listeners transport)
            (remove listener
                    (mcp-memory-transport-close-listeners transport))))))

(defun mcp-memory-emit-close (transport)
  (let ((emit nil))
    (sb-thread:with-mutex ((mcp-memory-transport-lock transport))
      (unless (mcp-memory-transport-close-emitted-p transport)
        (setf (mcp-memory-transport-close-emitted-p transport) t
              emit t)))
    (when emit
      (let ((listeners nil))
        (sb-thread:with-mutex ((mcp-memory-transport-lock transport))
          (setf listeners
                (copy-list (mcp-memory-transport-close-listeners transport))))
        (dolist (listener listeners)
          (funcall listener))))))

(defmethod mcp-transport-start ((transport mcp-memory-transport))
  (when (mcp-memory-transport-closed-p transport)
    (error 'mcp-connection-closed-error))
  (setf (mcp-memory-transport-started-p transport) t)
  nil)

(defmethod mcp-transport-send ((transport mcp-memory-transport) message &key abort)
  (declare (ignore abort))
  (when (or (not (mcp-memory-transport-started-p transport))
            (mcp-memory-transport-closed-p transport))
    (error 'mcp-connection-closed-error))
  (let ((peer (mcp-memory-transport-peer transport)))
    (unless (and peer
                 (mcp-memory-transport-started-p peer)
                 (not (mcp-memory-transport-closed-p peer)))
      (error 'mcp-connection-closed-error
             :message "In-memory MCP peer is not connected"))
    ;; One FIFO worker per peer, same order as queueMicrotask, and the
    ;; sender returns before the peer runs.
    (mcp-memory-enqueue peer (mcp-copy-json message)))
  nil)

(defmethod mcp-transport-close ((transport mcp-memory-transport))
  (unless (mcp-memory-transport-closed-p transport)
    (setf (mcp-memory-transport-closed-p transport) t)
    (mcp-memory-enqueue transport :stop)
    (mcp-memory-emit-close transport)
    (let ((peer (mcp-memory-transport-peer transport)))
      (when peer
        (mcp-transport-close peer))))
  nil)

(defun mcp-memory-emit-error (transport error)
  (mcp-memory-emit
   transport
   'error-listeners
   (if (typep error 'error)
       error
       (make-condition 'simple-error
                       :format-control "~A"
                       :format-arguments (list error)))))
