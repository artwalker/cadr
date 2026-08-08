(in-package #:cadr-ai)

(defparameter +kimi-coding-oauth-metadata+
  (make-oauth-provider-metadata
   :provider-name "Kimi For Coding"
   :method-name "Kimi Code (subscription)"
   :login-label "Sign in with Kimi Code"))

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
          '("access_denied") '("expired_token")
          :interaction interaction))))))

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
