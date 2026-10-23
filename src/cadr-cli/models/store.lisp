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
    (model &key provider base-url headers compat)
  (let ((copy (cadr-ai::copy-model model)))
    (when provider
      (setf (cadr-ai:model-provider copy) provider))
    (when base-url
      (setf (cadr-ai:model-base-url copy) base-url))
    (setf (cadr-ai::model-headers copy)
          (merge-header-sources
           (cadr-ai::model-headers model)
           headers))
    (when compat
      (setf (cadr-ai::model-compat copy)
            (merge-model-compat
             (cadr-ai::model-compat model)
             compat)))
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
    "supportsMaxOutputTokens" "sendImageOptInHeader"
    "supportsThinkingTokenBudget"))

(defparameter +thinking-token-budget-fields+
  '("thinking_token_budget" "thinking_budget" "thinking_budget_tokens"))

(defparameter +model-compat-merged-record-keys+
  '(:chat-template-kwargs :chat-template-args))

(defparameter +model-compat-enum-keys+
  '("sessionAffinityFormat" "deferredToolsMode" "cacheControlFormat"
    "thinkingFormat" "imageInput"))

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
            ((and (string= key "thinkingTokenBudgetField")
                  (member value +thinking-token-budget-fields+
                          :test #'string=))
             (list :thinking-token-budget-field value))
            ((and (member key
                          '("chatTemplateKwargs" "chatTemplateArgs")
                          :test #'string=)
                  (hash-table-p value))
             (let ((record (parse-chat-template-record value)))
               (when record
                 (list (model-compat-json-key key) record))))
            (t nil)))))

(defun json-model (provider object base-url
                   provider-api provider-headers
                   &optional provider-compat)
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
     (merge-model-compat
      provider-compat
      (parse-model-compat
       (cadr-ai::json-get object "compat")))
     :sampling-params
     (let ((params
             (cadr-ai::json-get object "samplingParams")))
       (and (hash-table-p params) params))
     :sampling-params-by-thinking-level
     (let ((levels
             (cadr-ai::json-get
              object "samplingParamsByThinkingLevel")))
       (when (hash-table-p levels)
         (loop for name in
               '("off" "minimal" "low" "medium"
                 "high" "xhigh" "max")
               for params = (cadr-ai::json-get levels name)
               when (hash-table-p params)
               collect
               (cons
                (intern (string-upcase name) :keyword)
                params)))))))

(defun parse-chat-template-value (value)
  ;; compat-schema.ts ChatTemplateKwargValueSchema. A $var object is
  ;; the plist resolve-chat-template-args already reads. JSON null
  ;; stays the null symbol so it is not written as false.
  (cond
    ((and (hash-table-p value)
          (stringp (cadr-ai::json-get value "$var")))
     (values
      (list :var
            (cadr-ai::json-get value "$var")
            :omit-when-off
            (eq t (cadr-ai::json-get value "omitWhenOff")))
      t))
    ((hash-table-p value)
     (values nil nil))
    (t
     (values
      (if (cadr-ai::json-null-p value) 'null value)
      t))))

(defun parse-chat-template-record (object)
  (let ((record nil))
    (maphash
     (lambda (key value)
       (multiple-value-bind (parsed present-p)
           (parse-chat-template-value value)
         (when present-p
           (setf record (append record (list (cons key parsed)))))))
     object)
    record))

(defun model-compat-plist-value (plist key)
  (loop for (entry-key entry-value) on plist by #'cddr
        when (eq entry-key key)
          return entry-value))

(defun model-compat-plist-put (plist key value)
  (let ((tail (member key plist :test #'eq)))
    (cond
      (tail
       (setf (second tail) value)
       plist)
      ((null plist)
       (list key value))
      (t
       (nconc plist (list key value))))))

(defun merge-chat-template-record (base override)
  ;; provider-composer.ts mergeCompat spreads these records. Base
  ;; keys stay in place; an override replaces the value or appends.
  (let ((merged
          (mapcar (lambda (cell)
                    (cons (car cell) (cdr cell)))
                  base)))
    (dolist (cell override)
      (let ((found (assoc (car cell) merged :test #'equal)))
        (if found
            (setf (cdr found) (cdr cell))
            (setf merged (append merged (list cell))))))
    merged))

(defun merge-model-compat (base override)
  ;; provider-composer.ts mergeCompat. Provider compat overlays each
  ;; chat model; a custom model then overlays that. The two template
  ;; records merge key by key. A false boolean stays in the plist.
  (if (null override)
      base
      (let ((merged (copy-list base)))
        (loop for (key value) on override by #'cddr
              do (setf merged
                       (model-compat-plist-put
                        merged key
                        (if (member key +model-compat-merged-record-keys+
                                    :test #'eq)
                            (merge-chat-template-record
                             (model-compat-plist-value merged key)
                             value)
                            value))))
        merged)))
