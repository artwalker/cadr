(defstruct rpc-extension-ui-client
  process input output error-output
  (statuses (make-hash-table :test #'equal))
  (widgets (make-hash-table :test #'equal))
  (editor-text "")
  (notifications nil)
  (closed-p nil))

(defun rpc-extension-ui-send (client object)
  (write-line
   (cadr-ai::stringify-json object)
   (rpc-extension-ui-client-input client))
  (finish-output (rpc-extension-ui-client-input client))
  object)

(defun rpc-extension-ui-read (client)
  (let ((line (read-line (rpc-extension-ui-client-output client) nil nil)))
    (and line (cadr-ai::parse-json line))))

(defun rpc-extension-ui-response (client id &rest fields)
  (let ((response (cadr-ai::json-object
                   "type" "extension_ui_response" "id" id)))
    (loop for (key value) on fields by #'cddr
          do (cadr-ai::json-put response key value))
    (rpc-extension-ui-send client response)))

(defun rpc-extension-ui-default-responder (method request)
  (declare (ignore request))
  (cond
    ((string= method "confirm") t)
    ((string= method "select") nil)
    ((member method '("input" "editor") :test #'string=) nil)
    (t nil)))

(defun rpc-extension-ui-handle-request (client request responder)
  (let ((id (cadr-ai::json-get request "id"))
        (method (cadr-ai::json-get request "method")))
    (cond
      ((string= method "select")
       (let ((value (funcall responder method request)))
         (if value
             (rpc-extension-ui-response client id "value" value)
             (rpc-extension-ui-response client id "cancelled" t))))
      ((string= method "confirm")
       (rpc-extension-ui-response
        client id "confirmed"
        (not (null (funcall responder method request)))))
      ((member method '("input" "editor") :test #'string=)
       (let ((value (funcall responder method request)))
         (if value
             (rpc-extension-ui-response client id "value" value)
             (rpc-extension-ui-response client id "cancelled" t))))
      ((string= method "notify")
       (push (list :level (cadr-ai::json-get request "notifyType")
                   :message (cadr-ai::json-get request "message"))
             (rpc-extension-ui-client-notifications client)))
      ((string= method "setStatus")
       (let ((key (cadr-ai::json-get request "statusKey"))
             (text (cadr-ai::json-get request "statusText")))
         (if text
             (setf (gethash key (rpc-extension-ui-client-statuses client)) text)
             (remhash key (rpc-extension-ui-client-statuses client)))))
      ((string= method "setWidget")
       (let ((key (cadr-ai::json-get request "widgetKey"))
             (lines (cadr-ai::json-get request "widgetLines")))
         (if lines
             (setf (gethash key (rpc-extension-ui-client-widgets client)) lines)
             (remhash key (rpc-extension-ui-client-widgets client)))))
      ((string= method "set_editor_text")
       (setf (rpc-extension-ui-client-editor-text client)
             (or (cadr-ai::json-get request "text") ""))))
    request))

(defun rpc-extension-ui-text-delta (event)
  (let ((update (cadr-ai::json-get event "assistantMessageEvent")))
    (when (and update
               (string= "text_delta"
                        (or (cadr-ai::json-get update "type") "")))
      (or (cadr-ai::json-get update "delta") ""))))

(defun rpc-extension-ui-prompt
    (client message &key (responder #'rpc-extension-ui-default-responder)
                          on-event)
  (rpc-extension-ui-send
   client (cadr-ai::json-object "type" "prompt" "message" message))
  (with-output-to-string (answer)
    (loop for event = (rpc-extension-ui-read client)
          while event
          for type = (cadr-ai::json-get event "type")
          do
          (when on-event (funcall on-event event))
          (cond
            ((string= type "extension_ui_request")
             (rpc-extension-ui-handle-request client event responder))
            ((string= type "message_update")
             (let ((delta (rpc-extension-ui-text-delta event)))
               (when delta (write-string delta answer))))
            ((string= type "agent_end") (return))
            ((and (string= type "response")
                  (eq :false (cadr-ai::json-get event "success")))
             (error "RPC command failed: ~A"
                    (or (cadr-ai::json-get event "error") "unknown error")))))))

(defun rpc-extension-ui-abort (client)
  (rpc-extension-ui-send client (cadr-ai::json-object "type" "abort")))

(defun run-rpc-extension-ui
    (&key (program "./cadr") extension
          (rpc-demo-extension
            (merge-pathnames
             "examples/extensions/rpc-demo.lisp"
             (asdf:system-source-directory "cadr-cli"))))
  "Start the JSONL RPC UI client.  Use RPC-EXTENSION-UI-PROMPT to chat.
The responder callback handles select/confirm/input/editor extension requests."
  (let ((extension-path (or extension rpc-demo-extension)))
    (unless (probe-file extension-path)
      (error "RPC extension does not exist: ~A" extension-path))
    (let ((process
            (uiop:launch-program
             (list program "--mode" "rpc" "--no-session"
                   "--no-extension" "--extension"
                   (namestring (truename extension-path)))
             :input :stream :output :stream :error-output :stream)))
      (make-rpc-extension-ui-client
       :process process
       :input (uiop:process-info-input process)
       :output (uiop:process-info-output process)
       :error-output (uiop:process-info-error-output process)))))

(defun stop-rpc-extension-ui (client)
  (unless (rpc-extension-ui-client-closed-p client)
    (setf (rpc-extension-ui-client-closed-p client) t)
    (ignore-errors (close (rpc-extension-ui-client-input client)))
    (when (uiop:process-alive-p (rpc-extension-ui-client-process client))
      (uiop:terminate-process (rpc-extension-ui-client-process client))))
  nil)
