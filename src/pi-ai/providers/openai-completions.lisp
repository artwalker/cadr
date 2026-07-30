(in-package #:pi-ai)

(defun chat-completions-url (base-url)
  (let ((base (strip-trailing-slash base-url)))
    (cond
      ((or (uiop:string-suffix-p "/chat/completions" base)
           (uiop:string-suffix-p "/v1/chat/completions" base))
       base)
      ((uiop:string-suffix-p "/v1" base)
       (concatenate 'string base "/chat/completions"))
      (t
       (concatenate 'string base "/v1/chat/completions")))))

(defun openai-chat-user-content (content)
  (if (stringp content)
      content
      (list-json-array
       (loop for block across (coerce content 'vector)
             append
             (cond
               ((typep block 'text-content)
                (list
                 (json-object
                  "type" "text"
                  "text" (text-content-text block))))
               ((typep block 'image-content)
                (list
                 (json-object
                  "type" "image_url"
                  "image_url"
                  (json-object
                   "url" (data-url block)))))
               (t nil))))))

(defun openai-chat-tool-call (call)
  (json-object
   "id" (tool-call-id call)
   "type" "function"
   "function"
   (json-object
    "name" (tool-call-name call)
    "arguments" (stringify-json (tool-call-arguments call)))))

(defun openai-chat-assistant-message (message)
  (let ((result (json-object "role" "assistant"))
        (texts nil)
        (thinking nil)
        (calls nil))
    (dolist (block (assistant-message-content message))
      (cond
        ((typep block 'text-content)
         (push (text-content-text block) texts))
        ((typep block 'thinking-content)
         (push (thinking-content-thinking block) thinking))
        ((typep block 'tool-call)
         (push (openai-chat-tool-call block) calls))))
    (when texts
      (json-put result "content"
                (format nil "~{~A~}" (nreverse texts))))
    (when thinking
      (json-put result "reasoning_content"
                (format nil "~{~A~^~%~%~}" (nreverse thinking))))
    (when calls
      (json-put result "tool_calls"
                (list-json-array (nreverse calls))))
    (when (and (null texts) (null calls))
      (json-put result "content" ""))
    result))

(defun openai-chat-messages (model context)
  (let ((messages nil))
    (when (non-empty-string-p (context-system-prompt context))
      (push
       (json-object "role" "system"
                    "content" (context-system-prompt context))
       messages))
    (dolist
        (message
         (prepare-messages-for-model
          (context-messages context)
          model
          #'normalize-provider-id))
      (cond
        ((typep message 'user-message)
         (let ((content
                 (openai-chat-user-content
                  (user-message-content message))))
           (unless (and (vectorp content) (zerop (length content)))
             (push (json-object "role" "user"
                                "content" content)
                   messages))))
        ((typep message 'assistant-message)
         (push (openai-chat-assistant-message message) messages))
        ((typep message 'tool-result-message)
         (push
          (json-object
           "role" "tool"
           "tool_call_id"
           (tool-result-message-tool-call-id message)
           "content"
           (let ((text
                   (content-text
                    (tool-result-message-content message))))
             (if (non-empty-string-p text)
                 text
                 (if (content-has-images-p
                      (tool-result-message-content message))
                     "(see attached image)"
                     "(no tool output)"))))
          messages)
         (when (content-has-images-p
                (tool-result-message-content message))
           (push
            (json-object
             "role" "user"
             "content"
             (list-json-array
              (cons
               (json-object
                "type" "text"
                "text" "Attached image(s) from tool result:")
               (loop for block
                       across
                       (coerce
                        (tool-result-message-content message)
                        'vector)
                     when (typep block 'image-content)
                       collect
                       (json-object
                        "type" "image_url"
                        "image_url"
                        (json-object "url" (data-url block)))))))
            messages)))))
    (list-json-array (nreverse messages))))

(defun openai-chat-tools (tools)
  (list-json-array
   (loop for tool in tools
         collect
         (json-object
          "type" "function"
          "function"
          (json-object
           "name" (tool-name tool)
           "description" (tool-description tool)
           "parameters" (tool-parameters tool))))))

(defmethod build-request ((provider openai-completions-provider)
                          model context
                          &key stream-p max-tokens temperature)
  (ensure-supported-content model context)
  (let* ((token (provider-bearer-token provider))
         (payload
           (json-object
            "model" (model-id model)
            "messages" (openai-chat-messages model context)
            "stream" (and stream-p t))))
    (when stream-p
      (json-put payload "stream_options"
                (json-object "include_usage" t)))
    (when max-tokens
      (json-put payload "max_tokens" max-tokens))
    (when (not (null temperature))
      (json-put payload "temperature" temperature))
    (when (context-tools context)
      (json-put payload "tools"
                (openai-chat-tools (context-tools context))))
    (make-request-spec
     :url (chat-completions-url (model-base-url model))
     :headers
     (append
      `(("content-type" . "application/json")
        ("accept" . ,(if stream-p
                         "text/event-stream"
                         "application/json")))
      (when token
        `(("authorization" . ,(format nil "Bearer ~A" token)))))
     :payload payload
     :stream-p stream-p
     :provider (model-provider model))))

(defun chat-choice (response)
  (let ((choices (json-get response "choices")))
    (and (vectorp choices)
         (plusp (length choices))
         (aref choices 0))))

(defun parse-chat-tool-call (object)
  (let* ((function (json-get object "function"))
         (arguments (json-get function "arguments")))
    (make-tool-call
     :id (or (json-get object "id") "")
     :name (or (json-get function "name") "")
     :arguments
     (if (non-empty-string-p arguments)
         (parse-json arguments)
         (json-object)))))

(defun parse-chat-message-content (message)
  (let ((content nil)
        (thinking (json-get message "reasoning_content"))
        (text (json-get message "content"))
        (calls (json-get message "tool_calls")))
    (when (non-empty-string-p thinking)
      (push
       (make-thinking-content
        :thinking thinking
        :signature "reasoning_content")
       content))
    (when (non-empty-string-p text)
      (push (make-text-content :text text) content))
    (when (vectorp calls)
      (loop for call across calls
            do (push (parse-chat-tool-call call) content)))
    (nreverse content)))

(defun update-openai-chat-usage (message raw)
  (when (hash-table-p raw)
    (let* ((prompt-details
             (json-get raw "prompt_tokens_details"))
           (completion-details
             (json-get raw "completion_tokens_details"))
           (cached
             (or (json-get prompt-details "cached_tokens")
                 (json-get raw "prompt_cache_hit_tokens")
                 0))
           (cache-write
             (or (json-get prompt-details "cache_write_tokens") 0))
           (prompt (or (json-get raw "prompt_tokens") 0))
           (usage
             (make-usage
              :input (max 0 (- prompt cached cache-write))
              :output (or (json-get raw "completion_tokens") 0)
              :cache-read cached
              :cache-write cache-write
              :reasoning
              (or (json-get completion-details "reasoning_tokens") 0))))
      (setf (assistant-message-usage message) usage)
      (apply-known-model-cost message)))
  message)

(defun map-chat-stop-reason (reason)
  (cond
    ((or (null reason)
         (member reason '("stop" "end") :test #'string=))
     :stop)
    ((string= reason "length") :length)
    ((member reason '("function_call" "tool_calls")
             :test #'string=)
     :tool-use)
    (t :error)))

(defmethod parse-complete-response
    ((provider openai-completions-provider) model response)
  (declare (ignore provider))
  (let* ((choice (chat-choice response))
         (raw-stop (or (json-get choice "finish_reason") "stop"))
         (message
           (make-assistant-message
            :content
            (parse-chat-message-content
             (or (json-get choice "message") (json-object)))
            :api (model-api model)
            :provider (model-provider model)
            :model (model-id model)
            :response-id (json-get response "id")
            :raw-stop-reason raw-stop
            :stop-reason (map-chat-stop-reason raw-stop))))
    (when (eq :error (assistant-message-stop-reason message))
      (setf (assistant-message-error-message message)
            (format nil "Provider finish_reason: ~A" raw-stop)))
    (update-openai-chat-usage message (json-get response "usage"))
    message))

(defun chat-stream-block (state key type emit)
  (let* ((message (provider-stream-state-message state))
         (index
           (gethash key
                    (provider-stream-state-block-indices state)))
         (block
           (and index
                (nth index (assistant-message-content message)))))
    (unless block
      (setf block
            (ecase type
              (:text (make-text-content))
              (:thinking
               (make-thinking-content
                :signature "reasoning_content"))))
      (setf index (append-content-block message block)
            (gethash key
                     (provider-stream-state-block-indices state))
            index)
      (emit-event emit
                  (ecase type
                    (:text :text-start)
                    (:thinking :thinking-start))
                  message
                  :content-index index))
    (values block index)))

(defun append-chat-text-delta (state key type delta emit)
  (when (non-empty-string-p delta)
    (multiple-value-bind (block index)
        (chat-stream-block state key type emit)
      (ecase type
        (:text
         (setf (text-content-text block)
               (concatenate 'string
                            (text-content-text block) delta)))
        (:thinking
         (setf (thinking-content-thinking block)
               (concatenate 'string
                            (thinking-content-thinking block)
                            delta))))
      (emit-event emit
                  (ecase type
                    (:text :text-delta)
                    (:thinking :thinking-delta))
                  (provider-stream-state-message state)
                  :content-index index
                  :delta delta))))

(defun chat-stream-tool-block (state tool-index delta emit)
  (let* ((key (+ 100000 tool-index))
         (message (provider-stream-state-message state))
         (content-index
           (gethash key
                    (provider-stream-state-block-indices state)))
         (block
           (and content-index
                (nth content-index
                     (assistant-message-content message)))))
    (unless block
      (setf block
            (make-tool-call
             :id (or (json-get delta "id") "")
             :name
             (or (json-get
                  (json-get delta "function") "name")
                 "")
             :arguments (json-object))
            content-index (append-content-block message block)
            (gethash key
                     (provider-stream-state-block-indices state))
            content-index
            (gethash key
                     (provider-stream-state-partial-json state))
            "")
      (emit-event emit :tool-call-start message
                  :content-index content-index))
    (let* ((function (json-get delta "function"))
           (id (json-get delta "id"))
           (name (json-get function "name"))
           (arguments (or (json-get function "arguments") "")))
      (when (non-empty-string-p id)
        (setf (tool-call-id block) id))
      (when (non-empty-string-p name)
        (setf (tool-call-name block) name))
      (when (plusp (length arguments))
        (setf
         (gethash key
                  (provider-stream-state-partial-json state))
         (concatenate
          'string
          (gethash key
                   (provider-stream-state-partial-json state)
                   "")
          arguments))
        (emit-event emit :tool-call-delta message
                    :content-index content-index
                    :delta arguments)))
    block))

(defun finish-chat-stream-blocks (state emit)
  (let ((message (provider-stream-state-message state)))
    (maphash
     (lambda (key index)
       (let ((block (nth index
                         (assistant-message-content message))))
         (cond
           ((typep block 'text-content)
            (emit-event emit :text-end message
                        :content-index index
                        :content (text-content-text block)))
           ((typep block 'thinking-content)
            (emit-event emit :thinking-end message
                        :content-index index
                        :content
                        (thinking-content-thinking block)))
           ((typep block 'tool-call)
            (let ((json
                    (gethash
                     key
                     (provider-stream-state-partial-json state)
                     "")))
              (setf
               (tool-call-arguments block)
               (if (non-empty-string-p json)
                   (parse-json json)
                   (json-object)))
              (emit-event emit :tool-call-end message
                          :content-index index
                          :tool-call block))))))
     (provider-stream-state-block-indices state))))

(defmethod reduce-provider-sse-event
    ((provider openai-completions-provider) state event emit)
  (declare (ignore provider))
  (let ((data (sse-event-data event))
        (message (provider-stream-state-message state)))
    (unless (string= data "[DONE]")
      (let* ((payload (parse-json data))
             (choice (chat-choice payload)))
        (when (non-empty-string-p (json-get payload "id"))
          (setf (assistant-message-response-id message)
                (json-get payload "id")))
        (update-openai-chat-usage message
                                  (json-get payload "usage"))
        (when choice
          (let ((delta (json-get choice "delta"))
                (finish-reason
                  (json-get choice "finish_reason")))
            (append-chat-text-delta
             state :thinking :thinking
             (json-get delta "reasoning_content") emit)
            (append-chat-text-delta
             state :text :text
             (json-get delta "content") emit)
            (let ((calls (json-get delta "tool_calls")))
              (when (vectorp calls)
                (loop for call across calls
                      do
                      (chat-stream-tool-block
                       state
                       (or (json-get call "index") 0)
                       call emit))))
            (when (and finish-reason
                       (not (json-null-p finish-reason)))
              (finish-chat-stream-blocks state emit)
              (setf
               (assistant-message-raw-stop-reason message)
               finish-reason
               (assistant-message-stop-reason message)
               (map-chat-stop-reason finish-reason)
               (provider-stream-state-terminal-p state) t)
              (when
                  (eq :error
                      (assistant-message-stop-reason message))
                (setf
                 (assistant-message-error-message message)
                 (format nil "Provider finish_reason: ~A"
                         finish-reason))))))))))
