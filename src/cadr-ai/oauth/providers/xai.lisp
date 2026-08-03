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

(defparameter +xai-oauth-metadata+
  (make-oauth-provider-metadata
   :provider-name "xAI"
   :method-name "xAI (Grok/X subscription)"
   :login-label "Sign in with SuperGrok or X Premium"))

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
