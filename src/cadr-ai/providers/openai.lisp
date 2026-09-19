(in-package #:cadr-ai)

(defun split-openai-tool-call-id (id)
  (let ((separator (position #\| id)))
    (if separator
        (values (subseq id 0 separator)
                (subseq id (1+ separator)))
        (values id nil))))

(defun responses-developer-role-p (model)
  (and (model-reasoning-p model)
       (model-compat-value model :supports-developer-role t)))

(defun normalize-openai-id-part (value)
  (let* ((sanitized (normalize-provider-id value))
         (trimmed (string-right-trim "_" sanitized)))
    trimmed))

(defun responses-normalize-tool-call-id (id target source)
  (if (not (member (model-provider target)
                   '(:openai :openai-codex :opencode)
                   :test #'eq))
      (normalize-openai-id-part id)
      (multiple-value-bind (call-id item-id)
          (split-openai-tool-call-id id)
        (let* ((normalized-call-id (normalize-openai-id-part call-id))
               (foreign-p
                 (or (not (eq (assistant-message-provider source)
                              (model-provider target)))
                     (not (eq (assistant-message-api source)
                              (model-api target)))))
               (normalized-item-id
                 (and item-id
                      (if foreign-p
                          (format nil "fc_~A" (short-hash item-id))
                          (normalize-openai-id-part item-id)))))
          (when (and normalized-item-id
                     (not (uiop:string-prefix-p "fc_" normalized-item-id)))
            (setf normalized-item-id
                  (normalize-openai-id-part
                   (format nil "fc_~A" normalized-item-id))))
          (if normalized-item-id
              (format nil "~A|~A" normalized-call-id normalized-item-id)
              normalized-call-id)))))

(defun parse-openai-text-signature (signature)
  (when (non-empty-string-p signature)
    (if (char= (char signature 0) #\{)
        (handler-case
            (let ((object (parse-json signature)))
              (when (and (= 1 (or (json-get object "v") 0))
                         (stringp (json-get object "id")))
                (values (json-get object "id")
                        (let ((phase (json-get object "phase")))
                          (and (member phase '("commentary" "final_answer")
                                       :test #'string=)
                               phase)))))
          (error () (values signature nil)))
        (values signature nil))))

(defun openai-input-items
    (model context &key grammar-properties deferred-tools deferred-tools-mode
                        tool-options)
  (let ((items nil)
        (message-index 0)
        (loaded-tool-names (make-hash-table :test #'equal)))
    (when (non-empty-string-p (context-system-prompt context))
      (push (json-object "role"
                         (if (responses-developer-role-p model)
                             "developer"
                             "system")
                         "content" (context-system-prompt context))
            items))
    (dolist (message
             (prepare-messages-for-model
              (context-messages context)
              model
              #'normalize-provider-id
              #'responses-normalize-tool-call-id))
      (cond
        ((typep message 'user-message)
         (let* ((source (user-message-content message))
                (content
                  (if (stringp source)
                      (json-array
                       (json-object "type" "input_text"
                                    "text" source))
                      (list-json-array
                       (loop for block across (coerce source 'vector)
                             append
                             (cond
                               ((typep block 'text-content)
                                (list
                                 (json-object
                                  "type" "input_text"
                                  "text"
                                  (text-content-text block))))
                               ((typep block 'image-content)
                                (list
                                 (json-object
                                  "type" "input_image"
                                  "image_url" (data-url block))))
                               (t nil)))))))
           (when (or (stringp (user-message-content message))
                     (plusp (length content)))
             (push (json-object
                    "role" "user"
                    "content" content)
                   items))))
        ((typep message 'assistant-message)
         (let ((text-index 0))
           (dolist (block (assistant-message-content message))
             (cond
               ((typep block 'text-content)
                (multiple-value-bind (signature-id phase)
                    (parse-openai-text-signature
                     (text-content-signature block))
                  (let* ((fallback
                           (format nil "msg_cadr_~D~@[_~D~]"
                                   message-index
                                   (and (plusp text-index) text-index)))
                         (item-id
                           (cond
                             ((null signature-id) fallback)
                             ((> (length signature-id) 64)
                              (format nil "msg_~A" (short-hash signature-id)))
                             (t signature-id)))
                         (item
                           (json-object
                            "type" "message"
                            "id" item-id
                            "role" "assistant"
                            "status" "completed"
                            "content"
                            (json-array
                             (json-object
                              "type" "output_text"
                              "text" (text-content-text block)
                              "annotations" #())))))
                    (when phase (json-put item "phase" phase))
                    (push item items)))
                (incf text-index))
               ((typep block 'tool-call)
                (multiple-value-bind (call-id item-id)
                    (split-openai-tool-call-id (tool-call-id block))
                  (let* ((custom-property
                           (and grammar-properties
                                (gethash (tool-call-name block)
                                         grammar-properties)))
                         (item
                           (if custom-property
                               (json-object
                                "type" "custom_tool_call"
                                "call_id" call-id
                                "name" (tool-call-name block)
                                "input"
                                (get-grammar-tool-input
                                 (tool-call-name block)
                                 (tool-call-arguments block)
                                 custom-property))
                               (json-object
                                "type" "function_call"
                                "call_id" call-id
                                "name" (tool-call-name block)
                                "arguments"
                                (stringify-json
                                 (tool-call-arguments block))))))
                    (when item-id
                      (json-put item "id" item-id))
                    ;; Baseline openai-responses-shared.ts: the namespace
                    ;; replays only for the same model or for a call to a
                    ;; deferred tool.
                    (let ((namespace (tool-call-namespace block)))
                      (when (and namespace
                                 (or (and (eq (assistant-message-provider
                                               message)
                                              (model-provider model))
                                          (eq (assistant-message-api message)
                                              (model-api model))
                                          (string=
                                           (assistant-message-model message)
                                           (model-id model)))
                                     (and deferred-tools
                                          (gethash (tool-call-name block)
                                                   deferred-tools))))
                        (json-put item "namespace" namespace)))
                    (push item items))))))))
        ((typep message 'tool-result-message)
         (multiple-value-bind (call-id item-id)
             (split-openai-tool-call-id
              (tool-result-message-tool-call-id message))
           (declare (ignore item-id))
           (push
            (json-object
             "type"
             (if (and grammar-properties
                      (gethash (tool-result-message-tool-name message)
                               grammar-properties))
                 "custom_tool_call_output"
                 "function_call_output")
             "call_id" call-id
             "output"
             (let ((text
                     (content-text
                      (tool-result-message-content message))))
               (if (non-empty-string-p text)
                   text
                   "(no tool output)")))
            items)
           (let ((loaded nil))
             (dolist (name (tool-result-message-added-tool-names message))
               (let ((tool (and deferred-tools (gethash name deferred-tools))))
                 (when (and tool (not (gethash name loaded-tool-names)))
                   (setf (gethash name loaded-tool-names) t)
                   (push tool loaded))))
             (when loaded
               (setf loaded (nreverse loaded))
               (cond
                 ;; Baseline openai-responses-shared.ts: in additional-tools
                 ;; mode the loaded tools arrive as one developer item.
                 ((eq deferred-tools-mode :additional-tools)
                  (push
                   (json-object
                    "type" "additional_tools"
                    "role" "developer"
                    "tools"
                    (openai-tools model loaded
                                  :options tool-options))
                   items))
                 ((eq deferred-tools-mode :tool-search)
                  (let* ((names (mapcar #'tool-name loaded))
                         (search-id
                           (format nil "cadr_tool_load_~A"
                                   (short-hash
                                    (format nil "~A:~{~A~^,~}"
                                            (tool-result-message-tool-call-id
                                             message)
                                            names)))))
                    (push
                     (json-object
                      "type" "tool_search_call"
                      "call_id" search-id
                      "execution" "client"
                      "status" "completed"
                      "arguments"
                      (json-object "query" (format nil "~{~A~^ ~}" names)
                                   "limit" (length names)))
                     items)
                    (push
                     (json-object
                      "type" "tool_search_output"
                      "call_id" search-id
                      "execution" "client"
                      "status" "completed"
                      "tools"
                      (openai-tools model loaded
                                    :defer-loading-p t
                                    :options tool-options))
                     items))))))
         (when (content-has-images-p
                (tool-result-message-content message))
           (push
            (json-object
             "role" "user"
             "content"
             (list-json-array
              (loop for block
                      across
                      (coerce
                       (tool-result-message-content message)
                       'vector)
                    when (typep block 'image-content)
                      collect
                      (json-object
                       "type" "input_image"
                       "image_url" (data-url block)))))
            items)))))
      (incf message-index))
    (list-json-array (nreverse items))))

(defun openai-tools (model tools &key defer-loading-p options)
  (list-json-array
   (loop for tool in tools
         collect
         (let* ((supports-strict
                  (if (member :supports-strict-mode options :test #'eq)
                      (getf options :supports-strict-mode)
                      (model-compat-value model :supports-strict-mode nil)))
                (supports-grammar
                  (if (member :supports-openai-grammar-tools options :test #'eq)
                      (getf options :supports-openai-grammar-tools)
                      (model-compat-value model :supports-openai-grammar-tools nil)))
                ;; Baseline convertResponsesTools: options.strict defaults
                ;; to false; a JSON null is passed through as :null.
                (default-strict
                  (if (member :strict options :test #'eq)
                      (getf options :strict)
                      nil))
                (grammar
                  (resolve-grammar-constrained-sampling tool supports-grammar)))
           (if grammar
               (let ((encoded
                       (json-object
                        "type" "custom"
                        "name" (tool-name tool)
                        "description" (tool-description tool)
                        "format"
                        (json-object
                         "type" "grammar"
                         "syntax"
                         (string-downcase
                          (symbol-name (getf grammar :format)))
                         "definition" (getf grammar :definition)))))
                 (when defer-loading-p
                   (json-put encoded "defer_loading" t))
                 encoded)
               (let* ((constrained-strict
                        ;; Called unconditionally, as in the baseline: a
                        ;; "require" tool errors even when strict mode is
                        ;; unsupported and no strict flag is emitted.
                        (resolve-json-schema-strict-sampling
                         tool supports-strict))
                      (strict
                        (if (eq constrained-strict t) t default-strict))
                      (encoded
                        (json-object
                         "type" "function"
                         "name" (tool-name tool)
                         "description" (tool-description tool)
                         "parameters"
                         (get-json-schema-tool-parameters
                          tool (eq strict t)))))
                 (when supports-strict
                   (json-put encoded "strict" strict))
                 (when defer-loading-p
                   (json-put encoded "defer_loading" t))
                 encoded))))))

(defun responses-session-affinity-format (model)
  (model-compat-value
   model :session-affinity-format
   (if (or (eq (model-provider model) :openrouter)
           (search "openrouter.ai" (model-base-url model)))
       :openrouter
       :openai)))

(defun responses-session-headers (model session-id cache-retention)
  (when (and (non-empty-string-p session-id)
             (not (eq (normalize-cache-retention cache-retention)
                      :none)))
    (case (responses-session-affinity-format model)
      (:openrouter
       `(("x-session-id" . ,session-id)))
      (:openai-nosession
       `(("x-client-request-id" . ,session-id)))
      (otherwise
       `(("session_id" . ,session-id)
         ("x-client-request-id" . ,session-id))))))

(defun add-responses-reasoning (payload model reasoning)
  (when (model-reasoning-p model)
    (cond
      (reasoning
       (json-put
        payload "reasoning"
        (json-object
         "effort"
         (or (model-thinking-level-value model reasoning)
             (string-downcase (symbol-name reasoning)))
         "summary" "auto"))
       (json-put
        payload "include"
        (json-array "reasoning.encrypted_content")))
      ((or (not (model-thinking-level-present-p model :off))
           (model-thinking-level-value model :off))
       (json-put
        payload "reasoning"
        (json-object
         "effort"
         (or (model-thinking-level-value model :off)
             "none"))))))
  payload)

(defmethod build-request ((provider openai-provider)
                          model context
                          &key stream-p max-tokens temperature reasoning
                            cache-retention session-id tool-choice metadata
                            &allow-other-keys)
  (declare (ignore metadata))
  (ensure-supported-content model context)
  (let* ((oauth-token (provider-oauth-access-token provider))
         (key (or oauth-token (require-api-key provider)))
         (account-id (provider-oauth-account-id provider))
         (deferred-tools-mode
           ;; Baseline buildParams: additional-tools beats tool-search.
           (cond
             ((model-compat-value model :supports-additional-tools nil)
              :additional-tools)
             ((model-compat-value model :supports-tool-search nil)
              :tool-search)
             (t nil)))
         (supports-grammar
           (model-compat-value model :supports-openai-grammar-tools nil))
         (grammar-properties
           (create-grammar-tool-input-properties
            (context-tools context) supports-grammar))
         (immediate-tools nil)
         (deferred-tools nil)
         (payload
           (json-object
            "model" (model-id model)
            "stream" (and stream-p t)
            "store" nil)))
    (multiple-value-setq (immediate-tools deferred-tools)
      (split-deferred-tools context (not (null deferred-tools-mode))))
    (json-put
     payload "input"
     (openai-input-items
      model context
      :grammar-properties grammar-properties
      :deferred-tools deferred-tools
      :deferred-tools-mode deferred-tools-mode
      :tool-options
      (list
       :supports-strict-mode
       (model-compat-value model :supports-strict-mode nil)
       :supports-openai-grammar-tools supports-grammar)))
    (let* ((retention
             (normalize-cache-retention cache-retention))
           (explicit-p
             (model-compat-value
              model :supports-explicit-prompt-cache-mode nil))
           (long-p
             (model-compat-value
              model :supports-long-cache-retention t)))
      (unless (eq retention :none)
        (let ((cache-key
                (clamp-openai-cache-key session-id)))
          (when cache-key
            (json-put payload "prompt_cache_key" cache-key))))
      (cond
        (explicit-p
         (cond
           ((eq retention :none)
            (json-put payload "prompt_cache_options"
                      (json-object "mode" "explicit")))
           ((and (eq retention :long) long-p)
            (json-put payload "prompt_cache_options"
                      (json-object "ttl" "30m")))))
        ((and (eq retention :long) long-p)
         (json-put payload "prompt_cache_retention" "24h"))))
    (when (and max-tokens
               (model-compat-value
                model :supports-max-output-tokens t))
      (json-put payload "max_output_tokens" (max 16 max-tokens)))
    (when (not (null temperature))
      (json-put payload "temperature" temperature))
    (when immediate-tools
      (json-put payload "tools"
                (openai-tools model immediate-tools)))
    (when tool-choice
      (json-put payload "tool_choice" tool-choice))
    (add-responses-reasoning payload model reasoning)
    (make-request-spec
     :url
     (let ((base (strip-trailing-slash (model-base-url model))))
       (if oauth-token
           (cond
             ((uiop:string-suffix-p base "/codex/responses")
              base)
             ((uiop:string-suffix-p base "/codex")
              (concatenate 'string base "/responses"))
             (t
              (concatenate 'string base "/codex/responses")))
           (if (uiop:string-suffix-p base "/v1")
               (concatenate 'string base "/responses")
               (concatenate 'string base "/v1/responses"))))
     :headers
     (append
      `(("content-type" . "application/json")
        ("accept" . ,(if stream-p
                         "text/event-stream"
                         "application/json"))
        ("authorization" . ,(format nil "Bearer ~A" key)))
      (when oauth-token
        (unless (non-empty-string-p account-id)
          (error 'authentication-error
                 :message
                 "OpenAI OAuth credential is missing account ID"))
        `(("chatgpt-account-id" . ,account-id)
          ("originator" . ,+openai-originator+)
          ("openai-beta" . "responses=experimental")))
      (responses-session-headers model session-id cache-retention)
      (model-headers model))
     :payload payload
     :stream-p stream-p
     :provider :openai)))

(defun parse-openai-output (output)
  (loop for item across (or output #())
        for type = (json-get item "type")
        append
        (cond
          ((string= type "message")
           (loop for block across (or (json-get item "content") #())
                 for block-type = (json-get block "type")
                 when (member block-type '("output_text" "refusal")
                              :test #'string=)
                   collect (make-text-content
                            :text (or (json-get block "text")
                                      (json-get block "refusal")
                                      "")
                            :signature (json-get item "id"))))
          ((string= type "reasoning")
           (list
            (make-thinking-content
             :thinking
             (format nil "~{~A~^~%~}"
                     (loop for summary across
                             (or (json-get item "summary") #())
                           collect (or (json-get summary "text") "")))
             :signature (stringify-json item))))
          ((string= type "function_call")
           (list
            (make-tool-call
             :id (format nil "~A|~A"
                         (or (json-get item "call_id") "")
                         (or (json-get item "id") ""))
             :name (or (json-get item "name") "")
             :arguments
             (let ((arguments (json-get item "arguments")))
               (if (non-empty-string-p arguments)
                   (parse-json-with-repair arguments)
                   (json-object)))
             :namespace (json-get item "namespace"))))
          (t nil))))

(defun update-openai-usage (message usage)
  (when (hash-table-p usage)
    (let* ((input-details (json-get usage "input_tokens_details"))
           (output-details (json-get usage "output_tokens_details"))
           (cached (or (json-get input-details "cached_tokens") 0))
           (cache-write
             (or (json-get input-details "cache_write_tokens") 0))
           (input (or (json-get usage "input_tokens") 0)))
      (update-message-usage
       message
       (max 0 (- input cached cache-write))
       (json-get usage "output_tokens")
       cached
       cache-write
       (json-get output-details "reasoning_tokens")
       (json-get usage "total_tokens"))
      (apply-known-model-cost message))))

(defmethod parse-complete-response ((provider openai-provider)
                                    model response)
  (declare (ignore provider))
  (let* ((raw-stop (or (json-get response "status") "completed"))
         (message
           (make-assistant-message
            :content (parse-openai-output (json-get response "output"))
            :api (model-api model)
            :provider (model-provider model)
            :model (model-id model)
            :response-id (json-get response "id")
            :raw-stop-reason raw-stop
            :stop-reason (map-simple-stop-reason raw-stop))))
    (update-openai-usage message (json-get response "usage"))
    (when (and (eq :stop (assistant-message-stop-reason message))
               (tool-call-present-p message))
      (setf (assistant-message-stop-reason message) :tool-use))
    message))

(defun openai-stream-block (state output-index)
  (let ((entry
          (gethash output-index
                   (provider-stream-state-block-indices state))))
    (if (consp entry)
        (values (cdr entry) (car entry))
        (values nil nil))))

(defun create-openai-stream-block (state item output-index emit)
  (let* ((message (provider-stream-state-message state))
         (type (json-get item "type"))
         (block
           (cond
             ((string= type "message")
              (make-text-content))
             ((string= type "reasoning")
              (make-thinking-content))
             ((string= type "function_call")
              (make-tool-call
               :id (format nil "~A|~A"
                           (or (json-get item "call_id") "")
                           (or (json-get item "id") ""))
               :name (or (json-get item "name") "")
               :arguments (json-object)
               :namespace (json-get item "namespace")))
             (t nil))))
    (when block
      (let ((content-index (append-content-block message block)))
        (setf (gethash output-index
                       (provider-stream-state-block-indices state))
              (cons content-index block))
        (cond
          ((typep block 'text-content)
           (emit-event emit :text-start message
                       :content-index content-index))
          ((typep block 'thinking-content)
           (emit-event emit :thinking-start message
                       :content-index content-index))
          ((typep block 'tool-call)
           (setf (gethash output-index
                          (provider-stream-state-partial-json state))
                 (or (json-get item "arguments") ""))
           (emit-event emit :tool-call-start message
                       :content-index content-index)))
        block))))

(defmethod reduce-provider-sse-event ((provider openai-provider)
                                      state event emit)
  (declare (ignore provider))
  (let ((data (sse-event-data event)))
    (when (or (zerop (length data)) (string= data "[DONE]"))
      (return-from reduce-provider-sse-event nil))
    (let* ((payload (parse-json data))
           (type (json-get payload "type"))
           (message (provider-stream-state-message state))
           (output-index (json-get payload "output_index")))
      (cond
        ((string= type "response.created")
         (setf (assistant-message-response-id message)
               (json-get (json-get payload "response") "id")))
        ((string= type "response.output_item.added")
         (create-openai-stream-block state
                                     (json-get payload "item")
                                     output-index
                                     emit))
        ((member type '("response.output_text.delta"
                        "response.refusal.delta")
                 :test #'string=)
         (multiple-value-bind (block content-index)
             (openai-stream-block state output-index)
           (when (typep block 'text-content)
             (let ((delta (or (json-get payload "delta") "")))
               (setf (text-content-text block)
                     (nappend-string
                      (text-content-text block) delta))
               (emit-event emit :text-delta message
                           :content-index content-index
                           :delta delta)))))
        ((member type '("response.reasoning_summary_text.delta"
                        "response.reasoning_text.delta")
                 :test #'string=)
         (multiple-value-bind (block content-index)
             (openai-stream-block state output-index)
           (when (typep block 'thinking-content)
             (let ((delta (or (json-get payload "delta") "")))
               (setf (thinking-content-thinking block)
                     (nappend-string
                      (thinking-content-thinking block) delta))
               (emit-event emit :thinking-delta message
                           :content-index content-index
                           :delta delta)))))
        ((string= type "response.reasoning_summary_part.done")
         (multiple-value-bind (block content-index)
             (openai-stream-block state output-index)
           (when (typep block 'thinking-content)
             (let ((delta (format nil "~%~%")))
               (setf (thinking-content-thinking block)
                     (nappend-string
                      (thinking-content-thinking block) delta))
               (emit-event emit :thinking-delta message
                           :content-index content-index
                           :delta delta)))))
        ((string= type "response.function_call_arguments.delta")
         (multiple-value-bind (block content-index)
             (openai-stream-block state output-index)
           (when (typep block 'tool-call)
             (let ((delta (or (json-get payload "delta") "")))
               (setf (gethash
                      output-index
                      (provider-stream-state-partial-json state))
                     (nappend-string
                      (gethash
                       output-index
                       (provider-stream-state-partial-json state)
                       "")
                      delta))
               (emit-event emit :tool-call-delta message
                           :content-index content-index
                           :delta delta)))))
        ((string= type "response.function_call_arguments.done")
         (multiple-value-bind (block content-index)
             (openai-stream-block state output-index)
           (when (typep block 'tool-call)
             (let* ((arguments
                      (or (json-get payload "arguments") ""))
                    (previous
                      (gethash
                       output-index
                       (provider-stream-state-partial-json state)
                       "")))
               (setf
                (gethash
                 output-index
                 (provider-stream-state-partial-json state))
                arguments
                (tool-call-arguments block)
                (parse-streaming-json arguments))
               (when
                   (and
                    (uiop:string-prefix-p previous arguments)
                    (< (length previous) (length arguments)))
                 (emit-event
                  emit :tool-call-delta message
                  :content-index content-index
                  :delta (subseq arguments (length previous))))))))
        ((string= type "response.output_item.done")
         (let ((item (json-get payload "item")))
           (multiple-value-bind (block content-index)
               (openai-stream-block state output-index)
             (unless block
               (setf block
                     (create-openai-stream-block state
                                                 item
                                                 output-index
                                                 emit))
               (setf content-index
                     (car
                      (gethash
                       output-index
                       (provider-stream-state-block-indices state)))))
             (cond
               ((typep block 'text-content)
                (let ((blocks (json-get item "content")))
                  (when (and (vectorp blocks) (plusp (length blocks)))
                    (setf (text-content-text block)
                          (or (json-get (aref blocks 0) "text")
                              (json-get (aref blocks 0) "refusal")
                              (text-content-text block)))))
                (setf (text-content-signature block)
                      (json-get item "id"))
                (emit-event emit :text-end message
                            :content-index content-index
                            :content (text-content-text block)))
               ((typep block 'thinking-content)
                (let* ((summary
                         (json-get item "summary"))
                       (content
                         (json-get item "content"))
                       (summary-text
                         (and
                          (vectorp summary)
                          (format
                           nil "~{~A~^~%~%~}"
                           (loop for part across summary
                                 collect
                                 (or (json-get part "text") "")))))
                       (content-text
                         (and
                          (vectorp content)
                          (format
                           nil "~{~A~^~%~%~}"
                           (loop for part across content
                                 collect
                                 (or (json-get part "text") ""))))))
                  (cond
                    ((and summary-text
                          (plusp (length summary-text)))
                     (setf (thinking-content-thinking block)
                           summary-text))
                    ((and content-text
                          (plusp (length content-text)))
                     (setf (thinking-content-thinking block)
                           content-text))))
                (setf (thinking-content-signature block)
                      (stringify-json item))
                (emit-event emit :thinking-end message
                            :content-index content-index
                            :content
                            (thinking-content-thinking block)))
               ((typep block 'tool-call)
                (let ((arguments
                        (or (json-get item "arguments")
                            (gethash
                             output-index
                             (provider-stream-state-partial-json state)
                             ""))))
                  (when (non-empty-string-p arguments)
                    (setf (tool-call-arguments block)
                          (parse-streaming-json arguments)))
                  (let ((namespace (json-get item "namespace")))
                    (when namespace
                      (setf (tool-call-namespace block) namespace))))
                (emit-event emit :tool-call-end message
                            :content-index content-index
                            :tool-call block))))))
        ((member type '("response.completed" "response.incomplete")
                 :test #'string=)
         (let* ((response (json-get payload "response"))
                (status (or (json-get response "status")
                            (if (string= type "response.completed")
                                "completed"
                                "incomplete"))))
           (setf (provider-stream-state-terminal-p state) t
                 (assistant-message-response-id message)
                 (or (json-get response "id")
                     (assistant-message-response-id message))
                 (assistant-message-raw-stop-reason message) status
                 (assistant-message-stop-reason message)
                 (map-simple-stop-reason status))
           ;; Baseline mapCodexEvents: preserve the provider's end_turn
           ;; indication (only Codex sends it).
           (when (json-present-p response "end_turn")
             (setf (assistant-message-end-turn message)
                   (eq (json-get response "end_turn") t)))
           (update-openai-usage message (json-get response "usage"))
           (when (and (eq :stop
                          (assistant-message-stop-reason message))
                      (tool-call-present-p message))
             (setf (assistant-message-stop-reason message) :tool-use))))
        ((string= type "response.failed")
         (setf (provider-stream-state-terminal-p state) t)
         (let* ((response (json-get payload "response"))
                (error-object (json-get response "error")))
           (error 'api-error
                  :provider :openai
                  :status 200
                  :message (or (json-get error-object "message")
                               "OpenAI response failed"))))
        ((string= type "error")
         (error 'api-error
                :provider :openai
                :status 200
                :message (or (json-get payload "message")
                             "OpenAI stream error")))))
  nil))
