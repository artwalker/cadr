(in-package #:cadr-ai/tests)
(in-suite cadr-ai-suite)

;;; pi@4a080252f packages/ai/test/openai-chatgpt-oauth.test.ts
;;; packages/ai/test/openai-responses-chatgpt-sign-in.test.ts
;;; packages/ai/src/auth/oauth/openai-chatgpt.ts
;;; The product name in agent_name_hint is Cadr, the same substitution
;;; the Codex originator already uses for "pi".

(defparameter +chatgpt-test-device-id+
  "e61bbe28-07ef-466d-8e5d-a344f94ab305")
(defparameter +chatgpt-test-scope+
  "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct")
(defparameter +chatgpt-test-token-url+
  "https://auth.openai.com/api/accounts/oauth/token")

(defun chatgpt-test-scope-list ()
  (uiop:split-string +chatgpt-test-scope+ :separator '(#\Space)))

(defun chatgpt-test-token (&key (access "access-token")
                             (refresh "refresh-token")
                             (expires-in 3600)
                             (id-token "id-token")
                             (scope +chatgpt-test-scope+)
                             (include-refresh t)
                             (include-id-token t))
  (let ((object
          (cadr-ai::json-object
           "access_token" access
           "expires_in" expires-in
           "scope" scope)))
    (when include-refresh
      (cadr-ai::json-put object "refresh_token" refresh))
    (when include-id-token
      (cadr-ai::json-put object "id_token" id-token))
    object))

(defun chatgpt-test-query (url name)
  (let ((start (position #\? url)))
    (gethash name
             (cadr-ai::parse-query
              (if start (subseq url (1+ start)) "")))))

(defun chatgpt-test-error (thunk)
  (handler-case
      (progn (funcall thunk) nil)
    (cadr-ai:authentication-error (condition)
      (cadr-ai:cadr-error-message condition))))

(defun chatgpt-test-callback (query)
  (let ((socket nil)
        (body nil))
    (unwind-protect
         (progn
           (loop repeat 20
                 do (setf socket
                          (make-instance 'sb-bsd-sockets:inet-socket
                                         :type :stream :protocol :tcp))
                    (handler-case
                        (progn
                          (sb-bsd-sockets:socket-connect
                           socket #(127 0 0 1) 1455)
                          (return))
                      (error ()
                        (ignore-errors
                         (sb-bsd-sockets:socket-close socket))
                        (setf socket nil)
                        (sleep 0.02))))
           (when socket
             (let ((stream
                     (sb-bsd-sockets:socket-make-stream
                      socket :input t :output t
                      :element-type 'character
                      :external-format :utf-8
                      :buffering :none)))
               (format stream
                       "GET /auth/callback?~A HTTP/1.1~C~CHost: 127.0.0.1:1455~C~CConnection: close~C~C~C~C"
                       query
                       #\Return #\Linefeed
                       #\Return #\Linefeed
                       #\Return #\Linefeed
                       #\Return #\Linefeed)
               (finish-output stream)
               (setf body
                     (with-output-to-string (collected)
                       (loop for line = (read-line stream nil nil)
                             while line
                             do (write-line line collected)))))))
      (when socket
        (ignore-errors (sb-bsd-sockets:socket-close socket))))
    body))

(defun chatgpt-paste-prompt (client-id)
  (lambda (prompt)
    (concatenate
     'string
     "http://127.0.0.1:1455/auth/callback?code=authorization-code&state="
     (chatgpt-test-query (getf prompt :url) "state")
     (if client-id (format nil "&client_id=~A" client-id) ""))))

(test openai-chatgpt-login-stores-the-issued-client-and-scopes
  (let ((events nil)
        (calls nil)
        (opened nil))
    (let ((cadr-ai::*oauth-login-device-id* +chatgpt-test-device-id+)
          (cadr-ai::*oauth-login-agent-name* nil)
          (cadr-ai::*oauth-browser-open-function*
            (lambda (url) (push url opened)))
          (cadr-ai::*oauth-flow-request-function*
            (lambda (url &key method headers content &allow-other-keys)
              (declare (ignore headers))
              (push (list :url url :method method :content content) calls)
              (values (chatgpt-test-token) 200))))
      (let* ((interaction
               (cadr-ai:make-runtime-auth-interaction
                :prompt-function (chatgpt-paste-prompt "oaiapp_issued")
                :notify-function
                (lambda (event) (push event events))))
             (credential
               (cadr-ai::login-openai-chatgpt-oauth interaction))
             (authorize
               (getf (find :auth-url events :key (lambda (event)
                                                   (getf event :type)))
                     :url))
             (exchange (cadr-ai::parse-query (getf (first calls) :content))))
        (is (string= "dynamic_agent_client"
                     (chatgpt-test-query authorize "client_id")))
        (is (string= "Cadr"
                     (chatgpt-test-query authorize "agent_name_hint")))
        (is (string= (format nil "urn:uuid:~A" +chatgpt-test-device-id+)
                     (chatgpt-test-query authorize "ext_agent_host_id")))
        (is (string= +chatgpt-test-scope+
                     (chatgpt-test-query authorize "scope")))
        (is (string= "http://127.0.0.1:1455/auth/callback"
                     (chatgpt-test-query authorize "redirect_uri")))
        (is (string= "https://api.openai.com/v1"
                     (chatgpt-test-query authorize "resource")))
        (is (string= "S256"
                     (chatgpt-test-query authorize "code_challenge_method")))
        (is (string= "code"
                     (chatgpt-test-query authorize "response_type")))
        (is (plusp (length (chatgpt-test-query authorize "nonce"))))
        (is (string= (cadr-ai:pkce-challenge
                      (gethash "code_verifier" exchange))
                     (chatgpt-test-query authorize "code_challenge")))
        (is (string= +chatgpt-test-token-url+ (getf (first calls) :url)))
        (is (string= "oaiapp_issued" (gethash "client_id" exchange)))
        (is (string= "authorization-code" (gethash "code" exchange)))
        (is (string= "https://api.openai.com/v1"
                     (gethash "resource" exchange)))
        (is (string= "authorization_code" (gethash "grant_type" exchange)))
        (is (string= "http://127.0.0.1:1455/auth/callback"
                     (gethash "redirect_uri" exchange)))
        (is (plusp (length (gethash "code_verifier" exchange))))
        (is (eq :openai (cadr-ai:oauth-credential-provider credential)))
        (is (string= "access-token"
                     (cadr-ai:oauth-credential-access credential)))
        (is (string= "refresh-token"
                     (cadr-ai:oauth-credential-refresh credential)))
        (is (string= "oaiapp_issued"
                     (cdr (assoc "clientId"
                                 (cadr-ai:oauth-credential-metadata credential)
                                 :test #'string=))))
        (is (equal (chatgpt-test-scope-list)
                   (cdr (assoc "scopes"
                               (cadr-ai:oauth-credential-metadata credential)
                               :test #'string=))))
        (is (search
             "Complete sign-in in your browser. If the callback does not complete, paste the final redirect URL here."
             (getf (find :auth-url events
                         :key (lambda (event) (getf event :type)))
                   :instructions)))
        (is (find "Exchanging authorization code for tokens..."
                  events
                  :key (lambda (event) (getf event :message))
                  :test #'string=))
        (is (string= (first opened) authorize))))))

(test openai-chatgpt-login-uses-the-caller-agent-name
  (let ((events nil)
        (calls nil))
    (let ((cadr-ai::*oauth-login-device-id* +chatgpt-test-device-id+)
          (cadr-ai::*oauth-login-agent-name* "my-app")
          (cadr-ai::*oauth-browser-open-function*
            (lambda (url) (declare (ignore url))))
          (cadr-ai::*oauth-flow-request-function*
            (lambda (url &key method headers content &allow-other-keys)
              (declare (ignore url method headers content))
              (push t calls)
              (values (chatgpt-test-token) 200))))
      (cadr-ai::login-openai-chatgpt-oauth
       (cadr-ai:make-runtime-auth-interaction
        :prompt-function (chatgpt-paste-prompt "oaiapp_issued")
        :notify-function (lambda (event) (push event events))))
      (is (string= "my-app"
                   (chatgpt-test-query
                    (getf (find :auth-url events
                                :key (lambda (event) (getf event :type)))
                          :url)
                    "agent_name_hint"))))))

(test openai-chatgpt-login-rejects-a-callback-without-an-issued-client-id
  (let ((calls nil))
    (let ((cadr-ai::*oauth-login-device-id* +chatgpt-test-device-id+)
          (cadr-ai::*oauth-browser-open-function*
            (lambda (url) (declare (ignore url))))
          (cadr-ai::*oauth-flow-request-function*
            (lambda (&rest args)
              (declare (ignore args))
              (push t calls)
              (values (chatgpt-test-token) 200))))
      (is (search
           "registration callback did not contain an issued client ID"
           (chatgpt-test-error
            (lambda ()
              (cadr-ai::login-openai-chatgpt-oauth
               (cadr-ai:make-runtime-auth-interaction
                :prompt-function (chatgpt-paste-prompt nil)))))))
      (is (null calls)))))

(test openai-chatgpt-login-rejects-a-grant-without-direct-token-use
  (let ((cadr-ai::*oauth-login-device-id* +chatgpt-test-device-id+)
        (cadr-ai::*oauth-browser-open-function*
          (lambda (url) (declare (ignore url))))
        (cadr-ai::*oauth-flow-request-function*
          (lambda (&rest args)
            (declare (ignore args))
            (values
             (chatgpt-test-token
              :scope "openid profile email offline_access resource.invoke")
             200))))
    (is (search
         "grant did not include chatgpt.tokens.use.direct"
         (chatgpt-test-error
          (lambda ()
            (cadr-ai::login-openai-chatgpt-oauth
             (cadr-ai:make-runtime-auth-interaction
              :prompt-function (chatgpt-paste-prompt "oaiapp_issued")))))))))

(test openai-chatgpt-login-requires-a-device-id-before-authorization
  (let ((started nil))
    (let ((cadr-ai::*oauth-browser-open-function*
            (lambda (url) (declare (ignore url))))
          (cadr-ai::*oauth-flow-request-function*
            (lambda (&rest args)
              (declare (ignore args))
              (error "token endpoint must not be called"))))
      (flet ((login ()
               (cadr-ai::login-openai-chatgpt-oauth
                (cadr-ai:make-runtime-auth-interaction
                 :notify-function
                 (lambda (event) (declare (ignore event)) (setf started t))
                 :prompt-function
                 (lambda (prompt)
                   (declare (ignore prompt))
                   (error "prompt must not run"))))))
        (let ((cadr-ai::*oauth-login-device-id* nil))
          (is (search "requires a device ID" (chatgpt-test-error #'login))))
        (let ((cadr-ai::*oauth-login-device-id* "not-a-uuid"))
          (is (search "requires a device ID" (chatgpt-test-error #'login)))))
      (is (null started)))))

(test openai-chatgpt-refresh-requires-a-new-refresh-token
  (let ((cadr-ai::*oauth-flow-request-function*
          (lambda (&rest args)
            (declare (ignore args))
            (values (chatgpt-test-token :include-refresh nil) 200))))
    (is (search
         "token response has invalid refresh_token"
         (chatgpt-test-error
          (lambda ()
            (cadr-ai::refresh-openai-chatgpt-oauth-credential
             (cadr-ai:make-oauth-credential
              :provider :openai
              :access "old-access"
              :refresh "old-refresh"
              :expires 0
              :metadata '(("clientId" . "oaiapp_existing"))))))))))

(test openai-chatgpt-refresh-uses-the-issued-client-id
  (let ((calls nil)
        (before (cadr-ai::unix-milliseconds)))
    (let ((cadr-ai::*oauth-flow-request-function*
            (lambda (url &key method headers content &allow-other-keys)
              (declare (ignore headers))
              (push (list :url url :method method :content content) calls)
              (values
               (chatgpt-test-token
                :access "new-access"
                :refresh "new-refresh"
                :include-id-token nil)
               200))))
      (let ((credential
              (cadr-ai::refresh-openai-chatgpt-oauth-credential
               (cadr-ai:make-oauth-credential
                :provider :openai
                :access "old-access"
                :refresh "old-refresh"
                :expires 0
                :metadata '(("clientId" . "oaiapp_existing")))))
            (after (cadr-ai::unix-milliseconds))
            (body (cadr-ai::parse-query (getf (first calls) :content))))
        (is (>= (cadr-ai:oauth-credential-expires credential)
                (+ before (* (- 3600 180) 1000))))
        (is (<= (cadr-ai:oauth-credential-expires credential)
                (+ after (* (- 3600 180) 1000))))
        (is (string= "refresh_token" (gethash "grant_type" body)))
        (is (string= "oaiapp_existing" (gethash "client_id" body)))
        (is (string= "old-refresh" (gethash "refresh_token" body)))
        (is (string= "https://api.openai.com/v1" (gethash "resource" body)))
        (is (null (gethash "scope" body)))
        (is (string= "new-access"
                     (cadr-ai:oauth-credential-access credential)))
        (is (string= "new-refresh"
                     (cadr-ai:oauth-credential-refresh credential)))
        (is (string= "oaiapp_existing"
                     (cdr (assoc "clientId"
                                 (cadr-ai:oauth-credential-metadata credential)
                                 :test #'string=))))
        (is (equal (chatgpt-test-scope-list)
                   (cdr (assoc "scopes"
                               (cadr-ai:oauth-credential-metadata credential)
                               :test #'string=))))))))

(test openai-chatgpt-login-rejects-a-token-response-without-an-id-token
  (let ((cadr-ai::*oauth-login-device-id* +chatgpt-test-device-id+)
        (cadr-ai::*oauth-browser-open-function*
          (lambda (url) (declare (ignore url))))
        (cadr-ai::*oauth-flow-request-function*
          (lambda (&rest args)
            (declare (ignore args))
            (values (chatgpt-test-token :include-id-token nil) 200))))
    (is (search
         "did not contain an ID token"
         (chatgpt-test-error
          (lambda ()
            (cadr-ai::login-openai-chatgpt-oauth
             (cadr-ai:make-runtime-auth-interaction
              :prompt-function (chatgpt-paste-prompt "oaiapp_issued")))))))))

(test openai-chatgpt-token-errors-match-the-upstream-messages
  (let ((cadr-ai::*oauth-flow-request-function*
          (lambda (&rest args)
            (declare (ignore args))
            (values "nope" 200))))
    (is (search
         "OpenAI OAuth token response must be an object"
         (chatgpt-test-error
          (lambda ()
            (cadr-ai::refresh-openai-chatgpt-oauth-credential
             (cadr-ai:make-oauth-credential
              :provider :openai :access "a" :refresh "b" :expires 0
              :metadata '(("clientId" . "oaiapp_existing")))))))))
  (let ((cadr-ai::*oauth-flow-request-function*
          (lambda (&rest args)
            (declare (ignore args))
            (values "denied" 401))))
    (is (string=
         "OpenAI OAuth token request failed (401): denied"
         (chatgpt-test-error
          (lambda ()
            (cadr-ai::refresh-openai-chatgpt-oauth-credential
             (cadr-ai:make-oauth-credential
              :provider :openai :access "a" :refresh "b" :expires 0
              :metadata '(("clientId" . "oaiapp_existing")))))))))
  (let ((cadr-ai::*oauth-flow-request-function*
          (lambda (&rest args)
            (declare (ignore args))
            (values (chatgpt-test-token :expires-in "3600") 200))))
    (is (search
         "invalid expires_in"
         (chatgpt-test-error
          (lambda ()
            (cadr-ai::refresh-openai-chatgpt-oauth-credential
             (cadr-ai:make-oauth-credential
              :provider :openai :access "a" :refresh "b" :expires 0
              :metadata '(("clientId" . "oaiapp_existing")))))))))
  (is (search
       "does not contain an issued client ID"
       (chatgpt-test-error
        (lambda ()
          (cadr-ai::refresh-openai-chatgpt-oauth-credential
           (cadr-ai:make-oauth-credential
            :provider :openai :access "a" :refresh "b" :expires 0)))))))

(test openai-chatgpt-manual-callback-errors-match-the-upstream-messages
  (let ((cadr-ai::*oauth-login-device-id* +chatgpt-test-device-id+)
        (cadr-ai::*oauth-browser-open-function*
          (lambda (url) (declare (ignore url))))
        (cadr-ai::*oauth-flow-request-function*
          (lambda (&rest args)
            (declare (ignore args))
            (error "token endpoint must not be called"))))
    (flet ((login (prompt)
             (chatgpt-test-error
              (lambda ()
                (cadr-ai::login-openai-chatgpt-oauth
                 (cadr-ai:make-runtime-auth-interaction
                  :prompt-function prompt))))))
      (is (search "Paste the full callback URL from the browser"
                  (login (lambda (prompt) (declare (ignore prompt)) "not a url"))))
      (is (search
           "must start with http://127.0.0.1:1455/auth/callback"
           (login (lambda (prompt)
                    (declare (ignore prompt))
                    "http://127.0.0.1:1456/auth/callback?code=a&state=b&client_id=c"))))
      (is (search
           "OAuth state mismatch"
           (login (lambda (prompt)
                    (declare (ignore prompt))
                    "http://127.0.0.1:1455/auth/callback?code=a&state=wrong&client_id=c"))))
      (is (search
           "ChatGPT authorization failed: access_denied"
           (login
            (lambda (prompt)
              (format nil
                      "http://127.0.0.1:1455/auth/callback?error=access_denied&state=~A"
                      (chatgpt-test-query (getf prompt :url) "state")))))))))

(test openai-chatgpt-browser-callback-completes-login
  (let ((page nil)
        (cadr-ai::*oauth-login-device-id* +chatgpt-test-device-id+)
        (cadr-ai::*oauth-browser-open-function*
          (lambda (url) (declare (ignore url))))
        (cadr-ai::*oauth-flow-request-function*
          (lambda (&rest args)
            (declare (ignore args))
            (values (chatgpt-test-token) 200))))
    (let ((credential
            (cadr-ai::login-openai-chatgpt-oauth
             (cadr-ai:make-runtime-auth-interaction
              :prompt-function
              (lambda (prompt)
                (setf page
                      (chatgpt-test-callback
                       (format nil
                               "code=authorization-code&state=~A&client_id=oaiapp_issued"
                               (chatgpt-test-query (getf prompt :url) "state"))))
                (loop until (funcall (getf prompt :cancelled-p-function))
                      do (sleep 0.01))
                nil)))))
      (is (search
           "ChatGPT authentication completed. You can close this window."
           page))
      (is (string= "oaiapp_issued"
                   (cdr (assoc "clientId"
                               (cadr-ai:oauth-credential-metadata credential)
                               :test #'string=)))))))

(test openai-chatgpt-browser-error-rejects-login
  (let ((page nil)
        (cadr-ai::*oauth-login-device-id* +chatgpt-test-device-id+)
        (cadr-ai::*oauth-browser-open-function*
          (lambda (url) (declare (ignore url))))
        (cadr-ai::*oauth-flow-request-function*
          (lambda (&rest args)
            (declare (ignore args))
            (error "token endpoint must not be called"))))
    (is (search
         "ChatGPT authorization failed: access_denied"
         (chatgpt-test-error
          (lambda ()
            (cadr-ai::login-openai-chatgpt-oauth
             (cadr-ai:make-runtime-auth-interaction
              :prompt-function
              (lambda (prompt)
                (setf page
                      (chatgpt-test-callback "error=access_denied"))
                (loop until (funcall (getf prompt :cancelled-p-function))
                      do (sleep 0.01))
                nil)))))))
    (is (search "ChatGPT was not connected." page))
    (is (search "Error: access_denied" page))))

(test openai-chatgpt-login-fails-when-the-callback-port-is-taken
  (let ((socket (cadr-ai::open-oauth-callback-socket 1455)))
    (unwind-protect
         (let ((cadr-ai::*oauth-login-device-id* +chatgpt-test-device-id+)
               (cadr-ai::*oauth-browser-open-function*
                 (lambda (url) (declare (ignore url)))))
           (is (search
                "Port 1455 is in use"
                (chatgpt-test-error
                 (lambda ()
                   (cadr-ai::login-openai-chatgpt-oauth
                    (cadr-ai:make-runtime-auth-interaction
                     :prompt-function
                     (lambda (prompt)
                       (declare (ignore prompt))
                       (error "prompt must not run")))))))))
      (ignore-errors (sb-bsd-sockets:socket-close socket)))))

(defun chatgpt-sign-in-model (&key (base-url "https://api.openai.com/v1")
                                compat)
  (make-model
   :id "gpt-5-mini"
   :name "GPT-5 Mini"
   :api :openai-responses
   :provider :openai
   :base-url base-url
   :reasoning-p t
   :max-tokens 128000
   :context-window 400000
   :compat compat))

(defun chatgpt-sign-in-context ()
  (make-context
   :system-prompt ""
   :messages (list (make-user-message :content "hi" :timestamp 0))))

(defun chatgpt-sign-in-payload (api-key &key model oauth-p)
  (request-spec-payload
   (build-request
    (if oauth-p
        (make-openai-provider :oauth-access-token api-key)
        (make-openai-provider :api-key api-key))
    (or model (chatgpt-sign-in-model))
    (chatgpt-sign-in-context)
    :stream-p t
    :max-tokens 1000
    :temperature 0.5
    :cache-retention :long)))

(test openai-chatgpt-sign-in-omits-fields-token-sharing-rejects
  (let* ((model (chatgpt-sign-in-model))
         (payload (chatgpt-sign-in-payload "chatgpt-access-token" :model model))
         (oauth-request
           (build-request
            (make-openai-provider :oauth-access-token "chatgpt-access-token")
            model
            (chatgpt-sign-in-context)
            :stream-p t
            :max-tokens 1000
            :temperature 0.5
            :cache-retention :long
            :session-id "session-chatgpt"))
         (oauth-payload (request-spec-payload oauth-request))
         (headers (request-spec-headers oauth-request)))
    (is (not (cadr-ai::json-present-p payload "max_output_tokens")))
    (is (not (cadr-ai::json-present-p payload "temperature")))
    (is (not (cadr-ai::json-present-p payload "prompt_cache_retention")))
    (is (string= "https://api.openai.com/v1/responses"
                 (request-spec-url oauth-request)))
    (is (string= "Bearer chatgpt-access-token"
                 (cdr (assoc "authorization" headers :test #'string-equal))))
    (is (null (assoc "chatgpt-account-id" headers :test #'string-equal)))
    (is (null (assoc "originator" headers :test #'string-equal)))
    (is (null (assoc "openai-beta" headers :test #'string-equal)))
    (is (not (cadr-ai::json-present-p oauth-payload "max_output_tokens")))
    (is (not (cadr-ai::json-present-p oauth-payload "temperature")))
    (is (not (cadr-ai::json-present-p oauth-payload "prompt_cache_retention")))
    (is (not (cadr-ai::json-present-p oauth-payload "prompt_cache_options")))
    (is (cadr-ai::json-present-p oauth-payload "prompt_cache_key"))))

(test openai-chatgpt-sign-in-omits-explicit-prompt-cache-options
  (let ((model
          (chatgpt-sign-in-model
           :compat '(:supports-explicit-prompt-cache-mode t))))
    (is (not (cadr-ai::json-present-p
              (chatgpt-sign-in-payload "chatgpt-access-token" :model model)
              "prompt_cache_options")))
    (is (equalp
         (cadr-ai::json-object "ttl" "30m")
         (cadr-ai::json-get
          (chatgpt-sign-in-payload "sk-proj-test" :model model)
          "prompt_cache_options")))))

(test openai-chatgpt-api-keys-and-other-endpoints-keep-request-fields
  (let ((official (chatgpt-sign-in-payload "sk-proj-test"))
        (gateway
          (chatgpt-sign-in-payload
           "gateway-key"
           :model (chatgpt-sign-in-model
                   :base-url "https://gateway.example.com/v1"))))
    (dolist (payload (list official gateway))
      (is (= 1000 (cadr-ai::json-get payload "max_output_tokens")))
      (is (= 0.5 (cadr-ai::json-get payload "temperature")))
      (is (string= "24h"
                   (cadr-ai::json-get payload "prompt_cache_retention"))))))

(test openai-codex-oauth-still-sends-the-account-header
  (let* ((request
           (build-request
            (make-openai-codex-provider
             :oauth-access-token "oauth-test"
             :oauth-account-id "acct-test")
            (make-model
             :id "gpt-5.5"
             :provider :openai-codex
             :api :openai-codex-responses
             :base-url "https://chatgpt.com/backend-api")
            (chatgpt-sign-in-context)
            :stream-p t
            :max-tokens 1000))
         (headers (request-spec-headers request)))
    (is (search "/codex/responses" (request-spec-url request)))
    (is (string= "acct-test"
                 (cdr (assoc "chatgpt-account-id" headers
                             :test #'string-equal))))))

(test openai-oauth-hides-classifier-models-and-keeps-the-chat-model
  (let* ((store (cadr-ai:make-memory-credential-store))
         (runtime
           (cadr-ai:make-built-in-models-runtime
            :credential-store store
            :environment '(("OPENAI_API_KEY" . ""))))
         (catalog (cadr-ai:list-classifier-models :openai)))
    (is (find "gpt-6-luna" catalog
              :key #'cadr-ai:classifier-model-id :test #'string=))
    (let ((luna (find "gpt-6-luna" catalog
                      :key #'cadr-ai:classifier-model-id :test #'string=)))
      (is (eq :openai-decisions (cadr-ai:classifier-model-api luna)))
      (is (equal '(:text :image) (cadr-ai:classifier-model-input luna)))
      (is (= 922000 (cadr-ai:classifier-model-context-window luna))))
    (is (null (cadr-ai::models-runtime-available-classifiers runtime :openai)))
    (cadr-ai:credential-store-modify
     store :openai
     (lambda (old)
       (declare (ignore old))
       (cadr-ai:make-api-key-credential :provider :openai :key "sk-test")))
    (is (find "gpt-6-luna"
              (cadr-ai::models-runtime-available-classifiers runtime :openai)
              :key #'cadr-ai:classifier-model-id :test #'string=))
    (cadr-ai:credential-store-modify
     store :openai
     (lambda (old)
       (declare (ignore old))
       (cadr-ai:make-oauth-credential
        :provider :openai :access "chatgpt-access-token"
        :refresh "refresh" :expires 9999999999999
        :metadata '(("clientId" . "oaiapp_issued")))))
    (is (null (cadr-ai::models-runtime-available-classifiers runtime :openai)))
    (is (find "gpt-6-luna"
              (cadr-ai:models-runtime-available-models runtime :openai)
              :key #'cadr-ai:model-id :test #'string=))))

(test openai-provider-offers-chatgpt-subscription-login
  (let ((definition (cadr-ai:find-provider-definition :openai))
        (metadata cadr-ai::+openai-chatgpt-oauth-metadata+))
    (is (equal '(:api-key :oauth)
               (cadr-ai:provider-definition-auth-types definition)))
    (is (cadr-ai:provider-oauth-subscription-p :openai))
    (is (string= "Sign in with ChatGPT"
                 (cadr-ai::oauth-provider-metadata-login-label metadata)))
    (is (string= "OpenAI (ChatGPT subscription)"
                 (cadr-ai::oauth-provider-metadata-method-name metadata)))))
