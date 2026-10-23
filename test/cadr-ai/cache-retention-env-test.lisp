(in-package #:cadr-ai/tests)

(in-suite cadr-ai-suite)

(defun %set-cache-retention-env (name value)
  (if value
      (setf (uiop:getenv name) value)
      (sb-posix:unsetenv name)))

(defun call-with-cache-retention-env (cadr upstream function)
  (let ((saved-cadr (uiop:getenv "CADR_CACHE_RETENTION"))
        (saved-upstream (uiop:getenv "PI_CACHE_RETENTION")))
    (unwind-protect
         (progn
           (%set-cache-retention-env "CADR_CACHE_RETENTION" cadr)
           (%set-cache-retention-env "PI_CACHE_RETENTION" upstream)
           (funcall function))
      (%set-cache-retention-env "CADR_CACHE_RETENTION" saved-cadr)
      (%set-cache-retention-env "PI_CACHE_RETENTION" saved-upstream))))

(defun cache-retention-context ()
  (cadr-ai:make-context
   :system-prompt "Be precise."
   :messages
   (list (cadr-ai:make-user-message :content "hi" :timestamp 1))))

(defun anthropic-cache-control (environment &key retention compat)
  (let* ((provider
           (cadr-ai:make-anthropic-provider
            :api-key "key"
            :options (list :environment environment)))
         (model
           (cadr-ai:make-model
            :id "claude-sonnet-4-5"
            :provider :anthropic
            :api :anthropic-messages
            :base-url "https://api.anthropic.com"
            :max-tokens 1024
            :compat compat))
         (request
           (apply #'cadr-ai:build-request
                  provider model (cache-retention-context)
                  :stream-p t
                  (when retention (list :cache-retention retention))))
         (system
           (cadr-ai::json-get
            (cadr-ai:request-spec-payload request) "system")))
    (cadr-ai::json-get (aref system 0) "cache_control")))

(defun completions-cache-payload
    (base-url environment &key retention compat session-id provider)
  (let* ((provider
           (or provider
               (cadr-ai:make-openai-completions-provider
                :api-key "key"
                :options (list :environment environment))))
         (model
           (cadr-ai:make-model
            :id "gpt-4.1"
            :provider :openai
            :api :openai-completions
            :base-url base-url
            :max-tokens 1024
            :compat compat))
         (request
           (apply #'cadr-ai:build-request
                  provider model (cache-retention-context)
                  :stream-p t
                  :session-id session-id
                  (when retention (list :cache-retention retention)))))
    (cadr-ai:request-spec-payload request)))

(defun responses-cache-payload
    (environment &key retention compat session-id
                      (provider-id :openai)
                      (api :openai-responses)
                      (base-url "https://api.openai.com/v1")
                      provider)
  (let* ((provider
           (or provider
               (cadr-ai:make-openai-provider
                :api-key "sk-test"
                :options (list :environment environment))))
         (model
           (cadr-ai:make-model
            :id "gpt-4.1"
            :provider provider-id
            :api api
            :base-url base-url
            :max-tokens 1024
            :compat compat))
         (request
           (apply #'cadr-ai:build-request
                  provider model (cache-retention-context)
                  :stream-p t
                  :session-id session-id
                  (when retention (list :cache-retention retention)))))
    (cadr-ai:request-spec-payload request)))

(defun pi-messages-cache-retention (environment &key retention)
  (let* ((provider
           (cadr-ai:make-pi-messages-provider
            :api-key "key"
            :options (list :environment environment)))
         (model
           (cadr-ai:make-model
            :id "pi-test"
            :provider :pi
            :api :pi-messages
            :base-url "https://example.invalid/v1"
            :max-tokens 1024))
         (request
           (apply #'cadr-ai:build-request
                  provider model (cache-retention-context)
                  :stream-p t
                  (when retention (list :cache-retention retention))))
         (options
           (cadr-ai::json-get
            (cadr-ai:request-spec-payload request) "options")))
    (cadr-ai::json-get options "cacheRetention")))

(defun bedrock-system-cache-point (environment)
  (let* ((provider
           (cadr-ai:make-bedrock-provider
            :api-key "bearer-token"
            :options (list :environment environment)))
         (model
           (cadr-ai:make-model
            :id "us.anthropic.claude-sonnet-4-5"
            :provider :amazon-bedrock
            :api :bedrock-converse-stream
            :base-url "https://bedrock-runtime.us-east-1.amazonaws.com"
            :max-tokens 1024))
         (request
           (cadr-ai:build-request
            provider model (cache-retention-context) :stream-p t))
         (system
           (cadr-ai::json-get
            (cadr-ai:request-spec-payload request) "system")))
    (when (> (length system) 1)
      (cadr-ai::json-get (aref system 1) "cachePoint"))))

(test cache-retention-env-anthropic-defaults-and-overrides
  ;; pi@4a080252f packages/ai/test/cache-retention.test.ts
  (call-with-cache-retention-env
   nil "long"
   (lambda ()
     (let ((control (anthropic-cache-control nil)))
       (is (string= "ephemeral" (cadr-ai::json-get control "type")))
       (is (null (cadr-ai::json-get control "ttl"))))))
  (call-with-cache-retention-env
   "long" "short"
   (lambda ()
     (is (string= "1h"
                  (cadr-ai::json-get
                   (anthropic-cache-control nil) "ttl")))
     (is (null
          (cadr-ai::json-get
           (anthropic-cache-control
            nil
            :compat '(:supports-long-cache-retention nil))
           "ttl")))
     (let ((overridden
             (anthropic-cache-control
              '(("CADR_CACHE_RETENTION" . "long"))
              :retention :short)))
       (is (string= "ephemeral" (cadr-ai::json-get overridden "type")))
       (is (null (cadr-ai::json-get overridden "ttl"))))
     (is (null
          (anthropic-cache-control
           '(("CADR_CACHE_RETENTION" . "long"))
           :retention :none)))
     (is (null
          (cadr-ai::json-get
           (anthropic-cache-control
            '(("CADR_CACHE_RETENTION" . "LONG")))
           "ttl")))
     (is (string= "1h"
                  (cadr-ai::json-get
                   (anthropic-cache-control
                    '(("CADR_CACHE_RETENTION" . "")))
                   "ttl")))
     (is (null
          (cadr-ai::json-get
           (anthropic-cache-control
            '(("CADR_CACHE_RETENTION" . "short")))
           "ttl"))))))

(test cache-retention-env-completions-and-responses
  (call-with-cache-retention-env
   nil nil
   (lambda ()
     (let ((payload
             (completions-cache-payload
              "https://api.openai.com/v1" nil
              :session-id "session-1")))
       (is (string= "session-1"
                    (cadr-ai::json-get payload "prompt_cache_key")))
       (is (null (cadr-ai::json-get payload "prompt_cache_retention"))))
     (let ((payload
             (responses-cache-payload
              nil :session-id "session-1")))
       (is (string= "session-1"
                    (cadr-ai::json-get payload "prompt_cache_key")))
       (is (null (cadr-ai::json-get payload "prompt_cache_retention"))))))
  (call-with-cache-retention-env
   "long" "short"
   (lambda ()
     (let ((direct
             (completions-cache-payload
              "https://api.openai.com/v1" nil
              :session-id "session-1"))
           (proxy
             (completions-cache-payload
              "https://proxy.example/v1" nil
              :session-id "session-1"))
           (unsupported
             (completions-cache-payload
              "https://proxy.example/v1" nil
              :compat '(:supports-long-cache-retention nil)
              :session-id "session-1"))
           (responses
             (responses-cache-payload
              nil :session-id "session-1"))
           (explicit
             (responses-cache-payload
              nil
              :compat '(:supports-explicit-prompt-cache-mode t)
              :session-id "session-1"))
           (held
             (completions-cache-payload
              "https://api.openai.com/v1"
              '(("CADR_CACHE_RETENTION" . "short"))
              :session-id "session-1")))
       (is (string= "24h"
                    (cadr-ai::json-get direct "prompt_cache_retention")))
       (is (string= "24h"
                    (cadr-ai::json-get proxy "prompt_cache_retention")))
       (is (string= "session-1"
                    (cadr-ai::json-get proxy "prompt_cache_key")))
       (is (null
            (cadr-ai::json-get unsupported "prompt_cache_retention")))
       (is (null (cadr-ai::json-get unsupported "prompt_cache_key")))
       (is (string= "24h"
                    (cadr-ai::json-get responses "prompt_cache_retention")))
       (is (string= "30m"
                    (cadr-ai::json-get
                     (cadr-ai::json-get explicit "prompt_cache_options")
                     "ttl")))
       (is (null (cadr-ai::json-get explicit "prompt_cache_retention")))
       (is (null (cadr-ai::json-get held "prompt_cache_retention")))
       (is (null
            (cadr-ai::json-get
             (completions-cache-payload
              "https://api.openai.com/v1"
              '(("CADR_CACHE_RETENTION" . "long"))
              :retention :none
              :session-id "session-1")
             "prompt_cache_key")))))))

(test cache-retention-env-pi-messages-omits-the-default
  (call-with-cache-retention-env
   nil "long"
   (lambda ()
     (is (null (pi-messages-cache-retention nil)))))
  (call-with-cache-retention-env
   "long" nil
   (lambda ()
     (is (string= "long" (pi-messages-cache-retention nil)))
     (is (string= "short"
                  (pi-messages-cache-retention
                   '(("CADR_CACHE_RETENTION" . "long"))
                   :retention :short)))
     (is (string= "none"
                  (pi-messages-cache-retention
                   nil :retention :none))))))

(test cache-retention-env-bedrock-writes-one-hour
  (call-with-cache-retention-env
   "long" "short"
   (lambda ()
     (let ((point (bedrock-system-cache-point nil)))
       (is (string= "default" (cadr-ai::json-get point "type")))
       (is (string= "ONE_HOUR" (cadr-ai::json-get point "ttl"))))))
  (call-with-cache-retention-env
   nil "long"
   (lambda ()
     (let ((point
             (bedrock-system-cache-point
              '(("CADR_CACHE_RETENTION" . "long")
                ("PI_CACHE_RETENTION" . "ignored")))))
       (is (string= "ONE_HOUR" (cadr-ai::json-get point "ttl"))))
     (let ((point
             (bedrock-system-cache-point
              '(("PI_CACHE_RETENTION" . "long")))))
       (is (string= "default" (cadr-ai::json-get point "type")))
       (is (null (cadr-ai::json-get point "ttl")))))))

(test cache-retention-env-skips-codex-and-azure-responses
  (call-with-cache-retention-env
   "long" nil
   (lambda ()
     (let* ((codex (provider-case :codex))
            (codex-model (nth-value 1 (provider-case :codex)))
            (codex-payload
              (cadr-ai:request-spec-payload
               (cadr-ai:build-request
                codex codex-model (cache-retention-context)
                :stream-p t :session-id "session-1")))
            (azure (provider-case :azure))
            (azure-model (nth-value 1 (provider-case :azure)))
            (azure-payload
              (cadr-ai:request-spec-payload
               (cadr-ai:build-request
                azure azure-model (cache-retention-context)
                :stream-p t :session-id "session-1"))))
       (is (string= "session-1"
                    (cadr-ai::json-get codex-payload "prompt_cache_key")))
       (is (null
            (cadr-ai::json-get codex-payload "prompt_cache_retention")))
       (is (string= "session-1"
                    (cadr-ai::json-get azure-payload "prompt_cache_key")))
       (is (null
            (cadr-ai::json-get azure-payload "prompt_cache_retention"))))))
  (call-with-cache-retention-env
   "long" nil
   (lambda ()
     (multiple-value-bind (provider model)
         (cadr-ai:instantiate-provider
          :azure :model-id "deepseek-v4-pro" :api-key "test-key"
          :options
          '(:azure-base-url
            "https://my-resource.services.ai.azure.com"))
       (let ((payload
               (cadr-ai:request-spec-payload
                (cadr-ai:build-request
                 provider model (cache-retention-context)
                 :stream-p t :session-id "session-1"))))
         (is (null (cadr-ai::json-get payload "prompt_cache_key")))
         (is (null
              (cadr-ai::json-get payload "prompt_cache_retention"))))))))
