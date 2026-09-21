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

(defun anthropic-message-content (message &optional allow-empty-signature-p)
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
              when (non-empty-string-p (text-content-text block))
                collect (json-object "type" "text"
                                     "text" (text-content-text block))
            when (typep block 'thinking-content)
              append
              (let* ((thinking (thinking-content-thinking block))
                     (signature (thinking-content-signature block))
                     (signed-p (non-empty-string-p signature)))
                (cond
                  ((thinking-content-redacted-p block)
                   (list
                    (json-object
                     "type" "redacted_thinking"
                     "data" (or signature ""))))
                  ((and (not (non-empty-string-p thinking))
                        (not signed-p))
                   nil)
                  (signed-p
                   (list
                    (json-object
                     "type" "thinking"
                     "thinking" thinking
                     "signature" signature)))
                  (allow-empty-signature-p
                   (list
                    (json-object
                     "type" "thinking"
                     "thinking" thinking
                     "signature" "")))
                  (t
                   (list
                    (json-object
                     "type" "text"
                     "text" thinking)))))
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

(defun anthropic-cache-control (model cache-retention)
  (let ((retention (normalize-cache-retention cache-retention)))
    (unless (eq retention :none)
      (let ((result (json-object "type" "ephemeral")))
        (when (and (eq retention :long)
                   (model-compat-value
                    model :supports-long-cache-retention t))
          (json-put result "ttl" "1h"))
        result))))

(defun add-anthropic-cache-control-to-messages (messages cache-control)
  (when (and cache-control (plusp (length messages)))
    (let* ((message (aref messages (1- (length messages))))
           (content (json-get message "content")))
      (when (string= "user" (json-get message "role"))
        (cond
          ((stringp content)
           (json-put
            message "content"
            (json-array
             (json-object
              "type" "text"
              "text" content
              "cache_control" cache-control))))
          ((and (vectorp content) (plusp (length content)))
           (let ((block (aref content (1- (length content)))))
             (when (member (json-get block "type")
                           '("text" "image" "tool_result")
                           :test #'string=)
               (json-put block "cache_control" cache-control))))))))
  messages)

(defun anthropic-tool-reference-support-p (model)
  (model-compat-value
   model :supports-tool-references
   (and
    (eq (model-provider model) :anthropic)
    (not (search "haiku" (model-id model)))
    (let ((prefix
            (find-if
             (lambda (value)
               (uiop:string-prefix-p value (model-id model)))
             '("claude-opus-" "claude-sonnet-" "claude-fable-"))))
      (when prefix
        (let* ((start (length prefix))
               (major (parse-integer (model-id model)
                                     :start start :junk-allowed t))
               (major-end
                 (and major
                      (position-if-not #'digit-char-p (model-id model)
                                       :start start)))
               (minor
                 (and major-end
                      (< major-end (length (model-id model)))
                      (char= (char (model-id model) major-end) #\-)
                      (parse-integer (model-id model)
                                     :start (1+ major-end)
                                     :junk-allowed t))))
          (and major
               (or (> major 4)
                   (and (= major 4) minor (>= minor 5))))))))))

(defun anthropic-tool-result-blocks
    (message allow-empty-signature-p deferred-tools loaded-tool-names)
  (let ((references nil))
    (dolist (name (tool-result-message-added-tool-names message))
      (when (and deferred-tools
                 (gethash name deferred-tools)
                 (not (gethash name loaded-tool-names)))
        (setf (gethash name loaded-tool-names) t)
        (push (json-object "type" "tool_reference" "tool_name" name)
              references)))
    (let* ((ordinary
             (aref
              (anthropic-message-content message allow-empty-signature-p)
              0))
           (ordinary-content (json-get ordinary "content")))
      (if (null references)
          (list ordinary)
          (progn
            (json-put ordinary "content"
                      (list-json-array (nreverse references)))
            (append
             (list ordinary)
             (cond
               ((stringp ordinary-content)
                (and (plusp (length ordinary-content))
                     (list (json-object "type" "text"
                                        "text" ordinary-content))))
               ((vectorp ordinary-content) (coerce ordinary-content 'list))
               (t nil))))))))

(defun anthropic-effort-marker (effort)
  (json-object
   "role" "system"
   "content" (json-array)
   "output_config" (json-object "effort" effort)))

(defun insert-thinking-level-messages
    (messages assistant-levels active-effort)
  (let ((out nil))
    (loop for message across messages
          for index from 0
          for historical = (gethash index assistant-levels)
          do
          (when historical
            (push (anthropic-effort-marker historical) out))
          (push message out))
    (push (anthropic-effort-marker active-effort) out)
    (list-json-array (nreverse out))))

(defun anthropic-messages
    (model messages &optional cache-control deferred-tools reasoning)
  (let ((prepared
          (prepare-messages-for-model
           messages model #'normalize-provider-id))
        (result nil)
        (assistant-levels (make-hash-table :test #'eql))
        (loaded-tool-names (make-hash-table :test #'equal))
        (allow-empty-signature-p
          (model-compat-value model :allow-empty-signature nil))
        (mid-convo-p
          (model-compat-value model :supports-mid-convo-effort nil)))
    (flet ((record (encoded effort)
             (when mid-convo-p
               (when effort
                 (setf (gethash (length result) assistant-levels)
                       effort)))
             (push encoded result)))
      (loop while prepared
            for message = (first prepared)
            do
            (cond
              ((typep message 'tool-result-message)
               (let ((blocks nil))
                 (loop while (and prepared
                                  (typep (first prepared)
                                         'tool-result-message))
                       do (dolist
                              (block
                               (anthropic-tool-result-blocks
                                (pop prepared)
                                allow-empty-signature-p
                                deferred-tools
                                loaded-tool-names))
                            (push block blocks)))
                 (record
                  (json-object
                   "role" "user"
                   "content" (list-json-array (nreverse blocks)))
                  nil)))
              ((typep message 'assistant-message)
               (pop prepared)
               (let ((content
                       (anthropic-message-content
                        message allow-empty-signature-p)))
                 (when (plusp (length content))
                   (record
                    (json-object "role" "assistant"
                                 "content" content)
                    (and mid-convo-p
                         (eq (assistant-message-api message)
                             :anthropic-messages)
                         (eq (assistant-message-provider message)
                             (model-provider model))
                         (anthropic-effort-p
                          (assistant-message-provider-thinking-level
                           message))
                         (assistant-message-provider-thinking-level
                          message))))))
              ((typep message 'user-message)
               (pop prepared)
               (let ((content
                       (anthropic-message-content
                        message allow-empty-signature-p)))
                 (when (if (stringp content)
                           (non-empty-string-p content)
                           (plusp (length content)))
                   (record
                    (json-object "role" "user"
                                 "content" content)
                    nil))))
              (t
               (pop prepared)))))
    (let ((encoded
            (add-anthropic-cache-control-to-messages
             (list-json-array (nreverse result))
             cache-control)))
      (if mid-convo-p
          (insert-thinking-level-messages
           encoded
           assistant-levels
           (anthropic-active-effort model reasoning))
          encoded))))

(defun anthropic-tools
    (model tools cache-control &optional defer-loading-p)
  (list-json-array
   (loop for tool in tools
         for index from 0
         for supports-strict =
           (model-compat-value model :supports-strict-tools nil)
         ;; Baseline anthropic-messages.ts convertTools: resolve throws on
         ;; a "require" mismatch, and strict tools send the strictified
         ;; schema; others send the legacy {type,properties,required}
         ;; shape.
         for strict =
           (resolve-json-schema-strict-sampling tool supports-strict)
         for parameters = (get-json-schema-tool-parameters tool strict)
         for encoded =
         (if (eq strict t)
             (let ((merged (copy-json-value parameters)))
               (json-put merged "type" "object")
               (json-put merged "properties"
                         (or (json-get parameters "properties")
                             (json-object)))
               (json-put merged "required"
                         (or (json-get parameters "required") #()))
               merged)
             (json-object
              "type" "object"
              "properties" (or (json-get parameters "properties")
                               (json-object))
              "required" (or (json-get parameters "required") #())))
         for encoded-tool =
         (json-object
          "name" (tool-name tool)
          "description" (tool-description tool)
          "input_schema" encoded)
         do
         (when (model-compat-value
                model :supports-eager-tool-input-streaming t)
           (json-put encoded-tool "eager_input_streaming" t))
         (when (eq strict t)
           (json-put encoded-tool "strict" t))
         (when (and cache-control
                    (not defer-loading-p)
                    (model-compat-value
                     model :supports-cache-control-on-tools t)
                    (= index (1- (length tools))))
           (json-put encoded-tool "cache_control" cache-control))
         (when defer-loading-p
           (json-put encoded-tool "defer_loading" t))
         collect encoded-tool)))

(defun anthropic-thinking-options (model reasoning)
  (cond
    ((model-compat-value model :supports-mid-convo-effort nil)
     (values
      (json-object
       "type" "adaptive"
       "display" "summarized"
       "block_binding"
       (json-object "prefix_mismatch_behavior" "drop_block"))
      (json-object "effort" "high")))
    ((not (model-reasoning-p model))
     nil)
    (reasoning
     (if (model-compat-value model :force-adaptive-thinking nil)
         (values
          (json-object "type" "adaptive"
                       "display" "summarized")
          (json-object
           "effort"
           (or (model-thinking-level-value model reasoning)
               (string-downcase (symbol-name reasoning)))))
         (values
          (json-object
           "type" "enabled"
           "budget_tokens" 1024
           "display" "summarized")
          nil)))
    ((or (not (model-thinking-level-present-p model :off))
         (model-thinking-level-value model :off))
     (values (json-object "type" "disabled") nil))))

(defun anthropic-tool-choice (choice)
  (if (stringp choice)
      (json-object "type" choice)
      choice))

(defmethod build-request ((provider anthropic-provider)
                          model context
                          &key stream-p max-tokens temperature reasoning
                            cache-retention session-id tool-choice metadata
                            &allow-other-keys)
  (ensure-supported-content model context)
  (let* ((oauth-token (provider-oauth-access-token provider))
         (key (or oauth-token (require-api-key provider)))
         (cache-control
           (anthropic-cache-control model cache-retention))
         (immediate-tools nil)
         (deferred-tools nil)
         (payload
           (json-object
            "model" (model-id model)
            "max_tokens" (or max-tokens (model-max-tokens model))
            "stream" (and stream-p t))))
    (multiple-value-setq (immediate-tools deferred-tools)
      (split-deferred-tools
       context (anthropic-tool-reference-support-p model)))
    (when (and (null immediate-tools)
               (plusp (hash-table-count deferred-tools)))
      (setf immediate-tools
            (loop for tool being the hash-values of deferred-tools
                  collect tool)
            deferred-tools (make-hash-table :test #'equal)))
    (json-put
     payload "messages"
     (anthropic-messages
      model (context-messages context) cache-control deferred-tools
      reasoning))
    (when (non-empty-string-p (context-system-prompt context))
      (let ((block
              (json-object
               "type" "text"
               "text" (context-system-prompt context))))
         (when cache-control
           (json-put block "cache_control" cache-control))
        (json-put payload "system" (json-array block))))
    (when (or immediate-tools
              (plusp (hash-table-count deferred-tools)))
      (json-put
       payload "tools"
       (list-json-array
        (append
         (coerce
          (anthropic-tools model immediate-tools cache-control)
          'list)
         (coerce
          (anthropic-tools
           model
           (loop for tool being the hash-values of deferred-tools
                 collect tool)
           nil t)
          'list)))))
    (when (and (not (null temperature))
               (null reasoning)
               (not (model-compat-value
                     model :supports-mid-convo-effort nil))
               (model-compat-value model :supports-temperature t))
      (json-put payload "temperature" temperature))
    (multiple-value-bind (thinking output-config)
        (anthropic-thinking-options model reasoning)
      (when thinking
        (json-put payload "thinking" thinking))
      (when output-config
        (json-put payload "output_config" output-config)))
    (when tool-choice
      (json-put payload "tool_choice"
                (anthropic-tool-choice tool-choice)))
    (let ((user-id (and (listp metadata) (getf metadata :user-id))))
      (when (stringp user-id)
        (json-put payload "metadata"
                  (json-object "user_id" user-id))))
    (make-request-spec
     :url (format nil "~A/v1/messages"
                  (strip-trailing-slash (model-base-url model)))
     :headers
    (let* ((beta-features
             (append
              (when oauth-token
                '("claude-code-20250219" "oauth-2025-04-20"))
              (when (and (context-tools context)
                         (not
                          (model-compat-value
                           model :supports-eager-tool-input-streaming t)))
                '("fine-grained-tool-streaming-2025-05-14"))
              (when (model-compat-value
                     model :supports-mid-convo-effort nil)
                '("mid-conversation-output-config-2026-07-01"
                  "thinking-binding-controls-2026-08-01"))))
           (headers
             (append
              `(("content-type" . "application/json")
                ("accept" . ,(if stream-p
                                 "text/event-stream"
                                 "application/json")))
              (if oauth-token
                  `(("authorization" . ,(format nil "Bearer ~A" key))
                    ("x-app" . "cli"))
                  `(("x-api-key" . ,key)))
              '(("anthropic-version" . "2023-06-01"))
              (when beta-features
                (list
                 (cons "anthropic-beta"
                       (format nil "~{~A~^,~}" beta-features))))
              (when (and cache-control
                         (non-empty-string-p session-id)
                         (model-compat-value
                          model :send-session-affinity-headers nil))
                `(("x-session-affinity" . ,session-id)))
              (opencode-request-headers
               :provider (model-provider model)
               :base-url (model-base-url model)
               :session-id session-id)
              (model-headers model))))
       (if (eq (model-provider model) :kimi-coding)
           (progn
             ;; Baseline anthropic-messages.ts mergeClientHeaders: the
             ;; kimi-coding endpoint is pinned to the OS-describing
             ;; product UA, so any inherited user-agent is dropped first.
             (setf headers
                   (delete-if
                    (lambda (pair)
                      (string-equal (car pair) "user-agent"))
                    headers))
             (append headers
                     (list (cons "User-Agent" (cadr-os-user-agent)))))
           headers))
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

(defun parse-anthropic-input-transformations (value)
  (when (or (vectorp value) (listp value))
    (map 'list
         (lambda (item)
           (list :type (json-get item "type")
                 :path (json-get item "path")
                 :reason (json-get item "reason")))
         value)))

(defun capture-anthropic-input-transformations (state value)
  (let ((parsed (parse-anthropic-input-transformations value)))
    (when parsed
      (setf (provider-stream-state-input-transformations state)
            parsed))))

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
           (update-anthropic-usage message (json-get upstream "usage"))
           (capture-anthropic-input-transformations
            state
            (json-get upstream "input_transformations"))))
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
                        (nappend-string
                         (text-content-text block) text))
                  (emit-event emit :text-delta message
                              :content-index content-index
                              :delta text)))
               ((and block (string= delta-type "thinking_delta"))
                (let ((text (or (json-get delta "thinking") "")))
                  (setf (thinking-content-thinking block)
                        (nappend-string
                         (thinking-content-thinking block) text))
                  (emit-event emit :thinking-delta message
                              :content-index content-index
                              :delta text)))
               ((and block (string= delta-type "signature_delta"))
                (setf (thinking-content-signature block)
                      (nappend-string
                       (or (thinking-content-signature block) "")
                       (or (json-get delta "signature") ""))))
               ((and block (string= delta-type "input_json_delta"))
                (let ((fragment (or (json-get delta "partial_json") "")))
                  (setf (gethash
                         provider-index
                         (provider-stream-state-partial-json state))
                        (nappend-string
                         (gethash
                          provider-index
                          (provider-stream-state-partial-json state)
                          "")
                         fragment))
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
                    (setf (tool-call-arguments block)
                          (parse-streaming-json json)))
                  (emit-event emit :tool-call-end message
                              :content-index content-index
                              :tool-call block)))))))
        ((string= type "message_delta")
         (let* ((delta (json-get payload "delta"))
                (raw-stop (json-get delta "stop_reason")))
           (capture-anthropic-input-transformations
            state
            (json-get payload "input_transformations"))
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
         (append-anthropic-input-transformations-diagnostic
          message
          (provider-stream-state-input-transformations state))
         (setf (provider-stream-state-terminal-p state) t)))))
  nil)
