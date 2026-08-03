(in-package #:cadr-ai)

(defun environment-value (environment name)
  (cdr (assoc name environment :test #'string=)))

(defun placeholder-api-key-p (value)
  (member value '("<authenticated>" "gcp-vertex-credentials")
          :test #'string=))

(defun resolve-bedrock-credentials
    (environment &key profile bearer-token)
  (let ((resolved-profile
          (or profile
              (environment-value environment "AWS_PROFILE")))
        (resolved-bearer
          (or bearer-token
              (environment-value
               environment "AWS_BEARER_TOKEN_BEDROCK"))))
    (cond
      ((non-empty-string-p resolved-bearer)
       (list :source :bearer-token :bearer-token resolved-bearer))
      ((non-empty-string-p resolved-profile)
       (list :source :profile :profile resolved-profile))
      ((and
        (non-empty-string-p
         (environment-value environment "AWS_ACCESS_KEY_ID"))
        (non-empty-string-p
         (environment-value environment "AWS_SECRET_ACCESS_KEY")))
       (list
        :source :access-keys
        :access-key-id
        (environment-value environment "AWS_ACCESS_KEY_ID")
        :secret-access-key
        (environment-value environment "AWS_SECRET_ACCESS_KEY")
        :session-token
        (environment-value environment "AWS_SESSION_TOKEN")))
      ((or
        (environment-value
         environment "AWS_CONTAINER_CREDENTIALS_RELATIVE_URI")
        (environment-value
         environment "AWS_CONTAINER_CREDENTIALS_FULL_URI"))
       (list :source :ecs-task-role))
      ((environment-value environment "AWS_WEB_IDENTITY_TOKEN_FILE")
       (list :source :web-identity))
      (t nil))))

(defun aws-ini-sections (text)
  (let ((sections (make-hash-table :test #'equal))
        (current nil))
    (dolist
        (raw-line
         (uiop:split-string
          text :separator '(#\Linefeed #\Return)))
      (let ((line (string-trim '(#\Space #\Tab) raw-line)))
        (cond
          ((or (zerop (length line))
               (member (char line 0) '(#\# #\;)))
           nil)
          ((and (> (length line) 2)
                (char= (char line 0) #\[)
                (char= (char line (1- (length line))) #\]))
           (setf current
                 (string-downcase
                  (string-trim
                   '(#\Space #\Tab)
                   (subseq line 1 (1- (length line))))))
           (unless (gethash current sections)
             (setf (gethash current sections)
                   (make-hash-table :test #'equal))))
          (current
           (let ((equals (position #\= line)))
             (when equals
               (let ((key
                       (string-downcase
                        (string-trim
                         '(#\Space #\Tab)
                         (subseq line 0 equals))))
                     (value
                       (string-trim
                        '(#\Space #\Tab)
                        (subseq line (1+ equals)))))
                 (setf
                  (gethash key
                           (gethash current sections))
                  value))))))))
    sections))

(defun aws-ini-value (sections section key)
  (let ((values
          (gethash (string-downcase section) sections)))
    (and values
         (gethash (string-downcase key) values))))

(defun default-aws-credentials-path ()
  (namestring
   (merge-pathnames ".aws/credentials"
                    (user-homedir-pathname))))

(defun default-aws-config-path ()
  (namestring
   (merge-pathnames ".aws/config"
                    (user-homedir-pathname))))

(defun load-bedrock-profile-credentials
    (profile &key
               (credentials-file
                 (default-aws-credentials-path))
               credentials-text)
  (let* ((text
           (or credentials-text
               (and (probe-file credentials-file)
                    (uiop:read-file-string credentials-file))))
         (sections (and text (aws-ini-sections text)))
         (access
           (and sections
                (aws-ini-value
                 sections profile "aws_access_key_id")))
         (secret
           (and sections
                (aws-ini-value
                 sections profile "aws_secret_access_key"))))
    (when (and (non-empty-string-p access)
               (non-empty-string-p secret))
      (list
       :source :access-keys
       :profile profile
       :access-key-id access
       :secret-access-key secret
       :session-token
       (aws-ini-value sections profile "aws_session_token")))))

(defun resolve-bedrock-profile-region
    (profile &key
               (config-file (default-aws-config-path))
               config-text)
  (let* ((text
           (or config-text
               (and (probe-file config-file)
                    (uiop:read-file-string config-file))))
         (sections (and text (aws-ini-sections text))))
    (and sections
         (or
          (aws-ini-value sections
                         (format nil "profile ~A" profile)
                         "region")
          (aws-ini-value sections profile "region")))))

(defun bedrock-arn-region (model-id)
  (when (uiop:string-prefix-p "arn:" model-id)
    (let ((parts (split-on-character model-id #\:)))
      (when (and (>= (length parts) 4)
                 (string= "bedrock" (nth 2 parts))
                 (non-empty-string-p (nth 3 parts)))
        (nth 3 parts)))))

(defun resolve-bedrock-region
    (model-id explicit-region environment-region
     &optional endpoint-region)
  (or (bedrock-arn-region model-id)
      explicit-region
      environment-region
      endpoint-region
      "us-east-1"))

(defun default-adc-path ()
  (namestring
   (merge-pathnames
    ".config/gcloud/application_default_credentials.json"
    (user-homedir-pathname))))

(defun resolve-vertex-auth
    (environment &key api-key
                   (file-exists-p #'probe-file))
  (let ((resolved-key
          (or api-key
              (environment-value environment
                                 "GOOGLE_CLOUD_API_KEY"))))
    (when (and (non-empty-string-p resolved-key)
               (not (placeholder-api-key-p resolved-key)))
      (return-from resolve-vertex-auth
        (list :type :api-key :api-key resolved-key)))
    (let* ((credentials
             (or
              (environment-value
               environment "GOOGLE_APPLICATION_CREDENTIALS")
              (default-adc-path)))
           (project
             (or
              (environment-value environment "GOOGLE_CLOUD_PROJECT")
              (environment-value environment "GCLOUD_PROJECT")))
           (location
             (environment-value environment "GOOGLE_CLOUD_LOCATION")))
      (unless (and (funcall file-exists-p credentials)
                   (non-empty-string-p project)
                   (non-empty-string-p location))
        (error 'configuration-error
               :message
               (if (or project location)
                   "Google Vertex ADC requires credentials, project, and location"
                   "Google Vertex credentials are not configured")))
      (list
       :type :adc
       :credentials-file credentials
       :project project
       :location location))))

(defun read-google-application-credential (path)
  (unless (probe-file path)
    (error 'configuration-error
           :message
           (format nil
                   "Google application credential does not exist: ~A"
                   path)))
  (let ((credential
          (parse-json (uiop:read-file-string path))))
    (unless (hash-table-p credential)
      (error 'configuration-error
             :message
             "Google application credential must be a JSON object"))
    credential))

(defun form-url-encode (fields)
  (format
   nil "~{~A~^&~}"
   (loop for (name value) on fields by #'cddr
         collect
         (format nil "~A=~A"
                 (sigv4-percent-encode name)
                 (sigv4-percent-encode value)))))

(defun google-required-string (object field)
  (let ((value (json-get object field)))
    (unless (non-empty-string-p value)
      (error 'configuration-error
             :message
             (format nil
                     "Invalid Google credential field: ~A"
                     field)))
    value))

(defun make-vertex-token-request
    (credential &key
                  (issued-at
                    (- (get-universal-time) 2208988800))
                  (scope
                    "https://www.googleapis.com/auth/cloud-platform"))
  (let ((type (google-required-string credential "type")))
    (cond
      ((string= type "service_account")
       (let* ((token-uri
                (or (json-get credential "token_uri")
                    "https://oauth2.googleapis.com/token"))
              (assertion
                (make-service-account-jwt
                 (google-required-string
                  credential "client_email")
                 (google-required-string
                  credential "private_key")
                 scope token-uri issued-at)))
         (make-request-spec
          :url token-uri
          :headers
          '(("content-type" .
             "application/x-www-form-urlencoded")
            ("accept" . "application/json"))
          :raw-body
          (form-url-encode
           (list
            "grant_type"
            "urn:ietf:params:oauth:grant-type:jwt-bearer"
            "assertion" assertion))
          :provider :google-vertex)))
      ((string= type "authorized_user")
       (let ((token-uri
               (or (json-get credential "token_uri")
                   "https://oauth2.googleapis.com/token")))
         (make-request-spec
          :url token-uri
          :headers
          '(("content-type" .
             "application/x-www-form-urlencoded")
            ("accept" . "application/json"))
          :raw-body
          (form-url-encode
           (list
            "grant_type" "refresh_token"
            "client_id"
            (google-required-string credential "client_id")
            "client_secret"
            (google-required-string credential "client_secret")
            "refresh_token"
            (google-required-string credential "refresh_token")))
          :provider :google-vertex)))
      (t
       (error 'configuration-error
              :message
              (format nil
                      "Unsupported Google application credential type: ~A"
                      type))))))

(defun exchange-vertex-access-token
    (credential &key issued-at)
  (multiple-value-bind (response)
      (request-json
       (make-vertex-token-request
        credential :issued-at
        (or issued-at
            (- (get-universal-time) 2208988800))))
    (google-required-string response "access_token")))

(defun device-authorization-cancelled-p (cancelled-p)
  (and cancelled-p
       (not (null (ignore-errors (funcall cancelled-p))))))

(defun signal-device-authorization-cancelled ()
  (error 'authentication-cancelled :message "Login cancelled"))

(defun sleep-for-device-authorization
    (seconds sleep-function cancelled-p)
  (if (and cancelled-p
           (eq sleep-function (symbol-function 'sleep)))
      (loop with remaining = seconds
            while (plusp remaining)
            do
            (when (device-authorization-cancelled-p cancelled-p)
              (signal-device-authorization-cancelled))
            (let ((slice (min remaining 0.05d0)))
              (sleep slice)
              (decf remaining slice)))
      (funcall sleep-function seconds))
  (when (device-authorization-cancelled-p cancelled-p)
    (signal-device-authorization-cancelled)))

(defun poll-device-authorization
    (poll &key (interval 5) (expires-in 900)
                 wait-before-first-poll-p
                 cancelled-p
                 (timeout-message "Device authorization expired")
                 slow-down-timeout-message
                 (sleep-function #'sleep)
                 (time-function #'get-universal-time))
  (unless (and (numberp interval)
               (not (minusp interval))
               (numberp expires-in)
               (plusp expires-in))
    (error 'configuration-error
           :message
           "Device authorization interval must be non-negative and expiry must be positive"))
  (let ((started-at (funcall time-function))
        (next-interval (max 1 interval))
        (first-p t)
        (slow-down-count 0))
    (loop
      (when (device-authorization-cancelled-p cancelled-p)
        (signal-device-authorization-cancelled))
      (when (>= (- (funcall time-function) started-at)
                expires-in)
        (error 'authentication-error
               :message
               (if (and slow-down-timeout-message
                        (plusp slow-down-count))
                   slow-down-timeout-message
                   timeout-message)))
      (when (or (not first-p) wait-before-first-poll-p)
        (sleep-for-device-authorization
         next-interval sleep-function cancelled-p))
      (setf first-p nil)
      (let* ((result (funcall poll))
             (status (getf result :status)))
        (case status
          (:complete
           (return (getf result :value)))
          (:pending
           (setf next-interval (max 1 interval)))
          (:slow-down
           (incf slow-down-count)
           (setf next-interval
                 (let ((server-interval
                         (getf result :interval)))
                   (if (and (numberp server-interval)
                            (plusp server-interval))
                       (max 1 server-interval)
                       (+ next-interval 5)))))
          (:failed
           (error 'authentication-error
                  :message
                  (or (getf result :message)
                      "Device authorization failed")))
          (:expired
           (error 'authentication-error
                  :message "Device authorization expired"))
          (:denied
           (error 'authentication-error
                  :message "Device authorization denied"))
          (:cancelled
           (signal-device-authorization-cancelled))
          (otherwise
           (error 'authentication-error
                  :message
                  (format nil
                          "Unexpected device authorization state: ~A"
                          status))))))))

(defun trusted-oauth-url-p (value &key https-only-p)
  (and
   (non-empty-string-p value)
   (or (uiop:string-prefix-p "https://" value)
       (and (not https-only-p)
            (uiop:string-prefix-p "http://" value)))
   (handler-case
       (progn (parse-http-url value) t)
     (error () nil))))

(defun required-oauth-string (object field provider)
  (let ((value (json-get object field)))
    (unless (non-empty-string-p value)
      (error 'authentication-error
             :message
             (format nil
                     "Invalid ~A OAuth response field: ~A"
                     provider field)))
    value))

(defun positive-oauth-number (object field provider)
  (let ((value (json-get object field)))
    (unless (and (numberp value) (plusp value))
      (error 'authentication-error
             :message
             (format nil
                     "Invalid ~A OAuth response field: ~A"
                     provider field)))
    value))

(defun parse-xai-device-authorization (object)
  (let* ((verification
           (required-oauth-string
            object "verification_uri" "xAI"))
         (complete
           (json-get object "verification_uri_complete"))
         (interval (json-get object "interval")))
    (unless (trusted-oauth-url-p verification :https-only-p t)
      (error 'authentication-error
             :message
             "Untrusted verification URI in xAI OAuth response"))
    (when (and complete
               (not
                (trusted-oauth-url-p complete
                                     :https-only-p t)))
      (error 'authentication-error
             :message
             "Untrusted verification URI in xAI OAuth response"))
    (list
     :device-code
     (required-oauth-string object "device_code" "xAI")
     :user-code
     (required-oauth-string object "user_code" "xAI")
     :verification-uri verification
     :verification-uri-complete complete
     :interval
     (and (numberp interval) (plusp interval) interval)
     :expires-in
     (positive-oauth-number object "expires_in" "xAI"))))

(defun oauth-token-credential
    (provider object
     &key previous-refresh-token
       (default-expires-in 3600)
       (expiry-skew-milliseconds 0))
  (let* ((access
           (required-oauth-string
            object "access_token" provider))
         (refresh
           (or (and (not (json-present-p object "refresh_token"))
                    previous-refresh-token)
               (required-oauth-string
                object "refresh_token" provider)))
         (expires-in
           (if (json-present-p object "expires_in")
               (positive-oauth-number
                object "expires_in" provider)
               default-expires-in)))
    (make-oauth-credential
     :provider provider
     :access access
     :refresh refresh
     :expires
     (- (+ (unix-milliseconds)
           (round (* expires-in 1000)))
        expiry-skew-milliseconds))))

(defun parse-kimi-device-authorization (object)
  (let ((verification
          (required-oauth-string
           object "verification_uri" "Kimi Code"))
        (complete
          (required-oauth-string
           object "verification_uri_complete" "Kimi Code"))
        (interval (json-get object "interval"))
        (expires-in (json-get object "expires_in")))
    (unless (and (trusted-oauth-url-p verification)
                 (trusted-oauth-url-p complete))
      (error 'authentication-error
             :message
             "Invalid Kimi Code device authorization response"))
    (list
     :device-code
     (required-oauth-string
      object "device_code" "Kimi Code")
     :user-code
     (required-oauth-string
      object "user_code" "Kimi Code")
     :verification-uri verification
     :verification-uri-complete complete
     :interval
     (if (and (numberp interval) (plusp interval))
         interval 5)
     :expires-in
     (if (and (numberp expires-in) (plusp expires-in))
         expires-in 900))))

(defun parse-github-device-authorization (object)
  (let ((verification
          (required-oauth-string
           object "verification_uri" "GitHub")))
    (unless (trusted-oauth-url-p verification)
      (error 'authentication-error
             :message
             "Untrusted verification_uri in device code response"))
    (list
     :device-code
     (required-oauth-string object "device_code" "GitHub")
     :user-code
     (required-oauth-string object "user_code" "GitHub")
     :verification-uri verification
     :interval
     (let ((value (json-get object "interval")))
       (and (numberp value) value))
     :expires-in
     (positive-oauth-number object "expires_in" "GitHub"))))

(defun github-copilot-base-url (token &optional enterprise-domain)
  (let* ((marker "proxy-ep=")
         (start (and token (search marker token)))
         (host
           (and start
                (let* ((value-start (+ start (length marker)))
                       (end (or (position #\; token
                                          :start value-start)
                                (length token))))
                  (subseq token value-start end)))))
    (cond
      ((non-empty-string-p host)
       (format nil "https://~A"
               (if (uiop:string-prefix-p "proxy." host)
                   (concatenate
                    'string "api."
                    (subseq host (length "proxy.")))
                   host)))
      ((non-empty-string-p enterprise-domain)
       (format nil "https://copilot-api.~A"
               enterprise-domain))
      (t
       "https://api.individual.githubcopilot.com"))))

(defun selectable-github-copilot-model-ids (response)
  (let ((data (json-get response "data")))
    (unless (vectorp data)
      (error 'authentication-error
             :message "Invalid Copilot models response"))
    (loop for item across data
          for policy = (json-get item "policy")
          for capabilities = (json-get item "capabilities")
          for supports = (json-get capabilities "supports")
          when
          (and
           (stringp (json-get item "id"))
           (eq t (json-get item "model_picker_enabled"))
           (not
            (string= "disabled"
                     (or (json-get policy "state") "")))
           (not
            (eq nil
                (json-get supports "tool_calls" t))))
            collect (json-get item "id"))))

(defun radius-authorization-url
    (endpoint challenge state
     &key
       (redirect-uri
         "http://127.0.0.1:1456/oauth/callback"))
  (format
   nil "~A?~A"
   endpoint
   (form-encode
    `(("response_type" . "code")
      ("client_id" . "pi-gateway")
      ("redirect_uri" . ,redirect-uri)
      ("scope" . "gateway offline_access")
      ("code_challenge" . ,challenge)
      ("code_challenge_method" . "S256")
      ("handoff" . "url")
      ("state" . ,state)))))

(defun materialize-cloudflare-url
    (base-url account-id gateway-id)
  (when (and
         (or (search "{CLOUDFLARE_ACCOUNT_ID}" base-url)
             (search "{accountId}" base-url))
         (not (non-empty-string-p account-id)))
    (error 'configuration-error
           :message "CLOUDFLARE_ACCOUNT_ID is not set"))
  (when (and
         (or (search "{CLOUDFLARE_GATEWAY_ID}" base-url)
             (search "{gatewayId}" base-url))
         (not (non-empty-string-p gateway-id)))
    (error 'configuration-error
           :message "CLOUDFLARE_GATEWAY_ID is not set"))
  (let ((result base-url))
    (dolist (entry
             `(("{CLOUDFLARE_ACCOUNT_ID}" . ,account-id)
               ("{CLOUDFLARE_GATEWAY_ID}" . ,gateway-id)
               ("{accountId}" . ,account-id)
               ("{gatewayId}" . ,gateway-id)))
      (when (cdr entry)
        (setf result
              (replace-all result (car entry) (cdr entry)))))
    result))

(defun radius-required-field (object field predicate)
  (let ((value (json-get object field)))
    (unless (and (json-present-p object field)
                 (funcall predicate value))
      (error 'configuration-error
             :message
             (format nil "Invalid Radius model field: ~A" field)))
    value))

(defun radius-models-from-config (provider config)
  (let ((base-url
          (radius-required-field
           config "baseUrl" #'non-empty-string-p))
        (models
          (radius-required-field
           config "models" #'vectorp)))
    (loop for model across models
          for id =
          (radius-required-field model "id" #'non-empty-string-p)
          for name =
          (radius-required-field model "name" #'non-empty-string-p)
          for reasoning =
          (radius-required-field
           model "reasoning"
           (lambda (value)
             (or (eq value t) (eq value nil))))
          for input =
          (radius-required-field model "input" #'vectorp)
          for cost =
          (radius-required-field model "cost" #'hash-table-p)
          for context-window =
          (radius-required-field
           model "contextWindow"
           (lambda (value)
             (and (integerp value) (plusp value))))
          for max-tokens =
          (radius-required-field
           model "maxTokens"
           (lambda (value)
             (and (integerp value) (plusp value))))
          collect
          (make-model-metadata
           :provider provider
           :id id
           :name name
           :api :pi-messages
           :base-url base-url
           :context-window context-window
           :max-output-tokens max-tokens
           :supports-images-p
           (not (null (find "image" input :test #'string=)))
           :supports-tools-p t
           :reasoning-p reasoning
           :thinking-level-map
           (let ((map (json-get model "thinkingLevelMap")))
             (when (hash-table-p map)
               (loop for key being the hash-keys of map
                       using (hash-value value)
                     collect
                     (cons
                      (intern (string-upcase key) :keyword)
                      (if (json-null-p value) nil value)))))
           :input-price
           (coerce (or (json-get cost "input") 0) 'double-float)
           :output-price
           (coerce (or (json-get cost "output") 0) 'double-float)
           :cache-read-price
           (coerce (or (json-get cost "cacheRead") 0) 'double-float)
           :cache-write-price
           (coerce (or (json-get cost "cacheWrite") 0) 'double-float)))))
