(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(test file-auth-storage-resolves-preserves-serializes-and-fails-closed
  (with-test-directory (root)
    (let* ((path (merge-pathnames "agent/auth.json" root))
           (storage
             (cadr-cli:make-file-auth-storage path)))
      (write-json
       path
       (args
        "anthropic"
        (args
         "type" "api_key"
         "key" "$SCOPED_KEY"
         "env"
         (args
          "SCOPED_KEY" "scoped"
          "REGION" "test"))))
      (let ((credential
              (cadr-cli:auth-storage-read
               storage "anthropic")))
        (is (string=
             "scoped"
             (cadr-ai:api-key-credential-key
              credential)))
        (is (string=
             "test"
             (cdr
              (assoc
               "REGION"
               (cadr-ai:api-key-credential-environment
                credential)
               :test #'string=)))))
      (write-json
       path
       (args
        "anthropic"
        (args "type" "api_key" "key" "old")
        "openai"
        (args "type" "api_key" "key" "external")))
      (cadr-cli:auth-storage-modify
       storage "anthropic"
       (lambda (current)
         (declare (ignore current))
         (cadr-ai:make-api-key-credential
          :provider :anthropic
          :key "new")))
      (is (string=
           "new"
           (cadr-ai:api-key-credential-key
            (cadr-cli:auth-storage-read
             storage "anthropic"))))
      (is (string=
           "external"
           (cadr-ai:api-key-credential-key
            (cadr-cli:auth-storage-read
             storage "openai"))))
      (is (equal
           '(("anthropic" . "api_key")
             ("openai" . "api_key"))
           (cadr-cli:auth-storage-list storage)))
      (cadr-cli:auth-storage-delete
       storage "anthropic")
      (is (null
           (cadr-cli:auth-storage-read
            storage "anthropic")))
      (write-text path "{invalid-json")
      (signals error
        (cadr-cli:auth-storage-modify
         storage "google"
         (lambda (current)
           (declare (ignore current))
           (cadr-ai:make-api-key-credential
            :provider :google
            :key "not-written"))))
      (is (string= "{invalid-json"
                   (read-text path))))))

(test file-auth-storage-lock-failures-are-transactional-and-retryable
  (with-test-directory (root)
    (let* ((path
             (merge-pathnames
              "agent/auth.json" root))
           (storage
             (cadr-cli:make-file-auth-storage
              path))
           (real-acquire
             cadr-cli::*auth-file-lock-acquire-function*)
           (attempts 0))
      (write-json
       path
       (args
        "anthropic"
        (args
         "type" "api_key"
         "key" "stored")))
      (let ((cadr-cli::*auth-file-lock-acquire-function*
              (lambda (lock-path)
                (incf attempts)
                (if (= attempts 1)
                    (error "lock compromised")
                    (funcall
                     real-acquire lock-path)))))
        (signals error
          (cadr-cli:auth-storage-modify
           storage "openai"
           (lambda (current)
             (declare (ignore current))
             (cadr-ai:make-api-key-credential
              :provider :openai
              :key "new"))))
        (is (null
             (cadr-cli:auth-storage-read
              storage "openai")))
        (cadr-cli:auth-storage-modify
         storage "openai"
         (lambda (current)
           (declare (ignore current))
           (cadr-ai:make-api-key-credential
            :provider :openai
            :key "new"))))
      (is (string=
           "new"
           (cadr-ai:api-key-credential-key
            (cadr-cli:auth-storage-read
             storage "openai"))))
      (let ((before
              (uiop:read-file-string
               path :external-format :utf-8)))
        (cadr-cli:auth-storage-modify
         storage "openai"
         (lambda (current)
           (declare (ignore current))
           nil))
        (is (string=
             before
             (uiop:read-file-string
              path :external-format :utf-8)))))))

(test file-auth-storage-serializes-concurrent-process-local-writers
  (with-test-directory (root)
    (let* ((path
             (merge-pathnames
              "auth.json" root))
           (storage
             (cadr-cli:make-file-auth-storage
              path))
           (ready
             (sb-thread:make-semaphore
              :count 0))
           (release
             (sb-thread:make-semaphore
              :count 0))
           (first
             (sb-thread:make-thread
              (lambda ()
                (cadr-cli:auth-storage-modify
                 storage "one"
                 (lambda (current)
                   (declare (ignore current))
                   (sb-thread:signal-semaphore
                    ready)
                   (sb-thread:wait-on-semaphore
                    release)
                   (cadr-ai:make-api-key-credential
                    :provider :one
                    :key "first")))))))
      (sb-thread:wait-on-semaphore ready)
      (let ((second
              (sb-thread:make-thread
               (lambda ()
                 (cadr-cli:auth-storage-modify
                  storage "two"
                  (lambda (current)
                    (declare (ignore current))
                    (cadr-ai:make-api-key-credential
                     :provider :two
                     :key "second")))))))
        (sb-thread:signal-semaphore release)
        (sb-thread:join-thread first)
        (sb-thread:join-thread second))
      (is (equal
           '(("one" . "api_key")
             ("two" . "api_key"))
           (cadr-cli:auth-storage-list
            storage))))))

(test command-backed-and-runtime-credentials-match-storage-contract
  (with-test-directory (root)
    (let* ((path (merge-pathnames "auth.json" root))
           (storage
             (cadr-cli:make-file-auth-storage path)))
      (write-json
       path
       (args
        "anthropic"
        (args
         "type" "api_key"
         "key" "!printf command-key")))
      (is (string=
           "command-key"
           (cadr-ai:api-key-credential-key
            (cadr-cli:auth-storage-read
             storage "anthropic"))))
      (let ((runtime
              (cadr-cli:make-runtime-credentials
               storage)))
        (cadr-cli:runtime-credentials-set-api-key
         runtime "anthropic" "runtime")
        (cadr-cli:runtime-credentials-set-api-key
         runtime "openai" "other")
        (is (string=
             "runtime"
             (cadr-ai:api-key-credential-key
              (cadr-cli:auth-storage-read
               runtime "anthropic"))))
        (is (string=
             "command-key"
             (cadr-ai:api-key-credential-key
              (cadr-cli:auth-storage-read
               storage "anthropic"))))
        (is (equal
             '(("anthropic" . "api_key")
               ("openai" . "api_key"))
             (cadr-cli:auth-storage-list runtime)))
        (cadr-cli:runtime-credentials-remove-api-key
         runtime "anthropic")
        (is (string=
             "command-key"
             (cadr-ai:api-key-credential-key
              (cadr-cli:auth-storage-read
               runtime "anthropic"))))
        (cadr-cli:auth-storage-delete
         runtime "openai")
        (is (null
             (cadr-cli:auth-storage-read
              runtime "openai")))))))

(test file-models-store-preserves-unrelated-provider-catalogs
  (with-test-directory (root)
    (let* ((path
             (merge-pathnames
              "models-store.json" root))
           (store
             (cadr-cli:make-file-models-store path))
           (one
             (args
              "checkedAt" 100
              "models"
              (vector
               (args "id" "m1"))))
           (two
             (args
              "checkedAt" 200
              "models"
              (vector
               (args "id" "m2")))))
      (cadr-cli:models-store-write
       store "one" one)
      (cadr-cli:models-store-write
       store "two" two)
      (is (= 100
             (cadr-ai::json-get
              (cadr-cli:models-store-read
               store "one")
              "checkedAt")))
      (is (string=
           "m2"
           (cadr-ai::json-get
            (aref
             (cadr-ai::json-get
              (cadr-cli:models-store-read
               store "two")
              "models")
             0)
            "id")))
      (cadr-cli:models-store-delete
       store "one")
      (is (null
           (cadr-cli:models-store-read
            store "one")))
      (is (not
           (null
            (cadr-cli:models-store-read
             store "two")))))))

(test model-registry-overrides-merges-hot-reloads-and-keeps-scoped-order
  (with-test-directory (root)
    (let ((path (merge-pathnames "models.json" root)))
      (write-json
       path
       (args
        "providers"
        (args
         "anthropic"
         (args
          "baseUrl" "https://proxy.one/v1"
          "headers" (args "X-Test" "One"))
         "custom"
         (args
          "baseUrl" "http://localhost/v1"
          "api" "openai-completions"
          "models"
          (vector
           (args
            "id" "model:edition"
            "name" "Custom"
            "contextWindow" 4242
            "maxTokens" 512))))))
      (let ((registry
              (cadr-cli:make-model-registry
               :path path)))
        (is (null
             (cadr-cli:model-registry-error
              registry)))
        (let ((anthropic
                (remove
                 :anthropic
                 (cadr-cli:model-registry-all
                  registry)
                 :key #'cadr-ai:model-provider
                 :test-not #'eq)))
          (is (> (length anthropic) 1))
          (is (every
               (lambda (model)
                 (string=
                  "https://proxy.one/v1"
                  (cadr-ai:model-base-url model)))
               anthropic)))
        (multiple-value-bind
              (model error thinking)
            (cadr-cli:resolve-model
             registry
             "custom/model:edition:high")
          (is (null error))
          (is (string=
               "model:edition"
               (cadr-ai:model-id model)))
          (is (eq :high thinking)))
        (let* ((patterns
                 '("custom/*"
                   "anthropic/*"))
               (scoped
                 (cadr-cli:resolve-scoped-models
                  registry patterns)))
          (is (eq :custom
                  (cadr-ai:model-provider
                   (first scoped))))
          (is
           (member
            :anthropic scoped
            :key #'cadr-ai:model-provider)))
        (write-json
         path
         (args
          "providers"
          (args
           "anthropic"
           (args
            "baseUrl"
            "https://proxy.two/v1"))))
        (cadr-cli:refresh-model-registry
         registry)
        (is (string=
             "https://proxy.two/v1"
             (cadr-ai:model-base-url
              (find
               :anthropic
               (cadr-cli:model-registry-all
                registry)
               :key #'cadr-ai:model-provider))))
        (write-text path "{bad")
        (cadr-cli:refresh-model-registry
         registry)
        (is (not
             (null
              (cadr-cli:model-registry-error
               registry))))))))

(test model-registry-refresh-does-not-promote-benign-signals-to-user-errors
  (let ((registry
          (cadr-cli::%make-model-registry))
        (original
          (symbol-function
           'cadr-cli::read-models-config)))
    (unwind-protect
         (progn
           (setf
            (symbol-function
             'cadr-cli::read-models-config)
            (lambda (path)
              (declare (ignore path))
              (signal
               'asdf/plan:system-out-of-date
               :name "cadr-cli")
              (cadr-cli::empty-json-object)))
           (cadr-cli:refresh-model-registry registry)
           (is (null
                (cadr-cli:model-registry-error
                 registry)))
           (is (plusp
                (length
                 (cadr-cli:model-registry-all
                  registry)))))
      (setf
       (symbol-function
        'cadr-cli::read-models-config)
       original))))

(defun model-scope-test-model
    (provider id name)
  (cadr-ai:make-model
   :id id
   :name name
   :provider provider
   :api :openai-responses
   :base-url "https://example.invalid"
   :max-tokens 1024))

(test model-scope-resolves-partials-colons-globs-brackets-and-diagnostics
  (let* ((sonnet
           (model-scope-test-model
            :anthropic
            "claude-sonnet-4-5"
            "Claude Sonnet"))
         (dated
           (model-scope-test-model
            :anthropic
            "claude-sonnet-4-5-20250929"
            "Claude Sonnet dated"))
         (gpt
           (model-scope-test-model
            :openai "gpt-4o" "GPT 4o"))
         (colon
           (model-scope-test-model
            :openrouter
            "qwen/qwen3-coder:exacto"
            "Qwen Coder"))
         (bracketed
           (model-scope-test-model
            :custom
            "bracketed-model[1m]"
            "Bracketed"))
         (registry
           (cadr-cli::%make-model-registry
            :models
            (list sonnet dated gpt colon
                  bracketed))))
    (multiple-value-bind (scoped diagnostics)
        (cadr-cli::resolve-scoped-models-with-diagnostics
         registry
         '("sonnet:high"
           "gpt-4o:invalid"
           "openrouter/qwen/qwen3-coder:exacto"
           "custom/bracketed-model[1m]"
           "anthropic/*"
           "missing"))
      (is (equal
           '("claude-sonnet-4-5"
             "gpt-4o"
             "qwen/qwen3-coder:exacto"
             "bracketed-model[1m]"
             "claude-sonnet-4-5-20250929")
           (mapcar
            (lambda (entry)
              (cadr-ai:model-id
               (getf entry :model)))
            scoped)))
      (is (eq :high
              (getf (first scoped)
                    :thinking)))
      (is (null
           (getf (second scoped)
                 :thinking)))
      (is (equal
           '(:invalid-thinking-level :no-match)
           (mapcar
            (lambda (diagnostic)
              (getf diagnostic :code))
            diagnostics)))
      (is (equal
           '("gpt-4o:invalid" "missing")
           (mapcar
            (lambda (diagnostic)
              (getf diagnostic :pattern))
            diagnostics)))
      (is (equal
           '("anthropic/claude-sonnet-4-5"
             "openai/gpt-4o"
             "openrouter/qwen/qwen3-coder:exacto"
             "custom/bracketed-model[1m]"
             "anthropic/claude-sonnet-4-5-20250929"
             "missing")
           (cadr-cli::enabled-model-ids-for-patterns
            scoped diagnostics))))))

(test initial-scoped-model-prefers-saved-default-and-respects-existing-session
  (let* ((one
           (model-scope-test-model
            :faux "one" "One"))
         (two
           (model-scope-test-model
            :faux "two" "Two"))
         (scope
           (list
            (list :model two)
            (list :model one
                  :thinking :high))))
    (is (eq one
            (getf
             (cadr-cli::initial-scoped-model-entry
              scope "faux" "one")
             :model)))
    (is (eq two
            (getf
             (cadr-cli::initial-scoped-model-entry
              scope nil nil)
             :model)))
    (is (null
         (cadr-cli::initial-scoped-model-entry
          scope "faux" "one"
          :existing-session-p t)))
    (is (null
         (cadr-cli::initial-scoped-model-entry
          scope "faux" "one"
          :explicit-model-p t)))))

(test registry-model-config-and-selection-update-the-complete-runtime-surface
  (with-test-directory (root)
    (let* ((models-path
             (merge-pathnames "models.json" root))
           (settings-path
             (merge-pathnames "settings.json" root))
           (auth-path
             (merge-pathnames "auth.json" root))
           (config-path
             (merge-pathnames "config.json" root)))
      (write-json
       models-path
       (args
        "providers"
        (args
         "custom"
         (args
          "baseUrl" "https://custom.invalid/v1"
          "api" "openai-completions"
          "apiKey" "custom-secret"
          "models"
          (vector
           (args
            "id" "custom-model"
            "name" "Custom Model"
            "contextWindow" 8192
            "maxTokens" 1024))))))
      (let* ((registry
               (cadr-cli:make-model-registry
                :path models-path
                :credentials
                (cadr-cli:make-file-auth-storage
                 auth-path)))
             (custom
               (cadr-cli:model-registry-find
                registry :custom "custom-model"))
             (custom-config
               (cadr-cli::provider-config-for-model
                registry custom
                :config-path config-path
                :auth-path auth-path
                :allow-missing-auth-p t)))
        (let ((cadr-cli::*environment-function*
                (lambda (name)
                  (declare (ignore name))
                  nil)))
          (is (equal
               '("custom/custom-model")
               (mapcar
                #'cadr-cli::canonical-model-id
                (cadr-cli::model-registry-available-models
                 registry
                 :config-path config-path
                 :auth-path auth-path)))))
        (is (eq :custom
                (cadr-ai::provider-id
                 (cadr-cli:provider-config-provider
                  custom-config))))
        (is (string=
             "custom-secret"
             (cadr-ai::provider-api-key
              (cadr-cli:provider-config-provider
               custom-config))))
        (is (cadr-ai:models-equal-p
             custom
             (cadr-cli:provider-config-model
              custom-config)))
        (let* ((settings
                 (cadr-cli::make-settings-manager
                  :global-path settings-path))
               (lifecycle-events nil)
               (session
                 (cadr-agent:create-session
                  :directory
                  (merge-pathnames "sessions/" root)
                  :cwd root))
               (bundle
                 (cadr-agent::make-extension-bundle
                  :id "model-production-events"
                  :path "/tmp/model-production-events.lisp"))
               (host
                 (cadr-agent::make-extension-host :cwd root))
               (agent
                 (cadr-agent:make-agent
                  :provider
                  (cadr-cli:provider-config-provider
                   custom-config)
                  :model custom
                  :extension-host host
                  :session session))
               (openai
                 (cadr-cli:model-registry-find
                  registry :openai "gpt-5.5"))
               (selected nil))
          (cadr-agent::call-with-extension-registration
           bundle
           (lambda ()
             (dolist (event '(:model-select :thinking-level-select))
               (cadr-agent:define-event-hook
                event
                :handler
                (lambda (value context)
                  (declare (ignore context))
                  (push (cadr-agent:extension-event-type value)
                        lifecycle-events)
                  nil)))))
          (cadr-agent::replace-extension-bundles host (list bundle))
          (setf selected
                (cadr-cli::apply-cli-model-selection
                 agent registry openai settings
                 :config-path config-path
                 :auth-path auth-path
                 :source :interactive))
          (is (cadr-ai:models-equal-p
               openai
               (cadr-agent:agent-model agent)))
          (is (eq
               (cadr-agent:agent-provider agent)
               (cadr-agent::extension-host-base-agent-provider
                host)))
          (is (cadr-ai:models-equal-p
               openai
               (cadr-agent::extension-host-base-agent-model
                host)))
          (is (string=
               "openai"
               (cadr-cli::settings-default-provider
                settings)))
          (is (string=
               "gpt-5.5"
               (cadr-cli::settings-default-model
                settings)))
          (is (eq
               :model-change
               (cadr-agent:session-entry-type
                (car
                 (last
                  (cadr-agent:session-entries
                   session))))))
          (is (cadr-ai:models-equal-p
               openai
               (cadr-cli:provider-config-model
                selected)))
          (is (member :model-select lifecycle-events))
          (cadr-cli::set-cli-thinking-level agent settings :high)
          (is (member :thinking-level-select lifecycle-events)))))))

(test model-spec-and-credential-print-cover-colons-types-and-refresh
  (let ((parsed
          (cadr-cli:parse-model-spec
           "provider/model:with:colon:max")))
    (is (string=
         "provider"
         (getf parsed :provider)))
    (is (string=
         "model:with:colon"
         (getf parsed :model)))
    (is (eq :max
            (getf parsed :thinking))))
  (let ((parsed
          (cadr-cli:parse-credential-print-command
           '("auth" "print-bearer-token"
             "--min-expiry" "30m"
             "--provider" "openai-codex"))))
    (is (eq :bearer-token
            (getf parsed :kind)))
    (is (= 1800000
           (getf parsed
                 :minimum-expiry-ms)))
    (is (equal
         '("--provider" "openai-codex")
         (getf parsed :arguments))))
  (signals cadr-cli::credential-print-error
    (cadr-cli:parse-credential-print-command
     '("auth" "print-api-key"
       "--min-expiry" "30m")))
  (let ((storage
          (cadr-ai:make-memory-credential-store)))
    (cadr-ai:credential-store-modify
     storage :openai
     (lambda (current)
       (declare (ignore current))
       (cadr-ai:make-api-key-credential
        :provider :openai
        :key "secret")))
    (is (string=
         "secret"
         (cadr-cli:credential-for-print
          storage "openai" :api-key)))
    (cadr-ai:credential-store-modify
     storage :openai-codex
     (lambda (current)
       (declare (ignore current))
       (cadr-ai:make-oauth-credential
        :provider :openai-codex
        :access "old"
        :refresh "refresh"
        :expires 0)))
    (is (string=
         "fresh"
         (cadr-cli:credential-for-print
          storage "openai-codex"
          :bearer-token
          :refresh-function
          (lambda (credential)
            (cadr-ai:make-oauth-credential
             :provider :openai-codex
             :access "fresh"
             :refresh
             (cadr-ai:oauth-credential-refresh
              credential)
             :expires
             (+ (cadr-ai::unix-milliseconds)
                3600000))))))))

(test credential-print-command-runs-as-a-top-level-one-shot
  (with-test-directory (root)
    (let ((auth
            (merge-pathnames "auth.json" root))
          (output
            (make-string-output-stream)))
      (cadr-ai:write-auth-credential
       auth
       (cadr-ai:make-api-key-credential
        :provider :openai
        :key "print-me"))
      (multiple-value-bind (handled-p status)
          (cadr-cli::run-credential-print-command
           '("auth" "print-api-key"
             "--provider" "openai"
             "--model" "gpt-5.5")
           :auth-path auth
           :output output)
        (is (eq t handled-p))
        (is (= 0 status))
        (is (string=
             (format nil "print-me~%")
             (get-output-stream-string
              output))))
      (signals cadr-cli::credential-print-error
        (cadr-cli::run-credential-print-command
         '("auth" "print-api-key"
           "--provider" "openai")
         :auth-path auth)))))
