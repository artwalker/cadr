(in-package #:cadr-ai)

(defparameter +radius-oauth-metadata+
  (make-oauth-provider-metadata
   :provider-name "Radius"
   :method-name "Radius"
   :auth-url-instructions "Continue in your browser."))

(defun normalize-radius-gateway (gateway)
  (let* ((raw (or gateway ""))
         (with-scheme
           (if (or (and (>= (length raw) 7)
                        (string-equal "http://" raw :end2 7))
                   (and (>= (length raw) 8)
                        (string-equal "https://" raw :end2 8)))
               raw
               (concatenate 'string "https://" raw))))
    (string-right-trim "/" with-scheme)))

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
            (parse-device-authorization
             response "Radius"
             :interval-policy :or-default
             :default-interval 5
             :untrusted-message
             "Untrusted verification URI in Radius OAuth response")))
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
        '("access_denied") '("expired_token")
        :interaction interaction)
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
               :instructions
               (oauth-provider-metadata-auth-url-instructions
                +radius-oauth-metadata+)))
        (radius-token-credential
         gateway
         `(("grant_type" . "authorization_code")
           ("client_id" . ,+radius-oauth-client-id+)
           ("redirect_uri" . "http://127.0.0.1:1456/oauth/callback")
           ("code" . ,(let ((code
                              (wait-for-oauth-code
                               state 1456 "/oauth/callback" "Radius"
                               (lambda ()
                                 (runtime-auth-interaction-aborted-p
                                  interaction)))))
                        (unless code
                          (signal-device-authorization-cancelled))
                        code))
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
