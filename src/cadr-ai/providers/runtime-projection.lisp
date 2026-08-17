(in-package #:cadr-ai)

(defun ambient-provider-environment ()
  (loop for name in +built-in-runtime-environment-names+
        for value = (uiop:getenv name)
        when (non-empty-string-p value)
          collect (cons name value)))

(defun merge-provider-environment (explicit ambient)
  (append
   explicit
   (remove-if
    (lambda (entry)
      (assoc (car entry) explicit :test #'string=))
    ambient)))

(defun provider-runtime-models (provider-id)
  (mapcar #'model-from-metadata
          (list-model-metadata provider-id)))

(defparameter +api-key-auth-strategy-table+
  '((:bedrock :structured-p t :login login-bedrock-api-key)
    (:vertex :structured-p t :login login-vertex-api-key)
    (:environment :structured-p nil :login nil)))

(defun api-key-auth-strategy-entry (strategy)
  (assoc strategy +api-key-auth-strategy-table+))

(defun provider-definition-structured-api-key-login-p (definition)
  "Whether the provider's API key login is a multi-step interaction flow
(baseline ApiKeyAuth.login with select/secret/text prompts and info
notices) rather than a single key entry.  This is the single owner of
which auth strategies are structured."
  (getf (cdr (api-key-auth-strategy-entry
              (provider-definition-api-key-auth-strategy definition)))
        :structured-p))

(defun built-in-api-key-login-function (definition)
  (let ((name
          (getf (cdr (api-key-auth-strategy-entry
                      (provider-definition-api-key-auth-strategy
                       definition)))
                :login)))
    (and name (symbol-function name))))

(defun built-in-api-key-auth
    (definition credential environment overrides)
  (let* ((explicit-key (getf overrides :api-key))
         (credential-key
           (and (typep credential 'api-key-credential)
                (api-key-credential-key credential)))
         (credential-environment
           (and (typep credential 'api-key-credential)
                (api-key-credential-environment credential)))
         (effective-environment
           (merge-provider-environment
            (append
             (or (getf overrides :environment) nil)
             credential-environment)
            environment))
         (key-name
           (provider-definition-key-environment definition))
         (key
           (or (and (non-empty-string-p explicit-key)
                    explicit-key)
               (and (non-empty-string-p credential-key)
                    credential-key)
               (and key-name
                    (environment-value
                     effective-environment key-name)))))
    (case (provider-definition-api-key-auth-strategy definition)
      (:bedrock
       (let ((resolved
               (resolve-bedrock-credentials
                effective-environment
                :bearer-token key)))
         (when resolved
           (make-runtime-auth-result
            :api-key (getf resolved :bearer-token)
            :environment effective-environment
            :source
            (ecase (getf resolved :source)
              (:bearer-token "AWS_BEARER_TOKEN_BEDROCK")
              (:profile "AWS profile")
              (:access-keys "AWS_ACCESS_KEY_ID")
              (:ecs-task-role "AWS ECS task role")
              (:web-identity "AWS web identity"))
            :type :api-key))))
      (:vertex
       (handler-case
           (let ((resolved
                   (resolve-vertex-auth
                    effective-environment
                    :api-key key)))
             (make-runtime-auth-result
              :api-key (getf resolved :api-key)
              :environment effective-environment
              :source
              (if (eq :api-key (getf resolved :type))
                  "GOOGLE_CLOUD_API_KEY"
                  "Google ADC")
              :type :api-key))
         (configuration-error () nil)))
      (:environment
       (when
           (or (non-empty-string-p key)
               (null key-name))
         (make-runtime-auth-result
          :api-key key
          :environment effective-environment
          :source
          (cond
            ((non-empty-string-p explicit-key)
             "Explicit API key")
            ((and (typep credential 'api-key-credential)
                  (non-empty-string-p credential-key))
             "Stored API key")
            (key-name key-name)
            (t "Keyless"))
          :type :api-key)))
      (otherwise nil))))

(defun built-in-oauth-to-auth (definition credential)
  (case (provider-definition-oauth-to-auth-strategy definition)
    (:github-copilot
     (github-copilot-oauth-to-auth credential))
    (:kimi-bearer
     (make-runtime-auth-result
      :headers
      (list
       (cons "Authorization"
             (format nil "Bearer ~A"
                     (oauth-credential-access credential))))
      :source "OAuth" :type :oauth))
    (:access-token
     (make-runtime-auth-result
      :api-key (oauth-credential-access credential)
      :source "OAuth" :type :oauth))
    (otherwise nil)))

(defun built-in-oauth-login-function
    (definition environment radius-gateway)
  (case (provider-definition-oauth-login-strategy definition)
    (:anthropic #'login-anthropic-runtime-oauth)
    (:github-copilot #'login-github-copilot-oauth)
    (:kimi
     (lambda (interaction)
       (login-kimi-oauth interaction environment)))
    (:openai-device #'login-openai-runtime-oauth)
    (:openrouter #'login-openrouter-oauth)
    (:radius
     (lambda (interaction)
       (login-radius-oauth radius-gateway interaction)))
    (:xai #'login-xai-oauth)
    (otherwise nil)))

(defun built-in-oauth-refresh-function
    (definition environment radius-gateway)
  (case (provider-definition-oauth-refresh-strategy definition)
    (:anthropic #'refresh-anthropic-oauth-credential)
    (:github-copilot #'refresh-github-copilot-oauth-credential)
    (:kimi
     (lambda (credential)
       (refresh-kimi-oauth-credential credential environment)))
    (:openai-device #'refresh-openai-oauth-credential)
    (:openrouter #'refresh-openrouter-oauth-credential)
    (:radius
     (lambda (credential)
       (refresh-radius-oauth-credential radius-gateway credential)))
    (:xai #'refresh-xai-oauth-credential)
    (otherwise nil)))

(defun built-in-model-filter-function (definition)
  (case (provider-definition-model-filter-strategy definition)
    (:github-available-models
     (lambda (models credential)
       (let ((available
               (and (typep credential 'oauth-credential)
                    (github-copilot-metadata-value
                     credential "availableModelIds"))))
         (if (vectorp available)
             (remove-if-not
              (lambda (model)
                (find (model-id model) available :test #'string=))
              models)
             models))))
    (otherwise nil)))

(defun built-in-provider-options (environment)
  (list
   :environment environment
   :azure-base-url
   (environment-value environment "AZURE_OPENAI_BASE_URL")
   :azure-resource-name
   (environment-value environment "AZURE_OPENAI_RESOURCE_NAME")
   :azure-deployment-name
   (environment-value environment "AZURE_OPENAI_DEPLOYMENT_NAME")
   :cloudflare-account-id
   (environment-value environment "CLOUDFLARE_ACCOUNT_ID")
   :cloudflare-gateway-id
   (environment-value environment "CLOUDFLARE_GATEWAY_ID")
   :project
   (or (environment-value environment "GOOGLE_CLOUD_PROJECT")
       (environment-value environment "GCLOUD_PROJECT"))
   :location
   (environment-value environment "GOOGLE_CLOUD_LOCATION")))

(defun built-in-runtime-dispatch
    (definition model context options stream-p on-event)
  (let* ((auth-type (getf options :auth-type))
         (api-key (getf options :api-key))
         (environment (getf options :environment))
         (provider
           (make-protocol-provider
            (model-api model)
            definition
            (and (not (eq auth-type :oauth)) api-key)
            (and (eq auth-type :oauth) api-key)
            nil
            (built-in-provider-options environment))))
    (if stream-p
        (apply #'stream-chat
               provider model context on-event
               (remove-runtime-only-options options))
        (apply #'complete-chat
               provider model context
               (remove-runtime-only-options options)))))

(defun remove-runtime-only-options (options)
  (loop for (key value) on options by #'cddr
        unless (member key
                       '(:api-key :headers :environment :auth-type))
          append (list key value)))

(defun make-built-in-runtime-provider (definition &optional environment)
  (let ((provider-id
          (provider-definition-id definition))
        (radius-gateway
          (normalize-radius-gateway
           (or (environment-value environment "RADIUS_GATEWAY_URL")
               (provider-definition-base-url definition)))))
    (make-runtime-provider
     :id provider-id
     :name (provider-definition-name definition)
     :oauth-metadata
     (provider-definition-oauth-metadata definition)
     :models (provider-runtime-models provider-id)
     :api-key-auth-p
     (not
      (null
       (member :api-key
               (provider-definition-auth-types definition))))
     :api-key-login-function
     (built-in-api-key-login-function definition)
     :oauth-auth-p
     (not
      (null
       (member :oauth
               (provider-definition-auth-types definition))))
     :auth-resolver
     (lambda (credential environment overrides)
       (built-in-api-key-auth
        definition credential environment overrides))
     :oauth-login-function
     (built-in-oauth-login-function definition environment radius-gateway)
     :oauth-refresh-function
     (built-in-oauth-refresh-function definition environment radius-gateway)
     :oauth-to-auth-function
     (lambda (credential)
       (built-in-oauth-to-auth definition credential))
     :filter-function
     (built-in-model-filter-function definition)
     :complete-function
     (lambda (model context options)
       (built-in-runtime-dispatch
        definition model context options nil nil))
     :stream-function
     (lambda (model context on-event &rest options)
       (built-in-runtime-dispatch
        definition model context options t on-event)))))

(defun make-built-in-models-runtime
    (&key credential-store model-store environment)
  (let ((runtime
          (make-models-runtime
           :credential-store credential-store
           :model-store model-store
           :environment
           (merge-provider-environment
            environment
            (ambient-provider-environment)))))
    (dolist (definition (list-provider-definitions))
      (models-runtime-set-provider
       runtime
       (make-built-in-runtime-provider
        definition (models-runtime-environment runtime))))
    runtime))
