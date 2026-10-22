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
   :compat (model-compat model)
   :sampling-params (model-sampling-params model)
   :sampling-params-by-thinking-level
   (model-sampling-params-by-thinking-level model)))

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
    ((provider provider) model context &rest args)
  (let ((*provider-request-transcript*
          (or *provider-request-transcript*
              (ensure-transcript-context context))))
    (let* ((request-context
             (coerce-provider-request-context model context))
         (resolved-model (cloudflare-model provider model))
         (request
           (apply #'call-next-method
                  provider resolved-model request-context args))
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
       (dolist (header (copilot-request-headers request-context))
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
    request)))

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

(defun azure-environment-value (provider name)
  (let ((environment (option-value provider :environment)))
    (if (and (listp environment)
             (assoc name environment :test #'string=))
        (cdr (assoc name environment :test #'string=))
        (uiop:getenv name))))

(defun azure-deployment-for (provider model)
  (resolve-azure-deployment-name
   (model-id model)
   (option-value provider :azure-deployment-name)
   (or (option-value provider :azure-deployment-name-map)
       (azure-environment-value
        provider "AZURE_OPENAI_DEPLOYMENT_NAME_MAP"))))

(defun azure-base-url (provider model)
  (let ((explicit
          (or (option-value provider :azure-base-url)
              (azure-environment-value
               provider "AZURE_OPENAI_BASE_URL")))
        (resource
          (or (option-value provider :azure-resource-name)
              (azure-environment-value
               provider "AZURE_OPENAI_RESOURCE_NAME"))))
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
             "Azure OpenAI base URL is required. Set AZURE_OPENAI_BASE_URL or AZURE_OPENAI_RESOURCE_NAME, or pass azureBaseUrl, azureResourceName, or model.baseUrl.")))))

(defparameter *azure-completions-parser*
  nil)

(defun azure-completions-parser ()
  (or *azure-completions-parser*
      (setf *azure-completions-parser*
            (make-openai-completions-provider :api-key "azure"))))

(defun present-azure-version (value)
  (and (stringp value) (plusp (length value)) value))

(defun azure-api-version (provider)
  ;; pi@4a080252f packages/ai/src/api/azure-openai-config.ts
  ;; resolveAzureConfig: azureApiVersion, then AZURE_OPENAI_API_VERSION,
  ;; then "v1". Empty strings are skipped the way JavaScript || skips them.
  (or (present-azure-version
       (option-value provider :azure-api-version))
      (present-azure-version
       (let ((environment (option-value provider :environment)))
         (when (listp environment)
           (cdr (assoc "AZURE_OPENAI_API_VERSION"
                       environment
                       :test #'string=)))))
      (present-azure-version
       (uiop:getenv "AZURE_OPENAI_API_VERSION"))
      "v1"))

(defun azure-completions-request (provider model context args)
  (let* ((base (azure-base-url provider model))
         (deployment (azure-deployment-for provider model))
         (delegate
           (make-openai-completions-provider
            :api-key (require-api-key provider)))
         (request
           (apply #'build-request
                  delegate
                  (copy-model-with model :base-url base)
                  context
                  args)))
    (json-put (request-spec-payload request) "model" deployment)
    request))

(defmethod build-request
    ((provider azure-openai-provider) model context
     &rest args)
  (when (eq (model-api model) :openai-completions)
    (return-from build-request
      (azure-completions-request provider model context args)))
  (let* ((key (require-api-key provider))
         (base (azure-base-url provider model))
         (deployment (azure-deployment-for provider model))
         (delegate
           (make-openai-provider :api-key key))
         (request
           (apply #'build-request
                  delegate
                  (copy-model-with model
                                   :api :openai-responses
                                   :base-url base)
                  context
                  args)))
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
     (model-provider model))
    (let ((api-version (azure-api-version provider))
          (url (request-spec-url request)))
      (setf (request-spec-url request)
            (format nil "~A~Capi-version=~A"
                    url
                    (if (position #\? url) #\& #\?)
                    api-version)))
    request))

(defmethod reduce-provider-sse-event
    ((provider azure-openai-provider) state event emit)
  (if (eq (model-api (provider-stream-state-model state))
          :openai-completions)
      (reduce-provider-sse-event
       (azure-completions-parser) state event emit)
      (call-next-method)))

(defmethod parse-complete-response
    ((provider azure-openai-provider) model response)
  (if (eq (model-api model) :openai-completions)
      (parse-complete-response
       (azure-completions-parser) model response)
      (call-next-method)))

(defmethod finalize-provider-stream
    ((provider azure-openai-provider) model state emit)
  (if (eq (model-api model) :openai-completions)
      (finalize-provider-stream
       (azure-completions-parser) model state emit)
      (call-next-method)))
