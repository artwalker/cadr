(in-package #:cadr-ai)

(defun copy-model-with
    (model &key
             (api (model-api model))
             (base-url (model-base-url model)))
  (make-model
   :id (model-id model)
   :name (model-name model)
   :provider (model-provider model)
   :api api
   :base-url base-url
   :max-tokens (model-max-tokens model)
   :context-window (model-context-window model)
   :supports-images-p (model-supports-images-p model)
   :supports-tools-p (model-supports-tools-p model)
   :reasoning-p (model-reasoning-p model)
   :thinking-level-map (model-thinking-level-map model)
   :headers (model-headers model)
   :compat (model-compat model)))

(defun option-value (provider key &optional default)
  (getf (provider-options provider) key default))

(defun remove-header (headers name)
  (remove name headers :key #'car :test #'string-equal))

(defun set-header (headers name value)
  (acons name value (remove-header headers name)))

(defun copilot-request-headers (context)
  (append
   '(("User-Agent" . "GitHubCopilotChat/0.35.0")
     ("Editor-Version" . "vscode/1.107.0")
     ("Editor-Plugin-Version" . "copilot-chat/0.35.0")
     ("Copilot-Integration-Id" . "vscode-chat")
     ("Openai-Intent" . "conversation-edits"))
   (list
    (cons
     "X-Initiator"
     (let ((last (car (last (context-messages context)))))
       (if (and last (not (typep last 'user-message)))
           "agent"
           "user"))))
   (when (context-has-images-p context)
     '(("Copilot-Vision-Request" . "true")))))

(defun cloudflare-model (provider model)
  (if (member (model-provider model)
              '(:cloudflare-ai-gateway :cloudflare-workers-ai))
      (copy-model-with
       model
       :base-url
       (materialize-cloudflare-url
        (model-base-url model)
        (option-value provider :cloudflare-account-id)
        (option-value provider :cloudflare-gateway-id)))
      model))

(defmethod build-request :around
    ((provider provider) model context
     &key stream-p max-tokens temperature reasoning
       cache-retention session-id tool-choice metadata)
  (let* ((resolved-model (cloudflare-model provider model))
         (request
           (call-next-method
            provider resolved-model context
            :stream-p stream-p
            :max-tokens max-tokens
            :temperature temperature
            :reasoning reasoning
            :cache-retention cache-retention
            :session-id session-id
            :tool-choice tool-choice
            :metadata metadata))
         (provider-id (model-provider model))
         (headers (request-spec-headers request)))
    (case provider-id
      (:cloudflare-ai-gateway
       (setf headers
             (remove-header
              (remove-header headers "authorization")
              "x-api-key"))
       (setf headers
             (set-header
              headers "cf-aig-authorization"
              (format nil "Bearer ~A"
                      (require-api-key provider)))))
      (:github-copilot
       (dolist (header (copilot-request-headers context))
         (setf headers
               (set-header headers
                           (car header) (cdr header)))))
      (:kimi-coding
       (let ((oauth-token
               (or (provider-oauth-access-token provider)
                   (option-value provider :oauth-bearer-token))))
         (when oauth-token
           (setf headers
                 (remove-header headers "x-api-key"))
           (setf headers
                 (set-header
                  headers "authorization"
                  (format nil "Bearer ~A"
                          oauth-token)))))))
    (setf (request-spec-headers request) headers
          (request-spec-provider request) provider-id)
    request))

(defun normalized-url-authority (parsed)
  (format nil "~A://~A~@[:~D~]"
          (parsed-url-scheme parsed)
          (parsed-url-host parsed)
          (unless
              (or
               (and (string= "https" (parsed-url-scheme parsed))
                    (= 443 (parsed-url-port parsed)))
               (and (string= "http" (parsed-url-scheme parsed))
                    (= 80 (parsed-url-port parsed))))
            (parsed-url-port parsed))))

(defun normalize-azure-openai-base-url (base-url)
  (handler-case
      (let* ((trimmed
               (string-right-trim
                "/" (string-trim '(#\Space #\Tab) base-url)))
             (parsed (parse-http-url trimmed))
             (host (string-downcase (parsed-url-host parsed)))
             (path
               (let ((question
                       (position #\? (parsed-url-path parsed))))
                 (string-right-trim
                  "/"
                  (subseq
                   (parsed-url-path parsed)
                   0 question))))
             (azure-host-p
               (or
                (uiop:string-suffix-p host ".openai.azure.com")
                (uiop:string-suffix-p
                 host ".cognitiveservices.azure.com")
                (uiop:string-suffix-p host ".ai.azure.com"))))
        (if (and azure-host-p
                 (member path
                         '("" "/" "/openai" "/openai/v1/responses")
                         :test #'string=))
            (format nil "~A/openai/v1"
                    (normalized-url-authority parsed))
            trimmed))
    (error ()
      (error 'configuration-error
             :message
             (format nil "Invalid Azure OpenAI base URL: ~A"
                     base-url)))))

(defun resolve-azure-deployment-name
    (model-id explicit-name deployment-map)
  (or
   (and (non-empty-string-p explicit-name)
        explicit-name)
   (loop for entry in
         (and (non-empty-string-p deployment-map)
              (split-on-character deployment-map #\,))
         for equals = (position #\= entry)
         when equals
           do
           (let ((source
                   (string-trim '(#\Space #\Tab)
                                (subseq entry 0 equals)))
                 (target
                   (string-trim '(#\Space #\Tab)
                                (subseq entry (1+ equals)))))
             (when (and (string= source model-id)
                        (non-empty-string-p target))
               (return target))))
   model-id))

(defun azure-base-url (provider model)
  (let ((explicit (option-value provider :azure-base-url))
        (resource (option-value provider :azure-resource-name)))
    (normalize-azure-openai-base-url
     (or
      (and (non-empty-string-p explicit) explicit)
      (and (non-empty-string-p resource)
           (format nil
                   "https://~A.openai.azure.com/openai/v1"
                   resource))
      (and (non-empty-string-p (model-base-url model))
           (model-base-url model))
      (error 'configuration-error
             :message
             "Azure OpenAI base URL is required")))))

(defmethod build-request
    ((provider azure-openai-provider) model context
     &key stream-p max-tokens temperature reasoning
       cache-retention session-id tool-choice metadata)
  (let* ((key (require-api-key provider))
         (base (azure-base-url provider model))
         (deployment
           (resolve-azure-deployment-name
            (model-id model)
            (option-value provider :azure-deployment-name)
            (option-value provider :azure-deployment-name-map)))
         (delegate
           (make-openai-provider :api-key key))
         (request
           (build-request
            delegate
            (copy-model-with model
                             :api :openai-responses
                             :base-url base)
            context
            :stream-p stream-p
            :max-tokens max-tokens
            :temperature temperature
            :reasoning reasoning
            :cache-retention cache-retention
            :session-id session-id
            :tool-choice tool-choice
            :metadata metadata)))
    (json-put (request-spec-payload request)
              "model" deployment)
    (setf
     (request-spec-headers request)
     (set-header
      (remove-header
       (request-spec-headers request)
       "authorization")
      "api-key" key)
     (request-spec-provider request)
     :azure-openai-responses)
    (let ((api-version
            (option-value provider :azure-api-version "v1")))
      (when (and (non-empty-string-p api-version)
                 (not (string= api-version "v1")))
        (setf (request-spec-url request)
              (format nil "~A?api-version=~A"
                      (request-spec-url request)
                      api-version))))
    request))

(defmethod build-request
    ((provider openai-codex-provider) model context
     &key stream-p max-tokens temperature reasoning
       cache-retention session-id tool-choice metadata)
  (let ((token (provider-oauth-access-token provider)))
    (unless (non-empty-string-p token)
      (error 'authentication-error
             :message "OpenAI Codex OAuth credential is missing"))
    (let ((request
            (build-request
             (make-openai-provider
              :oauth-access-token token
             :oauth-account-id
              (provider-oauth-account-id provider))
             (copy-model-with model)
             context
             :stream-p stream-p
             :max-tokens max-tokens
             :temperature temperature
             :reasoning reasoning
             :cache-retention cache-retention
             :session-id session-id
             :tool-choice tool-choice
             :metadata metadata)))
      (unless reasoning
        (remhash "reasoning"
                 (request-spec-payload request)))
      (setf (request-spec-provider request) :openai-codex)
      request)))

(defun mistral-reasoning-effort-model-p (model)
  (member
   (model-id model)
   '("mistral-small-2603"
     "mistral-small-latest"
     "mistral-medium-3.5")
   :test #'string=))

(defun derive-mistral-tool-call-id (id attempt)
  (let ((normalized
          (coerce
           (remove-if-not #'alphanumericp id)
           'string)))
    (if (and (zerop attempt) (= 9 (length normalized)))
        normalized
        (subseq
         (short-hash
          (if (zerop attempt)
              (if (plusp (length normalized)) normalized id)
              (format nil "~A:~D"
                      (if (plusp (length normalized)) normalized id)
                      attempt)))
         0 9))))

(defun make-mistral-tool-call-id-normalizer ()
  (let ((forward (make-hash-table :test #'equal))
        (reverse (make-hash-table :test #'equal)))
    (lambda (id)
      (or
       (gethash id forward)
       (loop for attempt from 0
             for candidate = (derive-mistral-tool-call-id id attempt)
             for owner = (gethash candidate reverse)
             when (or (null owner) (string= owner id))
               do (setf (gethash id forward) candidate
                        (gethash candidate reverse) id)
                  (return candidate))))))

(defmethod build-request
    ((provider mistral-provider) model context
     &key stream-p max-tokens temperature reasoning
       cache-retention session-id tool-choice metadata)
  (declare (ignore metadata))
  (ensure-supported-content model context)
  (let* ((normalize-id (make-mistral-tool-call-id-normalizer))
         (payload
          (json-object
           "model" (model-id model)
           "stream" (and stream-p t)
           "messages"
           (openai-chat-messages
            model context :normalize-id normalize-id)))
        (key (require-api-key provider)))
    (when max-tokens
      (json-put payload "max_tokens" max-tokens))
    (when (not (null temperature))
      (json-put payload "temperature" temperature))
    (when (context-tools context)
      (json-put payload "tools"
                (openai-chat-tools model (context-tools context))))
    (when tool-choice
      (json-put payload "tool_choice"
                (if (string= tool-choice "any")
                    "any"
                    tool-choice)))
    (when reasoning
      (if (mistral-reasoning-effort-model-p model)
          (json-put
           payload "reasoning_effort"
           (or (model-thinking-level-value model reasoning)
               (string-downcase (symbol-name reasoning))))
          (json-put payload "prompt_mode" "reasoning")))
    (when (and (non-empty-string-p session-id)
               (not (eq (normalize-cache-retention cache-retention)
                        :none)))
      (json-put payload "prompt_cache_key" session-id))
    (make-request-spec
     :url
     (format nil "~A/v1/chat/completions"
             (strip-trailing-slash (model-base-url model)))
     :headers
     (append
      `(("content-type" . "application/json")
        ("accept" . ,(if stream-p
                         "text/event-stream"
                         "application/json"))
        ("authorization" . ,(format nil "Bearer ~A" key)))
      (when (and (non-empty-string-p session-id)
                 (not
                  (eq (normalize-cache-retention cache-retention)
                      :none)))
        `(("x-affinity" . ,session-id)))
      (model-headers model))
     :payload payload
     :stream-p stream-p
     :provider :mistral)))

(defun vertex-base-url (model project location api-key-p)
  (let ((model-base (model-base-url model)))
    (cond
      ((and (non-empty-string-p model-base)
            (not (search "{location}" model-base)))
       (strip-trailing-slash model-base))
      (api-key-p
       "https://aiplatform.googleapis.com/v1")
      (t
       (format nil
               "https://~A-aiplatform.googleapis.com/v1/projects/~A/locations/~A"
               location project location)))))

(defmethod build-request
    ((provider vertex-provider) model context
     &key stream-p max-tokens temperature reasoning
       cache-retention session-id tool-choice metadata)
  (declare (ignore cache-retention session-id metadata))
  (ensure-supported-content model context)
  (let* ((environment
           (or (option-value provider :environment) nil))
         (key
           (let ((candidate (provider-api-key provider)))
             (and (non-empty-string-p candidate)
                  (not (placeholder-api-key-p candidate))
                  candidate)))
         (project
           (or
            (option-value provider :project)
            (environment-value environment "GOOGLE_CLOUD_PROJECT")
            (environment-value environment "GCLOUD_PROJECT")))
         (location
           (or
            (option-value provider :location)
            (environment-value
             environment "GOOGLE_CLOUD_LOCATION")))
         (access-token
           (or
            (option-value provider :access-token)
            (provider-oauth-access-token provider)
            (let* ((credential
                     (or
                      (option-value provider :credential)
                      (let ((path
                              (or
                               (environment-value
                                environment
                                "GOOGLE_APPLICATION_CREDENTIALS")
                               (and
                                (probe-file
                                 (default-adc-path))
                                (default-adc-path)))))
                        (and path
                             (read-google-application-credential
                              path))))))
              (when credential
                (unless project
                  (setf project
                        (json-get credential "project_id")))
                (exchange-vertex-access-token
                 credential
                 :issued-at
                 (option-value provider :issued-at))))))
         (base
           (vertex-base-url
            model project location (not (null key))))
         (payload
           (json-object
            "contents"
            (google-contents model (context-messages context))))
         (generation-config (json-object)))
    (unless (or key
                (and (non-empty-string-p project)
                     (non-empty-string-p location)
                     (non-empty-string-p access-token)))
      (error 'configuration-error
             :message
             "Vertex AI requires an API key or ADC access token with project and location"))
    (when (non-empty-string-p (context-system-prompt context))
      (json-put payload
                "systemInstruction"
                (json-object "parts"
                             (json-array
                              (json-object
                               "text"
                               (context-system-prompt context))))))
    (when max-tokens
      (json-put generation-config "maxOutputTokens" max-tokens))
    (when (not (null temperature))
      (json-put generation-config "temperature" temperature))
    (when (plusp (hash-table-count generation-config))
      (json-put payload "generationConfig" generation-config))
    (when (context-tools context)
      (json-put payload "tools" (google-tools (context-tools context))))
    (let ((thinking (google-thinking-config model reasoning)))
      (when thinking
        (json-put payload "thinkingConfig" thinking)))
    (when tool-choice
      (json-put
       payload "toolConfig"
       (json-object
        "functionCallingConfig"
        (json-object "mode" (string-upcase tool-choice)))))
    (make-request-spec
     :url
     (format
      nil "~A/~A/~A:~A~A"
      (strip-trailing-slash base)
      "publishers/google/models"
      (model-id model)
      (if stream-p
          "streamGenerateContent"
          "generateContent")
      (if stream-p "?alt=sse" ""))
     :headers
     (append
      `(("content-type" . "application/json")
        ("accept" . ,(if stream-p
                         "text/event-stream"
                         "application/json")))
      (if key
          `(("x-goog-api-key" . ,key))
          `(("authorization" .
             ,(format nil "Bearer ~A" access-token))))
      (model-headers model))
     :payload payload
     :stream-p stream-p
     :provider :google-vertex)))

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
                              (tool-call-arguments block))))))
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
                   (let ((spec
                           (json-object
                            "name" (tool-name tool)
                            "description"
                            (tool-description tool)
                            "inputSchema"
                            (json-object
                             "json"
                             (tool-parameters tool)))))
                     (when
                         (and
                          (model-compat-value
                           model :supports-strict-mode nil)
                          (tool-strict-p tool))
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
           environment "PI_CACHE_RETENTION")
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
         (multiple-value-bind (authorization signed)
             (aws-sigv4-authorization
              :method "POST"
              :url url
              :headers headers
              :payload (stringify-json payload)
              :access-key-id
              (getf credentials :access-key-id)
              :secret-access-key
              (getf credentials :secret-access-key)
              :session-token
              (getf credentials :session-token)
              :region region
              :service "bedrock"
              :timestamp
              (or (getf options :timestamp)
                  (iso8601-basic-now)))
           (setf headers
                 (set-header signed
                             "authorization"
                             authorization))))
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
           (multiple-value-bind (authorization signed)
               (aws-sigv4-authorization
                :method "POST"
                :url url
                :headers headers
                :payload (stringify-json payload)
                :access-key-id
                (getf loaded :access-key-id)
                :secret-access-key
                (getf loaded :secret-access-key)
                :session-token
                (getf loaded :session-token)
                :region region
                :service "bedrock"
                :timestamp
                (or (getf options :timestamp)
                    (iso8601-basic-now)))
             (setf headers
                   (set-header signed
                               "authorization"
                               authorization)))))
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
         (and (hash-table-p object)
              (loop for key being the hash-keys of object
                    return key)))
     (if (and (hash-table-p object)
              (sse-event-event event))
         object
         (and (hash-table-p object)
              (loop for value being the hash-values of object
                    return value))))))

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
          (concatenate 'string
                       (text-content-text block)
                       delta))
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
          (concatenate 'string
                       (thinking-content-thinking block)
                       delta))
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
                     (concatenate
                      'string
                      (or
                       (thinking-content-signature block)
                       "")
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
                     (piece (or (json-get tool "input") ""))
                     (partial
                       (concatenate
                        'string
                        (or
                         (gethash
                          index
                          (provider-stream-state-partial-json state))
                         "")
                        piece)))
                (when (typep block 'tool-call)
                  (setf
                   (gethash
                    index
                    (provider-stream-state-partial-json state))
                   partial
                   (tool-call-arguments block)
                   (parse-partial-json-object partial))
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
          (assistant-message-content message)
          (append (assistant-message-content message)
                  (list call)))
         (emit-event emit :tool-call-start message
                     :content-index index)))
      ((string= type "toolcall_delta")
       (let* ((piece (or (json-get data "delta") ""))
              (partial
                (concatenate
                 'string
                 (or (gethash
                      index
                      (provider-stream-state-partial-json state))
                     "")
                 piece))
              (block
                (nth index
                     (assistant-message-content message))))
         (setf
          (gethash index
                   (provider-stream-state-partial-json state))
          partial)
         (when (typep block 'tool-call)
           (setf (tool-call-arguments block)
                 (parse-partial-json-object partial)))
         (emit-event emit :tool-call-delta message
                     :content-index index
                     :delta piece)))
      ((string= type "toolcall_end")
       (let ((block
               (nth index
                    (assistant-message-content message))))
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
