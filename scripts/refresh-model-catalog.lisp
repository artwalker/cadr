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

(asdf:load-asd (truename (merge-pathnames "cadr-ai.asd" *root*)))
(asdf:load-system "cadr-ai")

(defparameter *catalog-fixture*
  (merge-pathnames
   "test/fixtures/catalogs/wave1-provider-models.json"
   *root*))

(defparameter *generated-path*
  (merge-pathnames "src/cadr-ai/models.generated.lisp" *root*))

(defparameter *base-rows*
  '((:provider :anthropic
     :id "claude-opus-4-8"
     :context-window 1000000
     :max-output-tokens 128000
     :supports-images-p t
     :supports-tools-p t
     :reasoning-p t
     :input-price 5.0d0
     :output-price 25.0d0
     :cache-read-price 0.5d0
     :cache-write-price 6.25d0)
    (:provider :openai
     :id "gpt-5.5"
     :context-window 1050000
     :max-output-tokens 128000
     :supports-images-p t
     :supports-tools-p t
     :reasoning-p t
     :input-price 5.0d0
     :output-price 30.0d0
     :cache-read-price 0.5d0
     :cache-write-price 0d0)
    (:provider :google
     :id "gemini-3.6-flash"
     :context-window 1048576
     :max-output-tokens 65536
     :supports-images-p t
     :supports-tools-p t
     :reasoning-p t
     :input-price 1.5d0
     :output-price 7.5d0
     :cache-read-price 0.15d0
     :cache-write-price 0d0)
    (:provider :deepseek
     :id "deepseek-v4-flash"
     :context-window 1000000
     :max-output-tokens 384000
     :supports-images-p nil
     :supports-tools-p t
     :reasoning-p t
     :input-price 0.14d0
     :output-price 0.28d0
     :cache-read-price 0.0028d0
     :cache-write-price 0d0)
    (:provider :deepseek
     :id "deepseek-v4-pro"
     :context-window 1000000
     :max-output-tokens 384000
     :supports-images-p nil
     :supports-tools-p t
     :reasoning-p t
     :input-price 0.435d0
     :output-price 0.87d0
     :cache-read-price 0.003625d0
     :cache-write-price 0d0)
    (:provider :ollama
     :id "gpt-oss:20b"
     :context-window 131072
     :max-output-tokens 32768
     :supports-images-p nil
     :supports-tools-p t
     :reasoning-p t
     :input-price 0d0
     :output-price 0d0
     :cache-read-price 0d0
     :cache-write-price 0d0)))

(defparameter *compat-key-map*
  '(("deferredToolsMode" . :deferred-tools-mode)
    ("maxTokensField" . :max-tokens-field)
    ("requiresReasoningContentOnAssistantMessages"
     . :requires-reasoning-content-on-assistant-messages)
    ("supportsCacheControlOnTools"
     . :supports-cache-control-on-tools)
    ("supportsDeveloperRole" . :supports-developer-role)
    ("supportsEagerToolInputStreaming"
     . :supports-eager-tool-input-streaming)
    ("supportsLongCacheRetention"
     . :supports-long-cache-retention)
    ("supportsReasoningEffort" . :supports-reasoning-effort)
    ("supportsStore" . :supports-store)
    ("supportsStrictMode" . :supports-strict-mode)
    ("supportsStrictTools" . :supports-strict-tools)
    ("supportsTemperature" . :supports-temperature)
    ("thinkingFormat" . :thinking-format)))

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
                              '(:deferred-tools-mode
                                :max-tokens-field
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
     (number-or-zero (json-get cost "cacheWrite")))))

(defun catalog-rows ()
  (let ((catalog
          (cadr-ai::parse-json
           (uiop:read-file-string
            *catalog-fixture*
            :external-format :utf-8))))
    (append
     *base-rows*
     (loop for provider in (sorted-json-keys catalog)
           for models = (json-get catalog provider)
           append
           (loop for id in (sorted-json-keys models)
                 collect (model-row provider
                                    (json-get models id)))))))

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
     ";; Generated by scripts/refresh-model-catalog.lisp from the fixed Wave 1 catalog fixture."
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
