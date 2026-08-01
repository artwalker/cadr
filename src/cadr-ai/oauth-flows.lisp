(in-package #:cadr-ai)

(defun default-oauth-flow-request (url &rest options)
  (multiple-value-bind (body status headers)
      (apply *oauth-http-request-function*
             url
             :force-string t
             options)
    (values
     (handler-case
         (parse-json (normalize-response-body body))
       (error () (json-object)))
     status headers)))

(defparameter *oauth-flow-request-function*
  #'default-oauth-flow-request)
(defparameter *oauth-flow-sleep-function* #'sleep)

(defun oauth-flow-request
    (url &key (method :get) headers content)
  (multiple-value-bind (object status response-headers)
      (funcall *oauth-flow-request-function*
               url
               :method method
               :headers headers
               :content content
               :connect-timeout 10
               :read-timeout 30)
    (unless (hash-table-p object)
      (error 'authentication-error
             :message "OAuth endpoint returned invalid JSON"))
    (values object status response-headers)))

(defun oauth-flow-post-form (url fields)
  (oauth-flow-request
   url
   :method :post
   :headers
   '(("accept" . "application/json")
     ("content-type" . "application/x-www-form-urlencoded"))
   :content (form-encode fields)))

(defun oauth-flow-post-json (url object &optional headers)
  (oauth-flow-request
   url
   :method :post
   :headers
   (append
    headers
    '(("accept" . "application/json")
      ("content-type" . "application/json")))
   :content (stringify-json object)))

(defun oauth-response-error-detail (object)
  (or (json-get object "error_description")
      (json-get object "message")
      (let ((error (json-get object "error")))
        (if (hash-table-p error)
            (json-get error "message")
            error))))

(defun ensure-oauth-response-success (provider action object status)
  (unless (<= 200 status 299)
    (let ((detail (oauth-response-error-detail object)))
      (error 'authentication-error
             :message
             (format nil "~A OAuth ~A failed (HTTP ~D)~A"
                     provider action status
                     (if detail (format nil ": ~A" detail) "")))))
  object)

(defun notify-device-authorization (interaction device)
  (runtime-auth-interaction-notify
   interaction
   (list
    :type :device-code
    :user-code (getf device :user-code)
    :verification-uri
    (or (getf device :verification-uri-complete)
        (getf device :verification-uri))
    :interval-seconds (getf device :interval)
    :expires-in-seconds (getf device :expires-in))))

(defun oauth-poll-token
    (poll device pending-errors slow-down-errors denied-errors expired-errors
     &key (complete-field "access_token"))
  (poll-device-authorization
   (lambda ()
     (multiple-value-bind (object status) (funcall poll)
       (if (and (<= 200 status 299)
                (non-empty-string-p
                 (json-get object complete-field)))
           (list :status :complete :value object)
           (let ((code (json-get object "error")))
             (cond
               ((member code pending-errors :test #'string=)
                (list :status :pending))
               ((member code slow-down-errors :test #'string=)
                (list :status :slow-down
                      :interval (json-get object "interval")))
               ((member code denied-errors :test #'string=)
                (list :status :denied))
               ((member code expired-errors :test #'string=)
                (list :status :expired))
               (t
                (error 'authentication-error
                       :message
                       (format nil "OAuth device token request failed (HTTP ~D)~A"
                               status
                               (let ((detail
                                       (oauth-response-error-detail object)))
                                 (if detail
                                     (format nil ": ~A" detail)
                                     ""))))))))))
   :interval (or (getf device :interval) 5)
   :expires-in (getf device :expires-in)
   :wait-before-first-poll-p t
   :sleep-function *oauth-flow-sleep-function*))

;;; xAI

(defparameter +xai-oauth-client-id+
  "b1a00492-073a-47ea-816f-4c329264a828")
(defparameter +xai-oauth-scope+
  "openid profile email offline_access grok-cli:access api:access")
(defparameter +xai-device-code-url+
  "https://auth.x.ai/oauth2/device/code")
(defparameter +xai-token-url+
  "https://auth.x.ai/oauth2/token")

(defun login-xai-oauth (interaction)
  (multiple-value-bind (response status)
      (oauth-flow-post-form
       +xai-device-code-url+
       `(("client_id" . ,+xai-oauth-client-id+)
         ("scope" . ,+xai-oauth-scope+)
         ("referrer" . "pi")))
    (ensure-oauth-response-success "xAI" "device authorization"
                                   response status)
    (let ((device (parse-xai-device-authorization response)))
      (notify-device-authorization interaction device)
      (oauth-token-credential
       :xai
       (oauth-poll-token
        (lambda ()
          (oauth-flow-post-form
           +xai-token-url+
           `(("grant_type" . "urn:ietf:params:oauth:grant-type:device_code")
             ("client_id" . ,+xai-oauth-client-id+)
             ("device_code" . ,(getf device :device-code)))))
        device
        '("authorization_pending") '("slow_down")
        '("access_denied" "authorization_denied") '("expired_token"))
       :expiry-skew-milliseconds 300000))))

(defun refresh-xai-oauth-credential (credential)
  (multiple-value-bind (response status)
      (oauth-flow-post-form
       +xai-token-url+
       `(("grant_type" . "refresh_token")
         ("client_id" . ,+xai-oauth-client-id+)
         ("refresh_token" . ,(oauth-credential-refresh credential))))
    (ensure-oauth-response-success "xAI" "token refresh" response status)
    (oauth-token-credential
     :xai response
     :previous-refresh-token (oauth-credential-refresh credential)
     :expiry-skew-milliseconds 300000)))

;;; Kimi Code

(defparameter +kimi-oauth-client-id+
  "17e5f671-d194-4dfb-9706-5516cb48c098")
(defparameter +kimi-oauth-default-host+ "https://auth.kimi.com")

(defun kimi-oauth-host (&optional environment)
  (string-right-trim
   "/"
   (or (environment-value environment "KIMI_CODE_OAUTH_HOST")
       (environment-value environment "KIMI_OAUTH_HOST")
       +kimi-oauth-default-host+)))

(defun login-kimi-oauth (interaction &optional environment)
  (let ((host (kimi-oauth-host environment)))
    (multiple-value-bind (response status)
        (oauth-flow-post-form
         (format nil "~A/api/oauth/device_authorization" host)
         `(("client_id" . ,+kimi-oauth-client-id+)))
      (ensure-oauth-response-success "Kimi Code" "device authorization"
                                     response status)
      (let ((device (parse-kimi-device-authorization response)))
        (notify-device-authorization interaction device)
        (oauth-token-credential
         :kimi-coding
         (oauth-poll-token
          (lambda ()
            (oauth-flow-post-form
             (format nil "~A/api/oauth/token" host)
             `(("client_id" . ,+kimi-oauth-client-id+)
               ("device_code" . ,(getf device :device-code))
               ("grant_type" . "urn:ietf:params:oauth:grant-type:device_code"))))
          device
          '("authorization_pending") '("slow_down")
          '("access_denied") '("expired_token")))))))

(defun refresh-kimi-oauth-credential (credential &optional environment)
  (multiple-value-bind (response status)
      (oauth-flow-post-form
       (format nil "~A/api/oauth/token" (kimi-oauth-host environment))
       `(("client_id" . ,+kimi-oauth-client-id+)
         ("grant_type" . "refresh_token")
         ("refresh_token" . ,(oauth-credential-refresh credential))))
    (ensure-oauth-response-success "Kimi Code" "token refresh"
                                   response status)
    (oauth-token-credential
     :kimi-coding response
     :previous-refresh-token (oauth-credential-refresh credential))))

;;; GitHub Copilot

(defparameter +github-copilot-client-id+ "Iv1.b507a08c87ecfe98")
(defparameter +github-copilot-api-version+ "2026-06-01")
(defparameter +github-copilot-headers+
  '(("User-Agent" . "GitHubCopilotChat/0.35.0")
    ("Editor-Version" . "vscode/1.107.0")
    ("Editor-Plugin-Version" . "copilot-chat/0.35.0")
    ("Copilot-Integration-Id" . "vscode-chat")))

(defun normalize-github-domain (input)
  (let ((trimmed (string-trim '(#\Space #\Tab #\Return #\Newline) input)))
    (if (zerop (length trimmed))
        nil
        (handler-case
            (parsed-url-host
             (parse-http-url
              (if (search "://" trimmed)
                  trimmed
                  (format nil "https://~A" trimmed))))
          (error () nil)))))

(defun github-oauth-url (domain suffix)
  (format nil "https://~A~A" domain suffix))

(defun github-copilot-request-headers (access &rest extra)
  (append
   extra
   (list (cons "Authorization" (format nil "Bearer ~A" access)))
   +github-copilot-headers+))

(defun github-copilot-metadata-value (credential name)
  (cdr (assoc name (oauth-credential-metadata credential)
              :test #'string=)))

(defun fetch-github-copilot-model-ids (access &optional enterprise-domain)
  (multiple-value-bind (response status)
      (oauth-flow-request
       (format nil "~A/models"
               (github-copilot-base-url access enterprise-domain))
       :headers
       (github-copilot-request-headers
        access
        '("Accept" . "application/json")
        (cons "X-GitHub-Api-Version" +github-copilot-api-version+)))
    (ensure-oauth-response-success "GitHub Copilot" "model discovery"
                                   response status)
    (selectable-github-copilot-model-ids response)))

(defun request-github-copilot-token (github-token &optional enterprise-domain)
  (let ((domain (or enterprise-domain "github.com")))
    (multiple-value-bind (response status)
        (oauth-flow-request
         (format nil "https://api.~A/copilot_internal/v2/token" domain)
         :headers
         (github-copilot-request-headers
          github-token '("Accept" . "application/json")))
      (ensure-oauth-response-success "GitHub Copilot" "token exchange"
                                     response status)
      (let ((access (required-oauth-string response "token" "GitHub Copilot"))
            (expires (positive-oauth-number response "expires_at"
                                            "GitHub Copilot")))
        (make-oauth-credential
         :provider :github-copilot
         :access access
         :refresh github-token
         :expires (- (* expires 1000) 300000)
         :metadata
         (append
          (when enterprise-domain
            (list (cons "enterpriseUrl" enterprise-domain)))
          (list
           (cons "availableModelIds"
                 (coerce
                  (fetch-github-copilot-model-ids
                   access enterprise-domain)
                  'vector)))))))))

(defun login-github-copilot-oauth (interaction)
  (let* ((input
           (runtime-auth-interaction-prompt
            interaction
            '(:type :text
              :message "GitHub Enterprise URL/domain (blank for github.com)"
              :placeholder "company.ghe.com")))
         (trimmed
           (string-trim '(#\Space #\Tab #\Return #\Newline) input))
         (enterprise-domain (normalize-github-domain input)))
    (when (and (plusp (length trimmed)) (null enterprise-domain))
      (error 'authentication-error
             :message "Invalid GitHub Enterprise URL/domain"))
    (let ((domain (or enterprise-domain "github.com")))
      (multiple-value-bind (response status)
          (oauth-flow-post-form
           (github-oauth-url domain "/login/device/code")
           `(("client_id" . ,+github-copilot-client-id+)
             ("scope" . "read:user")))
        (ensure-oauth-response-success "GitHub" "device authorization"
                                       response status)
        (let ((device (parse-github-device-authorization response)))
          (notify-device-authorization interaction device)
          (let* ((token-response
                   (oauth-poll-token
                    (lambda ()
                      (oauth-flow-post-form
                       (github-oauth-url domain "/login/oauth/access_token")
                       `(("client_id" . ,+github-copilot-client-id+)
                         ("device_code" . ,(getf device :device-code))
                         ("grant_type" . "urn:ietf:params:oauth:grant-type:device_code"))))
                    device
                    '("authorization_pending") '("slow_down")
                    '("access_denied") '("expired_token")))
                 (github-token
                   (required-oauth-string token-response "access_token" "GitHub")))
            (runtime-auth-interaction-notify
             interaction '(:type :progress :message "Enabling models..."))
            (request-github-copilot-token github-token enterprise-domain)))))))

(defun refresh-github-copilot-oauth-credential (credential)
  (request-github-copilot-token
   (oauth-credential-refresh credential)
   (github-copilot-metadata-value credential "enterpriseUrl")))

(defun github-copilot-oauth-to-auth (credential)
  (make-runtime-auth-result
   :api-key (oauth-credential-access credential)
   :base-url
   (github-copilot-base-url
    (oauth-credential-access credential)
    (github-copilot-metadata-value credential "enterpriseUrl"))
   :source "OAuth" :type :oauth))

;;; OpenRouter

(defparameter +openrouter-authorize-url+ "https://openrouter.ai/auth")
(defparameter +openrouter-token-url+ "https://openrouter.ai/api/v1/auth/keys")

(defun parse-openrouter-authorization-input (input)
  (let* ((trimmed
           (string-trim '(#\Space #\Tab #\Return #\Newline) input))
         (question (position #\? trimmed))
         (query
           (cond
             (question (subseq trimmed (1+ question)))
             ((search "code=" trimmed) trimmed)
             (t nil))))
    (if query
        (gethash "code" (parse-query query))
        (and (non-empty-string-p trimmed) trimmed))))

(defun openrouter-exchange-code (code verifier)
  (multiple-value-bind (response status)
      (oauth-flow-post-json
       +openrouter-token-url+
       (json-object
        "code" code
        "code_verifier" verifier
        "code_challenge_method" "S256"))
    (ensure-oauth-response-success "OpenRouter" "key exchange"
                                   response status)
    (make-oauth-credential
     :provider :openrouter
     :access (required-oauth-string response "key" "OpenRouter")
     :refresh ""
     :expires most-positive-fixnum)))

(defun login-openrouter-oauth (interaction)
  (multiple-value-bind (verifier challenge) (generate-pkce)
    (let* ((callback
             (format nil "http://127.0.0.1:1457/oauth/callback/~A"
                     (oauth-state)))
           (url
             (format nil "~A?~A"
                     +openrouter-authorize-url+
                     (form-encode
                      `(("callback_url" . ,callback)
                        ("code_challenge" . ,challenge)
                        ("code_challenge_method" . "S256"))))))
      (runtime-auth-interaction-notify
       interaction
       (list :type :auth-url :url url
             :instructions
             "Complete sign-in in your browser. If the browser is on another machine, paste the final redirect URL here."))
      (let ((code
              (parse-openrouter-authorization-input
               (runtime-auth-interaction-prompt
                interaction
                (list
                 :type :manual-code
                 :message
                 "Complete sign-in in your browser, or paste the authorization code / redirect URL here:"
                 :placeholder callback)))))
        (unless code
          (error 'authentication-error
                 :message "Missing authorization code"))
        (runtime-auth-interaction-notify
         interaction
         '(:type :progress
           :message "Exchanging authorization code for an API key..."))
        (openrouter-exchange-code code verifier)))))

(defun refresh-openrouter-oauth-credential (credential)
  credential)

;;; Radius

(defparameter +radius-oauth-client-id+ "pi-gateway")
(defparameter +radius-oauth-scope+ "gateway offline_access")

(defun normalize-radius-gateway (gateway)
  (string-right-trim "/" gateway))

(defun radius-token-credential (gateway fields)
  (multiple-value-bind (response status)
      (oauth-flow-post-form
       (format nil "~A/v1/oauth/token" gateway) fields)
    (ensure-oauth-response-success "Radius" "token request"
                                   response status)
    (oauth-token-credential
     :radius response :expiry-skew-milliseconds 60000)))

(defun login-radius-device-oauth (gateway interaction)
  (multiple-value-bind (response status)
      (oauth-flow-post-form
       (format nil "~A/v1/oauth/device" gateway)
       `(("client_id" . ,+radius-oauth-client-id+)
         ("scope" . ,+radius-oauth-scope+)))
    (ensure-oauth-response-success "Radius" "device authorization"
                                   response status)
    (let ((device
            (list
             :device-code
             (required-oauth-string response "device_code" "Radius")
             :user-code
             (required-oauth-string response "user_code" "Radius")
             :verification-uri
             (required-oauth-string response "verification_uri" "Radius")
             :interval (or (json-get response "interval") 5)
             :expires-in
             (positive-oauth-number response "expires_in" "Radius"))))
      (unless (trusted-oauth-url-p (getf device :verification-uri))
        (error 'authentication-error
               :message "Untrusted verification URI in Radius OAuth response"))
      (notify-device-authorization interaction device)
      (oauth-token-credential
       :radius
       (oauth-poll-token
        (lambda ()
          (oauth-flow-post-form
           (format nil "~A/v1/oauth/token" gateway)
           `(("grant_type" . "urn:ietf:params:oauth:grant-type:device_code")
             ("client_id" . ,+radius-oauth-client-id+)
             ("device_code" . ,(getf device :device-code)))))
        device
        '("authorization_pending") '("slow_down")
        '("access_denied") '("expired_token"))
       :expiry-skew-milliseconds 60000))))

(defun login-radius-browser-oauth (gateway interaction)
  (multiple-value-bind (discovery status)
      (oauth-flow-request
       (format nil "~A/v1/oauth" gateway)
       :headers '(("accept" . "application/json")))
    (ensure-oauth-response-success "Radius" "discovery" discovery status)
    (multiple-value-bind (verifier challenge) (generate-pkce)
      (let* ((state (oauth-state))
             (endpoint
               (required-oauth-string
                discovery "authorizationEndpoint" "Radius"))
             (url (radius-authorization-url endpoint challenge state)))
        (unless (trusted-oauth-url-p endpoint :https-only-p t)
          (error 'authentication-error
                 :message "Untrusted Radius authorization endpoint"))
        (runtime-auth-interaction-notify
         interaction
         '(:type :progress
           :message "Listening for OAuth callback on http://127.0.0.1:1456/oauth/callback"))
        (runtime-auth-interaction-notify
         interaction
         (list :type :auth-url :url url
               :instructions "Continue in your browser."))
        (radius-token-credential
         gateway
         `(("grant_type" . "authorization_code")
           ("client_id" . ,+radius-oauth-client-id+)
           ("redirect_uri" . "http://127.0.0.1:1456/oauth/callback")
           ("code" . ,(wait-for-oauth-code
                        state 1456 "/oauth/callback" "Radius"))
           ("code_verifier" . ,verifier)))))))

(defun login-radius-oauth (gateway interaction)
  (let ((method
          (runtime-auth-interaction-prompt
           interaction
           '(:type :select :message "Sign in to Radius:"
             :options
             ((:id "browser" :label "Sign in with browser (recommended)")
              (:id "device-code"
               :label "Sign in with device code (when signing in from another device)"))))))
    (cond
      ((string= method "browser")
       (login-radius-browser-oauth gateway interaction))
      ((string= method "device-code")
       (login-radius-device-oauth gateway interaction))
      (t
       (error 'authentication-error
              :message (format nil "Unknown Radius sign-in method: ~A" method))))))

(defun refresh-radius-oauth-credential (gateway credential)
  (radius-token-credential
   gateway
   `(("grant_type" . "refresh_token")
     ("client_id" . ,+radius-oauth-client-id+)
     ("refresh_token" . ,(oauth-credential-refresh credential)))))

;;; Existing OAuth flows adapted to the runtime interaction contract.

(defun login-openai-runtime-oauth (interaction)
  (login-openai-oauth
   nil
   :auth-url-function
   (lambda (url)
     (runtime-auth-interaction-notify
      interaction
      (list :type :auth-url :url url
            :instructions "Continue in your browser.")))))

(defun login-anthropic-runtime-oauth (interaction)
  (login-anthropic-oauth
   nil
   :auth-url-function
   (lambda (url)
     (runtime-auth-interaction-notify
      interaction
      (list :type :auth-url :url url
            :instructions "Continue in your browser.")))))
