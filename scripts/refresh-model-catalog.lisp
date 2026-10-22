#!/usr/bin/env -S sbcl --script

(require :asdf)

(let ((setup
        (or (uiop:getenv "QUICKLISP_SETUP")
            (namestring
             (merge-pathnames "quicklisp/setup.lisp"
                              (user-homedir-pathname))))))
  (unless (probe-file setup)
    (error "Quicklisp setup not found: ~A" setup))
  (load setup))

(defparameter *root*
  (uiop:pathname-parent-directory-pathname
   (uiop:pathname-directory-pathname
    (truename *load-truename*))))

(asdf:load-asd (truename (merge-pathnames "cadr-core.asd" *root*)))
(asdf:load-asd (truename (merge-pathnames "cadr-ai.asd" *root*)))
(asdf:load-system "cadr-ai")

(defparameter *catalog-directory*
  (merge-pathnames
   "test/fixtures/catalogs/provider-data/"
   *root*))

(defparameter *generated-path*
  (merge-pathnames "src/cadr-ai/models.generated.lisp" *root*))

(defun catalog-generation-timestamp ()
  (let* ((structure (cadr-ai:read-model-data-structure *catalog-directory*))
         (manifest
           (cadr-ai::parse-json
            (uiop:read-file-string
             (merge-pathnames ".manifest.json" *catalog-directory*)
             :external-format :utf-8))))
    (cadr-ai:validate-model-data-directory structure *catalog-directory*)
    (cadr-ai::json-get manifest "generatedAt")))

(defparameter *compat-key-map*
  '(("allowEmptySignature" . :allow-empty-signature)
    ("allowedFallbackModels" . :allowed-fallback-models)
    ("cacheControlFormat" . :cache-control-format)
    ("chatTemplateArgs" . :chat-template-args)
    ("deferredToolsMode" . :deferred-tools-mode)
    ("forceAdaptiveThinking" . :force-adaptive-thinking)
    ("maxTokensField" . :max-tokens-field)
    ("requiresReasoningContentOnAssistantMessages"
     . :requires-reasoning-content-on-assistant-messages)
    ("sendSessionAffinityHeaders"
     . :send-session-affinity-headers)
    ("sessionAffinityFormat" . :session-affinity-format)
    ("supportsAdditionalTools" . :supports-additional-tools)
    ("supportsCacheControlOnTools"
     . :supports-cache-control-on-tools)
    ("supportsDeveloperRole" . :supports-developer-role)
    ("supportsEagerToolInputStreaming"
     . :supports-eager-tool-input-streaming)
    ("supportsExplicitPromptCacheMode"
     . :supports-explicit-prompt-cache-mode)
    ("supportsLongCacheRetention"
     . :supports-long-cache-retention)
    ("supportsMidConvoEffort" . :supports-mid-convo-effort)
    ("supportsMidConvoSystemMessages"
     . :supports-mid-convo-system-messages)
    ("supportsMidConvoToolAdditions"
     . :supports-mid-convo-tool-additions)
    ("supportsMidConvoToolChanges"
     . :supports-mid-convo-tool-changes)
    ("supportsOpenAIGrammarTools"
     . :supports-openai-grammar-tools)
    ("supportsReasoningEffort" . :supports-reasoning-effort)
    ("supportsStore" . :supports-store)
    ("supportsStrictMode" . :supports-strict-mode)
    ("supportsStrictTools" . :supports-strict-tools)
    ("supportsThinkingTokenBudget" . :supports-thinking-token-budget)
    ("supportsTemperature" . :supports-temperature)
    ("supportsToolSearch" . :supports-tool-search)
    ("supportsUsageInStreaming" . :supports-usage-in-streaming)
    ("thinkingFormat" . :thinking-format)
    ("zaiToolStream" . :zai-tool-stream)))

(defun json-get (object key &optional default)
  (if (hash-table-p object)
      (gethash key object default)
      default))

(defun keyword-value (value)
  (if (stringp value)
      (intern
       (substitute #\- #\_ (string-upcase value))
       :keyword)
      value))

(defun normalized-json-value (value)
  (if (cadr-ai::json-null-p value)
      nil
      value))

(defun sorted-json-keys (object)
  (sort
   (loop for key being the hash-keys of object collect key)
   #'string<))

(defun compat-fallback-models (entries)
  (when (vectorp entries)
    (loop for entry across entries
          collect
          (list
           :provider (json-get entry "provider")
           :model (json-get entry "model")
           :cost
           (let ((cost (json-get entry "cost")))
             (when (hash-table-p cost)
               (list
                :input (number-or-zero (json-get cost "input"))
                :output (number-or-zero (json-get cost "output"))
                :cache-read (number-or-zero (json-get cost "cacheRead"))
                :cache-write
                (number-or-zero (json-get cost "cacheWrite")))))))))

(defun compat-chat-template-args (object key)
  (loop for arg-key in (sorted-json-keys (json-get object key))
        for arg-value = (json-get (json-get object key) arg-key)
        collect
        (cons
         arg-key
         (if (hash-table-p arg-value)
             (list :var
                   (json-get arg-value "$var")
                   :omit-when-off
                   (eq t (json-get arg-value "omitWhenOff")))
             (normalized-json-value arg-value)))))

(defun compat-scalar-value (mapped object key)
  (let ((value (normalized-json-value (json-get object key))))
    (if (member mapped
                '(:cache-control-format
                  :deferred-tools-mode
                  :max-tokens-field
                  :session-affinity-format
                  :thinking-format))
        (keyword-value value)
        value)))

(defun compat-plist (object)
  (when (hash-table-p object)
    (loop for key in (sorted-json-keys object)
          for mapped = (cdr (assoc key *compat-key-map*
                                   :test #'string=))
          unless mapped
            do (error "Unsupported compat key in catalog: ~A" key)
          append
          (list
           mapped
           (cond
             ((eq mapped :chat-template-args)
              (compat-chat-template-args object key))
             ((eq mapped :allowed-fallback-models)
              (compat-fallback-models (json-get object key)))
             (t
              (compat-scalar-value mapped object key)))))))

(defun thinking-level-map (object)
  (when (hash-table-p object)
    (loop for key in (sorted-json-keys object)
          collect
          (cons
           (keyword-value key)
           (normalized-json-value (json-get object key))))))

(defun header-alist (object)
  (when (hash-table-p object)
    (loop for key in (sorted-json-keys object)
          collect (cons key (json-get object key)))))

(defun number-or-zero (value)
  (if (numberp value)
      (coerce value 'double-float)
      0d0))

(defun prompt-cache-plist (object)
  (when (hash-table-p object)
    (append
     (when (numberp (json-get object "short"))
       (list :short (json-get object "short")))
     (when (numberp (json-get object "long"))
       (list :long (json-get object "long"))))))

(defun resize-limits-plist (object)
  (when (hash-table-p object)
    (list :jpeg-quality (json-get object "jpegQuality")
          :max-bytes (json-get object "maxBytes")
          :max-height (json-get object "maxHeight")
          :max-width (json-get object "maxWidth"))))

(defun input-limits-plist (object)
  (when (hash-table-p object)
    (let ((images (json-get object "images"))
          (limits nil))
      (when (numberp (json-get object "maxRequestBytes"))
        (setf limits
              (list :max-request-bytes
                    (json-get object "maxRequestBytes"))))
      (when (hash-table-p images)
        (let ((image-limits nil))
          (when (numberp (json-get images "maxPerMessage"))
            (setf image-limits
                  (list :max-per-message
                        (json-get images "maxPerMessage"))))
          (when (numberp (json-get images "maxPerRequest"))
            (setf image-limits
                  (append image-limits
                          (list :max-per-request
                                (json-get images "maxPerRequest")))))
          (when (hash-table-p (json-get images "resize"))
            (setf image-limits
                  (append image-limits
                          (list :resize
                                (resize-limits-plist
                                 (json-get images "resize"))))))
          (setf limits
                (append limits (list :images image-limits)))))
      limits)))

(defun image-input-p (model)
  (let ((input (json-get model "input")))
    (and (vectorp input)
         (find "image" input :test #'string=)
         t)))

(defun cost-tiers (cost)
  (let ((tiers (json-get cost "tiers")))
    (when (vectorp tiers)
      (loop for tier across tiers
            collect
            (list
             :input-tokens-above
             (or (json-get tier "inputTokensAbove") 0)
             :input-price
             (number-or-zero (json-get tier "input"))
             :output-price
             (number-or-zero (json-get tier "output"))
             :cache-read-price
             (number-or-zero (json-get tier "cacheRead"))
             :cache-write-price
             (number-or-zero (json-get tier "cacheWrite")))))))

(defun model-row (provider model)
  (let ((cost (json-get model "cost")))
    (list
     :provider (keyword-value provider)
     :id (json-get model "id")
     :name (json-get model "name" (json-get model "id"))
     :api (keyword-value (json-get model "api"))
     :base-url (json-get model "baseUrl" "")
     :context-window (or (json-get model "contextWindow") 0)
     :max-output-tokens (or (json-get model "maxTokens") 4096)
     :supports-images-p (image-input-p model)
     :supports-tools-p t
     :reasoning-p (eq t (json-get model "reasoning"))
     :thinking-level-map
     (thinking-level-map (json-get model "thinkingLevelMap"))
     :headers (header-alist (json-get model "headers"))
     :compat (compat-plist (json-get model "compat"))
     :prompt-cache (prompt-cache-plist (json-get model "promptCache"))
     :input-limits (input-limits-plist (json-get model "inputLimits"))
     :input-price (number-or-zero (json-get cost "input"))
     :output-price (number-or-zero (json-get cost "output"))
     :cache-read-price (number-or-zero (json-get cost "cacheRead"))
     :cache-write-price
     (number-or-zero (json-get cost "cacheWrite"))
     :cost-tiers (cost-tiers cost))))

(defun chat-catalog-rows (&key provider-filter)
  (loop for path in
        (sort
         (remove-if-not
          (lambda (path)
            (and
             (string-equal "json" (pathname-type path))
             (not
              (char= #\. (char (pathname-name path) 0)))))
          (uiop:directory-files *catalog-directory*))
         #'string<
         :key #'namestring)
        for provider = (pathname-name path)
        when (or (null provider-filter)
                 (funcall provider-filter provider))
          append
          (let ((catalog
                  (cadr-ai::parse-json
                   (uiop:read-file-string path :external-format :utf-8))))
            (loop for api in (sorted-json-keys catalog)
                  for models = (json-get catalog api)
                  append
                  (loop for id in (sorted-json-keys models)
                        for model = (json-get models id)
                        when (string= "chat" (or (json-get model "type") ""))
                          collect (model-row provider model))))))

(defparameter *radius-generated-path*
  (merge-pathnames
   "src/cadr-ai/providers/radius.models.generated.lisp"
   *root*))

(let* ((chat-rows
         (chat-catalog-rows
          :provider-filter
          (lambda (provider)
            (not (string= provider "radius")))))
       (radius-rows
         (chat-catalog-rows
          :provider-filter
          (lambda (provider) (string= provider "radius"))))
       (generated-at (catalog-generation-timestamp))
       (radius-sha
         (cadr-ai::model-data-file-hash
          (merge-pathnames "radius.json" *catalog-directory*)))
       (*print-pretty* t)
       (*print-right-margin* 88))
  (with-open-file
      (stream *generated-path*
              :direction :output
              :if-exists :supersede
              :if-does-not-exist :create
              :external-format :utf-8)
    (write-line
     ";; Generated by scripts/refresh-model-catalog.lisp from the pi-ai 1.4.0 catalog snapshot."
     stream)
    (write-line
     ";; Runtime use is offline and deterministic. Radius stays in its own public catalog."
     stream)
    (write-line "(in-package #:cadr-ai)" stream)
    (terpri stream)
    (format stream "(setf *generated-model-data-generated-at* ~S)~%~%"
            generated-at)
    (write-string "(defparameter *generated-model-metadata* '" stream)
    (pprint chat-rows stream)
    (write-line ")" stream)
    (terpri stream)
    (write-line
     "(register-generated-models *generated-model-metadata*)"
     stream))
  (with-open-file
      (stream *radius-generated-path*
              :direction :output
              :if-exists :supersede
              :if-does-not-exist :create
              :external-format :utf-8)
    (format stream
            ";; Generated by scripts/refresh-model-catalog.lisp from pi-ai 1.4.0 radius.json.~%")
    (format stream ";; sha256 ~A~%" radius-sha)
    (write-line
     ";; Not registered into *model-catalog*; Radius keeps a separate public catalog."
     stream)
    (write-line "(in-package #:cadr-ai)" stream)
    (terpri stream)
    (write-string "(defparameter *radius-public-model-metadata* '" stream)
    (pprint radius-rows stream)
    (write-line ")" stream)
    (terpri stream))
  (format t "Updated ~A with ~D models.~%"
          (namestring *generated-path*)
          (length chat-rows))
  (format t "Updated ~A with ~D models.~%"
          (namestring *radius-generated-path*)
          (length radius-rows)))
