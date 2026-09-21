(in-package #:cadr-ai)

(defparameter +meta-oauth-metadata+
  (make-oauth-provider-metadata
   :is-subscription-p t
   :provider-name "Meta"
   :method-name "Meta (Muse subscription)"
   :login-label "Sign in with Meta"))

;;; The identity token is not an inference key. It is stored as refresh
;;; and the minted Model API key as access, so the ordinary OAuth
;;; scheduler re-mints it. auth.meta.com issues no refresh grant, so a
;;; mint 401 or 403 means the user must /login meta again.

(defparameter +meta-oauth-client-id+ "1031625952748946")
(defparameter +meta-device-authorization-url+
  "https://auth.meta.com/oidc/device/authorization/")
(defparameter +meta-device-token-url+
  "https://auth.meta.com/oidc/device/token/")
(defparameter +meta-api-key-mint-url+
  "https://api.meta.ai/muse-code/key")
(defparameter +meta-api-key-lifetime-ms+ 86400000)

(defun meta-response-detail (object)
  (when (hash-table-p object)
    (loop for key in '("error_description" "detail" "message" "error")
          for value = (json-get object key)
          when (and (stringp value)
                    (plusp
                     (length
                      (string-trim
                       '(#\Space #\Tab #\Newline #\Return) value))))
            return
            (string-trim
             '(#\Space #\Tab #\Newline #\Return) value))))

(defun meta-error-suffix (object)
  (let ((detail (meta-response-detail object)))
    (if detail
        (format nil ": ~A" detail)
        "")))

(defun meta-string-error (object code)
  (let ((value (json-get object "error")))
    (and (stringp value) (string= value code))))

(defun start-meta-device-authorization ()
  (multiple-value-bind (response status)
      (oauth-flow-post-form
       +meta-device-authorization-url+
       `(("client_id" . ,+meta-oauth-client-id+)))
    (unless (<= 200 status 299)
      (error 'authentication-error
             :message
             (format nil
                     "Meta device authorization failed with status ~D~A"
                     status (meta-error-suffix response))))
    (parse-device-authorization
     response "Meta"
     :complete :optional
     :interval-policy :positive
     :untrusted-message
     "Untrusted verification URI in Meta OAuth response")))

(defun poll-meta-identity-token (device interaction)
  (let ((cancelled-p
          (and interaction
               (lambda ()
                 (runtime-auth-interaction-aborted-p interaction)))))
    (handler-case
        (let ((*native-http-abort-p* cancelled-p))
          (poll-device-authorization
           (lambda ()
             (multiple-value-bind (object status)
                 (oauth-flow-post-form
                  +meta-device-token-url+
                  `(("grant_type"
                     . "urn:ietf:params:oauth:grant-type:device_code")
                    ("device_code" . ,(getf device :device-code))
                    ("client_id" . ,+meta-oauth-client-id+)))
               (cond
                 ((and (<= 200 status 299)
                       (non-empty-string-p
                        (json-get object "access_token")))
                  (list :status :complete
                        :value (json-get object "access_token")))
                 ((meta-string-error object "authorization_pending")
                  (list :status :pending))
                 ((meta-string-error object "slow_down")
                  (list :status :slow-down
                        :interval (json-get object "interval")))
                 ((meta-string-error object "access_denied")
                  (list :status :failed
                        :message "Meta login was denied."))
                 ((meta-string-error object "expired_token")
                  (list :status :failed
                        :message
                        "Meta device authorization expired. Please restart login."))
                 (t
                  (list :status :failed
                        :message
                        (format nil
                                "Meta device token request failed with status ~D~A"
                                status (meta-error-suffix object)))))))
           :interval (or (getf device :interval) 5)
           :expires-in (or (getf device :expires-in) 900)
           :wait-before-first-poll-p t
           :cancelled-p cancelled-p
           :sleep-function *oauth-flow-sleep-function*))
      (request-aborted ()
        (signal-device-authorization-cancelled)))))

(defun mint-meta-api-key (identity-token)
  (multiple-value-bind (response status)
      (oauth-flow-post-json
       +meta-api-key-mint-url+
       (json-object)
       `(("authorization" . ,(format nil "Bearer ~A" identity-token))
         ("x-api-version" . "1.0.0")))
    (when (or (= status 401) (= status 403))
      (error 'authentication-error
             :message
             (format nil
                     "Meta session expired (status ~D). Run `/login meta` to sign in again.~A"
                     status (meta-error-suffix response))))
    (unless (<= 200 status 299)
      (error 'authentication-error
             :message
             (format nil "Meta API key mint failed with status ~D~A"
                     status (meta-error-suffix response))))
    (let ((api-key (json-get response "api_key")))
      (unless (non-empty-string-p api-key)
        (let ((action-url (json-get response "action_url")))
          (error 'authentication-error
                 :message
                 (format nil "Meta did not issue an API key.~A"
                         (if (trusted-oauth-url-p action-url)
                             (format nil " Complete setup at ~A" action-url)
                             "")))))
      (make-oauth-credential
       :provider :meta
       :refresh identity-token
       :access api-key
       :expires (+ (unix-milliseconds) +meta-api-key-lifetime-ms+)))))

(defun login-meta-oauth (interaction)
  (handler-case
      (let ((device (start-meta-device-authorization)))
        (notify-device-authorization interaction device)
        (let ((identity-token
                (poll-meta-identity-token device interaction)))
          (runtime-auth-interaction-notify
           interaction
           '(:type :progress
             :message "Enabling Meta Model API access..."))
          (mint-meta-api-key identity-token)))
    (request-aborted ()
      (signal-device-authorization-cancelled))))

(defun refresh-meta-oauth-credential (credential)
  (mint-meta-api-key (oauth-credential-refresh credential)))
