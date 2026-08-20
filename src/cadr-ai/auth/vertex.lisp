(in-package #:cadr-ai)

(defun default-adc-path ()
  (namestring
   (merge-pathnames
    ".config/gcloud/application_default_credentials.json"
    (user-homedir-pathname))))

(defun login-vertex-api-key (interaction)
  ;; Baseline packages/ai/src/providers/google-vertex.ts:13-63 vertexAuth
  ;; .login: a method select, then project/location (and optional service
  ;; account path) prompts with an ADC info notice carrying its link.
  (let ((method
          (runtime-auth-interaction-prompt
           interaction
           '(:type :select
             :message "Select Google Vertex AI authentication method:"
             :options
             ((:id "api-key" :label "Google Cloud API key")
              (:id "adc" :label "Application Default Credentials")
              (:id "service-account"
               :label "Service account credentials file"))))))
    (cond
      ((string= method "api-key")
       (make-api-key-credential
        :key
        (runtime-auth-interaction-prompt
         interaction
         '(:type :secret
           :message "Enter Google Cloud API key"))))
      ((member method '("adc" "service-account") :test #'string=)
       (runtime-auth-interaction-notify
        interaction
        (list :type :info
              :message
              (if (string= method "adc")
                  "Run `gcloud auth application-default login`, then provide the project and location."
                  "Provide a service account credentials file, project, and location.")
              :links
              '((:label "Application Default Credentials"
                 :url "https://cloud.google.com/docs/authentication/provide-credentials-adc"))))
       (let ((project
               (runtime-auth-interaction-prompt
                interaction
                '(:type :text
                  :message "Enter Google Cloud project ID")))
             (location
               (runtime-auth-interaction-prompt
                interaction
                '(:type :text
                  :message "Enter Google Cloud location")))
             (credentials-path
               (and (string= method "service-account")
                    (runtime-auth-interaction-prompt
                     interaction
                     '(:type :text
                       :message "Enter service account credentials file path")))))
         (make-api-key-credential
          :environment
          (append
           (list (cons "GOOGLE_CLOUD_PROJECT" project)
                 (cons "GOOGLE_CLOUD_LOCATION" location))
           (when (and credentials-path (plusp (length credentials-path)))
             (list
              (cons "GOOGLE_APPLICATION_CREDENTIALS"
                    credentials-path)))))))
      (t
       (error 'authentication-error
              :message
              (format nil
                      "Unknown Google Vertex AI auth method: ~A"
                      method))))))

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
    (unless (json-object-p credential)
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
