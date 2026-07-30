(in-package #:pi-cli/tests)
(in-suite pi-cli-suite)

(test provider-config-resolves-registry-config-and-cli-precedence
  (with-test-directory (directory)
    (let ((config-path (merge-pathnames "config.json" directory))
          (auth-path (merge-pathnames "auth.json" directory))
          (pi-cli::*environment-function*
            (lambda (name)
              (and (string= name "DEEPSEEK_API_KEY")
                   "deepseek-secret"))))
      (write-text
       config-path
       "{\"providers\":{\"deepseek\":{\"base-url\":\"https://config.example/v1\",\"model\":\"deepseek-v4-pro\"}}}")
      (let ((config
              (pi-cli:resolve-provider-config
               :provider "deepseek"
               :config-path config-path
               :auth-path auth-path)))
        (is (string= "deepseek"
                     (pi-cli:provider-config-name config)))
        (is (typep (pi-cli:provider-config-provider config)
                   'pi-ai:openai-completions-provider))
        (is (string= "deepseek-v4-pro"
                     (pi-ai:model-id
                      (pi-cli:provider-config-model config))))
        (is (string= "https://config.example/v1"
                     (pi-ai:model-base-url
                      (pi-cli:provider-config-model config)))))
      (let ((config
              (pi-cli:resolve-provider-config
               :provider "deepseek"
               :model "deepseek-v4-flash"
               :base-url "https://cli.example"
               :config-path config-path
               :auth-path auth-path)))
        (is (string= "deepseek-v4-flash"
                     (pi-ai:model-id
                      (pi-cli:provider-config-model config))))
        (is (string= "https://cli.example"
                     (pi-ai:model-base-url
                      (pi-cli:provider-config-model config))))))))

(test ollama-needs-no-api-key
  (let ((pi-cli::*environment-function* (constantly nil)))
    (let ((config
            (pi-cli:resolve-provider-config
             :provider "ollama"
             :config-path #P"/definitely/missing/config.json"
             :auth-path #P"/definitely/missing/auth.json")))
      (is (string= "gpt-oss:20b"
                   (pi-ai:model-id
                    (pi-cli:provider-config-model config))))
      (is (eq :none
              (pi-cli:provider-config-auth-source config))))))

(test stored-oauth-owns-openai-auth-and-selects-codex-endpoint
  (with-test-directory (directory)
    (let ((auth-path (merge-pathnames "auth.json" directory))
          (pi-cli::*environment-function*
            (lambda (name)
              (and (string= name "OPENAI_API_KEY")
                   "must-not-win"))))
      (pi-ai:write-auth-credential
       auth-path
       (pi-ai:make-oauth-credential
        :provider :openai
        :access "oauth-access"
        :refresh "oauth-refresh"
        :expires (+ (pi-ai::unix-milliseconds) 3600000)
        :account-id "acct"))
      (let ((config
              (pi-cli:resolve-provider-config
               :provider "openai"
               :config-path #P"/definitely/missing/config.json"
               :auth-path auth-path)))
        (is (eq :oauth
                (pi-cli:provider-config-auth-source config)))
        (is (string= "https://chatgpt.com/backend-api"
                     (pi-ai:model-base-url
                      (pi-cli:provider-config-model config))))
        (let ((request
                (pi-ai:build-request
                 (pi-cli:provider-config-provider config)
                 (pi-cli:provider-config-model config)
                 (pi-ai:make-context
                  :messages
                  (list
                   (pi-ai:make-user-message :content "hello")))
                 :stream-p t)))
          (is (string=
               "Bearer oauth-access"
               (cdr
                (assoc
                 "authorization"
                 (pi-ai:request-spec-headers request)
                 :test #'string-equal)))))))))

(test repl-dispatches-slash-commands-without-prompting-model
  (let ((commands nil)
        (prompts nil)
        (output (make-string-output-stream)))
    (pi-cli:run-repl
     (lambda (prompt)
       (push prompt prompts)
       (pi-ai:make-assistant-message
        :content (list (pi-ai:make-text-content :text "ok"))
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
           (pi-cli::*openai-login-function*
            (lambda (auth-path &key output)
              (declare (ignore output))
              (push :login calls)
              (pi-ai:write-auth-credential
               auth-path
               (pi-ai:make-oauth-credential
                :provider :openai
                :access "a" :refresh "r"
                :expires (+ (pi-ai::unix-milliseconds) 1000000)
                :account-id "acct")))))
      (is (pi-cli:handle-auth-command
           "/login openai" :auth-path path :output output))
      (is (typep (pi-ai:read-auth-credential path :openai)
                 'pi-ai:oauth-credential))
      (is (pi-cli:handle-auth-command
           "/logout openai" :auth-path path :output output))
      (is (null (pi-ai:read-auth-credential path :openai)))
      (is (equal '(:login) calls)))))
