(in-package #:cadr-cli)

(defstruct (model-registry
            (:constructor %make-model-registry))
  path
  credentials
  native-runtime
  (models nil :type list)
  (provider-settings
    (make-hash-table :test #'eq)
    :type hash-table)
  error
  %available-models
  %available-models-key)

(cadr-core:define-redacted-print-object (model-registry value stream)
  (format stream ":path ~A :credentials [REDACTED]"
          (model-registry-path value)))

(defvar *native-extension-host* nil)
(defvar *active-native-model-registry* nil)

(defun model-registry-sort-predicate (left right)
  ;; One owner for /model and --list-models order
  ;; (pi@13cbf77df model registry provider then id).
  (let ((left-provider
          (provider-key (cadr-ai:model-provider left)))
        (right-provider
          (provider-key (cadr-ai:model-provider right))))
    (if (string= left-provider right-provider)
        (string< (cadr-ai:model-id left) (cadr-ai:model-id right))
        (string< left-provider right-provider))))

(defun model-registry-native-provider-p
    (registry provider)
  (and
   (model-registry-native-runtime registry)
   (cadr-ai:models-runtime-provider
    (model-registry-native-runtime registry)
    provider)))

(defun seed-native-provider-credential
    (registry provider-id)
  (let* ((runtime
           (model-registry-native-runtime registry))
         (store
           (cadr-ai::models-runtime-credential-store
            runtime))
         (credential
           (and
            (model-registry-credentials registry)
            (auth-storage-read
             (model-registry-credentials registry)
             provider-id))))
    (if credential
        (cadr-ai:credential-store-modify
         store provider-id
         (lambda (old)
           (declare (ignore old))
           credential))
        (cadr-ai:credential-store-delete
         store provider-id))))

(defun merge-native-runtime-models (registry)
  (let* ((runtime
           (model-registry-native-runtime registry))
         (provider-ids
           (mapcar
            #'cadr-ai:runtime-provider-id
            (cadr-ai:models-runtime-providers runtime)))
         (static
           (remove-if
            (lambda (model)
              (member
               (cadr-ai:model-provider model)
               provider-ids))
            (model-registry-models registry))))
    (setf
     (model-registry-models registry)
     (sort
      (append
       static
       (cadr-ai:models-runtime-models runtime))
      #'model-registry-sort-predicate)))
  registry)

(defun sync-model-registry-native-providers
    (registry &key (allow-network t) force)
  (let ((runtime
          (model-registry-native-runtime registry)))
    (cadr-ai:models-runtime-clear-providers runtime)
    (dolist
        (provider
         (and
          *native-extension-host*
          (cadr-agent::extension-host-native-providers
           *native-extension-host*)))
      (cadr-ai:models-runtime-set-provider
       runtime provider)
      (seed-native-provider-credential
       registry
       (cadr-ai:runtime-provider-id provider)))
    (let ((result
            (cadr-ai:models-runtime-refresh
             runtime
             :allow-network allow-network
             :force force)))
      (merge-native-runtime-models registry)
      result)))

(defun model-registry-native-login-records (registry)
  (let ((runtime
          (model-registry-native-runtime registry)))
    (sort
     (loop for provider in
           (and runtime
                (cadr-ai:models-runtime-providers runtime))
           for auth-types =
           (append
            (when
                (cadr-ai:runtime-provider-oauth-login-function
                 provider)
              (list :oauth))
            (when
                (cadr-ai:runtime-provider-api-key-login-function
                 provider)
              (list :api-key)))
           when auth-types
             collect
             (list
              :id (cadr-ai:runtime-provider-id provider)
              :name (cadr-ai:runtime-provider-name provider)
              :oauth-metadata
              (cadr-ai:runtime-provider-oauth-metadata provider)
              :auth-types auth-types))
     #'string-lessp
     :key (lambda (record) (getf record :name)))))

(defun model-registry-login-native-provider
    (registry provider-id interaction
     &key (auth-type :api-key))
  (let* ((runtime
           (model-registry-native-runtime registry))
         (credential
           (cadr-ai:models-runtime-login
            runtime provider-id auth-type interaction)))
    (when (model-registry-credentials registry)
      (auth-storage-modify
       (model-registry-credentials registry)
       provider-id
       (lambda (current)
         (declare (ignore current))
         credential)))
    ;; Login operates on this registry's session-local provider projection.
    ;; Rebuilding from *NATIVE-EXTENSION-HOST* here would drop the provider in
    ;; SDK/test registries and needlessly couple a session-local operation to a
    ;; process-global host.
    (cadr-ai:models-runtime-refresh
     runtime :allow-network t :force t)
    (merge-native-runtime-models registry)
    credential))

(defun model-registry-login-built-in-provider
    (registry provider-id interaction &key login-function)
  (let* ((definition
           (cadr-ai:find-provider-definition provider-id))
         (provider
           (and definition
                (cadr-ai::make-built-in-runtime-provider definition)))
         (login-function
           (or login-function
               (and provider
                    (cadr-ai:runtime-provider-oauth-login-function
                     provider)))))
    (unless login-function
      (error 'cadr-ai:configuration-error
             :message
             (format nil "OAuth login is unavailable for ~A"
                     (provider-key provider-id))))
    (let ((credential (funcall login-function interaction)))
      (auth-storage-modify
       (model-registry-credentials registry)
       provider-id
       (lambda (current)
         (declare (ignore current))
         credential))
      credential)))

(define-condition credential-synchronization-error (error)
  ((provider-id
    :initarg :provider-id
    :reader credential-synchronization-error-provider-id)
   (operation
    :initarg :operation
    :reader credential-synchronization-error-operation)
   (message
    :initarg :message
    :reader credential-synchronization-error-message))
  (:report
   (lambda (condition stream)
     (format stream
             "local model state could not be synchronized: ~A"
             (credential-synchronization-error-message
              condition)))))

(defun model-registry-login-api-key
    (registry provider-id key)
  (unless (cadr-ai::non-empty-string-p key)
    (error 'cadr-ai:configuration-error
           :message "API key must not be empty"))
  (let ((storage
          (model-registry-credentials registry)))
    (unless storage
      (error 'cadr-ai:configuration-error
             :message
             "No credential storage is configured"))
    (let ((credential
            (cadr-ai:make-api-key-credential
             :provider
             (provider-symbol-from-key provider-id)
             :key key)))
      (auth-storage-modify
       storage provider-id
       (lambda (current)
         (declare (ignore current))
         credential))
      (refresh-model-registry registry)
      (let ((sync-error (model-registry-error registry)))
        (when sync-error
          (error 'credential-synchronization-error
                 :provider-id provider-id
                 :operation "login"
                 :message sync-error)))
      credential)))

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
      ;; Baseline core/model-config.ts:245-271 — load, parse, and
      ;; schema failures carry the message envelope plus the file path.
      (let* ((text
              (handler-case
                   (uiop:read-file-string
                    path :external-format :utf-8)
                (error (cause)
                  (error
                   'cadr-ai:configuration-error
                   :message
                   (format nil "Failed to load models.json: ~A~%~%File: ~A"
                           cause (namestring path))
                   :cause cause))))
            (root
              (handler-case
                  (cadr-ai::parse-json text)
                (error (cause)
                  (error
                   'cadr-ai:configuration-error
                   :message
                   (format nil "Failed to parse models.json: ~A~%~%File: ~A"
                           cause (namestring path))
                   :cause cause)))))
        (unless (hash-table-p root)
          (error
           'cadr-ai:configuration-error
           :message
           (format nil "Invalid models.json schema:~%Expected a JSON object at the top level~%~%File: ~A"
                   (namestring path))))
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
                'cadr-ai:configuration-error
                :message
                (format
                 nil
                 "Invalid models.json schema:~%Provider ~A configuration must be an object~%~%File: ~A"
                 provider-name
                 (namestring (model-registry-path registry)))))
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
         (sort models #'model-registry-sort-predicate)
         (model-registry-provider-settings registry)
         settings
         (model-registry-error registry)
         nil)
        (when (model-registry-native-runtime registry)
          (sync-model-registry-native-providers
           registry)))
    (error (condition)
      (setf (model-registry-error registry)
            (princ-to-string condition))))
  registry)

(defun make-model-registry (&key path credentials)
  (let ((registry
          (%make-model-registry
           :path path
           :credentials credentials
           :native-runtime
           (cadr-ai:make-models-runtime))))
    (setf *active-native-model-registry*
          registry)
    (refresh-model-registry registry)))

(defvar *cached-cli-model-registry* nil)
(defvar *cached-cli-model-registry-key* nil)

(defun cli-model-registry-cache-key (path credentials)
  (let ((auth-path
          (and (typep credentials 'file-auth-storage)
               (file-auth-storage-path credentials))))
    (list path
          (and path (probe-file path) (file-write-date path))
          auth-path
          (and auth-path (probe-file auth-path)
               (file-write-date auth-path)))))

(defun clear-cli-model-registry-cache ()
  (setf *cached-cli-model-registry* nil
        *cached-cli-model-registry-key* nil))

(defun cached-cli-model-registry (&key path credentials)
  ;; print-cli-models used to call make-model-registry on every
  ;; --list-models, which re-reads models.json and rebuilds the catalog
  ;; (probe 7d proved the table format is not the cost).  Reuse the last
  ;; refresh while models.json and auth.json write-dates stay the same.
  ;; Baseline cli/list-models.ts listModels still reads current files
  ;; each invocation; this cache is the CL limit, invalidated by mtime.
  (let ((key (cli-model-registry-cache-key path credentials)))
    (if (and *cached-cli-model-registry*
             (equal key *cached-cli-model-registry-key*))
        *cached-cli-model-registry*
        (let ((registry
                (make-model-registry
                 :path path
                 :credentials credentials)))
          (setf *cached-cli-model-registry* registry
                *cached-cli-model-registry-key* key)
          registry))))

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

(defun credential-kind-auth-type (kind)
  (cond
    ((member kind '("oauth" :oauth) :test #'equal)
     :oauth)
    ((member kind '("api_key" "api-key" :api-key)
             :test #'equal)
     :api-key)
    (t nil)))

(defun runtime-credentials-override-status
    (credentials provider)
  (when (typep credentials 'runtime-credentials)
    (sb-thread:with-mutex
        ((runtime-credentials-lock credentials))
      (let ((credential
              (gethash
               (provider-key provider)
               (runtime-credentials-overrides credentials))))
        (when credential
          (list
           :type
           (etypecase credential
             (cadr-ai:oauth-credential :oauth)
             (cadr-ai:api-key-credential :api-key))
           :source "runtime"))))))

(defun persistent-auth-storage (storage)
  (if (typep storage 'runtime-credentials)
      (runtime-credentials-storage storage)
      storage))

(defun stored-credential-status (storage provider)
  (let* ((persistent
           (and storage (persistent-auth-storage storage)))
         (entry
           (and persistent
                (assoc
                 (provider-key provider)
                 (auth-storage-list persistent)
                 :test #'string=))))
    (when entry
      (list
       :type (credential-kind-auth-type (cdr entry))
       :source "stored"))))

(defun config-value-environment-names (value)
  (let ((names nil)
        (index 0))
    (loop while (< index (length value))
          do
          (if (char/= (char value index) #\$)
              (incf index)
              (let ((next (1+ index)))
                (cond
                  ((>= next (length value))
                   (incf index))
                  ((member (char value next) '(#\$ #\!))
                   (incf index 2))
                  ((char= (char value next) #\{)
                   (let ((end
                           (position #\} value
                                     :start (+ index 2))))
                     (if (null end)
                         (incf index)
                         (let ((name
                                 (subseq value (+ index 2) end)))
                           (when
                               (and
                                (plusp (length name))
                                (config-name-start-p (char name 0))
                                (every #'config-name-character-p name))
                             (pushnew name names :test #'string=))
                           (setf index (1+ end))))))
                  ((config-name-start-p (char value next))
                   (let ((end next))
                     (loop while
                           (and
                            (< end (length value))
                            (config-name-character-p
                             (char value end)))
                           do (incf end))
                     (pushnew
                      (subseq value next end)
                      names :test #'string=)
                     (setf index end)))
                  (t (incf index))))))
    (nreverse names)))

(defun models-json-authentication-status
    (registry provider)
  (let* ((config
           (model-registry-provider-config registry provider))
         (value
           (and config
                (cadr-ai::json-get config "apiKey"))))
    (when (and (stringp value) (plusp (length value)))
      (cond
        ((uiop:string-prefix-p "!" value)
         (list :type :api-key
               :source "models_json_command"))
        ((config-value-environment-names value)
         (let ((names
                 (config-value-environment-names value)))
           (when (resolve-config-value value :uncached-p t)
             (list
              :type :api-key
              :source (format nil "~{~A~^, ~}" names)))))
        (t
         (list :type :api-key
               :source "models_json_key"))))))

(defun native-runtime-authentication-status
    (registry provider)
  (let ((runtime (model-registry-native-runtime registry)))
    (when (and runtime
               (cadr-ai:models-runtime-provider runtime provider))
      (let ((check
              (cadr-ai:models-runtime-check-auth
               runtime provider)))
        (when check
          (list
           :type (cadr-ai::runtime-auth-check-type check)
           :source (cadr-ai::runtime-auth-check-source check)))))))

(defun ambient-authentication-status (provider)
  (let* ((definition
           (ignore-errors
             (cadr-ai:find-provider-definition
              (provider-symbol-from-key provider))))
         (name
           (and definition
                (cadr-ai:provider-definition-key-environment
                 definition))))
    (when
        (and name
             (cadr-ai::non-empty-string-p
              (environment-value name)))
      (list :type :api-key :source name))))

(defun model-registry-authentication-status
    (registry provider)
  (or
   (runtime-credentials-override-status
    (model-registry-credentials registry) provider)
   (stored-credential-status
    (model-registry-credentials registry) provider)
   (models-json-authentication-status registry provider)
   (native-runtime-authentication-status registry provider)
   (ambient-authentication-status provider)))

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
    (cond
      ((model-registry-native-provider-p
        registry provider)
       (let ((auth
               (cadr-ai:models-runtime-auth
                (model-registry-native-runtime
                 registry)
                model
                :api-key effective-key)))
         (when
             (and
              (null auth)
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
          (funcall
           (model-provider-constructor
            (cadr-ai:model-api model))
           :api-key
           (and auth
                (cadr-ai:runtime-auth-result-api-key
                 auth))
           :provider-id provider
           :authentication-required-p nil)
          :model
          (if
              (and auth
                   (cadr-ai:runtime-auth-result-base-url
                    auth))
              (copy-model-with-overrides
               model
               :base-url
               (cadr-ai:runtime-auth-result-base-url
                auth))
              model)
          :auth-source
          (if auth :native :none))))
      ((known-provider-definition-p provider)
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
                resolved)))))
      (t
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
             (t :none))))))))

(defun model-registry-available-models
    (registry
     &key explicit-provider api-key
       (config-path (default-config-path))
       (auth-path (default-auth-path)))
  ;; print-cli-models calls this on every listing.  Reuse the last
  ;; configured-p walk while models.json / auth.json write-dates stay
  ;; the same.  Callers may SORT / FILTER the returned list, so hits
  ;; copy.  Not intern.  Not FFI.  Not table-layout.
  (let ((cache-key
          (and (null explicit-provider)
               (null api-key)
               (list
                (cli-model-registry-cache-key
                 (or (model-registry-path registry) config-path)
                 (model-registry-credentials registry))
                config-path
                auth-path))))
    (when (and cache-key
               (equal cache-key
                      (model-registry-%available-models-key registry)))
      (return-from model-registry-available-models
        (copy-list
         (model-registry-%available-models registry))))
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
      (let ((models
              (remove-if-not
               #'configured-p
               (model-registry-models registry))))
        (when cache-key
          (setf (model-registry-%available-models registry) models
                (model-registry-%available-models-key registry)
                cache-key))
        (copy-list models))))))

(defun model-registry-coerce-stream-context (context)
  (cond
    ((typep context 'cadr-ai:context) context)
    ((hash-table-p context)
     (cadr-ai:make-context
      :messages
      (or (gethash "messages" context)
          (gethash :messages context)
          (gethash "Messages" context))))
    ((and (listp context) (getf context :messages))
     (cadr-ai:make-context :messages (getf context :messages)))
    ((listp context)
     (cadr-ai:make-context :messages context))
    (t (cadr-ai:make-context))))

(defun model-registry-stream-api-key (registry model)
  (let* ((runtime (model-registry-native-runtime registry))
         (provider-id (cadr-ai:model-provider model))
         (configured (configured-model-api-key registry provider-id))
         (auth
           (and runtime
                (model-registry-native-provider-p registry provider-id)
                (cadr-ai:models-runtime-auth
                 runtime model :api-key configured)))
         (stored
           (and runtime
                (cadr-ai::runtime-credential runtime provider-id))))
    (or configured
        (and auth (cadr-ai:runtime-auth-result-api-key auth))
        (and (typep stored 'cadr-ai:api-key-credential)
             (cadr-ai:api-key-credential-key stored)))))

(defun model-registry-stream
    (registry model context &key simple-p &allow-other-keys)
  ;; pi@ecac0a9c4 ModelRegistry.stream / streamSimple: both resolve
  ;; auth then call the native runtime stream. SIMPLE-P is API parity.
  (declare (ignore simple-p))
  (let* ((runtime (model-registry-native-runtime registry))
         (provider-id (cadr-ai:model-provider model))
         (stream-context
           (model-registry-coerce-stream-context context))
         (api-key (model-registry-stream-api-key registry model))
         (event-stream
           (cadr-ai:make-event-stream
            :complete-p
            (lambda (event)
              (member (cadr-ai:stream-event-type event)
                      '(:done :error)))
            :result-function #'cadr-ai:stream-event-message)))
    (unless runtime
      (error 'cadr-ai:configuration-error
             :message "Model registry has no native runtime"))
    (unless
        (or api-key
            (and (model-registry-native-provider-p
                  registry provider-id)
                 (cadr-ai:models-runtime-auth runtime model)))
      (error
       'cadr-ai:configuration-error
       :message
       (format nil
               "No authentication configured for provider ~A"
               (provider-key provider-id))))
    (let ((result
            (apply
             #'cadr-ai:models-runtime-stream
             runtime model stream-context
             (lambda (event)
               (cadr-ai:event-stream-push event-stream event))
             (and api-key (list :api-key api-key)))))
      (unless (cadr-ai::event-stream-result-ready-p event-stream)
        (cadr-ai:event-stream-end event-stream result))
      event-stream)))
