(in-package #:cadr-ai)

(defun non-blank-string-p (value)
  (and (stringp value)
       (plusp
        (length
         (string-trim
          '(#\Space #\Tab #\Return #\Linefeed)
          value)))))

(defun bedrock-model-candidates (model)
  (loop for value in (list (model-id model)
                           (model-name model))
        when (non-empty-string-p value)
          append
          (let ((lower (string-downcase value)))
            (list
             lower
             (map 'string
                  (lambda (character)
                    (if (find character " _.:")
                        #\-
                        character))
                  lower)))))

(defun bedrock-candidate-matches-p (model fragments)
  (some
   (lambda (candidate)
     (some
      (lambda (fragment)
        (search fragment candidate))
      fragments))
   (bedrock-model-candidates model)))

(defun bedrock-claude-model-p (model)
  (bedrock-candidate-matches-p
   model
   '("anthropic.claude" "anthropic/claude" "claude")))

(defun bedrock-adaptive-thinking-p (model)
  (bedrock-candidate-matches-p
   model
   '("opus-4-6" "opus-4-7" "opus-4-8" "opus-5"
     "sonnet-4-6" "sonnet-5" "fable-5")))

(defun bedrock-native-xhigh-p (model)
  (bedrock-candidate-matches-p
   model
   '("opus-4-7" "opus-4-8" "opus-5"
     "sonnet-5" "fable-5")))

(defun bedrock-prompt-cache-p (model environment)
  (or
   (string=
    "1"
    (or
     (environment-value
      environment "AWS_BEDROCK_FORCE_CACHE")
     ""))
   (and
    (bedrock-candidate-matches-p model '("claude"))
    (bedrock-candidate-matches-p
     model
     '("fable-5" "opus-5" "sonnet-5"
       "-4-" "claude-3-7-sonnet" "claude-3-5-haiku")))))

(defun bedrock-govcloud-p (model region)
  (or (and (non-empty-string-p region)
           (uiop:string-prefix-p "us-gov-"
                                 (string-downcase region)))
      (uiop:string-prefix-p
       "us-gov." (string-downcase (model-id model)))
      (uiop:string-prefix-p
       "arn:aws-us-gov:" (string-downcase (model-id model)))))

(defun bedrock-effort (model reasoning)
  (cond
    ((and (eq reasoning :xhigh)
          (bedrock-native-xhigh-p model))
     "xhigh")
    ((model-thinking-level-value model reasoning))
    ((member reasoning '(:minimal :low)) "low")
    ((eq reasoning :medium) "medium")
    (t "high")))

(defun bedrock-thinking-fields (model reasoning region options)
  (when (and reasoning
             (model-reasoning-p model)
             (bedrock-claude-model-p model))
    (let ((display
            (unless (bedrock-govcloud-p model region)
              (or (getf options :thinking-display)
                  "summarized"))))
      (if (bedrock-adaptive-thinking-p model)
          (json-object
           "thinking"
           (apply #'json-object
                  (append
                   (list "type" "adaptive")
                   (when display
                     (list "display" display))))
           "output_config"
           (json-object
            "effort" (bedrock-effort model reasoning)))
          (let* ((level
                   (if (member reasoning '(:xhigh :max))
                       :high reasoning))
                 (custom (getf (getf options :thinking-budgets)
                               level))
                 (budget
                   (or custom
                       (case reasoning
                         (:minimal 1024)
                         (:low 2048)
                         (:medium 8192)
                         (otherwise 16384))))
                 (thinking
                   (apply #'json-object
                          (append
                           (list
                            "type" "enabled"
                            "budget_tokens" budget)
                           (when display
                             (list "display" display)))))
                 (result
                   (json-object "thinking" thinking)))
            (when (getf options :interleaved-thinking t)
              (json-put
               result "anthropic_beta"
               (json-array
                "interleaved-thinking-2025-05-14")))
            result)))))

(defun bedrock-image-block (block)
  (let ((subtype
          (second
           (split-on-character
            (image-content-mime-type block) #\/))))
    (unless
        (member subtype '("jpeg" "jpg" "png" "gif" "webp")
                :test #'string-equal)
      (error 'unsupported-content-error
             :message
             (format nil "Unknown image type: ~A"
                     (image-content-mime-type block))))
    (json-object
     "image"
     (json-object
      "format"
      (if (string-equal subtype "jpg") "jpeg" subtype)
      "source"
      (json-object "bytes" (image-content-data block))))))

(defun sanitize-bedrock-document (value)
  ;; Baseline bedrock-converse-stream.ts sanitizeBedrockDocument: Bedrock
  ;; documents reject empty member names; drop them recursively.
  ;; Strings are vectors of characters in CL; keep them atomic.
  (cond
    ((or (stringp value) (null value) (eq t value) (numberp value))
     value)
    ((vectorp value)
     (map 'vector #'sanitize-bedrock-document value))
    ((json-object-p value)
     (let ((result (make-hash-table :test #'equal)))
       (json-map-entries
        value
        (lambda (key nested)
          (when (plusp (length key))
            (setf (gethash key result)
                  (sanitize-bedrock-document nested)))))
       result))
    (t value)))

(defun bedrock-text-blocks (content &key required-p)
  (let ((blocks
          (if (stringp content)
              (and (non-blank-string-p content)
                   (list (json-object "text" content)))
              (loop for block across (coerce content 'vector)
                    when (and
                          (typep block 'text-content)
                          (non-blank-string-p
                           (text-content-text block)))
                      collect
                      (json-object
                       "text" (text-content-text block))
                    when (typep block 'image-content)
                      collect (bedrock-image-block block)))))
    (list-json-array
     (or blocks
         (and required-p
              (list (json-object "text" "<empty>")))))))

(defun bedrock-messages (context model)
  (let ((messages
          (prepare-messages-for-model
           (context-messages context)
           model #'normalize-provider-id))
        (result nil))
    (loop for tail on messages
          for message = (car tail)
          do
          (cond
           ((typep message 'user-message)
            (push
             (json-object
              "role" "user"
              "content"
              (bedrock-text-blocks
               (user-message-content message)
               :required-p t))
             result))
           ((typep message 'assistant-message)
            (let ((blocks
                    (loop for block in
                          (assistant-message-content message)
                          when
                          (and
                           (typep block 'text-content)
                           (non-blank-string-p
                            (text-content-text block)))
                            collect
                            (json-object
                             "text" (text-content-text block))
                          when
                          (and
                           (typep block 'thinking-content)
                           (non-blank-string-p
                            (thinking-content-thinking block)))
                            collect
                            (if
                                (and
                                 (bedrock-claude-model-p model)
                                 (not
                                  (non-empty-string-p
                                   (thinking-content-signature block))))
                                (json-object
                                 "text"
                                 (thinking-content-thinking block))
                                (json-object
                                 "reasoningContent"
                                 (json-object
                                  "reasoningText"
                                  (apply
                                   #'json-object
                                   (append
                                    (list
                                     "text"
                                     (thinking-content-thinking block))
                                    (when
                                        (and
                                         (bedrock-claude-model-p model)
                                         (non-empty-string-p
                                          (thinking-content-signature block)))
                                      (list
                                       "signature"
                                       (thinking-content-signature
                                        block))))))))
                          when (typep block 'tool-call)
                            collect
                            (json-object
                             "toolUse"
                             (json-object
                              "toolUseId" (tool-call-id block)
                              "name" (tool-call-name block)
                              "input"
                              (sanitize-bedrock-document
                               (tool-call-arguments block)))))))
              (when blocks
                (push
                 (json-object
                  "role" "assistant"
                  "content" (list-json-array blocks))
                 result))))
           ((typep message 'tool-result-message)
            (let* ((block
                     (json-object
                      "toolResult"
                      (json-object
                       "toolUseId"
                       (tool-result-message-tool-call-id message)
                       "status"
                       (if (tool-result-message-is-error message)
                           "error" "success")
                       "content"
                       (bedrock-text-blocks
                        (tool-result-message-content message)
                        :required-p t))))
                   (previous (car result))
                   (previous-content
                     (and previous
                          (string= (json-get previous "role") "user")
                          (json-get previous "content")))
                   (tool-result-message-p
                     (and previous-content
                          (plusp (length previous-content))
                          (every
                           (lambda (entry)
                             (json-present-p entry "toolResult"))
                           previous-content))))
              (if tool-result-message-p
                  (json-put
                   previous "content"
                   (concatenate 'vector
                                previous-content
                                (vector block)))
                  (push
                   (json-object
                    "role" "user"
                    "content" (json-array block))
                   result))))))
    (list-json-array (nreverse result))))

(defun bedrock-tools (model tools tool-choice)
  (let ((result
          (json-object
           "tools"
           (list-json-array
            (loop for tool in tools
                  collect
                  (json-object
                   "toolSpec"
                   (let* ((supports-strict
                            (model-compat-value
                             model :supports-strict-mode nil))
                          ;; Baseline bedrock-converse-stream.ts
                          ;; convertToolConfig.
                          (strict
                            (resolve-json-schema-strict-sampling
                             tool supports-strict))
                          (spec
                            (json-object
                             "name" (tool-name tool)
                             "description"
                             (tool-description tool)
                             "inputSchema"
                             (json-object
                              "json"
                              (get-json-schema-tool-parameters
                               tool strict)))))
                     (when (eq strict t)
                       (json-put spec "strict" t))
                     spec)))))))
    (cond
      ((and (stringp tool-choice)
            (string= tool-choice "auto"))
       (json-put result "toolChoice"
                 (json-object "auto" (json-object))))
      ((and (stringp tool-choice)
            (string= tool-choice "any"))
       (json-put result "toolChoice"
                 (json-object "any" (json-object))))
      ((and (listp tool-choice)
            (getf tool-choice :name))
       (json-put
        result "toolChoice"
        (json-object
         "tool"
         (json-object "name" (getf tool-choice :name))))))
    result))

(defun bedrock-cache-retention (value environment)
  (normalize-cache-retention
   (or value
       (and
        (string=
         "long"
         (or
          (environment-value
           environment "CADR_CACHE_RETENTION")
          ""))
        :long)
       :short)))

(defun bedrock-cache-point (retention)
  (json-object
   "cachePoint"
   (apply
    #'json-object
    (append
     (list "type" "default")
     (when (eq retention :long)
       (list "ttl" "ONE_HOUR"))))))

(defun bedrock-add-message-cache-point
    (messages model retention environment)
  (when (and
         (not (eq retention :none))
         (bedrock-prompt-cache-p model environment)
         (plusp (length messages)))
    (let* ((last
             (aref messages (1- (length messages))))
           (content (json-get last "content")))
      (when (and (string= (json-get last "role") "user")
                 content)
        (json-put
         last "content"
         (concatenate
          'vector content
          (vector
           (bedrock-cache-point retention)))))))
  messages)

(defun bedrock-endpoint-region (base-url)
  (handler-case
      (let* ((host
               (parsed-url-host (parse-http-url base-url)))
             (prefix "bedrock-runtime.")
             (start (search prefix host)))
        (when start
          (let* ((region-start (+ start (length prefix)))
                 (end (position #\. host :start region-start)))
            (and end (subseq host region-start end)))))
    (error () nil)))

(defun standard-bedrock-endpoint-p (base-url)
  (handler-case
      (let ((host
              (string-downcase
               (parsed-url-host
                (parse-http-url base-url)))))
        (and
         (or
          (uiop:string-prefix-p "bedrock-runtime." host)
          (uiop:string-prefix-p "bedrock-runtime-fips." host))
         (or
          (uiop:string-suffix-p host ".amazonaws.com")
          (uiop:string-suffix-p host ".amazonaws.com.cn"))))
    (error () nil)))

(defun bedrock-base-url
    (model region options ambient-profile-p)
  (let ((base (strip-trailing-slash (model-base-url model))))
    (cond
      ((getf options :explicit-base-url)
       (strip-trailing-slash
        (getf options :explicit-base-url)))
      ((and (standard-bedrock-endpoint-p base)
            (or
             (getf options :region)
             (environment-value
              (getf options :environment) "AWS_REGION")
             (environment-value
              (getf options :environment)
              "AWS_DEFAULT_REGION")
             ambient-profile-p))
       (format nil
               "https://bedrock-runtime.~A.amazonaws.com"
               region))
      (t base))))

(defun reserved-bedrock-header-p (name)
  (let ((lower (string-downcase name)))
    (or (string= lower "authorization")
        (string= lower "host")
        (uiop:string-prefix-p "x-amz-" lower))))

(defun bedrock-request-headers (provider model stream-p)
  (let ((headers
          `(("content-type" . "application/json")
            ("accept" .
             ,(if stream-p
                  "application/vnd.amazon.eventstream"
                  "application/json")))))
    (dolist
        (header
         (append
          (model-headers model)
          (getf (provider-options provider) :headers)))
      (unless (reserved-bedrock-header-p (car header))
        (setf headers
              (set-header headers
                          (car header) (cdr header)))))
    headers))

(defun iso8601-basic-now ()
  (multiple-value-bind
      (second minute hour day month year)
      (decode-universal-time (get-universal-time) 0)
    (format nil "~4,'0D~2,'0D~2,'0DT~2,'0D~2,'0D~2,'0DZ"
            year month day hour minute second)))

(defun bedrock-sigv4-headers
    (url headers payload credentials region options)
  (multiple-value-bind (authorization signed)
      (aws-sigv4-authorization
       :method "POST"
       :url url
       :headers headers
       :payload (stringify-json payload)
       :access-key-id (getf credentials :access-key-id)
       :secret-access-key (getf credentials :secret-access-key)
       :session-token (getf credentials :session-token)
       :region region
       :service "bedrock"
       :timestamp
       (or (getf options :timestamp)
           (iso8601-basic-now)))
    (set-header signed "authorization" authorization)))

(defmethod build-request
    ((provider bedrock-provider) model context
     &key stream-p max-tokens temperature reasoning
       cache-retention session-id tool-choice metadata)
  (declare (ignore session-id))
  (ensure-supported-content model context)
  (let* ((options (provider-options provider))
         (environment (getf options :environment))
         (profile
           (or (getf options :profile)
               (environment-value environment "AWS_PROFILE")))
         (profile-region
           (and profile
                (resolve-bedrock-profile-region
                 profile
                 :config-file
                 (or (getf options :config-file)
                     (default-aws-config-path))
                 :config-text
                 (getf options :config-text))))
         (region
           (resolve-bedrock-region
            (model-id model)
            (getf options :region)
            (or
             (environment-value environment "AWS_REGION")
             (environment-value environment "AWS_DEFAULT_REGION")
             profile-region)
            (bedrock-endpoint-region (model-base-url model))))
         (base
           (bedrock-base-url
            model region options
            (not (null profile))))
         (url
           (format nil "~A/model/~A/~A"
                   base
                   (sigv4-percent-encode (model-id model))
                   (if stream-p "converse-stream" "converse")))
         (retention
           (bedrock-cache-retention
            cache-retention environment))
         (messages
           (bedrock-add-message-cache-point
            (bedrock-messages context model)
            model retention environment))
         (payload
           (json-object
            "modelId" (model-id model)
            "messages" messages
            "inferenceConfig"
            (let ((config (json-object)))
              (let ((limit
                      (or max-tokens
                          (and
                           (bedrock-claude-model-p model)
                           (model-max-tokens model)))))
                (when limit
                  (json-put config "maxTokens" limit)))
              (when (not (null temperature))
                (json-put config "temperature" temperature))
              config)))
         (credentials
           (resolve-bedrock-credentials
            environment
            :profile profile
            :bearer-token (provider-api-key provider))))
    (when (non-empty-string-p (context-system-prompt context))
      (json-put payload
                "system"
                (list-json-array
                 (append
                  (list
                   (json-object
                    "text"
                    (context-system-prompt context)))
                  (when
                      (and
                       (not (eq retention :none))
                       (bedrock-prompt-cache-p
                        model environment))
                    (list
                     (bedrock-cache-point
                      retention)))))))
    (when (context-tools context)
      (json-put payload "toolConfig"
                (bedrock-tools
                 model (context-tools context) tool-choice)))
    (let ((thinking
            (bedrock-thinking-fields
             model reasoning region options)))
      (when thinking
        (json-put payload
                  "additionalModelRequestFields"
                  thinking)))
    (when metadata
      (json-put payload "requestMetadata" metadata))
    (unless credentials
      (error 'configuration-error
             :message "Amazon Bedrock credentials are not configured"))
    (let ((headers
            (bedrock-request-headers
             provider model stream-p)))
      (case (getf credentials :source)
        (:bearer-token
         (setf headers
               (set-header
                headers "authorization"
                (format nil "Bearer ~A"
                        (getf credentials :bearer-token)))))
        (:access-keys
         (setf headers
               (bedrock-sigv4-headers
                url headers payload credentials region options)))
        (:profile
         (let ((loaded
                 (load-bedrock-profile-credentials
                  (getf credentials :profile)
                  :credentials-file
                  (or
                   (getf options :credentials-file)
                   (default-aws-credentials-path))
                  :credentials-text
                  (getf options :credentials-text))))
           (unless loaded
             (error 'configuration-error
                    :message
                    (format nil
                            "AWS profile ~A has no static credentials"
                            (getf credentials :profile))))
           (setf headers
                 (bedrock-sigv4-headers
                  url headers payload loaded region options))))
        (otherwise
         (error 'configuration-error
                :message
                "Amazon Bedrock ambient credential source requires resolution before dispatch")))
      (make-request-spec
       :url url
       :headers headers
       :payload payload
       :stream-p stream-p
       :stream-format
       (if stream-p :aws-event-stream :sse)
       :provider :amazon-bedrock))))

(defun bedrock-event-data (event)
  (let ((object (parse-json (sse-event-data event))))
    (values
     (or (sse-event-event event)
         (and (json-object-p object)
              (first (json-keys object))))
     (if (and (json-object-p object)
              (sse-event-event event))
         object
         (and (json-object-p object)
              (json-get object (first (json-keys object))))))))

(defun finish-current-block (state emit)
  (let* ((message (provider-stream-state-message state))
         (index (provider-stream-state-current-block-index state))
         (block
           (and index
                (nth index
                     (assistant-message-content message)))))
    (when (typep block 'text-content)
      (emit-event emit :text-end message
                  :content-index index
                  :content (text-content-text block)))
    (when (typep block 'thinking-content)
      (emit-event emit :thinking-end message
                  :content-index index
                  :content
                  (thinking-content-thinking block)))
    (setf (provider-stream-state-current-block-index state) nil)))

(defun start-content-block (state type emit)
  (finish-current-block state emit)
  (let* ((message (provider-stream-state-message state))
         (block
           (ecase type
             (:text (make-text-content))
             (:thinking (make-thinking-content))))
         (index (length (assistant-message-content message))))
    (setf
     (assistant-message-content message)
     (append (assistant-message-content message)
             (list block))
     (provider-stream-state-current-block-index state)
     index)
    (emit-event emit
                (ecase type
                  (:text :text-start)
                  (:thinking :thinking-start))
                message
                :content-index index)
    block))

(defun append-text-delta (state delta emit)
  (let* ((message (provider-stream-state-message state))
         (index (provider-stream-state-current-block-index state))
         (block
           (and index
                (nth index
                     (assistant-message-content message)))))
    (unless (typep block 'text-content)
      (setf block (start-content-block state :text emit)
            index
            (provider-stream-state-current-block-index state)))
    (setf (text-content-text block)
          (nappend-string
           (text-content-text block) delta))
    (emit-event emit :text-delta message
                :content-index index
                :delta delta)))

(defun append-thinking-delta (state delta emit)
  (let* ((message (provider-stream-state-message state))
         (index (provider-stream-state-current-block-index state))
         (block
           (and index
                (nth index
                     (assistant-message-content message)))))
    (unless (typep block 'thinking-content)
      (setf block (start-content-block state :thinking emit)
            index
            (provider-stream-state-current-block-index state)))
    (setf (thinking-content-thinking block)
          (nappend-string
           (thinking-content-thinking block) delta))
    (emit-event emit :thinking-delta message
                :content-index index
                :delta delta)))

(defun parse-partial-json-object (text)
  (parse-streaming-json text))

(defmethod reduce-provider-sse-event
    ((provider bedrock-provider) state event emit)
  (declare (ignore provider))
  (multiple-value-bind (type data)
      (bedrock-event-data event)
    (let ((message (provider-stream-state-message state)))
      (cond
        ((string= type "contentBlockStart")
         (let* ((index (or (json-get data "contentBlockIndex") 0))
                (start (json-get data "start"))
                (tool (json-get start "toolUse")))
           (when tool
             (let ((call
                     (make-tool-call
                      :id (or (json-get tool "toolUseId") "")
                      :name (or (json-get tool "name") "")
                      :arguments (json-object))))
               (setf
                (gethash index
                         (provider-stream-state-block-indices state))
                (length (assistant-message-content message))
                (gethash index
                         (provider-stream-state-partial-json state))
                "")
               (setf
                (assistant-message-content message)
                (append
                 (assistant-message-content message)
                 (list call)))
               (emit-event emit :tool-call-start message
                           :content-index
                           (1- (length
                                (assistant-message-content message))))))))
        ((string= type "contentBlockDelta")
         (let* ((index (or (json-get data "contentBlockIndex") 0))
                (delta (json-get data "delta"))
                (text (json-get delta "text"))
                (reasoning-content
                  (json-get delta "reasoningContent"))
                (reasoning-text
                  (and reasoning-content
                       (json-get reasoning-content "text")))
                (reasoning-signature
                  (and reasoning-content
                       (json-get reasoning-content "signature")))
                (tool (json-get delta "toolUse")))
           (cond
             ((stringp text)
              (append-text-delta state text emit))
             ((or (stringp reasoning-text)
                  (non-empty-string-p reasoning-signature))
              (if (non-empty-string-p reasoning-text)
                  (append-thinking-delta state reasoning-text emit)
                  (let* ((block-index
                           (provider-stream-state-current-block-index
                            state))
                         (block
                           (and block-index
                                (nth
                                 block-index
                                 (assistant-message-content message)))))
                    (unless (typep block 'thinking-content)
                      (start-content-block state :thinking emit))))
              (when (non-empty-string-p reasoning-signature)
                (let* ((block-index
                         (provider-stream-state-current-block-index
                          state))
                       (block
                         (and block-index
                              (nth
                               block-index
                               (assistant-message-content
                                message)))))
                  (when (typep block 'thinking-content)
                    (setf
                     (thinking-content-signature block)
                     (nappend-string
                      (or (thinking-content-signature block) "")
                      reasoning-signature))))))
             (tool
              (let* ((block-index
                       (gethash
                        index
                        (provider-stream-state-block-indices state)))
                     (block
                       (and block-index
                            (nth block-index
                                 (assistant-message-content message))))
                     (piece (or (json-get tool "input") "")))
                (when (typep block 'tool-call)
                  (setf
                   (gethash
                    index
                    (provider-stream-state-partial-json state))
                   (nappend-string
                    (or
                     (gethash
                      index
                      (provider-stream-state-partial-json state))
                     "")
                    piece))
                  (emit-event emit :tool-call-delta message
                              :content-index block-index
                              :delta piece)))))))
        ((string= type "contentBlockStop")
         (let* ((index (or (json-get data "contentBlockIndex") 0))
                (block-index
                  (gethash
                   index
                   (provider-stream-state-block-indices state)))
                (block
                  (and block-index
                       (nth block-index
                            (assistant-message-content message)))))
           (when (typep block 'tool-call)
             (let ((json
                     (gethash
                      index
                      (provider-stream-state-partial-json state)
                      "")))
               (when (non-empty-string-p json)
                 (setf (tool-call-arguments block)
                       (parse-partial-json-object json))))
             (emit-event emit :tool-call-end message
                         :content-index block-index
                         :tool-call block))))
        ((string= type "messageStop")
         (let ((raw (or (json-get data "stopReason") "end_turn")))
           (setf (assistant-message-raw-stop-reason message) raw
                 (assistant-message-stop-reason message)
                 (map-simple-stop-reason raw)
                 (provider-stream-state-terminal-p state) t)
           (when (eq (assistant-message-stop-reason message)
                     :error)
             (setf
              (assistant-message-error-message message)
              (format nil "Provider stopped with: ~A" raw)))))
        ((string= type "metadata")
         (let ((usage (json-get data "usage")))
           (when usage
             (update-message-usage
              message
              (json-get usage "inputTokens")
              (json-get usage "outputTokens")
              (json-get usage "cacheReadInputTokens")
              (json-get usage "cacheWriteInputTokens")
              nil
              (json-get usage "totalTokens"))
             (apply-known-model-cost message))))))))

(defmethod parse-complete-response
    ((provider bedrock-provider) model response)
  (declare (ignore provider))
  (let* ((output (json-get response "output"))
         (message-data (json-get output "message"))
         (content (json-get message-data "content"))
         (raw (or (json-get response "stopReason") "end_turn"))
         (message
           (make-assistant-message
            :content
            (loop for block across (or content #())
                  append
                  (cond
                    ((json-present-p block "text")
                     (list
                      (make-text-content
                       :text (json-get block "text"))))
                    ((json-get block "toolUse")
                     (let ((tool (json-get block "toolUse")))
                       (list
                        (make-tool-call
                         :id (or (json-get tool "toolUseId") "")
                         :name (or (json-get tool "name") "")
                         :arguments
                         (or (json-get tool "input")
                             (json-object))))))
                    (t nil)))
            :api (model-api model)
            :provider (model-provider model)
            :model (model-id model)
            :raw-stop-reason raw
            :stop-reason (map-simple-stop-reason raw))))
    (when (eq (assistant-message-stop-reason message) :error)
      (setf
       (assistant-message-error-message message)
       (format nil "Provider stopped with: ~A" raw)))
    (let ((usage (json-get response "usage")))
      (when usage
        (update-message-usage
         message
         (json-get usage "inputTokens")
         (json-get usage "outputTokens")
         (json-get usage "cacheReadInputTokens")
         (json-get usage "cacheWriteInputTokens"))))
    (when (tool-call-present-p message)
      (setf (assistant-message-stop-reason message) :tool-use))
    (apply-known-model-cost message)))
