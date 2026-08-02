(load (merge-pathnames "../support.lisp" *load-truename*))

(defparameter +custom-anthropic-client-id+
  "9d1c250a-e61b-44d9-88ed-5944d1962f5e")
(defparameter +custom-anthropic-authorize-url+
  "https://claude.ai/oauth/authorize")
(defparameter +custom-anthropic-token-url+
  "https://console.anthropic.com/v1/oauth/token")
(defparameter +custom-anthropic-redirect-uri+
  "https://console.anthropic.com/oauth/code/callback")
(defparameter +custom-anthropic-scopes+
  "org:create_api_key user:profile user:inference")

(defun custom-anthropic-credential-from-json (object &optional refresh)
  (let ((access (cadr-ai::json-get object "access_token"))
        (new-refresh (or (cadr-ai::json-get object "refresh_token") refresh))
        (expires-in (cadr-ai::json-get object "expires_in")))
    (unless (and (stringp access) (plusp (length access))
                 (stringp new-refresh) (numberp expires-in))
      (error "Custom Anthropic token response was invalid"))
    (cadr-ai:make-oauth-credential
     :provider :custom-anthropic
     :access access :refresh new-refresh
     :expires
     (- (+ (example-unix-milliseconds)
           (round (* expires-in 1000)))
        300000))))

(defun custom-anthropic-login (interaction)
  (multiple-value-bind (verifier challenge) (cadr-ai:generate-pkce)
    (let ((url
            (format nil "~A?~A"
                    +custom-anthropic-authorize-url+
                    (example-form-encode
                     `(("code" . "true")
                       ("client_id" . ,+custom-anthropic-client-id+)
                       ("response_type" . "code")
                       ("redirect_uri" . ,+custom-anthropic-redirect-uri+)
                       ("scope" . ,+custom-anthropic-scopes+)
                       ("code_challenge" . ,challenge)
                       ("code_challenge_method" . "S256")
                       ("state" . ,verifier))))))
      (cadr-ai:runtime-auth-interaction-notify
       interaction (list :type :auth-url :url url))
      (let* ((authorization
               (cadr-ai:runtime-auth-interaction-prompt
                interaction
                '(:type :manual-code
                  :message "Paste the authorization code:"))))
        (unless authorization
          (error "Custom Anthropic OAuth login was cancelled"))
        (let* (
             (hash (position #\# authorization))
             (code (if hash (subseq authorization 0 hash) authorization))
             (state (and hash (subseq authorization (1+ hash)))))
          (custom-anthropic-credential-from-json
           (example-http-json
            +custom-anthropic-token-url+
            :object
            (cadr-ai::json-object
             "grant_type" "authorization_code"
             "client_id" +custom-anthropic-client-id+
             "code" code
             "state" state
             "redirect_uri" +custom-anthropic-redirect-uri+
             "code_verifier" verifier))))))))

(defun custom-anthropic-refresh (credential)
  (custom-anthropic-credential-from-json
   (example-http-json
    +custom-anthropic-token-url+
    :object
    (cadr-ai::json-object
     "grant_type" "refresh_token"
     "client_id" +custom-anthropic-client-id+
     "refresh_token" (cadr-ai:oauth-credential-refresh credential)))
   (cadr-ai:oauth-credential-refresh credential)))

(defun custom-anthropic-model
    (id name input output cache-read cache-write)
  (declare (ignore input output cache-read cache-write))
  (cadr-ai:make-model
   :id id :name name
   :provider :custom-anthropic
   :api :custom-anthropic-api
   :base-url "https://api.anthropic.com"
   :reasoning-p t :supports-images-p t
   :context-window 200000 :max-tokens 64000))

(defparameter *custom-anthropic-models*
  (list
   (custom-anthropic-model
    "claude-opus-4-5" "Claude Opus 4.5 (Custom)" 5 25 0.5 6.25)
   (custom-anthropic-model
    "claude-sonnet-4-5" "Claude Sonnet 4.5 (Custom)" 3 15 0.3 3.75)))

(defun custom-anthropic-auth-resolver (credential environment overrides)
  (let ((key
          (or (getf overrides :api-key)
              (and (typep credential 'cadr-ai:api-key-credential)
                   (cadr-ai:api-key-credential-key credential))
              (example-environment-value
               environment "CUSTOM_ANTHROPIC_API_KEY"))))
    (and key
         (cadr-ai:make-runtime-auth-result
          :api-key key :source "CUSTOM_ANTHROPIC_API_KEY"
          :type :api-key))))

(defun custom-anthropic-stream (model context on-event &rest options)
  (let* ((key (getf options :api-key))
         (oauth-p (eq :oauth (getf options :auth-type)))
         (provider
           (cadr-ai:make-anthropic-provider
            :api-key (and (not oauth-p) key)
            :oauth-access-token (and oauth-p key)
            :provider-id :custom-anthropic
            :options (list :environment (getf options :environment)))))
    (apply #'cadr-ai:stream-chat provider model context on-event
           (example-runtime-stream-options
            options (getf options :headers)))))

(cadr-agent:define-native-provider
 (cadr-ai:make-runtime-provider
  :id :custom-anthropic
  :name "Custom Anthropic"
  :models *custom-anthropic-models*
  :api-key-auth-p t
  :oauth-auth-p t
  :auth-resolver #'custom-anthropic-auth-resolver
  :oauth-login-function #'custom-anthropic-login
  :oauth-refresh-function #'custom-anthropic-refresh
  :oauth-to-auth-function
  (lambda (credential)
    (cadr-ai:make-runtime-auth-result
     :api-key (cadr-ai:oauth-credential-access credential)
     :source "OAuth" :type :oauth))
  :stream-function #'custom-anthropic-stream))
