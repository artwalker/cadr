(in-package #:cadr-cli)

(defstruct provider-config
  name
  provider
  model
  (auth-source :none :type symbol))

(cadr-core:define-redacted-print-object (provider-config value stream)
  (format stream ":name ~A :auth-source ~A :credentials [REDACTED]"
          (provider-config-name value)
          (provider-config-auth-source value)))

(defparameter *environment-function* #'uiop:getenv)
(defparameter *openai-login-function* #'cadr-ai:login-openai-oauth)
(defparameter *anthropic-login-function* #'cadr-ai:login-anthropic-oauth)

(defun default-config-path ()
  (cadr-core:agent-config-path))

(defun default-auth-path ()
  (cadr-core:agent-auth-path))

(defun environment-value (name)
  (funcall *environment-function* name))

(defun stored-auth-secrets
    (&optional (path (default-auth-path)))
  (if (not (probe-file path))
      nil
      (handler-case
          (let ((secrets nil))
            (maphash
             (lambda (provider object)
               (declare (ignore provider))
               (when (hash-table-p object)
                 (dolist (field '("key" "access" "refresh"))
                   (let ((value
                           (cadr-ai::json-get object field)))
                     (when
                         (and
                          (stringp value)
                          (plusp (length value)))
                       (push value secrets))))))
             (cadr-ai::read-auth-object path))
            secrets)
        (condition () nil))))

(defun provider-config-secrets (config)
  (let ((provider
          (and config
               (provider-config-provider config))))
    (remove-if-not
     #'cadr-ai::non-empty-string-p
     (nconc
      (when provider
        (list
         (cadr-ai::provider-api-key provider)
         (cadr-ai::provider-oauth-access-token
          provider)))
      (loop
        for environment in
        '("ANTHROPIC_API_KEY"
          "OPENAI_API_KEY"
          "GEMINI_API_KEY"
          "DEEPSEEK_API_KEY")
        collect (environment-value environment))
      (stored-auth-secrets)))))

(defun openai-codex-oauth-credential (auth-path)
  (and (probe-file auth-path)
       (let ((credential
               (cadr-ai:read-auth-credential auth-path :openai-codex)))
         (and (typep credential 'cadr-ai:oauth-credential)
              credential))))

(defun configured-provider-name
    (explicit &key (auth-path (default-auth-path)))
  (or explicit
      (environment-value "CADR_PROVIDER")
      (cond
        ((environment-value "ANTHROPIC_API_KEY") "anthropic")
        ((environment-value "OPENAI_API_KEY") "openai")
        ((environment-value "GEMINI_API_KEY") "google")
        ((environment-value "DEEPSEEK_API_KEY") "deepseek")
        ((openai-codex-oauth-credential auth-path) "openai-codex")
        ((and (probe-file auth-path)
              (typep
               (cadr-ai:read-auth-credential auth-path :anthropic)
               'cadr-ai:oauth-credential))
         "anthropic")
        (t nil))))

(defun provider-symbol (name)
  (intern (string-upcase name) :keyword))

(defun provider-default-model (name)
  (cadr-ai:provider-definition-default-model
   (cadr-ai:find-provider-definition (provider-symbol name))))

(defun read-cli-config (path)
  (if (probe-file path)
      (handler-case
          (let ((object
                  (cadr-ai::parse-json
                   (uiop:read-file-string
                    path :external-format :utf-8))))
            (unless (hash-table-p object)
              (error 'cadr-ai:configuration-error
                     :message
                     "config.json must contain a JSON object"))
            object)
        (cadr-ai:cadr-error (condition)
          (error condition))
        (error (cause)
          (error 'cadr-ai:configuration-error
                 :message
                 (format nil "Cannot read config.json: ~A" cause)
                 :cause cause)))
      (cadr-ai::json-object)))

(defun provider-settings (config name)
  (let ((providers (cadr-ai::json-get config "providers")))
    (or (cadr-ai::json-get providers name)
        (cadr-ai::json-object))))

(defparameter +oauth-login-providers+
  '((:openai-codex . cadr-ai:refresh-openai-oauth-credential)
    (:anthropic . cadr-ai:refresh-anthropic-oauth-credential)
    (:github-copilot
     . cadr-ai::refresh-github-copilot-oauth-credential)
    (:kimi-coding . refresh-kimi-coding-oauth-for-cli)
    (:openrouter . cadr-ai::refresh-openrouter-oauth-credential)
    (:radius . refresh-radius-oauth-for-cli)
    (:xai . cadr-ai::refresh-xai-oauth-credential)))

(defun refresh-kimi-coding-oauth-for-cli (credential)
  (cadr-ai::refresh-kimi-oauth-credential credential nil))

(defun refresh-radius-oauth-for-cli (credential)
  (cadr-ai::refresh-radius-oauth-credential
   (or (environment-value "RADIUS_GATEWAY_URL")
       "https://radius.pi.dev")
   credential))

(defun oauth-refresh-function (provider)
  (or (cdr (assoc provider +oauth-login-providers+))
      (error "No OAuth refresh for ~S" provider)))

(defun oauth-login-function (provider)
  (ecase provider
    (:openai-codex *openai-login-function*)
    (:anthropic *anthropic-login-function*)))

(defun resolve-stored-credential (path provider)
  (let ((credential
          (and (probe-file path)
               (cadr-ai:read-auth-credential path provider))))
    (cond
      ((typep credential 'cadr-ai:oauth-credential)
       (let ((refresh
               (cdr (assoc provider +oauth-login-providers+))))
         (if refresh
             (values
              (cadr-ai:resolve-oauth-credential
               path provider refresh)
              :oauth)
             (values nil :none))))
      ((typep credential 'cadr-ai:api-key-credential)
       (values credential :stored-api-key))
      (t
       (values nil :none)))))

(defun resolve-provider-config
    (&key provider model base-url api-key reasoning
          (config-path (default-config-path))
          (auth-path (default-auth-path))
          allow-missing-auth-p)
  (let* ((name
           (configured-provider-name
            provider :auth-path auth-path)))
    (unless name
      (if allow-missing-auth-p
          ;; Defer to the send path, whose missing-key failure carries
          ;; the baseline auth-guidance text.
          (setf name "openai")
          (error 'cadr-ai:configuration-error
                 :message
                 (cadr-ai::no-api-key-found-message "unknown"))))
    (setf name (string-downcase name))
    (let* ((provider-id (provider-symbol name)))
      ;; /login openai stores under openai-codex. Prefer that OAuth over
      ;; an empty openai API-key provider when the caller said openai
      ;; or left the provider unset.
      (when
          (and (eq provider-id :openai)
               (null api-key)
               (null (environment-value "OPENAI_API_KEY"))
               (openai-codex-oauth-credential auth-path))
        (setf name "openai-codex"
              provider-id :openai-codex))
      (let* ((definition
             (cadr-ai:find-provider-definition provider-id))
           (config (read-cli-config config-path))
           (settings (provider-settings config name))
           (resolved-model
             (or model
                 (environment-value "CADR_MODEL")
                 (cadr-ai::json-get settings "model")
                 (cadr-ai:provider-definition-default-model definition)))
           (configured-base-url
             (or base-url
                 (environment-value "CADR_BASE_URL")
                 (cadr-ai::json-get settings "base-url")))
           (credential nil)
           (auth-source :none))
      (unless api-key
        (multiple-value-setq (credential auth-source)
          (resolve-stored-credential auth-path provider-id)))
      (let* ((oauth-p
               (typep credential 'cadr-ai:oauth-credential))
             (resolved-api-key
               (cond
                 ((cadr-ai::non-empty-string-p
                   api-key)
                  (setf auth-source :cli)
                  api-key)
                 ((typep credential 'cadr-ai:api-key-credential)
                  (cadr-ai:api-key-credential-key credential))
                 (oauth-p nil)
                 (t
                  (let ((environment
                          (cadr-ai:provider-definition-key-environment
                           definition)))
                    (and environment
                         (environment-value environment))))))
             (resolved-base-url
               (or configured-base-url
                   (and oauth-p
                        (eq provider-id
                            :openai-codex)
                        "https://chatgpt.com/backend-api")
                   (and oauth-p
                        (eq provider-id :github-copilot)
                        (cadr-ai:github-copilot-base-url
                         (cadr-ai:oauth-credential-access
                          credential)
                         (cadr-ai::github-copilot-metadata-value
                          credential "enterpriseUrl")))
                   (cadr-ai:provider-definition-base-url definition))))
        (when (and (eq auth-source :none)
                   (cadr-ai::non-empty-string-p
                    resolved-api-key))
          (setf auth-source :environment))
        (multiple-value-bind (provider-object model-object)
            (cadr-ai:instantiate-provider
             provider-id
             :api-key resolved-api-key
             :oauth-access-token
             (and oauth-p
                  (cadr-ai:oauth-credential-access credential))
             :oauth-account-id
             (and oauth-p
                  (cadr-ai:oauth-credential-account-id credential))
             :base-url resolved-base-url
             :model-id resolved-model
             :reasoning reasoning
             :allow-missing-auth-p allow-missing-auth-p)
          (make-provider-config
           :name name
           :provider provider-object
           :model model-object
           :auth-source auth-source)))))))

(defun split-command-line (line)
  (remove ""
          (uiop:split-string
           (string-trim '(#\Space #\Tab) line)
           :separator '(#\Space #\Tab))
          :test #'string=))

(defun parse-auth-provider (value)
  (let* ((provider
           (and value
                (provider-symbol
                 (string-downcase value))))
         (identity
           (case provider
             (:openai :openai-codex)
             (:openai-codex :openai-codex)
             (:anthropic :anthropic)
             (otherwise nil))))
    (unless identity
      (error 'cadr-ai:configuration-error
             :message
             "OAuth provider must be openai or anthropic"))
    identity))

(defun handle-auth-command
    (line &key
            (auth-path (default-auth-path))
            (output *standard-output*)
            auth-url-function
            auth-prompt-function
            on-change)
  (let* ((parts (split-command-line line))
         (command (first parts)))
    (cond
      ((string= command "/login")
       (let ((provider (parse-auth-provider (second parts))))
         (funcall
          (oauth-login-function provider)
          auth-path
          :output output
          :auth-url-function auth-url-function
          :auth-prompt-function auth-prompt-function)
         (format output "~(~A~) login stored in ~A~%"
                 provider (namestring auth-path))
         (when on-change
           (funcall on-change provider :login))
         (finish-output output)
         t))
      ((string= command "/logout")
       (let ((provider (parse-auth-provider (second parts))))
         (cadr-ai:delete-auth-credential auth-path provider)
         (format output "~(~A~) logged out~%" provider)
         (when on-change
           (funcall on-change provider :logout))
         (finish-output output)
         t))
      (t nil))))
