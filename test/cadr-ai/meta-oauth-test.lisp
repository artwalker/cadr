(in-package #:cadr-ai/tests)
(in-suite cadr-ai-suite)

;;; pi@4a080252f packages/ai/test/meta-oauth.test.ts
;;; plus the provider row in packages/ai/src/providers/meta.ts
;;; and defaultModelPerProvider.meta in model-resolver.ts.

(defparameter +meta-oauth-day-ms+ (* 24 60 60 1000))
(defparameter +meta-oauth-start-ms+ 1788393600000)
(defparameter +meta-oauth-noon-ms+ 1788436800000)

(defun meta-oauth-calls ()
  (list nil))

(defun meta-oauth-record (calls url method headers content)
  (push (list :url url :method method :headers headers :content content)
        (car calls)))

(defun meta-oauth-header (call name)
  (cdr (assoc name (getf call :headers) :test #'string=)))

(defmacro with-meta-oauth-transport ((calls clock responses) &body body)
  (let ((scripted-responses (gensym "SCRIPTED-RESPONSES")))
    `(let ((,calls (meta-oauth-calls))
           (,clock ,+meta-oauth-start-ms+)
           (,scripted-responses ,responses))
       (let ((cadr-ai::*oauth-flow-request-function*
               (lambda (url &key method headers content &allow-other-keys)
                 (meta-oauth-record ,calls url method headers content)
                 (let ((scripted (assoc url ,scripted-responses :test #'string=)))
                   (unless scripted
                     (error "Unexpected Meta OAuth URL: ~A" url))
                   (let ((next (pop (cdr scripted))))
                     (unless next
                       (error "Unexpected extra Meta OAuth request: ~A" url))
                     (values (json-object-from-alist (first next))
                             (second next))))))
             (cadr-ai::*oauth-flow-sleep-function*
               (lambda (seconds)
                 (incf ,clock (round (* seconds 1000)))))
             (cadr-ai::*meta-unix-milliseconds-function*
               (lambda () ,clock)))
         ,@body))))

(defun json-object-from-alist (pairs)
  (apply #'cadr-ai::json-object
         (loop for (key . value) in pairs
               collect key
               collect value)))

(defun meta-oauth-interaction (&key (events (list nil)) (aborted nil))
  (cadr-ai:make-runtime-auth-interaction
   :prompt-function
   (lambda (prompt)
     (declare (ignore prompt))
     (error "Meta login should not prompt"))
   :notify-function
   (lambda (event)
     (push (copy-list event) (car events)))
   :abort-p (lambda () aborted)))

(defun meta-oauth-error-message (thunk)
  (handler-case
      (funcall thunk)
    (cadr-ai:authentication-error (condition)
      (cadr-ai:cadr-error-message condition))))

(test meta-provider-reads-meta-api-key-and-uses-responses
  (let ((definition (cadr-ai:find-provider-definition :meta)))
    (is (string= "Meta" (cadr-ai:provider-definition-name definition)))
    (is (eq :openai-responses
            (cadr-ai:provider-definition-protocol definition)))
    (is (string= "https://api.meta.ai/v1"
                 (cadr-ai:provider-definition-base-url definition)))
    (is (string= "muse-spark-1.3"
                 (cadr-ai:provider-definition-default-model definition)))
    (is (string= "META_API_KEY"
                 (cadr-ai:provider-definition-key-environment definition)))
    (is (cadr-ai:provider-oauth-subscription-p :meta))
    (is (equal '("muse-spark-1.1" "muse-spark-1.2"
                 "muse-spark-1.2-contributor" "muse-spark-1.3"
                 "muse-spark-1.3-contributor" "muse-wonder-1.0")
               (mapcar #'cadr-ai:model-metadata-id
                       (cadr-ai:list-model-metadata :meta))))
    (dolist (metadata (cadr-ai:list-model-metadata :meta))
      (is (eq :openai-responses (cadr-ai:model-metadata-api metadata)))
      (is (string= "https://api.meta.ai/v1"
                   (cadr-ai:model-metadata-base-url metadata)))))
  (let ((auth
          (cadr-ai::built-in-api-key-auth
           (cadr-ai:find-provider-definition :meta)
           nil
           '(("META_API_KEY" . "sk-meta"))
           nil)))
    (is (string= "sk-meta" (cadr-ai::runtime-auth-result-api-key auth)))
    (is (string= "META_API_KEY" (cadr-ai::runtime-auth-result-source auth))))
  (multiple-value-bind (adapter model)
      (cadr-ai:instantiate-provider
       :meta :model-id "muse-spark-1.3"
       :oauth-access-token "LLM|minted-key")
    (is (typep adapter 'cadr-ai:openai-provider))
    (is (eq :openai-responses (cadr-ai:model-api model)))
    (is (string= "LLM|minted-key" (cadr-ai::provider-api-key adapter))))
  (let* ((credential
           (cadr-ai:make-oauth-credential
            :provider :meta
            :refresh "identity-token"
            :access "LLM|key"
            :expires 1))
         (auth
           (cadr-ai::built-in-oauth-to-auth
            (cadr-ai:find-provider-definition :meta)
            credential)))
    (is (string= "LLM|key" (cadr-ai::runtime-auth-result-api-key auth)))
    (is (eq :oauth (cadr-ai::runtime-auth-result-type auth)))))

(test meta-oauth-login-mints-a-day-long-model-api-key
  (let ((events (list nil))
        (calls nil)
        (clock 0))
    (with-meta-oauth-transport
        (calls clock
         (list
          (list "https://auth.meta.com/oidc/device/authorization/"
                (list '(("device_code" . "device-code-123")
                        ("user_code" . "ABCD-1234")
                        ("verification_uri" . "https://auth.meta.com/oauth/device/")
                        ("verification_uri_complete"
                         . "https://auth.meta.com/oauth/device/?code=ABCD-1234")
                        ("interval" . 5)
                        ("expires_in" . 600))
                      200))
          (list "https://auth.meta.com/oidc/device/token/"
                (list '(("error" . "authorization_pending")) 400)
                (list '(("access_token" . "identity-token")
                        ("token_type" . "Bearer"))
                      200))
          (list "https://api.meta.ai/muse-code/key"
                (list '(("api_key" . "LLM|minted-key")) 200))))
      (let ((credential
              (cadr-ai::login-meta-oauth
               (meta-oauth-interaction :events events))))
        (is (eq :meta (cadr-ai:oauth-credential-provider credential)))
        (is (string= "identity-token"
                     (cadr-ai:oauth-credential-refresh credential)))
        (is (string= "LLM|minted-key"
                     (cadr-ai:oauth-credential-access credential)))
        (is (= (+ +meta-oauth-start-ms+ 10000 +meta-oauth-day-ms+)
               (cadr-ai:oauth-credential-expires credential)))
        (is (= clock (+ +meta-oauth-start-ms+ 10000))))
      (let ((notices (reverse (car events)))
            (trace (reverse (car calls))))
        (is (equal '(:type :device-code
                     :user-code "ABCD-1234"
                     :verification-uri
                     "https://auth.meta.com/oauth/device/?code=ABCD-1234"
                     :interval-seconds 5
                     :expires-in-seconds 600)
                   (first notices)))
        (is (equal '(:type :progress
                     :message "Enabling Meta Model API access...")
                   (second notices)))
        (is (string= "client_id=1031625952748946"
                     (getf (first trace) :content)))
        (is (eq :post (getf (second trace) :method)))
        (is (search "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code"
                    (getf (second trace) :content)))
        (is (search "device_code=device-code-123"
                    (getf (second trace) :content)))
        (is (search "client_id=1031625952748946"
                    (getf (second trace) :content)))
        (let ((mint (fourth trace)))
          (is (string= "https://api.meta.ai/muse-code/key"
                       (getf mint :url)))
          (is (eq :post (getf mint :method)))
          (is (string= "{}" (getf mint :content)))
          (is (string= "Bearer identity-token"
                       (meta-oauth-header mint "Authorization")))
          (is (string= "1.0.0"
                       (meta-oauth-header mint "x-api-version"))))))))

(test meta-oauth-refresh-remints-from-the-identity-token
  (let ((cadr-ai::*meta-unix-milliseconds-function*
          (constantly +meta-oauth-noon-ms+))
        (cadr-ai::*oauth-flow-request-function*
          (lambda (url &key method headers content &allow-other-keys)
            (declare (ignore method content))
            (is (string= "https://api.meta.ai/muse-code/key" url))
            (is (string= "Bearer identity-token"
                         (cdr (assoc "Authorization" headers
                                     :test #'string=))))
            (values (cadr-ai::json-object "api_key" "LLM|fresh-key") 200))))
    (let ((credential
            (cadr-ai::refresh-meta-oauth-credential
             (cadr-ai:make-oauth-credential
              :provider :meta
              :refresh "identity-token"
              :access "LLM|old-key"
              :expires 1))))
      (is (string= "identity-token"
                   (cadr-ai:oauth-credential-refresh credential)))
      (is (string= "LLM|fresh-key"
                   (cadr-ai:oauth-credential-access credential)))
      (is (= (+ +meta-oauth-noon-ms+ +meta-oauth-day-ms+)
             (cadr-ai:oauth-credential-expires credential))))))

(test meta-oauth-reports-the-setup-url-when-meta-issues-no-key
  (let ((cadr-ai::*oauth-flow-request-function*
          (lambda (url &key &allow-other-keys)
            (declare (ignore url))
            (values
             (cadr-ai::json-object
              "require_payment" t
              "action_url" "https://dev.meta.ai/billing")
             200))))
    (is (string=
         "Meta did not issue an API key. Complete setup at https://dev.meta.ai/billing"
         (meta-oauth-error-message
          (lambda ()
            (cadr-ai::refresh-meta-oauth-credential
             (cadr-ai:make-oauth-credential
              :provider :meta :refresh "identity-token"
              :access "" :expires 1))))))))

(test meta-oauth-session-expiry-and-mint-failure-match-upstream
  (let ((cadr-ai::*oauth-flow-request-function*
          (lambda (url &key &allow-other-keys)
            (declare (ignore url))
            (values
             (cadr-ai::json-object "detail" "revoked")
             401))))
    (is (string=
         "Meta session expired (status 401). Run `/login meta` to sign in again.: revoked"
         (meta-oauth-error-message
          (lambda ()
            (cadr-ai::refresh-meta-oauth-credential
             (cadr-ai:make-oauth-credential
              :provider :meta :refresh "identity-token"
              :access "old" :expires 1)))))))
  (let ((cadr-ai::*oauth-flow-request-function*
          (lambda (url &key &allow-other-keys)
            (declare (ignore url))
            (values (cadr-ai::json-object "message" "upstream") 500))))
    (is (string=
         "Meta API key mint failed with status 500: upstream"
         (meta-oauth-error-message
          (lambda ()
            (cadr-ai::mint-meta-api-key "identity-token")))))))

(test meta-device-token-failures-use-meta-messages
  (is (string= "Meta login was denied."
               (getf (cadr-ai::meta-device-token-result
                      (cadr-ai::json-object "error" "access_denied")
                      400)
                     :message)))
  (is (string= "Meta device authorization expired. Please restart login."
               (getf (cadr-ai::meta-device-token-result
                      (cadr-ai::json-object "error" "expired_token")
                      400)
                     :message)))
  (is (string=
       "Meta device token request failed with status 400: slow"
       (getf (cadr-ai::meta-device-token-result
              (cadr-ai::json-object "error" "other" "detail" "slow")
              400)
             :message))))

(test meta-device-authorization-rejects-bad-responses
  (let ((cadr-ai::*oauth-flow-request-function*
          (lambda (url &key content &allow-other-keys)
            (declare (ignore url))
            (is (string= "client_id=1031625952748946" content))
            (values (cadr-ai::json-object "error_description" "nope") 503))))
    (is (string=
         "Meta device authorization failed with status 503: nope"
         (meta-oauth-error-message
          (lambda ()
            (cadr-ai::login-meta-oauth
             (meta-oauth-interaction)))))))
  (let ((cadr-ai::*oauth-flow-request-function*
          (lambda (url &key &allow-other-keys)
            (declare (ignore url))
            (values (cadr-ai::json-object "extra" t) 200))))
    (is (string=
         "Invalid Meta device authorization response: {\"extra\":true}"
         (meta-oauth-error-message
          (lambda ()
            (cadr-ai::login-meta-oauth
             (meta-oauth-interaction)))))))
  (let ((cadr-ai::*oauth-flow-request-function*
          (lambda (url &key &allow-other-keys)
            (declare (ignore url))
            (values
             (cadr-ai::json-object
              "device_code" "device"
              "user_code" "ABCD"
              "verification_uri" "javascript:alert(1)"
              "verification_uri_complete" "https://auth.meta.com/device")
             200))))
    (let ((device (cadr-ai::start-meta-device-authorization)))
      (is (string= "https://auth.meta.com/device"
                   (getf device :verification-uri-complete))))))

(test meta-oauth-login-cancel-uses-the-login-cancelled-message
  (let ((aborted nil)
        (sleeps 0))
    (let ((cadr-ai::*oauth-flow-request-function*
            (lambda (url &key &allow-other-keys)
              (if (search "authorization" url)
                  (values
                   (cadr-ai::json-object
                    "device_code" "device"
                    "user_code" "ABCD"
                    "verification_uri" "https://auth.meta.com/device"
                    "interval" 5
                    "expires_in" 600)
                   200)
                  (values
                   (cadr-ai::json-object "error" "authorization_pending")
                   400))))
          (cadr-ai::*oauth-flow-sleep-function*
            (lambda (seconds)
              (declare (ignore seconds))
              (setf aborted t)
              (incf sleeps))))
      (is (string= "Login cancelled"
                   (meta-oauth-error-message
                    (lambda ()
                      (cadr-ai::login-meta-oauth
                       (cadr-ai:make-runtime-auth-interaction
                        :abort-p (lambda () aborted)
                        :notify-function (lambda (event)
                                           (declare (ignore event))))))))
          "sleeps ~D" sleeps))))
