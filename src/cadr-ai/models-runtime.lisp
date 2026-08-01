(in-package #:cadr-ai)

(define-condition models-runtime-error (cadr-error)
  ((code
    :initarg :code
    :reader models-runtime-error-code)))

(defstruct (memory-credential-store
            (:constructor %make-memory-credential-store))
  (entries (make-hash-table) :type hash-table)
  (lock (sb-thread:make-mutex
         :name "cadr-ai memory credential store")))

(defun make-memory-credential-store ()
  (%make-memory-credential-store))

(defun credential-store-read (store provider-id)
  (sb-thread:with-mutex ((memory-credential-store-lock store))
    (gethash provider-id
             (memory-credential-store-entries store))))

(defun credential-store-modify (store provider-id function)
  (sb-thread:with-mutex ((memory-credential-store-lock store))
    (let* ((entries (memory-credential-store-entries store))
           (current (gethash provider-id entries))
           (next (funcall function current)))
      (when next
        (setf (gethash provider-id entries) next))
      (or next current))))

(defun credential-store-delete (store provider-id)
  (sb-thread:with-mutex ((memory-credential-store-lock store))
    (remhash provider-id
             (memory-credential-store-entries store)))
  nil)

(defun credential-type (credential)
  (etypecase credential
    (api-key-credential :api-key)
    (oauth-credential :oauth)))

(defun credential-store-list (store)
  (sb-thread:with-mutex ((memory-credential-store-lock store))
    (sort
     (loop for provider-id being the hash-keys
             of (memory-credential-store-entries store)
           using (hash-value credential)
           collect (cons provider-id
                         (credential-type credential)))
     #'string<
     :key (lambda (entry)
            (symbol-name (car entry))))))

(defstruct runtime-auth-result
  api-key
  (headers nil :type list)
  base-url
  (environment nil :type list)
  source
  type)

(defstruct runtime-auth-check
  source
  type)

(defstruct runtime-auth-interaction
  prompt-function
  notify-function
  abort-p)

(defun valid-runtime-auth-prompt-p (prompt)
  (and
   (listp prompt)
   (member (getf prompt :type) '(:text :secret :select :manual-code))
   (stringp (getf prompt :message))
   (or (null (getf prompt :placeholder))
       (stringp (getf prompt :placeholder)))
   (if (eq :select (getf prompt :type))
       (let ((options (getf prompt :options)))
         (and
          (listp options)
          (plusp (length options))
          (every
           (lambda (option)
             (and (listp option)
                  (stringp (getf option :id))
                  (stringp (getf option :label))
                  (or (null (getf option :description))
                      (stringp (getf option :description)))))
           options)))
       (null (getf prompt :options)))))

(defun valid-runtime-auth-event-p (event)
  (and
   (listp event)
   (case (getf event :type)
     ((:info :progress)
      (stringp (getf event :message)))
     (:auth-url
      (and (stringp (getf event :url))
           (or (null (getf event :instructions))
               (stringp (getf event :instructions)))))
     (:device-code
      (and (stringp (getf event :user-code))
           (stringp (getf event :verification-uri))
           (or (null (getf event :interval-seconds))
               (numberp (getf event :interval-seconds)))
           (or (null (getf event :expires-in-seconds))
               (numberp (getf event :expires-in-seconds)))))
     (otherwise nil))))

(defun runtime-auth-interaction-aborted-p (interaction)
  (let ((abort-p
          (runtime-auth-interaction-abort-p interaction)))
    (and abort-p
         (not (null (funcall abort-p))))))

(defun runtime-auth-interaction-prompt (interaction prompt)
  (unless (valid-runtime-auth-prompt-p prompt)
    (error 'models-runtime-error
           :code :auth
           :message "Invalid runtime authentication prompt"))
  (when (runtime-auth-interaction-aborted-p interaction)
    (error 'models-runtime-error
           :code :auth
           :message "Runtime authentication was aborted"))
  (let ((function
          (runtime-auth-interaction-prompt-function
           interaction)))
    (unless function
      (error 'models-runtime-error
             :code :auth
             :message "Runtime authentication has no prompt function"))
    (funcall function (copy-list prompt))))

(defun runtime-auth-interaction-notify (interaction event)
  (unless (valid-runtime-auth-event-p event)
    (error 'models-runtime-error
           :code :auth
           :message "Invalid runtime authentication event"))
  (let ((function
          (runtime-auth-interaction-notify-function
           interaction)))
    (when function
      (funcall function (copy-list event))))
  nil)

(defstruct runtime-refresh-context
  credential
  store
  (allow-network-p t :type boolean)
  (force-p nil :type boolean)
  abort-p)

(defun runtime-refresh-context-aborted-p (context)
  (let ((abort-p
          (runtime-refresh-context-abort-p context)))
    (and abort-p
         (not (null (funcall abort-p))))))

(defstruct runtime-provider
  (id nil :type symbol)
  (name "" :type string)
  (models nil :type list)
  models-function
  (api-key-auth-p nil :type boolean)
  (oauth-auth-p nil :type boolean)
  api-key-login-function
  auth-check-function
  auth-resolver
  oauth-login-function
  oauth-refresh-function
  oauth-to-auth-function
  refresh-function
  refresh-context-function
  filter-function
  complete-function
  stream-function)

(defstruct models-refresh-result
  (aborted-p nil :type boolean)
  (errors nil :type list))

(defstruct (models-runtime
            (:constructor %make-models-runtime))
  (provider-table (make-hash-table) :type hash-table)
  (provider-order nil :type list)
  (credential-store (make-memory-credential-store))
  (model-store (make-hash-table) :type hash-table)
  (environment nil :type list))

(defun make-models-runtime (&key credential-store model-store environment)
  (%make-models-runtime
   :credential-store
   (or credential-store (make-memory-credential-store))
   :model-store (or model-store (make-hash-table))
   :environment environment))

(defun models-runtime-set-provider (runtime provider)
  (let ((id (runtime-provider-id provider)))
    (unless (gethash id (models-runtime-provider-table runtime))
      (setf (models-runtime-provider-order runtime)
            (append (models-runtime-provider-order runtime)
                    (list id))))
    (setf (gethash id (models-runtime-provider-table runtime))
          provider))
  provider)

(defun models-runtime-delete-provider (runtime provider-id)
  (remhash provider-id (models-runtime-provider-table runtime))
  (setf (models-runtime-provider-order runtime)
        (remove provider-id
                (models-runtime-provider-order runtime)))
  nil)

(defun models-runtime-clear-providers (runtime)
  (clrhash (models-runtime-provider-table runtime))
  (setf (models-runtime-provider-order runtime) nil)
  nil)

(defun models-runtime-provider (runtime provider-id)
  (gethash provider-id (models-runtime-provider-table runtime)))

(defun models-runtime-providers (runtime)
  (loop for id in (models-runtime-provider-order runtime)
        for provider =
        (gethash id (models-runtime-provider-table runtime))
        when provider collect provider))

(defun runtime-provider-current-models (provider)
  (handler-case
      (copy-list
       (if (runtime-provider-models-function provider)
           (funcall
            (runtime-provider-models-function provider))
           (runtime-provider-models provider)))
    (error () nil)))

(defun models-runtime-models (runtime &optional provider-id)
  (if provider-id
      (let ((provider
              (models-runtime-provider runtime provider-id)))
        (if provider
            (runtime-provider-current-models provider)
            nil))
      (mapcan #'runtime-provider-current-models
              (models-runtime-providers runtime))))

(defun models-runtime-model (runtime provider-id model-id)
  (find model-id
        (models-runtime-models runtime provider-id)
        :key #'model-id
        :test #'string=))

(defun runtime-credential (runtime provider-id)
  (handler-case
      (credential-store-read
       (models-runtime-credential-store runtime)
       provider-id)
    (error (cause)
      (error 'models-runtime-error
             :code :auth
             :message
             (format nil
                     "Credential store read failed for ~A"
                     provider-id)
             :cause cause))))

(defun oauth-credential-expiring-p
    (credential &optional (minimum-validity-milliseconds 300000))
  (<= (oauth-credential-expires credential)
      (+ (unix-milliseconds)
         minimum-validity-milliseconds)))

(defun runtime-refresh-oauth
    (runtime provider)
  (let ((refresh
          (runtime-provider-oauth-refresh-function provider)))
    (unless refresh
      (return-from runtime-refresh-oauth nil))
    (handler-case
        (credential-store-modify
         (models-runtime-credential-store runtime)
         (runtime-provider-id provider)
         (lambda (current)
           (cond
             ((not (typep current 'oauth-credential))
              nil)
             ((not (oauth-credential-expiring-p current))
              nil)
             (t
              (let ((refreshed
                      (funcall refresh current)))
                (unless (typep refreshed 'oauth-credential)
                  (error "OAuth refresh returned an invalid credential"))
                refreshed)))))
      (error (cause)
        (error 'models-runtime-error
               :code :oauth
               :message
               (format nil
                       "OAuth refresh failed for ~A"
                       (runtime-provider-id provider))
               :cause cause)))))

(defun runtime-resolve-api-key-auth
    (runtime provider credential overrides)
  (unless (runtime-provider-api-key-auth-p provider)
    (return-from runtime-resolve-api-key-auth nil))
  (let ((resolver
          (runtime-provider-auth-resolver provider)))
    (if resolver
        (handler-case
            (funcall resolver
                     credential
                     (models-runtime-environment runtime)
                     overrides)
          (error (cause)
            (error 'models-runtime-error
                   :code :auth
                   :message
                   (format nil
                           "API key auth resolution failed for ~A"
                           (runtime-provider-id provider))
                   :cause cause)))
        (when (and (typep credential 'api-key-credential)
                   (non-empty-string-p
                    (api-key-credential-key credential)))
          (make-runtime-auth-result
           :api-key (api-key-credential-key credential)
           :environment
           (api-key-credential-environment credential)
           :source "Stored API key"
           :type :api-key)))))

(defun models-runtime-auth
    (runtime provider-or-model
     &key api-key environment)
  (let* ((provider-id
           (if (typep provider-or-model 'model)
               (model-provider provider-or-model)
               provider-or-model))
         (provider
           (models-runtime-provider runtime provider-id)))
    (unless provider
      (return-from models-runtime-auth nil))
    (let* ((stored (runtime-credential runtime provider-id))
           (explicit
             (and api-key
                  (make-api-key-credential
                   :provider provider-id
                   :key api-key
                   :environment environment)))
           (credential (or explicit stored))
           (result nil))
      (setf
       result
       (if (typep credential 'oauth-credential)
           (progn
             (unless (runtime-provider-oauth-auth-p provider)
               (return-from models-runtime-auth nil))
             (let ((effective
                     (if (oauth-credential-expiring-p credential)
                         (runtime-refresh-oauth runtime provider)
                         credential)))
               (when effective
                 (if (runtime-provider-oauth-to-auth-function
                      provider)
                     (funcall
                      (runtime-provider-oauth-to-auth-function
                       provider)
                      effective)
                     (make-runtime-auth-result
                      :api-key
                      (oauth-credential-access effective)
                      :source "OAuth"
                      :type :oauth)))))
           (runtime-resolve-api-key-auth
            runtime provider credential
            (list :api-key api-key
                  :environment environment))))
      (when (and result
                 (typep provider-or-model 'model)
                 (model-headers provider-or-model))
        (setf
         (runtime-auth-result-headers result)
         (merge-runtime-headers
          (runtime-auth-result-headers result)
          (model-headers provider-or-model))))
      result)))

(defun models-runtime-check-auth (runtime provider-id)
  (let ((provider
          (models-runtime-provider runtime provider-id)))
    (unless provider
      (return-from models-runtime-check-auth nil))
    (let ((credential
            (runtime-credential runtime provider-id)))
      (cond
        ((typep credential 'oauth-credential)
         (when (runtime-provider-oauth-auth-p provider)
           (make-runtime-auth-check
            :source "OAuth" :type :oauth)))
        (t
         (let ((check
                 (runtime-provider-auth-check-function
                  provider)))
           (if check
               (handler-case
                   (funcall
                    check credential
                    (models-runtime-environment runtime))
                 (error (cause)
                   (error 'models-runtime-error
                          :code :auth
                          :message
                          (format nil
                                  "API key auth check failed for provider ~A"
                                  provider-id)
                          :cause cause)))
               (let ((auth
                       (runtime-resolve-api-key-auth
                        runtime provider credential nil)))
                 (when auth
                   (make-runtime-auth-check
                    :source (runtime-auth-result-source auth)
                    :type :api-key))))))))))

(defun models-runtime-login-api-key
    (runtime provider-id interaction)
  (let ((provider
          (models-runtime-provider runtime provider-id)))
    (unless provider
      (error 'models-runtime-error
             :code :provider
             :message
             (format nil "Unknown provider: ~A" provider-id)))
    (let ((login
            (runtime-provider-api-key-login-function
             provider)))
      (unless login
        (error 'models-runtime-error
               :code :auth
               :message
               (format nil
                       "~A does not support API key login"
                       (runtime-provider-name provider))))
      (let ((credential
              (handler-case
                  (funcall login interaction)
                (models-runtime-error (condition)
                  (error condition))
                (error (cause)
                  (error 'models-runtime-error
                         :code :auth
                         :message
                         (format nil
                                 "API key login failed for ~A"
                                 provider-id)
                         :cause cause)))))
        (unless (typep credential 'api-key-credential)
          (error 'models-runtime-error
                 :code :auth
                 :message
                 (format nil
                         "API key login returned an invalid credential for ~A"
                         provider-id)))
        (setf
         (api-key-credential-provider credential)
         provider-id)
        (handler-case
            (credential-store-modify
             (models-runtime-credential-store runtime)
             provider-id
             (lambda (current)
               (declare (ignore current))
               credential))
          (error (cause)
            (error 'models-runtime-error
                   :code :auth
                   :message
                   (format nil
                           "Credential store modify failed for ~A"
                           provider-id)
                   :cause cause)))
        credential))))

(defun models-runtime-provider-for-login (runtime provider-id)
  (or (models-runtime-provider runtime provider-id)
      (error 'models-runtime-error
             :code :provider
             :message (format nil "Unknown provider: ~A" provider-id))))

(defun persist-runtime-login-credential
    (runtime provider-id credential expected-type)
  (unless (typep credential expected-type)
    (error 'models-runtime-error
           :code :auth
           :message
           (format nil "Login returned an invalid credential for ~A"
                   provider-id)))
  (etypecase credential
    (api-key-credential
     (setf (api-key-credential-provider credential) provider-id))
    (oauth-credential
     (setf (oauth-credential-provider credential) provider-id)))
  (handler-case
      (credential-store-modify
       (models-runtime-credential-store runtime)
       provider-id
       (lambda (current)
         (declare (ignore current))
         credential))
    (error (cause)
      (error 'models-runtime-error
             :code :auth
             :message
             (format nil "Credential store modify failed for ~A"
                     provider-id)
             :cause cause)))
  credential)

(defun models-runtime-login-oauth
    (runtime provider-id interaction)
  (let* ((provider
           (models-runtime-provider-for-login runtime provider-id))
         (login (runtime-provider-oauth-login-function provider)))
    (unless login
      (error 'models-runtime-error
             :code :auth
             :message
             (format nil "~A does not support OAuth login"
                     (runtime-provider-name provider))))
    (persist-runtime-login-credential
     runtime provider-id
     (handler-case
         (funcall login interaction)
       (models-runtime-error (condition)
         (error condition))
       (error (cause)
         (error 'models-runtime-error
                :code :auth
                :message
                (format nil "OAuth login failed for ~A" provider-id)
                :cause cause)))
     'oauth-credential)))

(defun models-runtime-login
    (runtime provider-id auth-type interaction)
  (ecase auth-type
    (:api-key
     (models-runtime-login-api-key runtime provider-id interaction))
    (:oauth
     (models-runtime-login-oauth runtime provider-id interaction))))

(defun models-runtime-available-models
    (runtime &optional provider-id)
  (let ((providers
          (if provider-id
              (let ((provider
                      (models-runtime-provider runtime provider-id)))
                (if provider (list provider) nil))
              (models-runtime-providers runtime))))
    (mapcan
     (lambda (provider)
       (let ((check
               (models-runtime-check-auth
                runtime
                (runtime-provider-id provider))))
         (if check
             (let* ((models
                      (runtime-provider-current-models provider))
                    (filter
                      (runtime-provider-filter-function provider)))
               (if filter
                   (copy-list
                    (funcall filter models
                             (runtime-credential
                              runtime
                              (runtime-provider-id provider))))
                   models))
             nil)))
     providers)))

(defun make-model-store-view (runtime provider-id)
  (lambda (operation &optional value)
    (ecase operation
      (:read
       (gethash provider-id
                (models-runtime-model-store runtime)))
      (:write
       (setf
        (gethash provider-id
                 (models-runtime-model-store runtime))
        value))
      (:delete
       (remhash provider-id
                (models-runtime-model-store runtime))))))

(defun runtime-refresh-credential
    (runtime provider allow-network)
  (let ((stored
          (runtime-credential
           runtime (runtime-provider-id provider))))
    (cond
      ((typep stored 'oauth-credential)
       (cond
         ((not (runtime-provider-oauth-auth-p provider)) nil)
         ((or (not allow-network)
              (not (oauth-credential-expiring-p stored 0)))
          stored)
         (t
          (runtime-refresh-oauth runtime provider))))
      ((runtime-provider-api-key-auth-p provider)
       (let ((auth
               (runtime-resolve-api-key-auth
                runtime provider stored nil)))
         (when auth
           (or stored
               (make-api-key-credential
                :provider (runtime-provider-id provider)
                :key (or
                      (runtime-auth-result-api-key auth)
                      "")
                :environment
                (runtime-auth-result-environment auth))))))
      (t nil))))

(defun models-runtime-refresh
    (runtime &key (allow-network t) force abort-p)
  (let ((errors nil)
        (aborted-p nil))
    (dolist (provider (models-runtime-providers runtime))
      (when (and abort-p (funcall abort-p))
        (setf aborted-p t)
        (return))
      (let ((refresh
              (runtime-provider-refresh-function provider))
            (refresh-context
              (runtime-provider-refresh-context-function
               provider)))
        (when (or refresh refresh-context)
          (let* ((provider-id
                   (runtime-provider-id provider))
                 (stored
                   (runtime-credential runtime provider-id))
                 (store
                   (make-model-store-view runtime provider-id)))
            (handler-case
                (let ((credential
                        (runtime-refresh-credential
                         runtime provider allow-network)))
                  (when credential
                    (if refresh-context
                        (funcall
                         refresh-context
                         (make-runtime-refresh-context
                          :credential credential
                          :store store
                          :allow-network-p allow-network
                          :force-p (not (null force))
                          :abort-p abort-p))
                        (funcall refresh credential store
                                 allow-network force))))
              (error (cause)
                (push (cons provider-id cause) errors)
                (ignore-errors
                  (if refresh-context
                      (funcall
                       refresh-context
                       (make-runtime-refresh-context
                        :credential stored
                        :store store
                        :allow-network-p nil
                        :force-p nil
                        :abort-p abort-p))
                      (funcall refresh
                               stored store nil nil)))))))))
    (make-models-refresh-result
     :aborted-p aborted-p
     :errors (nreverse errors))))

(defun merge-runtime-headers (base override)
  (append
   (mapcar
    (lambda (entry)
      (or (find (car entry) override
                :key #'car :test #'string-equal)
          entry))
    base)
   (remove-if
    (lambda (entry)
      (find (car entry) base
            :key #'car :test #'string-equal))
    override)))

(defun copy-runtime-model-with-base-url (model base-url)
  (make-model
   :id (model-id model)
   :name (model-name model)
   :provider (model-provider model)
   :api (model-api model)
   :base-url base-url
   :max-tokens (model-max-tokens model)
   :context-window (model-context-window model)
   :supports-images-p (model-supports-images-p model)
   :supports-tools-p (model-supports-tools-p model)
   :reasoning-p (model-reasoning-p model)
   :thinking-level-map (model-thinking-level-map model)
   :headers (model-headers model)
   :compat (model-compat model)))

(defun models-runtime-request
    (runtime model context stream-p on-event options)
  (handler-case
      (let ((provider
              (models-runtime-provider
               runtime (model-provider model))))
        (unless provider
          (error 'models-runtime-error
                 :code :provider
                 :message
                 (format nil "Unknown provider: ~A"
                         (model-provider model))))
        (let* ((api-key (getf options :api-key))
               (environment (getf options :environment))
               (auth
                 (models-runtime-auth
                  runtime model
                  :api-key api-key
                  :environment environment)))
          (unless auth
            (error 'models-runtime-error
                   :code :auth
                   :message
                   (format nil
                           "Provider is not configured: ~A"
                           (model-provider model))))
          (let* ((request-model
                   (if (runtime-auth-result-base-url auth)
                       (copy-runtime-model-with-base-url
                        model
                        (runtime-auth-result-base-url auth))
                       model))
                 (request-options (copy-list options))
                 (headers
                   (merge-runtime-headers
                    (runtime-auth-result-headers auth)
                    (getf options :headers))))
            (setf (getf request-options :api-key)
                  (or api-key
                      (runtime-auth-result-api-key auth))
                  (getf request-options :auth-type)
                  (runtime-auth-result-type auth)
                  (getf request-options :headers)
                  headers
                  (getf request-options :environment)
                  (append environment
                          (remove-if
                           (lambda (entry)
                             (assoc (car entry) environment
                                    :test #'string-equal))
                           (runtime-auth-result-environment auth))))
            (if stream-p
                (let ((stream
                        (runtime-provider-stream-function provider)))
                  (unless stream
                    (error 'models-runtime-error
                           :code :stream
                           :message
                           (format nil
                                   "Provider ~A has no stream implementation"
                                   (runtime-provider-id provider))))
                  (apply stream request-model context
                         on-event request-options))
                (let ((complete
                        (runtime-provider-complete-function provider)))
                  (unless complete
                    (error 'models-runtime-error
                           :code :stream
                           :message
                           (format nil
                                   "Provider ~A has no complete implementation"
                                   (runtime-provider-id provider))))
                  (funcall complete
                           request-model context
                           request-options))))))
    (error (condition)
      (let ((message
              (error-assistant-message model condition)))
        (when (and stream-p on-event)
          (funcall
           on-event
           (make-stream-event
            :type :error
            :message message
            :reason
            (assistant-message-stop-reason message))))
        message))))

(defun models-runtime-complete
    (runtime model context &rest options)
  (models-runtime-request
   runtime model context nil nil options))

(defun models-runtime-stream
    (runtime model context on-event &rest options)
  (models-runtime-request
   runtime model context t on-event options))

(defstruct faux-state
  (call-count 0 :type (integer 0 *)))

(defstruct (faux-handle
            (:constructor %make-faux-handle))
  provider
  (api :faux :type symbol)
  (provider-id :faux :type symbol)
  (models nil :type list)
  (responses nil :type list)
  (state (make-faux-state) :type faux-state)
  (prompt-cache (make-hash-table :test #'equal)
                :type hash-table)
  (token-min 3 :type (integer 1 *))
  (token-max 5 :type (integer 1 *)))

(defun faux-text (text)
  (make-text-content :text text))

(defun faux-thinking (thinking)
  (make-thinking-content :thinking thinking))

(defun faux-tool-call (name arguments &key id)
  (make-tool-call
   :id (or id (format nil "tool:~A" (uuid-v7)))
   :name name
   :arguments arguments))

(defun faux-assistant-message
    (content &key (stop-reason :stop)
                     error-message response-id timestamp)
  (make-assistant-message
   :content
   (cond
     ((stringp content) (list (faux-text content)))
     ((or (typep content 'text-content)
          (typep content 'thinking-content)
          (typep content 'tool-call))
      (list content))
     (t (copy-list content)))
   :api :faux
   :provider :faux
   :model "faux-1"
   :usage (make-usage)
   :stop-reason stop-reason
   :error-message error-message
   :response-id response-id
   :timestamp (or timestamp (unix-milliseconds))))

(defun faux-make-model (api provider-id definition)
  (make-model
   :id (or (getf definition :id) "faux-1")
   :name (or (getf definition :name)
             (getf definition :id)
             "Faux Model")
   :api api
   :provider provider-id
   :base-url "http://localhost:0"
   :reasoning-p (not (null (getf definition :reasoning-p)))
   :supports-images-p
   (if (member :supports-images-p definition)
       (not (null (getf definition :supports-images-p)))
       t)
   :context-window
   (or (getf definition :context-window) 128000)
   :max-tokens (or (getf definition :max-tokens) 16384)))

(defun make-faux-provider
    (&key (api :faux)
          (provider-id :faux)
          model-definitions
          (token-min 3)
          (token-max 5))
  (let* ((definitions
           (or model-definitions
               '((:id "faux-1"
                  :name "Faux Model"
                  :reasoning-p nil))))
         (models
           (mapcar
            (lambda (definition)
              (faux-make-model
               api provider-id definition))
            definitions))
         (handle
           (%make-faux-handle
            :api api
            :provider-id provider-id
            :models models
            :token-min
            (max 1 (min token-min token-max))
            :token-max
            (max token-min token-max))))
    (setf
     (faux-handle-provider handle)
     (make-runtime-provider
      :id provider-id
      :name (symbol-name provider-id)
      :models models
      :api-key-auth-p t
      :auth-resolver
      (lambda (&rest ignored)
        (declare (ignore ignored))
        (make-runtime-auth-result
         :source "Faux" :type :api-key))
      :complete-function
      (lambda (model context options)
        (apply #'faux-complete
               handle model context options))
      :stream-function
      (lambda (model context on-event &rest options)
        (apply #'faux-stream
               handle model context on-event options))))
    handle))

(defun faux-set-responses (handle responses)
  (setf (faux-handle-responses handle)
        (copy-list responses))
  handle)

(defun faux-append-responses (handle responses)
  (setf (faux-handle-responses handle)
        (append (faux-handle-responses handle)
                (copy-list responses)))
  handle)

(defun faux-pending-response-count (handle)
  (length (faux-handle-responses handle)))

(defun faux-get-model (handle &optional model-id)
  (if model-id
      (find model-id
            (faux-handle-models handle)
            :key #'model-id
            :test #'string=)
      (first (faux-handle-models handle))))

(defun faux-copy-content-block (block)
  (cond
    ((typep block 'text-content)
     (make-text-content
      :text (text-content-text block)
      :signature (text-content-signature block)))
    ((typep block 'thinking-content)
     (make-thinking-content
      :thinking (thinking-content-thinking block)
      :signature (thinking-content-signature block)
      :redacted-p (thinking-content-redacted-p block)))
    ((typep block 'tool-call)
     (make-tool-call
      :id (tool-call-id block)
      :name (tool-call-name block)
      :arguments (tool-call-arguments block)
      :thought-signature
      (tool-call-thought-signature block)))
    (t block)))

(defun faux-copy-message (message handle model)
  (make-assistant-message
   :content
   (mapcar #'faux-copy-content-block
           (assistant-message-content message))
   :api (faux-handle-api handle)
   :provider (faux-handle-provider-id handle)
   :model (model-id model)
   :response-model
   (assistant-message-response-model message)
   :response-id (assistant-message-response-id message)
   :usage (assistant-message-usage message)
   :stop-reason (assistant-message-stop-reason message)
   :error-message (assistant-message-error-message message)
   :raw-stop-reason
   (assistant-message-raw-stop-reason message)
   :timestamp (assistant-message-timestamp message)))

(defun faux-content-text (content)
  (cond
    ((stringp content) content)
    ((or (listp content) (vectorp content))
     (format
      nil "~{~A~^~%~}"
      (loop for block across (coerce content 'vector)
            collect
            (cond
              ((typep block 'text-content)
               (text-content-text block))
              ((typep block 'image-content)
               (format nil "[image:~A:~D]"
                       (image-content-mime-type block)
                       (length (image-content-data block))))
              (t "")))))
    (t "")))

(defun faux-assistant-content-text (content)
  (format
   nil "~{~A~^~%~}"
   (mapcar
    (lambda (block)
      (cond
        ((typep block 'text-content)
         (text-content-text block))
        ((typep block 'thinking-content)
         (thinking-content-thinking block))
        ((typep block 'tool-call)
         (format nil "~A:~A"
                 (tool-call-name block)
                 (stringify-json
                  (tool-call-arguments block))))
        (t "")))
    content)))

(defun faux-message-text (message)
  (cond
    ((typep message 'user-message)
     (faux-content-text (user-message-content message)))
    ((typep message 'assistant-message)
     (faux-assistant-content-text
      (assistant-message-content message)))
    ((typep message 'tool-result-message)
     (format nil "~A~%~A"
             (tool-result-message-tool-name message)
             (faux-content-text
              (tool-result-message-content message))))
    (t "")))

(defun faux-serialize-context (context)
  (format
   nil "~{~A~^~%~%~}"
   (append
    (when (context-system-prompt context)
      (list
       (format nil "system:~A"
               (context-system-prompt context))))
    (mapcar
     (lambda (message)
       (format nil "~A:~A"
               (cond
                 ((typep message 'user-message) "user")
                 ((typep message 'assistant-message)
                  "assistant")
                 (t "toolResult"))
               (faux-message-text message)))
     (context-messages context))
    (when (context-tools context)
      (list
       (format nil "tools:~{~A~^,~}"
               (mapcar #'tool-name
                       (context-tools context))))))))

(defun common-prefix-length (left right)
  (loop for index from 0
        below (min (length left) (length right))
        while (char= (char left index)
                     (char right index))
        finally (return index)))

(defun faux-with-usage
    (handle message context session-id cache-retention)
  (let* ((prompt (faux-serialize-context context))
         (prompt-tokens (estimate-text-tokens prompt))
         (output-tokens
           (estimate-text-tokens
            (faux-assistant-content-text
             (assistant-message-content message))))
         (input prompt-tokens)
         (cache-read 0)
         (cache-write 0))
    (when (and session-id
               (not (eq cache-retention :none)))
      (let ((previous
              (gethash session-id
                       (faux-handle-prompt-cache handle))))
        (if previous
            (let ((prefix
                    (common-prefix-length previous prompt)))
              (setf cache-read
                    (estimate-text-tokens
                     (subseq previous 0 prefix))
                    cache-write
                    (estimate-text-tokens
                     (subseq prompt prefix))
                    input (max 0
                               (- prompt-tokens cache-read))))
            (setf cache-write prompt-tokens))
        (setf
         (gethash session-id
                  (faux-handle-prompt-cache handle))
         prompt)))
    (setf
     (assistant-message-usage message)
     (make-usage
      :input input
      :output output-tokens
      :cache-read cache-read
      :cache-write cache-write))
    message))

(defun faux-error-message (handle model text &optional aborted-p)
  (make-assistant-message
   :api (faux-handle-api handle)
   :provider (faux-handle-provider-id handle)
   :model (model-id model)
   :content nil
   :stop-reason (if aborted-p :aborted :error)
   :error-message text))

(defun faux-resolve
    (handle model context options)
  (incf (faux-state-call-count
         (faux-handle-state handle)))
  (let ((step (pop (faux-handle-responses handle))))
    (unless step
      (return-from faux-resolve
        (faux-error-message
         handle model "No more faux responses queued")))
    (handler-case
        (let* ((resolved
                 (if (functionp step)
                     (funcall step context options
                              (faux-handle-state handle)
                              model)
                     step))
               (message
                 (faux-copy-message resolved handle model)))
          (when (eq :pending
                    (assistant-message-stop-reason message))
            (return-from faux-resolve
              (faux-error-message
               handle model
               "Faux response ended without a stop reason")))
          (faux-with-usage
           handle message context
           (getf options :session-id)
           (getf options :cache-retention)))
      (error (condition)
        (faux-error-message
         handle model (princ-to-string condition))))))

(defun faux-complete
    (handle model context &rest options
     &key abort-p &allow-other-keys)
  (when (and abort-p (funcall abort-p))
    (return-from faux-complete
      (faux-error-message
       handle model "Request was aborted" t)))
  (faux-resolve handle model context options))

(defun faux-emit
    (emit type message
     &key content-index delta content tool-call reason)
  (funcall
   emit
   (make-stream-event
    :type type
    :message message
    :content-index content-index
    :delta delta
    :content content
    :tool-call tool-call
    :reason reason)))

(defun faux-stream
    (handle model context on-event
     &rest options &key abort-p &allow-other-keys)
  (let ((message
          (if (and abort-p (funcall abort-p))
              (faux-error-message
               handle model "Request was aborted" t)
              (faux-resolve handle model context options))))
    (when (member (assistant-message-stop-reason message)
                  '(:error :aborted))
      (faux-emit
       on-event :error message
       :reason (assistant-message-stop-reason message))
      (return-from faux-stream message))
    (faux-emit on-event :start message)
    (loop for block in (assistant-message-content message)
          for index from 0
          do
          (cond
            ((typep block 'thinking-content)
             (faux-emit
              on-event :thinking-start message
              :content-index index)
             (faux-emit
              on-event :thinking-delta message
              :content-index index
              :delta
              (thinking-content-thinking block))
             (faux-emit
              on-event :thinking-end message
              :content-index index
              :content
              (thinking-content-thinking block)))
            ((typep block 'text-content)
             (faux-emit
              on-event :text-start message
              :content-index index)
             (faux-emit
              on-event :text-delta message
              :content-index index
              :delta (text-content-text block))
             (faux-emit
              on-event :text-end message
              :content-index index
              :content (text-content-text block)))
            ((typep block 'tool-call)
             (faux-emit
              on-event :tool-call-start message
              :content-index index)
             (faux-emit
              on-event :tool-call-delta message
              :content-index index
              :delta
              (stringify-json
               (tool-call-arguments block)))
             (faux-emit
              on-event :tool-call-end message
              :content-index index
              :tool-call block))))
    (faux-emit
     on-event :done message
     :reason (assistant-message-stop-reason message))
    message))
