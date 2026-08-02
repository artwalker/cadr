(load (merge-pathnames "../support.lisp" *load-truename*))

(defparameter +gitlab-duo-root+ "https://gitlab.com")
(defparameter +gitlab-duo-gateway+ "https://cloud.gitlab.com")
(defparameter +gitlab-duo-anthropic-proxy+
  "https://cloud.gitlab.com/ai/v1/proxy/anthropic/")
(defparameter +gitlab-duo-openai-proxy+
  "https://cloud.gitlab.com/ai/v1/proxy/openai/v1")
(defparameter +gitlab-duo-client-id+
  "da4edff2e6ebd2bc3208611e2768bc1c1dd7be791dc5ff26ca34ca9ee44f7d4b")
(defparameter +gitlab-duo-redirect-uri+ "http://127.0.0.1:8080/callback")
(defparameter +gitlab-duo-direct-access-ttl+ (* 25 60 1000))

(defstruct gitlab-duo-model-definition
  id name backend base-url context-window max-tokens)

(defparameter *gitlab-duo-model-definitions*
  (list
   (make-gitlab-duo-model-definition
    :id "claude-opus-4-8" :name "Claude Opus 4.8"
    :backend :anthropic :base-url +gitlab-duo-anthropic-proxy+
    :context-window 1000000 :max-tokens 128000)
   (make-gitlab-duo-model-definition
    :id "claude-sonnet-4-6" :name "Claude Sonnet 4.6"
    :backend :anthropic :base-url +gitlab-duo-anthropic-proxy+
    :context-window 1000000 :max-tokens 64000)
   (make-gitlab-duo-model-definition
    :id "claude-opus-4-5-20251101" :name "Claude Opus 4.5"
    :backend :anthropic :base-url +gitlab-duo-anthropic-proxy+
    :context-window 200000 :max-tokens 32000)
   (make-gitlab-duo-model-definition
    :id "claude-sonnet-4-5-20250929" :name "Claude Sonnet 4.5"
    :backend :anthropic :base-url +gitlab-duo-anthropic-proxy+
    :context-window 200000 :max-tokens 16384)
   (make-gitlab-duo-model-definition
    :id "claude-haiku-4-5-20251001" :name "Claude Haiku 4.5"
    :backend :anthropic :base-url +gitlab-duo-anthropic-proxy+
    :context-window 200000 :max-tokens 8192)
   (make-gitlab-duo-model-definition
    :id "gpt-5.5-2026-04-23" :name "GPT-5.5"
    :backend :openai :base-url +gitlab-duo-openai-proxy+
    :context-window 272000 :max-tokens 128000)
   (make-gitlab-duo-model-definition
    :id "gpt-5.1-2025-11-13" :name "GPT-5.1"
    :backend :openai :base-url +gitlab-duo-openai-proxy+
    :context-window 128000 :max-tokens 16384)
   (make-gitlab-duo-model-definition
    :id "gpt-5-mini-2025-08-07" :name "GPT-5 Mini"
    :backend :openai :base-url +gitlab-duo-openai-proxy+
    :context-window 128000 :max-tokens 16384)
   (make-gitlab-duo-model-definition
    :id "gpt-5-codex" :name "GPT-5 Codex"
    :backend :openai :base-url +gitlab-duo-openai-proxy+
    :context-window 128000 :max-tokens 16384)))

(defparameter *gitlab-duo-models*
  (mapcar
   (lambda (definition)
     (cadr-ai:make-model
      :id (gitlab-duo-model-definition-id definition)
      :name (gitlab-duo-model-definition-name definition)
      :provider :gitlab-duo
      :api :gitlab-duo-api
      :base-url (gitlab-duo-model-definition-base-url definition)
      :reasoning-p t :supports-images-p t
      :thinking-level-map '((:xhigh . :max))
      :compat
      (and (eq :anthropic
               (gitlab-duo-model-definition-backend definition))
           '(:force-adaptive-thinking t))
      :context-window
      (gitlab-duo-model-definition-context-window definition)
      :max-tokens (gitlab-duo-model-definition-max-tokens definition)))
   *gitlab-duo-model-definitions*))

(defparameter *gitlab-duo-direct-access* nil)
(defparameter *gitlab-duo-direct-access-lock*
  (sb-thread:make-mutex :name "GitLab Duo direct access cache"))

(defun gitlab-duo-clear-direct-access ()
  (sb-thread:with-mutex (*gitlab-duo-direct-access-lock*)
    (setf *gitlab-duo-direct-access* nil)))

(defun gitlab-duo-json-headers (object)
  (unless (hash-table-p object)
    (error "GitLab Duo direct access headers were invalid"))
  (loop for key being the hash-keys of object
        using (hash-value value)
        unless (and (stringp key) (stringp value))
          do (error "GitLab Duo direct access headers were invalid")
        collect (cons key value)))

(defun gitlab-duo-direct-access (gitlab-access-token)
  (let ((now (example-unix-milliseconds)))
    (sb-thread:with-mutex (*gitlab-duo-direct-access-lock*)
      (when (and *gitlab-duo-direct-access*
                 (> (getf *gitlab-duo-direct-access* :expires-at) now))
        (return-from gitlab-duo-direct-access
          (copy-tree *gitlab-duo-direct-access*))))
    (let* ((object
             (example-http-json
              (format nil "~A/api/v4/ai/third_party_agents/direct_access"
                      +gitlab-duo-root+)
              :headers
              (list (cons "Authorization"
                          (format nil "Bearer ~A" gitlab-access-token)))
              :object
              (cadr-ai::json-object
               "feature_flags"
               (cadr-ai::json-object "DuoAgentPlatformNext" t))))
           (token (cadr-ai::json-get object "token"))
           (headers (gitlab-duo-json-headers
                     (cadr-ai::json-get object "headers"))))
      (unless (and (stringp token) (plusp (length token)))
        (error "GitLab Duo direct access response was invalid"))
      (let ((result
              (list :token token :headers headers
                    :expires-at (+ now +gitlab-duo-direct-access-ttl+))))
        (sb-thread:with-mutex (*gitlab-duo-direct-access-lock*)
          (setf *gitlab-duo-direct-access* (copy-tree result)))
        result))))

(defun gitlab-duo-token-credential (object &optional refresh)
  (let ((access (cadr-ai::json-get object "access_token"))
        (new-refresh (or (cadr-ai::json-get object "refresh_token") refresh))
        (expires-in (cadr-ai::json-get object "expires_in"))
        (created-at (cadr-ai::json-get object "created_at")))
    (unless (and (stringp access) (plusp (length access))
                 (stringp new-refresh) (numberp expires-in)
                 (numberp created-at))
      (error "GitLab OAuth token response was invalid"))
    (gitlab-duo-clear-direct-access)
    (cadr-ai:make-oauth-credential
     :provider :gitlab-duo :access access :refresh new-refresh
     :expires (- (* (+ created-at expires-in) 1000) 300000))))

(defun gitlab-duo-login (interaction)
  (multiple-value-bind (verifier challenge) (cadr-ai:generate-pkce)
    (let* ((state (cadr-ai:uuid-v7))
           (url
             (format nil "~A/oauth/authorize?~A"
                     +gitlab-duo-root+
                     (example-form-encode
                      `(("client_id" . ,+gitlab-duo-client-id+)
                        ("redirect_uri" . ,+gitlab-duo-redirect-uri+)
                        ("response_type" . "code")
                        ("scope" . "api")
                        ("code_challenge" . ,challenge)
                        ("code_challenge_method" . "S256")
                        ("state" . ,state))))))
      (cadr-ai:runtime-auth-interaction-notify
       interaction (list :type :auth-url :url url))
      (let* ((callback
               (cadr-ai:runtime-auth-interaction-prompt
                interaction
                '(:type :manual-code :message "Paste the callback URL:"))))
        (unless callback
          (error "GitLab OAuth login was cancelled"))
        (let ((code (example-query-value callback "code")))
        (unless (and code (plusp (length code)))
          (error "No authorization code found in callback URL"))
        (gitlab-duo-token-credential
         (example-http-json
          (format nil "~A/oauth/token" +gitlab-duo-root+)
          :form
          `(("client_id" . ,+gitlab-duo-client-id+)
            ("grant_type" . "authorization_code")
            ("code" . ,code)
            ("code_verifier" . ,verifier)
            ("redirect_uri" . ,+gitlab-duo-redirect-uri+)))))))))

(defun gitlab-duo-refresh (credential)
  (gitlab-duo-token-credential
   (example-http-json
    (format nil "~A/oauth/token" +gitlab-duo-root+)
    :form
    `(("client_id" . ,+gitlab-duo-client-id+)
      ("grant_type" . "refresh_token")
      ("refresh_token" . ,(cadr-ai:oauth-credential-refresh credential))))
   (cadr-ai:oauth-credential-refresh credential)))

(defun gitlab-duo-auth-resolver (credential environment overrides)
  (let ((key
          (or (getf overrides :api-key)
              (and (typep credential 'cadr-ai:api-key-credential)
                   (cadr-ai:api-key-credential-key credential))
              (example-environment-value environment "GITLAB_TOKEN"))))
    (and key
         (cadr-ai:make-runtime-auth-result
          :api-key key :source "GITLAB_TOKEN" :type :api-key))))

(defun gitlab-duo-stream (model context on-event &rest options)
  (let* ((access-token (getf options :api-key))
         (definition
           (find (cadr-ai:model-id model) *gitlab-duo-model-definitions*
                 :key #'gitlab-duo-model-definition-id :test #'string=)))
    (unless access-token
      (error "No GitLab access token. Run /login gitlab-duo or set GITLAB_TOKEN"))
    (unless definition
      (error "Unknown GitLab Duo model: ~A" (cadr-ai:model-id model)))
    (let* ((direct (gitlab-duo-direct-access access-token))
           (headers
             (append
              (getf direct :headers)
              (list
               (cons "Authorization"
                     (format nil "Bearer ~A" (getf direct :token))))))
           (provider
             (if (eq :anthropic
                     (gitlab-duo-model-definition-backend definition))
                 (cadr-ai:make-anthropic-provider
                  :api-key "gitlab-duo" :provider-id :gitlab-duo
                  :options (list :environment (getf options :environment)))
                 (cadr-ai:make-openai-provider
                  :api-key "gitlab-duo" :provider-id :gitlab-duo
                  :options (list :environment (getf options :environment))))))
      (apply #'cadr-ai:stream-chat provider model context on-event
             (example-runtime-stream-options options headers)))))

(cadr-agent:define-native-provider
 (cadr-ai:make-runtime-provider
  :id :gitlab-duo
  :name "GitLab Duo"
  :models *gitlab-duo-models*
  :api-key-auth-p t :oauth-auth-p t
  :auth-resolver #'gitlab-duo-auth-resolver
  :oauth-login-function #'gitlab-duo-login
  :oauth-refresh-function #'gitlab-duo-refresh
  :oauth-to-auth-function
  (lambda (credential)
    (cadr-ai:make-runtime-auth-result
     :api-key (cadr-ai:oauth-credential-access credential)
     :source "OAuth" :type :oauth))
  :stream-function #'gitlab-duo-stream))
