(in-package #:cadr-ai/tests)
(in-suite cadr-ai-suite)

(test pkce-matches-rfc-7636-vector
  (is (string=
       "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
       (cadr-ai:pkce-challenge
        "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"))))

(test openai-authorization-url-uses-approved-cadr-originator-difference
  (let ((url (cadr-ai:openai-authorization-url
              "challenge" "state-1")))
    (is (search "https://auth.openai.com/oauth/authorize?" url))
    (is (search "client_id=app_EMoamEEZ73f0CkXaXp7hrann" url))
    (is (search "redirect_uri=http%3A%2F%2Flocalhost%3A1455%2Fauth%2Fcallback"
                url))
    (is (search "code_challenge_method=S256" url))
    (is (search "state=state-1" url))
    (is (search "id_token_add_organizations=true" url))
    (is (search "codex_cli_simplified_flow=true" url))
    (is (search "originator=cadr" url))
    (is (not (search "originator=pi" url)))))

(test openai-token-credentials-use-openai-codex-provider-identity
  (let* ((payload
           (cadr-ai::json-object
            "https://api.openai.com/auth"
            (cadr-ai::json-object
             "chatgpt_account_id" "account-identity")))
         (access
           (format
            nil "e30.~A.signature"
            (cadr-ai::base64url-encode
             (babel:string-to-octets
              (cadr-ai::stringify-json payload)
              :encoding :utf-8))))
         (credential
           (cadr-ai::token-response-credential
            :openai-codex
            (cadr-ai::json-object
             "access_token" access
             "refresh_token" "refresh"
             "expires_in" 3600)
            nil)))
    (is (eq :openai-codex
            (cadr-ai:oauth-credential-provider
             credential)))
    (is (string=
         "account-identity"
         (cadr-ai:oauth-credential-account-id
          credential)))))

(test oauth-auth-url-presentation-is-structured-for-tui
  (let ((output (make-string-output-stream))
        (observed nil)
        (url "https://example.invalid/oauth?state=one&code=two"))
    (cadr-ai::present-oauth-auth-url
     url output
     (lambda (presented)
       (setf observed presented)))
    (is (string= url observed))
    (is (string= ""
                 (get-output-stream-string output))))
  (let ((output (make-string-output-stream))
        (url "https://example.invalid/oauth?state=one&code=two"))
    (cadr-ai::present-oauth-auth-url
     url output nil)
    (is (string=
         (format nil
                 "Open this URL in your browser:~%~A~%"
                 url)
         (get-output-stream-string output)))))

(test oauth-browser-launch-isolates-browser-diagnostics
  (let ((captured nil)
        (original
          (symbol-function 'uiop:launch-program)))
    (unwind-protect
         (progn
           (setf
            (symbol-function 'uiop:launch-program)
            (lambda (command &rest arguments)
              (setf captured
                    (cons command arguments))
              :process))
           (funcall
            cadr-ai::*oauth-browser-open-function*
            "https://example.invalid/oauth")
           (is (equal
                '("xdg-open"
                  "https://example.invalid/oauth")
                (first captured)))
           (is (null (getf (rest captured) :output)))
           (is (null
                (getf
                 (rest captured)
                 :error-output))))
      (setf
       (symbol-function 'uiop:launch-program)
       original))))

(test anthropic-authorization-url-matches-fixed-reference
  (let ((url
          (cadr-ai:anthropic-authorization-url
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
      (cadr-ai:parse-oauth-callback-request
       "GET /auth/callback?code=abc&state=expected HTTP/1.1"
       "/auth/callback" "expected")
    (is (string= "abc" code))
    (is (= 200 status)))
  (is (= 400
         (nth-value
          1
          (cadr-ai:parse-oauth-callback-request
           "GET /auth/callback?code=abc&state=wrong HTTP/1.1"
           "/auth/callback" "expected"))))
  (is (= 404
         (nth-value
          1
          (cadr-ai:parse-oauth-callback-request
           "GET /wrong?code=abc&state=expected HTTP/1.1"
           "/auth/callback" "expected")))))

(test auth-file-is-0600-and-round-trips-without-secret-output
  (uiop:with-temporary-file (:pathname path)
    (delete-file path)
    (let ((credential
            (cadr-ai:make-oauth-credential
             :provider :openai-codex
             :access "access-secret"
             :refresh "refresh-secret"
             :expires (+ (cadr-ai::unix-milliseconds) 3600000)
             :account-id "acct-1")))
      (cadr-ai:write-auth-credential path credential)
      (is (= #o600 (logand #o777 (cadr-ai:auth-file-mode path))))
      (let ((stored
              (cadr-ai:read-auth-credential
               path :openai-codex)))
        (is (string= "access-secret"
                     (cadr-ai:oauth-credential-access stored)))
        (is (string= "acct-1"
                     (cadr-ai:oauth-credential-account-id stored))))
      (let ((redacted
              (cadr-ai:redact-secrets
               "Authorization: Bearer access-secret refresh-secret"
               '("access-secret" "refresh-secret"))))
        (is (not (search "access-secret" redacted)))
        (is (not (search "refresh-secret" redacted)))
        (is (search "[REDACTED]" redacted)))
      (cadr-ai:delete-auth-credential
       path :openai-codex)
      (is (null
           (cadr-ai:read-auth-credential
            path :openai-codex))))))

(test oauth-refresh-is-double-checked-under-lock
  (uiop:with-temporary-file (:pathname path)
    (delete-file path)
    (cadr-ai:write-auth-credential
     path
     (cadr-ai:make-oauth-credential
      :provider :openai-codex
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
            (cadr-ai:resolve-oauth-credential
             path :openai-codex
             (lambda (credential)
               (declare (ignore credential))
               (bt:with-lock-held ((cadr-ai::provider-auth-lock :test-counter))
                 (incf refreshes))
               (cadr-ai:make-oauth-credential
                :provider :openai-codex
                :access "new"
                :refresh "rotated"
                :expires (+ (cadr-ai::unix-milliseconds) 3600000)
                :account-id "acct")))))
         threads))
      (dolist (thread threads)
        (bt:join-thread thread))
      (is (= 1 refreshes))
      (is (string= "new"
                   (cadr-ai:oauth-credential-access
                    (cadr-ai:read-auth-credential
                     path :openai-codex)))))))

(test openai-oauth-uses-codex-url-and-approved-cadr-originator-header
  (let* ((provider
           (cadr-ai:make-openai-codex-provider
            :oauth-access-token "oauth-secret"
            :oauth-account-id "acct-7"))
         (model
           (cadr-ai:make-model
            :id "gpt-5.5"
            :provider :openai-codex
            :api :openai-codex-responses
            :base-url "https://chatgpt.com/backend-api"))
         (request
           (cadr-ai:build-request provider model (sample-context)
                                :stream-p t))
         (headers (cadr-ai:request-spec-headers request)))
    (is (string=
         "https://chatgpt.com/backend-api/codex/responses"
         (cadr-ai:request-spec-url request)))
    (is (string= "Bearer oauth-secret"
                 (cdr (assoc "authorization" headers
                             :test #'string-equal))))
    (is (string= "acct-7"
                 (cdr (assoc "chatgpt-account-id" headers
                             :test #'string-equal))))
    (is (string= "cadr"
                 (cdr (assoc "originator" headers
                             :test #'string-equal))))
    (is (string= "responses=experimental"
                 (cdr (assoc "openai-beta" headers
                             :test #'string-equal))))))

(test oauth-access-token-is-redacted-from-provider-errors
  (let* ((secret "oauth-access-must-not-leak")
         (provider
           (cadr-ai:make-openai-codex-provider
            :oauth-access-token secret
            :oauth-account-id "acct-7"))
         (model
           (cadr-ai:make-model
            :id "gpt-5.5"
            :provider :openai-codex
            :api :openai-codex-responses
            :base-url "https://chatgpt.com/backend-api"))
         (context (sample-context))
         (cadr-ai::*max-provider-retries* 0)
         (cadr-ai::*http-request-function*
           (lambda (url &rest arguments)
             (declare (ignore url arguments))
             (error "transport echoed ~A" secret))))
    (let* ((message
             (cadr-ai:complete-chat
              provider model context))
           (error-text
             (cadr-ai:assistant-message-error-message
              message)))
      (is (not (search secret error-text)))
      (is (search "[REDACTED]" error-text)))
    (let* ((message
             (cadr-ai:stream-chat
              provider model context
              (lambda (event)
                (declare (ignore event)))))
           (error-text
             (cadr-ai:assistant-message-error-message
              message)))
      (is (not (search secret error-text)))
      (is (search "[REDACTED]" error-text)))
    (let* ((request
             (cadr-ai:build-request
              provider model context :stream-p nil))
           (cadr-ai::*http-request-function*
             (lambda (url &rest arguments)
               (declare (ignore url arguments))
               (values
                (cadr-ai::stringify-json
                 (cadr-ai::json-object
                  "error"
                  (cadr-ai::json-object
                   "message"
                   (format nil "server echoed ~A"
                           secret))))
                401
                nil))))
      (handler-case
          (progn
            (cadr-ai::request-json request)
            (fail "Expected api-error"))
        (cadr-ai:api-error (condition)
          (let ((error-text
                  (cadr-ai:cadr-error-message
                   condition)))
            (is (not (search secret error-text)))
            (is (search "[REDACTED]"
                        error-text))))))))

(test expired-openai-token-refreshes-once-then-builds-request
  (uiop:with-temporary-file (:pathname path)
    (delete-file path)
    (cadr-ai:write-auth-credential
     path
     (cadr-ai:make-oauth-credential
      :provider :openai-codex
      :access "expired-access"
      :refresh "refresh-secret"
      :expires 0
      :account-id "old-account"))
    (let* ((payload
             (cadr-ai::json-object
              "https://api.openai.com/auth"
              (cadr-ai::json-object
               "chatgpt_account_id" "account-new")))
           (access
             (format
              nil "e30.~A.signature"
              (cadr-ai::base64url-encode
               (babel:string-to-octets
                (cadr-ai::stringify-json payload)
                :encoding :utf-8))))
           (calls 0)
           (cadr-ai::*oauth-http-request-function*
             (lambda (url &rest arguments)
               (declare (ignore url))
               (incf calls)
               (is (not
                    (search "expired-access"
                            (or (getf arguments :content) ""))))
               (values
                (cadr-ai::stringify-json
                 (cadr-ai::json-object
                  "access_token" access
                  "refresh_token" "refresh-rotated"
                  "expires_in" 3600))
                200
                nil))))
      (let* ((credential
               (cadr-ai:resolve-oauth-credential
                path :openai-codex
                #'cadr-ai:refresh-openai-oauth-credential))
             (provider
               (cadr-ai:make-openai-codex-provider
                :oauth-access-token
                (cadr-ai:oauth-credential-access credential)
                :oauth-account-id
                (cadr-ai:oauth-credential-account-id credential)))
             (model
               (cadr-ai:make-model
                :id "gpt-5.5"
                :provider :openai-codex
                :api :openai-codex-responses
                :base-url "https://chatgpt.com/backend-api"))
             (request
               (cadr-ai:build-request
                provider model (sample-context) :stream-p t)))
        (is (= 1 calls))
        (is (string= "account-new"
                     (cdr
                      (assoc
                       "chatgpt-account-id"
                       (cadr-ai:request-spec-headers request)
                       :test #'string-equal))))
        (is (not
             (search
              "expired-access"
              (cadr-ai::stringify-json
               (cadr-ai:request-spec-payload request)))))))))
