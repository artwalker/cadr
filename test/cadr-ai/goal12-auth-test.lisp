(in-package #:cadr-ai/tests)

(in-suite cadr-ai-suite)

(test goal12-auth-interaction-accepts-the-full-baseline-prompt-and-event-surface
  (let* ((prompts nil)
        (events nil)
        (interaction
          (cadr-ai:make-runtime-auth-interaction
           :prompt-function
           (lambda (prompt)
             (push prompt prompts)
             (if (eq :select (getf prompt :type)) "browser" "code"))
           :notify-function (lambda (event) (push event events)))))
    (is (string=
         "browser"
         (cadr-ai:runtime-auth-interaction-prompt
          interaction
          '(:type :select :message "Choose"
            :options ((:id "browser" :label "Browser"))))))
    (is (string=
         "code"
         (cadr-ai:runtime-auth-interaction-prompt
          interaction
          '(:type :manual-code :message "Paste code"
            :placeholder "http://127.0.0.1"))))
    (cadr-ai:runtime-auth-interaction-notify
     interaction
     '(:type :auth-url :url "https://example.test/auth"
       :instructions "Continue"))
    (cadr-ai:runtime-auth-interaction-notify
     interaction
     '(:type :device-code :user-code "ABCD"
       :verification-uri "https://example.test/device"
       :interval-seconds 5 :expires-in-seconds 900))
    (is (= 2 (length prompts)))
    (is (= 2 (length events)))))

(test goal12-generic-oauth-login-persists-provider-owned-credential
  (let* ((store (cadr-ai:make-memory-credential-store))
         (runtime (cadr-ai:make-models-runtime :credential-store store))
         (interaction (cadr-ai:make-runtime-auth-interaction))
         (provider
           (cadr-ai:make-runtime-provider
            :id :fixture :name "Fixture" :oauth-auth-p t
            :oauth-login-function
            (lambda (actual-interaction)
              (is (eq interaction actual-interaction))
              (cadr-ai:make-oauth-credential
               :provider :wrong :access "access" :refresh "refresh"
               :expires (+ (cadr-ai::unix-milliseconds) 3600000)
               :metadata '(("scope" . "fixture")))))))
    (cadr-ai:models-runtime-set-provider runtime provider)
    (let ((credential
            (cadr-ai::models-runtime-login
             runtime :fixture :oauth interaction)))
      (is (eq :fixture (cadr-ai:oauth-credential-provider credential)))
      (is (equal '(("scope" . "fixture"))
                 (cadr-ai::oauth-credential-metadata credential)))
      (is (eq credential
              (cadr-ai:credential-store-read store :fixture))))))

(test goal12-provider-owned-oauth-metadata-round-trips-at-the-baseline-json-level
  (uiop:with-temporary-file (:pathname path)
    (delete-file path)
    (cadr-ai:write-auth-credential
     path
     (cadr-ai:make-oauth-credential
      :provider :github-copilot
      :access "access" :refresh "refresh" :expires 99
      :metadata
      '(("enterpriseUrl" . "github.example.test")
        ("availableModelIds" . #("gpt-5.4" "claude-opus-4.8")))))
    (let* ((root
             (cadr-ai::parse-json
              (uiop:read-file-string path :external-format :utf-8)))
           (object (cadr-ai::json-get root "github-copilot"))
           (stored
             (cadr-ai:read-auth-credential path :github-copilot)))
      (is (string= "github.example.test"
                   (cadr-ai::json-get object "enterpriseUrl")))
      (is (equalp #("gpt-5.4" "claude-opus-4.8")
                  (cadr-ai::json-get object "availableModelIds")))
      (is (equalp #("gpt-5.4" "claude-opus-4.8")
                  (cdr (assoc "availableModelIds"
                              (cadr-ai:oauth-credential-metadata stored)
                              :test #'string=)))))))

(test goal12-all-bundled-oauth-providers-load-login-refresh-and-auth-contracts
  (let ((runtime
          (cadr-ai:make-built-in-models-runtime
           :environment '(("RADIUS_GATEWAY_URL" . "https://radius.test")))))
    (dolist (provider-id
             '(:anthropic :github-copilot :kimi-coding :meta :openai-codex
               :openrouter :radius :xai))
      (let ((provider (cadr-ai:models-runtime-provider runtime provider-id)))
        (is (functionp
             (cadr-ai::runtime-provider-oauth-login-function provider))
            "~A has no OAuth login" provider-id)
        (is (functionp
             (cadr-ai::runtime-provider-oauth-refresh-function provider))
            "~A has no OAuth refresh" provider-id)
        (is (functionp
             (cadr-ai::runtime-provider-oauth-to-auth-function provider))
            "~A has no OAuth to-auth" provider-id)))))

(test goal12-xai-device-login-emits-baseline-event-and-uses-rfc8628-polling
  (let* ((requests nil)
        (events nil)
        (responses
          (list
           (list
            (cadr-ai::json-object
             "device_code" "device" "user_code" "ABCD"
             "verification_uri" "https://auth.x.ai/activate"
             "verification_uri_complete" "https://auth.x.ai/activate?code=ABCD"
             "interval" 5 "expires_in" 900)
            200)
           (list
            (cadr-ai::json-object "error" "authorization_pending")
            400)
           (list
            (cadr-ai::json-object
             "access_token" "access" "refresh_token" "refresh"
             "expires_in" 3600)
            200)))
        (interaction
          (cadr-ai:make-runtime-auth-interaction
           :notify-function (lambda (event) (push event events)))))
    (let ((cadr-ai::*oauth-flow-request-function*
            (lambda (url &rest options)
              (push (list url options) requests)
              (let ((response (pop responses)))
                (values-list response))))
          (cadr-ai::*oauth-flow-sleep-function* (lambda (seconds)
                                                   (declare (ignore seconds)))))
      (let ((credential (cadr-ai::login-xai-oauth interaction)))
        (is (string= "access" (cadr-ai:oauth-credential-access credential)))
        (is (string= "refresh" (cadr-ai:oauth-credential-refresh credential)))))
    (is (= 3 (length requests)))
    (let* ((device-request (car (last requests)))
           (options (second device-request)))
      (is (string= "https://auth.x.ai/oauth2/device/code"
                   (first device-request)))
      (is (search "referrer=cadr" (getf options :content)))
      (is (not (search "referrer=pi" (getf options :content)))))
    (let ((event (first events)))
      (is (eq :device-code (getf event :type)))
      (is (string= "ABCD" (getf event :user-code)))
      (is (string= "https://auth.x.ai/activate?code=ABCD"
                   (getf event :verification-uri))))))
