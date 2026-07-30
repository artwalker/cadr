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
                  "ollama")
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
             :auth-path #P"/definitely/missing/auth.json")))
      (is (string= "ollama"
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
           `(("CADR_PROVIDER" . "ollama")
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
             :auth-path #P"/definitely/missing/auth.json")))
      (is (string= "ollama"
                   (cadr-cli:provider-config-name config)))
      (is (string= "new-model"
                   (cadr-ai:model-id
                    (cadr-cli:provider-config-model config))))
      (is (string= "https://new.example"
                   (cadr-ai:model-base-url
                    (cadr-cli:provider-config-model config)))))
    (is (string= "" (get-output-stream-string warnings)))))

(test ollama-needs-no-api-key
  (let ((cadr-cli::*environment-function* (constantly nil)))
    (let ((config
            (cadr-cli:resolve-provider-config
             :provider "ollama"
             :config-path #P"/definitely/missing/config.json"
             :auth-path #P"/definitely/missing/auth.json")))
      (is (string= "gpt-oss:20b"
                   (cadr-ai:model-id
                    (cadr-cli:provider-config-model config))))
      (is (eq :none
              (cadr-cli:provider-config-auth-source config))))))

(test stored-oauth-owns-openai-auth-and-selects-codex-endpoint
  (with-test-directory (directory)
    (let ((auth-path (merge-pathnames "auth.json" directory))
          (cadr-cli::*environment-function*
            (lambda (name)
              (and (string= name "OPENAI_API_KEY")
                   "must-not-win"))))
      (cadr-ai:write-auth-credential
       auth-path
       (cadr-ai:make-oauth-credential
        :provider :openai
        :access "oauth-access"
        :refresh "oauth-refresh"
        :expires (+ (cadr-ai::unix-milliseconds) 3600000)
        :account-id "acct"))
      (let ((config
              (cadr-cli:resolve-provider-config
               :provider "openai"
               :config-path #P"/definitely/missing/config.json"
               :auth-path auth-path)))
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
            (lambda (auth-path &key output)
              (declare (ignore output))
              (push :login calls)
              (cadr-ai:write-auth-credential
               auth-path
               (cadr-ai:make-oauth-credential
                :provider :openai
                :access "a" :refresh "r"
                :expires (+ (cadr-ai::unix-milliseconds) 1000000)
                :account-id "acct")))))
      (is (cadr-cli:handle-auth-command
           "/login openai" :auth-path path :output output))
      (is (typep (cadr-ai:read-auth-credential path :openai)
                 'cadr-ai:oauth-credential))
      (is (cadr-cli:handle-auth-command
           "/logout openai" :auth-path path :output output))
      (is (null (cadr-ai:read-auth-credential path :openai)))
      (is (equal '(:login) calls)))))
