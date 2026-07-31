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

(test legacy-environment-values-work-for-one-transition-release-and-warn
  (let* ((values
           (list
            (cons (cadr-cli::legacy-environment-name "PROVIDER")
                  "deepseek")
            (cons (cadr-cli::legacy-environment-name "MODEL")
                  "legacy-model")
            (cons (cadr-cli::legacy-environment-name "BASE_URL")
                  "https://legacy.example")))
         (warnings (make-string-output-stream))
         (cadr-cli::*environment-function*
           (lambda (name)
             (cdr (assoc name values :test #'string=))))
         (cadr-cli::*deprecation-warning-stream* warnings))
    (let ((config
            (cadr-cli:resolve-provider-config
             :config-path #P"/definitely/missing/config.json"
             :auth-path #P"/definitely/missing/auth.json"
             :allow-missing-auth-p t)))
      (is (string= "deepseek"
                   (cadr-cli:provider-config-name config)))
      (is (string= "legacy-model"
                   (cadr-ai:model-id
                    (cadr-cli:provider-config-model config))))
      (is (string= "https://legacy.example"
                   (cadr-ai:model-base-url
                    (cadr-cli:provider-config-model config)))))
    (let ((text (get-output-stream-string warnings)))
      (dolist (suffix '("PROVIDER" "MODEL" "BASE_URL"))
        (is (search
             (cadr-cli::legacy-environment-name suffix)
             text)))
      (is (search "0.2.0" text)))))

(test new-environment-values-win-without-reading-legacy-values
  (let* ((values
           `(("CADR_PROVIDER" . "deepseek")
             ("CADR_MODEL" . "new-model")
             ("CADR_BASE_URL" . "https://new.example")
             (,(cadr-cli::legacy-environment-name "PROVIDER")
              . "deepseek")
             (,(cadr-cli::legacy-environment-name "MODEL")
              . "legacy-model")
             (,(cadr-cli::legacy-environment-name "BASE_URL")
              . "https://legacy.example")))
         (warnings (make-string-output-stream))
         (cadr-cli::*environment-function*
           (lambda (name)
             (cdr (assoc name values :test #'string=))))
         (cadr-cli::*deprecation-warning-stream* warnings))
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
                    (cadr-cli:provider-config-model config)))))
    (is (string= "" (get-output-stream-string warnings)))))

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
                 &key output auth-url-function)
              (declare
               (ignore output auth-url-function))
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

(test login-openai-change-event-selects-codex-default-path
  (with-test-directory (directory)
    (let* ((path (merge-pathnames "auth.json" directory))
           (changes nil)
           (request-url nil)
           (request-headers nil)
           (cadr-cli::*openai-login-function*
             (lambda (auth-path &key output auth-url-function)
               (declare (ignore output auth-url-function))
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
        :auth-path path
        :output (make-string-output-stream)
        :on-change
        (lambda (provider action)
          (push (list provider action) changes))))
      (is (equal
           '((:openai-codex :login))
           changes))
      (let* ((provider
               (first (first changes)))
             (config
               (cadr-cli:resolve-provider-config
                :provider
                (string-downcase
                 (symbol-name provider))
                :config-path
                #P"/definitely/missing/config.json"
                :auth-path path)))
        (is (string=
             "gpt-5.5"
             (cadr-ai:model-id
              (cadr-cli:provider-config-model
               config))))
        (let ((cadr-ai::*http-request-function*
                (lambda (url &rest arguments)
                  (setf request-url url
                        request-headers
                        (getf arguments :headers))
                  (values
                   (make-string-input-stream
                    (format
                     nil
                     "data: {\"type\":\"response.created\",\"response\":{\"id\":\"resp_login\"}}~%~%data: {\"type\":\"response.output_item.added\",\"output_index\":0,\"item\":{\"type\":\"message\",\"id\":\"msg_login\",\"role\":\"assistant\",\"content\":[]}}~%~%data: {\"type\":\"response.output_text.delta\",\"output_index\":0,\"delta\":\"LOGIN_DEFAULT_OK\"}~%~%data: {\"type\":\"response.output_item.done\",\"output_index\":0,\"item\":{\"type\":\"message\",\"id\":\"msg_login\",\"role\":\"assistant\",\"content\":[{\"type\":\"output_text\",\"text\":\"LOGIN_DEFAULT_OK\"}]}}~%~%data: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp_login\",\"status\":\"completed\",\"model\":\"gpt-5.5\",\"usage\":{\"input_tokens\":1,\"output_tokens\":1,\"total_tokens\":2}}}~%~%"))
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
                     :test #'string-equal))))))))
