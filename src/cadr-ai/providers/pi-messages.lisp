(in-package #:cadr-ai)

(defun pi-message-content (content)
  (if (stringp content)
      content
      (list-json-array
       (loop for block across (coerce content 'vector)
             collect
             (cond
               ((typep block 'text-content)
                (json-object
                 "type" "text"
                 "text" (text-content-text block)))
               ((typep block 'image-content)
                (json-object
                 "type" "image"
                 "mimeType" (image-content-mime-type block)
                 "data" (image-content-data block))))))))

(defun pi-context-json (context)
  (json-object
   "systemPrompt" (context-system-prompt context)
   "messages"
   (list-json-array
    (loop for message in (context-messages context)
          collect
          (cond
            ((typep message 'user-message)
             (json-object
              "role" "user"
              "content"
              (pi-message-content
               (user-message-content message))
              "timestamp"
              (user-message-timestamp message)))
            ((typep message 'assistant-message)
             (json-object
              "role" "assistant"
              "content"
              (list-json-array
               (loop for block in
                     (assistant-message-content message)
                     collect
                     (cond
                       ((typep block 'text-content)
                        (json-object
                         "type" "text"
                         "text" (text-content-text block)))
                       ((typep block 'thinking-content)
                        (json-object
                         "type" "thinking"
                         "thinking"
                         (thinking-content-thinking block)))
                       ((typep block 'tool-call)
                        (json-object
                         "type" "toolCall"
                         "id" (tool-call-id block)
                         "name" (tool-call-name block)
                         "arguments"
                         (tool-call-arguments block))))))))
            ((typep message 'tool-result-message)
             (json-object
              "role" "toolResult"
              "toolCallId"
              (tool-result-message-tool-call-id message)
              "toolName"
              (tool-result-message-tool-name message)
              "content"
              (pi-message-content
               (tool-result-message-content message))
              "isError"
              (tool-result-message-is-error message))))))
   "tools"
   (list-json-array
    (loop for tool in (context-tools context)
          collect
          (json-object
           "name" (tool-name tool)
           "description" (tool-description tool)
           "parameters" (tool-parameters tool))))))

(defmethod build-request
    ((provider pi-messages-provider) model context
     &key stream-p max-tokens temperature reasoning
       cache-retention session-id tool-choice metadata)
  (let ((key
          (or (provider-oauth-access-token provider)
              (provider-api-key provider))))
    (unless (non-empty-string-p key)
      (error 'configuration-error
             :message
             (format nil
                     "No API key provided for provider ~A"
                     (model-provider model))))
    (let ((options
            (json-object)))
      (when (not (null temperature))
        (json-put options "temperature" temperature))
      (when max-tokens
        (json-put options "maxTokens" max-tokens))
      (when reasoning
        (json-put options "reasoning"
                  (string-downcase (symbol-name reasoning))))
      (when cache-retention
        (json-put options "cacheRetention"
                  (string-downcase
                   (symbol-name cache-retention))))
      (when session-id
        (json-put options "sessionId" session-id))
      (when tool-choice
        (json-put options "toolChoice" tool-choice))
      (make-request-spec
       :url
       (format nil "~A/messages~A"
               (strip-trailing-slash (model-base-url model))
               (if (and (listp metadata)
                        (getf metadata :debug))
                   "?debug=1" ""))
       :headers
       (append
        `(("authorization" . ,(format nil "Bearer ~A" key))
          ("accept" . ,(if stream-p
                           "text/event-stream"
                           "application/json"))
          ("content-type" . "application/json"))
        (model-headers model))
       :payload
       (json-object
        "model" (model-id model)
        "context" (pi-context-json context)
        "options" options)
       :stream-p stream-p
       :provider (model-provider model)))))

(defun pi-event-data (event)
  (parse-json (sse-event-data event)))

(defmethod reduce-provider-sse-event
    ((provider pi-messages-provider) state event emit)
  (declare (ignore provider))
  (let* ((data (pi-event-data event))
         (type (json-get data "type"))
         (message (provider-stream-state-message state))
         (index (json-get data "contentIndex")))
    (cond
      ((string= type "text_start")
       (start-content-block state :text emit))
      ((string= type "text_delta")
       (append-text-delta state
                          (or (json-get data "delta") "")
                          emit))
      ((string= type "text_end")
       (finish-current-block state emit))
      ((string= type "thinking_start")
       (start-content-block state :thinking emit))
      ((string= type "thinking_delta")
       (append-thinking-delta
        state (or (json-get data "delta") "") emit))
      ((string= type "thinking_end")
       (finish-current-block state emit))
      ((string= type "toolcall_start")
       (let ((call
               (make-tool-call
                :id (or (json-get data "id") "")
                :name (or (json-get data "toolName") "")
                :arguments (json-object))))
         (setf
          (provider-stream-state-current-block-index state)
          index
          (gethash index
                   (provider-stream-state-partial-json state))
          ""
          (gethash index
                   (provider-stream-state-block-indices state))
          call
          (assistant-message-content message)
          (append (assistant-message-content message)
                  (list call)))
         (emit-event emit :tool-call-start message
                     :content-index index)))
      ((string= type "toolcall_delta")
       (let ((piece (or (json-get data "delta") "")))
         (setf
          (gethash index
                   (provider-stream-state-partial-json state))
          (nappend-string
           (or (gethash
                index
                (provider-stream-state-partial-json state))
               "")
           piece))
         (emit-event emit :tool-call-delta message
                     :content-index index
                     :delta piece)))
      ((string= type "toolcall_end")
       (let ((block
               (gethash
                index
                (provider-stream-state-block-indices state))))
         (when (typep block 'tool-call)
           (let ((json
                   (gethash
                    index
                    (provider-stream-state-partial-json state)
                    "")))
             (when (non-empty-string-p json)
               (setf (tool-call-arguments block)
                     (parse-partial-json-object json)))))
         (emit-event emit :tool-call-end message
                     :content-index index
                     :tool-call block)))
      ((member type '("done" "error") :test #'string=)
       (let* ((raw (or (json-get data "reason")
                       (if (string= type "done")
                           "stop" "error")))
              (usage (json-get data "usage")))
         (setf
          (assistant-message-raw-stop-reason message) raw
          (assistant-message-stop-reason message)
          (case (intern
                 (substitute #\-
                             #\_
                             (string-upcase raw))
                 :keyword)
            (:STOP :stop)
            (:LENGTH :length)
            (:TOOLUSE :tool-use)
            (:TOOL-USE :tool-use)
            (:ABORTED :aborted)
            (otherwise :error))
          (assistant-message-response-id message)
          (json-get data "responseId")
          (assistant-message-error-message message)
          (json-get data "errorMessage")
          (provider-stream-state-terminal-p state) t)
         (when usage
           (update-message-usage
            message
            (json-get usage "input")
            (json-get usage "output")
            (json-get usage "cacheRead")
            (json-get usage "cacheWrite")
            (json-get usage "reasoning")
            (json-get usage "totalTokens"))))))))

(defmethod parse-complete-response
    ((provider pi-messages-provider) model response)
  (let ((state
          (make-provider-stream-state
           :message (empty-assistant-message model))))
    (reduce-provider-sse-event
     provider state
     (make-sse-event :data (stringify-json response))
     (constantly nil))
    (provider-stream-state-message state)))
