(in-package #:cadr-cli)

(defparameter *auth-storage-locks*
  (make-hash-table :test #'equal))
(defparameter *auth-storage-locks-lock*
  (sb-thread:make-mutex
   :name "cadr auth storage lock table"))

(defun acquire-auth-file-lock (path)
  (ensure-directories-exist path)
  (let ((deadline
          (+ (get-internal-real-time)
             (* 10
                internal-time-units-per-second)))
        (stream nil))
    (loop
      (setf
       stream
       (open
        path
        :direction :output
        :if-does-not-exist :create
        :if-exists nil
        :external-format :utf-8))
      (when stream
        (format
         stream "~A ~A~%"
         0
         (get-universal-time))
        (finish-output stream)
        (return))
      (when
          (>= (get-internal-real-time)
              deadline)
        (error
         "Timed out acquiring auth storage lock ~A"
         path))
      (sleep 0.05))
    (lambda ()
      (when stream
        (close stream)
        (setf stream nil))
      (when (probe-file path)
        (delete-file path)))))

(defparameter *auth-file-lock-acquire-function*
  #'acquire-auth-file-lock)

(defun auth-storage-lock-path (path)
  (parse-namestring
   (format nil "~A.lock"
           (namestring
            (uiop:ensure-absolute-pathname
             path)))))

(defun call-with-auth-file-lock (path function)
  (let ((release
          (funcall
           *auth-file-lock-acquire-function*
           (auth-storage-lock-path path))))
    (unwind-protect
         (funcall function)
      (funcall release))))

(defun canonical-storage-path (path)
  (namestring
   (or (ignore-errors (truename path))
       (uiop:ensure-absolute-pathname path))))

(defun auth-storage-lock (path)
  (let ((key (canonical-storage-path path)))
    (sb-thread:with-mutex
        (*auth-storage-locks-lock*)
      (or (gethash key *auth-storage-locks*)
          (setf
           (gethash key *auth-storage-locks*)
           (sb-thread:make-mutex
            :name (format nil
                          "cadr auth storage ~A"
                          key)))))))

(defstruct (file-auth-storage
            (:constructor make-file-auth-storage
                (path)))
  path)

(defstruct (runtime-credentials
            (:constructor make-runtime-credentials
                (storage)))
  storage
  (overrides (make-hash-table :test #'equal)
             :type hash-table)
  (lock
    (sb-thread:make-mutex
     :name "cadr runtime credentials")))

(defun provider-key (provider)
  (string-downcase
   (etypecase provider
     (symbol (symbol-name provider))
     (string provider))))

(defun provider-symbol-from-key (provider)
  (intern (string-upcase (provider-key provider))
          :keyword))

(defun credential-object-at (object provider)
  (cadr-ai::json-get object (provider-key provider)))

(defun credential-environment (object)
  (let ((environment
          (and (hash-table-p object)
               (cadr-ai::json-get object "env"))))
    (when (hash-table-p environment)
      (cadr-ai::json-object-alist environment))))

(defun resolved-json-credential (provider object)
  (let* ((provider-id
           (provider-symbol-from-key provider))
         (credential
           (cadr-ai::json-credential
            provider-id object)))
    (if (typep credential
               'cadr-ai:api-key-credential)
        (let* ((environment
                 (credential-environment object))
               (resolved
                 (resolve-config-value
                  (cadr-ai:api-key-credential-key
                   credential)
                  :environment environment)))
          (and resolved
               (cadr-ai:make-api-key-credential
                :provider provider-id
                :key resolved
                :environment environment)))
        credential)))

(defun auth-storage-read (storage provider)
  (etypecase storage
    (file-auth-storage
     (let ((object
             (cadr-ai::read-auth-object
              (file-auth-storage-path storage))))
       (resolved-json-credential
        provider
        (credential-object-at object provider))))
    (cadr-ai:memory-credential-store
     (cadr-ai:credential-store-read
      storage (provider-symbol-from-key provider)))
    (runtime-credentials
     (let ((key (provider-key provider)))
       (sb-thread:with-mutex
           ((runtime-credentials-lock storage))
         (or
          (gethash key
                   (runtime-credentials-overrides
                    storage))
          (auth-storage-read
           (runtime-credentials-storage storage)
           provider)))))))

(defun credential-provider (credential fallback)
  (etypecase credential
    (cadr-ai:api-key-credential
     (or
      (cadr-ai:api-key-credential-provider credential)
      (provider-symbol-from-key fallback)))
    (cadr-ai:oauth-credential
     (or
      (cadr-ai:oauth-credential-provider credential)
      (provider-symbol-from-key fallback)))))

(defun credential-with-provider (credential provider)
  (let ((provider-id
          (provider-symbol-from-key provider)))
    (etypecase credential
      (cadr-ai:api-key-credential
       (cadr-ai:make-api-key-credential
        :provider provider-id
        :key
        (cadr-ai:api-key-credential-key credential)
        :environment
        (cadr-ai:api-key-credential-environment
         credential)))
      (cadr-ai:oauth-credential
       (cadr-ai:make-oauth-credential
        :provider provider-id
        :access
        (cadr-ai:oauth-credential-access credential)
        :refresh
        (cadr-ai:oauth-credential-refresh credential)
        :expires
        (cadr-ai:oauth-credential-expires credential)
        :account-id
        (cadr-ai:oauth-credential-account-id
         credential))))))

(defun auth-storage-modify
    (storage provider function)
  (etypecase storage
    (file-auth-storage
     (let ((path (file-auth-storage-path storage)))
       (sb-thread:with-mutex
           ((auth-storage-lock path))
         (call-with-auth-file-lock
          path
          (lambda ()
            (let* ((object
                     (cadr-ai::read-auth-object
                      path))
                   (raw
                     (credential-object-at
                      object provider))
                   (current
                     (resolved-json-credential
                      provider raw))
                   (next
                     (funcall function current))
                   (effective
                     (or next current)))
              (when next
                (cadr-ai::json-put
                 object (provider-key provider)
                 (cadr-ai::credential-json
                  (credential-with-provider
                   next provider)))
                (cadr-ai::write-auth-object
                 path object))
              effective))))))
    (cadr-ai:memory-credential-store
     (cadr-ai:credential-store-modify
      storage
      (provider-symbol-from-key provider)
      (lambda (current)
        (let ((next
                (funcall function current)))
          (and next
               (credential-with-provider
                next provider))))))
    (runtime-credentials
     (let ((key (provider-key provider)))
       (sb-thread:with-mutex
           ((runtime-credentials-lock storage))
         (let* ((current
                  (or
                   (gethash
                    key
                    (runtime-credentials-overrides
                     storage))
                   (auth-storage-read
                    (runtime-credentials-storage storage)
                    provider)))
                (next (funcall function current)))
           (when next
             (setf
              (gethash
               key
               (runtime-credentials-overrides storage))
              (credential-with-provider
               next provider)))
           (or next current)))))))

(defun auth-storage-delete (storage provider)
  (etypecase storage
    (file-auth-storage
     (let ((path (file-auth-storage-path storage)))
       (sb-thread:with-mutex
           ((auth-storage-lock path))
         (call-with-auth-file-lock
          path
          (lambda ()
            (when (probe-file path)
              (let ((object
                      (cadr-ai::read-auth-object
                       path)))
                (remhash
                 (provider-key provider)
                 object)
                (cadr-ai::write-auth-object
                 path object))))))))
    (cadr-ai:memory-credential-store
     (cadr-ai:credential-store-delete
      storage
      (provider-symbol-from-key provider)))
    (runtime-credentials
     (let ((key (provider-key provider)))
       (sb-thread:with-mutex
           ((runtime-credentials-lock storage))
         (remhash
          key
          (runtime-credentials-overrides storage)))
       (auth-storage-delete
        (runtime-credentials-storage storage)
        provider))))
  nil)

(defun credential-kind-name (credential)
  (etypecase credential
    (cadr-ai:api-key-credential "api_key")
    (cadr-ai:oauth-credential "oauth")))

(defun auth-storage-list (storage)
  (etypecase storage
    (file-auth-storage
     (let ((object
             (cadr-ai::read-auth-object
              (file-auth-storage-path storage))))
       (sort
        (loop for provider being the hash-keys
                of object
              for credential =
              (cadr-ai::json-credential
               (provider-symbol-from-key provider)
               (gethash provider object))
              when credential
                collect
                (cons provider
                      (credential-kind-name credential)))
        #'string< :key #'car)))
    (cadr-ai:memory-credential-store
     (mapcar
      (lambda (entry)
        (cons
         (provider-key (car entry))
         (ecase (cdr entry)
           (:api-key "api_key")
           (:oauth "oauth"))))
      (cadr-ai:credential-store-list storage)))
    (runtime-credentials
     (let ((table (make-hash-table :test #'equal)))
       (dolist
           (entry
            (auth-storage-list
             (runtime-credentials-storage storage)))
         (setf (gethash (car entry) table)
               (cdr entry)))
       (sb-thread:with-mutex
           ((runtime-credentials-lock storage))
         (maphash
          (lambda (provider credential)
            (setf
             (gethash provider table)
             (credential-kind-name credential)))
          (runtime-credentials-overrides storage)))
       (sort
        (loop for provider being the hash-keys
                of table using (hash-value kind)
              collect (cons provider kind))
        #'string< :key #'car)))))

(defun runtime-credentials-set-api-key
    (credentials provider key)
  (sb-thread:with-mutex
      ((runtime-credentials-lock credentials))
    (setf
     (gethash
      (provider-key provider)
      (runtime-credentials-overrides credentials))
     (cadr-ai:make-api-key-credential
      :provider (provider-symbol-from-key provider)
      :key key)))
  key)

(defun runtime-credentials-remove-api-key
    (credentials provider)
  (sb-thread:with-mutex
      ((runtime-credentials-lock credentials))
    (remhash
     (provider-key provider)
     (runtime-credentials-overrides credentials)))
  nil)

(defstruct (file-models-store
            (:constructor make-file-models-store
                (path)))
  path
  (lock
    (sb-thread:make-mutex
     :name "cadr models store")))

(defun models-store-object (store)
  (let ((path (file-models-store-path store)))
    (if (probe-file path)
        (let ((object
                (cadr-ai::parse-json
                 (uiop:read-file-string
                  path :external-format :utf-8))))
          (unless (hash-table-p object)
            (error "models store must contain an object"))
          object)
        (empty-json-object))))

(defun models-store-read (store provider)
  (sb-thread:with-mutex
      ((file-models-store-lock store))
    (cadr-ai::copy-json-value
     (cadr-ai::json-get
      (models-store-object store)
      (provider-key provider)))))

(defun models-store-write
    (store provider entry)
  (sb-thread:with-mutex
      ((file-models-store-lock store))
    (let ((object (models-store-object store)))
      (cadr-ai::json-put
       object (provider-key provider)
       (cadr-ai::copy-json-value entry))
      (write-settings-object
       (file-models-store-path store)
       object)))
  entry)

(defun models-store-delete (store provider)
  (sb-thread:with-mutex
      ((file-models-store-lock store))
    (let ((object (models-store-object store)))
      (remhash (provider-key provider) object)
      (write-settings-object
       (file-models-store-path store)
       object)))
  nil)

(defun parse-model-spec (spec &optional provider)
  (let* ((slash (position #\/ spec))
         (resolved-provider
           (or
            (and slash
                 (subseq spec 0 slash))
            provider))
         (model-and-level
           (if slash
               (subseq spec (1+ slash))
               spec))
         (colon
           (position #\: model-and-level
                     :from-end t))
         (candidate
           (and colon
                (subseq model-and-level
                        (1+ colon))))
         (thinking
           (and candidate
                (find candidate
                      +thinking-level-names+
                      :test #'string-equal)))
         (model
           (if thinking
               (subseq model-and-level 0 colon)
               model-and-level)))
    (when (zerop (length model))
      (error "Model identifier cannot be empty"))
    (list
     :provider resolved-provider
     :model model
     :thinking
     (and thinking
          (intern (string-upcase thinking)
                  :keyword)))))

(defun copy-model-with-overrides
    (model &key provider base-url headers)
  (cadr-ai:make-model
   :id (cadr-ai:model-id model)
   :name (cadr-ai::model-name model)
   :provider
   (or provider (cadr-ai:model-provider model))
   :api (cadr-ai:model-api model)
   :base-url
   (or base-url (cadr-ai:model-base-url model))
   :max-tokens
   (cadr-ai:model-max-tokens model)
   :context-window
   (cadr-ai:model-context-window model)
   :supports-images-p
   (cadr-ai:model-supports-images-p model)
   :supports-tools-p
   (cadr-ai:model-supports-tools-p model)
   :reasoning-p
   (cadr-ai:model-reasoning-p model)
   :thinking-level-map
   (cadr-ai::model-thinking-level-map model)
   :headers
   (merge-header-sources
    (cadr-ai::model-headers model)
    headers)
   :compat (cadr-ai::model-compat model)))

(defun json-model (provider object base-url
                   provider-api provider-headers)
  (let ((id (cadr-ai::json-get object "id")))
    (unless (and (stringp id)
                 (plusp (length id)))
      (error "Custom model is missing id"))
    (cadr-ai:make-model
     :id id
     :name
     (or (cadr-ai::json-get object "name")
         id)
     :provider provider
     :api
     (intern
      (string-upcase
       (or (cadr-ai::json-get object "api")
           provider-api
           "openai-completions"))
      :keyword)
     :base-url base-url
     :max-tokens
     (or (cadr-ai::json-get object "maxTokens")
         4096)
     :context-window
     (or
      (cadr-ai::json-get object "contextWindow")
      128000)
     :supports-images-p
     (let ((input
             (cadr-ai::json-get object "input")))
       (and input
            (find "image" input
                  :test #'string=)))
     :supports-tools-p
     (not
      (eq nil
          (cadr-ai::json-get
           object "supportsTools" t)))
     :reasoning-p
     (eq t
         (cadr-ai::json-get
          object "reasoning"))
     :headers
     (merge-header-sources
      provider-headers
      (cadr-ai::json-object-alist
       (cadr-ai::json-get object "headers"))))))

(defstruct (model-registry
            (:constructor %make-model-registry))
  path
  credentials
  (models nil :type list)
  (provider-settings
    (make-hash-table :test #'eq)
    :type hash-table)
  error)

(defun built-in-models ()
  (mapcar
   #'cadr-ai::model-from-metadata
   (cadr-ai:list-model-metadata)))

(defun provider-config-object (root)
  (and (hash-table-p root)
       (cadr-ai::json-get root "providers")))

(defun provider-headers-from-json (object)
  (cadr-ai::json-object-alist
   (and (hash-table-p object)
        (cadr-ai::json-get object "headers"))))

(defun read-models-config (path)
  (if (or (null path)
          (not (probe-file path)))
      (empty-json-object)
      (let ((root
              (cadr-ai::parse-json
               (uiop:read-file-string
                path :external-format :utf-8))))
        (unless (hash-table-p root)
          (error "models.json must contain an object"))
        root)))

(defun refresh-model-registry (registry)
  (handler-case
      (let* ((root
               (read-models-config
                (model-registry-path registry)))
             (providers
               (provider-config-object root))
             (models (built-in-models))
             (settings
               (make-hash-table :test #'eq)))
        (when (hash-table-p providers)
          (maphash
           (lambda (provider-name config)
             (unless (hash-table-p config)
               (error
                "Provider ~A configuration must be an object"
                provider-name))
             (let* ((provider
                      (provider-symbol-from-key
                       provider-name))
                    (base-url
                      (cadr-ai::json-get
                       config "baseUrl"))
                    (headers
                      (provider-headers-from-json
                       config))
                    (api
                      (cadr-ai::json-get config "api"))
                    (custom
                      (cadr-ai::json-get
                       config "models")))
               (setf (gethash provider settings)
                     config)
               (setf
                models
                (mapcar
                 (lambda (model)
                   (if (eq provider
                           (cadr-ai:model-provider
                            model))
                       (copy-model-with-overrides
                        model
                        :base-url base-url
                        :headers headers)
                       model))
                 models))
               (when custom
                 (loop for object across
                       (coerce custom 'vector)
                       for model =
                       (json-model
                        provider object
                        (or base-url
                            "http://localhost")
                        api headers)
                       do
                       (setf models
                             (remove
                              (cadr-ai:model-id model)
                              models
                              :key #'cadr-ai:model-id
                              :test #'string=
                              :count 1))
                       (push model models)))))
           providers))
        (setf
         (model-registry-models registry)
         (sort models
               (lambda (left right)
                 (let ((left-provider
                         (provider-key
                          (cadr-ai:model-provider left)))
                       (right-provider
                         (provider-key
                          (cadr-ai:model-provider right))))
                   (if (string= left-provider
                                right-provider)
                       (string<
                        (cadr-ai:model-id left)
                        (cadr-ai:model-id right))
                       (string< left-provider
                                right-provider)))))
         (model-registry-provider-settings registry)
         settings
         (model-registry-error registry)
         nil))
    (condition (condition)
      (setf (model-registry-error registry)
            (princ-to-string condition))))
  registry)

(defun make-model-registry (&key path credentials)
  (refresh-model-registry
   (%make-model-registry
    :path path
    :credentials credentials)))

(defun model-registry-all (registry)
  (copy-list (model-registry-models registry)))

(defun model-registry-find
    (registry provider model)
  (find-if
   (lambda (candidate)
     (and
      (or
       (null provider)
       (string-equal
        (provider-key
         (cadr-ai:model-provider candidate))
        (provider-key provider)))
      (string= (cadr-ai:model-id candidate)
               model)))
   (model-registry-models registry)))

(defun known-provider-definition-p (provider)
  (find
   (provider-symbol-from-key provider)
   (cadr-ai:list-provider-definitions)
   :key #'cadr-ai:provider-definition-id
   :test #'eq))

(defun model-registry-provider-config
    (registry provider)
  (gethash
   (provider-symbol-from-key provider)
   (model-registry-provider-settings registry)))

(defun configured-model-api-key
    (registry provider)
  (let* ((config
           (model-registry-provider-config
            registry provider))
         (value
           (and config
                (cadr-ai::json-get
                 config "apiKey"))))
    (and
     (stringp value)
     (resolve-config-value value))))

(defun model-provider-constructor
    (protocol)
  (ecase protocol
    (:anthropic-messages
     #'cadr-ai:make-anthropic-provider)
    (:openai-responses
     #'cadr-ai:make-openai-provider)
    (:openai-completions
     #'cadr-ai:make-openai-completions-provider)
    (:google-generative-ai
     #'cadr-ai:make-google-provider)
    (:azure-openai-responses
     #'cadr-ai:make-azure-openai-provider)
    (:bedrock-converse-stream
     #'cadr-ai:make-bedrock-provider)
    (:google-vertex
     #'cadr-ai:make-vertex-provider)
    (:mistral-conversations
     #'cadr-ai:make-mistral-provider)
    (:openai-codex-responses
     #'cadr-ai:make-openai-codex-provider)
    (:pi-messages
     #'cadr-ai:make-pi-messages-provider)))

(defun provider-config-for-model
    (registry model
     &key api-key base-url
       (config-path (default-config-path))
       (auth-path (default-auth-path))
       allow-missing-auth-p)
  (let* ((provider
           (cadr-ai:model-provider model))
         (provider-name
           (provider-key provider))
         (provider-config
           (model-registry-provider-config
            registry provider))
         (configured-base-url
           (and provider-config
                (cadr-ai::json-get
                 provider-config "baseUrl")))
         (configured-key
           (configured-model-api-key
            registry provider))
         (effective-key
           (or api-key configured-key))
         (effective-base-url
           (or base-url configured-base-url)))
    (if (known-provider-definition-p provider)
        (let ((resolved
                (resolve-provider-config
                 :provider provider-name
                 :model (cadr-ai:model-id model)
                 :base-url effective-base-url
                 :api-key effective-key
                 :config-path config-path
                 :auth-path auth-path
                 :allow-missing-auth-p
                 allow-missing-auth-p)))
          (make-provider-config
           :name provider-name
           :provider
           (provider-config-provider resolved)
           :model
           (if base-url
               (copy-model-with-overrides
                model :base-url base-url)
               model)
           :auth-source
           (if
               (and configured-key
                    (null api-key))
               :models-json
               (provider-config-auth-source
                resolved))))
        (let* ((credential
                 (and
                  (model-registry-credentials registry)
                  (auth-storage-read
                   (model-registry-credentials registry)
                   provider)))
               (resolved-key
                 (or
                  effective-key
                  (and
                   (typep
                    credential
                    'cadr-ai:api-key-credential)
                   (cadr-ai:api-key-credential-key
                    credential))))
               (oauth
                 (and
                  (typep
                   credential
                   'cadr-ai:oauth-credential)
                  credential))
               (protocol
                 (cadr-ai:model-api model)))
          (when
              (and
               (null resolved-key)
               (null oauth)
               (not allow-missing-auth-p))
            (error
             'cadr-ai:configuration-error
             :message
             (format nil
                     "No authentication configured for provider ~A"
                     provider-name)))
          (make-provider-config
           :name provider-name
           :provider
           (apply
            (model-provider-constructor protocol)
            (append
             (list
              :api-key resolved-key
              :oauth-access-token
              (and oauth
                   (cadr-ai:oauth-credential-access
                    oauth))
              :oauth-account-id
              (and oauth
                   (cadr-ai:oauth-credential-account-id
                    oauth))
              :provider-id provider)
             (and
              (eq protocol
                  :openai-completions)
              (list
               :authentication-required-p t))))
           :model
           (if base-url
               (copy-model-with-overrides
                model :base-url base-url)
               model)
           :auth-source
           (cond
             (api-key :cli)
             (configured-key :models-json)
             ((typep
               credential
               'cadr-ai:oauth-credential)
              :oauth)
             (credential :stored-api-key)
             (t :none)))))))

(defun model-registry-available-models
    (registry
     &key explicit-provider api-key
       (config-path (default-config-path))
       (auth-path (default-auth-path)))
  (let ((availability
          (make-hash-table :test #'eq)))
    (labels
        ((configured-p (model)
           (let ((provider
                   (cadr-ai:model-provider model)))
             (multiple-value-bind
                   (value found-p)
                 (gethash provider availability)
               (if found-p
                   value
                   (setf
                    (gethash provider availability)
                    (handler-case
                        (let ((config
                                (provider-config-for-model
                                 registry model
                                 :api-key
                                 (and
                                  explicit-provider
                                  (string-equal
                                   (provider-key provider)
                                   (provider-key
                                    explicit-provider))
                                  api-key)
                                 :config-path config-path
                                 :auth-path auth-path
                                 :allow-missing-auth-p
                                 t)))
                          (not
                           (eq :none
                               (provider-config-auth-source
                                config))))
                      (condition () nil))))))))
      (remove-if-not
       #'configured-p
       (model-registry-models registry)))))

(defun canonical-model-id (model)
  (format nil "~A/~A"
          (provider-key
           (cadr-ai:model-provider model))
          (cadr-ai:model-id model)))

(defun exact-model-reference-match
    (reference models)
  (let* ((trimmed
           (string-trim
            '(#\Space #\Tab #\Newline #\Return)
            reference))
         (canonical
           (remove-if-not
            (lambda (model)
              (string-equal
               trimmed
               (canonical-model-id model)))
            models)))
    (cond
      ((zerop (length trimmed)) nil)
      ((= 1 (length canonical))
       (first canonical))
      ((plusp (length canonical)) nil)
      (t
       (let ((by-id
               (remove-if-not
                (lambda (model)
                  (string-equal
                   trimmed
                   (cadr-ai:model-id model)))
                models)))
         (and (= 1 (length by-id))
              (first by-id)))))))

(defun alias-model-id-p (id)
  (or
   (uiop:string-suffix-p "-latest" id)
   (not
    (cl-ppcre:scan "-[0-9]{8}$" id))))

(defun model-text-contains-p (model pattern)
  (or
   (search pattern
           (cadr-ai:model-id model)
           :test #'char-equal)
   (let ((name (cadr-ai::model-name model)))
     (and name
          (search pattern name
                  :test #'char-equal)))))

(defun best-partial-model-match
    (pattern models)
  (let* ((matches
           (remove-if-not
            (lambda (model)
              (model-text-contains-p
               model pattern))
            models))
         (aliases
           (remove-if-not
            (lambda (model)
              (alias-model-id-p
               (cadr-ai:model-id model)))
            matches))
         (candidates
           (or aliases matches)))
    (first
     (sort (copy-list candidates)
           #'string>
           :key #'cadr-ai:model-id))))

(defun match-single-model-pattern
    (pattern models)
  (or
   (exact-model-reference-match pattern models)
   (best-partial-model-match pattern models)))

(defun parse-scoped-model-pattern
    (pattern models)
  (let ((full
          (match-single-model-pattern
           pattern models)))
    (when full
      (return-from parse-scoped-model-pattern
        (values full nil nil)))
    (let ((colon
            (position #\: pattern :from-end t)))
      (unless colon
        (return-from parse-scoped-model-pattern
          (values nil nil nil)))
      (let* ((prefix (subseq pattern 0 colon))
             (suffix (subseq pattern (1+ colon)))
             (thinking
               (find suffix
                     +thinking-level-names+
                     :test #'string-equal)))
        (multiple-value-bind
              (model inner-thinking warning)
            (parse-scoped-model-pattern
             prefix models)
          (declare (ignore inner-thinking))
          (cond
            ((null model)
             (values nil nil warning))
            (thinking
             (values
              model
              (and (null warning)
                   (intern
                    (string-upcase thinking)
                    :keyword))
              warning))
            (t
             (values
              model nil
              (format nil
                      "Invalid thinking level ~S in pattern ~S. Using default instead."
                      suffix pattern)))))))))

(defun regex-literal-character
    (character output)
  (when
      (find character
            ".+(){}^$|\\")
    (write-char #\\ output))
  (write-char character output))

(defun glob-pattern-regex (pattern)
  (with-output-to-string (output)
    (write-char #\^ output)
    (loop with length = (length pattern)
          with index = 0
          while (< index length)
          for character = (char pattern index)
          do
          (case character
            (#\*
             (if
                 (and (< (1+ index) length)
                      (char= #\*
                             (char pattern
                                   (1+ index))))
                 (progn
                   (write-string ".*" output)
                   (incf index))
                 (write-string "[^/]*" output)))
            (#\?
             (write-string "[^/]" output))
            (#\[
             (let ((close
                     (position #\] pattern
                               :start (+ index 2))))
               (if (null close)
                   (write-string "\\[" output)
                   (let ((content
                           (subseq pattern
                                   (1+ index)
                                   close)))
                     (write-char #\[ output)
                     (when
                         (and (plusp
                               (length content))
                              (char= #\!
                                     (char content 0)))
                       (write-char #\^ output)
                       (setf content
                             (subseq content 1)))
                     (loop for class-character
                             across content
                           do
                           (when
                               (member class-character
                                       '(#\\ #\]))
                             (write-char #\\ output))
                           (write-char
                            class-character output))
                     (write-char #\] output)
                     (setf index close)))))
            (otherwise
             (regex-literal-character
              character output)))
          (incf index))
    (write-char #\$ output)))

(defun model-glob-matches-p
    (model pattern)
  (let ((scanner
          (cl-ppcre:create-scanner
           (glob-pattern-regex pattern)
           :case-insensitive-mode t)))
    (or
     (cl-ppcre:scan
      scanner (canonical-model-id model))
     (cl-ppcre:scan
      scanner (cadr-ai:model-id model)))))

(defun model-entry-present-p
    (model entries)
  (find model entries
        :key
        (lambda (entry)
          (getf entry :model))
        :test #'cadr-ai:models-equal-p))

(defun model-scope-diagnostic
    (code pattern message)
  (list
   :type :warning
   :code code
   :message message
   :pattern pattern))

(defun resolve-scoped-models-with-diagnostics
    (registry patterns)
  (let ((models
          (model-registry-models registry))
        (scoped nil)
        (diagnostics nil))
    (dolist (pattern patterns)
      (if
          (find-if
           (lambda (character)
             (find character "*?["))
           pattern)
          (let* ((colon
                   (position #\: pattern
                             :from-end t))
                 (suffix
                   (and colon
                        (subseq pattern
                                (1+ colon))))
                 (thinking-name
                   (and suffix
                        (find
                         suffix
                         +thinking-level-names+
                         :test #'string-equal)))
                 (thinking
                   (and thinking-name
                        (intern
                         (string-upcase
                          thinking-name)
                         :keyword)))
                 (glob
                   (if thinking
                       (subseq pattern 0 colon)
                       pattern))
                 (exact
                   (exact-model-reference-match
                    glob models))
                 (matches
                   (if exact
                       (list exact)
                       (remove-if-not
                        (lambda (model)
                          (model-glob-matches-p
                           model glob))
                        models))))
            (if matches
                (dolist (model matches)
                  (unless
                      (model-entry-present-p
                       model scoped)
                    (setf scoped
                          (append
                           scoped
                           (list
                            (list
                             :model model
                             :thinking
                             thinking))))))
                (setf diagnostics
                      (append
                       diagnostics
                       (list
                        (model-scope-diagnostic
                         :no-match pattern
                         (format nil
                                 "No models match pattern ~S"
                                 pattern)))))))
          (multiple-value-bind
                (model thinking warning)
              (parse-scoped-model-pattern
               pattern models)
            (when warning
              (setf diagnostics
                    (append
                     diagnostics
                     (list
                      (model-scope-diagnostic
                       :invalid-thinking-level
                       pattern warning)))))
            (if model
                (unless
                    (model-entry-present-p
                     model scoped)
                  (setf scoped
                        (append
                         scoped
                         (list
                          (list
                           :model model
                           :thinking thinking)))))
                (setf diagnostics
                      (append
                       diagnostics
                       (list
                        (model-scope-diagnostic
                         :no-match pattern
                         (format nil
                                 "No models match pattern ~S"
                                 pattern)))))))))
    (values scoped diagnostics)))

(defun enabled-model-ids-for-patterns
    (scoped diagnostics)
  (let ((ids nil))
    (dolist (entry scoped)
      (pushnew
       (canonical-model-id
        (getf entry :model))
       ids :test #'string=))
    (setf ids (nreverse ids))
    (dolist (diagnostic diagnostics)
      (when (eq :no-match
                (getf diagnostic :code))
        (setf ids
              (append
               ids
               (list
                (getf diagnostic
                      :pattern))))))
    (remove-duplicates ids
                       :test #'string=
                       :from-end t)))

(defun initial-scoped-model-entry
    (scoped default-provider default-model
     &key existing-session-p explicit-model-p)
  (unless
      (or existing-session-p explicit-model-p)
    (or
     (and
      default-provider
      default-model
      (find-if
       (lambda (entry)
         (let ((model (getf entry :model)))
           (and
            (string-equal
             (provider-key
              (cadr-ai:model-provider model))
             (provider-key default-provider))
            (string-equal
             (cadr-ai:model-id model)
             default-model))))
       scoped))
     (first scoped))))

(defun resolve-scoped-models
    (registry patterns)
  (mapcar
   (lambda (entry)
     (getf entry :model))
   (resolve-scoped-models-with-diagnostics
    registry patterns)))

(defun resolve-model
    (registry spec &key provider)
  (let* ((parsed
           (parse-model-spec spec provider))
         (resolved-provider
           (getf parsed :provider))
         (model-id (getf parsed :model))
         (matches
           (remove-if-not
            (lambda (model)
              (and
               (string=
                (cadr-ai:model-id model)
                model-id)
               (or
                (null resolved-provider)
                (string-equal
                 (provider-key
                  (cadr-ai:model-provider model))
                 resolved-provider))))
            (model-registry-models registry))))
    (cond
      ((null matches)
       (values nil
               (format nil
                       "Model not found: ~@[~A/~]~A"
                       resolved-provider model-id)
               (getf parsed :thinking)))
      ((or resolved-provider
           (= 1 (length matches)))
       (values (first matches)
               nil
               (getf parsed :thinking)))
      (t
       (values
        (or
         (find :openai-codex matches
               :key #'cadr-ai:model-provider)
         (find :openai matches
               :key #'cadr-ai:model-provider)
         (first matches))
        nil
        (getf parsed :thinking))))))

(define-condition credential-print-error (error)
  ((message :initarg :message
            :reader credential-print-error-message))
  (:report
   (lambda (condition stream)
     (write-string
      (credential-print-error-message condition)
      stream))))

(defun parse-duration-milliseconds (value)
  (multiple-value-bind (match groups)
      (cl-ppcre:scan-to-strings
       "^([0-9]+)(ms|s|m|h)?$" value)
    (unless match
      (error 'credential-print-error
             :message
             (format nil "Invalid duration: ~A" value)))
    (* (parse-integer (aref groups 0))
       (cond
         ((string= (aref groups 1) "h") 3600000)
         ((string= (aref groups 1) "m") 60000)
         ((string= (aref groups 1) "s") 1000)
         (t 1)))))

(defun parse-credential-print-command (arguments)
  (unless (and arguments
               (string= (first arguments)
                        "auth"))
    (return-from
        parse-credential-print-command nil))
  (let ((command (second arguments))
        (rest (cddr arguments))
        (kind nil)
        (minimum-expiry nil)
        (forwarded nil))
    (cond
      ((member command
               '("--help" "-h")
               :test #'string=)
       (return-from
           parse-credential-print-command
         (list :help-p t)))
      ((string= command "print-api-key")
       (setf kind :api-key))
      ((string= command "print-bearer-token")
       (setf kind :bearer-token))
      (t
       (error 'credential-print-error
              :message
              (format nil
                      "Unknown auth command: ~A"
                      command))))
    (loop while rest
          for argument = (pop rest)
          do
          (if (string= argument "--min-expiry")
              (progn
                (when (eq kind :api-key)
                  (error
                   'credential-print-error
                   :message
                   "--min-expiry is only supported by print-bearer-token"))
                (unless rest
                  (error
                   'credential-print-error
                   :message
                   "--min-expiry requires a value"))
                (setf minimum-expiry
                      (parse-duration-milliseconds
                       (pop rest))))
              (setf forwarded
                    (append forwarded
                            (list argument)))))
    (list :kind kind
          :arguments forwarded
          :minimum-expiry-ms minimum-expiry)))

(defun credential-for-print
    (storage provider kind
     &key refresh-function
       (minimum-expiry-ms 300000))
  (let ((credential
          (auth-storage-read storage provider)))
    (unless credential
      (error 'credential-print-error
             :message
             (format nil
                     "No credential configured for ~A"
                     provider)))
    (ecase kind
      (:api-key
       (unless
           (typep credential
                  'cadr-ai:api-key-credential)
         (error 'credential-print-error
                :message
                (format nil
                        "~A is configured with OAuth"
                        provider)))
       (cadr-ai:api-key-credential-key
        credential))
      (:bearer-token
       (unless
           (typep credential
                  'cadr-ai:oauth-credential)
         (error 'credential-print-error
                :message
                (format nil
                        "~A is not configured with OAuth"
                        provider)))
       (when
           (<=
            (cadr-ai:oauth-credential-expires
             credential)
            (+ (cadr-ai::unix-milliseconds)
               minimum-expiry-ms))
         (unless refresh-function
           (error 'credential-print-error
                  :message
                  "OAuth credential expires too soon"))
         (setf credential
               (auth-storage-modify
                storage provider
                (lambda (current)
                  (funcall refresh-function
                           current)))))
       (cadr-ai:oauth-credential-access
        credential)))))

(defun print-credential-command-usage
    (&optional
       (stream *standard-output*))
  (format
   stream
   "Usage:~%  cadr auth print-api-key --provider <name> --model <id>~%  cadr auth print-bearer-token --provider <name> --model <id> [--min-expiry <duration>]~%")
  (finish-output stream))

(defun run-credential-print-command
    (arguments
     &key
       (auth-path (default-auth-path))
       (output *standard-output*))
  (let ((parsed
          (parse-credential-print-command
           arguments)))
    (unless parsed
      (return-from
          run-credential-print-command
        (values nil nil)))
    (when (getf parsed :help-p)
      (print-credential-command-usage
       output)
      (return-from
          run-credential-print-command
        (values t 0)))
    (let* ((cli
             (parse-cli-arguments
              (getf parsed :arguments)))
           (model
             (cli-arguments-model cli)))
      (unless
          (and model
               (plusp (length model)))
        (error
         'credential-print-error
         :message
         "Credential printing requires --model"))
      (let* ((model-spec
               (parse-model-spec
                model
                (cli-arguments-provider cli)))
             (provider
               (or
                (getf model-spec :provider)
                (configured-provider-name nil))))
        (unless provider
          (error
           'credential-print-error
           :message
           "Credential printing requires --provider or a provider-qualified --model"))
        (let* ((provider-id
                 (provider-symbol-from-key
                  provider))
               (refresh
                 (and
                  (member
                   provider-id
                   '(:openai :openai-codex
                     :anthropic))
                  (oauth-refresh-function
                   provider-id)))
               (credential
                 (credential-for-print
                  (make-file-auth-storage
                   auth-path)
                  provider
                  (getf parsed :kind)
                  :refresh-function refresh
                  :minimum-expiry-ms
                  (or
                   (getf parsed
                         :minimum-expiry-ms)
                   300000))))
          (format output "~A~%"
                  credential)
          (finish-output output)
          (values t 0))))))
