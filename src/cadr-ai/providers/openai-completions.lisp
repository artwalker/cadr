(in-package #:cadr-ai)

(defun chat-completions-url (base-url)
  (let ((base (strip-trailing-slash base-url)))
    (cond
      ((or (uiop:string-suffix-p base "/chat/completions")
           (uiop:string-suffix-p base "/v1/chat/completions"))
       base)
      ((uiop:string-suffix-p base "/v1")
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

(defun completions-developer-role-p (model)
  (model-compat-value
   model :supports-developer-role
   (let ((base (model-base-url model)))
     (and (not (search "deepseek.com" base))
          (not (member
                (model-provider model)
                '(:ant-ling :cerebras :deepseek :moonshotai
                  :moonshotai-cn :together)
                :test #'eq))))))

(defun deferred-tool-names (messages)
  (let ((names (make-hash-table :test #'equal)))
    (dolist (message messages)
      (when (typep message 'tool-result-message)
        (dolist (name (tool-result-message-added-tool-names message))
          (setf (gethash name names) t))))
    names))

(defun openai-chat-messages
    (model context &key (normalize-id #'normalize-provider-id)
                       deferred-tools-mode)
  (let ((messages nil)
        (loaded-tool-names (make-hash-table :test #'equal)))
    (when (non-empty-string-p (context-system-prompt context))
      (push
       (json-object "role"
                    (if (and (model-reasoning-p model)
                             (completions-developer-role-p model))
                        "developer"
                        "system")
                    "content" (context-system-prompt context))
       messages))
    (dolist
        (message
         (prepare-messages-for-model
          (context-messages context)
          model
          normalize-id))
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
            messages))
         (when (eq deferred-tools-mode :kimi)
           (let ((loaded nil))
             (dolist (name (tool-result-message-added-tool-names message))
               (let ((tool
                       (find name (context-tools context)
                             :key #'tool-name :test #'string=)))
                 (when (and tool (not (gethash name loaded-tool-names)))
                   (setf (gethash name loaded-tool-names) t)
                   (push tool loaded))))
             (when loaded
               (push
                (json-object
                 "role" "system"
                 "tools" (openai-chat-tools model (nreverse loaded)))
                messages)))))))
    (list-json-array (nreverse messages))))

(defun completions-strict-mode-p (model)
  (model-compat-value
   model :supports-strict-mode
   (not
    (member (model-provider model)
            '(:minimax :minimax-cn :moonshotai :moonshotai-cn
              :together)
            :test #'eq))))

(defun openai-chat-tools (model tools)
  (list-json-array
   (loop for tool in tools
         collect
         (let ((grammar
                 (resolve-grammar-constrained-sampling
                  tool
                  (model-compat-value
                   model :supports-openai-grammar-tools nil))))
           (if grammar
               (json-object
                "type" "custom"
                "custom"
                (json-object
                 "name" (tool-name tool)
                 "description" (tool-description tool)
                 "format"
                 (json-object
                  "type" "grammar"
                  "grammar"
                  (json-object
                   "syntax"
                   (string-downcase
                    (symbol-name (getf grammar :format)))
                   "definition" (getf grammar :definition)))))
               (json-object
                "type" "function"
                "function"
                (let* ((supports-strict (completions-strict-mode-p model))
                       ;; Baseline openai-completions.ts convertTools:
                       ;; resolve throws on a "require" mismatch; strict
                       ;; tools send the strictified schema.
                       (strict
                         (resolve-json-schema-strict-sampling
                          tool supports-strict))
                       (function
                         (json-object
                          "name" (tool-name tool)
                          "description" (tool-description tool)
                          "parameters"
                          (get-json-schema-tool-parameters tool strict))))
                  (when supports-strict
                    (json-put function "strict" (eq strict t)))
                  function)))))))

(defun completions-provider-match-p (model providers fragments)
  (or (member (model-provider model) providers :test #'eq)
      (some (lambda (fragment)
              (search fragment (model-base-url model)))
            fragments)))

(defun completions-max-tokens-field (model)
  (or (model-compat-value model :max-tokens-field nil)
      (if (completions-provider-match-p
           model
           '(:ant-ling :deepseek :minimax :minimax-cn :moonshotai
             :moonshotai-cn :together)
           '("api.ant-ling.com" "api.moonshot." "api.together."
             "deepseek.com"))
          :max-tokens
          :max-completion-tokens)))

(defun completions-supports-store-p (model)
  (model-compat-value
   model :supports-store
   (not
    (completions-provider-match-p
     model
     '(:ant-ling :cerebras :deepseek :minimax :minimax-cn
       :moonshotai :moonshotai-cn :together)
     '("cerebras.ai" "deepseek.com" "api.ant-ling.com"
       "api.moonshot." "api.together.")))))

(defun completions-thinking-format (model)
  (or (model-compat-value model :thinking-format nil)
      (cond
        ((eq (model-provider model) :deepseek) :deepseek)
        ((eq (model-provider model) :together) :together)
        ((eq (model-provider model) :ant-ling) :ant-ling)
        (t :openai))))

(defun completions-supports-reasoning-effort-p (model)
  (model-compat-value
   model :supports-reasoning-effort
   (not
    (member (model-provider model)
            '(:ant-ling :minimax :minimax-cn :moonshotai
              :moonshotai-cn :together)
            :test #'eq))))

(defun openai-reasoning-value (model reasoning)
  (or (and reasoning
           (model-thinking-level-value model reasoning))
      (and reasoning
           (string-downcase (symbol-name reasoning)))))

(defun resolve-chat-template-args (model reasoning values)
  ;; pi@53fa77ccd api/openai-completions.ts:892-940 — each entry
  ;; resolves a scalar verbatim or a $var reference to the current
  ;; thinking state; omitWhenOff drops the entry with no reasoning
  ;; active; an empty result omits the request field entirely.
  (let ((resolved (json-object)))
    (dolist (entry values)
      (let* ((value (cdr entry))
             (resolved-value
               (if (and (consp value) (eq (car value) :var))
                   (let ((var (getf value :var))
                         (omit-when-off
                           (getf value :omit-when-off)))
                     (cond
                       ((and (null reasoning) omit-when-off)
                        :omit)
                       ((string= var "thinking.enabled")
                        (not (null reasoning)))
                       (t
                        ;; thinking.effort: the level map wins; a
                        ;; missing map entry falls back to the
                        ;; requested level name; nothing is sent when
                        ;; reasoning is off without an off mapping.
                        (let ((mapped
                                (if reasoning
                                    (model-thinking-level-value
                                     model reasoning)
                                    (model-thinking-level-value
                                     model :off))))
                          (cond
                            ((stringp mapped) mapped)
                            (reasoning
                             (string-downcase
                              (symbol-name reasoning)))
                            (t :omit))))))
                   value)))
        (unless (eq resolved-value :omit)
          (json-put resolved (car entry) resolved-value))))
    (when (plusp (hash-table-count resolved))
      resolved)))

(defun add-completions-reasoning (payload model reasoning)
  (when (model-reasoning-p model)
    (case (completions-thinking-format model)
      (:qwen
       (json-put payload "enable_thinking" (not (null reasoning)))
       (when (and reasoning
                  (completions-supports-reasoning-effort-p model))
         (json-put payload "reasoning_effort"
                   (openai-reasoning-value model reasoning))))
      (:deepseek
       (when (or reasoning
                 (not (and
                       (model-thinking-level-present-p model :off)
                       (null
                        (model-thinking-level-value model :off)))))
         (json-put payload "thinking"
                   (json-object "type"
                                (if reasoning "enabled" "disabled"))))
       (when (and reasoning
                  (completions-supports-reasoning-effort-p model))
         (json-put payload "reasoning_effort"
                   (openai-reasoning-value model reasoning))))
      (:zai
       (json-put
        payload "thinking"
        (if reasoning
            (json-object "type" "enabled"
                         "clear_thinking" nil)
            (json-object "type" "disabled")))
       (when (and reasoning
                  (completions-supports-reasoning-effort-p model))
         (let ((effort
                 (openai-reasoning-value model reasoning)))
           (when (stringp effort)
             (json-put payload "reasoning_effort" effort)))))
      (:openrouter
       (cond
         (reasoning
          (json-put
           payload "reasoning"
           (json-object
            "effort"
            (openai-reasoning-value model reasoning))))
         ((or
           (not (model-thinking-level-present-p model :off))
           (model-thinking-level-value model :off))
          (json-put
           payload "reasoning"
           (json-object
            "effort"
            (or (model-thinking-level-value model :off)
                "none"))))))
      (:together
       (json-put payload "reasoning"
                 (json-object "enabled" (not (null reasoning))))
       (when (and reasoning
                  (completions-supports-reasoning-effort-p model))
         (json-put payload "reasoning_effort"
                   (openai-reasoning-value model reasoning))))
      (:ant-ling
       (let ((effort
               (and reasoning
                    (model-thinking-level-value model reasoning))))
         (when (stringp effort)
           (json-put payload "reasoning"
                     (json-object "effort" effort)))))
      (:string-thinking
       (let ((value
               (if reasoning
                   (openai-reasoning-value model reasoning)
                   (model-thinking-level-value model :off))))
         (when (stringp value)
           (json-put payload "thinking" value))))
      (:baseten
       ;; pi@53fa77ccd api/openai-completions.ts:779-793 — chat
       ;; template args carry the thinking toggle, and reasoning_effort
       ;; follows only when the model supports it.
       (let ((args
               (resolve-chat-template-args
                model reasoning
                (model-compat-value
                 model :chat-template-args nil))))
         (when args
           (json-put payload "chat_template_args" args)))
       (when (completions-supports-reasoning-effort-p model)
         (let ((effort
                 (if reasoning
                     (openai-reasoning-value model reasoning)
                     (model-thinking-level-value model :off))))
           (when (stringp effort)
             (json-put payload "reasoning_effort" effort)))))
      (otherwise
       (cond
         ((and reasoning
               (completions-supports-reasoning-effort-p model))
          (json-put payload "reasoning_effort"
                    (openai-reasoning-value model reasoning)))
         ((and (null reasoning)
               (completions-supports-reasoning-effort-p model))
          (let ((off
                  (model-thinking-level-value model :off)))
            (when (stringp off)
              (json-put payload "reasoning_effort" off))))))))
  payload)

(defun completions-session-headers (model session-id cache-retention)
  (when (and (non-empty-string-p session-id)
             (not (eq (normalize-cache-retention cache-retention)
                      :none))
             (model-compat-value
              model :send-session-affinity-headers nil))
    (case (model-compat-value
           model :session-affinity-format :openai)
      (:openrouter
       `(("x-session-id" . ,session-id)))
      (:openai-nosession
       `(("x-client-request-id" . ,session-id)
         ("x-session-affinity" . ,session-id)))
      (otherwise
       `(("session_id" . ,session-id)
         ("x-client-request-id" . ,session-id)
         ("x-session-affinity" . ,session-id))))))

(defmethod build-request ((provider openai-completions-provider)
                          model context
                          &key stream-p max-tokens temperature reasoning
                            cache-retention session-id tool-choice metadata)
  (declare (ignore metadata))
  (ensure-supported-content model context)
  (let* ((token (provider-bearer-token provider))
         (deferred-mode
           (model-compat-value model :deferred-tools-mode nil))
         (deferred-names
           (and (eq deferred-mode :kimi)
                (deferred-tool-names (context-messages context))))
         (active-tools
           (if deferred-names
               (remove-if
                (lambda (tool) (gethash (tool-name tool) deferred-names))
                (context-tools context))
               (context-tools context)))
         (payload
           (json-object
            "model" (model-id model)
            "messages"
            (openai-chat-messages
             model context :deferred-tools-mode deferred-mode)
            "stream" (and stream-p t))))
    (when (and stream-p
               (model-compat-value
                model :supports-usage-in-streaming t))
      (json-put payload "stream_options"
                (json-object "include_usage" t)))
    (when max-tokens
      (json-put payload
                (if (eq (completions-max-tokens-field model)
                        :max-tokens)
                    "max_tokens"
                    "max_completion_tokens")
                max-tokens))
    (when (not (null temperature))
      (json-put payload "temperature" temperature))
    (when (completions-supports-store-p model)
      (json-put payload "store" nil))
    (when active-tools
      (json-put payload "tools"
                (openai-chat-tools model active-tools)))
    (when tool-choice
      (json-put payload "tool_choice" tool-choice))
    (add-completions-reasoning payload model reasoning)
    ;; pi@53fa77ccd api/openai-completions.ts:847-866 — vLLM caps
    ;; reasoning with a top-level thinking_token_budget, independent of
    ;; thinkingFormat; reasoning and the answer share max_tokens, so an
    ;; uncapped reasoning phase can consume the whole response.  The
    ;; budget always leaves MIN_ANSWER_TOKENS (1024) for the answer.
    (when (and (model-compat-value
                model :supports-thinking-token-budget nil)
               reasoning
               (model-reasoning-p model))
      (let* ((level
               (if (member reasoning '(:xhigh :max))
                   :high reasoning))
             (budget
               (case level
                 (:minimal 1024)
                 (:low 2048)
                 (:medium 8192)
                 (otherwise 16384)))
             (ceiling
               (or max-tokens
                   (model-max-tokens model)))
             (capped
               (min budget (max 0 (- ceiling 1024)))))
        (when (plusp capped)
          (json-put payload "thinking_token_budget" capped))))
    (let ((retention
            (normalize-cache-retention cache-retention))
          (supports-long
            (model-compat-value
             model :supports-long-cache-retention t)))
      (when (or (and (search "api.openai.com"
                             (model-base-url model))
                     (not (eq retention :none)))
                (and (eq retention :long) supports-long))
        (let ((cache-key
                (clamp-openai-cache-key session-id)))
          (when cache-key
            (json-put payload "prompt_cache_key" cache-key))))
      (when (and (eq retention :long) supports-long)
        (json-put payload "prompt_cache_retention" "24h")))
    (make-request-spec
     :url (chat-completions-url (model-base-url model))
     :headers
     (append
      `(("content-type" . "application/json")
        ("accept" . ,(if stream-p
                         "text/event-stream"
                         "application/json")))
      (when token
        `(("authorization" . ,(format nil "Bearer ~A" token))))
      (completions-session-headers
       model session-id cache-retention)
      (model-headers model))
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
         (parse-json-with-repair arguments)
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
            :response-model
            (let ((response-model
                    (json-get response "model")))
              (and (non-empty-string-p response-model)
                   (not (string=
                         response-model (model-id model)))
                   response-model))
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
  (when (and (stringp delta)
             (plusp (length delta)))
    (multiple-value-bind (block index)
        (chat-stream-block state key type emit)
      (ecase type
        (:text
         (setf (text-content-text block)
               (nappend-string
                (text-content-text block) delta)))
        (:thinking
         (setf (thinking-content-thinking block)
               (nappend-string
                (thinking-content-thinking block) delta))))
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
         (nappend-string
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
                   (parse-streaming-json json)
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
        (let ((response-model
                (json-get payload "model")))
          (when (and (non-empty-string-p response-model)
                     (not (string=
                           response-model
                           (assistant-message-model message))))
            (setf
             (assistant-message-response-model message)
             response-model)))
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

(defmethod finalize-provider-stream
    ((provider openai-completions-provider)
     model state emit)
  (declare (ignore provider))
  (unless
      (or
       (provider-stream-state-terminal-p state)
       (model-compat-value
        model :supports-finish-reason t))
    (finish-chat-stream-blocks state emit)
    (let ((message
            (provider-stream-state-message state)))
      (setf
       (assistant-message-stop-reason message)
       (if (tool-call-present-p message)
           :tool-use
           :stop)
       (provider-stream-state-terminal-p state) t)))
  nil)
