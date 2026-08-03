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

(test goal13-oauth-pages-match-baseline-shell-copy-and-escaping
  (let ((success
          (cadr-ai::oauth-success-html
           "OpenAI <done> & close \"this\" window."))
        (failure
          (cadr-ai::oauth-error-html
           "Anthropic <failed> & retry."
           "Error: bad \"state\" & 'token'")))
    (dolist (fragment
             '("<!doctype html>"
               "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />"
               "<title>Authentication successful</title>"
               "<h1>Authentication successful</h1>"
               "color-scheme: dark"
               "<svg xmlns=\"http://www.w3.org/2000/svg\""))
      (is (search fragment success)))
    (is (search
         "OpenAI &lt;done&gt; &amp; close &quot;this&quot; window."
         success))
    (is (null (search "OpenAI <done>" success)))
    (is (search "<title>Authentication failed</title>" failure))
    (is (search "<h1>Authentication failed</h1>" failure))
    (is (search "Anthropic &lt;failed&gt; &amp; retry." failure))
    (is (search
         "Error: bad &quot;state&quot; &amp; &#39;token&#39;"
         failure))
    (is (null (search "bad \"state\"" failure))))
  (let ((rendered
          (cadr-ai::render-oauth-page
           "<&\"'" ">&\"'<" "&<>'\"" "'<&>\"")))
    (is (search "<title>&lt;&amp;&quot;&#39;</title>" rendered))
    (is (search "<h1>&gt;&amp;&quot;&#39;&lt;</h1>" rendered))
    (is (search "&amp;&lt;&gt;&#39;&quot;" rendered))
    (is (search "&#39;&lt;&amp;&gt;&quot;" rendered))))

(test goal13-oauth-callback-copy-distinguishes-every-baseline-failure
  (flet ((parse (request provider)
           (multiple-value-list
            (cadr-ai:parse-oauth-callback-request
             request "/auth/callback" "expected"
             :provider-name provider))))
    (is (equal '(nil 404 :route-not-found nil)
               (parse
                "GET /wrong?code=abc&state=expected HTTP/1.1"
                "OpenAI")))
    (is (equal '(nil 400 :state-mismatch nil)
               (parse
                "GET /auth/callback?code=abc&state=wrong HTTP/1.1"
                "OpenAI")))
    (is (equal '(nil 400 :missing-authorization-code nil)
               (parse
                "GET /auth/callback?state=expected HTTP/1.1"
                "OpenAI")))
    (is (equal
         '(nil 400 :provider-error "Error: access_denied")
         (parse
          "GET /auth/callback?error=access_denied&state=expected HTTP/1.1"
          "Anthropic")))
    (is (equal '(nil 400 :missing-code-or-state nil)
               (parse
                "GET /auth/callback?code=abc HTTP/1.1"
                "Anthropic")))
    (is (equal '(nil 500 :internal-error nil)
               (parse
                "GET /auth/callback?code=%ZZ&state=expected HTTP/1.1"
                "OpenAI"))))
  (dolist
      (case
       '(("OpenAI" 200 :success
          "OpenAI authentication completed. You can close this window.")
         ("OpenAI" 404 :route-not-found
          "Callback route not found.")
         ("OpenAI" 400 :state-mismatch
          "State mismatch.")
         ("OpenAI" 400 :missing-authorization-code
          "Missing authorization code.")
         ("OpenAI" 500 :internal-error
          "Internal error while processing OAuth callback.")
         ("Anthropic" 400 :provider-error
          "Anthropic authentication did not complete.")
         ("Anthropic" 400 :missing-code-or-state
          "Missing code or state parameter.")
         ("Radius" 200 :success
          "Signed in to Radius. You may now close this page.")
         ("Radius" 400 :state-mismatch
          "OAuth state mismatch.")))
    (destructuring-bind (provider status reason expected) case
      (is (string=
           expected
           (nth-value
            0
            (cadr-ai::oauth-callback-response-copy
             provider status reason nil)))))))

(test goal13-oauth-http-response-keeps-byte-accurate-html-framing
  (let* ((stream (make-string-output-stream))
         (body (cadr-ai::oauth-success-html "认证完成")))
    (cadr-ai::write-oauth-http-response stream 200 body)
    (let* ((response (get-output-stream-string stream))
           (separator (format nil "~C~C~C~C"
                              #\Return #\Linefeed
                              #\Return #\Linefeed))
           (body-start (+ (search separator response)
                          (length separator))))
      (is (search "HTTP/1.1 200 OK" response))
      (is (search "Content-Type: text/html; charset=utf-8" response))
      (is (search
           (format nil "Content-Length: ~D"
                   (length (babel:string-to-octets
                            body :encoding :utf-8)))
           response))
      (is (string= body (subseq response body-start))))))

(test goal13-manual-oauth-input-matches-baseline-url-code-and-state-forms
  (is (equal
       '("code-a" "state-a")
       (multiple-value-list
        (cadr-ai::parse-oauth-authorization-input
         "http://localhost:1455/auth/callback?code=code-a&state=state-a"))))
  (is (equal
       '("code-b" "state-b")
       (multiple-value-list
        (cadr-ai::parse-oauth-authorization-input
         "code-b#state-b"))))
  (is (equal
       '("code-c" "state-c")
       (multiple-value-list
        (cadr-ai::parse-oauth-authorization-input
         "code=code-c&state=state-c"))))
  (is (equal
       '("code-d" nil)
       (multiple-value-list
        (cadr-ai::parse-oauth-authorization-input
         " code-d ")))))

(test goal13-callback-and-manual-oauth-input-race-cancels-the-loser
  (let ((callback-cancelled-p nil)
        (prompt nil))
    (is
     (string=
      "manual-code"
      (cadr-ai::wait-for-oauth-authorization
       "expected-state"
       (lambda (cancelled-p)
         (loop until (funcall cancelled-p)
               do (sb-thread:thread-yield))
         (setf callback-cancelled-p t)
         nil)
       (lambda (value)
         (setf prompt value)
         "http://localhost:1455/auth/callback?code=manual-code&state=expected-state")
       '(:type :manual-code
         :message "Complete login in your browser, or paste the authorization code / redirect URL here:"
         :placeholder "http://localhost:1455/auth/callback"))))
    (is (not (null callback-cancelled-p)))
    (is (functionp (getf prompt :cancel-function)))
    (is (functionp (getf prompt :cancelled-p-function))))
  (let ((manual-cancelled-p nil))
    (is
     (string=
      "callback-code"
      (cadr-ai::wait-for-oauth-authorization
       "expected-state"
       (lambda (cancelled-p)
         (declare (ignore cancelled-p))
         "callback-code")
       (lambda (prompt)
         (loop until (funcall (getf prompt :cancelled-p-function))
               do (sb-thread:thread-yield))
         (setf manual-cancelled-p t)
         nil)
       '(:type :manual-code
         :message "manual"
         :placeholder "callback"))))
    (is (not (null manual-cancelled-p))))
  (signals cadr-ai:authentication-error
    (cadr-ai::wait-for-oauth-authorization
     "expected-state"
     (lambda (cancelled-p)
       (loop until (funcall cancelled-p)
             do (sb-thread:thread-yield)))
     (lambda (prompt)
       (declare (ignore prompt))
       "code#wrong-state")
     '(:type :manual-code :message "manual"))))

(test goal13-oauth-cancel-aborts-the-loopback-worker-and-releases-it
  (let ((callback-stopped-p nil)
        (prompt nil))
    (signals cadr-ai:authentication-error
      (cadr-ai::wait-for-oauth-authorization
       "expected-state"
       (lambda (cancelled-p)
         (loop until (funcall cancelled-p)
               do (sb-thread:thread-yield))
         (setf callback-stopped-p t)
         nil)
       (lambda (value)
         (setf prompt value)
         (funcall (getf value :cancel-function))
         nil)
       '(:type :manual-code :message "manual")))
    (is (not (null callback-stopped-p)))
    (is (functionp (getf prompt :cancel-function)))
    (is (funcall (getf prompt :cancelled-p-function)))))

(test goal13-every-built-in-oauth-cancel-closes-its-loopback-listener
  (labels
      ((port-bindable-p (port)
         (let ((socket
                 (make-instance
                  'sb-bsd-sockets:inet-socket
                  :type :stream :protocol :tcp)))
           (unwind-protect
                (handler-case
                    (progn
                      (sb-bsd-sockets:socket-bind
                       socket #(127 0 0 1) port)
                      t)
                  (error () nil))
             (ignore-errors
               (sb-bsd-sockets:socket-close socket)))))
       (cancel-at-prompt (prompt)
         (funcall (getf prompt :cancel-function))
         nil)
       (run-cancelled-login (function port)
         (let ((bindable-before-p
                 (port-bindable-p port)))
           (signals cadr-ai:authentication-error
             (funcall
              function nil
              :output (make-string-output-stream)
              :open-browser (constantly nil)
              :auth-prompt-function #'cancel-at-prompt))
           ;; A separately running cadr login can legitimately own the fixed
           ;; baseline port.  In a clean test process this assertion proves
           ;; release; in a shared developer environment it proves that the
           ;; cancelled login did not change listener ownership.
           (is (eql bindable-before-p
                    (port-bindable-p port))))))
    (run-cancelled-login #'cadr-ai:login-openai-oauth 1455)
    (run-cancelled-login #'cadr-ai:login-anthropic-oauth 53692)))

(test goal13-credential-bearing-objects-never-print-secret-material
  (let* ((api-key "api-key-must-never-print")
         (access "oauth-access-must-never-print")
         (refresh "oauth-refresh-must-never-print")
         (objects
           (list
            (cadr-ai:make-api-key-credential
             :provider :faux :key api-key)
            (cadr-ai:make-oauth-credential
             :provider :openai-codex
             :access access :refresh refresh
             :expires 1 :account-id "acct")
            (cadr-ai:make-openai-codex-provider
             :api-key api-key
             :oauth-access-token access
             :oauth-account-id "acct")
            (cadr-ai::make-runtime-auth-result
             :api-key api-key
             :headers
             `(("authorization" . ,(format nil "Bearer ~A" access))))
            (cadr-ai::make-request-spec
             :url "https://example.invalid"
             :headers
             `(("authorization" . ,(format nil "Bearer ~A" access)))
             :payload
             (cadr-ai::json-object "refresh_token" refresh))
            (cadr-ai:make-model-metadata
             :provider :faux :id "secret-model"
             :headers `(("authorization" . ,access)))
            (cadr-ai:make-image-model
             :provider :faux :id "secret-image-model"
             :headers `(("authorization" . ,access))))))
    (dolist (object objects)
      (let ((printed (write-to-string object :readably nil)))
        (dolist (secret (list api-key access refresh))
          (is (null (search secret printed))))
        (is (search "REDACTED" printed))))))

(test goal13-oauth-page-uses-cadr-owned-grid-cons-cell-mark
  (let ((logo cadr-ai::+oauth-logo-svg+))
    (is (search "viewBox=\"0 0 800 800\"" logo))
    (is (search "fill=\"#fff\"" logo))
    (is (search "fill-rule=\"evenodd\"" logo))
    (is (search "aria-hidden=\"true\"" logo))
    (is (search
         "M47.93 165.29 H400.01 V517.37 H47.93 Z"
         logo))
    (is (search
         "M400.01 165.29 H752.09 V517.37 H400.01 Z"
         logo))
    (is (search
         "M165.29 282.65 H282.65 V400.01 H165.29 Z"
         logo))
    (is (search
         "M517.37 282.65 H634.73 V165.29 H752.09 V517.37 H634.73 V400.01 H517.37 Z"
         logo))
    (let ((first-path (search "<path" logo)))
      (is (not (null first-path)))
      (is (null (search "<path" logo
                        :start2 (+ first-path 5)))))
    (is (null (search "stroke=" logo)))
    (is (null (search "gradient" logo)))
    (is (null (search
               "M165.29 165.29 H634.72 V282.65"
               logo)))
    (is (null (search
               "M517.37 282.65 H634.73 V400.01 H517.37 Z"
               logo)))))

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
      (is (string= "fetch failed" error-text)))
    (let* ((message
             (cadr-ai:stream-chat
              provider model context
              (lambda (event)
                (declare (ignore event)))))
           (error-text
             (cadr-ai:assistant-message-error-message
              message)))
      (is (not (search secret error-text)))
      (is (string= "fetch failed" error-text)))
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
