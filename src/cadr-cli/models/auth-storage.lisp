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

(cadr-core:define-redacted-print-object
    (runtime-credentials value stream)
  (write-string ":credentials [REDACTED]" stream))

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
          (and (cadr-ai::json-object-p object)
               (cadr-ai::json-get object "env"))))
    (when (cadr-ai::json-object-p environment)
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
