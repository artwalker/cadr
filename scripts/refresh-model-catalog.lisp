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

(dolist (relative
         '("src/cadr-ai/package.lisp"
           "src/cadr-ai/conditions.lisp"
           "src/cadr-ai/types.lisp"
           "src/cadr-ai/json.lisp"
           "src/cadr-ai/models.lisp"))
  (load (truename (merge-pathnames relative *root*))))

(defparameter *catalog-directory*
  (merge-pathnames
   "test/fixtures/catalogs/provider-data/"
   *root*))

(defparameter *generated-path*
  (merge-pathnames "src/cadr-ai/models.generated.lisp" *root*))

(defparameter *compat-key-map*
  '(("allowEmptySignature" . :allow-empty-signature)
    ("cacheControlFormat" . :cache-control-format)
    ("deferredToolsMode" . :deferred-tools-mode)
    ("forceAdaptiveThinking" . :force-adaptive-thinking)
    ("maxTokensField" . :max-tokens-field)
    ("requiresReasoningContentOnAssistantMessages"
     . :requires-reasoning-content-on-assistant-messages)
    ("sendSessionAffinityHeaders"
     . :send-session-affinity-headers)
    ("sessionAffinityFormat" . :session-affinity-format)
    ("supportsCacheControlOnTools"
     . :supports-cache-control-on-tools)
    ("supportsDeveloperRole" . :supports-developer-role)
    ("supportsEagerToolInputStreaming"
     . :supports-eager-tool-input-streaming)
    ("supportsExplicitPromptCacheMode"
     . :supports-explicit-prompt-cache-mode)
    ("supportsLongCacheRetention"
     . :supports-long-cache-retention)
    ("supportsOpenAIGrammarTools"
     . :supports-openai-grammar-tools)
    ("supportsReasoningEffort" . :supports-reasoning-effort)
    ("supportsStore" . :supports-store)
    ("supportsStrictMode" . :supports-strict-mode)
    ("supportsStrictTools" . :supports-strict-tools)
    ("supportsTemperature" . :supports-temperature)
    ("supportsToolSearch" . :supports-tool-search)
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

(defun compat-plist (object)
  (when (hash-table-p object)
    (loop for key in (sorted-json-keys object)
          for mapped = (cdr (assoc key *compat-key-map*
                                   :test #'string=))
          unless mapped
            do (error "Unsupported compat key in catalog: ~A" key)
          append
          (list mapped
                (let ((value
                        (normalized-json-value
                         (json-get object key))))
                  (if (member mapped
                              '(:cache-control-format
                                :deferred-tools-mode
                                :max-tokens-field
                                :session-affinity-format
                                :thinking-format))
                      (keyword-value value)
                      value))))))

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
     :input-price (number-or-zero (json-get cost "input"))
     :output-price (number-or-zero (json-get cost "output"))
     :cache-read-price (number-or-zero (json-get cost "cacheRead"))
     :cache-write-price
     (number-or-zero (json-get cost "cacheWrite"))
     :cost-tiers (cost-tiers cost))))

(defun catalog-rows ()
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
        for catalog =
        (cadr-ai::parse-json
         (uiop:read-file-string path :external-format :utf-8))
        append
        (loop for api in (sorted-json-keys catalog)
              for models = (json-get catalog api)
              append
              (loop for id in (sorted-json-keys models)
                    collect
                    (model-row provider (json-get models id))))))

(let* ((rows (catalog-rows))
       (*print-pretty* t)
       (*print-right-margin* 88))
  (with-open-file
      (stream *generated-path*
              :direction :output
              :if-exists :supersede
              :if-does-not-exist :create
              :external-format :utf-8)
    (write-line
     ";; Generated by scripts/refresh-model-catalog.lisp from the fixed pi-ai 0.83.0 catalog snapshot."
     stream)
    (write-line
     ";; Runtime use is offline and deterministic."
     stream)
    (write-line "(in-package #:cadr-ai)" stream)
    (terpri stream)
    (write-string "(defparameter *generated-model-metadata* '" stream)
    (pprint rows stream)
    (write-line ")" stream)
    (terpri stream)
    (write-line
     "(register-generated-models *generated-model-metadata*)"
     stream))
  (format t "Updated ~A with ~D models.~%"
          (namestring *generated-path*)
          (length rows)))
