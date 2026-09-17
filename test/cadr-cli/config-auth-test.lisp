(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(test provider-config-resolves-registry-config-and-cli-precedence
  (with-test-directory (directory)
    (let ((config-path (merge-pathnames "config.json" directory))
          (auth-path (merge-pathnames "auth.json" directory))
          (cadr-cli::*environment-function*
            (lambda (name)
              (and (string= name "DEEPSEEK_API_KEY")
                   "deepseek-secret"))))
      (write-text
       config-path
       "{\"providers\":{\"deepseek\":{\"base-url\":\"https://config.example/v1\",\"model\":\"deepseek-v4-pro\"}}}")
      (let ((config
              (cadr-cli:resolve-provider-config
               :provider "deepseek"
               :config-path config-path
               :auth-path auth-path)))
        (is (string= "deepseek"
                     (cadr-cli:provider-config-name config)))
        (is (typep (cadr-cli:provider-config-provider config)
                   'cadr-ai:openai-completions-provider))
        (is (string= "deepseek-v4-pro"
                     (cadr-ai:model-id
                      (cadr-cli:provider-config-model config))))
        (is (string= "https://config.example/v1"
                     (cadr-ai:model-base-url
                      (cadr-cli:provider-config-model config)))))
      (let ((config
              (cadr-cli:resolve-provider-config
               :provider "deepseek"
               :model "deepseek-v4-flash"
               :base-url "https://cli.example"
               :config-path config-path
               :auth-path auth-path)))
        (is (string= "deepseek-v4-flash"
                     (cadr-ai:model-id
                      (cadr-cli:provider-config-model config))))
        (is (string= "https://cli.example"
                     (cadr-ai:model-base-url
                      (cadr-cli:provider-config-model config))))))))

(test unknown-deepseek-model-inherits-fallback-capabilities-for-every-thinking-level
  (with-test-directory (directory)
    (let ((config-path (merge-pathnames "config.json" directory))
          (auth-path (merge-pathnames "auth.json" directory))
          (cadr-cli::*environment-function*
            (lambda (name)
              (and (string= name "DEEPSEEK_API_KEY")
                   "deepseek-secret"))))
      (dolist (level '(:off :minimal :low :medium :high :xhigh :max))
        (let* ((config
                 (cadr-cli:resolve-provider-config
                  :provider "deepseek"
                  :model "deepseek-chat"
                  :reasoning level
                  :config-path config-path
                  :auth-path auth-path))
               (provider
                 (cadr-cli:provider-config-provider config))
               (model
                 (cadr-cli:provider-config-model config))
               (requested
                 (unless (eq level :off) level))
               (request
                 (cadr-ai:build-request
                  provider model
                  (cadr-ai:make-context
                   :messages
                   (list
                    (cadr-ai:make-user-message :content "think")))
                  :stream-p t
                  :reasoning requested))
               (payload
                 (cadr-ai:request-spec-payload request))
               (thinking
                 (cadr-ai::json-get payload "thinking")))
          (is (string= "deepseek-chat"
                       (cadr-ai:model-id model)))
          (is (cadr-ai:model-reasoning-p model))
          (is (= 1000000
                 (cadr-ai:model-context-window model)))
          (if requested
              (progn
                (is (string=
                     "enabled"
                     (cadr-ai::json-get thinking "type")))
                (is (string=
                     (string-downcase (symbol-name level))
                     (cadr-ai::json-get payload
                                        "reasoning_effort"))))
              (progn
                (is (string=
                     "disabled"
                     (cadr-ai::json-get thinking "type")))
                (is (null
                     (cadr-ai::json-get payload
                                        "reasoning_effort")))))
          (let ((events nil)
                (cadr-ai::*http-request-function*
                  (lambda (url &rest arguments)
                    (declare (ignore url arguments))
                    (values
                     (make-string-input-stream
                      (if requested
                          (format
                           nil
                           "data: {\"choices\":[{\"delta\":{\"reasoning_content\":\"plan\"},\"finish_reason\":null}]}~%~%data: {\"choices\":[{\"delta\":{\"content\":\"ok\"},\"finish_reason\":\"stop\"}]}~%~%")
                          (format
                           nil
                           "data: {\"choices\":[{\"delta\":{\"content\":\"ok\"},\"finish_reason\":\"stop\"}]}~%~%")))
                     200
                     '(("content-type" . "text/event-stream"))))))
            (let ((message
                    (cadr-ai:stream-chat
                     provider model
                     (cadr-ai:make-context
                      :messages
                      (list
                       (cadr-ai:make-user-message :content "think")))
                     (lambda (event)
                       (push event events))
                     :reasoning requested)))
              (is (eq :stop
                      (cadr-ai:assistant-message-stop-reason message)))
              (if requested
                  (is (equal
                       '(:thinking-start :thinking-delta :thinking-end)
                       (remove-if-not
                        (lambda (type)
                          (member type
                                  '(:thinking-start
                                    :thinking-delta
                                    :thinking-end)))
                        (mapcar
                         #'cadr-ai:stream-event-type
                         (nreverse events)))))
                  (is (not
                       (member
                        :thinking-delta
                        (mapcar
                         #'cadr-ai:stream-event-type
                         (nreverse events)))))))))))))

(test goal10-version-0-2-no-longer-reads-legacy-environment-values
  (let* ((values
           '(("PI_CL_PROVIDER" . "deepseek")
             ("PI_CL_MODEL" . "legacy-model")
             ("PI_CL_BASE_URL" . "https://legacy.example")))
         (cadr-cli::*environment-function*
           (lambda (name)
             (cdr (assoc name values :test #'string=)))))
    ;; Strict resolution still fails when nothing is configured.
    (signals cadr-ai:configuration-error
      (cadr-cli:resolve-provider-config
       :config-path #P"/definitely/missing/config.json"
       :auth-path #P"/definitely/missing/auth.json"))
    ;; The deferred (allow-missing-auth) path falls back to the openai
    ;; default — the legacy PI_CL_* values must contribute nothing.
    (let ((config
            (cadr-cli:resolve-provider-config
             :config-path #P"/definitely/missing/config.json"
             :auth-path #P"/definitely/missing/auth.json"
             :allow-missing-auth-p t)))
      (is (string= "openai"
                   (cadr-cli:provider-config-name config)))
      (is (not (string= "legacy-model"
                        (cadr-ai:model-id
                         (cadr-cli:provider-config-model config)))))
      (is (not (string= "https://legacy.example"
                        (cadr-ai:model-base-url
                         (cadr-cli:provider-config-model config))))))))

(test cadr-environment-values-resolve-provider-model-and-base-url
  (let* ((values
           '(("CADR_PROVIDER" . "deepseek")
             ("CADR_MODEL" . "new-model")
             ("CADR_BASE_URL" . "https://new.example")))
         (cadr-cli::*environment-function*
           (lambda (name)
             (cdr (assoc name values :test #'string=)))))
    (let ((config
            (cadr-cli:resolve-provider-config
             :config-path #P"/definitely/missing/config.json"
             :auth-path #P"/definitely/missing/auth.json"
             :allow-missing-auth-p t)))
      (is (string= "deepseek"
                   (cadr-cli:provider-config-name config)))
      (is (string= "new-model"
                   (cadr-ai:model-id
                    (cadr-cli:provider-config-model config))))
      (is (string= "https://new.example"
                   (cadr-ai:model-base-url
                    (cadr-cli:provider-config-model config)))))))

(test non-baseline-ollama-provider-is-not-registered
  (let ((cadr-cli::*environment-function* (constantly nil)))
    (signals cadr-ai:configuration-error
      (cadr-cli:resolve-provider-config
       :provider "ollama"
       :config-path #P"/definitely/missing/config.json"
       :auth-path #P"/definitely/missing/auth.json"
       :allow-missing-auth-p t))))

(test stored-oauth-owns-openai-codex-auth-and-selects-codex-endpoint
  (with-test-directory (directory)
    (let ((auth-path (merge-pathnames "auth.json" directory))
          (cadr-cli::*environment-function*
            (lambda (name)
              (and (string= name "OPENAI_API_KEY")
                   "must-not-win"))))
      (cadr-ai:write-auth-credential
       auth-path
       (cadr-ai:make-oauth-credential
        :provider :openai-codex
        :access "oauth-access"
        :refresh "oauth-refresh"
        :expires (+ (cadr-ai::unix-milliseconds) 3600000)
        :account-id "acct"))
      (let ((config
              (cadr-cli:resolve-provider-config
               :provider "openai-codex"
               :config-path #P"/definitely/missing/config.json"
               :auth-path auth-path)))
        (is (string= "gpt-5.5"
                     (cadr-ai:model-id
                      (cadr-cli:provider-config-model config))))
        (is (eq :oauth
                (cadr-cli:provider-config-auth-source config)))
        (is (string= "https://chatgpt.com/backend-api"
                     (cadr-ai:model-base-url
                      (cadr-cli:provider-config-model config))))
        (let ((request
                (cadr-ai:build-request
                 (cadr-cli:provider-config-provider config)
                 (cadr-cli:provider-config-model config)
                 (cadr-ai:make-context
                  :messages
                  (list
                   (cadr-ai:make-user-message :content "hello")))
                 :stream-p t)))
          (is (string=
               "Bearer oauth-access"
               (cdr
                (assoc
                 "authorization"
                 (cadr-ai:request-spec-headers request)
                 :test #'string-equal)))))))))

(test stored-xai-oauth-resolves-for-grok-chat
  (with-test-directory (directory)
    (let ((auth-path (merge-pathnames "auth.json" directory))
          (cadr-cli::*environment-function*
            (lambda (name)
              (and (string= name "XAI_API_KEY")
                   "must-not-win"))))
      (cadr-ai:write-auth-credential
       auth-path
       (cadr-ai:make-oauth-credential
        :provider :xai
        :access "xai-oauth-access"
        :refresh "xai-oauth-refresh"
        :expires (+ (cadr-ai::unix-milliseconds) 3600000)))
      (let ((config
              (cadr-cli:resolve-provider-config
               :provider "xai"
               :model "grok-4.5"
               :config-path #P"/definitely/missing/config.json"
               :auth-path auth-path)))
        (is (eq :oauth
                (cadr-cli:provider-config-auth-source config)))
        (is (string= "grok-4.5"
                     (cadr-ai:model-id
                      (cadr-cli:provider-config-model config))))
        (let ((request
                (cadr-ai:build-request
                 (cadr-cli:provider-config-provider config)
                 (cadr-cli:provider-config-model config)
                 (cadr-ai:make-context
                  :messages
                  (list
                   (cadr-ai:make-user-message :content "hello")))
                 :stream-p t)))
          (is (string=
               "Bearer xai-oauth-access"
               (cdr
                (assoc
                 "authorization"
                 (cadr-ai:request-spec-headers request)
                 :test #'string-equal)))))))))
(test misidentified-openai-oauth-does-not-block-login-recovery
  (with-test-directory (directory)
    (let ((auth-path
            (merge-pathnames "auth.json" directory)))
      (cadr-ai:write-auth-credential
       auth-path
       (cadr-ai:make-oauth-credential
        :provider :openai
        :access "legacy-access"
        :refresh "legacy-refresh"
        :expires
        (+ (cadr-ai::unix-milliseconds)
           3600000)
        :account-id "acct"))
      (let ((config
              (cadr-cli:resolve-provider-config
               :provider "openai"
               :config-path
               #P"/definitely/missing/config.json"
               :auth-path auth-path
               :allow-missing-auth-p t)))
        (is (eq
             :none
             (cadr-cli:provider-config-auth-source
              config)))
        (is (null
             (cadr-ai::provider-oauth-access-token
              (cadr-cli:provider-config-provider
               config))))
        (is (typep
             (cadr-ai:read-auth-credential
              auth-path :openai)
             'cadr-ai:oauth-credential))))))

(test repl-dispatches-slash-commands-without-prompting-model
  (let ((commands nil)
        (prompts nil)
        (output (make-string-output-stream)))
    (cadr-cli:run-repl
     (lambda (prompt)
       (push prompt prompts)
       (cadr-ai:make-assistant-message
        :content (list (cadr-ai:make-text-content :text "ok"))
        :stop-reason :stop))
     :command-function
     (lambda (command)
       (push command commands)
       t)
     :input
     (make-string-input-stream
      (format nil "/logout openai~%hello~%"))
     :output output)
    (is (equal '("/logout openai") (nreverse commands)))
    (is (equal '("hello") (nreverse prompts)))))

(test auth-command-login-and-logout-dispatch
  (with-test-directory (directory)
    (let* ((path (merge-pathnames "auth.json" directory))
           (calls nil)
           (output (make-string-output-stream))
           (cadr-cli::*openai-login-function*
            (lambda
                (auth-path
                 &key output auth-url-function
                   auth-prompt-function)
              (declare
               (ignore output auth-url-function
                       auth-prompt-function))
              (push :login calls)
              (cadr-ai:write-auth-credential
               auth-path
               (cadr-ai:make-oauth-credential
                :provider :openai-codex
                :access "a" :refresh "r"
                :expires (+ (cadr-ai::unix-milliseconds) 1000000)
                :account-id "acct")))))
      (is (cadr-cli:handle-auth-command
           "/login openai" :auth-path path :output output))
      (is (typep (cadr-ai:read-auth-credential
                  path :openai-codex)
                 'cadr-ai:oauth-credential))
      (let ((config
              (cadr-cli:resolve-provider-config
               :provider "openai-codex"
               :config-path
               #P"/definitely/missing/config.json"
               :auth-path path)))
        (is (string=
             "gpt-5.5"
             (cadr-ai:model-id
              (cadr-cli:provider-config-model config))))
        (is (eq :oauth
                (cadr-cli:provider-config-auth-source
                 config))))
      (is (cadr-cli:handle-auth-command
           "/logout openai" :auth-path path :output output))
      (is (null
           (cadr-ai:read-auth-credential
            path :openai-codex)))
      (is (equal '(:login) calls)))))

(test login-openai-temp-store-default-resolver-routes-codex-request
  (with-test-directory (directory)
    (let* ((auth-path
             (merge-pathnames
              ".cadr/auth.json" directory))
           (config-path
             (merge-pathnames
              ".cadr/config.json" directory))
           (changes nil)
           (request-url nil)
           (request-headers nil)
           (cadr-cli::*openai-login-function*
             (lambda
                 (auth-path
                  &key output auth-url-function
                    auth-prompt-function)
               (declare
                (ignore output auth-url-function
                        auth-prompt-function))
               (cadr-ai:write-auth-credential
                auth-path
                (cadr-ai:make-oauth-credential
                 :provider :openai-codex
                 :access "a" :refresh "r"
                 :expires
                 (+ (cadr-ai::unix-milliseconds)
                    1000000)
                 :account-id "acct")))))
      (is
       (cadr-cli:handle-auth-command
        "/login openai"
        :auth-path auth-path
        :output (make-string-output-stream)
        :on-change
        (lambda (provider action)
          (push (list provider action) changes))))
      (is (equal
           '((:openai-codex :login))
           changes))
      (is (typep
           (cadr-ai:read-auth-credential
            auth-path :openai-codex)
           'cadr-ai:oauth-credential))
      (is (null
           (cadr-ai:read-auth-credential
            auth-path :openai)))
      (let* ((provider
               (first (first changes)))
             (config
               (cadr-cli:resolve-provider-config
                :provider
                (string-downcase
                 (symbol-name provider))
                :config-path config-path
                :auth-path auth-path)))
        (is (string=
             "openai-codex"
             (cadr-cli:provider-config-name
              config)))
        (is (eq
             :openai-codex
             (cadr-ai:model-provider
              (cadr-cli:provider-config-model
               config))))
        (is (eq
             :oauth
             (cadr-cli:provider-config-auth-source
              config)))
        (let ((cadr-ai::*http-request-function*
                (lambda (url &rest arguments)
                  (setf request-url url
                        request-headers
                        (getf arguments :headers))
                  (values
                   (make-string-input-stream
                    (format
                     nil
                     "data: {\"type\":\"response.created\",\"response\":{\"id\":\"resp_login\"}}~%~%data: {\"type\":\"response.output_item.added\",\"output_index\":0,\"item\":{\"type\":\"message\",\"id\":\"msg_login\",\"role\":\"assistant\",\"content\":[]}}~%~%data: {\"type\":\"response.output_text.delta\",\"output_index\":0,\"delta\":\"LOGIN_DEFAULT_OK\"}~%~%data: {\"type\":\"response.output_item.done\",\"output_index\":0,\"item\":{\"type\":\"message\",\"id\":\"msg_login\",\"role\":\"assistant\",\"content\":[{\"type\":\"output_text\",\"text\":\"LOGIN_DEFAULT_OK\"}]}}~%~%data: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp_login\",\"status\":\"completed\",\"usage\":{\"input_tokens\":1,\"output_tokens\":1,\"total_tokens\":2}}}~%~%"))
                   200
                   '(("content-type"
                      . "text/event-stream"))))))
          (let ((message
                  (cadr-ai:stream-chat
                   (cadr-cli:provider-config-provider
                    config)
                   (cadr-cli:provider-config-model
                    config)
                   (cadr-ai:make-context
                    :messages
                    (list
                     (cadr-ai:make-user-message
                      :content "hello")))
                   (lambda (event)
                     (declare (ignore event))))))
            (is (eq
                 :stop
                 (cadr-ai:assistant-message-stop-reason
                  message)))
            (is (string=
                 "LOGIN_DEFAULT_OK"
                 (cadr-ai:text-content-text
                  (first
                   (cadr-ai:assistant-message-content
                    message)))))))
        (is (search
             "/codex/responses"
             request-url))
        (is (string=
             "Bearer a"
             (cdr
              (assoc "authorization"
                     request-headers
                     :test #'string-equal))))
        (is (string=
             "cadr"
             (cdr
              (assoc "originator"
                     request-headers
                     :test #'string-equal))))))))

(test goal13-login-command-forwards-the-manual-authorization-prompt
  (with-test-directory (directory)
    (let* ((path (merge-pathnames "auth.json" directory))
           (prompt-function (lambda (prompt) prompt))
           (received-prompt-function nil)
           (cadr-cli::*openai-login-function*
             (lambda
                 (auth-path
                  &key output auth-url-function
                    auth-prompt-function)
               (declare (ignore output auth-url-function))
               (setf received-prompt-function
                     auth-prompt-function)
               (cadr-ai:write-auth-credential
                auth-path
                (cadr-ai:make-oauth-credential
                 :provider :openai-codex
                 :access "access" :refresh "refresh"
                 :expires
                 (+ (cadr-ai::unix-milliseconds) 1000000)
                 :account-id "acct")))))
      (is
       (cadr-cli:handle-auth-command
        "/login openai"
        :auth-path path
        :output (make-string-output-stream)
        :auth-prompt-function prompt-function))
      (is (eq prompt-function received-prompt-function)))))

(test goal13-built-in-runtime-login-routes-aliases-and-persists-canonical-credentials
  (with-test-directory (directory)
    (let* ((path (merge-pathnames "auth.json" directory))
           (storage (cadr-cli:make-file-auth-storage path))
           (registry
             (cadr-cli:make-model-registry
              :path (merge-pathnames "models.json" directory)
              :credentials storage))
           (credential
             (cadr-ai:make-oauth-credential
              :provider :openai-codex
              :access "access" :refresh "refresh"
              :expires 1000 :account-id "account")))
      (is
       (eq
        credential
        (cadr-cli::model-registry-login-built-in-provider
         registry :openai-codex
         (cadr-ai:make-runtime-auth-interaction
          :prompt-function (constantly "unused"))
         :login-function (lambda (interaction)
                           (declare (ignore interaction))
                           credential))))
      (is
       (eq :openai-codex
           (cadr-ai:oauth-credential-provider
            (cadr-cli:auth-storage-read storage :openai-codex))))
      (is (null (cadr-cli:auth-storage-read storage :openai)))
      (let ((prompts nil))
        (signals cadr-ai:authentication-error
          (cadr-cli::handle-native-auth-command
           registry "/login openai"
           (cadr-ai:make-runtime-auth-interaction
            :prompt-function
            (lambda (prompt)
              (push (copy-tree prompt) prompts)
              "unsupported"))
           :output (make-string-output-stream)))
        (is
         (equal
          '((:type :select
             :message "Select OpenAI Codex login method:"
             :options
             ((:id "browser" :label "Browser login (default)")
              (:id "device_code"
               :label "Device code login (headless)"))))
          (nreverse prompts)))))))
