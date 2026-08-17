(in-package #:cadr-ai)

(defun environment-value (environment name)
  (cdr (assoc name environment :test #'string=)))

(defun placeholder-api-key-p (value)
  (member value '("<authenticated>" "gcp-vertex-credentials")
          :test #'string=))

(defun login-bedrock-api-key (interaction)
  ;; Baseline packages/ai/src/providers/amazon-bedrock.ts:12-54 bedrockAuth
  ;; .login: a method select followed by per-method prompts and an info
  ;; notice with the AWS credential-chain link.
  (let ((method
          (runtime-auth-interaction-prompt
           interaction
           '(:type :select
             :message "Select Amazon Bedrock authentication method:"
             :options
             ((:id "bearer-token" :label "Bearer token")
              (:id "aws-profile" :label "AWS profile")
              (:id "credential-chain"
               :label "Existing AWS credential chain"))))))
    (cond
      ((string= method "bearer-token")
       (make-api-key-credential
        :key
        (runtime-auth-interaction-prompt
         interaction
         '(:type :secret
           :message "Enter Amazon Bedrock bearer token"))))
      (t
       (runtime-auth-interaction-notify
        interaction
        '(:type :info
          :message "Amazon Bedrock supports AWS profiles, IAM credentials, and role-based credentials."
          :links
          ((:label "AWS credential provider chain"
            :url "https://docs.aws.amazon.com/sdkref/latest/guide/standardized-credentials.html"))))
       (cond
         ((string= method "aws-profile")
          (make-api-key-credential
           :environment
           (list
            (cons "AWS_PROFILE"
                  (runtime-auth-interaction-prompt
                   interaction
                   '(:type :text
                     :message "Enter AWS profile name"))))))
         ((string= method "credential-chain")
          (runtime-auth-interaction-prompt
           interaction
           '(:type :text
             :message "Configure AWS credentials, then press Enter to continue"))
          (make-api-key-credential))
         (t
          (error 'authentication-error
                 :message
                 (format nil
                         "Unknown Amazon Bedrock auth method: ~A"
                         method))))))))

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
      (when (>= (length parts) 4)
        (destructuring-bind
            (arn partition service region &rest rest)
            parts
          (declare (ignore arn partition rest))
          (when (and (string= "bedrock" service)
                     (non-empty-string-p region))
            region))))))

(defun resolve-bedrock-region
    (model-id explicit-region environment-region
     &optional endpoint-region)
  (or (bedrock-arn-region model-id)
      explicit-region
      environment-region
      endpoint-region
      "us-east-1"))
