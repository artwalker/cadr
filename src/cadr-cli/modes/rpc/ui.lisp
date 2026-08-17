(in-package #:cadr-cli)

(defstruct (rpc-pending-dialog
            (:constructor make-rpc-pending-dialog
                (&key method)))
  method
  response
  (done-p nil :type boolean)
  (lock
    (sb-thread:make-mutex
     :name "cadr-rpc-dialog"))
  (condition
    (sb-thread:make-waitqueue
     :name "cadr-rpc-dialog-result")))

(defun rpc-dialog-default (method)
  (case method
    (:confirm nil)
    (otherwise nil)))

(defun rpc-dialog-result (method response)
  (if (or (null response)
          (eq t
              (cadr-ai::json-get
               response "cancelled")))
      (rpc-dialog-default method)
      (case method
        (:confirm
         (eq t
             (cadr-ai::json-get
              response "confirmed")))
        ((:select :input :editor)
         (let ((value
                 (cadr-ai::json-get
                  response "value")))
           (and (stringp value) value)))
        (otherwise nil))))

(defun rpc-dialog-expired-p (deadline)
  (and deadline
       (>= (get-internal-real-time)
           deadline)))

(defun rpc-dialog-deadline (timeout-ms)
  (and timeout-ms
       (+ (get-internal-real-time)
          (ceiling
           (* timeout-ms
              internal-time-units-per-second)
           1000))))

(defun rpc-wait-for-dialog
    (state id pending signal timeout-ms)
  (let ((deadline
          (rpc-dialog-deadline timeout-ms)))
    (sb-thread:with-mutex
        ((rpc-pending-dialog-lock pending))
      (loop
        until
        (or
         (rpc-pending-dialog-done-p pending)
         (rpc-state-closing-p state)
         (and signal
              (cadr-agent:extension-cancellation-aborted-p
               signal))
         (rpc-dialog-expired-p deadline))
        do
        (sb-thread:condition-wait
         (rpc-pending-dialog-condition pending)
         (rpc-pending-dialog-lock pending)
         :timeout 0.05)))
    (sb-thread:with-mutex
        ((rpc-state-pending-lock state))
      (remhash id (rpc-state-pending state)))
    (rpc-dialog-result
     (rpc-pending-dialog-method pending)
     (rpc-pending-dialog-response pending))))

(defun rpc-dialog-request
    (state method request
     &key signal timeout-ms)
  (when
      (or
       (rpc-state-closing-p state)
       (and signal
            (cadr-agent:extension-cancellation-aborted-p
             signal)))
    (return-from rpc-dialog-request
      (rpc-dialog-default method)))
  (let* ((id (rpc-next-id state))
         (pending
           (make-rpc-pending-dialog :method method)))
    (cadr-ai::json-put request "id" id)
    (sb-thread:with-mutex
        ((rpc-state-pending-lock state))
      (setf
       (gethash id (rpc-state-pending state))
       pending))
    (rpc-write-object state request)
    (rpc-wait-for-dialog
     state id pending signal timeout-ms)))

(defun rpc-fire-and-forget
    (state method &rest fields)
  (let ((request
          (apply
           #'cadr-ai::json-object
           "type" "extension_ui_request"
           "id" (rpc-next-id state)
           "method" method
           fields)))
    (rpc-write-object state request))
  nil)

(defun rpc-extension-ui-callback (state)
  (lambda (method arguments)
    (case method
      (:select
       (let ((request
               (cadr-ai::json-object
                "type" "extension_ui_request"
                "method" "select"
                "title" (getf arguments :title)
                "options"
                (coerce
                 (getf arguments :options)
                 'vector))))
         (when (getf arguments :timeout-ms)
           (cadr-ai::json-put
            request "timeout"
            (getf arguments :timeout-ms)))
         (rpc-dialog-request
          state :select request
          :signal (getf arguments :signal)
          :timeout-ms
          (getf arguments :timeout-ms))))
      (:confirm
       (let ((request
               (cadr-ai::json-object
                "type" "extension_ui_request"
                "method" "confirm"
                "title" (getf arguments :title)
                "message" (getf arguments :message))))
         (when (getf arguments :timeout-ms)
           (cadr-ai::json-put
            request "timeout"
            (getf arguments :timeout-ms)))
         (rpc-dialog-request
          state :confirm request
          :signal (getf arguments :signal)
          :timeout-ms
          (getf arguments :timeout-ms))))
      (:input
       (let ((request
               (cadr-ai::json-object
                "type" "extension_ui_request"
                "method" "input"
                "title" (getf arguments :title))))
         (when (getf arguments :placeholder)
           (cadr-ai::json-put
            request "placeholder"
            (getf arguments :placeholder)))
         (when (getf arguments :timeout-ms)
           (cadr-ai::json-put
            request "timeout"
            (getf arguments :timeout-ms)))
         (rpc-dialog-request
          state :input request
          :signal (getf arguments :signal)
          :timeout-ms
          (getf arguments :timeout-ms))))
      (:editor
       (let ((request
               (cadr-ai::json-object
                "type" "extension_ui_request"
                "method" "editor"
                "title" (getf arguments :title))))
         (when (getf arguments :prefill)
           (cadr-ai::json-put
            request "prefill"
            (getf arguments :prefill)))
         (rpc-dialog-request
          state :editor request)))
      (:notify
       (let ((fields
               (list
                "message" (getf arguments :message))))
         (when (getf arguments :level)
           (setf fields
                 (nconc
                  fields
                  (list
                   "notifyType"
                   (rpc-symbol-name
                    (getf arguments :level))))))
         (apply
          #'rpc-fire-and-forget
          state "notify" fields)))
      (:set-status
       (let ((fields
               (list
                "statusKey"
                (getf arguments :key))))
         (when (getf arguments :text)
           (setf
            fields
            (nconc
             fields
             (list
              "statusText"
              (getf arguments :text)))))
         (apply
          #'rpc-fire-and-forget
          state "setStatus" fields)))
      (:set-widget
       (let ((fields
               (list
                "widgetKey"
                (getf arguments :key))))
         (when (getf arguments :lines)
           (setf
            fields
            (nconc
             fields
             (list
              "widgetLines"
              (coerce
               (getf arguments :lines)
               'vector)))))
         (when (getf arguments :placement)
           (setf
            fields
            (nconc
             fields
             (list
              "widgetPlacement"
              (case
                  (getf arguments :placement)
                (:below-editor "belowEditor")
                (otherwise "aboveEditor"))))))
         (apply
          #'rpc-fire-and-forget
          state "setWidget" fields)))
      (:set-title
       (rpc-fire-and-forget
        state "setTitle"
        "title" (getf arguments :title)))
      (:set-editor-text
       (rpc-fire-and-forget
        state "set_editor_text"
        "text" (getf arguments :text)))
      (otherwise nil))))

(defun rpc-handle-ui-response (state object)
  (let* ((id (require-rpc-string object "id"))
         (pending
           (sb-thread:with-mutex
               ((rpc-state-pending-lock state))
             (gethash
              id (rpc-state-pending state)))))
    (unless pending
      (rpc-write-object
       state
       (rpc-failure
        id "extension_ui_response"
        (format nil
                "Unknown extension UI request id: ~A"
                id)))
      (return-from rpc-handle-ui-response nil))
    (sb-thread:with-mutex
        ((rpc-pending-dialog-lock pending))
      (unless (rpc-pending-dialog-done-p pending)
        (setf
         (rpc-pending-dialog-response pending)
         object
         (rpc-pending-dialog-done-p pending)
         t)
        (sb-thread:condition-broadcast
         (rpc-pending-dialog-condition pending))))
    t))

(defun rpc-close-pending-dialogs (state)
  (setf (rpc-state-closing-p state) t)
  (let ((pending nil))
    (sb-thread:with-mutex
        ((rpc-state-pending-lock state))
      (maphash
       (lambda (id dialog)
         (declare (ignore id))
         (push dialog pending))
       (rpc-state-pending state))
      (clrhash (rpc-state-pending state)))
    (dolist (dialog pending)
      (sb-thread:with-mutex
          ((rpc-pending-dialog-lock dialog))
        (setf
         (rpc-pending-dialog-done-p dialog)
         t)
        (sb-thread:condition-broadcast
         (rpc-pending-dialog-condition dialog)))))
  nil)
