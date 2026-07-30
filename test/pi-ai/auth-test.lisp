(in-package #:pi-ai/tests)
(in-suite pi-ai-suite)

(test pkce-matches-rfc-7636-vector
  (is (string=
       "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
       (pi-ai:pkce-challenge
        "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"))))

(test openai-authorization-url-matches-fixed-reference
  (let ((url (pi-ai:openai-authorization-url
              "challenge" "state-1")))
    (is (search "https://auth.openai.com/oauth/authorize?" url))
    (is (search "client_id=app_EMoamEEZ73f0CkXaXp7hrann" url))
    (is (search "redirect_uri=http%3A%2F%2Flocalhost%3A1455%2Fauth%2Fcallback"
                url))
    (is (search "code_challenge_method=S256" url))
    (is (search "state=state-1" url))
    (is (search "id_token_add_organizations=true" url))
    (is (search "codex_cli_simplified_flow=true" url))
    (is (search "originator=pi" url))))

(test anthropic-authorization-url-matches-fixed-reference
  (let ((url
          (pi-ai:anthropic-authorization-url
           "challenge" "state-1")))
    (is (search "https://claude.ai/oauth/authorize?" url))
    (is (search
         "client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e"
         url))
    (is (search
         "redirect_uri=http%3A%2F%2Flocalhost%3A53692%2Fcallback"
         url))
    (is (search "state=state-1" url))))

(test oauth-callback-parser-validates-path-and-state
  (multiple-value-bind (code status)
      (pi-ai:parse-oauth-callback-request
       "GET /auth/callback?code=abc&state=expected HTTP/1.1"
       "/auth/callback" "expected")
    (is (string= "abc" code))
    (is (= 200 status)))
  (is (= 400
         (nth-value
          1
          (pi-ai:parse-oauth-callback-request
           "GET /auth/callback?code=abc&state=wrong HTTP/1.1"
           "/auth/callback" "expected"))))
  (is (= 404
         (nth-value
          1
          (pi-ai:parse-oauth-callback-request
           "GET /wrong?code=abc&state=expected HTTP/1.1"
           "/auth/callback" "expected")))))

(test auth-file-is-0600-and-round-trips-without-secret-output
  (uiop:with-temporary-file (:pathname path)
    (delete-file path)
    (let ((credential
            (pi-ai:make-oauth-credential
             :provider :openai
             :access "access-secret"
             :refresh "refresh-secret"
             :expires (+ (pi-ai::unix-milliseconds) 3600000)
             :account-id "acct-1")))
      (pi-ai:write-auth-credential path credential)
      (is (= #o600 (logand #o777 (pi-ai:auth-file-mode path))))
      (let ((stored (pi-ai:read-auth-credential path :openai)))
        (is (string= "access-secret"
                     (pi-ai:oauth-credential-access stored)))
        (is (string= "acct-1"
                     (pi-ai:oauth-credential-account-id stored))))
      (let ((redacted
              (pi-ai:redact-secrets
               "Authorization: Bearer access-secret refresh-secret"
               '("access-secret" "refresh-secret"))))
        (is (not (search "access-secret" redacted)))
        (is (not (search "refresh-secret" redacted)))
        (is (search "[REDACTED]" redacted)))
      (pi-ai:delete-auth-credential path :openai)
      (is (null (pi-ai:read-auth-credential path :openai))))))

(test oauth-refresh-is-double-checked-under-lock
  (uiop:with-temporary-file (:pathname path)
    (delete-file path)
    (pi-ai:write-auth-credential
     path
     (pi-ai:make-oauth-credential
      :provider :openai
      :access "old"
      :refresh "refresh"
      :expires 0
      :account-id "acct"))
    (let ((refreshes 0)
          (threads nil))
      (dotimes (index 6)
        (declare (ignorable index))
        (push
         (bt:make-thread
          (lambda ()
            (pi-ai:resolve-oauth-credential
             path :openai
             (lambda (credential)
               (declare (ignore credential))
               (bt:with-lock-held ((pi-ai::provider-auth-lock :test-counter))
                 (incf refreshes))
               (pi-ai:make-oauth-credential
                :provider :openai
                :access "new"
                :refresh "rotated"
                :expires (+ (pi-ai::unix-milliseconds) 3600000)
                :account-id "acct")))))
         threads))
      (dolist (thread threads)
        (bt:join-thread thread))
      (is (= 1 refreshes))
      (is (string= "new"
                   (pi-ai:oauth-credential-access
                    (pi-ai:read-auth-credential path :openai)))))))

(test openai-oauth-uses-codex-url-and-reference-headers
  (let* ((provider
           (pi-ai:make-openai-provider
            :oauth-access-token "oauth-secret"
            :oauth-account-id "acct-7"))
         (model
           (pi-ai:make-model
            :id "gpt-5.5"
            :provider :openai
            :api :openai-responses
            :base-url "https://chatgpt.com/backend-api"))
         (request
           (pi-ai:build-request provider model (sample-context)
                                :stream-p t))
         (headers (pi-ai:request-spec-headers request)))
    (is (string=
         "https://chatgpt.com/backend-api/codex/responses"
         (pi-ai:request-spec-url request)))
    (is (string= "Bearer oauth-secret"
                 (cdr (assoc "authorization" headers
                             :test #'string-equal))))
    (is (string= "acct-7"
                 (cdr (assoc "chatgpt-account-id" headers
                             :test #'string-equal))))
    (is (string= "pi"
                 (cdr (assoc "originator" headers
                             :test #'string-equal))))
    (is (string= "responses=experimental"
                 (cdr (assoc "openai-beta" headers
                             :test #'string-equal))))))

(test oauth-access-token-is-redacted-from-provider-errors
  (let* ((secret "oauth-access-must-not-leak")
         (provider
           (pi-ai:make-openai-provider
            :oauth-access-token secret
            :oauth-account-id "acct-7"))
         (model
           (pi-ai:make-model
            :id "gpt-5.5"
            :provider :openai
            :api :openai-responses
            :base-url "https://chatgpt.com/backend-api"))
         (context (sample-context))
         (pi-ai::*max-provider-retries* 0)
         (pi-ai::*http-request-function*
           (lambda (url &rest arguments)
             (declare (ignore url arguments))
             (error "transport echoed ~A" secret))))
    (let* ((message
             (pi-ai:complete-chat
              provider model context))
           (error-text
             (pi-ai:assistant-message-error-message
              message)))
      (is (not (search secret error-text)))
      (is (search "[REDACTED]" error-text)))
    (let* ((message
             (pi-ai:stream-chat
              provider model context
              (lambda (event)
                (declare (ignore event)))))
           (error-text
             (pi-ai:assistant-message-error-message
              message)))
      (is (not (search secret error-text)))
      (is (search "[REDACTED]" error-text)))
    (let* ((request
             (pi-ai:build-request
              provider model context :stream-p nil))
           (pi-ai::*http-request-function*
             (lambda (url &rest arguments)
               (declare (ignore url arguments))
               (values
                (pi-ai::stringify-json
                 (pi-ai::json-object
                  "error"
                  (pi-ai::json-object
                   "message"
                   (format nil "server echoed ~A"
                           secret))))
                401
                nil))))
      (handler-case
          (progn
            (pi-ai::request-json request)
            (fail "Expected api-error"))
        (pi-ai:api-error (condition)
          (let ((error-text
                  (pi-ai:pi-error-message
                   condition)))
            (is (not (search secret error-text)))
            (is (search "[REDACTED]"
                        error-text))))))))

(test expired-openai-token-refreshes-once-then-builds-request
  (uiop:with-temporary-file (:pathname path)
    (delete-file path)
    (pi-ai:write-auth-credential
     path
     (pi-ai:make-oauth-credential
      :provider :openai
      :access "expired-access"
      :refresh "refresh-secret"
      :expires 0
      :account-id "old-account"))
    (let* ((payload
             (pi-ai::json-object
              "https://api.openai.com/auth"
              (pi-ai::json-object
               "chatgpt_account_id" "account-new")))
           (access
             (format
              nil "e30.~A.signature"
              (pi-ai::base64url-encode
               (babel:string-to-octets
                (pi-ai::stringify-json payload)
                :encoding :utf-8))))
           (calls 0)
           (pi-ai::*oauth-http-request-function*
             (lambda (url &rest arguments)
               (declare (ignore url))
               (incf calls)
               (is (not
                    (search "expired-access"
                            (or (getf arguments :content) ""))))
               (values
                (pi-ai::stringify-json
                 (pi-ai::json-object
                  "access_token" access
                  "refresh_token" "refresh-rotated"
                  "expires_in" 3600))
                200
                nil))))
      (let* ((credential
               (pi-ai:resolve-oauth-credential
                path :openai
                #'pi-ai:refresh-openai-oauth-credential))
             (provider
               (pi-ai:make-openai-provider
                :oauth-access-token
                (pi-ai:oauth-credential-access credential)
                :oauth-account-id
                (pi-ai:oauth-credential-account-id credential)))
             (model
               (pi-ai:make-model
                :id "gpt-5.5"
                :provider :openai
                :api :openai-responses
                :base-url "https://chatgpt.com/backend-api"))
             (request
               (pi-ai:build-request
                provider model (sample-context) :stream-p t)))
        (is (= 1 calls))
        (is (string= "account-new"
                     (cdr
                      (assoc
                       "chatgpt-account-id"
                       (pi-ai:request-spec-headers request)
                       :test #'string-equal))))
        (is (not
             (search
              "expired-access"
              (pi-ai::stringify-json
               (pi-ai:request-spec-payload request)))))))))
