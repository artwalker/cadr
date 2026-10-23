(in-package #:cadr-ai/tests)
(in-suite cadr-ai-suite)

;;; v1.4.0 packages/ai/src/providers/typesafe.ts and
;;; packages/ai/src/auth/helpers.ts envApiKeyAuth:
;;; provider id typesafe, name "TypeSafe API key", env TYPESAFE_API_KEY.
;;; A stored key wins. Otherwise the first non-empty env value wins.
;;; An empty value does not authenticate. The only model is the
;;; typesafe-system-one classifier jev-latest
;;; (generate-models.ts loadModelsDevClassifierModels).
;;; packages/coding-agent/src/core/model-resolver.ts
;;; defaultModelPerProvider lists chat defaults only and omits
;;; typesafe, so the declaration's default-model is empty.

(test typesafe-provider-reads-typesafe-api-key-for-system-one
  (let ((definition (cadr-ai:find-provider-definition :typesafe))
        (model (cadr-ai:find-classifier-model :typesafe "jev-latest")))
    (is (string= "TypeSafe" (cadr-ai:provider-definition-name definition)))
    (is (string= "TypeSafe API key"
                 (cadr-ai::provider-definition-api-key-name definition)))
    (is (string= "TYPESAFE_API_KEY"
                 (cadr-ai:provider-definition-key-environment definition)))
    (is (equal '("TYPESAFE_API_KEY")
               (cadr-ai::provider-definition-environment-names definition)))
    (is (equal '(:api-key)
               (cadr-ai:provider-definition-auth-types definition)))
    (is (eq :environment
            (cadr-ai::provider-definition-api-key-auth-strategy definition)))
    (is (null (cadr-ai::provider-definition-oauth-login-strategy definition)))
    (is (eq :typesafe-system-one
            (cadr-ai:provider-definition-protocol definition)))
    (is (equal '(:typesafe-system-one)
               (cadr-ai::provider-definition-protocols definition)))
    (is (string= "https://api.typesafe.ai/v1/"
                 (cadr-ai:provider-definition-base-url definition)))
    (is (string= ""
                 (cadr-ai:provider-definition-default-model definition)))
    (is (null (cadr-ai:list-model-metadata :typesafe)))
    (is (eq :typesafe-system-one (cadr-ai:classifier-model-api model)))
    (is (string= "https://api.typesafe.ai/v1/"
                 (cadr-ai:classifier-model-base-url model)))
    (is (string= "Jev" (cadr-ai:classifier-model-name model)))
    (is (equal '("jev-latest")
               (mapcar #'cadr-ai:classifier-model-id
                       (cadr-ai:list-classifier-models :typesafe)))))
  (let ((from-env
          (cadr-ai::built-in-api-key-auth
           (cadr-ai:find-provider-definition :typesafe)
           nil
           '(("TYPESAFE_API_KEY" . "ts-env-key"))
           nil))
        (blank
          (cadr-ai::built-in-api-key-auth
           (cadr-ai:find-provider-definition :typesafe)
           nil
           '(("TYPESAFE_API_KEY" . ""))
           nil))
        (missing
          (cadr-ai::built-in-api-key-auth
           (cadr-ai:find-provider-definition :typesafe)
           nil
           nil
           nil))
        (stored
          (cadr-ai::built-in-api-key-auth
           (cadr-ai:find-provider-definition :typesafe)
           (cadr-ai:make-api-key-credential
            :provider :typesafe :key "ts-stored-key")
           '(("TYPESAFE_API_KEY" . "ts-env-key"))
           nil))
        (empty-stored
          (cadr-ai::built-in-api-key-auth
           (cadr-ai:find-provider-definition :typesafe)
           (cadr-ai:make-api-key-credential
            :provider :typesafe :key "")
           '(("TYPESAFE_API_KEY" . "ts-env-key"))
           nil)))
    (is (string= "ts-env-key"
                 (cadr-ai::runtime-auth-result-api-key from-env)))
    (is (string= "TYPESAFE_API_KEY"
                 (cadr-ai::runtime-auth-result-source from-env)))
    (is (eq :api-key (cadr-ai::runtime-auth-result-type from-env)))
    (is (null blank))
    (is (null missing))
    (is (string= "ts-stored-key"
                 (cadr-ai::runtime-auth-result-api-key stored)))
    (is (string= "Stored API key"
                 (cadr-ai::runtime-auth-result-source stored)))
    (is (string= "ts-env-key"
                 (cadr-ai::runtime-auth-result-api-key empty-stored)))
    (is (string= "TYPESAFE_API_KEY"
                 (cadr-ai::runtime-auth-result-source empty-stored))))
  (let* ((store (cadr-ai:make-memory-credential-store))
         (unsigned
           (cadr-ai:make-built-in-models-runtime
            :credential-store store
            :environment '(("TYPESAFE_API_KEY" . ""))))
         (signed
           (cadr-ai:make-built-in-models-runtime
            :environment '(("TYPESAFE_API_KEY" . "ts-env-key")))))
    (is (null (cadr-ai:models-runtime-check-auth unsigned :typesafe)))
    (is (null (cadr-ai::models-runtime-available-classifiers
               unsigned :typesafe)))
    (let ((check (cadr-ai:models-runtime-check-auth signed :typesafe)))
      (is (eq :api-key (cadr-ai::runtime-auth-check-type check)))
      (is (string= "TYPESAFE_API_KEY"
                   (cadr-ai::runtime-auth-check-source check))))
    (is (equal '("jev-latest")
               (mapcar #'cadr-ai:classifier-model-id
                       (cadr-ai::models-runtime-available-classifiers
                        signed :typesafe))))
    (cadr-ai:credential-store-modify
     store :typesafe
     (lambda (old)
       (declare (ignore old))
       (cadr-ai:make-api-key-credential
        :provider :typesafe :key "ts-stored-key")))
    (let ((auth
            (cadr-ai:models-runtime-auth
             unsigned :typesafe)))
      (is (string= "ts-stored-key"
                   (cadr-ai::runtime-auth-result-api-key auth)))
      (is (string= "Stored API key"
                   (cadr-ai::runtime-auth-result-source auth))))
    (is (equal '("jev-latest")
               (mapcar #'cadr-ai:classifier-model-id
                       (cadr-ai::models-runtime-available-classifiers
                        unsigned :typesafe))))))
