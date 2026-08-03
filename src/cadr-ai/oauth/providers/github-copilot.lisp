(in-package #:cadr-ai)

(defparameter +github-copilot-oauth-metadata+
  (make-oauth-provider-metadata
   :provider-name "GitHub Copilot"
   :method-name "GitHub Copilot"))

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
