(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(test goal28-credential-sync-reaches-existing-login
  (with-test-directory (root)
    (let* ((models-path (merge-pathnames "agent/models.json" root))
           (auth-path (merge-pathnames "agent/auth.json" root))
           (storage (cadr-cli:make-file-auth-storage auth-path)))
      (write-text models-path "{")
      (let ((registry
              (cadr-cli:make-model-registry
               :path models-path
               :credentials storage))
            (signaled nil))
        (handler-case
            (cadr-cli::model-registry-login-api-key
             registry :anthropic "sk-test")
          (cadr-cli::credential-synchronization-error (condition)
            (setf signaled condition)))
        (is-true signaled)
        (is (typep
             signaled
             'cadr-cli::credential-synchronization-error))
        (is (eq
             :anthropic
             (cadr-cli::credential-synchronization-error-provider-id
              signaled)))
        (is (search
             "local model state could not be synchronized"
             (princ-to-string signaled)))
        (let ((credential
                (cadr-cli:auth-storage-read storage :anthropic)))
          (is (typep credential 'cadr-ai:api-key-credential))
          (is (string=
               "sk-test"
               (cadr-ai:api-key-credential-key credential))))))))
