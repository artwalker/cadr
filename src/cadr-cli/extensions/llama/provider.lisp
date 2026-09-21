(in-package #:cadr-cli)

(defparameter +llama-provider-id+ :llama.cpp)

(defstruct (llama-provider-controller
            (:constructor %make-llama-provider-controller))
  provider)

(defun llama-environment-value (name environment)
  (let ((entry
          (assoc name environment
                 :test #'string-equal)))
    (or (and entry (cdr entry))
        (uiop:getenv name))))

(defun llama-credential-server-url
    (credential environment)
  (let ((value
          (or
           (and
            (typep credential
                   'cadr-ai:api-key-credential)
            (cdr
             (assoc
              "LLAMA_BASE_URL"
              (cadr-ai:api-key-credential-environment
               credential)
              :test #'string-equal)))
           (llama-environment-value
            "LLAMA_BASE_URL" environment))))
    (and
     (stringp value)
     (plusp
      (length
       (string-trim
        '(#\Space #\Tab #\Newline
          #\Return)
        value)))
     (normalize-llama-server-url value))))

(defun llama-positive-number (value)
  (and (numberp value) (plusp value) value))

(defparameter +llama-thinking-level-map+
  '((:off . "off")
    (:minimal)
    (:low)
    (:medium . "medium")
    (:high)
    (:xhigh)))

(defun llama-template-reasoning-p (chat-template)
  (and (stringp chat-template)
       (not
        (null
         (search "enable_thinking" chat-template)))))

(defun llama-model (info server-url &optional chat-template)
  (let ((context-window
          (or
           (llama-positive-number
            (llama-model-info-context-window info))
           (llama-positive-number
            (llama-model-info-training-context-window
             info))
           128000))
        (reasoning-p
          (llama-template-reasoning-p chat-template)))
    (cadr-ai:make-model
     :id (llama-model-info-id info)
     :name (llama-model-info-id info)
     :provider +llama-provider-id+
     :api :openai-completions
     :base-url (llama-inference-url server-url)
     :reasoning-p reasoning-p
     :thinking-level-map
     (when reasoning-p +llama-thinking-level-map+)
     :supports-images-p
     (not
      (null
       (find
        "image"
        (llama-model-info-input-modalities info)
        :test #'string=)))
     :supports-tools-p t
     :context-window context-window
     :max-tokens context-window
     :compat
     (append
      '(:supports-store nil
        :supports-developer-role nil
        :supports-reasoning-effort nil
        :supports-usage-in-streaming t
        :supports-strict-mode nil
        :max-tokens-field :max-tokens)
      (when reasoning-p
        '(:thinking-format :qwen-chat-template))))))

(defun llama-model-selectable-p (info &optional router-autoload-p)
  (let ((status (llama-model-info-status info)))
    (or (eq status :loaded)
        (eq status :sleeping)
        (and router-autoload-p
             (eq status :unloaded)
             (not (llama-model-info-failed-p info))
             (equal "preset" (llama-model-info-source info))))))

(defun llama-router-autoload-enabled-p (client catalog)
  (unless (find-if
           (lambda (info)
             (and (eq :unloaded (llama-model-info-status info))
                  (equal "preset" (llama-model-info-source info))))
           catalog)
    (return-from llama-router-autoload-enabled-p nil))
  (handler-case
      (eq t (getf (llama-client-props client) :models-autoload))
    (error () nil)))

(defun llama-provider-set-catalog
    (controller catalog server-url &key router-autoload-p)
  (setf
   (cadr-ai:runtime-provider-models
    (llama-provider-controller-provider controller))
   (loop for info in catalog
         when (llama-model-selectable-p info router-autoload-p)
           collect
           (llama-model
            info
            (normalize-llama-server-url
             server-url))))
  controller)

(defun llama-loaded-chat-template (client info)
  (handler-case
      (getf
       (llama-client-props
        client :model (llama-model-info-id info))
       :chat-template)
    (cadr-ai:request-aborted (condition)
      (error condition))
    (error ()
      nil)))

(defun llama-collect-refreshed-models
    (client catalog server-url router-autoload-p context)
  (let ((normalized
          (normalize-llama-server-url server-url))
        (models nil))
    (dolist (info catalog)
      (when (cadr-ai:runtime-refresh-context-aborted-p
             context)
        (return-from llama-collect-refreshed-models
          (values nil nil)))
      (when (llama-model-selectable-p
             info router-autoload-p)
        (let ((template
                (when (eq :loaded
                          (llama-model-info-status info))
                  (llama-loaded-chat-template
                   client info))))
          (when (cadr-ai:runtime-refresh-context-aborted-p
                 context)
            (return-from llama-collect-refreshed-models
              (values nil nil)))
          (push
           (llama-model info normalized template)
           models))))
    (values (nreverse models) t)))

(defun llama-publish-refreshed-catalog
    (controller client catalog server-url
     router-autoload-p context)
  (when (cadr-ai:runtime-refresh-context-aborted-p context)
    (return-from llama-publish-refreshed-catalog nil))
  (multiple-value-bind (models complete-p)
      (llama-collect-refreshed-models
       client catalog server-url
       router-autoload-p context)
    (when (and complete-p
               (not
                (cadr-ai:runtime-refresh-context-aborted-p
                 context)))
      (setf
       (cadr-ai:runtime-provider-models
        (llama-provider-controller-provider controller))
       models)
      (funcall
       (cadr-ai:runtime-refresh-context-store context)
       :write
       (copy-list models))))
  nil)

(defun llama-runtime-request-options (options)
  (loop for (key value) on options by #'cddr
        when
        (member
         key
         '(:max-tokens :temperature :reasoning
           :cache-retention :session-id
           :tool-choice :metadata :abort-p
           :on-payload :transform-headers
           :on-response))
          append (list key value)))

(defun llama-openai-provider (options)
  (cadr-ai:make-openai-completions-provider
   :api-key (getf options :api-key)
   :provider-id +llama-provider-id+
   :authentication-required-p nil))

(defun llama-runtime-complete
    (model context options)
  (apply
   #'cadr-ai:complete-chat
   (llama-openai-provider options)
   model context
   (llama-runtime-request-options options)))

(defun llama-runtime-stream
    (model context on-event &rest options)
  (apply
   #'cadr-ai:stream-chat
   (llama-openai-provider options)
   model context on-event
   (llama-runtime-request-options options)))

(defun make-llama-provider-controller ()
  (let ((controller
          (%make-llama-provider-controller)))
    (setf
     (llama-provider-controller-provider controller)
     (cadr-ai:make-runtime-provider
      :id +llama-provider-id+
      :name "llama.cpp"
      :models nil
      :api-key-auth-p t
      :api-key-login-function
      (lambda (interaction)
        (let* ((configured
                 (or
                  (uiop:getenv "LLAMA_BASE_URL")
                  +default-llama-server-url+))
               (entered-url
                 (cadr-ai:runtime-auth-interaction-prompt
                  interaction
                  (list
                   :type :text
                   :message "llama.cpp server URL"
                   :placeholder configured)))
               (server-url
                 (normalize-llama-server-url
                  (if
                      (plusp
                       (length
                        (string-trim
                         '(#\Space #\Tab #\Newline
                           #\Return)
                         entered-url)))
                      entered-url
                      configured)))
               (entered-key
                 (cadr-ai:runtime-auth-interaction-prompt
                  interaction
                  '(:type :secret
                    :message "API key (optional)")))
               (api-key
                 (string-trim
                  '(#\Space #\Tab #\Newline
                    #\Return)
                  entered-key)))
          (llama-client-list
           (make-llama-client
            :server-url server-url
            :api-key
            (and (plusp (length api-key))
                 api-key)))
          (cadr-ai:make-api-key-credential
           :provider +llama-provider-id+
           :key api-key
           :environment
           (list
            (cons
             "LLAMA_BASE_URL"
             server-url)))))
      :auth-check-function
      (lambda (credential environment)
        (when
            (llama-credential-server-url
             credential environment)
          (cadr-ai:make-runtime-auth-check
           :source
           (if credential
               "Stored credential"
               "LLAMA_BASE_URL")
           :type :api-key)))
      :auth-resolver
      (lambda (credential environment overrides)
        (let* ((override-environment
                 (getf overrides :environment))
               (effective-environment
                 (append
                  override-environment
                  (remove-if
                   (lambda (entry)
                     (assoc
                      (car entry)
                      override-environment
                      :test #'string-equal))
                   environment)))
               (server-url
                 (llama-credential-server-url
                  credential
                  effective-environment)))
          (when server-url
            (let* ((stored-key
                     (and
                      (typep
                       credential
                       'cadr-ai:api-key-credential)
                      (cadr-ai:api-key-credential-key
                       credential)))
                   (key
                     (or
                      (getf overrides :api-key)
                      (and
                       stored-key
                       (plusp (length stored-key))
                       stored-key)
                      (llama-environment-value
                       "LLAMA_API_KEY"
                       effective-environment)
                      "local")))
              (cadr-ai:make-runtime-auth-result
               :api-key key
               :base-url
               (llama-inference-url server-url)
               :environment
               (list
                (cons
                 "LLAMA_BASE_URL"
                 server-url))
               :source
               (if credential
                   "Stored credential"
                   "LLAMA_BASE_URL")
               :type :api-key)))))
      :refresh-context-function
      (lambda (context)
        (let ((store
                (cadr-ai:runtime-refresh-context-store
                 context)))
          (let ((stored (funcall store :read)))
            (when
                (and
                 (listp stored)
                 (every
                  (lambda (model)
                    (and
                     (typep model 'cadr-ai:model)
                     (eq
                      +llama-provider-id+
                      (cadr-ai:model-provider model))
                     (eq
                      :openai-completions
                      (cadr-ai:model-api model))))
                  stored))
              (setf
               (cadr-ai:runtime-provider-models
                (llama-provider-controller-provider
                 controller))
               (copy-list stored))))
          (unless
              (or
               (not
                (cadr-ai:runtime-refresh-context-allow-network-p
                 context))
               (cadr-ai:runtime-refresh-context-aborted-p
                context))
            (let* ((credential
                     (cadr-ai:runtime-refresh-context-credential
                      context))
                   (server-url
                     (llama-credential-server-url
                      credential nil)))
              (when server-url
                (let* ((client
                         (make-llama-client
                          :server-url server-url
                          :api-key
                          (and
                           (typep
                            credential
                            'cadr-ai:api-key-credential)
                           (let ((key
                                   (cadr-ai:api-key-credential-key
                                    credential)))
                             (and
                              (plusp (length key))
                              key)))))
                       (catalog (llama-client-list client)))
                  (unless
                      (cadr-ai:runtime-refresh-context-aborted-p
                       context)
                    (llama-publish-refreshed-catalog
                     controller client catalog server-url
                     (llama-router-autoload-enabled-p
                      client catalog)
                     context))))))))
      :complete-function #'llama-runtime-complete
      :stream-function #'llama-runtime-stream))
    controller))
