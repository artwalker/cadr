(in-package #:cadr-ai)

(defparameter +meta-oauth-metadata+
  (make-oauth-provider-metadata
   :is-subscription-p t
   :provider-name "Meta"
   :method-name "Meta (Muse subscription)"
   :login-label "Sign in with Meta"))

(defparameter +meta-oauth-client-id+ "1031625952748946")
(defparameter +meta-device-authorization-url+
  "https://auth.meta.com/oidc/device/authorization/")
(defparameter +meta-device-token-url+
  "https://auth.meta.com/oidc/device/token/")
(defparameter +meta-api-key-mint-url+
  "https://api.meta.ai/muse-code/key")
(defparameter +meta-api-key-lifetime-ms+ (* 24 60 60 1000))
(defparameter +meta-device-token-failure-messages+
  '(("access_denied" . "Meta login was denied.")
    ("expired_token" . "Meta device authorization expired. Please restart login.")))
(defparameter +meta-device-flow-timeout-message+
  "Device flow timed out")
(defparameter +meta-device-flow-slow-down-timeout-message+
  "Device flow timed out after one or more slow_down responses. This is often caused by clock drift in WSL or VM environments. Please sync or restart the VM clock and try again.")

(defvar *meta-unix-milliseconds-function* #'unix-milliseconds)

(defun meta-error-detail (object)
  (or (and (hash-table-p object)
           (dolist (key '("error_description" "detail" "message" "error"))
             (let ((value (json-get object key)))
               (when (stringp value)
                 (let ((trimmed
                         (string-trim
                          '(#\Space #\Tab #\Newline #\Return #\Page #\Vt)
                          value)))
                   (when (plusp (length trimmed))
                     (return (format nil ": ~A" trimmed))))))))
      ""))

(defun meta-positive-number (value)
  (when (and (realp value)
             (plusp value)
             (not (and (floatp value)
                       (or (sb-ext:float-infinity-p value)
                           (sb-ext:float-nan-p value)))))
    value))

(defun meta-trusted-http-url (value)
  (when (trusted-oauth-url-p value)
    value))

(defun meta-nonempty-string (value)
  (and (stringp value) (plusp (length value)) value))

(defun meta-authentication-error (message)
  (error 'authentication-error :message message))

(defun start-meta-device-authorization ()
  (multiple-value-bind (object status)
      (oauth-flow-post-form
       +meta-device-authorization-url+
       `(("client_id" . ,+meta-oauth-client-id+)))
    (unless (<= 200 status 299)
      (meta-authentication-error
       (format nil "Meta device authorization failed with status ~D~A"
               status (meta-error-detail object))))
    (let* ((device-code (meta-nonempty-string (json-get object "device_code")))
           (user-code (meta-nonempty-string (json-get object "user_code")))
           (complete
             (meta-trusted-http-url
              (json-get object "verification_uri_complete")))
           (verification
             (meta-trusted-http-url
              (json-get object "verification_uri"))))
      (unless (and device-code user-code (or complete verification))
        (meta-authentication-error
         (format nil "Invalid Meta device authorization response: ~A"
                 (stringify-json object))))
      (list :device-code device-code
            :user-code user-code
            :verification-uri (or verification complete)
            :verification-uri-complete complete
            :interval (meta-positive-number (json-get object "interval"))
            :expires-in (meta-positive-number (json-get object "expires_in"))))))

(defun meta-device-token-result (object status)
  (let ((access (json-get object "access_token")))
    (if (and (<= 200 status 299) (meta-nonempty-string access))
        (list :status :complete :value access)
        (let ((code (json-get object "error")))
          (cond
            ((equal code "authorization_pending")
             (list :status :pending))
            ((equal code "slow_down")
             (list :status :slow-down
                   :interval
                   (meta-positive-number (json-get object "interval"))))
            ((and (stringp code)
                  (assoc code +meta-device-token-failure-messages+
                         :test #'string=))
             (list :status :failed
                   :message
                   (cdr (assoc code +meta-device-token-failure-messages+
                               :test #'string=))))
            (t
             (list :status :failed
                   :message
                   (format nil
                           "Meta device token request failed with status ~D~A"
                           status
                           (meta-error-detail object)))))))))

(defun poll-meta-identity-token (device cancelled-p)
  (poll-device-authorization
   (lambda ()
     (multiple-value-bind (object status)
         (oauth-flow-post-form
          +meta-device-token-url+
          `(("grant_type" . "urn:ietf:params:oauth:grant-type:device_code")
            ("device_code" . ,(getf device :device-code))
            ("client_id" . ,+meta-oauth-client-id+)))
       (meta-device-token-result object status)))
   :interval (or (getf device :interval) 5)
   :expires-in (or (getf device :expires-in) most-positive-fixnum)
   :wait-before-first-poll-p t
   :cancelled-p cancelled-p
   :timeout-message +meta-device-flow-timeout-message+
   :slow-down-timeout-message +meta-device-flow-slow-down-timeout-message+
   :sleep-function *oauth-flow-sleep-function*
   :time-function
   (lambda ()
     (floor (funcall *meta-unix-milliseconds-function*) 1000))))

(defun mint-meta-api-key (identity-token)
  ;; auth.meta.com does not issue a refresh_token. A 401 or 403 from the
  ;; mint endpoint means the stored identity token is dead.
  (multiple-value-bind (object status)
      (oauth-flow-request
       +meta-api-key-mint-url+
       :method :post
       :headers
       `(("Accept" . "application/json")
         ("Authorization" . ,(format nil "Bearer ~A" identity-token))
         ("Content-Type" . "application/json")
         ("x-api-version" . "1.0.0"))
       :content "{}")
    (cond
      ((or (= status 401) (= status 403))
       (meta-authentication-error
        (format nil
                "Meta session expired (status ~D). Run `/login meta` to sign in again.~A"
                status (meta-error-detail object))))
      ((not (<= 200 status 299))
        (meta-authentication-error
         (format nil "Meta API key mint failed with status ~D~A"
                 status (meta-error-detail object))))
      (t
       (let ((api-key (json-get object "api_key"))
             (action
               (meta-trusted-http-url (json-get object "action_url"))))
         (unless (meta-nonempty-string api-key)
           (meta-authentication-error
            (format nil "Meta did not issue an API key.~A"
                    (if action
                        (format nil " Complete setup at ~A" action)
                        ""))))
         (make-oauth-credential
          :provider :meta
          :refresh identity-token
          :access api-key
          :expires (+ (funcall *meta-unix-milliseconds-function*)
                      +meta-api-key-lifetime-ms+)))))))

(defun login-meta-oauth (interaction)
  (let ((cancelled-p
          (lambda ()
            (runtime-auth-interaction-aborted-p interaction))))
    (handler-case
        (let ((*native-http-abort-p* cancelled-p))
          (let ((device (start-meta-device-authorization)))
            (notify-device-authorization interaction device)
            (let ((identity
                    (poll-meta-identity-token device cancelled-p)))
              (runtime-auth-interaction-notify
               interaction
               '(:type :progress
                 :message "Enabling Meta Model API access..."))
              (mint-meta-api-key identity))))
      (request-aborted ()
        (signal-device-authorization-cancelled))
      (authentication-cancelled ()
        (signal-device-authorization-cancelled))
      (error (condition)
        (if (funcall cancelled-p)
            (signal-device-authorization-cancelled)
            (error condition))))))

(defun refresh-meta-oauth-credential (credential)
  (mint-meta-api-key (oauth-credential-refresh credential)))
