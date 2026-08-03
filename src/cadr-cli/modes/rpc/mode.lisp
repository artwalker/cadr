(in-package #:cadr-cli)

(defun rpc-handle-line (state line)
  (handler-case
      (let ((object
              (cadr-ai::parse-json line)))
        (require-rpc-object object)
        (if
            (string=
             (or
              (cadr-ai::json-get object "type")
              "")
             "extension_ui_response")
            (rpc-handle-ui-response
             state object)
            (handler-case
                (let ((response
                        (rpc-handle-command
                         state object)))
                  (unless
                      (eq response
                          +rpc-async-response+)
                    (rpc-write-object
                     state response)))
              (error (condition)
                (rpc-write-object
                 state
                 (rpc-failure
                  (rpc-command-id object)
                  (or
                   (cadr-ai::json-get
                    object "type")
                   "unknown")
                  condition))))))
    (error (condition)
      (rpc-write-object
       state
       (rpc-failure
        nil "parse"
        (format nil
                "Failed to parse command: ~A"
                condition))))))

(defun rpc-shutdown (state)
  (rpc-close-pending-dialogs state)
  (rpc-cancel-bash state)
  (cadr-agent:agent-abort
   (rpc-state-agent state))
  (let ((host
          (cadr-agent::agent-extension-host
           (rpc-state-agent state))))
    (when host
      (cadr-agent::run-extension-lifecycle-hooks
       host :session-shutdown
       :payload '(:reason :quit))))
  0)

(defun run-rpc-mode
    (agent extension-manager
     &key
       (input *standard-input*)
       (output *standard-output*)
       (error-output *error-output*))
  (let ((state
          (%make-rpc-state
           :agent agent
           :extension-manager extension-manager
           :input input
           :output output
           :error-output error-output)))
    (setf
     (cadr-agent::extension-host-ui-function
      (cli-extension-manager-host
       extension-manager))
     (rpc-extension-ui-callback state))
    (let ((previous
            (cadr-agent::agent-on-event agent)))
      (unwind-protect
           (progn
             (setf
              (cadr-agent::agent-on-event agent)
              (lambda (event)
                (when previous
                  (funcall previous event))
                (rpc-write-object
                 state
                 (agent-event-to-json event))))
             (read-rpc-jsonl-lines
              input
              (lambda (line)
                (rpc-handle-line state line))))
        (setf
         (cadr-agent::agent-on-event agent)
         previous)
        (rpc-shutdown state)))))
