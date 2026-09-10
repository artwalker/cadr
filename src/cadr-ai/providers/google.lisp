(in-package #:cadr-ai)

(defun google-message-parts (model message)
  (cond
    ((typep message 'user-message)
     (let ((content (user-message-content message)))
       (if (stringp content)
           (json-array (json-object "text" content))
           (list-json-array
            (loop for block across (coerce content 'vector)
                  when (typep block 'text-content)
                    collect (json-object
                             "text" (text-content-text block))
                  when (typep block 'image-content)
                    collect
                    (json-object
                     "inlineData"
                     (json-object
                      "mimeType" (image-content-mime-type block)
                      "data" (image-content-data block))))))))
    ((typep message 'assistant-message)
     (list-json-array
      (loop for block in (assistant-message-content message)
            when (typep block 'text-content)
              collect (let ((part
                              (json-object
                               "text" (text-content-text block))))
                        (when (text-content-signature block)
                          (json-put part
                                    "thoughtSignature"
                                    (text-content-signature block)))
                        part)
            when (typep block 'thinking-content)
              collect (let ((part
                              (json-object
                               "thought" t
                               "text"
                               (thinking-content-thinking block))))
                        (when (thinking-content-signature block)
                          (json-put part
                                    "thoughtSignature"
                                    (thinking-content-signature block)))
                        part)
            when (typep block 'tool-call)
              collect (let ((call
                              (json-object
                               "name" (tool-call-name block)
                               "args" (tool-call-arguments block))))
                        (when (google-gemini-3-model-p model)
                          (json-put call "id" (tool-call-id block)))
                        (let ((part
                                (json-object "functionCall" call)))
                          (when (tool-call-thought-signature block)
                            (json-put
                             part
                             "thoughtSignature"
                             (tool-call-thought-signature block)))
                          part)))))
    ((typep message 'tool-result-message)
     (json-array
      (let ((response
              (json-object
               (if (tool-result-message-is-error message)
                   "error"
                   "output")
               (content-text (tool-result-message-content message)))))
        (json-object
         "functionResponse"
         (let ((function-response
                 (json-object
                  "name" (tool-result-message-tool-name message)
                  "response" response)))
           (when (google-gemini-3-model-p model)
             (json-put function-response
                       "id"
                       (tool-result-message-tool-call-id message)))
           function-response)))))))

(defun google-contents (model messages)
  (list-json-array
   (loop for message
           in (prepare-messages-for-model
               messages model #'normalize-provider-id)
         for parts = (google-message-parts model message)
         unless (and (typep message 'assistant-message)
                     (zerop (length parts)))
           collect
           (json-object
            "role" (if (typep message 'assistant-message)
                       "model"
                       "user")
            "parts" parts))))

(defun google-tools (tools &key (supports-strict-mode-p t))
  (json-array
   (json-object
    "functionDeclarations"
    (list-json-array
     (loop for tool in tools
           collect
           (let ((strict
                   ;; Baseline google-shared.ts convertTools: per-tool
                   ;; strict resolution, throwing on "require" mismatch.
                   (resolve-json-schema-strict-sampling
                    tool supports-strict-mode-p)))
             (json-object
              "name" (tool-name tool)
              "description" (tool-description tool)
              "parametersJsonSchema"
              (get-json-schema-tool-parameters tool (eq strict t)))))))))

(defun google-gemini-3-model-p (model)
  ;; Baseline google-shared.ts: gemini-3 tool-call/result ids.
  (search "gemini-3" (string-downcase (model-id model))))

(defun gemini-major-version (model-id)
  ;; Baseline google-shared.ts getGeminiMajorVersion.
  (let* ((lowered (string-downcase model-id))
         (rest
           (cond
             ((uiop:string-prefix-p "gemini-live-" lowered)
              (subseq lowered 12))
             ((uiop:string-prefix-p "gemini-" lowered)
              (subseq lowered 7))
             (t nil))))
    (when rest
      (let ((end (or (position-if-not #'digit-char-p rest)
                     (length rest))))
        (when (plusp end)
          (parse-integer rest :end end))))))

(defun supports-google-strict-tool-sampling-p (model)
  ;; Baseline supportsGoogleStrictToolSampling: Gemini 3+ enforces
  ;; required function parameters in validated tool-calling modes.
  (let ((major (gemini-major-version (model-id model))))
    (and major (>= major 3))))

(defun gemini-3.6-flash-p (model)
  (string-equal "gemini-3.6-flash" (model-id model)))

(defun google-gemini-3-pro-p (model)
  (let ((id (string-downcase (model-id model))))
    (and (search "gemini-3" id)
         (search "-pro" id))))

(defun google-gemini-3-flash-p (model)
  (let ((id (string-downcase (model-id model))))
    (or (and (search "gemini-3" id)
             (search "-flash" id))
        (member id
                '("gemini-flash-latest"
                  "gemini-flash-lite-latest")
                :test #'string=))))

(defun google-gemma-4-p (model)
  (let ((id (string-downcase (model-id model))))
    (or (search "gemma-4" id)
        (search "gemma4" id))))

(defparameter +google-resolved-thinking-levels+
  '(:minimal :low :medium :high))

(defun google-parse-resolved-thinking-level (value)
  (when (stringp value)
    (let ((keyword (find-symbol (string-upcase value) :keyword)))
      (when (member keyword +google-resolved-thinking-levels+)
        keyword))))

(defun resolve-google-thinking-level (model level)
  ;; Baseline google-shared.ts resolveGoogleThinkingLevel.
  (let* ((mapped
           (unless (eq level :off)
             (model-thinking-level-value model level)))
         (resolved
           (if (eq level :off)
               :high
               (or (google-parse-resolved-thinking-level mapped)
                   level))))
    (if (member resolved +google-resolved-thinking-levels+)
        resolved
        (error "Unsupported Google thinking level mapping for ~A/~A: ~A -> ~A"
               (model-provider model)
               (model-id model)
               level
               mapped))))

(defun google-api-thinking-level (resolved-level model)
  ;; Baseline google-generative-ai.ts getThinkingLevel (GoogleApiThinkingLevel).
  (cond
    ((google-gemini-3-pro-p model)
     (if (member resolved-level '(:minimal :low)) "LOW" "HIGH"))
    ((google-gemma-4-p model)
     (if (member resolved-level '(:minimal :low)) "MINIMAL" "HIGH"))
    (t
     (ecase resolved-level
       (:minimal "MINIMAL")
       (:low "LOW")
       (:medium "MEDIUM")
       (:high "HIGH")))))

(defun google-thinking-config (model reasoning)
  (when (model-reasoning-p model)
    (if reasoning
        (let* ((clamped (clamp-thinking-level model reasoning))
               (resolved (resolve-google-thinking-level model clamped)))
          (json-object
           "includeThoughts" t
           "thinkingLevel"
           (google-api-thinking-level resolved model)))
        (cond
          ((google-gemini-3-pro-p model)
           (json-object "thinkingLevel" "LOW"))
          ((or (google-gemini-3-flash-p model)
               (google-gemma-4-p model))
           (json-object "thinkingLevel" "MINIMAL"))
          (t
           (json-object "thinkingBudget" 0))))))

(defmethod build-request ((provider google-provider)
                          model context
                          &key stream-p max-tokens temperature reasoning
                            cache-retention session-id tool-choice metadata
                            &allow-other-keys)
  (declare (ignore cache-retention session-id metadata))
  (ensure-supported-content model context)
  (let* ((key (require-api-key provider))
         (payload
           (json-object
            "contents"
            (google-contents model (context-messages context))))
         (generation-config (json-object)))
    (when (non-empty-string-p (context-system-prompt context))
      (json-put
       payload
       "systemInstruction"
       (json-object
        "parts"
        (json-array
         (json-object "text" (context-system-prompt context))))))
    (when max-tokens
      (json-put generation-config "maxOutputTokens" max-tokens))
    (when (and temperature
               (not (gemini-3.6-flash-p model)))
      (json-put generation-config "temperature" temperature))
    (when (plusp (hash-table-count generation-config))
      (json-put payload "generationConfig" generation-config))
    (when (context-tools context)
      (json-put payload "tools"
                (google-tools
                 (context-tools context)
                 :supports-strict-mode-p
                 (supports-google-strict-tool-sampling-p model))))
    (let ((thinking-config
            (google-thinking-config model reasoning)))
      (when thinking-config
        (json-put payload "thinkingConfig" thinking-config)))
    (when tool-choice
      (json-put
       payload "toolConfig"
       (json-object
        "functionCallingConfig"
        (json-object
         "mode" (string-upcase tool-choice)))))
    (make-request-spec
     :url (format
           nil
           "~A/models/~A:~A"
           (strip-trailing-slash (model-base-url model))
           (model-id model)
           (if stream-p
               "streamGenerateContent?alt=sse"
               "generateContent"))
     :headers
     (append
      `(("content-type" . "application/json")
        ("accept" . ,(if stream-p
                         "text/event-stream"
                         "application/json"))
        ("x-goog-api-key" . ,key))
      (model-headers model))
     :payload payload
     :stream-p stream-p
     :provider :google)))

(defun google-candidate (response)
  (let ((candidates (json-get response "candidates")))
    (and (vectorp candidates)
         (plusp (length candidates))
         (aref candidates 0))))

(defun parse-google-parts (parts)
  (loop for part across (or parts #())
        append
        (cond
          ((json-present-p part "text")
           (if (eq t (json-get part "thought"))
               (list
                (make-thinking-content
                 :thinking (or (json-get part "text") "")
                 :signature (json-get part "thoughtSignature")))
               (list
                (make-text-content
                 :text (or (json-get part "text") "")
                 :signature (json-get part "thoughtSignature")))))
          ((hash-table-p (json-get part "functionCall"))
           (let ((call (json-get part "functionCall")))
             (list
              (make-tool-call
               :id (or (json-get call "id")
                       (format nil "~A-generated"
                               (or (json-get call "name") "tool")))
               :name (or (json-get call "name") "")
               :arguments (or (json-get call "args") (json-object))
               :thought-signature
               (json-get part "thoughtSignature")))))
          (t nil))))

(defun update-google-usage (message usage)
  (when (hash-table-p usage)
    (let ((cached (or (json-get usage "cachedContentTokenCount") 0))
          (thoughts (or (json-get usage "thoughtsTokenCount") 0)))
      (update-message-usage
       message
       (max 0 (- (or (json-get usage "promptTokenCount") 0)
                 cached))
       (+ (or (json-get usage "candidatesTokenCount") 0)
          thoughts)
       cached
       0
       thoughts
       (json-get usage "totalTokenCount"))
      (apply-known-model-cost message))))

(defmethod parse-complete-response ((provider google-provider)
                                    model response)
  (declare (ignore provider))
  (let* ((candidate (google-candidate response))
         (content (json-get candidate "content"))
         (raw-stop (or (json-get candidate "finishReason") "STOP"))
         (message
           (make-assistant-message
            :content (parse-google-parts (json-get content "parts"))
            :api (model-api model)
            :provider (model-provider model)
            :model (model-id model)
            :response-id (json-get response "responseId")
            :raw-stop-reason raw-stop
            :stop-reason (map-simple-stop-reason raw-stop))))
    (update-google-usage message (json-get response "usageMetadata"))
    ;; Baseline v0.84.2: toolUse overrides only a clean stop.
    (when (and (eq (assistant-message-stop-reason message) :stop)
               (tool-call-present-p message))
      (setf (assistant-message-stop-reason message) :tool-use))
    message))

(defun finish-google-current-block (state emit)
  (let* ((message (provider-stream-state-message state))
         (index (provider-stream-state-current-block-index state))
         (block (and index
                     (nth index (assistant-message-content message)))))
    (cond
      ((typep block 'text-content)
       (emit-event emit :text-end message
                   :content-index index
                   :content (text-content-text block)))
      ((typep block 'thinking-content)
       (emit-event emit :thinking-end message
                   :content-index index
                   :content (thinking-content-thinking block))))
    (setf (provider-stream-state-current-block-index state) nil)))

(defun google-text-delta (state part emit)
  (let* ((message (provider-stream-state-message state))
         (thinking-p (eq t (json-get part "thought")))
         (index (provider-stream-state-current-block-index state))
         (current (and index
                       (nth index (assistant-message-content message))))
         (wanted-type (if thinking-p 'thinking-content 'text-content)))
    (unless (typep current wanted-type)
      (finish-google-current-block state emit)
      (setf current
            (if thinking-p
                (make-thinking-content)
                (make-text-content)))
      (setf index (append-content-block message current)
            (provider-stream-state-current-block-index state) index)
      (emit-event emit
                  (if thinking-p :thinking-start :text-start)
                  message
                  :content-index index))
    (let ((delta (or (json-get part "text") "")))
      (if thinking-p
          (progn
            (setf (thinking-content-thinking current)
                  (nappend-string
                   (thinking-content-thinking current) delta))
            (when (non-empty-string-p
                   (json-get part "thoughtSignature"))
              (setf (thinking-content-signature current)
                    (json-get part "thoughtSignature"))))
          (progn
            (setf (text-content-text current)
                  (nappend-string
                   (text-content-text current) delta))
            (when (non-empty-string-p
                   (json-get part "thoughtSignature"))
              (setf (text-content-signature current)
                    (json-get part "thoughtSignature")))))
      (emit-event emit
                  (if thinking-p :thinking-delta :text-delta)
                  message
                  :content-index index
                  :delta delta))))

(defmethod reduce-provider-sse-event ((provider google-provider)
                                      state event emit)
  (declare (ignore provider))
  (let ((data (sse-event-data event)))
    (when (or (zerop (length data)) (string= data "[DONE]"))
      (return-from reduce-provider-sse-event nil))
    (let* ((payload (parse-json data))
           (message (provider-stream-state-message state))
           (candidate (google-candidate payload))
           (content (json-get candidate "content"))
           (parts (json-get content "parts")))
      (when (non-empty-string-p (json-get payload "responseId"))
        (setf (assistant-message-response-id message)
              (json-get payload "responseId")))
      (when (vectorp parts)
        (loop for part across parts
              do (cond
                   ((json-present-p part "text")
                    (google-text-delta state part emit))
                   ((hash-table-p (json-get part "functionCall"))
                    (finish-google-current-block state emit)
                    (let* ((call (json-get part "functionCall"))
                           (tool-call
                             (make-tool-call
                              :id (or (json-get call "id")
                                      (format nil "~A-generated"
                                              (or (json-get call "name")
                                                  "tool")))
                              :name (or (json-get call "name") "")
                              :arguments
                              (or (json-get call "args") (json-object))
                              :thought-signature
                              (json-get part "thoughtSignature")))
                           (index
                             (append-content-block message tool-call))
                           (arguments
                             (stringify-json
                              (tool-call-arguments tool-call))))
                      (emit-event emit :tool-call-start message
                                  :content-index index)
                      (emit-event emit :tool-call-delta message
                                  :content-index index
                                  :delta arguments)
                      (emit-event emit :tool-call-end message
                                  :content-index index
                                  :tool-call tool-call))))))
      (let ((raw-stop (json-get candidate "finishReason")))
        (when (non-empty-string-p raw-stop)
          (finish-google-current-block state emit)
          (setf (provider-stream-state-terminal-p state) t
                (assistant-message-raw-stop-reason message) raw-stop
                (assistant-message-stop-reason message)
                (map-simple-stop-reason raw-stop))
          (when (and (eq (assistant-message-stop-reason message) :stop)
                     (tool-call-present-p message))
            (setf (assistant-message-stop-reason message) :tool-use))))
      (update-google-usage message (json-get payload "usageMetadata"))))
  nil)
