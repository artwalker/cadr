(in-package #:cadr-ai)

(defun mistral-header-timeout-ms (timeout-ms)
  ;; pi@4a080252f mistral-conversations.ts. Headers wait at most this
  ;; long. The body is not on the same clock.
  (if (and (integerp timeout-ms) (>= timeout-ms 0))
      timeout-ms
      60000))

(defun mistral-header-timeout-message (milliseconds)
  (format nil "Mistral response headers timed out after ~Dms"
          milliseconds))

(defun mistral-active-reasoning (model reasoning)
  ;; streamSimple drops "off" before choosing prompt_mode or effort.
  (let ((requested
          (and reasoning (not (eq reasoning :off)) reasoning)))
    (when requested
      (let ((clamped (clamp-thinking-level model requested)))
        (unless (eq clamped :off)
          clamped)))))

(defun mistral-mapped-effort (model level)
  ;; `effortMap[level] ?? "high"`. A null map entry is "high".
  (let ((value (model-thinking-level-value model level)))
    (if (and (stringp value) (plusp (length value)))
        value
        "high")))

(defun apply-mistral-reasoning
    (payload model reasoning prompt-mode prompt-mode-p)
  (let* ((active (mistral-active-reasoning model reasoning))
         (effort-map
           (and (model-reasoning-p model)
                (model-thinking-level-map model))))
    (cond
      (effort-map
       (let ((effort
               (if active
                   (mistral-mapped-effort model active)
                   (let ((off (model-thinking-level-value model :off)))
                     (and (stringp off) (plusp (length off)) off)))))
         (when effort
           (json-put payload "reasoning_effort" effort))))
      ((and (model-reasoning-p model) active)
       (json-put payload "prompt_mode" "reasoning")))
    (when (and prompt-mode-p
               (stringp prompt-mode)
               (plusp (length prompt-mode)))
      (json-put payload "prompt_mode" prompt-mode)))
  payload)

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
       cache-retention session-id tool-choice metadata
       (prompt-mode nil prompt-mode-p)
       &allow-other-keys)
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
        (key (require-api-key provider))
        (affinity-p
          (and (non-empty-string-p session-id)
               (not (eq (normalize-cache-retention cache-retention)
                        :none)))))
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
    (apply-mistral-reasoning
     payload model reasoning prompt-mode prompt-mode-p)
    (when affinity-p
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
      (when affinity-p
        `(("x-affinity" . ,session-id)))
      (model-headers model))
     :payload payload
     :stream-p stream-p
     :provider :mistral)))

(defun apply-mistral-finish-reason (message reason)
  ;; pi@4a080252f mistral-conversations.ts mapChatStopReason. #10487
  ;; puts "server error" in the error finish so the retry classifier
  ;; treats a transient Mistral stop as retryable.
  (cond
    ((or (null reason)
         (json-null-p reason)
         (equal reason "stop"))
     (setf (assistant-message-stop-reason message) :stop
           (assistant-message-error-message message) nil))
    ((member reason '("length" "model_length") :test #'equal)
     (setf (assistant-message-stop-reason message) :length
           (assistant-message-error-message message) nil))
    ((equal reason "tool_calls")
     (setf (assistant-message-stop-reason message) :tool-use
           (assistant-message-error-message message) nil))
    ((equal reason "error")
     (setf (assistant-message-stop-reason message) :error
           (assistant-message-error-message message)
           "Provider stopped with: error (server error)"))
    (t
     (setf (assistant-message-stop-reason message) :error
           (assistant-message-error-message message)
           (format nil "Provider stopped with: ~A" reason))))
  message)

(defmethod parse-complete-response :around
    ((provider mistral-provider) model response)
  (let ((message (call-next-method)))
    (apply-mistral-finish-reason
     message (assistant-message-raw-stop-reason message))))
