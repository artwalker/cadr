(in-package #:cadr-cli)

(defun json-event-type-name (type)
  (string-downcase
   (substitute #\_ #\-
               (symbol-name type))))

(defun stream-event-to-json (event)
  (let ((object
          (cadr-ai::json-object
           "type"
           (json-event-type-name
            (cadr-ai:stream-event-type event))
           "message"
           (cadr-agent::message-to-json
            (cadr-ai:stream-event-message event)))))
    (when (cadr-ai:stream-event-delta event)
      (cadr-ai::json-put
       object "delta"
       (cadr-ai:stream-event-delta event)))
    (when (cadr-ai:stream-event-reason event)
      (cadr-ai::json-put
       object "reason"
       (json-event-type-name
        (cadr-ai:stream-event-reason event))))
    object))

(defun tool-result-to-json (result)
  (cadr-agent::message-to-json result))

(defun agent-event-to-json (event)
  (let* ((type
           (cadr-agent:agent-event-type event))
         (object
           (cadr-ai::json-object
            "type" (json-event-type-name type))))
    (case type
      (:agent-end
       (cadr-ai::json-put
        object "messages"
        (coerce
         (mapcar
          #'cadr-agent::message-to-json
          (cadr-agent:agent-event-messages event))
         'vector))
       (cadr-ai::json-put
        object "willRetry"
        (cadr-agent:agent-event-will-retry
         event)))
      (:auto-retry-start
       (cadr-ai::json-put
        object "attempt"
        (cadr-agent:agent-event-attempt event))
       (cadr-ai::json-put
        object "maxAttempts"
        (cadr-agent:agent-event-max-attempts
         event))
       (cadr-ai::json-put
        object "delayMs"
        (cadr-agent:agent-event-delay-ms event))
       (cadr-ai::json-put
        object "errorMessage"
        (cadr-agent:agent-event-error-message
         event)))
      (:auto-retry-end
       (cadr-ai::json-put
        object "success"
        (cadr-agent:agent-event-success event))
       (cadr-ai::json-put
        object "attempt"
        (cadr-agent:agent-event-attempt event))
       (when
           (cadr-agent:agent-event-final-error
            event)
         (cadr-ai::json-put
          object "finalError"
          (cadr-agent:agent-event-final-error
           event))))
      ((:message-start :message-end)
       (cadr-ai::json-put
        object "message"
        (cadr-agent::message-to-json
         (cadr-agent:agent-event-message event))))
      (:message-update
       (cadr-ai::json-put
        object "message"
        (cadr-agent::message-to-json
         (cadr-agent:agent-event-message event)))
       (cadr-ai::json-put
        object "assistantMessageEvent"
        (stream-event-to-json
         (cadr-agent:agent-event-stream-event
          event))))
      (:turn-end
       (cadr-ai::json-put
        object "message"
        (cadr-agent::message-to-json
         (cadr-agent:agent-event-message event)))
       (cadr-ai::json-put
        object "toolResults"
        (coerce
         (mapcar
          #'tool-result-to-json
          (cadr-agent:agent-event-tool-results
           event))
         'vector)))
      (:tool-execution-start
       (let ((call
               (cadr-agent:agent-event-tool-call
                event)))
         (cadr-ai::json-put
          object "toolCallId"
          (cadr-ai:tool-call-id call))
         (cadr-ai::json-put
          object "toolName"
          (cadr-ai:tool-call-name call))
         (cadr-ai::json-put
          object "args"
          (cadr-ai:tool-call-arguments call))))
      (:tool-execution-end
       (let ((call
               (cadr-agent:agent-event-tool-call
                event))
             (result
               (cadr-agent:agent-event-tool-result
                event)))
         (cadr-ai::json-put
          object "toolCallId"
          (cadr-ai:tool-call-id call))
         (cadr-ai::json-put
          object "toolName"
          (cadr-ai:tool-call-name call))
         (cadr-ai::json-put
          object "result"
          (tool-result-to-json result))
         (cadr-ai::json-put
          object "isError"
          (cadr-ai:tool-result-message-is-error
           result))))
      (:queue-update
       (cadr-ai::json-put
        object "steering"
        (coerce
         (mapcar
          #'cadr-agent::message-to-json
          (cadr-agent:agent-event-steering event))
         'vector))
       (cadr-ai::json-put
        object "followUp"
        (coerce
         (mapcar
          #'cadr-agent::message-to-json
          (cadr-agent:agent-event-follow-up event))
         'vector))
       (cadr-ai::json-put
        object "nextTurn"
        (coerce
         (mapcar
          #'cadr-agent::message-to-json
          (cadr-agent:agent-event-next-turn event))
         'vector))))
    object))

(defun write-json-line (object output)
  (write-string
   (cadr-ai::stringify-json object)
   output)
  (terpri output)
  (finish-output output))

(defun make-json-event-renderer (output)
  (lambda (event)
    (unless
        (member
         (cadr-agent:agent-event-type event)
         '(:compaction-start
           :compaction-end
           :compaction-error))
      (write-json-line
       (agent-event-to-json event)
       output))))

(defun assistant-text-content (message)
  (loop
    for block in
    (cadr-ai:assistant-message-content message)
    when (typep block 'cadr-ai:text-content)
      collect (cadr-ai:text-content-text block)))

(defun run-print-mode
    (agent initial-message messages
     &key
       (mode :text)
       (output *standard-output*)
       (error-output *error-output*))
  (let ((original-consumer
          (cadr-agent::agent-on-event agent)))
    (unwind-protect
         (handler-case
             (progn
               (when (eq mode :json)
                 (setf
                  (cadr-agent::agent-on-event agent)
                  (make-json-event-renderer output)))
               (when initial-message
                 (cadr-agent:agent-prompt
                  agent initial-message
                  :source :interactive))
               (dolist (message messages)
                 (cadr-agent:agent-prompt
                  agent message
                  :source :interactive))
               (if (eq mode :json)
                   0
                   (let ((last
                           (car
                            (last
                             (cadr-agent:agent-messages
                              agent)))))
                     (if
                         (and
                          (typep
                           last
                           'cadr-ai:assistant-message)
                          (member
                           (cadr-ai:assistant-message-stop-reason
                            last)
                           '(:error :aborted)))
                         (progn
                           (format
                            error-output "~A~%"
                            (or
                             (cadr-ai:assistant-message-error-message
                              last)
                             (format
                              nil "Request ~(~A~)"
                              (cadr-ai:assistant-message-stop-reason
                               last))))
                           (finish-output error-output)
                           1)
                         (progn
                           (when
                               (typep
                                last
                                'cadr-ai:assistant-message)
                             (dolist
                                 (text
                                  (assistant-text-content
                                   last))
                               (format output "~A~%" text)))
                           (finish-output output)
                           0)))))
           (error (condition)
             (format error-output "~A~%" condition)
             (finish-output error-output)
             1))
      (setf
       (cadr-agent::agent-on-event agent)
       original-consumer)
      (when (cadr-agent::agent-extension-host agent)
        (cadr-agent::run-extension-lifecycle-hooks
         (cadr-agent::agent-extension-host agent)
         :session-shutdown
         :payload '(:reason :quit))))))
