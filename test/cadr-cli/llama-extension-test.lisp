(in-package #:cadr-cli/tests)

(in-suite cadr-cli-suite)

(test goal18-llama-context-label-matches-the-baseline
  ;; Baseline ui.ts:35-39 contextLabel: meta n_ctx ?? n_ctx_train, then
  ;; the --ctx-size/-c/-ctx status arg; >=1000 renders as Nk.
  (flet ((model (&key context-window training-context-window args)
           (cadr-cli::make-llama-model-info
            :id "m"
            :status :loaded
            :context-window context-window
            :training-context-window training-context-window
            :arguments args)))
    (is (string= "8k" (cadr-cli::llama-context-label (model :context-window 8192))))
    (is (string= "8k" (cadr-cli::llama-context-label (model :training-context-window 8192))))
    (is (string= "66k" (cadr-cli::llama-context-label (model :context-window 65536))))
    (is (string= "512" (cadr-cli::llama-context-label (model :context-window 512))))
    (is (string= "1k" (cadr-cli::llama-context-label (model :context-window 1000))))
    (is (string= "8k" (cadr-cli::llama-context-label (model :context-window 8499))))
    (is (string= "9k" (cadr-cli::llama-context-label (model :context-window 8500))))
    (is (string= "4k" (cadr-cli::llama-context-label (model :args '("--ctx-size" "4096")))))
    (is (string= "4k" (cadr-cli::llama-context-label (model :args '("-c" "4096")))))
    (is (string= "4k" (cadr-cli::llama-context-label (model :args '("-ctx" "4096")))))
    (is (null (cadr-cli::llama-context-label (model :args '("--ctx-size"))))
        "a flag without a value has no label")
    (is (null (cadr-cli::llama-context-label (model :args '("--ctx-size" "junk"))))
        "a non-numeric value has no label")
    (is (null (cadr-cli::llama-context-label (model :args '("--ctx-size" "0"))))
        "a non-positive value has no label")
    (is (null (cadr-cli::llama-context-label (model))))))

(test goal18-llama-model-description-matches-the-baseline
  ;; Baseline ui.ts:41-52 modelDescription.
  (flet ((model (status &key context-window)
           (cadr-cli::make-llama-model-info
            :id "m"
            :status status
            :context-window context-window)))
    (is (string= "loaded" (cadr-cli::llama-model-description (model :loaded))))
    (is (string= "loaded · 8k context" (cadr-cli::llama-model-description (model :loaded :context-window 8192))))
    (is (string= "loaded · 8k context" (cadr-cli::llama-model-description (model :sleeping :context-window 8192))))
    (is (string= "" (cadr-cli::llama-model-description (model :unloaded))))
    (is (string= "loading" (cadr-cli::llama-model-description (model :loading))))
    (is (string= "loading" (cadr-cli::llama-model-description (model :loading :context-window 8192)))
        "the context label only shows for loaded models")))

(test goal18-llama-compact-count-matches-the-baseline
  ;; Baseline ui.ts:102-106 compactCount.
  (is (string= "0" (cadr-cli::llama-compact-count 0)))
  (is (string= "999" (cadr-cli::llama-compact-count 999)))
  (is (string= "1.0k" (cadr-cli::llama-compact-count 1000)))
  (is (string= "1.2k" (cadr-cli::llama-compact-count 1234)))
  (is (string= "99.9k" (cadr-cli::llama-compact-count 99949)))
  (is (string= "100k" (cadr-cli::llama-compact-count 100000)))
  (is (string= "999k" (cadr-cli::llama-compact-count 999499)))
  (is (string= "1.0M" (cadr-cli::llama-compact-count 1000000)))
  (is (string= "3.4M" (cadr-cli::llama-compact-count 3400000)))
  (is (string= "10M" (cadr-cli::llama-compact-count 10000000)))
  (is (string= "250M" (cadr-cli::llama-compact-count 250000000))))

(defun llama-json-response (value)
  (values
   (cadr-ai::stringify-json value)
   200
   '(("content-type" . "application/json"))))

(defun llama-catalog-json (&rest models)
  (cadr-ai::json-object
   "data"
   (cadr-ai::list-json-array models)))

(defun llama-model-json
    (id status &key context-window training-context-window
       image-p source)
  (let ((model
          (cadr-ai::json-object
           "id" id
           "status"
           (cadr-ai::json-object "value" status))))
    (when (or context-window training-context-window)
      (cadr-ai::json-put
       model "meta"
       (cadr-ai::json-object
        "n_ctx" context-window
        "n_ctx_train" training-context-window)))
    (when image-p
      (cadr-ai::json-put
       model "architecture"
       (cadr-ai::json-object
        "input_modalities"
        (vector "text" "image"))))
    (when source
      (cadr-ai::json-put model "source" source))
    model))

(test llama-bundled-extension-registers-native-provider-and-command
  (with-test-directory (root)
    (let* ((manager
             (cadr-cli::make-cli-extension-manager
              :cwd root
              :global-directory
              (merge-pathnames "global/" root)
              :output (make-string-output-stream)))
           (report
             (cadr-cli::reload-cli-extensions manager))
           (host
             (cadr-cli::cli-extension-manager-host
              manager)))
      (is (= 1 (getf report :active)))
      (is (equal
           '(:llama.cpp)
           (mapcar
            #'cadr-ai:runtime-provider-id
            (cadr-agent::extension-host-native-providers
             host))))
      (is (find
           "llama"
           (cadr-agent::extension-snapshot-commands
            (cadr-agent::extension-host-current-snapshot
             host))
           :key
           #'cadr-agent::extension-command-definition-name
           :test #'string=)))))

(test llama-url-normalization-and-loaded-model-mapping-match-baseline
  (is (string=
       "http://127.0.0.1:8080"
       (cadr-cli::normalize-llama-server-url
        "http://127.0.0.1:8080/v1/")))
  (is (string=
       "https://example.com/prefix"
       (cadr-cli::normalize-llama-server-url
        "https://example.com/prefix/v1")))
  (signals cadr-ai:configuration-error
    (cadr-cli::normalize-llama-server-url
     "file:///tmp/llama"))
  (let ((controller
          (cadr-cli::make-llama-provider-controller)))
    (cadr-cli::llama-provider-set-catalog
     controller
     (list
      (cadr-cli::make-llama-model-info
       :id "loaded"
       :status :loaded
       :context-window 65536
       :training-context-window 131072
       :input-modalities '("text" "image"))
      (cadr-cli::make-llama-model-info
       :id "unloaded" :status :unloaded))
     "http://localhost:8080")
    (let ((models
            (cadr-ai:runtime-provider-models
             (cadr-cli::llama-provider-controller-provider
              controller))))
      (is (= 1 (length models)))
      (is (string= "loaded"
                   (cadr-ai:model-id (first models))))
      (is (string=
           "http://localhost:8080/v1"
           (cadr-ai:model-base-url (first models))))
      (is (= 65536
             (cadr-ai:model-context-window
              (first models))))
      (is
       (cadr-ai:model-supports-images-p
        (first models))))))

(test llama-provider-includes-sleeping-and-autoload-presets
  (let ((controller
          (cadr-cli::make-llama-provider-controller)))
    (cadr-cli::llama-provider-set-catalog
     controller
     (list
      (cadr-cli::make-llama-model-info :id "asleep" :status :sleeping)
      (cadr-cli::make-llama-model-info
       :id "preset-one" :status :unloaded :source "preset")
      (cadr-cli::make-llama-model-info
       :id "failed-preset" :status :unloaded :source "preset"
       :failed-p t))
     "http://localhost:8080"
     :router-autoload-p t)
    (let ((ids
            (mapcar #'cadr-ai:model-id
                    (cadr-ai:runtime-provider-models
                     (cadr-cli::llama-provider-controller-provider
                      controller)))))
      (is (equal '("asleep" "preset-one") ids)))))

(test llama-provider-restores-provider-scoped-cache-and-resolves-auth
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
                  "Bearer secret"
                  (cdr
                   (assoc "authorization" headers
                          :test #'string-equal))))
             (cond
               ((string=
                 "http://router.test/models" url)
                (llama-json-response
                 (llama-catalog-json
                  (llama-model-json
                   "loaded" "loaded"
                   :context-window 32768)
                  (llama-model-json
                   "unloaded" "unloaded"))))
               ((string=
                 "http://router.test/props?model=loaded&autoload=false"
                 url)
                (llama-json-response
                 (cadr-ai::json-object
                  "chat_template" "plain template")))
               (t
                (error "Unexpected llama request ~A" url)))))
         (credentials
           (cadr-ai:make-memory-credential-store))
         (model-store (make-hash-table))
         (runtime
           (cadr-ai:make-models-runtime
            :credential-store credentials
            :model-store model-store))
         (first
           (cadr-cli::make-llama-provider-controller)))
    (cadr-ai:credential-store-modify
     credentials :llama.cpp
     (lambda (old)
       (declare (ignore old))
       (cadr-ai:make-api-key-credential
        :provider :llama.cpp
        :key "secret"
        :environment
        '(("LLAMA_BASE_URL"
           . "http://router.test")))))
    (cadr-ai:models-runtime-set-provider
     runtime
     (cadr-cli::llama-provider-controller-provider
      first))
    (cadr-ai:models-runtime-refresh runtime)
    (is (= 2 calls))
    (is (equal
         '("loaded")
         (mapcar
          #'cadr-ai:model-id
          (cadr-ai:models-runtime-models
           runtime :llama.cpp))))
    (let ((second
            (cadr-cli::make-llama-provider-controller)))
      (cadr-ai:models-runtime-set-provider
       runtime
       (cadr-cli::llama-provider-controller-provider
        second))
      (cadr-ai:models-runtime-refresh
       runtime :allow-network nil)
      (is (= 2 calls))
      (is (equal
           '("loaded")
           (mapcar
            #'cadr-ai:model-id
            (cadr-ai:models-runtime-models
             runtime :llama.cpp)))))
    (let ((auth
            (cadr-ai:models-runtime-auth
             runtime :llama.cpp)))
      (is (string=
           "secret"
           (cadr-ai:runtime-auth-result-api-key auth)))
      (is (string=
           "http://router.test/v1"
           (cadr-ai:runtime-auth-result-base-url
            auth))))))

(defun llama-info (id status &key source)
  (cadr-cli::make-llama-model-info
   :id id :status status :source source))

(test llama-enable-thinking-template-sets-reasoning-map-and-format
  (let* ((model
           (cadr-cli::llama-model
            (llama-info "qwen" :loaded)
            "http://127.0.0.1:8080"
            "{% if enable_thinking %}"))
         (compat (cadr-ai::model-compat model))
         (provider
           (cadr-ai:make-openai-completions-provider
            :api-key "local"))
         (context
           (cadr-ai:make-context
            :messages
            (list (cadr-ai:make-user-message :content "hi"))))
         (on
           (cadr-ai:request-spec-payload
            (cadr-ai:build-request
             provider model context
             :reasoning :medium :max-tokens 32)))
         (kwargs
           (cadr-ai::json-get on "chat_template_kwargs"))
         (off
           (cadr-ai:request-spec-payload
            (cadr-ai:build-request
             provider model context
             :max-tokens 32))))
    (is (eq t (cadr-ai:model-reasoning-p model)))
    (is (equal
         '((:off . "off")
           (:minimal)
           (:low)
           (:medium . "medium")
           (:high)
           (:xhigh))
         (cadr-ai::model-thinking-level-map model)))
    (is (eq :qwen-chat-template
            (getf compat :thinking-format)))
    (is (member :supports-store compat))
    (is (eq :max-tokens (getf compat :max-tokens-field)))
    (is (eq t (cadr-ai::json-get kwargs "enable_thinking")))
    (is (eq t (cadr-ai::json-get kwargs "preserve_thinking")))
    (is (not (cadr-ai::json-present-p on "reasoning_effort")))
    (is (not (cadr-ai::json-present-p on "enable_thinking")))
    (let ((off-kwargs
            (cadr-ai::json-get off "chat_template_kwargs")))
      (is (cadr-ai::json-present-p
           off-kwargs "enable_thinking"))
      (is (null
           (cadr-ai::json-get off-kwargs "enable_thinking")))
      (is (eq t
              (cadr-ai::json-get
               off-kwargs "preserve_thinking"))))))

(test llama-template-without-enable-thinking-is-not-reasoning
  (dolist (template (list nil "chat template without the flag"))
    (let* ((model
             (cadr-cli::llama-model
              (llama-info "plain" :loaded)
              "http://127.0.0.1:8080"
              template))
           (compat (cadr-ai::model-compat model)))
      (is (null (cadr-ai:model-reasoning-p model)))
      (is (null (cadr-ai::model-thinking-level-map model)))
      (is (not (member :thinking-format compat)))
      (is (member :supports-store compat))
      (is (eq :max-tokens (getf compat :max-tokens-field))))))

(test llama-client-props-returns-autoload-and-chat-template
  (let ((cadr-ai:*http-request-function*
          (lambda (url &key method headers content
                       connect-timeout read-timeout want-stream
                       force-string force-binary)
            (declare
             (ignore method headers content connect-timeout
                     read-timeout want-stream force-string
                     force-binary))
            (cond
              ((string= "http://router.test/props" url)
               (llama-json-response
                (cadr-ai::json-object
                 "models_autoload" t
                 "chat_template" 12)))
              ((string=
                "http://router.test/props?model=owner%2Frepo%3AQ4&autoload=false"
                url)
               (llama-json-response
                (cadr-ai::json-object
                 "models_autoload" nil
                 "chat_template" "{% if enable_thinking %}")))
              (t
               (error "Unexpected llama request ~A" url))))))
    (let ((client
            (cadr-cli::make-llama-client
             :server-url "http://router.test")))
      (let ((router (cadr-cli::llama-client-props client)))
        (is (eq t (getf router :models-autoload)))
        (is (not (member :chat-template router))))
      (let ((props
              (cadr-cli::llama-client-props
               client :model "owner/repo:Q4")))
        (is (null (getf props :models-autoload)))
        (is (member :models-autoload props))
        (is (string=
             "{% if enable_thinking %}"
             (getf props :chat-template)))))))

(test llama-refresh-classifies-loaded-templates-only
  (let* ((urls nil)
         (cadr-ai:*http-request-function*
           (lambda (url &key method headers content
                        connect-timeout read-timeout want-stream
                        force-string force-binary)
             (declare
              (ignore method headers content connect-timeout
                      read-timeout want-stream force-string
                      force-binary))
             (push url urls)
             (cond
               ((string= "http://router.test/models" url)
                (llama-json-response
                 (llama-catalog-json
                  (llama-model-json "think" "loaded")
                  (llama-model-json "plain" "loaded")
                  (llama-model-json "asleep" "sleeping")
                  (llama-model-json
                   "preset" "unloaded" :source "preset"))))
               ((string= "http://router.test/props" url)
                (llama-json-response
                 (cadr-ai::json-object "models_autoload" t)))
               ((string=
                 "http://router.test/props?model=think&autoload=false"
                 url)
                (llama-json-response
                 (cadr-ai::json-object
                  "chat_template"
                  "template enable_thinking here")))
               ((string=
                 "http://router.test/props?model=plain&autoload=false"
                 url)
                (values "{\"error\":\"down\"}" 500
                        '(("content-type"
                           . "application/json"))))
               (t
                (error "Unexpected llama request ~A" url)))))
         (credentials (cadr-ai:make-memory-credential-store))
         (runtime
           (cadr-ai:make-models-runtime
            :credential-store credentials
            :model-store (make-hash-table))))
    (cadr-ai:credential-store-modify
     credentials :llama.cpp
     (lambda (old)
       (declare (ignore old))
       (cadr-ai:make-api-key-credential
        :provider :llama.cpp
        :key "secret"
        :environment
        '(("LLAMA_BASE_URL" . "http://router.test")))))
    (cadr-ai:models-runtime-set-provider
     runtime
     (cadr-cli::llama-provider-controller-provider
      (cadr-cli::make-llama-provider-controller)))
    (cadr-ai:models-runtime-refresh runtime)
    (is (null
         (find-if
          (lambda (url)
            (or (search "model=asleep" url)
                (search "model=preset" url)))
          urls)))
    (let ((models
            (cadr-ai:models-runtime-models
             runtime :llama.cpp)))
      (is (equal
           '("think" "plain" "asleep" "preset")
           (mapcar #'cadr-ai:model-id models)))
      (is (eq t
              (cadr-ai:model-reasoning-p (first models))))
      (is (eq :qwen-chat-template
              (getf (cadr-ai::model-compat (first models))
                    :thinking-format)))
      (is (null (cadr-ai:model-reasoning-p (second models))))
      (is (not
           (member :thinking-format
                   (cadr-ai::model-compat (second models)))))
      (is (null (cadr-ai:model-reasoning-p (third models))))
      (is (null (cadr-ai:model-reasoning-p (fourth models)))))))

(test llama-refresh-stops-between-models-when-aborted
  (let* ((abort nil)
         (urls nil)
         (cadr-ai:*http-request-function*
           (lambda (url &key method headers content
                        connect-timeout read-timeout want-stream
                        force-string force-binary)
             (declare
              (ignore method headers content connect-timeout
                      read-timeout want-stream force-string
                      force-binary))
             (push url urls)
             (cond
               ((string= "http://router.test/models" url)
                (llama-json-response
                 (llama-catalog-json
                  (llama-model-json "first" "loaded")
                  (llama-model-json "second" "loaded"))))
               ((string=
                 "http://router.test/props?model=first&autoload=false"
                 url)
                (setf abort t)
                (llama-json-response
                 (cadr-ai::json-object
                  "chat_template" "enable_thinking")))
               (t
                (error "Unexpected llama request ~A" url)))))
         (credentials (cadr-ai:make-memory-credential-store))
         (runtime
           (cadr-ai:make-models-runtime
            :credential-store credentials
            :model-store (make-hash-table))))
    (cadr-ai:credential-store-modify
     credentials :llama.cpp
     (lambda (old)
       (declare (ignore old))
       (cadr-ai:make-api-key-credential
        :provider :llama.cpp
        :key "secret"
        :environment
        '(("LLAMA_BASE_URL" . "http://router.test")))))
    (cadr-ai:models-runtime-set-provider
     runtime
     (cadr-cli::llama-provider-controller-provider
      (cadr-cli::make-llama-provider-controller)))
    (cadr-ai:models-runtime-refresh
     runtime :abort-p (lambda () abort))
    (is (null
         (cadr-ai:models-runtime-models runtime :llama.cpp)))
    (is (not
         (find-if
          (lambda (url) (search "model=second" url))
          urls)))))

(test hugging-face-client-groups-gguf-quantizations-and-gated-metadata
  (let* ((requests nil)
        (cadr-ai:*http-request-function*
          (lambda (url &key method headers content
                       connect-timeout read-timeout want-stream
                       force-string force-binary)
            (declare
             (ignore method content connect-timeout
                     read-timeout want-stream force-string
                     force-binary))
            (push (list url headers) requests)
            (if (search "/api/models?" url)
                (llama-json-response
                 (vector
                  (cadr-ai::json-object
                   "id" "owner/model-GGUF"
                   "downloads" 1200)))
                (llama-json-response
                 (cadr-ai::json-object
                  "id" "owner/model-GGUF"
                  "gated" "manual"
                  "siblings"
                  (vector
                   (cadr-ai::json-object
                    "rfilename"
                    "model-Q5_K_M.gguf"
                    "size" 6000)
                   (cadr-ai::json-object
                    "rfilename"
                    "model-Q4_K_M-00001-of-00002.gguf"
                    "size" 2000)
                   (cadr-ai::json-object
                    "rfilename"
                    "model-Q4_K_M-00002-of-00002.gguf"
                    "size" 3000)
                   (cadr-ai::json-object
                    "rfilename"
                    "mmproj-F16.gguf"
                    "size" 1000))))))))
    (let ((client
            (cadr-cli::make-hugging-face-client
             :token "hf-secret"
             :base-url "http://hf.test")))
      (is (equal
           '(("owner/model-GGUF" 1200))
           (cadr-cli::hugging-face-search
            client "qwen coder")))
      (let ((details
              (cadr-cli::hugging-face-details
               client "owner/model-GGUF")))
        (is (eq :manual
                (getf details :gated)))
        (is (equal
             '(("Q4_K_M" 5000)
               ("Q5_K_M" 6000))
             (getf details :quantizations)))))
    (is (every
         (lambda (request)
           (string=
            "Bearer hf-secret"
            (cdr
             (assoc
              "authorization"
              (second request)
              :test #'string-equal))))
         requests))))

(test llama-load-and-download-consume-sse-progress-and-refresh-catalog
  (let* ((state :unloaded)
        (progress nil)
        (cadr-ai:*http-request-function*
          (lambda (url &key method headers content
                       connect-timeout read-timeout want-stream
                       force-string force-binary)
            (declare
             (ignore headers content connect-timeout
                     force-string force-binary))
            (cond
              ((and want-stream
                    (search "/models/sse" url))
               (is (null read-timeout))
               (values
                (make-string-input-stream
                 (if (eq state :loading)
                     (format
                      nil
                      "data: {\"model\":\"test-model\",\"event\":\"status_change\",\"data\":{\"status\":\"loading\",\"progress\":{\"stages\":[\"text_model\",\"mmproj_model\"],\"current\":\"text_model\",\"value\":0.5}}}~%~%data: {\"model\":\"test-model\",\"event\":\"status_change\",\"data\":{\"status\":\"loaded\"}}~%~%"
                      )
                     (format
                      nil
                      "data: {\"model\":\"owner/repo:Q4_K_M\",\"event\":\"download_progress\",\"data\":{\"progress\":{\"file\":{\"done\":512,\"total\":1024}}}}~%~%data: {\"model\":\"owner/repo:Q4_K_M\",\"event\":\"download_finished\",\"data\":{}}~%~%")))
                200
                '(("content-type"
                   . "text/event-stream"))))
              ((and (eq method :post)
                    (search "/models/load" url))
               (setf state :loading)
               (llama-json-response
                (cadr-ai::json-object
                 "success" t)))
              ((and (eq method :post)
                    (uiop:string-suffix-p
                     "/models" url))
               (setf state :downloading)
               (llama-json-response
                (cadr-ai::json-object
                 "success" t)))
              ((search "/models" url)
               (let ((effective
                       (case state
                         (:loading :loaded)
                         (:downloading :unloaded)
                         (otherwise state))))
                 (setf state effective)
                 (llama-json-response
                  (llama-catalog-json
                   (llama-model-json
                    (if (eq effective :loaded)
                        "test-model"
                        "owner/repo:Q4_K_M")
                    (string-downcase
                     (symbol-name effective)))))))
              (t
               (error "Unexpected request ~A" url))))))
    (let ((client
            (cadr-cli::make-llama-client
             :server-url "http://router.test")))
      (is (eq
           :loaded
           (cadr-cli::llama-model-info-status
            (cadr-cli::llama-client-load-and-wait
             client "test-model"
             (lambda (entry)
               (push entry progress))))))
      (setf state :missing)
      (let ((models
              (cadr-cli::llama-client-download-and-wait
               client "owner/repo:Q4_K_M"
               (lambda (entry)
                 (push entry progress)))))
        (is (equal
             '("owner/repo:Q4_K_M")
             (mapcar
              #'cadr-cli::llama-model-info-id
              models))))
      (is (find
           "Loading text model"
           progress
           :key (lambda (entry)
                  (getf entry :message))
           :test #'string=))
      (is (find
           0.5d0
           progress
           :key (lambda (entry)
                  (getf entry :ratio))
           :test #'=)))))

(test llama-extension-entry-gated-approval-and-argument-split-match-baseline
  (is (string=
       "Manual approval is required"
       (cadr-cli::llama-gated-approval-text :manual)))
  (is (string=
       "Accept the access terms"
       (cadr-cli::llama-gated-approval-text :auto)))
  (is (string=
       "Accept the access terms"
       (cadr-cli::llama-gated-approval-text nil)))
  (multiple-value-bind (action target)
      (cadr-cli::split-llama-command-arguments "  Load  foo/bar  ")
    (is (string= "load" action))
    (is (string= "foo/bar" target)))
  (multiple-value-bind (action target)
      (cadr-cli::split-llama-command-arguments "login")
    (is (string= "login" action))
    (is (string= "" target)))
  (is (cadr-cli::llama-loaded-model-p
       (cadr-cli::make-llama-model-info :id "m" :status :loaded)))
  (is (cadr-cli::llama-loaded-model-p
       (cadr-cli::make-llama-model-info :id "m" :status :sleeping)))
  (is (not
       (cadr-cli::llama-loaded-model-p
        (cadr-cli::make-llama-model-info :id "m" :status :unloaded))))
  (is (string=
       "Q4_K_M · recommended"
       (cadr-cli::llama-quantization-option-label
        (list :name "Q4_K_M"))))
  (is (string=
       "Q5_K_M · 1.00 GiB"
       (cadr-cli::llama-quantization-option-label
        (list :name "Q5_K_M" :size 1073741824)))))

(test llama-extension-entry-ensure-auth-requires-registry-and-reuses-stored-credential
  (signals cadr-agent:extension-execution-error
    (let ((cadr-cli::*active-native-model-registry* nil)
          (bundle
            (cadr-agent::make-extension-bundle
             :id "llama-entry"
             :path "/tmp/llama-entry/")))
      (cadr-cli::ensure-llama-auth
       (cadr-agent::%make-extension-context
        :host (cadr-agent::make-extension-host :cwd #P"/tmp/" :mode :print)
        :bundle bundle
        :kind :command
        :source-path #P"/tmp/llama-entry/")
       nil)))
  (let* ((credentials (cadr-ai:make-memory-credential-store))
         (runtime
           (cadr-ai:make-models-runtime
            :credential-store credentials
            :model-store (make-hash-table)))
         (registry
           (cadr-cli::%make-model-registry
            :path nil
            :credentials credentials
            :native-runtime runtime))
         (bundle
           (cadr-agent::make-extension-bundle
            :id "llama-entry"
            :path "/tmp/llama-entry/"))
         (context
           (cadr-agent::%make-extension-context
            :host
            (cadr-agent::make-extension-host
             :cwd #P"/tmp/" :mode :print)
            :bundle bundle
            :kind :command
            :source-path #P"/tmp/llama-entry/"))
         (provider
           (cadr-cli::llama-provider-controller-provider
            (cadr-cli::make-llama-provider-controller))))
    (cadr-ai:models-runtime-set-provider runtime provider)
    (cadr-ai:credential-store-modify
     credentials cadr-cli::+llama-provider-id+
     (lambda (old)
       (declare (ignore old))
       (cadr-ai:make-api-key-credential
        :provider cadr-cli::+llama-provider-id+
        :key "local"
        :environment
        '(("LLAMA_BASE_URL" . "http://127.0.0.1:8080")))))
    (let ((cadr-cli::*active-native-model-registry* registry))
      (is (cadr-ai:models-runtime-check-auth
           runtime cadr-cli::+llama-provider-id+))
      (let ((auth (cadr-cli::ensure-llama-auth context nil)))
        (is (typep auth 'cadr-ai:runtime-auth-result))
        (is (string=
             "http://127.0.0.1:8080/v1"
             (cadr-ai:runtime-auth-result-base-url auth)))))))
