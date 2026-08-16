(in-package #:cadr-cli)

(defun json-event-type-name (type)
  (case type
    (:tool-call-start "toolcall_start")
    (:tool-call-delta "toolcall_delta")
    (:tool-call-end "toolcall_end")
    (otherwise
     (string-downcase
      (substitute #\_ #\-
                  (symbol-name type))))))

(defun wire-stop-reason-name (reason)
  (case reason
    (:tool-use "toolUse")
    (otherwise (json-event-type-name reason))))

(defun wire-usage-to-json (usage)
  (let* ((cost (cadr-ai:usage-cost usage))
         (object
           (cadr-ai::json-object
            "input" (cadr-ai:usage-input usage)
            "output" (cadr-ai:usage-output usage)
            "cacheRead" (cadr-ai:usage-cache-read usage)
            "cacheWrite" (cadr-ai:usage-cache-write usage)
            "totalTokens" (cadr-ai:usage-total usage)
            "cost"
            (cadr-ai::json-object
             "input" (cadr-ai:cost-input cost)
             "output" (cadr-ai:cost-output cost)
             "cacheRead" (cadr-ai:cost-cache-read cost)
             "cacheWrite" (cadr-ai:cost-cache-write cost)
             "total" (cadr-ai:cost-total cost)))))
    (unless (null (cadr-ai:usage-cache-write-1h usage))
      (cadr-ai::json-put
       object "cacheWrite1h"
       (cadr-ai:usage-cache-write-1h usage)))
    (unless (null (cadr-ai:usage-reasoning usage))
      (cadr-ai::json-put
       object "reasoning"
       (cadr-ai:usage-reasoning usage)))
    object))

(defun wire-content-block-to-json (block)
  (cond
    ((typep block 'cadr-ai:text-content)
     (let ((object
             (cadr-ai::json-object
              "type" "text"
              "text" (cadr-ai:text-content-text block))))
       (when (cadr-ai:text-content-signature block)
         (cadr-ai::json-put
          object "textSignature"
          (cadr-ai:text-content-signature block)))
       object))
    ((typep block 'cadr-ai:thinking-content)
     (let ((object
             (cadr-ai::json-object
              "type" "thinking"
              "thinking"
              (cadr-ai:thinking-content-thinking block))))
       (when (cadr-ai:thinking-content-signature block)
         (cadr-ai::json-put
          object "thinkingSignature"
          (cadr-ai:thinking-content-signature block)))
       (when (cadr-ai:thinking-content-redacted-p block)
         (cadr-ai::json-put object "redacted" t))
       object))
    ((typep block 'cadr-ai:image-content)
     (cadr-ai::json-object
      "type" "image"
      "data" (cadr-ai:image-content-data block)
      "mimeType" (cadr-ai:image-content-mime-type block)))
    ((typep block 'cadr-ai:tool-call)
     (let ((object
             (cadr-ai::json-object
              "type" "toolCall"
              "id" (cadr-ai:tool-call-id block)
              "name" (cadr-ai:tool-call-name block)
              "arguments"
              (cadr-agent::json-safe-value
               (cadr-ai:tool-call-arguments block)))))
       (when (cadr-ai:tool-call-thought-signature block)
         (cadr-ai::json-put
          object "thoughtSignature"
          (cadr-ai:tool-call-thought-signature block)))
       object))
    (t
     (error "Unsupported wire content block: ~S" block))))

(defun wire-content-blocks-to-json (blocks)
  (map 'vector #'wire-content-block-to-json blocks))

(defun wire-json-value (value)
  (cond
    ((null value) nil)
    ((hash-table-p value)
     (let ((object (cadr-ai::json-object)))
       (maphash
        (lambda (key nested)
          (cadr-ai::json-put
           object
           (if (symbolp key)
               (cadr-agent::symbol-json-name key)
               key)
           (wire-json-value nested)))
        value)
       object))
    ((and (listp value)
          (cadr-agent::strict-keyword-plist-p value))
     (let ((object (cadr-ai::json-object)))
       (loop for (key nested) on value by #'cddr
             do (cadr-ai::json-put
                 object
                 (cadr-agent::symbol-json-name key)
                 (wire-json-value nested)))
       object))
    ((vectorp value)
     (map 'vector #'wire-json-value value))
    ((listp value)
     (map 'vector #'wire-json-value value))
    ((pathnamep value)
     (namestring value))
    ((and (symbolp value)
          (not (member value '(nil t null))))
     (cadr-agent::symbol-json-name value))
    (t value)))

(defun compaction-details-to-json (details)
  (if (and (cadr-agent::strict-keyword-plist-p details)
           (or (member :read-files details)
               (member :modified-files details)))
      (cadr-ai::json-object
       "readFiles"
       (coerce (or (getf details :read-files) nil) 'vector)
       "modifiedFiles"
       (coerce (or (getf details :modified-files) nil) 'vector))
      (wire-json-value details)))

(defun compaction-result-to-json (result)
  (let ((object
          (cadr-ai::json-object
           "summary" (getf result :summary)
           "firstKeptEntryId"
           (getf result :first-kept-entry-id)
           "tokensBefore" (getf result :tokens-before)
           "estimatedTokensAfter"
           (getf result :estimated-tokens-after))))
    (when (getf result :usage)
      (cadr-ai::json-put
       object "usage"
       (wire-usage-to-json (getf result :usage))))
    (when (member :details result)
      (cadr-ai::json-put
       object "details"
       (compaction-details-to-json
        (getf result :details))))
    object))

(defun wire-message-to-json (message)
  (cond
    ((typep message 'cadr-ai:user-message)
     (let ((content (cadr-ai:user-message-content message)))
       (cadr-ai::json-object
        "role" "user"
        "content"
        (if (stringp content)
            (vector
             (cadr-ai::json-object
              "type" "text" "text" content))
            (wire-content-blocks-to-json content))
        "timestamp" (cadr-ai:user-message-timestamp message))))
    ((typep message 'cadr-ai:assistant-message)
     (let ((object
             (cadr-ai::json-object
              "role" "assistant"
              "content"
              (wire-content-blocks-to-json
               (cadr-ai:assistant-message-content message))
              "api"
              (cadr-agent::symbol-json-name
               (cadr-ai:assistant-message-api message))
              "provider"
              (cadr-agent::symbol-json-name
               (cadr-ai:assistant-message-provider message))
              "model" (cadr-ai:assistant-message-model message)
              "usage"
              (wire-usage-to-json
               (cadr-ai:assistant-message-usage message))
              "stopReason"
              (wire-stop-reason-name
               (cadr-ai:assistant-message-stop-reason message))
              "timestamp"
              (cadr-ai:assistant-message-timestamp message))))
       (when (cadr-ai:assistant-message-response-id message)
         (cadr-ai::json-put
          object "responseId"
          (cadr-ai:assistant-message-response-id message)))
       (when (cadr-ai:assistant-message-response-model message)
         (cadr-ai::json-put
          object "responseModel"
          (cadr-ai:assistant-message-response-model message)))
       (when (cadr-ai:assistant-message-error-message message)
         (cadr-ai::json-put
          object "errorMessage"
          (cadr-ai:assistant-message-error-message message)))
       (when (cadr-ai:assistant-message-raw-stop-reason message)
         (cadr-ai::json-put
          object "rawStopReason"
          (cadr-ai:assistant-message-raw-stop-reason message)))
       (when (cadr-ai:assistant-message-diagnostics message)
         (cadr-ai::json-put
          object "diagnostics"
          (map
           'vector
           #'cadr-agent::assistant-diagnostic-to-json
           (cadr-ai:assistant-message-diagnostics message))))
       object))
    ((typep message 'cadr-ai:tool-result-message)
     (let ((object
             (cadr-ai::json-object
              "role" "toolResult"
              "toolCallId"
              (cadr-ai:tool-result-message-tool-call-id message)
              "toolName"
              (cadr-ai:tool-result-message-tool-name message)
              "content"
              (wire-content-blocks-to-json
               (cadr-ai:tool-result-message-content message))
              "details"
              (or
               (cadr-agent::json-safe-value
                (cadr-ai:tool-result-message-details message))
               (cadr-ai::json-object))
              "isError"
              (cadr-ai:tool-result-message-is-error message)
              "timestamp"
              (cadr-ai:tool-result-message-timestamp message))))
       (when (cadr-ai:tool-result-message-added-tool-names message)
         (cadr-ai::json-put
          object "addedToolNames"
          (coerce
           (cadr-ai:tool-result-message-added-tool-names message)
           'vector)))
       object))
    (t
     (error "Unsupported wire message: ~S" message))))

(defun stream-event-to-json (event)
  (let ((object
          (cadr-ai::json-object
           "type"
           (json-event-type-name
            (cadr-ai:stream-event-type event))
           "partial"
           (wire-message-to-json
            (cadr-ai:stream-event-message event)))))
    (unless (null (cadr-ai:stream-event-content-index event))
      (cadr-ai::json-put
       object "contentIndex"
       (cadr-ai:stream-event-content-index event)))
    (unless (null (cadr-ai:stream-event-delta event))
      (cadr-ai::json-put
       object "delta"
       (cadr-ai:stream-event-delta event)))
    (unless (null (cadr-ai:stream-event-content event))
      (cadr-ai::json-put
       object "content"
       (cadr-ai:stream-event-content event)))
    (when (cadr-ai:stream-event-tool-call event)
      (cadr-ai::json-put
       object "toolCall"
       (wire-content-block-to-json
        (cadr-ai:stream-event-tool-call event))))
    object))

(defun tool-result-to-json (result)
  (wire-message-to-json result))

(defun wire-session-header-to-json (session)
  (let ((object
          (cadr-agent::session-header-to-json session)))
    (cadr-ai::json-put
     object "cwd"
     (string-right-trim
      "/"
      (cadr-agent::session-cwd session)))
    object))

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
          #'wire-message-to-json
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
      (:summarization-retry-scheduled
       (cadr-ai::json-put
        object "attempt"
        (cadr-agent:agent-event-attempt event))
       (cadr-ai::json-put
        object "maxAttempts"
        (cadr-agent:agent-event-max-attempts event))
       (cadr-ai::json-put
        object "delayMs"
        (cadr-agent:agent-event-delay-ms event))
       (cadr-ai::json-put
        object "errorMessage"
        (cadr-agent:agent-event-error-message event)))
      (:summarization-retry-attempt-start
       (cadr-ai::json-put
        object "source"
        (json-event-type-name
         (cadr-agent:agent-event-source event)))
       (when (cadr-agent:agent-event-reason event)
         (cadr-ai::json-put
          object "reason"
          (json-event-type-name
           (cadr-agent:agent-event-reason event)))))
      (:compaction-start
       (cadr-ai::json-put
        object "reason"
        (json-event-type-name
         (cadr-agent:agent-event-reason event))))
      (:compaction-end
       (cadr-ai::json-put
        object "reason"
        (json-event-type-name
         (cadr-agent:agent-event-reason event)))
       (when (cadr-agent:agent-event-result event)
         (cadr-ai::json-put
          object "result"
          (compaction-result-to-json
           (cadr-agent:agent-event-result event))))
       (cadr-ai::json-put
        object "aborted"
        (not (null
              (cadr-agent:agent-event-aborted event))))
       (cadr-ai::json-put
        object "willRetry"
        (not (null
              (cadr-agent:agent-event-will-retry event))))
       (when (cadr-agent:agent-event-error-message event)
         (cadr-ai::json-put
          object "errorMessage"
          (cadr-agent:agent-event-error-message event))))
      ((:message-start :message-end)
       (cadr-ai::json-put
        object "message"
        (wire-message-to-json
         (cadr-agent:agent-event-message event))))
      (:message-update
       ;; NOTE (goal 20 v0.84.2 upgrade): the baseline adds a cumulative
       ;; `usage` field to this wire event.  That change is event-diff
       ;; visible, so it lands together with the baselineCommit bump
       ;; (upgrade step 4), not here.
       (cadr-ai::json-put
        object "assistantMessageEvent"
        (let ((stream-object
                (stream-event-to-json
                 (cadr-agent:agent-event-stream-event
                  event))))
          (remhash "partial" stream-object)
          stream-object)))
      (:turn-end
       (cadr-ai::json-put
        object "message"
        (wire-message-to-json
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
          (cadr-ai::json-object
           "content"
           (wire-content-blocks-to-json
            (cadr-ai:tool-result-message-content result))
           "details"
           (or
            (cadr-agent::json-safe-value
             (cadr-ai:tool-result-message-details result))
            (cadr-ai::json-object))))
         (cadr-ai::json-put
          object "isError"
          (cadr-ai:tool-result-message-is-error
           result))))
      (:queue-update
       (let ((steering
               (cadr-agent:agent-event-steering event))
             (follow-up
               (cadr-agent:agent-event-follow-up event)))
         (when (or steering follow-up)
           (cadr-ai::json-put
            object "steering"
            (coerce
             (mapcar
              (lambda (message)
                (cadr-ai::content-text
                 (cadr-ai:user-message-content message)))
              steering)
             'vector))
           (cadr-ai::json-put
            object "followUp"
            (coerce
             (mapcar
              (lambda (message)
                (cadr-ai::content-text
                 (cadr-ai:user-message-content message)))
              follow-up)
             'vector))))
       (when (= 1 (hash-table-count object))
         (return-from agent-event-to-json nil))))
    object))

(defun write-json-line (object output)
  (write-string
   (cadr-ai::stringify-json object)
   output)
  (terpri output)
  (finish-output output))

(defun make-json-event-renderer (output)
  (lambda (event)
    (let ((object (agent-event-to-json event)))
      (when object
        (write-json-line object output)))))

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
                 (when (cadr-agent:agent-session agent)
                   (write-json-line
                    (wire-session-header-to-json
                     (cadr-agent:agent-session agent))
                    output))
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
