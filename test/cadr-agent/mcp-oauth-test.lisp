(in-package #:cadr-agent/tests)

(in-suite cadr-agent-suite)

;;; Locked to pi v1.4.0 packages/mcp/test/oauth.test.ts, refresh.test.ts,
;;; store.test.ts, and packages/coding-agent/src/extensions/mcp/oauth.ts.
;;; Product client_name is Cadr. CIMD client ids stay on the hosted
;;; document the authorization server fetches.

(defun mcp-oauth-json (value)
  (cadr-agent::mcp-write-json value))

(defun mcp-oauth-test-path (url)
  (getf (cadr-agent::mcp-oauth-parse-url url) :pathname))

(defun mcp-oauth-test-fetch (handler)
  (lambda (url &key method headers body signal)
    (declare (ignore signal))
    (funcall handler url (or method :get) headers body)))

(defun mcp-oauth-response (status value &optional headers)
  (values status
          (if (stringp value) value (mcp-oauth-json value))
          headers))

(defun mcp-oauth-metadata (origin &rest extra)
  (apply #'cadr-agent::mcp-obj
         "issuer" origin
         "authorization_endpoint" (format nil "~A/authorize" origin)
         "token_endpoint" (format nil "~A/token" origin)
         "registration_endpoint" (format nil "~A/register" origin)
         "response_types_supported" (vector "code")
         "grant_types_supported" (vector "authorization_code" "refresh_token")
         "token_endpoint_auth_methods_supported" (vector "none")
         "code_challenge_methods_supported" (vector "S256")
         extra))

(defun mcp-oauth-query-value (url name)
  (cadr-agent::mcp-oauth-query-get
   (cadr-agent::mcp-oauth-query-alist
    (string-left-trim '(#\?)
                      (getf (cadr-agent::mcp-oauth-parse-url url) :search)))
   name))

(test mcp-oauth-discovers-registers-pkce-and-refreshes
  ;; oauth.test.ts "discovers, registers, authorizes with PKCE, and refreshes on 401"
  (let* ((origin "http://127.0.0.1:9")
         (server (format nil "~A/mcp" origin))
         (refreshes 0)
         (registered nil)
         (challenge nil)
         (store (cadr-agent::make-mcp-oauth-memory-store))
         (authorization nil)
         (provider nil)
         (fetch
           (mcp-oauth-test-fetch
            (lambda (url method headers body)
              (declare (ignore headers))
              (let ((path (mcp-oauth-test-path url)))
                (cond
                  ((and (eq method :get)
                        (string= path "/.well-known/oauth-protected-resource/mcp"))
                   (mcp-oauth-response
                    200
                    (cadr-agent::mcp-obj
                     "resource" server
                     "authorization_servers" (vector origin)
                     "scopes_supported" (vector "org:read"))))
                  ((and (eq method :get)
                        (string= path "/.well-known/oauth-authorization-server"))
                   (mcp-oauth-response 200 (mcp-oauth-metadata origin)))
                  ((and (eq method :post) (string= path "/register"))
                   (setf registered (cadr-agent::mcp-read-json body))
                   (mcp-oauth-response
                    201
                    (cadr-agent::mcp-put
                     (cadr-agent::mcp-put registered "client_id" "test-client")
                     "client_secret" "")))
                  ((and (eq method :post) (string= path "/token"))
                   (let ((params (cadr-agent::mcp-oauth-query-alist body)))
                     (cond
                       ((string= (cadr-agent::mcp-oauth-query-get params "grant_type")
                                 "refresh_token")
                        (incf refreshes)
                        (mcp-oauth-response
                         200
                         (cadr-agent::mcp-obj
                          "access_token" "refreshed-token"
                          "token_type" "Bearer"
                          "refresh_token" ""
                          "expires_in" 'null)))
                       ((and (string= (cadr-agent::mcp-oauth-query-get params "code")
                                      "test-code")
                             (string= (cadr-ai:pkce-challenge
                                       (cadr-agent::mcp-oauth-query-get
                                        params "code_verifier"))
                                      challenge))
                        (mcp-oauth-response
                         200
                         (cadr-agent::mcp-obj
                          "access_token" "first-token"
                          "refresh_token" "refresh-token"
                          "token_type" "Bearer"
                          "scope" "")))
                       (t
                        (mcp-oauth-response
                         400
                         (cadr-agent::mcp-obj "error" "invalid_grant"))))))
                  (t (error "unexpected ~A ~A" method url))))))))
    (setf provider
          (cadr-agent::make-mcp-oauth-provider
           :server-url server
           :redirect-url "http://127.0.0.1:1234/callback"
           :store store
           :on-redirect (lambda (url) (setf authorization url))))
    (let ((auth (cadr-agent::mcp-oauth-adapt-provider provider)))
      (handler-case
          (funcall (cadr-agent::mcp-oauth-auth-unauthorized auth)
                   (list :server-url server
                         :headers (list (cons "www-authenticate"
                                              (format nil "Bearer resource_metadata=\"~A/.well-known/oauth-protected-resource/mcp\", scope=\"\""
                                                      origin)))
                         :token "caller-supplied-stale-token"
                         :fetch fetch))
        (cadr-agent::mcp-oauth-authorization-required-error ()))
      (is (string= "Cadr" (cadr-agent::mcp-get registered "client_name")))
      (is (string= "org:read" (mcp-oauth-query-value authorization "scope")))
      (is (string= server (mcp-oauth-query-value authorization "resource")))
      (is (string= "S256" (mcp-oauth-query-value authorization "code_challenge_method")))
      (setf challenge (mcp-oauth-query-value authorization "code_challenge"))
      (is (string= (cadr-agent::mcp-oauth-authorize
                    provider
                    :server-url server
                    :authorization-code "test-code"
                    :fetch fetch)
                   "AUTHORIZED"))
      (let ((tokens (cadr-agent::mcp-oauth-provider-tokens provider)))
        (is (string= "first-token" (cadr-agent::mcp-get tokens "access_token")))
        (is (string= "refresh-token" (cadr-agent::mcp-get tokens "refresh_token")))
        (is (string= "org:read" (cadr-agent::mcp-get tokens "scope")))
        (is (not (nth-value 1 (cadr-agent::mcp-get tokens "expires_in")))))
      (funcall (getf store :save)
               (cadr-agent::mcp-put
                (funcall (getf store :load))
                "tokens"
                (cadr-agent::mcp-put
                 (cadr-agent::mcp-oauth-provider-tokens provider)
                 "access_token" "stale-token")))
      (funcall (cadr-agent::mcp-oauth-auth-unauthorized auth)
               (list :server-url server
                     :headers (list (cons "www-authenticate" "Bearer"))
                     :token "stale-token"
                     :fetch fetch))
      (let ((tokens (cadr-agent::mcp-oauth-provider-tokens provider)))
        (is (string= "refreshed-token" (cadr-agent::mcp-get tokens "access_token")))
        (is (string= "refresh-token" (cadr-agent::mcp-get tokens "refresh_token")))
        (is (string= "Bearer" (cadr-agent::mcp-get tokens "token_type")))
        (is (string= "org:read" (cadr-agent::mcp-get tokens "scope")))
        (is (not (nth-value 1 (cadr-agent::mcp-get tokens "expires_in")))))
      (is (= 1 refreshes)))))

(test mcp-oauth-shares-one-rotating-refresh
  ;; oauth.test.ts "shares one refresh between concurrent 401s when refresh tokens rotate"
  (let* ((origin "http://127.0.0.1:9")
         (server (format nil "~A/mcp" origin))
         (grants nil)
         (store (cadr-agent::make-mcp-oauth-memory-store))
         (fetch
           (mcp-oauth-test-fetch
            (lambda (url method headers body)
              (declare (ignore headers))
              (unless (and (eq method :post)
                           (string= (mcp-oauth-test-path url) "/token"))
                (error "unexpected ~A ~A" method url))
              (let ((refresh (cadr-agent::mcp-oauth-query-get
                              (cadr-agent::mcp-oauth-query-alist body)
                              "refresh_token")))
                (push refresh grants)
                (if (string= refresh "r1")
                    (mcp-oauth-response
                     200
                     (cadr-agent::mcp-obj
                      "access_token" "a2"
                      "refresh_token" "r2"
                      "token_type" "Bearer"
                      "expires_in" 3600))
                    (mcp-oauth-response
                     400 (cadr-agent::mcp-obj "error" "invalid_grant"))))))))
    (funcall (getf store :save)
             (cadr-agent::mcp-obj
              "serverUrl" server
              "clientInformation" (cadr-agent::mcp-obj "client_id" "client")
              "tokens" (cadr-agent::mcp-obj
                        "access_token" "a1"
                        "refresh_token" "r1"
                        "token_type" "Bearer")
              "discovery"
              (cadr-agent::mcp-obj
               "authorizationServerUrl" origin
               "authorizationServerMetadata" (mcp-oauth-metadata origin))))
    (let* ((provider
             (cadr-agent::make-mcp-oauth-provider
              :server-url server
              :redirect-url "http://127.0.0.1/callback"
              :client-id "client"
              :store store
              :on-redirect (lambda (url) (declare (ignore url)) nil)))
           (auth (cadr-agent::mcp-oauth-adapt-provider provider))
           (call (lambda ()
                   (funcall (cadr-agent::mcp-oauth-auth-unauthorized auth)
                            (list :server-url server
                                  :headers (list (cons "www-authenticate" "Bearer"))
                                  :token "a1"
                                  :fetch fetch)))))
      (let ((first (sb-thread:make-thread call :name "mcp oauth refresh a"))
            (second (sb-thread:make-thread call :name "mcp oauth refresh b")))
        (sb-thread:join-thread first)
        (sb-thread:join-thread second))
      (funcall call)
      (is (equal '("r1") grants))
      (is (string= "a2" (funcall (cadr-agent::mcp-oauth-auth-token auth))))
      (is (string= "r2"
                   (cadr-agent::mcp-get
                    (cadr-agent::mcp-get (funcall (getf store :load)) "tokens")
                    "refresh_token")))
      (is (> (cadr-agent::mcp-get (funcall (getf store :load)) "tokensExpireAt")
             (+ (cadr-core:unix-milliseconds) 3500000))))))

(test mcp-oauth-insufficient-scope-keeps-the-grant
  ;; oauth.test.ts "asks for authorization instead of refreshing when the server needs more scope"
  ;; Agent createMcpAuthProvider throws before refresh so login can open the browser.
  (let* ((origin "http://127.0.0.1:9")
         (server (format nil "~A/mcp" origin))
         (token-posts 0)
         (authorization nil)
         (store (cadr-agent::make-mcp-oauth-memory-store))
         (fetch
           (mcp-oauth-test-fetch
            (lambda (url method headers body)
              (declare (ignore headers body))
              (cond
                ((and (eq method :post)
                      (string= (mcp-oauth-test-path url) "/token"))
                 (incf token-posts)
                 (mcp-oauth-response 500 "no"))
                ((string= (mcp-oauth-test-path url)
                          "/.well-known/oauth-authorization-server")
                 (mcp-oauth-response 200 (mcp-oauth-metadata origin)))
                (t (mcp-oauth-response 404 "")))))))
    (funcall (getf store :save)
             (cadr-agent::mcp-obj
              "serverUrl" server
              "clientInformation" (cadr-agent::mcp-obj "client_id" "client")
              "tokens" (cadr-agent::mcp-obj
                        "access_token" "a1"
                        "refresh_token" "r1"
                        "token_type" "Bearer"
                        "scope" "repo read:org")))
    (let* ((provider
             (cadr-agent::make-mcp-oauth-provider
              :server-url server
              :redirect-url "http://127.0.0.1/callback"
              :client-id "client"
              :store store
              :on-redirect (lambda (url) (setf authorization url))))
           (auth (cadr-agent::mcp-oauth-adapt-provider provider)))
      (handler-case
          (funcall (cadr-agent::mcp-oauth-auth-unauthorized auth)
                   (list :server-url server
                         :headers (list (cons "www-authenticate"
                                              "Bearer error=\"insufficient_scope\", scope=\"repo admin\""))
                         :token "a1"
                         :fetch fetch))
        (cadr-agent::mcp-oauth-authorization-required-error ()))
      (is (string= "repo read:org admin" (mcp-oauth-query-value authorization "scope")))
      (is (string= "a1"
                   (cadr-agent::mcp-get
                    (cadr-agent::mcp-oauth-provider-tokens provider)
                    "access_token")))
      (is (= 0 token-posts)))
    (let* ((view (cadr-agent::mcp-oauth-credential-server
                  (cadr-agent::make-mcp-oauth-credential-store nil)
                  "docs" server))
           (posts 0)
           (connection-auth nil))
      (funcall (getf view :save)
               (cadr-agent::mcp-obj
                "serverUrl" server
                "tokens" (cadr-agent::mcp-obj
                          "access_token" "a1"
                          "refresh_token" "r1"
                          "token_type" "Bearer"
                          "scope" "repo read:org")))
      (setf connection-auth
            (cadr-agent::mcp-oauth-create-auth
             server view
             (lambda () (cadr-agent::make-mcp-oauth-settings))
             (lambda (challenge) (declare (ignore challenge)) nil)))
      (handler-case
          (funcall (cadr-agent::mcp-oauth-auth-unauthorized connection-auth)
                   (list :server-url server
                         :headers (list (cons "www-authenticate"
                                              "Bearer error=\"insufficient_scope\", scope=\"admin\""))
                         :token "a1"
                         :fetch (lambda (&rest args)
                                  (declare (ignore args))
                                  (incf posts)
                                  (values 500 "" nil))))
        (cadr-agent::mcp-oauth-authorization-required-error ()))
      (is (= 0 posts))
      (is (string= "a1"
                   (cadr-agent::mcp-get
                    (cadr-agent::mcp-get (cadr-agent::mcp-oauth-store-load view) "tokens")
                    "access_token"))))))

(test mcp-oauth-credentials-follow-the-server-url-and-name
  ;; oauth.test.ts "binds persisted credentials to the exact MCP server URL"
  ;; store.test.ts separate accounts, hyphen/underscore names, legacy migration.
  (let ((store (cadr-agent::make-mcp-oauth-memory-store)))
    (let ((first (cadr-agent::make-mcp-oauth-provider
                  :server-url "https://one.example/mcp"
                  :redirect-url "http://127.0.0.1/callback"
                  :store store)))
      (cadr-agent::mcp-oauth-provider-save-tokens
       first
       (cadr-agent::mcp-obj "access_token" "secret" "token_type" "Bearer"))
      (is (string= "secret"
                   (cadr-agent::mcp-get
                    (cadr-agent::mcp-oauth-provider-tokens first)
                    "access_token"))))
    (let ((second (cadr-agent::make-mcp-oauth-provider
                   :server-url "https://two.example/mcp"
                   :redirect-url "http://127.0.0.1/callback"
                   :store store)))
      (is (null (cadr-agent::mcp-oauth-provider-tokens second)))))
  (let* ((path (merge-pathnames
                (format nil "cadr-mcp-oauth-~A.json" (random 1000000))
                (uiop:temporary-directory)))
         (credentials (cadr-agent::make-mcp-oauth-credential-store
                       (namestring path)))
         (alpha (cadr-agent::mcp-oauth-credential-server
                 credentials "alpha" "https://example.com/mcp"))
         (beta (cadr-agent::mcp-oauth-credential-server
                credentials "beta" "https://example.com/mcp"))
         (same (cadr-agent::mcp-oauth-credential-server
                credentials "my-server" "https://example.com/mcp")))
    (unwind-protect
         (progn
           (funcall (getf alpha :save)
                    (cadr-agent::mcp-obj
                     "tokens" (cadr-agent::mcp-obj "access_token" "alpha-token")))
           (funcall (getf beta :save)
                    (cadr-agent::mcp-obj
                     "tokens" (cadr-agent::mcp-obj "access_token" "beta-token")))
           (is (string= "alpha-token"
                        (cadr-agent::mcp-get (funcall (getf alpha :tokens))
                                             "access_token")))
           (is (string= "beta-token"
                        (cadr-agent::mcp-get (funcall (getf beta :tokens))
                                             "access_token")))
           (funcall (getf same :save)
                    (cadr-agent::mcp-obj
                     "tokens" (cadr-agent::mcp-obj "access_token" "shared")))
           (is (string= "shared"
                        (cadr-agent::mcp-get
                         (funcall
                          (getf (cadr-agent::mcp-oauth-credential-server
                                 credentials "my_server" "https://example.com/mcp")
                                :tokens))
                         "access_token")))
           (mcp-command-write-oauth-legacy path)
           (let ((docs (cadr-agent::mcp-oauth-credential-server
                        credentials "docs" "https://example.com/mcp")))
             (is (string= "legacy"
                          (cadr-agent::mcp-get (funcall (getf docs :tokens))
                                               "access_token")))
             (is (cadr-agent::mcp-get
                  (cadr-agent::mcp-read-json
                   (uiop:read-file-string path :external-format :utf-8))
                  "https://example.com/mcp"))
             (is (string= "legacy"
                          (cadr-agent::mcp-get
                           (cadr-agent::mcp-get (funcall (getf docs :load)) "tokens")
                           "access_token")))
             (is (not (nth-value 1
                                 (cadr-agent::mcp-get
                                  (cadr-agent::mcp-read-json
                                   (uiop:read-file-string path :external-format :utf-8))
                                  "https://example.com/mcp"))))
             (is (funcall (getf docs :remove)))
             (is (null (funcall (getf docs :tokens))))))
      (ignore-errors (delete-file path)))))

(defun mcp-command-write-oauth-legacy (path)
  (with-open-file (out path :direction :output :if-exists :supersede
                            :if-does-not-exist :create
                            :external-format :utf-8)
    (write-string
     "{\"https://example.com/mcp\":{\"tokens\":{\"access_token\":\"legacy\",\"token_type\":\"Bearer\"}}}
"
     out)))

(test mcp-oauth-application-type-follows-the-redirect
  ;; oauth.test.ts "registers with an application_type derived from the redirect URIs"
  (let* ((types nil)
         (fetch
           (mcp-oauth-test-fetch
            (lambda (url method headers body)
             (declare (ignore url method headers))
             (let ((metadata (cadr-agent::mcp-read-json body)))
               (push (cadr-agent::mcp-get metadata "application_type") types)
               (mcp-oauth-response
                201
                (cadr-agent::mcp-put metadata "client_id" "client")))))))
    (dolist (spec '(("http://127.0.0.1:1234/callback")
                    ("http://[::1]/callback")
                    ("com.example.app:/callback")
                    ("https://app.example/callback")
                    ("http://localhost/callback" "web")))
      (cadr-agent::mcp-oauth-register-client
       "http://127.0.0.1:9"
       :client-metadata
       (apply #'cadr-agent::mcp-obj
              "redirect_uris" (vector (first spec))
              (when (second spec)
                (list "application_type" (second spec))))
       :fetch fetch))
    (is (equal '("native" "native" "native" "web" "web") (nreverse types)))))

(test mcp-oauth-rejects-issuer-mismatch-and-insecure-metadata
  (let ((fetch
          (mcp-oauth-test-fetch
           (lambda (url method headers body)
             (declare (ignore method headers body))
             (if (string= (mcp-oauth-test-path url)
                          "/.well-known/oauth-authorization-server")
                 (mcp-oauth-response
                  200
                  (mcp-oauth-metadata "https://attacker.example"))
                 (mcp-oauth-response 404 ""))))))
    (handler-case
        (cadr-agent::mcp-oauth-discover-authorization-metadata
         "http://127.0.0.1:9" :fetch fetch)
      (cadr-agent::mcp-oauth-issuer-mismatch-error (condition)
        (is (string= "OAuth issuer mismatch: expected \"http://127.0.0.1:9\", received \"https://attacker.example\""
                     (princ-to-string condition))))))
  (handler-case
      (cadr-agent::mcp-oauth-authorize
       (cadr-agent::make-mcp-oauth-provider
        :server-url "http://127.0.0.1:9/mcp"
        :redirect-url "http://127.0.0.1/callback")
       :server-url "http://127.0.0.1:9/mcp"
       :authorization-server-metadata-url
       "http://example.com/.well-known/oauth-authorization-server"
       :fetch (lambda (&rest args)
                (declare (ignore args))
                (error "metadata must be refused before the request")))
    (cadr-agent::mcp-oauth-insecure-endpoint-error (condition)
      (is (string= "Refusing to send OAuth credentials to non-HTTPS endpoint http://example.com/.well-known/oauth-authorization-server"
                   (princ-to-string condition))))))

(test mcp-oauth-abort-does-not-fall-through-to-redirect
  (let* ((redirected nil)
         (provider
           (cadr-agent::make-mcp-oauth-provider
           :server-url "http://127.0.0.1:9/mcp"
           :redirect-url "http://127.0.0.1/callback"
           :on-redirect (lambda (url)
                          (declare (ignore url))
                          (setf redirected t)))))
    (handler-case
        (cadr-agent::mcp-oauth-authorize
         provider
         :server-url "http://127.0.0.1:9/mcp"
         :signal (lambda () t)
         :fetch (lambda (&rest args)
                  (declare (ignore args))
                  (error "aborted discovery must not fetch")))
      (cadr-agent::mcp-oauth-abort-error ()
        (is (null redirected))))))

(test mcp-oauth-callback-is-plain-text-and-rejects-another-path
  (let ((server (cadr-agent::mcp-oauth-callback-listen
                 :extra-paths '("/callback/other")
                 :timeout-ms 3000)))
    (unwind-protect
         (let ((redirect (cadr-agent::mcp-oauth-callback-redirect-url server)))
           (let ((body nil)
                 (content-type nil))
             (sb-thread:make-thread
              (lambda ()
                (sleep 0.1)
                (multiple-value-bind (payload status headers)
                    (cadr-ai::native-http-request
                     (format nil "~A?code=abc&state=s1" redirect)
                     :force-string t)
                  (declare (ignore status))
                  (setf body payload
                        content-type (cadr-ai::header-value headers "content-type"))))
              :name "mcp oauth callback hit")
             (let ((result (cadr-agent::mcp-oauth-callback-wait
                            server "s1" "/callback")))
               (is (string= "abc" (getf result :code))))
             (is (mcp-oauth-test-wait (lambda () body)))
             (is (string= "Authorization complete. You may close this window." body))
             (is (string= "text/plain; charset=utf-8" content-type)))
           (let ((failed nil))
             (sb-thread:make-thread
              (lambda ()
                (sleep 0.1)
                (cadr-ai::native-http-request
                 (format nil "~A/other?code=z&state=s2" redirect)
                 :force-string t))
              :name "mcp oauth wrong path")
             (handler-case
                 (cadr-agent::mcp-oauth-callback-wait server "s2" "/callback")
               (error (condition)
                 (setf failed (princ-to-string condition))))
             (is (string= "The authorization response arrived on another redirect URI"
                          failed))))
      (cadr-agent::mcp-oauth-callback-close server))))

(defun mcp-oauth-test-wait (predicate)
  (loop for step from 0 below 200
        when (funcall predicate)
          return t
        do (sleep 0.01)))

(test mcp-oauth-cimd-uses-the-hosted-client-document
  ;; refresh.test.ts CIMD: iss-capable servers use the shared client document
  ;; and the callback path; others bind the client id to the redirect path.
  (let* ((origin "http://127.0.0.1:9")
         (server (format nil "~A/mcp" origin))
         (registered nil)
         (authorization nil)
         (fetch
           (mcp-oauth-test-fetch
            (lambda (url method headers body)
              (declare (ignore headers body))
              (let ((path (mcp-oauth-test-path url)))
                (cond
                  ((and (eq method :post) (string= path "/register"))
                   (setf registered t)
                   (mcp-oauth-response 500 "registered"))
                  ((string= path "/.well-known/oauth-protected-resource/mcp")
                   (mcp-oauth-response
                    200
                    (cadr-agent::mcp-obj
                     "resource" server
                     "authorization_servers" (vector origin))))
                  ((string= path "/.well-known/oauth-authorization-server")
                   (mcp-oauth-response
                    200
                    (cadr-agent::mcp-put
                     (cadr-agent::mcp-put
                      (mcp-oauth-metadata origin)
                      "client_id_metadata_document_supported" t)
                     "authorization_response_iss_parameter_supported" t)))
                  (t (mcp-oauth-response 404 "")))))))
         (provider
           (cadr-agent::make-mcp-oauth-provider
            :server-url server
            :redirect-url "http://127.0.0.1:1234/callback"
            :client-metadata-document
            (lambda (metadata)
              (cadr-agent::mcp-oauth-client-document
               server "http://127.0.0.1:1234/callback" metadata))
            :on-redirect (lambda (url) (setf authorization url)))))
    (is (string= "REDIRECT"
                 (cadr-agent::mcp-oauth-authorize
                  provider :server-url server :fetch fetch)))
    (is (null registered))
    (is (string= "https://pi.dev/oauth/client.json"
                 (mcp-oauth-query-value authorization "client_id")))
    (is (string= "http://127.0.0.1:1234/callback"
                 (mcp-oauth-query-value authorization "redirect_uri"))))
  (handler-case
      (cadr-agent::mcp-oauth-client-document
       "http://127.0.0.1:9/mcp"
       "http://127.0.0.1/callback"
       (cadr-agent::mcp-obj "issuer" "http://127.0.0.1:9"))
    (error (condition)
      (is (string= "The authorization server does not support Client ID Metadata Documents for public clients; remove oauth.clientRegistration \"cimd\""
                   (princ-to-string condition))))))
