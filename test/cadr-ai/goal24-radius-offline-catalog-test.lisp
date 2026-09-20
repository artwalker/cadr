(in-package #:cadr-ai/tests)

(defun goal24-radius-config-json ()
  "{\"baseUrl\":\"https://radius.example/v1\",\"models\":[{\"id\":\"balanced\",\"name\":\"Fresh Balanced\",\"reasoning\":true,\"input\":[\"text\"],\"cost\":{\"input\":1,\"output\":2,\"cacheRead\":0.1,\"cacheWrite\":0},\"contextWindow\":424242,\"maxTokens\":32000},{\"id\":\"organization-only\",\"name\":\"Organization Only\",\"reasoning\":false,\"input\":[\"text\"],\"cost\":{\"input\":0,\"output\":0,\"cacheRead\":0,\"cacheWrite\":0},\"contextWindow\":128000,\"maxTokens\":16000}]}")

(defun goal24-radius-refreshed-models ()
  (mapcar
   #'cadr-ai::model-from-metadata
   (cadr-ai:radius-models-from-config
    :radius
    (cadr-ai::parse-json (goal24-radius-config-json)))))

(defun goal24-radius-seed-api-key (credentials)
  (cadr-ai:credential-store-modify
   credentials :radius
   (lambda (old)
     (declare (ignore old))
     (cadr-ai:make-api-key-credential
      :provider :radius
      :key "radius-key"))))

(test goal24-radius-default-gateway-ships-static-public-catalog
  (let* ((runtime (cadr-ai:make-built-in-models-runtime))
         (models (cadr-ai:models-runtime-models runtime :radius))
         (balanced
           (cadr-ai:models-runtime-model
            runtime :radius "balanced")))
    (is (> (length models) 0))
    (is (= 27 (length models)))
    (is (not (null balanced)))
    (is (string= "balanced" (cadr-ai:model-id balanced)))
    (is (eq :radius (cadr-ai:model-provider balanced)))
    (is (eq :pi-messages (cadr-ai:model-api balanced)))
    (is (string=
         "balanced"
         (cadr-ai:provider-definition-default-model
          (cadr-ai:find-provider-definition :radius))))))

(test goal24-radius-custom-gateway-has-empty-catalog-before-refresh
  (let* ((runtime
           (cadr-ai:make-built-in-models-runtime
            :environment
            '(("RADIUS_GATEWAY_URL" . "http://localhost:8788")))))
    (is (null
         (cadr-ai:models-runtime-models runtime :radius)))))

(test goal24-radius-network-refresh-overlays-static-catalog
  (let* ((calls 0)
         (cadr-ai:*http-request-function*
           (lambda (url &key method headers content
                        connect-timeout read-timeout want-stream
                        force-string force-binary)
             (declare
              (ignore method content connect-timeout
                      read-timeout want-stream force-string
                      force-binary))
             (incf calls)
             (is (string=
                  "https://radius.pi.dev/v1/config"
                  url))
             (is (string=
                  "Bearer radius-key"
                  (cdr
                   (assoc "authorization" headers
                          :test #'string-equal))))
             (values (goal24-radius-config-json) 200 nil)))
         (credentials (cadr-ai:make-memory-credential-store))
         (model-store (make-hash-table))
         (runtime
           (cadr-ai:make-built-in-models-runtime
            :credential-store credentials
            :model-store model-store)))
    (goal24-radius-seed-api-key credentials)
    (let ((result (cadr-ai:models-runtime-refresh runtime)))
      (is (null (cadr-ai:models-refresh-result-errors result))))
    (is (= 1 calls))
    (let ((balanced
            (cadr-ai:models-runtime-model
             runtime :radius "balanced"))
          (organization
            (cadr-ai:models-runtime-model
             runtime :radius "organization-only"))
          (refreshed-only (length (goal24-radius-refreshed-models))))
      (is (string= "Fresh Balanced" (cadr-ai::model-name balanced)))
      (is (string=
           "https://radius.example/v1"
           (cadr-ai:model-base-url balanced)))
      (is (= 424242 (cadr-ai:model-context-window balanced)))
      (is (not (null organization)))
      (is (>
           (length
            (cadr-ai:models-runtime-models runtime :radius))
           refreshed-only)))))

(test goal24-radius-cached-store-overlays-without-network
  (let* ((calls 0)
         (cadr-ai:*http-request-function*
           (lambda (&rest ignored)
             (declare (ignore ignored))
             (incf calls)
             (values "{}" 500 nil)))
         (credentials (cadr-ai:make-memory-credential-store))
         (model-store (make-hash-table))
         (runtime
           (cadr-ai:make-built-in-models-runtime
            :credential-store credentials
            :model-store model-store)))
    (goal24-radius-seed-api-key credentials)
    (setf (gethash :radius model-store)
          (goal24-radius-refreshed-models))
    (let ((result
            (cadr-ai:models-runtime-refresh
             runtime :allow-network nil)))
      (is (null (cadr-ai:models-refresh-result-errors result))))
    (is (= 0 calls))
    (is (string=
         "Fresh Balanced"
         (cadr-ai::model-name
          (cadr-ai:models-runtime-model
           runtime :radius "balanced"))))
    (is (not
         (null
          (cadr-ai:models-runtime-model
           runtime :radius "organization-only"))))
    (is (>
         (length
          (cadr-ai:models-runtime-models runtime :radius))
         (length (goal24-radius-refreshed-models))))))
