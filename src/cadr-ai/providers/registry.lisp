(in-package #:cadr-ai)

(defun make-protocol-provider
    (protocol definition api-key oauth-access-token oauth-account-id
     options)
  (let* ((provider-id (provider-definition-id definition))
         (oauth-strategy
           (provider-definition-oauth-login-strategy definition))
         (native-oauth-p
           (member oauth-strategy
                   '(:anthropic :openai-device :radius)))
         (effective-api-key
           (if (and oauth-access-token (not native-oauth-p))
               oauth-access-token
               api-key))
         (effective-oauth-token
           (and native-oauth-p oauth-access-token))
         (effective-options
           (if (and oauth-access-token
                    (eq oauth-strategy :kimi))
               (append
                (list :oauth-bearer-token oauth-access-token)
                options)
               options))
         (common
          (list
           :api-key effective-api-key
           :oauth-access-token effective-oauth-token
           :oauth-account-id oauth-account-id
           :provider-id provider-id
           :options effective-options)))
    (case protocol
      (:anthropic-messages
       (apply #'make-anthropic-provider common))
      (:openai-responses
       (apply #'make-openai-provider common))
      (:openai-completions
       (apply
        #'make-openai-completions-provider
        (append
         common
         (list
          :authentication-required-p
          (not
           (null
            (provider-definition-key-environment definition)))))))
      (:google-generative-ai
       (apply #'make-google-provider common))
      (:azure-openai-responses
       (apply #'make-azure-openai-provider common))
      (:bedrock-converse-stream
       (apply #'make-bedrock-provider common))
      (:google-vertex
       (apply #'make-vertex-provider common))
      (:mistral-conversations
       (apply #'make-mistral-provider common))
      (:openai-codex-responses
       (apply #'make-openai-codex-provider common))
      (:pi-messages
       (apply #'make-pi-messages-provider common))
      (otherwise
       (error 'configuration-error
              :message
              (format nil "Unsupported provider protocol: ~A"
                      protocol))))))

(defun instantiate-provider
    (id &key api-key oauth-access-token oauth-account-id
             base-url model-id reasoning allow-missing-auth-p options)
  (let* ((definition (find-provider-definition id))
         (requires-key-p
           (and
            (provider-definition-key-environment definition)
            (not oauth-access-token))))
    (when (and requires-key-p
               (not allow-missing-auth-p)
               (not (non-empty-string-p api-key)))
      (error 'configuration-error
             :message
             (format nil "~A is not set"
                     (provider-definition-key-environment definition))))
    (let* ((resolved-id
             (or model-id
                 (provider-definition-default-model definition)))
           (metadata
             (ignore-errors
               (find-model-metadata id resolved-id)))
           (fallback-metadata
             (and
              (null metadata)
              (ignore-errors
                (find-model-metadata
                 id
                 (provider-definition-default-model definition)))))
           (effective-metadata
             (or metadata fallback-metadata))
           (protocol
             (or (and effective-metadata
                      (model-metadata-api effective-metadata))
                 (provider-definition-protocol definition))))
      (values
       (make-protocol-provider
        protocol definition api-key oauth-access-token oauth-account-id
        (if base-url
            (append (list :explicit-base-url base-url) options)
            options))
       (make-model
        :id resolved-id
        :provider id
        :api protocol
        :base-url
        (or base-url
            (and effective-metadata
                 (non-empty-string-p
                  (model-metadata-base-url effective-metadata))
                 (model-metadata-base-url effective-metadata))
            (provider-definition-base-url definition))
        :name
        (if (and metadata
                 (non-empty-string-p
                  (model-metadata-name metadata)))
            (model-metadata-name metadata)
            resolved-id)
        :max-tokens
        (if effective-metadata
            (model-metadata-max-output-tokens effective-metadata)
            4096)
        :context-window
        (if effective-metadata
            (model-metadata-context-window effective-metadata)
            0)
        :supports-images-p
        (if effective-metadata
            (model-metadata-supports-images-p effective-metadata)
            (provider-definition-supports-images-p definition))
        :supports-tools-p
        (if effective-metadata
            (model-metadata-supports-tools-p effective-metadata)
            (provider-definition-supports-tools-p definition))
        :reasoning-p
        (or
         (and
          (null metadata)
          reasoning
          (not (eq reasoning :off)))
         (if effective-metadata
             (model-metadata-reasoning-p effective-metadata)
             (provider-definition-reasoning-p definition)))
        :thinking-level-map
        (and effective-metadata
             (model-metadata-thinking-level-map effective-metadata))
        :headers
        (and effective-metadata
             (model-metadata-headers effective-metadata))
        :compat
        (and effective-metadata
             (model-metadata-compat effective-metadata)))))))
