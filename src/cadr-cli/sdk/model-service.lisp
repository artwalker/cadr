(in-package #:cadr-cli)

(defclass sdk-model-runtime ()
  ((registry
    :initarg :registry
    :reader sdk-model-runtime-registry)
   (credentials
    :initarg :credentials
    :reader sdk-model-runtime-credentials)
   (persistent-storage
    :initarg :persistent-storage
    :reader sdk-model-runtime-persistent-storage)
   (native-runtime
    :initarg :native-runtime
    :reader sdk-model-runtime-native-runtime)
   (lock
    :initform
    (sb-thread:make-mutex
     :name "cadr SDK model runtime")
    :reader sdk-model-runtime-lock)))

(defun sdk-copy-credential-into-store
    (store provider credential)
  (let ((provider-id
          (provider-symbol-from-key provider)))
    (if credential
        (cadr-ai:credential-store-modify
         store provider-id
         (lambda (current)
           (declare (ignore current))
           (credential-with-provider
            credential provider-id)))
        (cadr-ai:credential-store-delete
         store provider-id))))

(defun sdk-seed-native-credentials (runtime)
  (let* ((credentials
           (sdk-model-runtime-credentials runtime))
         (store
           (cadr-ai::models-runtime-credential-store
            (sdk-model-runtime-native-runtime
             runtime))))
    (dolist (entry (auth-storage-list credentials))
      (sdk-copy-credential-into-store
       store (car entry)
       (auth-storage-read credentials (car entry)))))
  runtime)

(defun make-sdk-model-runtime
    (&key
       (auth-path (default-auth-path))
       (models-path
         (merge-pathnames
          "models.json"
          (uiop:pathname-directory-pathname
           (default-auth-path))))
       credential-storage environment)
  (let* ((persistent
           (or credential-storage
               (make-file-auth-storage auth-path)))
         (credentials
           (make-runtime-credentials persistent))
         (native
           (cadr-ai:make-built-in-models-runtime
            :credential-store
            (cadr-ai:make-memory-credential-store)
            :environment environment))
         (registry
           (make-model-registry
            :path models-path
            :credentials credentials))
         (runtime
           (make-instance
            'sdk-model-runtime
            :registry registry
            :credentials credentials
            :persistent-storage persistent
            :native-runtime native)))
    (sdk-seed-native-credentials runtime)
    runtime))

(defun sdk-model-runtime-providers (runtime)
  (cadr-ai:models-runtime-providers
   (sdk-model-runtime-native-runtime runtime)))

(defun sdk-model-runtime-models
    (runtime &optional provider)
  (let* ((native
           (cadr-ai:models-runtime-models
            (sdk-model-runtime-native-runtime runtime)
            (and provider
                 (provider-symbol-from-key provider))))
         (native-provider-ids
           (mapcar
            #'cadr-ai:runtime-provider-id
            (sdk-model-runtime-providers runtime)))
         (configured
           (remove-if
            (lambda (model)
              (or
               (member
                (cadr-ai:model-provider model)
                native-provider-ids)
               (and provider
                    (not
                     (eq
                      (cadr-ai:model-provider model)
                      (provider-symbol-from-key
                       provider))))))
            (model-registry-all
             (sdk-model-runtime-registry runtime)))))
    (append native configured)))

(defun sdk-model-runtime-model
    (runtime provider model-id)
  (or
   (cadr-ai:models-runtime-model
    (sdk-model-runtime-native-runtime runtime)
    (provider-symbol-from-key provider)
    model-id)
   (model-registry-find
    (sdk-model-runtime-registry runtime)
    provider model-id)))

(defun sdk-model-runtime-register-provider
    (runtime provider)
  (sb-thread:with-mutex
      ((sdk-model-runtime-lock runtime))
    (cadr-ai:models-runtime-set-provider
     (sdk-model-runtime-native-runtime runtime)
     provider)
    (let ((credential
            (auth-storage-read
             (sdk-model-runtime-credentials runtime)
             (cadr-ai:runtime-provider-id provider))))
      (sdk-copy-credential-into-store
       (cadr-ai::models-runtime-credential-store
        (sdk-model-runtime-native-runtime runtime))
       (cadr-ai:runtime-provider-id provider)
       credential)))
  provider)

(defun sdk-model-runtime-check-auth
    (runtime provider)
  (sb-thread:with-mutex
      ((sdk-model-runtime-lock runtime))
    (cadr-ai:models-runtime-check-auth
     (sdk-model-runtime-native-runtime runtime)
     (provider-symbol-from-key provider))))

(defun sdk-sync-refreshed-oauth
    (runtime provider)
  (let* ((provider-id
           (provider-symbol-from-key provider))
         (store
           (cadr-ai::models-runtime-credential-store
            (sdk-model-runtime-native-runtime runtime)))
         (credential
           (cadr-ai:credential-store-read
            store provider-id)))
    (when (typep credential 'cadr-ai:oauth-credential)
      (auth-storage-modify
       (sdk-model-runtime-persistent-storage runtime)
       provider-id
       (lambda (current)
         (declare (ignore current))
         credential))))
  runtime)

(defun sdk-model-runtime-auth
    (runtime provider-or-model
     &key api-key environment)
  (sb-thread:with-mutex
      ((sdk-model-runtime-lock runtime))
    (let ((auth
            (cadr-ai:models-runtime-auth
             (sdk-model-runtime-native-runtime runtime)
             (if (typep provider-or-model 'cadr-ai:model)
                 provider-or-model
                 (provider-symbol-from-key
                  provider-or-model))
             :api-key api-key
             :environment environment)))
      (sdk-sync-refreshed-oauth
       runtime
       (if (typep provider-or-model 'cadr-ai:model)
           (cadr-ai:model-provider provider-or-model)
           provider-or-model))
      auth)))

(defun sdk-model-runtime-set-api-key
    (runtime provider key)
  (unless (and (stringp key) (plusp (length key)))
    (error
     'cadr-ai:configuration-error
     :message "Runtime API key must not be empty"))
  (sb-thread:with-mutex
      ((sdk-model-runtime-lock runtime))
    (runtime-credentials-set-api-key
     (sdk-model-runtime-credentials runtime)
     provider key)
    (sdk-copy-credential-into-store
     (cadr-ai::models-runtime-credential-store
      (sdk-model-runtime-native-runtime runtime))
     provider
     (auth-storage-read
      (sdk-model-runtime-credentials runtime)
      provider)))
  key)

(defun sdk-model-runtime-remove-api-key
    (runtime provider)
  (sb-thread:with-mutex
      ((sdk-model-runtime-lock runtime))
    (runtime-credentials-remove-api-key
     (sdk-model-runtime-credentials runtime)
     provider)
    (sdk-copy-credential-into-store
     (cadr-ai::models-runtime-credential-store
      (sdk-model-runtime-native-runtime runtime))
     provider
     (auth-storage-read
      (sdk-model-runtime-credentials runtime)
      provider)))
  nil)

(defun sdk-model-runtime-login
    (runtime provider auth-type interaction)
  (sb-thread:with-mutex
      ((sdk-model-runtime-lock runtime))
    (let* ((provider-id
             (provider-symbol-from-key provider))
           (credential
             (cadr-ai:models-runtime-login
              (sdk-model-runtime-native-runtime runtime)
              provider-id auth-type interaction)))
      (auth-storage-modify
       (sdk-model-runtime-persistent-storage runtime)
       provider-id
       (lambda (current)
         (declare (ignore current))
         credential))
      credential)))

(defun sdk-model-runtime-refresh
    (runtime &key (allow-network t) force abort-p)
  (sb-thread:with-mutex
      ((sdk-model-runtime-lock runtime))
    (sdk-seed-native-credentials runtime)
    (let ((result
            (cadr-ai:models-runtime-refresh
             (sdk-model-runtime-native-runtime runtime)
             :allow-network allow-network
             :force force :abort-p abort-p)))
      (dolist
          (provider
           (sdk-model-runtime-providers runtime))
        (sdk-sync-refreshed-oauth
         runtime
         (cadr-ai:runtime-provider-id provider)))
      (refresh-model-registry
       (sdk-model-runtime-registry runtime))
      result)))

(defun sdk-model-runtime-available-models
    (runtime &optional provider)
  (sb-thread:with-mutex
      ((sdk-model-runtime-lock runtime))
    (let* ((provider-id
             (and provider
                  (provider-symbol-from-key provider)))
           (native
             (cadr-ai:models-runtime-available-models
              (sdk-model-runtime-native-runtime runtime)
              provider-id))
           (native-provider-ids
             (mapcar
              #'cadr-ai:runtime-provider-id
              (sdk-model-runtime-providers runtime)))
           (configured
             (remove-if
              (lambda (model)
                (or
                 (member
                  (cadr-ai:model-provider model)
                  native-provider-ids)
                 (and provider-id
                      (not
                       (eq provider-id
                           (cadr-ai:model-provider
                            model))))))
              (model-registry-available-models
               (sdk-model-runtime-registry runtime)))))
      (append native configured))))

(defun sdk-model-runtime-list-credentials (runtime)
  (auth-storage-list
   (sdk-model-runtime-credentials runtime)))

(defun sdk-model-runtime-provider-config
    (runtime model &key allow-missing-auth-p)
  (let* ((provider-id
           (cadr-ai:model-provider model))
         (native-provider
           (cadr-ai:models-runtime-provider
            (sdk-model-runtime-native-runtime runtime)
            provider-id)))
    (if native-provider
        (let ((auth
                (sdk-model-runtime-auth runtime model)))
          (when (and (null auth)
                     (not allow-missing-auth-p))
            (error
             'cadr-ai:configuration-error
             :message
             (format nil
                     "No authentication configured for provider ~A"
                     (provider-key provider-id))))
          (make-provider-config
           :name (provider-key provider-id)
           :provider
           (funcall
            (model-provider-constructor
             (cadr-ai:model-api model))
            :api-key
            (and auth
                 (cadr-ai:runtime-auth-result-api-key
                  auth))
            :provider-id provider-id
            :authentication-required-p nil)
           :model
           (if (and auth
                    (cadr-ai:runtime-auth-result-base-url
                     auth))
               (copy-model-with-overrides
                model :base-url
                (cadr-ai:runtime-auth-result-base-url
                 auth))
               model)
           :auth-source
           (if auth :sdk-runtime :none)))
        (provider-config-for-model
         (sdk-model-runtime-registry runtime)
         model
         :allow-missing-auth-p
         allow-missing-auth-p))))

(defun sdk-model-runtime-stream-function (runtime)
  (lambda (provider model context on-event
           &rest options)
    (declare (ignore provider))
    (apply
     #'cadr-ai:models-runtime-stream
     (sdk-model-runtime-native-runtime runtime)
     model context on-event options)))
