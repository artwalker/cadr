(in-package #:cadr-ai)

(defstruct provider-definition
  (id nil :type symbol)
  (name "" :type string)
  (protocol nil :type symbol)
  (base-url "" :type string)
  (auth-types nil :type list)
  (default-model "" :type string)
  (key-environment nil :type (or null string))
  (supports-images-p nil :type boolean)
  (supports-tools-p t :type boolean)
  (reasoning-p nil :type boolean))

(defparameter *provider-definitions* (make-hash-table))

(defun register-provider-definition (definition)
  (setf (gethash (provider-definition-id definition)
                 *provider-definitions*)
        definition)
  definition)

(defun find-provider-definition (id)
  (or (gethash id *provider-definitions*)
      (error 'configuration-error
             :message (format nil "Unknown provider: ~A" id))))

(defun list-provider-definitions ()
  (sort
   (loop for definition being the hash-values
           of *provider-definitions*
         collect definition)
   #'string<
   :key (lambda (definition)
          (symbol-name (provider-definition-id definition)))))

(defun register-built-in-providers ()
  (clrhash *provider-definitions*)
  (dolist
      (definition
       (list
        (make-provider-definition
         :id :anthropic
         :name "Anthropic"
         :protocol :anthropic-messages
         :base-url "https://api.anthropic.com"
         :auth-types '(:api-key :oauth)
         :default-model "claude-opus-4-8"
         :key-environment "ANTHROPIC_API_KEY"
         :supports-images-p t
         :reasoning-p t)
        (make-provider-definition
         :id :openai
         :name "OpenAI"
         :protocol :openai-responses
         :base-url "https://api.openai.com"
         :auth-types '(:api-key :oauth)
         :default-model "gpt-5.5"
         :key-environment "OPENAI_API_KEY"
         :supports-images-p t
         :reasoning-p t)
        (make-provider-definition
         :id :google
         :name "Google"
         :protocol :google-generative-ai
         :base-url "https://generativelanguage.googleapis.com/v1beta"
         :auth-types '(:api-key)
         :default-model "gemini-3.6-flash"
         :key-environment "GEMINI_API_KEY"
         :supports-images-p t
         :reasoning-p t)
        (make-provider-definition
         :id :deepseek
         :name "DeepSeek"
         :protocol :openai-completions
         :base-url "https://api.deepseek.com"
         :auth-types '(:api-key)
         :default-model "deepseek-v4-flash"
         :key-environment "DEEPSEEK_API_KEY"
         :reasoning-p t)
        (make-provider-definition
         :id :ollama
         :name "Ollama"
         :protocol :openai-completions
         :base-url "http://localhost:11434"
         :auth-types '(:api-key)
         :default-model "gpt-oss:20b"
         :key-environment nil
         :reasoning-p t)))
    (register-provider-definition definition)))

(register-built-in-providers)

(defun make-protocol-provider (definition api-key
                               oauth-access-token oauth-account-id)
  (case (provider-definition-protocol definition)
    (:anthropic-messages
     (make-anthropic-provider
      :api-key api-key
      :oauth-access-token oauth-access-token))
    (:openai-responses
     (make-openai-provider
      :api-key api-key
      :oauth-access-token oauth-access-token
      :oauth-account-id oauth-account-id))
    (:openai-completions
     (make-openai-completions-provider
      :api-key api-key
      :authentication-required-p
      (not (null
            (provider-definition-key-environment definition)))))
    (:google-generative-ai
     (make-google-provider :api-key api-key))
    (otherwise
     (error 'configuration-error
            :message
            (format nil "Unsupported provider protocol: ~A"
                    (provider-definition-protocol definition))))))

(defun instantiate-provider
    (id &key api-key oauth-access-token oauth-account-id
             base-url model-id allow-missing-auth-p)
  (let* ((definition (find-provider-definition id))
         (requires-key-p
           (and
            (provider-definition-key-environment definition)
            (not oauth-access-token))))
    (when (and requires-key-p
               (not allow-missing-auth-p)
               (not (non-empty-string-p api-key)))
      (error 'configuration-error
             :message
             (format nil "~A is not set"
                     (provider-definition-key-environment definition))))
    (let* ((resolved-id
             (or model-id
                 (provider-definition-default-model definition)))
           (metadata
             (ignore-errors
               (find-model-metadata id resolved-id))))
      (values
       (make-protocol-provider definition api-key
                               oauth-access-token oauth-account-id)
       (make-model
        :id resolved-id
        :provider id
        :api (provider-definition-protocol definition)
        :base-url (or base-url
                      (provider-definition-base-url definition))
        :max-tokens
        (if metadata
            (model-metadata-max-output-tokens metadata)
            4096)
        :context-window
        (if metadata
            (model-metadata-context-window metadata)
            0)
        :supports-images-p
        (if metadata
            (model-metadata-supports-images-p metadata)
            (provider-definition-supports-images-p definition))
        :supports-tools-p
        (if metadata
            (model-metadata-supports-tools-p metadata)
            (provider-definition-supports-tools-p definition))
        :reasoning-p
        (if metadata
            (model-metadata-reasoning-p metadata)
            (provider-definition-reasoning-p definition)))))))
