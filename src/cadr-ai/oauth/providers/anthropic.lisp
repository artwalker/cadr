(in-package #:cadr-ai)

(defun login-anthropic-copy-code-oauth (interaction)
  ;; pi@4a080252f anthropic.ts #10194. The copy-code page shows the
  ;; authorization code, so a browser on another machine can finish
  ;; login without the localhost callback.
  (multiple-value-bind (verifier challenge)
      (generate-pkce)
    (let ((url
            (anthropic-authorization-url
             challenge verifier
             +anthropic-copy-code-redirect-uri+)))
      (runtime-auth-interaction-notify
       interaction
       (list :type :auth-url
             :url url
             :instructions
             "Complete login in your browser, then copy the code Anthropic shows and paste it here."))
      (multiple-value-bind (code state)
          (parse-oauth-authorization-input
           (runtime-auth-interaction-prompt
            interaction
            '(:type :manual-code
              :message
              "Paste the code Anthropic shows after you sign in:"
              :placeholder "code#state")))
        (when (and (non-empty-string-p state)
                   (not (string= state verifier)))
          (error 'authentication-error
                 :message "OAuth state mismatch"))
        (unless (non-empty-string-p code)
          (error 'authentication-error
                 :message "Missing authorization code"))
        (runtime-auth-interaction-notify
         interaction
         '(:type :progress
           :message
           "Exchanging authorization code for tokens..."))
        (exchange-anthropic-authorization-code
         code
         (if (non-empty-string-p state) state verifier)
         verifier
         +anthropic-copy-code-redirect-uri+)))))

(defun login-anthropic-runtime-oauth (interaction)
  (let ((method
          (runtime-auth-interaction-prompt
           interaction
           '(:type :select
             :message "Select Anthropic login method:"
             :options
             ((:id "browser" :label "Browser login (default)")
              (:id "copy_code"
               :label "Copy code login (headless)"))))))
    (cond
      ((string= method "copy_code")
       (login-anthropic-copy-code-oauth interaction))
      ((string= method "browser")
       (login-anthropic-oauth
        nil
        :auth-url-function
        (lambda (url)
          (runtime-auth-interaction-notify
           interaction
           (list :type :auth-url :url url
                 :instructions
                 (oauth-provider-metadata-auth-url-instructions
                  +anthropic-oauth-metadata+))))
        :auth-prompt-function
        (lambda (prompt)
          (runtime-auth-interaction-prompt interaction prompt))))
      (t
       (error 'authentication-error
              :message
              (format nil
                      "Unknown Anthropic login method: ~A"
                      method))))))

(defparameter +anthropic-federation-rule-id-env+
  "ANTHROPIC_FEDERATION_RULE_ID")
(defparameter +anthropic-organization-id-env+
  "ANTHROPIC_ORGANIZATION_ID")
(defparameter +anthropic-identity-token-file-env+
  "ANTHROPIC_IDENTITY_TOKEN_FILE")
(defparameter +anthropic-service-account-id-env+
  "ANTHROPIC_SERVICE_ACCOUNT_ID")
(defparameter +anthropic-workspace-id-env+
  "ANTHROPIC_WORKSPACE_ID")
(defparameter +anthropic-federation-grant-type+
  "urn:ietf:params:oauth:grant-type:jwt-bearer")
(defparameter +anthropic-federation-beta-header+
  "oauth-2025-04-20,oidc-federation-2026-04-01")
(defparameter +anthropic-federation-assertion-limit+ (* 16 1024))
(defparameter +anthropic-federation-advisory-refresh-seconds+ 120)
(defparameter +anthropic-federation-mandatory-refresh-seconds+ 30)
(defparameter +anthropic-federation-advisory-backoff-seconds+ 5)
(defparameter +anthropic-federation-oauth-api-beta+ "oauth-2025-04-20")

(defvar *anthropic-federation-client* nil)
(defvar *anthropic-federation-lock*
  (sb-thread:make-mutex :name "anthropic-federation"))
(defvar *anthropic-federation-clock* #'get-universal-time)

(defstruct anthropic-federation-client
  key
  token
  expires-at
  (force-refresh-p nil)
  (pending-refresh nil)
  (last-advisory-error 0))

(defun anthropic-configured-string (value)
  (and (stringp value) (plusp (length value)) value))

(defun anthropic-federation-env-value (environment name)
  (anthropic-configured-string (environment-value environment name)))

(defun anthropic-federation-env (environment)
  (let ((rule
          (anthropic-federation-env-value
           environment +anthropic-federation-rule-id-env+))
        (organization
          (anthropic-federation-env-value
           environment +anthropic-organization-id-env+))
        (token-file
          (anthropic-federation-env-value
           environment +anthropic-identity-token-file-env+)))
    (when (and rule organization token-file)
      (let ((env
              (list
               (cons +anthropic-federation-rule-id-env+ rule)
               (cons +anthropic-organization-id-env+ organization)
               (cons +anthropic-identity-token-file-env+ token-file)))
            (service
              (anthropic-federation-env-value
               environment +anthropic-service-account-id-env+))
            (workspace
              (anthropic-federation-env-value
               environment +anthropic-workspace-id-env+)))
        (when service
          (setf env
                (append env
                        (list
                         (cons +anthropic-service-account-id-env+
                               service)))))
        (when workspace
          (setf env
                (append env
                        (list
                         (cons +anthropic-workspace-id-env+
                               workspace)))))
        env))))

(defun anthropic-process-federation-env ()
  (anthropic-federation-env
   (loop for name in (list +anthropic-federation-rule-id-env+
                           +anthropic-organization-id-env+
                           +anthropic-identity-token-file-env+
                           +anthropic-service-account-id-env+
                           +anthropic-workspace-id-env+)
         for value = (uiop:getenv name)
         when (anthropic-configured-string value)
           collect (cons name value))))

(defun resolve-anthropic-api-key-auth
    (credential environment overrides)
  (let* ((explicit-key (getf overrides :api-key))
         (credential-key
           (and (typep credential 'api-key-credential)
                (api-key-credential-key credential)))
         (credential-environment
           (and (typep credential 'api-key-credential)
                (api-key-credential-environment credential)))
         (effective-environment
           (merge-provider-environment
            (append (or (getf overrides :environment) nil)
                    credential-environment)
            environment))
         (auth-token
           (anthropic-federation-env-value
            effective-environment "ANTHROPIC_AUTH_TOKEN"))
         (oauth-token
           (anthropic-federation-env-value
            effective-environment "ANTHROPIC_OAUTH_TOKEN"))
         (api-key
           (anthropic-federation-env-value
            effective-environment "ANTHROPIC_API_KEY"))
         (federation (anthropic-federation-env effective-environment)))
    (cond
      ((anthropic-configured-string explicit-key)
       (make-runtime-auth-result
        :api-key explicit-key
        :environment effective-environment
        :source "Explicit API key"
        :type :api-key))
      ((anthropic-configured-string credential-key)
       (make-runtime-auth-result
        :api-key credential-key
        :environment effective-environment
        :source "stored credential"
        :type :api-key))
      (auth-token
       (make-runtime-auth-result
        :headers
        (list (cons "Authorization"
                    (format nil "Bearer ~A" auth-token)))
        :environment effective-environment
        :source "ANTHROPIC_AUTH_TOKEN"
        :type :api-key))
      (oauth-token
       (make-runtime-auth-result
        :api-key oauth-token
        :environment effective-environment
        :source "ANTHROPIC_OAUTH_TOKEN"
        :type :api-key))
      (api-key
       (make-runtime-auth-result
        :api-key api-key
        :environment effective-environment
        :source "ANTHROPIC_API_KEY"
        :type :api-key))
      (federation
       (make-runtime-auth-result
        :environment federation
        :source "workload identity federation"
        :type :api-key)))))

(defun anthropic-header-value (headers name)
  (cdr (assoc name headers :test #'string-equal)))

(defun anthropic-headers-with-overlay (base overlay)
  (append
   (remove-if
    (lambda (entry)
      (assoc (car entry) overlay :test #'string-equal))
    base)
   overlay))

(defun anthropic-header-has-auth-p (headers)
  (loop for name in '("authorization" "x-api-key" "cf-aig-authorization")
        for value = (anthropic-header-value headers name)
        thereis (and (stringp value)
                     (plusp
                      (length
                       (string-trim
                        '(#\Space #\Tab #\Newline #\Return #\Page #\Vt)
                        value))))))

(defun anthropic-federation-config (provider)
  (let ((environment (getf (provider-options provider) :environment)))
    (if environment
        (anthropic-federation-env environment)
        (anthropic-process-federation-env))))

(defun anthropic-token-endpoint-host (base-url)
  (let* ((text (string-trim '(#\Space #\Tab) (or base-url "")))
         (marker (search "://" text)))
    (unless marker
      (return-from anthropic-token-endpoint-host nil))
    (let* ((rest (subseq text (+ marker 3)))
           (bracket (and (plusp (length rest)) (char= (char rest 0) #\[)))
           (end
             (if bracket
                 (let ((close (position #\] rest)))
                   (or close (length rest)))
                 (or (position #\/ rest)
                     (position #\: rest)
                     (length rest)))))
      (values (subseq text 0 marker)
              (string-downcase (subseq rest 0 (if bracket (1+ end) end)))))))

(defun anthropic-secure-token-endpoint-p (base-url)
  (multiple-value-bind (scheme host)
      (anthropic-token-endpoint-host base-url)
    (or (and scheme (string-equal scheme "https"))
        (and scheme
             (string-equal scheme "http")
             (member host '("localhost" "127.0.0.1" "[::1]" "::1")
                     :test #'string=)))))

(defun read-anthropic-identity-token (path)
  (let ((content
          (handler-case
              (uiop:read-file-string path)
            (error (condition)
              (error 'authentication-error
                     :message
                     (format nil
                             "Failed to read identity token file at ~A: ~A"
                             path condition))))))
    (let ((token
            (string-trim
             '(#\Space #\Tab #\Newline #\Return #\Page #\Vt)
             (or content ""))))
      (unless (plusp (length token))
        (error 'authentication-error
               :message
               (format nil "Identity token file at ~A is empty" path)))
      (when (> (length token) +anthropic-federation-assertion-limit+)
        (error 'authentication-error
               :message
               (format nil
                       "Identity token is ~D KiB, exceeds the 16 KiB assertion limit"
                       (ceiling (length token) 1024))))
      token)))

(defun anthropic-federation-cache-key (base-url env)
  (list (strip-trailing-slash base-url)
        (anthropic-federation-env-value
         env +anthropic-federation-rule-id-env+)
        (anthropic-federation-env-value
         env +anthropic-organization-id-env+)
        (or (anthropic-federation-env-value
             env +anthropic-service-account-id-env+)
            "")
        (or (anthropic-federation-env-value
             env +anthropic-workspace-id-env+)
            "")
        (anthropic-federation-env-value
         env +anthropic-identity-token-file-env+)))

(defun exchange-anthropic-federation-token (base-url env)
  (unless (anthropic-secure-token-endpoint-p base-url)
    (error 'authentication-error
           :message
           (format nil
                   "Refusing to send credential over non-https token endpoint \"~A\""
                   base-url)))
  (let* ((assertion
           (read-anthropic-identity-token
            (anthropic-federation-env-value
             env +anthropic-identity-token-file-env+)))
         (payload
           (json-object
            "grant_type" +anthropic-federation-grant-type+
            "assertion" assertion
            "federation_rule_id"
            (anthropic-federation-env-value
             env +anthropic-federation-rule-id-env+)
            "organization_id"
            (anthropic-federation-env-value
             env +anthropic-organization-id-env+)))
         (service
           (anthropic-federation-env-value
            env +anthropic-service-account-id-env+))
         (workspace
           (anthropic-federation-env-value
            env +anthropic-workspace-id-env+)))
    (when service
      (json-put payload "service_account_id" service))
    (when workspace
      (json-put payload "workspace_id" workspace))
    (let ((body
            (handler-case
                (request-json
                 (make-request-spec
                  :url (format nil "~A/v1/oauth/token"
                               (strip-trailing-slash base-url))
                  :method :post
                  :headers
                  `(("content-type" . "application/json")
                    ("anthropic-beta" . ,+anthropic-federation-beta-header+))
                  :payload payload
                  :provider :anthropic))
              (api-error (condition)
                (error 'authentication-error
                       :message
                       (format nil
                               "Token exchange failed with status ~A: ~A"
                               (api-error-status condition)
                               (cadr-error-message condition)))))))
      (let ((token (json-get body "access_token"))
            (expires-in (json-get body "expires_in"))
            (token-type (json-get body "token_type")))
        (unless (anthropic-configured-string token)
          (error 'authentication-error
                 :message
                 "Token endpoint response missing access_token"))
        (when (and (stringp token-type)
                   (not (string-equal token-type "bearer")))
          (error 'authentication-error
                 :message
                 (format nil
                         "Token endpoint response: unsupported token_type \"~A\" (want Bearer)"
                         token-type)))
        (unless (and (realp expires-in) (not (minusp expires-in)))
          (error 'authentication-error
                 :message
                 "Token endpoint response missing required fields"))
        (cons token (round expires-in))))))

(defun anthropic-federation-store-exchange (key base-url env now)
  (let ((exchanged
          (exchange-anthropic-federation-token base-url env)))
    (setf *anthropic-federation-client*
          (make-anthropic-federation-client
           :key key
           :token (car exchanged)
           :expires-at (+ now (cdr exchanged))
           :force-refresh-p nil
           :pending-refresh nil
           :last-advisory-error
           (if *anthropic-federation-client*
               (anthropic-federation-client-last-advisory-error
                *anthropic-federation-client*)
               0)))
    (car exchanged)))

(defun anthropic-federation-clear-advisory-pending (key &optional errorp)
  (sb-thread:with-mutex (*anthropic-federation-lock*)
    (let ((cached *anthropic-federation-client*))
      (when (and cached
                 (equal key (anthropic-federation-client-key cached)))
        (setf (anthropic-federation-client-pending-refresh cached) nil)
        (when errorp
          (setf (anthropic-federation-client-last-advisory-error cached)
                (funcall *anthropic-federation-clock*)))))))

(defun anthropic-federation-run-advisory-refresh (key base-url env)
  (handler-case
      (let* ((now (funcall *anthropic-federation-clock*))
             (exchanged
               (exchange-anthropic-federation-token base-url env)))
        (sb-thread:with-mutex (*anthropic-federation-lock*)
          (let ((cached *anthropic-federation-client*))
            (when (and cached
                       (equal key (anthropic-federation-client-key cached)))
              (setf *anthropic-federation-client*
                    (make-anthropic-federation-client
                     :key key
                     :token (car exchanged)
                     :expires-at (+ now (cdr exchanged))
                     :force-refresh-p nil
                     :pending-refresh nil
                     :last-advisory-error
                     (anthropic-federation-client-last-advisory-error
                      cached)))))))
    (error ()
      (anthropic-federation-clear-advisory-pending key t))))

(defun anthropic-federation-kick-advisory-refresh (key base-url env)
  (let ((http *http-request-function*)
        (clock *anthropic-federation-clock*))
    (sb-thread:make-thread
     (lambda ()
       (let ((*http-request-function* http)
             (*anthropic-federation-clock* clock))
         (anthropic-federation-run-advisory-refresh key base-url env)))
     :name "anthropic-federation-advisory-refresh"))
  nil)

(defun anthropic-federation-access-token (base-url env)
  (let ((advisory nil)
        (token nil))
    (sb-thread:with-mutex (*anthropic-federation-lock*)
      (let* ((key (anthropic-federation-cache-key base-url env))
             (cached *anthropic-federation-client*)
             (now (funcall *anthropic-federation-clock*))
             (force
               (and cached
                    (equal key (anthropic-federation-client-key cached))
                    (anthropic-federation-client-force-refresh-p cached))))
        (when (and cached
                   (equal key (anthropic-federation-client-key cached))
                   force)
          (setf (anthropic-federation-client-force-refresh-p cached) nil))
        (cond
          ((or force
               (null cached)
               (not (equal key (anthropic-federation-client-key cached))))
           (setf token
                 (anthropic-federation-store-exchange key base-url env now)))
          (t
           (let ((remaining
                   (- (anthropic-federation-client-expires-at cached) now)))
             (cond
               ((> remaining +anthropic-federation-advisory-refresh-seconds+)
                (setf token (anthropic-federation-client-token cached)))
               ((> remaining +anthropic-federation-mandatory-refresh-seconds+)
                (unless (or (anthropic-federation-client-pending-refresh cached)
                            (< (- now
                                  (anthropic-federation-client-last-advisory-error
                                   cached))
                               +anthropic-federation-advisory-backoff-seconds+))
                  (setf (anthropic-federation-client-pending-refresh cached) t
                        advisory (list key env)))
                (setf token (anthropic-federation-client-token cached)))
               (t
                (setf token
                      (anthropic-federation-store-exchange
                       key base-url env now)))))))))
    (when advisory
      (anthropic-federation-kick-advisory-refresh
       (first advisory) base-url (second advisory)))
    token))

(defun invalidate-anthropic-federation-token-cache ()
  (sb-thread:with-mutex (*anthropic-federation-lock*)
    (let ((cached *anthropic-federation-client*))
      (when cached
        (setf (anthropic-federation-client-token cached) nil
              (anthropic-federation-client-expires-at cached) 0
              (anthropic-federation-client-force-refresh-p cached) t)))))

(defun note-anthropic-federation-response (status)
  (when (and *anthropic-federation-bearer-p* (eql status 401))
    (invalidate-anthropic-federation-token-cache)))

(defun anthropic-request-auth (provider model headers)
  (let* ((oauth (provider-oauth-access-token provider))
         (api-key (provider-api-key provider))
         (overlay
           (anthropic-headers-with-overlay
            (getf (provider-options provider) :auth-headers)
            headers))
         (federation
           (and (eq (model-provider model) :anthropic)
                (anthropic-federation-config provider))))
    (cond
      ((non-empty-string-p oauth)
       (values oauth t nil overlay))
      ((non-empty-string-p api-key)
       (values api-key nil nil overlay))
      ((anthropic-header-has-auth-p overlay)
       (values nil nil nil overlay))
      (federation
       (values
        (anthropic-federation-access-token
         (model-base-url model) federation)
        nil t overlay))
      (t
       (values (require-api-key provider) nil nil overlay)))))
