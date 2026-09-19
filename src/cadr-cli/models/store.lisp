(in-package #:cadr-cli)

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
  (let ((copy (cadr-ai::copy-model model)))
    (when provider
      (setf (cadr-ai:model-provider copy) provider))
    (when base-url
      (setf (cadr-ai:model-base-url copy) base-url))
    (setf (cadr-ai::model-headers copy)
          (merge-header-sources
           (cadr-ai::model-headers model)
           headers))
    copy))

(defun model-compat-json-key (name)
  ;; camelCase wire key to the compat plist's uppercase kebab keyword.
  (intern
   (string-upcase
    (with-output-to-string (out)
      (loop for character across name
            do (when (upper-case-p character)
                 (write-char #\- out))
               (write-char character out))))
   :keyword))

(defparameter +model-compat-boolean-keys+
  '("supportsDeveloperRole" "supportsLongCacheRetention"
    "supportsStrictMode" "supportsOpenAIGrammarTools"
    "supportsAdditionalTools" "supportsToolSearch"
    "supportsEagerToolInputStreaming" "sendSessionAffinityHeaders"
    "supportsCacheControlOnTools" "supportsTemperature"
    "forceAdaptiveThinking" "allowEmptySignature"
    "supportsStrictTools" "supportsToolReferences"
    "supportsMaxOutputTokens"))

(defparameter +model-compat-enum-keys+
  '("sessionAffinityFormat" "deferredToolsMode" "cacheControlFormat"
    "thinkingFormat"))

(defun parse-model-compat (object)
  ;; Baseline model-config.ts ProviderCompatSchema: the boolean and enum
  ;; compat keys from models.json.  The routing-object keys
  ;; (openRouterRouting, vercelGatewayRouting) are not parsed yet.
  (when (hash-table-p object)
    (loop for key being the hash-keys of object
          using (hash-value value)
          append
          (cond
            ((member key +model-compat-boolean-keys+ :test #'string=)
             (list (model-compat-json-key key)
                   (not (null value))))
            ((and (member key +model-compat-enum-keys+ :test #'string=)
                  (stringp value))
             (list (model-compat-json-key key)
                   (model-compat-json-key value)))
            ((and (string= key "vllmPriority")
                  (numberp value))
             (list :vllm-priority value))
            (t nil)))))

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
            ;; find returns the matching string; supports-images-p is a
            ;; boolean slot, so a bare find aborts the models.json load.
            (find "image" input
                  :test #'equal)
            t))
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
       (cadr-ai::json-get object "headers")))
     :compat
     (parse-model-compat (cadr-ai::json-get object "compat")))))
