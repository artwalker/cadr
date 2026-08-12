(in-package #:cadr-ai/tests)

(in-suite cadr-ai-suite)

(defun runtime-test-model (provider id)
  (cadr-ai:make-model
   :id id :name id :provider provider :api :test-api
   :base-url "https://example.test/v1"
   :context-window 10000 :max-tokens 1000))

(defun runtime-ok-message (model &optional (text "ok"))
  (cadr-ai:make-assistant-message
   :api (cadr-ai:model-api model)
   :provider (cadr-ai:model-provider model)
   :model (cadr-ai:model-id model)
   :content (list (cadr-ai:make-text-content :text text))
   :stop-reason :stop))

(defun runtime-test-provider
    (id &key models auth-resolver refresh-function
            filter-function calls)
  (cadr-ai:make-runtime-provider
   :id id
   :name (symbol-name id)
   :models
   (or models (list (runtime-test-model id "model-a")))
   :api-key-auth-p t
   :auth-resolver
   (or auth-resolver
       (lambda (credential environment overrides)
         (declare (ignore credential environment overrides))
         (cadr-ai:make-runtime-auth-result
          :source "Ambient" :type :api-key)))
   :refresh-function refresh-function
   :filter-function filter-function
   :complete-function
   (lambda (model context options)
     (declare (ignore context))
     (when calls
       (vector-push-extend
        (list model options) calls))
     (runtime-ok-message model))))

(test models-runtime-registers-lists-and-isolates-provider-failures
  (let ((runtime (cadr-ai:make-models-runtime)))
    (cadr-ai:models-runtime-set-provider
     runtime
     (runtime-test-provider
      :p1
      :models
      (list
       (runtime-test-model :p1 "m1")
       (runtime-test-model :p1 "m2"))))
    (cadr-ai:models-runtime-set-provider
     runtime
     (runtime-test-provider
      :p2 :models (list (runtime-test-model :p2 "m3"))))
    (is (equal '(:p1 :p2)
               (mapcar #'cadr-ai:runtime-provider-id
                       (cadr-ai:models-runtime-providers runtime))))
    (is (equal '("m1" "m2" "m3")
               (mapcar #'cadr-ai:model-id
                       (cadr-ai:models-runtime-models runtime))))
    (is (string=
         "m3"
         (cadr-ai:model-id
          (cadr-ai:models-runtime-model runtime :p2 "m3"))))
    (cadr-ai:models-runtime-set-provider
     runtime
     (cadr-ai:make-runtime-provider
      :id :broken :name "broken"
      :models-function
      (lambda () (error "boom"))
      :api-key-auth-p t
      :auth-resolver
      (lambda (&rest ignored)
        (declare (ignore ignored))
        (cadr-ai:make-runtime-auth-result))))
    (is (null
         (cadr-ai:models-runtime-models runtime :broken)))
    (cadr-ai:models-runtime-delete-provider runtime :p1)
    (is (null
         (cadr-ai:models-runtime-provider runtime :p1)))))

(test models-runtime-auth-priority-refresh-and-availability
  (let* ((store (cadr-ai:make-memory-credential-store))
         (refreshes 0)
         (provider
           (cadr-ai:make-runtime-provider
            :id :oauth :name "OAuth"
            :models (list (runtime-test-model :oauth "m"))
            :oauth-auth-p t
            :oauth-refresh-function
            (lambda (credential)
              (incf refreshes)
              (cadr-ai:make-oauth-credential
               :provider :oauth
               :access "fresh"
               :refresh
               (cadr-ai:oauth-credential-refresh credential)
               :expires
               (+ (cadr-ai::unix-milliseconds) 3600000)))
            :oauth-to-auth-function
            (lambda (credential)
              (cadr-ai:make-runtime-auth-result
               :api-key
               (cadr-ai:oauth-credential-access credential)
               :source "OAuth"
               :type :oauth))))
         (runtime
           (cadr-ai:make-models-runtime
            :credential-store store)))
    (cadr-ai:models-runtime-set-provider runtime provider)
    (cadr-ai:credential-store-modify
     store :oauth
     (lambda (old)
       (declare (ignore old))
       (cadr-ai:make-oauth-credential
        :provider :oauth
        :access "expired"
        :refresh "refresh"
        :expires 0)))
    (let ((auth
            (cadr-ai:models-runtime-auth runtime :oauth)))
      (is (string=
           "fresh"
           (cadr-ai:runtime-auth-result-api-key auth))))
    (is (= 1 refreshes))
    (is (eq :oauth
            (cadr-ai:runtime-auth-check-type
             (cadr-ai:models-runtime-check-auth
              runtime :oauth))))
    (is (= 1
           (length
            (cadr-ai:models-runtime-available-models runtime))))))

(test models-runtime-merges-auth-and-explicit-request-options
  (let* ((calls
           (make-array 0 :adjustable t :fill-pointer 0))
         (provider
           (runtime-test-provider
            :p1
            :calls calls
            :auth-resolver
            (lambda (credential environment overrides)
              (declare (ignore credential environment overrides))
              (cadr-ai:make-runtime-auth-result
               :api-key "resolved-key"
               :headers
               '(("Authorization" . "Bearer resolved-key")
                 ("x-a" . "auth")
                 ("x-b" . "auth"))
               :base-url "https://auth.test/v1"
               :source "env"
               :type :api-key))))
         (runtime (cadr-ai:make-models-runtime)))
    (cadr-ai:models-runtime-set-provider runtime provider)
    (let ((message
            (cadr-ai:models-runtime-complete
             runtime
             (first (cadr-ai:runtime-provider-models provider))
             (cadr-ai:make-context)
             :api-key "explicit-key"
             :headers
             '(("authorization" . "Explicit token")
               ("x-b" . "explicit")))))
      (is (eq :stop
              (cadr-ai:assistant-message-stop-reason message))))
    (destructuring-bind (model options)
        (aref calls 0)
      (is (string=
           "https://auth.test/v1"
           (cadr-ai:model-base-url model)))
      (is (string=
           "explicit-key"
           (getf options :api-key)))
      (is (equal
           '(("authorization" . "Explicit token")
             ("x-a" . "auth")
             ("x-b" . "explicit"))
           (getf options :headers))))))

(test models-runtime-refresh-restores-cache-and-reports-errors
  (let* ((runtime (cadr-ai:make-models-runtime))
         (current (list (runtime-test-model :dynamic "before")))
         (refreshes 0))
    (cadr-ai:models-runtime-set-provider
     runtime
     (runtime-test-provider
      :dynamic
      :models current
      :refresh-function
      (lambda (credential store allow-network force)
        (declare (ignore credential force))
        (if allow-network
            (progn
              (incf refreshes)
              (setf current
                    (list
                     (runtime-test-model :dynamic "after")))
              (funcall store :write current))
            (let ((cached (funcall store :read)))
              (when cached (setf current cached)))))))
    (let ((result
            (cadr-ai:models-runtime-refresh runtime)))
      (is (null
           (cadr-ai:models-refresh-result-errors result)))
      (is (= 1 refreshes)))
    (cadr-ai:models-runtime-set-provider
     runtime
     (runtime-test-provider
      :flaky
      :refresh-function
      (lambda (&rest ignored)
        (declare (ignore ignored))
        (error "fetch failed"))))
    (let ((result
            (cadr-ai:models-runtime-refresh runtime)))
      (is (assoc :flaky
                 (cadr-ai:models-refresh-result-errors result))))))

(test memory-credential-store-lists-metadata-without-secrets
  (let ((store (cadr-ai:make-memory-credential-store)))
    (cadr-ai:credential-store-modify
     store :api
     (lambda (old)
       (declare (ignore old))
       (cadr-ai:make-api-key-credential
        :provider :api :key "secret")))
    (cadr-ai:credential-store-modify
     store :oauth
     (lambda (old)
       (declare (ignore old))
       (cadr-ai:make-oauth-credential
        :provider :oauth :access "access"
        :refresh "refresh" :expires 9999999999999)))
    (is (equal
         '((:api . :api-key) (:oauth . :oauth))
         (cadr-ai:credential-store-list store)))))

(test built-in-models-runtime-registers-the-exact-provider-surface
  (let ((runtime
          (cadr-ai:make-built-in-models-runtime
           :environment
           '(("DEEPSEEK_API_KEY" . "test-deepseek")))))
    (is (= 40
           (length
            (cadr-ai:models-runtime-providers runtime))))
    (is (= 1220
           (length
            (cadr-ai:models-runtime-models runtime))))
    (is (eq :api-key
            (cadr-ai:runtime-auth-check-type
             (cadr-ai:models-runtime-check-auth
              runtime :deepseek))))
    (is (null
         (cadr-ai:models-runtime-check-auth
          runtime :anthropic)))
    (is (null
         (cadr-ai:models-runtime-check-auth
          runtime :ollama)))))

(test built-in-runtime-resolves-codex-oauth-without-api-key-fallback
  (let* ((store (cadr-ai:make-memory-credential-store))
         (runtime
           (cadr-ai:make-built-in-models-runtime
            :credential-store store
            :environment nil)))
    (cadr-ai:credential-store-modify
     store :openai-codex
     (lambda (old)
       (declare (ignore old))
       (cadr-ai:make-oauth-credential
        :provider :openai-codex
        :access "oauth-access"
        :refresh "refresh"
        :expires
        (+ (cadr-ai::unix-milliseconds) 3600000))))
    (let ((auth
            (cadr-ai:models-runtime-auth
             runtime :openai-codex)))
      (is (eq :oauth
              (cadr-ai:runtime-auth-result-type auth)))
      (is (string=
           "oauth-access"
           (cadr-ai:runtime-auth-result-api-key auth))))))

(test api-key-credential-environment-round-trips
  (uiop:with-temporary-file (:pathname path)
    (when (probe-file path)
      (delete-file path))
    (cadr-ai:write-auth-credential
     path
     (cadr-ai:make-api-key-credential
      :provider :cloudflare-ai-gateway
      :key "key"
      :environment
      '(("CLOUDFLARE_ACCOUNT_ID" . "account")
        ("CLOUDFLARE_GATEWAY_ID" . "gateway"))))
    (let ((credential
            (cadr-ai:read-auth-credential
             path :cloudflare-ai-gateway)))
      (is (equal
           '(("CLOUDFLARE_ACCOUNT_ID" . "account")
             ("CLOUDFLARE_GATEWAY_ID" . "gateway"))
           (cadr-ai:api-key-credential-environment
            credential))))))

(test models-runtime-api-key-login-uses-opaque-interaction-and-persists
  (let* ((prompts nil)
         (events nil)
         (aborted-p nil)
         (store (cadr-ai:make-memory-credential-store))
         (runtime
           (cadr-ai:make-models-runtime
            :credential-store store))
         (interaction
           (cadr-ai:make-runtime-auth-interaction
            :prompt-function
            (lambda (prompt)
              (push prompt prompts)
              "secret")
            :notify-function
            (lambda (event)
              (push event events))
            :abort-p
            (lambda () aborted-p))))
    (cadr-ai:models-runtime-set-provider
     runtime
     (cadr-ai:make-runtime-provider
      :id :interactive
      :name "Interactive"
      :api-key-auth-p t
      :api-key-login-function
      (lambda (login-interaction)
        (cadr-ai:runtime-auth-interaction-notify
         login-interaction
         '(:type :info :message "Checking"))
        (cadr-ai:make-api-key-credential
         :provider :interactive
         :key
         (cadr-ai:runtime-auth-interaction-prompt
          login-interaction
          '(:type :secret
            :message "API key"
            :placeholder "optional"))))))
    (let ((credential
            (cadr-ai:models-runtime-login-api-key
             runtime :interactive interaction)))
      (is (typep credential 'cadr-ai:api-key-credential))
      (is (string= "secret"
                   (cadr-ai:api-key-credential-key credential)))
      (is (eq credential
              (cadr-ai:credential-store-read
               store :interactive))))
    (is (equal
         '((:type :secret
            :message "API key"
            :placeholder "optional"))
         prompts))
    (is (equal
         '((:type :info :message "Checking"))
         events))
    (setf aborted-p t)
    (is (cadr-ai:runtime-auth-interaction-aborted-p
         interaction))
    (signals cadr-ai:models-runtime-error
      (cadr-ai:models-runtime-login-api-key
       runtime :missing interaction))))

(test models-runtime-prefers-provider-auth-check
  (let* ((check-input nil)
         (runtime (cadr-ai:make-models-runtime)))
    (cadr-ai:models-runtime-set-provider
     runtime
     (cadr-ai:make-runtime-provider
      :id :checked
      :name "Checked"
      :models (list (runtime-test-model :checked "m"))
      :api-key-auth-p t
      :auth-check-function
      (lambda (credential environment)
        (setf check-input (list credential environment))
        (cadr-ai:make-runtime-auth-check
         :source "Custom check"
         :type :api-key))
      :auth-resolver
      (lambda (&rest ignored)
        (declare (ignore ignored))
        (error "resolver must not run"))))
    (let ((check
            (cadr-ai:models-runtime-check-auth
             runtime :checked)))
      (is (string=
           "Custom check"
           (cadr-ai:runtime-auth-check-source check))))
    (is (equal '(nil nil) check-input))))

(test models-runtime-refresh-context-is-additive-and-old-refresh-stays-compatible
  (let* ((runtime (cadr-ai:make-models-runtime))
         (context-seen nil)
         (legacy-call nil)
         (abort-p (lambda () nil)))
    (cadr-ai:models-runtime-set-provider
     runtime
     (cadr-ai:make-runtime-provider
      :id :contextual
      :name "Contextual"
      :api-key-auth-p t
      :auth-resolver
      (lambda (&rest ignored)
        (declare (ignore ignored))
        (cadr-ai:make-runtime-auth-result
         :api-key "context-key"
         :source "Ambient"
         :type :api-key))
      :refresh-context-function
      (lambda (context)
        (setf context-seen context)
        (funcall
         (cadr-ai:runtime-refresh-context-store context)
         :write
         '(:cached t)))))
    (cadr-ai:models-runtime-set-provider
     runtime
     (cadr-ai:make-runtime-provider
      :id :legacy
      :name "Legacy"
      :api-key-auth-p t
      :auth-resolver
      (lambda (&rest ignored)
        (declare (ignore ignored))
        (cadr-ai:make-runtime-auth-result
         :api-key "legacy-key"
         :source "Ambient"
         :type :api-key))
      :refresh-function
      (lambda (credential store allow-network force)
        (setf legacy-call
              (list credential store allow-network force)))))
    (let ((result
            (cadr-ai:models-runtime-refresh
             runtime
             :allow-network t
             :force t
             :abort-p abort-p)))
      (is (null
           (cadr-ai:models-refresh-result-errors result))))
    (is (typep
         (cadr-ai:runtime-refresh-context-credential
          context-seen)
         'cadr-ai:api-key-credential))
    (is (cadr-ai:runtime-refresh-context-allow-network-p
         context-seen))
    (is (cadr-ai:runtime-refresh-context-force-p
         context-seen))
    (is (not
         (cadr-ai:runtime-refresh-context-aborted-p
          context-seen)))
    (is (equal
         '(:cached t)
         (funcall
          (cadr-ai:runtime-refresh-context-store
           context-seen)
          :read)))
    (is (= 4 (length legacy-call)))
    (is (typep (first legacy-call)
               'cadr-ai:api-key-credential))
    (is (functionp (second legacy-call)))
    (is (third legacy-call))
    (is (fourth legacy-call))))
