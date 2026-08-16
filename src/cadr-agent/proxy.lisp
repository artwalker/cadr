(in-package #:cadr-agent)

(defun proxy-model-json (model)
  (cadr-ai::json-object
   "id" (cadr-ai:model-id model)
   "name" (cadr-ai::model-name model)
   "provider" (string-downcase (symbol-name (cadr-ai:model-provider model)))
   "api" (string-downcase (symbol-name (cadr-ai:model-api model)))
   "baseUrl" (cadr-ai:model-base-url model)
   "maxTokens" (cadr-ai:model-max-tokens model)
   "contextWindow" (cadr-ai:model-context-window model)
   "supportsImages" (cadr-ai:model-supports-images-p model)
   "supportsTools" (cadr-ai:model-supports-tools-p model)
   "reasoning" (cadr-ai:model-reasoning-p model)
   "thinkingLevelMap" (json-safe-value (cadr-ai::model-thinking-level-map model))
   "headers" (json-safe-value (cadr-ai::model-headers model))
   "compat" (json-safe-value (cadr-ai::model-compat model))))

(defun proxy-context-json (context)
  (cadr-ai::json-object
   "systemPrompt" (cadr-ai:context-system-prompt context)
   "messages" (coerce (mapcar #'message-to-json
                               (cadr-ai:context-messages context))
                       'vector)
   "tools"
   (coerce
    (loop for tool in (cadr-ai:context-tools context)
          collect
          (cadr-ai::json-object
           "name" (cadr-ai:tool-name tool)
           "description" (cadr-ai:tool-description tool)
           "parameters" (cadr-ai:tool-parameters tool)))
    'vector)))

(defun proxy-options-json
    (&key max-tokens temperature reasoning cache-retention session-id headers
          metadata transport thinking-budgets max-retry-delay-ms)
  (let ((result (cadr-ai::json-object)))
    (dolist (entry
             `(("maxTokens" ,max-tokens)
               ("temperature" ,temperature)
               ("reasoning" ,reasoning)
               ("cacheRetention" ,cache-retention)
               ("sessionId" ,session-id)
               ("headers" ,headers)
               ("metadata" ,metadata)
               ("transport" ,transport)
               ("thinkingBudgets" ,thinking-budgets)
               ("maxRetryDelayMs" ,max-retry-delay-ms)))
      (when (second entry)
        (cadr-ai::json-put result (first entry)
                           (json-safe-value (second entry)))))
    result))

(defun ensure-proxy-content-index (message index block)
  (let ((content (copy-list (cadr-ai:assistant-message-content message))))
    (loop while (<= (length content) index) do (setf content (nconc content (list nil))))
    (setf (nth index content) block
          (cadr-ai:assistant-message-content message) content)
    block))

(defun proxy-event-type (object)
  (let ((name (substitute #\- #\_ (cadr-ai::json-get object "type"))))
    (cond
      ((string= name "toolcall-start") :tool-call-start)
      ((string= name "toolcall-delta") :tool-call-delta)
      ((string= name "toolcall-end") :tool-call-end)
      (t (intern (string-upcase name) "KEYWORD")))))

(defun proxy-stop-reason (value)
  (cond
    ((string= value "toolUse") :tool-use)
    (t (intern (string-upcase value) "KEYWORD"))))

(defun apply-proxy-usage (message object)
  (let ((usage (cadr-ai::json-get object "usage")))
    (when (hash-table-p usage)
      (let ((parsed (usage-from-json usage)))
        (when (cadr-ai::json-get usage "totalTokens")
          (setf (cadr-ai:usage-total parsed)
                (cadr-ai::json-get usage "totalTokens")))
        (setf (cadr-ai:assistant-message-usage message) parsed)))))

(defun process-proxy-event (object message partial-json emit)
  (let* ((type (proxy-event-type object))
         (index (cadr-ai::json-get object "contentIndex")))
    (labels ((emit-event (&key delta content tool-call reason)
               (funcall emit
                        (cadr-ai:make-stream-event
                         :type type :content-index index :delta delta
                         :content content :tool-call tool-call
                         :message message :reason reason))))
      (case type
        (:start (emit-event))
        (:text-start
         (ensure-proxy-content-index
          message index (cadr-ai:make-text-content :text ""))
         (emit-event))
        (:text-delta
         (let ((block (nth index (cadr-ai:assistant-message-content message)))
               (delta (cadr-ai::json-get object "delta")))
           (unless (typep block 'cadr-ai:text-content)
             (error "Received text_delta for non-text content"))
           (setf (cadr-ai:text-content-text block)
                 (concatenate 'string (cadr-ai:text-content-text block) delta))
           (emit-event :delta delta)))
        (:text-end
         (let ((block (nth index (cadr-ai:assistant-message-content message))))
           (unless (typep block 'cadr-ai:text-content)
             (error "Received text_end for non-text content"))
           (setf (cadr-ai:text-content-signature block)
                 (cadr-ai::json-get object "contentSignature"))
           (emit-event :content (cadr-ai:text-content-text block))))
        (:thinking-start
         (ensure-proxy-content-index
          message index (cadr-ai:make-thinking-content :thinking ""))
         (emit-event))
        (:thinking-delta
         (let ((block (nth index (cadr-ai:assistant-message-content message)))
               (delta (cadr-ai::json-get object "delta")))
           (unless (typep block 'cadr-ai:thinking-content)
             (error "Received thinking_delta for non-thinking content"))
           (setf (cadr-ai:thinking-content-thinking block)
                 (concatenate 'string
                              (cadr-ai:thinking-content-thinking block) delta))
           (emit-event :delta delta)))
        (:thinking-end
         (let ((block (nth index (cadr-ai:assistant-message-content message))))
           (unless (typep block 'cadr-ai:thinking-content)
             (error "Received thinking_end for non-thinking content"))
           (setf (cadr-ai:thinking-content-signature block)
                 (cadr-ai::json-get object "contentSignature"))
           (emit-event :content (cadr-ai:thinking-content-thinking block))))
        (:tool-call-start
         (setf (gethash index partial-json) "")
         (ensure-proxy-content-index
          message index
          (cadr-ai:make-tool-call
           :id (cadr-ai::json-get object "id")
           :name (cadr-ai::json-get object "toolName")
           :arguments (cadr-ai::json-object)))
         (emit-event))
        (:tool-call-delta
         (let* ((block (nth index (cadr-ai:assistant-message-content message)))
                (delta (cadr-ai::json-get object "delta"))
                (partial (concatenate 'string (gethash index partial-json "") delta)))
           (unless (typep block 'cadr-ai:tool-call)
             (error "Received toolcall_delta for non-toolCall content"))
           (setf (gethash index partial-json) partial
                 (cadr-ai:tool-call-arguments block)
                 (cadr-ai::parse-partial-json-object partial))
           (emit-event :delta delta)))
        (:tool-call-end
         (let ((block (nth index (cadr-ai:assistant-message-content message))))
           (when (typep block 'cadr-ai:tool-call)
             (let ((final (cadr-ai::json-get object "toolCall")))
               (when (hash-table-p final)
                 ;; Baseline proxy.ts: Object.assign(content, toolCall) —
                 ;; only keys present on the wire replace the partial.
                 (setf (cadr-ai:tool-call-id block)
                       (or (cadr-ai::json-get final "id") "")
                       (cadr-ai:tool-call-name block)
                       (or (cadr-ai::json-get final "name") "")
                       (cadr-ai:tool-call-arguments block)
                       (or (cadr-ai::json-get final "arguments")
                           (cadr-ai::json-object)))
                 (when (cadr-ai::json-present-p final "thoughtSignature")
                   (setf (cadr-ai:tool-call-thought-signature block)
                         (cadr-ai::json-get final "thoughtSignature")))
                 (when (cadr-ai::json-present-p final "namespace")
                   (setf (cadr-ai:tool-call-namespace block)
                         (cadr-ai::json-get final "namespace")))))
             (remhash index partial-json)
             (emit-event :tool-call block))))
        (:done
         (let ((reason (proxy-stop-reason (cadr-ai::json-get object "reason"))))
           (setf (cadr-ai:assistant-message-stop-reason message) reason)
           (apply-proxy-usage message object)
           (emit-event :reason reason)))
        (:error
         (let ((reason (proxy-stop-reason (cadr-ai::json-get object "reason"))))
           (setf (cadr-ai:assistant-message-stop-reason message) reason
                 (cadr-ai:assistant-message-error-message message)
                 (cadr-ai::json-get object "errorMessage"))
           (apply-proxy-usage message object)
           (emit-event :reason reason)))))))

(defun stream-proxy
    (model context on-event
     &key auth-token proxy-url abort-p max-tokens temperature reasoning
       cache-retention session-id headers metadata transport thinking-budgets
       max-retry-delay-ms (request-sse-function #'cadr-ai:request-sse))
  (unless (and (stringp auth-token) (plusp (length auth-token)))
    (error "Proxy auth token is required"))
  (unless (and (stringp proxy-url) (plusp (length proxy-url)))
    (error "Proxy URL is required"))
  (let ((message
          (cadr-ai:make-assistant-message
           :api (cadr-ai:model-api model)
           :provider (cadr-ai:model-provider model)
           :model (cadr-ai:model-id model)))
        (partial-json (make-hash-table)))
    (handler-case
        (progn
          (funcall
           request-sse-function
           (cadr-ai::make-request-spec
            :url (format nil "~A/api/stream" (string-right-trim "/" proxy-url))
            :method :post
            :headers
            (list (cons "Authorization" (format nil "Bearer ~A" auth-token))
                  (cons "Content-Type" "application/json"))
            :payload
            (cadr-ai::json-object
             "model" (proxy-model-json model)
             "context" (proxy-context-json context)
             "options"
             (proxy-options-json
              :max-tokens max-tokens :temperature temperature
              :reasoning reasoning :cache-retention cache-retention
              :session-id session-id :headers headers :metadata metadata
              :transport transport :thinking-budgets thinking-budgets
              :max-retry-delay-ms max-retry-delay-ms))
            :stream-p t :stream-format :sse :provider :proxy)
           (lambda (event)
             (when (and abort-p (funcall abort-p))
               (error 'cadr-ai:request-aborted :message "Request aborted by user"))
             (let ((data (cadr-ai:sse-event-data event)))
               (when (plusp (length data))
                 (process-proxy-event
                  (cadr-ai::parse-json data) message partial-json on-event))))
           :abort-p abort-p)
          message)
      (error (condition)
        (let ((reason (if (or (typep condition 'cadr-ai:request-aborted)
                              (and abort-p (ignore-errors (funcall abort-p))))
                          :aborted :error)))
          (setf (cadr-ai:assistant-message-stop-reason message) reason
                (cadr-ai:assistant-message-error-message message)
                (if (eq reason :aborted)
                    "Request aborted by user"
                    (princ-to-string condition)))
          (funcall on-event
                   (cadr-ai:make-stream-event
                    :type :error :message message :reason reason))
          message)))))
