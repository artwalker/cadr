(in-package #:cadr-ai)

(defun mistral-reasoning-effort-model-p (model)
  (member
   (model-id model)
   '("mistral-small-2603"
     "mistral-small-latest"
     "mistral-medium-3.5"
     "zai-glm-5-2")
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
       cache-retention session-id tool-choice metadata
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
    (when reasoning
      (if (mistral-reasoning-effort-model-p model)
          (json-put
           payload "reasoning_effort"
           (or (model-thinking-level-value model reasoning)
               (string-downcase (symbol-name reasoning))))
          (json-put payload "prompt_mode" "reasoning")))
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
