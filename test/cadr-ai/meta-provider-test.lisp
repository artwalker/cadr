(in-package #:cadr-ai/tests)
(in-suite cadr-ai-suite)

(test meta-provider-definition-and-api-key-lookup
  (let ((definition (cadr-ai:find-provider-definition :meta)))
    (is (eq :meta (cadr-ai:provider-definition-id definition)))
    (is (string= "Meta" (cadr-ai:provider-definition-name definition)))
    (is (eq :openai-responses
            (cadr-ai:provider-definition-protocol definition)))
    (is (string= "https://api.meta.ai/v1"
                 (cadr-ai:provider-definition-base-url definition)))
    (is (string= "META_API_KEY"
                 (cadr-ai:provider-definition-key-environment definition)))
    (is (string= "muse-spark-1.3"
                 (cadr-ai:provider-definition-default-model definition)))
    (is (equal '(:api-key :oauth)
               (cadr-ai:provider-definition-auth-types definition)))
    (is (cadr-ai:provider-oauth-subscription-p :meta))
    (is (member "META_API_KEY"
                cadr-ai::+built-in-runtime-environment-names+
                :test #'string=)))
  (let ((present
          (cadr-ai:make-built-in-models-runtime
           :environment '(("META_API_KEY" . "fixture-meta-key"))))
        (absent
          (cadr-ai:make-built-in-models-runtime :environment nil)))
    (is (string= "fixture-meta-key"
                 (cadr-ai:runtime-auth-result-api-key
                  (cadr-ai:models-runtime-auth present :meta))))
    (is (null (cadr-ai:models-runtime-auth absent :meta)))
    (is (eq :api-key
            (cadr-ai:runtime-auth-check-type
             (cadr-ai:models-runtime-check-auth present :meta))))
    (is (null (cadr-ai:models-runtime-check-auth absent :meta))))
  (let ((spark (cadr-ai:find-model-metadata :meta "muse-spark-1.3")))
    (is (= 5 (length (cadr-ai:list-model-metadata :meta))))
    (is (eq :openai-responses (cadr-ai:model-metadata-api spark)))
    (is (string= "https://api.meta.ai/v1"
                 (cadr-ai:model-metadata-base-url spark)))
    (is (eq t (cadr-ai:model-metadata-supports-images-p spark)))
    (is (equal '((:off)
                 (:minimal . "minimal")
                 (:low . "low")
                 (:medium . "medium")
                 (:high . "high")
                 (:xhigh . "xhigh")
                 (:max . "max"))
               (cadr-ai:model-metadata-thinking-level-map spark)))))

(defun meta-oauth-script (responses requests)
  (lambda (url &rest options)
    (push (list url options) (cdr requests))
    (let ((response (pop (car responses))))
      (unless response
        (error "Unexpected Meta OAuth request to ~A" url))
      (values-list response))))

(test meta-device-login-mints-model-api-key
  (let* ((events nil)
         (requests (cons nil nil))
         (responses
           (list
            (list
             (cadr-ai::json-object
              "device_code" "device-code-123"
              "user_code" "ABCD-1234"
              "verification_uri" "https://auth.meta.com/oauth/device/"
              "verification_uri_complete"
              "https://auth.meta.com/oauth/device/?code=ABCD-1234"
              "interval" 5
              "expires_in" 600)
             200)
            (list
             (cadr-ai::json-object "error" "authorization_pending")
             400)
            (list
             (cadr-ai::json-object
              "access_token" "identity-token"
              "token_type" "Bearer")
             200)
            (list
             (cadr-ai::json-object "api_key" "LLM|minted-key")
             200)))
         (interaction
           (cadr-ai:make-runtime-auth-interaction
            :notify-function (lambda (event) (push event events)))))
    (let ((cadr-ai::*oauth-flow-request-function*
            (meta-oauth-script (cons responses nil) requests))
          (cadr-ai::*oauth-flow-sleep-function*
            (lambda (seconds) (declare (ignore seconds))))
          (before (cadr-ai::unix-milliseconds)))
      (let ((credential (cadr-ai::login-meta-oauth interaction)))
        (let ((after (cadr-ai::unix-milliseconds)))
          (is (eq :meta (cadr-ai:oauth-credential-provider credential)))
          (is (string= "identity-token"
                       (cadr-ai:oauth-credential-refresh credential)))
          (is (string= "LLM|minted-key"
                       (cadr-ai:oauth-credential-access credential)))
          (is (<= (+ before cadr-ai::+meta-api-key-lifetime-ms+)
                  (cadr-ai:oauth-credential-expires credential)
                  (+ after cadr-ai::+meta-api-key-lifetime-ms+))))))
    (let* ((oldest-first (reverse (cdr requests)))
           (device-options (second (first oldest-first)))
           (token-options (second (second oldest-first)))
           (mint-options (second (fourth oldest-first))))
      (is (equal '("https://auth.meta.com/oidc/device/authorization/"
                   "https://auth.meta.com/oidc/device/token/"
                   "https://auth.meta.com/oidc/device/token/"
                   "https://api.meta.ai/muse-code/key")
                 (mapcar #'first oldest-first)))
      (is (search "client_id=1031625952748946"
                  (getf device-options :content)))
      (is (search "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code"
                  (getf token-options :content)))
      (is (search "device_code=device-code-123"
                  (getf token-options :content)))
      (is (equal "Bearer identity-token"
                 (cdr (assoc "authorization"
                             (getf mint-options :headers)
                             :test #'string=))))
      (is (equal "1.0.0"
                 (cdr (assoc "x-api-version"
                             (getf mint-options :headers)
                             :test #'string=)))))
    (let ((device-event
            (find :device-code events :key (lambda (event) (getf event :type))))
          (progress
            (find :progress events :key (lambda (event) (getf event :type)))))
      (is (string= "ABCD-1234" (getf device-event :user-code)))
      (is (string= "https://auth.meta.com/oauth/device/?code=ABCD-1234"
                   (getf device-event :verification-uri)))
      (is (= 5 (getf device-event :interval-seconds)))
      (is (= 600 (getf device-event :expires-in-seconds)))
      (is (string= "Enabling Meta Model API access..."
                   (getf progress :message))))))

(test meta-oauth-refresh-remints-from-identity-token
  (let* ((requests (cons nil nil))
         (responses
           (list
            (list
             (cadr-ai::json-object "api_key" "LLM|fresh-key")
             200)))
         (before (cadr-ai::unix-milliseconds)))
    (let ((cadr-ai::*oauth-flow-request-function*
            (meta-oauth-script (cons responses nil) requests)))
      (let ((credential
              (cadr-ai::refresh-meta-oauth-credential
               (cadr-ai:make-oauth-credential
                :provider :meta
                :refresh "identity-token"
                :access "LLM|old-key"
                :expires 1))))
        (let ((after (cadr-ai::unix-milliseconds)))
          (is (string= "https://api.meta.ai/muse-code/key"
                       (first (first (cdr requests)))))
          (is (equal "Bearer identity-token"
                     (cdr (assoc "authorization"
                                 (getf (second (first (cdr requests)))
                                       :headers)
                                 :test #'string=))))
          (is (string= "identity-token"
                       (cadr-ai:oauth-credential-refresh credential)))
          (is (string= "LLM|fresh-key"
                       (cadr-ai:oauth-credential-access credential)))
          (is (<= (+ before cadr-ai::+meta-api-key-lifetime-ms+)
                  (cadr-ai:oauth-credential-expires credential)
                  (+ after cadr-ai::+meta-api-key-lifetime-ms+))))))))

(test meta-oauth-reports-setup-url-when-no-key-is-issued
  (let ((cadr-ai::*oauth-flow-request-function*
          (lambda (url &rest options)
            (declare (ignore url options))
            (values
             (cadr-ai::json-object
              "require_payment" t
              "action_url" "https://dev.meta.ai/billing")
             200))))
    (handler-case
        (progn
          (cadr-ai::refresh-meta-oauth-credential
           (cadr-ai:make-oauth-credential
            :provider :meta
            :refresh "identity-token"
            :access ""
            :expires 1))
          (is nil "mint should have failed"))
      (cadr-ai:authentication-error (condition)
        (is (string= "Meta did not issue an API key. Complete setup at https://dev.meta.ai/billing"
                     (cadr-ai:cadr-error-message condition)))))))

(test meta-oauth-uses-minted-key-as-request-api-key
  (let* ((runtime (cadr-ai:make-built-in-models-runtime :environment nil))
         (provider (cadr-ai:models-runtime-provider runtime :meta))
         (auth
           (funcall
            (cadr-ai::runtime-provider-oauth-to-auth-function provider)
            (cadr-ai:make-oauth-credential
             :provider :meta
             :refresh "identity-token"
             :access "LLM|key"
             :expires 1))))
    (is (string= "LLM|key" (cadr-ai:runtime-auth-result-api-key auth)))
    (is (eq :oauth (cadr-ai:runtime-auth-result-type auth)))))
