(in-package #:pi-cli)

(defstruct provider-config
  name
  provider
  model
  (auth-source :none :type symbol))

(defparameter *environment-function* #'uiop:getenv)
(defparameter *openai-login-function* #'pi-ai:login-openai-oauth)
(defparameter *anthropic-login-function* #'pi-ai:login-anthropic-oauth)

(defun default-config-path ()
  (merge-pathnames ".pi-cl/config.json"
                   (user-homedir-pathname)))

(defun default-auth-path ()
  (merge-pathnames ".pi-cl/auth.json"
                   (user-homedir-pathname)))

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
                           (pi-ai::json-get object field)))
                     (when
                         (and
                          (stringp value)
                          (plusp (length value)))
                       (push value secrets))))))
             (pi-ai::read-auth-object path))
            secrets)
        (condition () nil))))

(defun provider-config-secrets (config)
  (let ((provider
          (and config
               (provider-config-provider config))))
    (remove-if-not
     #'pi-ai::non-empty-string-p
     (nconc
      (when provider
        (list
         (pi-ai::provider-api-key provider)
         (pi-ai::provider-oauth-access-token
          provider)))
      (loop
        for environment in
        '("ANTHROPIC_API_KEY"
          "OPENAI_API_KEY"
          "GEMINI_API_KEY"
          "DEEPSEEK_API_KEY")
        collect (environment-value environment))
      (stored-auth-secrets)))))

(defun configured-provider-name (explicit)
  (or explicit
      (environment-value "PI_CL_PROVIDER")
      (cond
        ((environment-value "ANTHROPIC_API_KEY") "anthropic")
        ((environment-value "OPENAI_API_KEY") "openai")
        ((environment-value "GEMINI_API_KEY") "google")
        ((environment-value "DEEPSEEK_API_KEY") "deepseek")
        (t nil))))

(defun provider-symbol (name)
  (intern (string-upcase name) :keyword))

(defun provider-default-model (name)
  (pi-ai:provider-definition-default-model
   (pi-ai:find-provider-definition (provider-symbol name))))

(defun read-cli-config (path)
  (if (probe-file path)
      (handler-case
          (let ((object
                  (pi-ai::parse-json
                   (uiop:read-file-string
                    path :external-format :utf-8))))
            (unless (hash-table-p object)
              (error 'pi-ai:configuration-error
                     :message
                     "config.json must contain a JSON object"))
            object)
        (pi-ai:pi-error (condition)
          (error condition))
        (error (cause)
          (error 'pi-ai:configuration-error
                 :message
                 (format nil "Cannot read config.json: ~A" cause)
                 :cause cause)))
      (pi-ai::json-object)))

(defun provider-settings (config name)
  (let ((providers (pi-ai::json-get config "providers")))
    (or (pi-ai::json-get providers name)
        (pi-ai::json-object))))

(defun oauth-refresh-function (provider)
  (ecase provider
    (:openai #'pi-ai:refresh-openai-oauth-credential)
    (:anthropic #'pi-ai:refresh-anthropic-oauth-credential)))

(defun resolve-stored-credential (path provider)
  (let ((credential
          (and (probe-file path)
               (pi-ai:read-auth-credential path provider))))
    (cond
      ((typep credential 'pi-ai:oauth-credential)
       (unless (member provider '(:openai :anthropic))
         (error 'pi-ai:configuration-error
                :message
                (format nil
                        "OAuth is not supported for provider ~A"
                        provider)))
       (values
        (pi-ai:resolve-oauth-credential
         path provider (oauth-refresh-function provider))
        :oauth))
      ((typep credential 'pi-ai:api-key-credential)
       (values credential :stored-api-key))
      (t
       (values nil :none)))))

(defun resolve-provider-config
    (&key provider model base-url
          (config-path (default-config-path))
          (auth-path (default-auth-path))
          allow-missing-auth-p)
  (let* ((name (configured-provider-name provider)))
    (unless name
      (error 'pi-ai:configuration-error
             :message
             "No provider configured; use --provider or set a provider API key"))
    (setf name (string-downcase name))
    (let* ((provider-id (provider-symbol name))
           (definition
             (pi-ai:find-provider-definition provider-id))
           (config (read-cli-config config-path))
           (settings (provider-settings config name))
           (resolved-model
             (or model
                 (environment-value "PI_CL_MODEL")
                 (pi-ai::json-get settings "model")
                 (pi-ai:provider-definition-default-model definition)))
           (configured-base-url
             (or base-url
                 (environment-value "PI_CL_BASE_URL")
                 (pi-ai::json-get settings "base-url")))
           (credential nil)
           (auth-source :none))
      (multiple-value-setq (credential auth-source)
        (resolve-stored-credential auth-path provider-id))
      (let* ((oauth-p
               (typep credential 'pi-ai:oauth-credential))
             (api-key
               (cond
                 ((typep credential 'pi-ai:api-key-credential)
                  (pi-ai:api-key-credential-key credential))
                 (oauth-p nil)
                 (t
                  (let ((environment
                          (pi-ai:provider-definition-key-environment
                           definition)))
                    (and environment
                         (environment-value environment))))))
             (resolved-base-url
               (or configured-base-url
                   (and oauth-p
                        (eq provider-id :openai)
                        "https://chatgpt.com/backend-api")
                   (pi-ai:provider-definition-base-url definition))))
        (when (and (eq auth-source :none)
                   (pi-ai::non-empty-string-p api-key))
          (setf auth-source :environment))
        (multiple-value-bind (provider-object model-object)
            (pi-ai:instantiate-provider
             provider-id
             :api-key api-key
             :oauth-access-token
             (and oauth-p
                  (pi-ai:oauth-credential-access credential))
             :oauth-account-id
             (and oauth-p
                  (pi-ai:oauth-credential-account-id credential))
             :base-url resolved-base-url
             :model-id resolved-model
             :allow-missing-auth-p allow-missing-auth-p)
          (make-provider-config
           :name name
           :provider provider-object
           :model model-object
           :auth-source auth-source))))))

(defun split-command-line (line)
  (remove ""
          (uiop:split-string
           (string-trim '(#\Space #\Tab) line)
           :separator '(#\Space #\Tab))
          :test #'string=))

(defun parse-auth-provider (value)
  (let ((provider
          (and value
               (provider-symbol (string-downcase value)))))
    (unless (member provider '(:openai :anthropic))
      (error 'pi-ai:configuration-error
             :message
             "OAuth provider must be openai or anthropic"))
    provider))

(defun handle-auth-command
    (line &key
            (auth-path (default-auth-path))
            (output *standard-output*)
            on-change)
  (let* ((parts (split-command-line line))
         (command (first parts)))
    (cond
      ((string= command "/login")
       (let ((provider (parse-auth-provider (second parts))))
         (ecase provider
           (:openai
            (funcall *openai-login-function*
                     auth-path :output output))
           (:anthropic
            (funcall *anthropic-login-function*
                     auth-path :output output)))
         (format output "~(~A~) login stored in ~A~%"
                 provider (namestring auth-path))
         (when on-change (funcall on-change provider))
         (finish-output output)
         t))
      ((string= command "/logout")
       (let ((provider (parse-auth-provider (second parts))))
         (pi-ai:delete-auth-credential auth-path provider)
         (format output "~(~A~) logged out~%" provider)
         (when on-change (funcall on-change provider))
         (finish-output output)
         t))
      (t nil))))
