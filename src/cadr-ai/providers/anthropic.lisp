(in-package #:cadr-ai)

(defun anthropic-input-block (block)
  (cond
    ((typep block 'text-content)
     (json-object "type" "text"
                  "text" (text-content-text block)))
    ((typep block 'image-content)
     (json-object
      "type" "image"
      "source"
      (json-object
       "type" "base64"
       "media_type" (image-content-mime-type block)
       "data" (image-content-data block))))
    (t nil)))

(defun anthropic-message-content (message)
  (cond
    ((typep message 'user-message)
     (let ((content (user-message-content message)))
       (if (stringp content)
           content
           (list-json-array
            (loop for block across (coerce content 'vector)
                  for encoded = (anthropic-input-block block)
                  when encoded collect encoded)))))
    ((typep message 'assistant-message)
     (list-json-array
      (loop for block in (assistant-message-content message)
            when (typep block 'text-content)
              collect (json-object "type" "text"
                                   "text" (text-content-text block))
            when (typep block 'thinking-content)
              collect (if (thinking-content-redacted-p block)
                          (json-object
                           "type" "redacted_thinking"
                           "data" (or (thinking-content-signature block) ""))
                          (json-object
                           "type" "thinking"
                           "thinking" (thinking-content-thinking block)
                           "signature"
                           (or (thinking-content-signature block) "")))
            when (typep block 'tool-call)
              collect (json-object
                       "type" "tool_use"
                       "id" (tool-call-id block)
                       "name" (tool-call-name block)
                       "input" (tool-call-arguments block)))))
    ((typep message 'tool-result-message)
     (json-array
      (json-object
       "type" "tool_result"
       "tool_use_id" (tool-result-message-tool-call-id message)
       "content"
       (let ((content (tool-result-message-content message)))
         (if (content-has-images-p content)
             (list-json-array
              (loop for block across (coerce content 'vector)
                    for encoded = (anthropic-input-block block)
                    when encoded collect encoded))
             (content-text content)))
       "is_error" (tool-result-message-is-error message))))))

(defun anthropic-messages (model messages)
  (let ((prepared
          (prepare-messages-for-model
           messages model #'normalize-provider-id))
        (result nil))
    (loop with index = 0
          while (< index (length prepared))
          for message = (nth index prepared)
          do
          (cond
            ((typep message 'tool-result-message)
             (let ((blocks nil))
               (loop while (and (< index (length prepared))
                                (typep (nth index prepared)
                                       'tool-result-message))
                     do (push
                         (aref
                          (anthropic-message-content
                           (nth index prepared))
                          0)
                         blocks)
                        (incf index))
               (push
                (json-object
                 "role" "user"
                 "content" (list-json-array (nreverse blocks)))
                result)))
            ((typep message 'assistant-message)
             (let ((content (anthropic-message-content message)))
               (when (plusp (length content))
                 (push
                  (json-object "role" "assistant"
                               "content" content)
                  result)))
             (incf index))
            ((typep message 'user-message)
             (let ((content (anthropic-message-content message)))
               (when (if (stringp content)
                         (non-empty-string-p content)
                         (plusp (length content)))
                 (push
                  (json-object "role" "user"
                               "content" content)
                  result)))
             (incf index))
            (t
             (incf index))))
    (list-json-array (nreverse result))))

(defun anthropic-tools (tools)
  (list-json-array
   (loop for tool in tools
         collect
         (json-object
          "name" (tool-name tool)
          "description" (tool-description tool)
          "eager_input_streaming" t
          "input_schema" (tool-parameters tool)))))

(defmethod build-request ((provider anthropic-provider)
                          model context
                          &key stream-p max-tokens temperature)
  (ensure-supported-content model context)
  (let* ((oauth-token (provider-oauth-access-token provider))
         (key (or oauth-token (require-api-key provider)))
         (payload
           (json-object
            "model" (model-id model)
            "messages" (anthropic-messages
                        model (context-messages context))
            "max_tokens" (or max-tokens (model-max-tokens model))
            "stream" (and stream-p t))))
    (when (non-empty-string-p (context-system-prompt context))
      (json-put payload
                "system"
                (json-array
                 (json-object "type" "text"
                              "text" (context-system-prompt context)))))
    (when (context-tools context)
      (json-put payload "tools" (anthropic-tools (context-tools context))))
    (when temperature
      (json-put payload "temperature" temperature))
    (make-request-spec
     :url (format nil "~A/v1/messages"
                  (strip-trailing-slash (model-base-url model)))
     :headers
     (append
      `(("content-type" . "application/json")
        ("accept" . ,(if stream-p
                         "text/event-stream"
                         "application/json")))
      (if oauth-token
          `(("authorization" . ,(format nil "Bearer ~A" key))
            ("anthropic-beta"
             . "claude-code-20250219,oauth-2025-04-20")
            ("x-app" . "cli"))
          `(("x-api-key" . ,key)))
      '(("anthropic-version" . "2023-06-01")))
     :payload payload
     :stream-p stream-p
     :provider :anthropic)))

(defun parse-anthropic-content (content)
  (loop for block across (or content #())
        for type = (json-get block "type")
        when (string= type "text")
          collect (make-text-content :text (or (json-get block "text") ""))
        when (string= type "thinking")
          collect (make-thinking-content
                   :thinking (or (json-get block "thinking") "")
                   :signature (json-get block "signature"))
        when (string= type "redacted_thinking")
          collect (make-thinking-content
                   :thinking "[Reasoning redacted]"
                   :signature (json-get block "data")
                   :redacted-p t)
        when (string= type "tool_use")
          collect (make-tool-call
                   :id (or (json-get block "id") "")
                   :name (or (json-get block "name") "")
                   :arguments (or (json-get block "input")
                                  (json-object)))))

(defun update-anthropic-usage (message usage)
  (when (hash-table-p usage)
    (update-message-usage
     message
     (json-get usage "input_tokens")
     (json-get usage "output_tokens")
     (json-get usage "cache_read_input_tokens")
     (json-get usage "cache_creation_input_tokens")
     (json-get (json-get usage "output_tokens_details")
               "thinking_tokens"))
    (apply-known-model-cost message)))

(defmethod parse-complete-response ((provider anthropic-provider)
                                    model response)
  (declare (ignore provider))
  (let* ((raw-stop (or (json-get response "stop_reason") "end_turn"))
         (message
           (make-assistant-message
            :content (parse-anthropic-content (json-get response "content"))
            :api (model-api model)
            :provider (model-provider model)
            :model (model-id model)
            :response-id (json-get response "id")
            :raw-stop-reason raw-stop
            :stop-reason (map-simple-stop-reason raw-stop))))
    (update-anthropic-usage message (json-get response "usage"))
    (when (and (eq :stop (assistant-message-stop-reason message))
               (tool-call-present-p message))
      (setf (assistant-message-stop-reason message) :tool-use))
    message))

(defun anthropic-stream-block (state provider-index)
  (let ((content-index
          (gethash provider-index
                   (provider-stream-state-block-indices state))))
    (values (and content-index
                 (nth content-index
                      (assistant-message-content
                       (provider-stream-state-message state))))
            content-index)))

(defmethod reduce-provider-sse-event ((provider anthropic-provider)
                                      state event emit)
  (declare (ignore provider))
  (let ((data (sse-event-data event)))
    (when (or (zerop (length data)) (string= data "[DONE]"))
      (return-from reduce-provider-sse-event nil))
    (let* ((payload (parse-json data))
           (type (or (json-get payload "type")
                     (sse-event-event event)))
           (message (provider-stream-state-message state)))
      (cond
        ((string= type "message_start")
         (let ((upstream (json-get payload "message")))
           (setf (assistant-message-response-id message)
                 (json-get upstream "id"))
           (update-anthropic-usage message (json-get upstream "usage"))))
        ((string= type "content_block_start")
         (let* ((provider-index (json-get payload "index"))
                (block-data (json-get payload "content_block"))
                (block-type (json-get block-data "type"))
                (block
                  (cond
                    ((string= block-type "text")
                     (make-text-content))
                    ((string= block-type "thinking")
                     (make-thinking-content))
                    ((string= block-type "redacted_thinking")
                     (make-thinking-content
                      :thinking "[Reasoning redacted]"
                      :signature (json-get block-data "data")
                      :redacted-p t))
                    ((string= block-type "tool_use")
                     (make-tool-call
                      :id (or (json-get block-data "id") "")
                      :name (or (json-get block-data "name") "")
                      :arguments (or (json-get block-data "input")
                                     (json-object))))
                    (t
                     (error 'sse-protocol-error
                            :message (format nil
                                             "Unknown Anthropic content block: ~A"
                                             block-type)))))
                (content-index (append-content-block message block)))
           (setf (gethash provider-index
                          (provider-stream-state-block-indices state))
                 content-index)
           (cond
             ((typep block 'text-content)
              (emit-event emit :text-start message
                          :content-index content-index))
             ((typep block 'thinking-content)
              (emit-event emit :thinking-start message
                          :content-index content-index))
             ((typep block 'tool-call)
              (setf (gethash provider-index
                             (provider-stream-state-partial-json state))
                    "")
              (emit-event emit :tool-call-start message
                          :content-index content-index)))))
        ((string= type "content_block_delta")
         (let* ((provider-index (json-get payload "index"))
                (delta (json-get payload "delta"))
                (delta-type (json-get delta "type")))
           (multiple-value-bind (block content-index)
               (anthropic-stream-block state provider-index)
             (cond
               ((and block (string= delta-type "text_delta"))
                (let ((text (or (json-get delta "text") "")))
                  (setf (text-content-text block)
                        (concatenate 'string
                                     (text-content-text block)
                                     text))
                  (emit-event emit :text-delta message
                              :content-index content-index
                              :delta text)))
               ((and block (string= delta-type "thinking_delta"))
                (let ((text (or (json-get delta "thinking") "")))
                  (setf (thinking-content-thinking block)
                        (concatenate
                         'string
                         (thinking-content-thinking block)
                         text))
                  (emit-event emit :thinking-delta message
                              :content-index content-index
                              :delta text)))
               ((and block (string= delta-type "signature_delta"))
                (setf (thinking-content-signature block)
                      (concatenate
                       'string
                       (or (thinking-content-signature block) "")
                       (or (json-get delta "signature") ""))))
               ((and block (string= delta-type "input_json_delta"))
                (let* ((fragment (or (json-get delta "partial_json") ""))
                       (previous
                         (gethash provider-index
                                  (provider-stream-state-partial-json state)
                                  "")))
                  (setf (gethash
                         provider-index
                         (provider-stream-state-partial-json state))
                        (concatenate 'string previous fragment))
                  (emit-event emit :tool-call-delta message
                              :content-index content-index
                              :delta fragment)))))))
        ((string= type "content_block_stop")
         (let ((provider-index (json-get payload "index")))
           (multiple-value-bind (block content-index)
               (anthropic-stream-block state provider-index)
             (cond
               ((typep block 'text-content)
                (emit-event emit :text-end message
                            :content-index content-index
                            :content (text-content-text block)))
               ((typep block 'thinking-content)
                (emit-event emit :thinking-end message
                            :content-index content-index
                            :content (thinking-content-thinking block)))
               ((typep block 'tool-call)
                (let ((json (gethash
                             provider-index
                             (provider-stream-state-partial-json state)
                             "")))
                  (when (non-empty-string-p json)
                    (setf (tool-call-arguments block) (parse-json json)))
                  (emit-event emit :tool-call-end message
                              :content-index content-index
                              :tool-call block)))))))
        ((string= type "message_delta")
         (let* ((delta (json-get payload "delta"))
                (raw-stop (json-get delta "stop_reason")))
           (when (non-empty-string-p raw-stop)
             (setf (assistant-message-raw-stop-reason message) raw-stop
                   (assistant-message-stop-reason message)
                   (map-simple-stop-reason raw-stop)))
           (when (json-get payload "usage")
             (let ((old (assistant-message-usage message))
                   (usage (json-get payload "usage")))
               (update-message-usage
                message
                (or (json-get usage "input_tokens")
                    (usage-input old))
                (or (json-get usage "output_tokens")
                    (usage-output old))
                (or (json-get usage "cache_read_input_tokens")
                    (usage-cache-read old))
                (or (json-get usage "cache_creation_input_tokens")
                    (usage-cache-write old))
                (or (json-get
                     (json-get usage "output_tokens_details")
                     "thinking_tokens")
                    (usage-reasoning old)))))))
        ((string= type "message_stop")
         (setf (provider-stream-state-terminal-p state) t)))))
  nil)
