(in-package #:cadr-ai)

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
       cache-retention session-id tool-choice metadata
       &allow-other-keys)
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
      (json-put payload "tools"
                (google-tools
                 (context-tools context)
                 :supports-strict-mode-p
                 (supports-google-strict-tool-sampling-p model))))
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
