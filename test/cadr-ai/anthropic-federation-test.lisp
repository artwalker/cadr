(in-package #:cadr-ai/tests)

(in-suite cadr-ai-suite)

;;; pi@4a080252f packages/ai/test/anthropic-federation.test.ts
;;; packages/ai/test/anthropic-federation-sdk.test.ts
;;; packages/ai/src/providers/anthropic.ts anthropicApiKeyAuth
;;; packages/ai/src/api/anthropic-messages.ts getAnthropicFederation
;;; @anthropic-ai/sdk@0.129.0 lib/credentials/oidc-federation.js

(defun federation-resolve (environment &key credential overrides)
  (cadr-ai::built-in-api-key-auth
   (cadr-ai:find-provider-definition :anthropic)
   credential
   environment
   overrides))

(defun federation-env (&key (rule "fdrl_test")
                            (organization "org-test")
                            (service "svac_test" service-p)
                            (file "/tmp/identity.jwt")
                            workspace
                            omit)
  (let ((service-id (if service-p service "svac_test")))
    (remove-if
     (lambda (entry) (member (car entry) omit :test #'string=))
     (append
      (list (cons "ANTHROPIC_FEDERATION_RULE_ID" rule)
            (cons "ANTHROPIC_ORGANIZATION_ID" organization)
            (cons "ANTHROPIC_IDENTITY_TOKEN_FILE" file))
      (when service-id
        (list (cons "ANTHROPIC_SERVICE_ACCOUNT_ID" service-id)))
      (when workspace
        (list (cons "ANTHROPIC_WORKSPACE_ID" workspace)))))))

(defun federation-model (&key (provider :anthropic)
                              (base-url "https://api.anthropic.com"))
  (cadr-ai:make-model
   :id "claude-test"
   :name "Claude Test"
   :provider provider
   :api :anthropic-messages
   :base-url base-url
   :max-tokens 4096
   :context-window 100000))

(defun federation-context ()
  (make-context
   :system-prompt "System prompt."
   :messages (list (make-user-message :content "Hello"))))

(defun federation-header (headers name)
  (cdr (assoc name headers :test #'string-equal)))

(defun federation-calls ()
  (list nil))

(defun federation-record (calls url method headers content)
  (push (list :url url :method method :headers headers :content content)
        (car calls)))

(defun federation-sse ()
  (flexi-streams:make-in-memory-input-stream
   (babel:string-to-octets
    (format nil
            "event: message_start~%data: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_test\",\"usage\":{\"input_tokens\":1,\"output_tokens\":0}}}~%~%event: message_delta~%data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"},\"usage\":{\"output_tokens\":1}}~%~%event: message_stop~%data: {\"type\":\"message_stop\"}~%~%")
    :encoding :utf-8)))

(defmacro with-federation-transport ((calls &key (expires-in 3600)
                                            (token "federated-token")
                                            (clock 4000000000)
                                            (messages-status 200)
                                            (token-fn nil)
                                            (message-body-fn nil))
                                     &body body)
  (let ((box (gensym "CALLS"))
        (message-n (gensym "MESSAGE-N"))
        (saved-client (gensym "SAVED-CLIENT"))
        (saved-clock (gensym "SAVED-CLOCK")))
    `(let* ((,box (federation-calls))
            (,calls ,box)
            (,message-n (list 0))
            (,saved-client cadr-ai::*anthropic-federation-client*)
            (,saved-clock cadr-ai::*anthropic-federation-clock*)
            (*http-request-function*
              (lambda (url &key method headers content &allow-other-keys)
                (federation-record ,box url method headers content)
                (cond
                  ((search "/v1/oauth/token" url)
                   (let ((issued
                           (if ,token-fn
                               (funcall ,token-fn)
                               ,token)))
                     (values
                      (format nil
                              "{\"access_token\":\"~A\",\"expires_in\":~D}"
                              issued ,expires-in)
                      200
                      '(("content-type" . "application/json")))))
                  (t
                   (incf (car ,message-n))
                   (let ((status
                           (if (functionp ,messages-status)
                               (funcall ,messages-status (car ,message-n))
                               ,messages-status)))
                     (values
                      (if ,message-body-fn
                          (funcall ,message-body-fn status)
                          (if (<= 200 status 299)
                              (federation-sse)
                              "{\"type\":\"error\",\"error\":{\"type\":\"authentication_error\",\"message\":\"invalid\"}}"))
                      status
                      (if (<= 200 status 299)
                          '(("content-type" . "text/event-stream"))
                          '(("content-type" . "application/json"))))))))))
       ;; Process-global cache: advisory refresh runs on another thread and
       ;; must see the same client the request path wrote.
       (setf cadr-ai::*anthropic-federation-client* nil
             cadr-ai::*anthropic-federation-clock* (lambda () ,clock))
       (unwind-protect
            (progn ,@body)
         (setf cadr-ai::*anthropic-federation-client* ,saved-client
               cadr-ai::*anthropic-federation-clock* ,saved-clock)))))

(defun federation-recorded (calls suffix)
  (remove-if-not
   (lambda (call) (search suffix (getf call :url)))
   (car calls)))

(test anthropic-federation-resolves-provider-env-without-request-auth
  (let* ((env (federation-env))
         (result (federation-resolve env)))
    (is (null (cadr-ai:runtime-auth-result-api-key result)))
    (is (null (cadr-ai:runtime-auth-result-headers result)))
    (is (string= "workload identity federation"
                 (cadr-ai:runtime-auth-result-source result)))
    (is (equal env (cadr-ai:runtime-auth-result-environment result)))))

(test anthropic-federation-passes-workspace-id-when-set
  (let ((result
          (federation-resolve
           (federation-env :workspace "wrkspc_test"))))
    (is (string= "wrkspc_test"
                 (cdr (assoc "ANTHROPIC_WORKSPACE_ID"
                             (cadr-ai:runtime-auth-result-environment result)
                             :test #'string=))))))

(test anthropic-federation-is-absent-when-a-required-variable-is-missing
  (dolist (name '("ANTHROPIC_FEDERATION_RULE_ID"
                  "ANTHROPIC_ORGANIZATION_ID"
                  "ANTHROPIC_IDENTITY_TOKEN_FILE"))
    (is (null (federation-resolve (federation-env :omit (list name))))
        name))
  (is (null (federation-resolve
             (federation-env :rule ""))))
  (is (null (federation-resolve
             (federation-env :organization ""))))
  (is (null (federation-resolve
             (federation-env :file "")))))

(test anthropic-federation-treats-service-account-as-optional
  (let* ((env (federation-env :service nil))
         (result (federation-resolve env)))
    (is (string= "workload identity federation"
                 (cadr-ai:runtime-auth-result-source result)))
    (is (null (assoc "ANTHROPIC_SERVICE_ACCOUNT_ID"
                     (cadr-ai:runtime-auth-result-environment result)
                     :test #'string=)))
    (is (equal env
               (cadr-ai:runtime-auth-result-environment result)))))

(test anthropic-federation-keeps-key-and-auth-token-precedence
  (let ((api-key
          (federation-resolve
           (acons "ANTHROPIC_API_KEY" "api-key" (federation-env))))
        (auth-token
          (federation-resolve
           (acons "ANTHROPIC_AUTH_TOKEN" "auth-token" (federation-env))))
        (oauth-token
          (federation-resolve
           (acons "ANTHROPIC_OAUTH_TOKEN" "oauth-token"
                  (acons "ANTHROPIC_API_KEY" "api-key" (federation-env)))))
        (stored
          (federation-resolve
           (federation-env)
           :credential
           (cadr-ai:make-api-key-credential
            :provider :anthropic :key "stored-key")))
        (explicit
          (federation-resolve
           (federation-env)
           :overrides '(:api-key "explicit-key"))))
    (is (string= "api-key" (cadr-ai:runtime-auth-result-api-key api-key)))
    (is (string= "ANTHROPIC_API_KEY"
                 (cadr-ai:runtime-auth-result-source api-key)))
    (is (null (cadr-ai:runtime-auth-result-api-key auth-token)))
    (is (string= "Bearer auth-token"
                 (federation-header
                  (cadr-ai:runtime-auth-result-headers auth-token)
                  "Authorization")))
    (is (string= "ANTHROPIC_AUTH_TOKEN"
                 (cadr-ai:runtime-auth-result-source auth-token)))
    (is (string= "oauth-token"
                 (cadr-ai:runtime-auth-result-api-key oauth-token)))
    (is (string= "ANTHROPIC_OAUTH_TOKEN"
                 (cadr-ai:runtime-auth-result-source oauth-token)))
    (is (string= "stored-key"
                 (cadr-ai:runtime-auth-result-api-key stored)))
    (is (string= "stored credential"
                 (cadr-ai:runtime-auth-result-source stored)))
    (is (string= "explicit-key"
                 (cadr-ai:runtime-auth-result-api-key explicit)))
    (is (string= "Explicit API key"
                 (cadr-ai:runtime-auth-result-source explicit)))))

(test anthropic-federation-exchanges-the-identity-token-once
  (uiop:with-temporary-file (:pathname path)
    (with-open-file (stream path :direction :output :if-exists :supersede)
      (write-string "header.payload.signature" stream))
    (with-federation-transport (calls)
      (let ((provider
              (cadr-ai:make-anthropic-provider
               :provider-id :anthropic
               :options
               (list :environment
                     (federation-env :service nil
                                     :file (namestring path)))))
            (model (federation-model)))
        (dotimes (i 3)
          (let ((message
                  (stream-chat provider model (federation-context)
                               (lambda (event) (declare (ignore event))))))
            (is (eq :stop (assistant-message-stop-reason message))))))
      (is (= 1 (length (federation-recorded calls "/v1/oauth/token"))))
      (let ((messages (federation-recorded calls "/v1/messages")))
        (is (= 3 (length messages)))
        (dolist (call messages)
          (is (string= "Bearer federated-token"
                       (federation-header (getf call :headers)
                                          "authorization")))
          (is (null (federation-header (getf call :headers) "x-api-key")))
          (let ((beta (federation-header (getf call :headers)
                                         "anthropic-beta")))
            (is (search "oauth-2025-04-20" beta)))))
      (let* ((token (first (federation-recorded calls "/v1/oauth/token")))
             (body (cadr-ai::parse-json (getf token :content))))
        (is (string= "urn:ietf:params:oauth:grant-type:jwt-bearer"
                     (cadr-ai::json-get body "grant_type")))
        (is (string= "header.payload.signature"
                     (cadr-ai::json-get body "assertion")))
        (is (string= "fdrl_test"
                     (cadr-ai::json-get body "federation_rule_id")))
        (is (string= "org-test"
                     (cadr-ai::json-get body "organization_id")))
        (is (not (cadr-ai::json-present-p body "service_account_id")))
        (is (not (cadr-ai::json-present-p body "workspace_id")))
        (is (string= "oauth-2025-04-20,oidc-federation-2026-04-01"
                     (federation-header (getf token :headers)
                                        "anthropic-beta")))))))

(test anthropic-federation-sends-optional-service-account-and-workspace
  (uiop:with-temporary-file (:pathname path)
    (with-open-file (stream path :direction :output :if-exists :supersede)
      (write-string "header.payload.signature" stream))
    (with-federation-transport (calls)
      (stream-chat
       (cadr-ai:make-anthropic-provider
        :provider-id :anthropic
        :options
        (list :environment
              (federation-env :file (namestring path)
                              :workspace "wrkspc_test")))
       (federation-model)
       (federation-context)
       (lambda (event) (declare (ignore event))))
      (let ((body
              (cadr-ai::parse-json
               (getf (first (federation-recorded calls "/v1/oauth/token"))
                     :content))))
        (is (string= "svac_test"
                     (cadr-ai::json-get body "service_account_id")))
        (is (string= "wrkspc_test"
                     (cadr-ai::json-get body "workspace_id")))))))

(test anthropic-federation-rereads-the-identity-token-after-expiry
  (uiop:with-temporary-file (:pathname path)
    (with-open-file (stream path :direction :output :if-exists :supersede)
      (write-string "header.payload.one" stream))
    (let ((now 4000000000))
      (with-federation-transport (calls :clock now)
        (flet ((chat ()
                 (stream-chat
                  (cadr-ai:make-anthropic-provider
                   :provider-id :anthropic
                   :options
                   (list :environment
                         (federation-env :service nil
                                         :file (namestring path))))
                  (federation-model)
                  (federation-context)
                  (lambda (event) (declare (ignore event))))))
          (chat)
          (with-open-file (stream path :direction :output :if-exists :supersede)
            (write-string "header.payload.two" stream))
          (incf now 3600)
          (chat))
        (let ((assertions
                (mapcar
                 (lambda (call)
                   (cadr-ai::json-get
                    (cadr-ai::parse-json (getf call :content))
                    "assertion"))
                 (federation-recorded calls "/v1/oauth/token"))))
          (is (equal '("header.payload.two" "header.payload.one")
                     assertions)))))))

;;; @anthropic-ai/sdk@0.129.0 lib/credentials/token-cache.ts:
;;; remaining > 120 keeps the cache; 30 < remaining <= 120 returns the
;;; stale token and refreshes in the background while rereading the file.
(test anthropic-federation-refreshes-in-the-background-inside-the-advisory-window
  (uiop:with-temporary-file (:pathname path)
    (with-open-file (stream path :direction :output :if-exists :supersede)
      (write-string "header.payload.one" stream))
    (let ((now 4000000000)
          (token-n (list 0)))
      (with-federation-transport
          (calls
           :clock now
           :expires-in 3600
           :token-fn
           (lambda ()
             (incf (car token-n))
             (format nil "federated-token-~D" (car token-n))))
        (flet ((chat ()
                 (stream-chat
                  (cadr-ai:make-anthropic-provider
                   :provider-id :anthropic
                   :options
                   (list :environment
                         (federation-env :service nil
                                         :file (namestring path))))
                  (federation-model)
                  (federation-context)
                  (lambda (event) (declare (ignore event))))))
          (chat)
          (with-open-file (stream path :direction :output :if-exists :supersede)
            (write-string "header.payload.two" stream))
          (incf now 3500)
          (let ((message (chat)))
            (is (eq :stop (assistant-message-stop-reason message))))
          (loop repeat 50
                until (>= (length (federation-recorded calls "/v1/oauth/token"))
                          2)
                do (sleep 0.02))
          (is (= 2 (length (federation-recorded calls "/v1/oauth/token"))))
          (let* ((messages (federation-recorded calls "/v1/messages"))
                 (first-message (second messages))
                 (second-message (first messages))
                 (assertions
                   (mapcar
                    (lambda (call)
                      (cadr-ai::json-get
                       (cadr-ai::parse-json (getf call :content))
                       "assertion"))
                    (federation-recorded calls "/v1/oauth/token"))))
            (is (string= "Bearer federated-token-1"
                         (federation-header (getf first-message :headers)
                                            "authorization")))
            (is (string= "Bearer federated-token-1"
                         (federation-header (getf second-message :headers)
                                            "authorization")))
            (is (equal '("header.payload.two" "header.payload.one")
                       assertions))
            (chat)
            (let ((third
                    (first (federation-recorded calls "/v1/messages"))))
              (is (string= "Bearer federated-token-2"
                           (federation-header (getf third :headers)
                                              "authorization"))))))))))

;;; pi sets SDK maxRetries to 0; shouldRetry still invalidates the cache on
;;; 401, so the next request exchanges again.
(test anthropic-federation-exchanges-again-after-a-401
  (uiop:with-temporary-file (:pathname path)
    (with-open-file (stream path :direction :output :if-exists :supersede)
      (write-string "header.payload.one" stream))
    (let ((now 4000000000)
          (token-n (list 0)))
      (with-federation-transport
          (calls
           :clock now
           :token-fn
           (lambda ()
             (incf (car token-n))
             (format nil "federated-token-~D" (car token-n)))
           :messages-status
           (lambda (n)
             (if (= n 1) 401 200)))
        (flet ((chat ()
                 (stream-chat
                  (cadr-ai:make-anthropic-provider
                   :provider-id :anthropic
                   :options
                   (list :environment
                         (federation-env :service nil
                                         :file (namestring path))))
                  (federation-model)
                  (federation-context)
                  (lambda (event) (declare (ignore event))))))
          (let ((first (chat)))
            (is (eq :error (assistant-message-stop-reason first))))
          (with-open-file (stream path :direction :output :if-exists :supersede)
            (write-string "header.payload.two" stream))
          (let ((second (chat)))
            (is (eq :stop (assistant-message-stop-reason second))))
          (is (= 2 (length (federation-recorded calls "/v1/oauth/token"))))
          (let* ((messages (federation-recorded calls "/v1/messages"))
                 (assertions
                   (mapcar
                    (lambda (call)
                      (cadr-ai::json-get
                       (cadr-ai::parse-json (getf call :content))
                       "assertion"))
                    (federation-recorded calls "/v1/oauth/token"))))
            (is (= 2 (length messages)))
            (is (string= "Bearer federated-token-1"
                         (federation-header
                          (getf (second messages) :headers)
                          "authorization")))
            (is (string= "Bearer federated-token-2"
                         (federation-header
                          (getf (first messages) :headers)
                          "authorization")))
            (is (equal '("header.payload.two" "header.payload.one")
                       assertions))))))))

(test anthropic-federation-lets-an-explicit-api-key-win
  (uiop:with-temporary-file (:pathname path)
    (with-open-file (stream path :direction :output :if-exists :supersede)
      (write-string "header.payload.signature" stream))
    (with-federation-transport (calls)
      (let ((message
              (stream-chat
               (cadr-ai:make-anthropic-provider
                :api-key "explicit-key"
                :provider-id :anthropic
                :options
                (list :environment
                      (federation-env :file (namestring path))))
               (federation-model)
               (federation-context)
               (lambda (event) (declare (ignore event))))))
        (is (eq :stop (assistant-message-stop-reason message))))
      (is (null (federation-recorded calls "/v1/oauth/token")))
      (is (string= "explicit-key"
                   (federation-header
                    (getf (first (federation-recorded calls "/v1/messages"))
                          :headers)
                    "x-api-key"))))))

(test anthropic-federation-skips-exchange-for-header-owned-auth
  (uiop:with-temporary-file (:pathname path)
    (with-open-file (stream path :direction :output :if-exists :supersede)
      (write-string "header.payload.signature" stream))
    (with-federation-transport (calls)
      (let ((message
              (stream-chat
               (cadr-ai:make-anthropic-provider
                :provider-id :anthropic
                :options
                (list :environment
                      (federation-env :file (namestring path))))
               (federation-model)
               (federation-context)
               (lambda (event) (declare (ignore event)))
               :headers '(("Authorization" . "Bearer auth-token")))))
        (is (eq :stop (assistant-message-stop-reason message)))
        (is (null (federation-recorded calls "/v1/oauth/token")))
        (let ((messages (federation-recorded calls "/v1/messages")))
          (is (= 1 (length messages)))
          (is (string= "Bearer auth-token"
                       (federation-header
                        (getf (first messages) :headers)
                        "authorization"))))))))

(test anthropic-federation-does-not-federate-other-anthropic-messages-providers
  (with-federation-transport (calls)
    (let ((message
            (stream-chat
             (cadr-ai:make-anthropic-provider
              :provider-id :kimi-coding
              :options (list :environment (federation-env)))
             (federation-model :provider :kimi-coding
                               :base-url "https://api.kimi.com/coding")
             (federation-context)
             (lambda (event) (declare (ignore event))))))
      (is (eq :error (assistant-message-stop-reason message))))
    (is (null (car calls)))))

(test anthropic-federation-refuses-a-cleartext-token-endpoint
  (uiop:with-temporary-file (:pathname path)
    (with-open-file (stream path :direction :output :if-exists :supersede)
      (write-string "header.payload.signature" stream))
    (with-federation-transport (calls)
      (let ((message
              (stream-chat
               (cadr-ai:make-anthropic-provider
                :provider-id :anthropic
                :options
                (list :environment
                      (federation-env :file (namestring path))))
               (federation-model :base-url "http://example.com")
               (federation-context)
               (lambda (event) (declare (ignore event))))))
        (is (eq :error (assistant-message-stop-reason message)))
        (is (search "Refusing to send credential over non-https token endpoint"
                    (assistant-message-error-message message))))
      (is (null (car calls))))))

(test anthropic-federation-threads-auth-context-through-the-models-runtime
  (uiop:with-temporary-file (:pathname path)
    (with-open-file (stream path :direction :output :if-exists :supersede)
      (write-string "header.payload.signature" stream))
    (with-federation-transport (calls)
      (let* ((env
               (append
                '(("ANTHROPIC_API_KEY" . "")
                  ("ANTHROPIC_AUTH_TOKEN" . "")
                  ("ANTHROPIC_OAUTH_TOKEN" . ""))
                (federation-env :service nil :file (namestring path))))
             (runtime
               (cadr-ai:make-built-in-models-runtime :environment env))
             (message
               (cadr-ai:models-runtime-stream
                runtime
                (federation-model)
                (federation-context)
                (lambda (event) (declare (ignore event))))))
        (is (eq :stop (assistant-message-stop-reason message)))
        (is (= 1 (length (federation-recorded calls "/v1/oauth/token"))))
        (is (string= "Bearer federated-token"
                     (federation-header
                      (getf (first (federation-recorded calls "/v1/messages"))
                            :headers)
                      "authorization")))))))
