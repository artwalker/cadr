(in-package #:cadr-ai/tests)
(in-suite cadr-ai-suite)

(defun openrouter-user-chat (id)
  (cadr-ai::make-model-metadata
   :provider :openrouter
   :id id
   :name id
   :api :openai-completions
   :base-url "https://openrouter.ai/api/v1"
   :context-window 200000
   :max-output-tokens 50000
   :input-price 1d0
   :output-price 2d0
   :cache-read-price 0.1d0
   :cache-write-price 0d0))

(defun openrouter-user-item-id (item)
  (etypecase item
    (cadr-ai::model-metadata (cadr-ai::model-metadata-id item))
    (cadr-ai::model (cadr-ai::model-id item))))

(test openrouter-user-list-keeps-the-keys-chat-models
  ;; pi@71023aec1 openrouter.ts personalizeOpenRouterCatalog #10672.
  (let* ((image
           (cadr-ai::make-model
            :id "image"
            :name "image"
            :provider :openrouter
            :api :openrouter-images
            :base-url "https://openrouter.ai/api/v1"))
         (classifier
           (cadr-ai::make-model
            :id "classifier"
            :name "classifier"
            :provider :openrouter
            :api :typesafe-system-one
            :base-url "https://openrouter.ai/api/v1"))
         (catalog
           (list
            (openrouter-user-chat "listed")
            (openrouter-user-chat "no-limits")
            (openrouter-user-chat "router")
            (openrouter-user-chat "blocked")
            image
            classifier))
         (body
           (cadr-ai::parse-json
            "{\"data\":[
               {\"id\":\"listed\",
                \"context_length\":1000000,
                \"top_provider\":{\"context_length\":262144,
                                  \"max_completion_tokens\":32768},
                \"pricing\":{\"prompt\":\"0.000003\",
                             \"completion\":\"0.000015\",
                             \"overrides\":[
                               {\"min_prompt_tokens\":200000,
                                \"prompt\":\"0.000001\"},
                               {\"min_prompt_tokens\":1,
                                \"utc_start\":0,
                                \"prompt\":\"0.000009\"}]}},
               {\"id\":\"no-limits\",
                \"context_length\":0,
                \"top_provider\":{\"context_length\":null,
                                  \"max_completion_tokens\":null}},
               {\"id\":\"router\",
                \"pricing\":{\"prompt\":\"-1\",\"completion\":\"-1\"}}]}"))
         (result
           (cadr-ai::personalize-openrouter-catalog catalog 200 body))
         (listed (first result))
         (tier (first (cadr-ai::model-metadata-cost-tiers listed))))
    (is (equal
         '("listed" "no-limits" "router" "image" "classifier")
         (mapcar #'openrouter-user-item-id result)))
    (is (= 262144 (cadr-ai::model-metadata-context-window listed)))
    (is (= 32768 (cadr-ai::model-metadata-max-output-tokens listed)))
    (is (= 3d0 (cadr-ai::model-metadata-input-price listed)))
    (is (= 15d0 (cadr-ai::model-metadata-output-price listed)))
    (is (= 0d0 (cadr-ai::model-metadata-cache-read-price listed)))
    (is (= 0d0 (cadr-ai::model-metadata-cache-write-price listed)))
    (is (= 1 (length (cadr-ai::model-metadata-cost-tiers listed))))
    (is (= 200000 (cadr-ai::model-cost-tier-input-tokens-above tier)))
    (is (= 1d0 (cadr-ai::model-cost-tier-input-price tier)))
    (is (= 15d0 (cadr-ai::model-cost-tier-output-price tier)))
    (let ((kept (second result)))
      (is (= 200000 (cadr-ai::model-metadata-context-window kept)))
      (is (= 50000 (cadr-ai::model-metadata-max-output-tokens kept)))
      (is (= 1d0 (cadr-ai::model-metadata-input-price kept)))
      (is (= 2d0 (cadr-ai::model-metadata-output-price kept)))
      (is (= 0.1d0 (cadr-ai::model-metadata-cache-read-price kept))))
    (let ((router (third result)))
      (is (= 0d0 (cadr-ai::model-metadata-input-price router)))
      (is (= 0d0 (cadr-ai::model-metadata-output-price router)))
      (is (= 0d0 (cadr-ai::model-metadata-cache-read-price router)))
      (is (= 0d0 (cadr-ai::model-metadata-cache-write-price router))))
    (is (eq image (fourth result)))
    (is (eq classifier (fifth result)))
    (dolist (status '(401 403 404))
      (is (eq catalog
              (cadr-ai::personalize-openrouter-catalog
               catalog status nil))))
    (handler-case
        (cadr-ai::personalize-openrouter-catalog catalog 500 nil)
      (cadr-ai:configuration-error (condition)
        (is (string=
             "OpenRouter model list request failed: 500"
             (cadr-ai:cadr-error-message condition))))
      (:no-error (&rest ignored)
        (declare (ignore ignored))
        (is (eq t nil))))
    (handler-case
        (cadr-ai::personalize-openrouter-catalog
         catalog 200 (cadr-ai::json-object "data" "nope"))
      (cadr-ai:configuration-error (condition)
        (is (string=
             "Invalid OpenRouter model list response"
             (cadr-ai:cadr-error-message condition))))
      (:no-error (&rest ignored)
        (declare (ignore ignored))
        (is (eq t nil))))))

(test openrouter-refresh-replaces-chat-models-for-the-key
  (let* ((stored nil)
         (calls 0)
         (seen-url nil)
         (seen-headers nil)
         (seen-connect nil)
         (seen-read nil)
         (store
           (lambda (operation &optional value)
             (ecase operation
               (:read stored)
               (:write (setf stored value))
               (:delete (setf stored nil)))))
         (definition (cadr-ai::find-provider-definition :openrouter))
         (baseline
           (cadr-ai::list-model-metadata :openrouter))
         (parts
           (cadr-ai::make-openrouter-runtime-provider-parts
            definition))
         (models (getf parts :models-function))
         (refresh (getf parts :refresh-context-function))
         (body
           "{\"data\":[{\"id\":\"anthropic/claude-3-haiku\",
                        \"context_length\":1000000,
                        \"top_provider\":{\"context_length\":262144,
                                          \"max_completion_tokens\":32768},
                        \"pricing\":{\"prompt\":\"0.000003\",
                                     \"completion\":\"0.000015\"}}]}")
         (status 200))
    (unwind-protect
         (let ((cadr-ai::*openrouter-http-request-function*
                 (lambda (url &key headers connect-timeout read-timeout
                            &allow-other-keys)
                   (setf seen-url url
                         seen-headers headers
                         seen-connect connect-timeout
                         seen-read read-timeout)
                   (incf calls)
                   (values body status)))
               (cadr-ai::*openrouter-metadata-overlay* nil))
           (funcall
            refresh
            (cadr-ai::make-runtime-refresh-context
             :credential
             (cadr-ai::make-api-key-credential
              :provider :openrouter
              :key "sk-or-test")
             :store store
             :allow-network-p t))
           (is (string=
                "https://openrouter.ai/api/v1/models/user"
                seen-url))
           (is (equal
                '(("accept" . "application/json")
                  ("authorization" . "Bearer sk-or-test"))
                seen-headers))
           (is (= 15 seen-connect))
           (is (= 15 seen-read))
           (let ((listed (funcall models)))
             (is (= 1 (length listed)))
             (is (string= "anthropic/claude-3-haiku"
                          (cadr-ai::model-id (first listed))))
             (is (= 262144
                    (cadr-ai::model-context-window (first listed))))
             (is (= 32768 (cadr-ai::model-max-tokens (first listed)))))
           (let ((metadata
                   (cadr-ai::find-model-metadata
                    :openrouter "anthropic/claude-3-haiku")))
             (is (= 3d0 (cadr-ai::model-metadata-input-price metadata)))
             (is (= 0d0
                    (cadr-ai::model-metadata-cache-read-price
                     metadata))))
           (is (= 1 (length stored)))
           (let ((offline
                   (cadr-ai::make-openrouter-runtime-provider-parts
                    definition))
                 (calls-before calls))
             (funcall
              (getf offline :refresh-context-function)
              (cadr-ai::make-runtime-refresh-context
               :credential
               (cadr-ai::make-api-key-credential
                :provider :openrouter
                :key "sk-or-test")
               :store store
               :allow-network-p nil))
             (is (= calls-before calls))
             (is (= 1 (length (funcall (getf offline :models-function))))))
           (setf status 401)
           (funcall
            refresh
            (cadr-ai::make-runtime-refresh-context
             :credential
             (cadr-ai::make-api-key-credential
              :provider :openrouter
              :key "sk-or-test")
             :store store
             :allow-network-p t))
           (is (= (length baseline) (length (funcall models))))
           (is (null stored))
           (is (= 0.03d0
                  (cadr-ai::model-metadata-cache-read-price
                   (cadr-ai::find-model-metadata
                    :openrouter "anthropic/claude-3-haiku"))))
           (let ((calls-before calls))
             (funcall
              refresh
              (cadr-ai::make-runtime-refresh-context
               :credential
               (cadr-ai::make-api-key-credential
                :provider :openrouter
                :key "")
               :store store
               :allow-network-p t))
             (is (= calls-before calls))
             (is (= (length baseline) (length (funcall models))))))
      (setf cadr-ai::*openrouter-metadata-overlay* nil))))
