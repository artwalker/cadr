(in-package #:cadr-ai/tests)
(in-suite cadr-ai-suite)

(test goal16-bedrock-cache-retention-uses-only-cadr-environment
  (is (eq :long
          (cadr-ai::bedrock-cache-retention
           nil
           '(("CADR_CACHE_RETENTION" . "long")
             ("PI_CACHE_RETENTION" . "ignored")))))
  (is (eq :short
          (cadr-ai::bedrock-cache-retention
           nil
           '(("PI_CACHE_RETENTION" . "long"))))))

(defparameter *baseline-provider-counts*
  '((:amazon-bedrock . 114)
    (:ant-ling . 3)
    (:anthropic . 13)
    (:azure-openai-responses . 38)
    (:baseten . 16)
    (:cerebras . 3)
    (:cloudflare-ai-gateway . 43)
    (:cloudflare-workers-ai . 13)
    (:deepseek . 2)
    (:fireworks . 17)
    (:github-copilot . 30)
    (:google . 24)
    (:google-vertex . 12)
    (:groq . 6)
    (:huggingface . 58)
    (:kimi-coding . 4)
    (:minimax . 3)
    (:minimax-cn . 3)
    (:mistral . 31)
    (:moonshotai . 10)
    (:moonshotai-cn . 10)
    (:nvidia . 30)
    (:openai . 38)
    (:openai-codex . 7)
    (:opencode . 59)
    (:opencode-go . 18)
    (:openrouter . 335)
    (:qwen-token-plan . 16)
    (:qwen-token-plan-cn . 16)
    (:qwen-token-plan-individual . 7)
    (:together . 18)
    (:vercel-ai-gateway . 197)
    (:xai . 3)
    (:xiaomi . 6)
    (:xiaomi-token-plan-ams . 3)
    (:xiaomi-token-plan-cn . 3)
    (:xiaomi-token-plan-sgp . 3)
    (:zai . 4)
    (:zai-coding-cn . 4)))

(test wave3-provider-registry-is-baseline-exact
  (is
   (equal
    '(:amazon-bedrock :ant-ling :anthropic
      :azure-openai-responses :baseten :cerebras
      :cloudflare-ai-gateway :cloudflare-workers-ai :deepseek
      :fireworks :github-copilot :google :google-vertex :groq
      :huggingface :kimi-coding :minimax :minimax-cn :mistral
      :moonshotai :moonshotai-cn :nvidia :openai :openai-codex
      :opencode :opencode-go :openrouter :qwen-token-plan
      :qwen-token-plan-cn :qwen-token-plan-individual :radius
      :together :vercel-ai-gateway
      :xai :xiaomi :xiaomi-token-plan-ams :xiaomi-token-plan-cn
      :xiaomi-token-plan-sgp :zai :zai-coding-cn)
    (mapcar #'cadr-ai:provider-definition-id
            (cadr-ai:list-provider-definitions))))
  (signals cadr-ai:configuration-error
    (cadr-ai:find-provider-definition :ollama)))

(test wave3-static-catalog-is-exact-package-snapshot
  (is (= 1220 (length (cadr-ai:list-model-metadata))))
  (dolist (entry *baseline-provider-counts*)
    (is (= (cdr entry)
           (length (cadr-ai:list-model-metadata (car entry))))
        "~A model count differs" (car entry)))
  (is (null (cadr-ai:list-model-metadata :radius)))
  (let ((opus
          (cadr-ai:find-model-metadata
           :amazon-bedrock "us.anthropic.claude-opus-4-8"))
        (grammar
          (cadr-ai:find-model-metadata
           :openai "gpt-5.5")))
    (is (eq :bedrock-converse-stream
            (cadr-ai:model-metadata-api opus)))
    (is (eq t
            (getf (cadr-ai:model-metadata-compat grammar)
                  :supports-openai-grammar-tools)))))

(defmacro define-wave3-route-test
    (name provider model-id api class)
  `(test ,name
     (multiple-value-bind (adapter model)
         (cadr-ai:instantiate-provider
          ,provider :model-id ,model-id
          :allow-missing-auth-p t)
       (is (typep adapter ',class))
       (is (eq ,api (cadr-ai:model-api model)))
       (is (eq ,provider (cadr-ai:model-provider model))))))

(define-wave3-route-test cloudflare-routes-anthropic-models
  :cloudflare-ai-gateway "claude-3-5-haiku"
  :anthropic-messages cadr-ai:anthropic-provider)
(define-wave3-route-test cloudflare-routes-completions-models
  :cloudflare-ai-gateway "workers-ai/@cf/moonshotai/kimi-k2.5"
  :openai-completions cadr-ai:openai-completions-provider)
(define-wave3-route-test cloudflare-routes-responses-models
  :cloudflare-ai-gateway "gpt-4"
  :openai-responses cadr-ai:openai-provider)
(define-wave3-route-test opencode-routes-google-models
  :opencode "gemini-3-flash"
  :google-generative-ai cadr-ai:google-provider)
(define-wave3-route-test azure-uses-independent-adapter
  :azure-openai-responses "gpt-5.5"
  :azure-openai-responses cadr-ai:azure-openai-provider)
(define-wave3-route-test bedrock-uses-independent-adapter
  :amazon-bedrock "us.anthropic.claude-opus-4-8"
  :bedrock-converse-stream cadr-ai:bedrock-provider)
(define-wave3-route-test vertex-uses-independent-adapter
  :google-vertex "gemini-3-flash-preview"
  :google-vertex cadr-ai:vertex-provider)
(define-wave3-route-test mistral-uses-independent-adapter
  :mistral "mistral-large-latest"
  :mistral-conversations cadr-ai:mistral-provider)
(define-wave3-route-test codex-uses-independent-adapter
  :openai-codex "gpt-5.3-codex-spark"
  :openai-codex-responses cadr-ai:openai-codex-provider)
(define-wave3-route-test radius-uses-independent-adapter
  :radius "fixture-model"
  :pi-messages cadr-ai:pi-messages-provider)

(test azure-base-url-and-deployment-resolution-match-baseline
  (is
   (string=
    "https://example.openai.azure.com/openai/v1"
    (cadr-ai:normalize-azure-openai-base-url
     "https://example.openai.azure.com/openai/v1/responses/")))
  (is
   (string=
    "https://proxy.example/v1/responses"
    (cadr-ai:normalize-azure-openai-base-url
     "https://proxy.example/v1/responses/")))
  (signals cadr-ai:configuration-error
    (cadr-ai:normalize-azure-openai-base-url "not a URL"))
  (is
   (string=
    "deployment-b"
    (cadr-ai:resolve-azure-deployment-name
     "model-b" nil "model-a=deployment-a, model-b=deployment-b")))
  (is
   (string=
    "explicit"
    (cadr-ai:resolve-azure-deployment-name
     "model-b" "explicit" "model-b=ignored"))))

(defun hex-octets (hex)
  (let ((result
          (make-array (/ (length hex) 2)
                      :element-type '(unsigned-byte 8))))
    (loop for index below (length result)
          do (setf (aref result index)
                   (parse-integer hex
                                  :start (* index 2)
                                  :end (+ (* index 2) 2)
                                  :radix 16)))
    result))

(test pure-lisp-hmac-sha256-matches-rfc-4231
  (is
   (string=
    "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"
    (cadr-ai:octets-hex
     (cadr-ai:hmac-sha256
      (make-array 20
                  :element-type '(unsigned-byte 8)
                  :initial-element #x0b)
      (babel:string-to-octets "Hi There" :encoding :utf-8))))))

(test sigv4-canonical-signature-is-deterministic
  (multiple-value-bind (authorization headers)
      (cadr-ai:aws-sigv4-authorization
       :method "GET"
       :url "https://iam.amazonaws.com/?Action=ListUsers&Version=2010-05-08"
       :headers '(("content-type" . "application/x-www-form-urlencoded; charset=utf-8"))
       :payload ""
       :access-key-id "AKIDEXAMPLE"
       :secret-access-key
       "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY"
       :region "us-east-1"
       :service "iam"
       :timestamp "20150830T123600Z")
    (is (search "Credential=AKIDEXAMPLE/20150830/us-east-1/iam/aws4_request"
                authorization))
    (is (search "SignedHeaders=content-type;host;x-amz-date"
                authorization))
    (is (string=
         "20150830T123600Z"
         (cdr (assoc "x-amz-date" headers :test #'string-equal))))
    (is
     (string=
      "5d672d79c15b13162d9279b0855cfba6789a8edb4c82c400e06b5924a6f2b5d7"
      (subseq authorization
              (- (length authorization) 64))))))

(test bedrock-credential-and-region-priority
  (is
   (equal
    '(:source :profile :profile "scoped")
    (cadr-ai:resolve-bedrock-credentials
     '(("AWS_PROFILE" . "ambient")
       ("AWS_ACCESS_KEY_ID" . "AKIA")
       ("AWS_SECRET_ACCESS_KEY" . "secret"))
     :profile "scoped")))
  (is
   (equal
    '(:source :access-keys :access-key-id "AKIA"
      :secret-access-key "secret" :session-token nil)
    (cadr-ai:resolve-bedrock-credentials
     '(("AWS_ACCESS_KEY_ID" . "AKIA")
       ("AWS_SECRET_ACCESS_KEY" . "secret")))))
  (is
   (string=
    "eu-west-1"
    (cadr-ai:resolve-bedrock-region
     "arn:aws:bedrock:eu-west-1:123:model/foo"
     nil nil)))
  (is
   (string=
    "us-west-2"
    (cadr-ai:resolve-bedrock-region
     "model" "us-west-2" "us-east-1"))))

(test bedrock-profile-files-and-request-semantics-match-baseline
  (is
   (equal
    '(:source :access-keys :profile "work"
      :access-key-id "AKIAWORK"
      :secret-access-key "work-secret"
      :session-token "session")
    (cadr-ai:load-bedrock-profile-credentials
     "work"
     :credentials-text
     "[default]
aws_access_key_id=ignored
aws_secret_access_key=ignored
[work]
aws_access_key_id = AKIAWORK
aws_secret_access_key = work-secret
aws_session_token = session")))
  (is
   (string=
    "eu-central-1"
    (cadr-ai:resolve-bedrock-profile-region
     "work"
     :config-text
     "[profile work]
region = eu-central-1")))
  (multiple-value-bind (provider model)
      (cadr-ai:instantiate-provider
       :amazon-bedrock
       :model-id "us.anthropic.claude-opus-4-8"
       :api-key "bearer"
       :options
       '(:environment
         (("AWS_REGION" . "eu-central-1"))
         :headers
         (("x-caller" . "yes")
          ("Authorization" . "forbidden")
          ("X-Amz-Date" . "forbidden"))))
    (let* ((request
             (cadr-ai:build-request
              provider model
              (cadr-ai:make-context
               :system-prompt "system"
               :messages
               (list
                (cadr-ai:make-user-message
                 :content "hello")))
              :stream-p t
              :reasoning :xhigh
              :cache-retention :long))
           (payload (cadr-ai:request-spec-payload request))
           (fields
             (cadr-ai::json-get
              payload "additionalModelRequestFields"))
           (thinking (cadr-ai::json-get fields "thinking"))
           (output-config
             (cadr-ai::json-get fields "output_config")))
      (is
       (string=
        "https://bedrock-runtime.eu-central-1.amazonaws.com/model/us.anthropic.claude-opus-4-8/converse-stream"
        (cadr-ai:request-spec-url request)))
      (is (string= "adaptive"
                   (cadr-ai::json-get thinking "type")))
      (is (string= "xhigh"
                   (cadr-ai::json-get output-config "effort")))
      (is (= 2 (length (cadr-ai::json-get payload "system"))))
      (is
       (string=
        "yes"
        (cdr
         (assoc
          "x-caller"
          (cadr-ai:request-spec-headers request)
          :test #'string-equal))))
      (is
       (string=
        "Bearer bearer"
        (cdr
         (assoc
          "authorization"
          (cadr-ai:request-spec-headers request)
          :test #'string-equal))))
      (is
       (null
        (assoc
         "x-amz-date"
         (cadr-ai:request-spec-headers request)
         :test #'string-equal))))))

(test bedrock-sanitize-keeps-string-document-members
  (let ((sanitized
          (cadr-ai::sanitize-bedrock-document
           (cadr-ai::json-object
            "path" "src/example.ts"
            "" "drop-empty-key"
            "nested"
            (cadr-ai::json-array "keep")))))
    (is (string= "src/example.ts"
                 (cadr-ai::json-get sanitized "path")))
    (is (not (cadr-ai::json-present-p sanitized "")))
    (is (equalp
         (cadr-ai::json-array "keep")
         (cadr-ai::json-get sanitized "nested")))))

(test bedrock-conversion-groups-results-and-gates-strict-tools
  (multiple-value-bind (provider model)
      (cadr-ai:instantiate-provider
       :amazon-bedrock
       :model-id
       "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
       :api-key "bearer")
    (let* ((tool
             (cadr-ai:make-tool
              :name "lookup"
              :description "Lookup"
              :parameters
              (cadr-ai::json-object "type" "object")
              :constrained-sampling
              '(:type :json-schema :strict :require)))
           (context
             (cadr-ai:make-context
              :messages
              (list
               (cadr-ai:make-user-message :content " ")
               (cadr-ai:make-assistant-message
                :api :bedrock-converse-stream
                :provider :amazon-bedrock
                :model (cadr-ai:model-id model)
                :stop-reason :tool-use
                :content
                (list
                 (cadr-ai:make-tool-call
                  :id "one" :name "lookup"
                  :arguments (cadr-ai::json-object))
                 (cadr-ai:make-tool-call
                  :id "two" :name "lookup"
                  :arguments (cadr-ai::json-object))))
               (cadr-ai:make-tool-result-message
                :tool-call-id "one" :tool-name "lookup"
                :content nil)
               (cadr-ai:make-tool-result-message
                :tool-call-id "two" :tool-name "lookup"
                :content
                (list
                 (cadr-ai:make-text-content
                  :text "second"))))
              :tools (list tool)))
           (request
             (cadr-ai:build-request
              provider model context :stream-p t))
           (payload
             (cadr-ai:request-spec-payload request))
           (messages
             (cadr-ai::json-get payload "messages"))
           (tools
             (cadr-ai::json-get
              (cadr-ai::json-get payload "toolConfig")
              "tools")))
      (is
       (string=
        "<empty>"
        (cadr-ai::json-get
         (aref
          (cadr-ai::json-get (aref messages 0) "content")
          0)
         "text")))
      (is (= 3 (length messages)))
      (is
       (= 3
          (length
           (cadr-ai::json-get
            (aref messages 2) "content"))))
      (is
       (cadr-ai::json-present-p
        (aref
         (cadr-ai::json-get
          (aref messages 2) "content")
         2)
        "cachePoint"))
      (is
       (eq
        t
        (cadr-ai::json-get
         (cadr-ai::json-get (aref tools 0) "toolSpec")
         "strict"))))))

(test bedrock-unknown-stop-reason-retains-provider-detail
  (multiple-value-bind (provider model)
      (cadr-ai:instantiate-provider
       :amazon-bedrock
       :model-id "amazon.nova-lite-v1:0"
       :api-key "bearer")
    (let ((message
            (cadr-ai:parse-complete-response
             provider model
             (cadr-ai::parse-json
              "{\"output\":{\"message\":{\"content\":[]}},\"stopReason\":\"guardrail_intervened\"}"))))
      (is (eq :error
              (cadr-ai:assistant-message-stop-reason message)))
      (is
       (string=
        "guardrail_intervened"
        (cadr-ai:assistant-message-raw-stop-reason message)))
      (is
       (string=
        "Provider stopped with: guardrail_intervened"
        (cadr-ai:assistant-message-error-message message))))))

(test bedrock-failure-records-bounded-structured-metadata
  (multiple-value-bind (provider model)
      (cadr-ai:instantiate-provider
       :amazon-bedrock
       :model-id "amazon.nova-lite-v1:0"
       :api-key "bearer")
    (let ((*http-request-function*
            (lambda (url &rest arguments)
              (declare (ignore url arguments))
              (values
               (make-string-input-stream
                "{\"message\":\"bad model\",\"__type\":\"ValidationException\"}")
               400
               '(("x-amzn-requestid"
                  . "11111111-2222-3333-4444-555555555555"))))))
      (let* ((message
               (cadr-ai:stream-chat
                provider model
                (cadr-ai:make-context
                 :messages
                 (list
                  (cadr-ai:make-user-message
                   :content "hello")))
                (lambda (event)
                  (declare (ignore event)))))
             (diagnostic
               (first
                (cadr-ai:assistant-message-diagnostics
                 message)))
             (details
               (cadr-ai:assistant-message-diagnostic-details
                diagnostic)))
        (is (eq :error
                (cadr-ai:assistant-message-stop-reason
                 message)))
        (is (eq :bedrock-response-failure
                (cadr-ai:assistant-message-diagnostic-type
                 diagnostic)))
        (is (= 400 (getf details :status)))
        (is (string=
             "ValidationException"
             (getf details :error-code)))
        (is (string=
             "11111111-2222-3333-4444-555555555555"
             (getf details :request-id)))))
    (let ((*http-request-function*
            (lambda (url &rest arguments)
              (declare (ignore url arguments))
              (error "socket hang up"))))
      (let ((message
              (cadr-ai:stream-chat
               provider model
               (cadr-ai:make-context)
               (lambda (event)
                 (declare (ignore event))))))
        (is (null
             (cadr-ai:assistant-message-diagnostics
              message)))))))

(test bedrock-abort-does-not-append-failure-diagnostic
  (multiple-value-bind (provider model)
      (cadr-ai:instantiate-provider
       :amazon-bedrock
       :model-id "amazon.nova-lite-v1:0"
       :api-key "bearer")
    (let ((message
            (cadr-ai:stream-chat
             provider model
             (cadr-ai:make-context)
             (lambda (event)
               (declare (ignore event)))
             :abort-p (constantly t))))
      (is (eq :aborted
              (cadr-ai:assistant-message-stop-reason
               message)))
      (is (null
           (cadr-ai:assistant-message-diagnostics
            message))))))

(test gpt-5-6-authoritative-pricing-and-opencode-go-name
  (dolist
      (provider
       '(:openai :openai-codex :cloudflare-ai-gateway))
    (let ((luna
            (cadr-ai:find-model-metadata
             provider "gpt-5.6-luna"))
          (terra
            (cadr-ai:find-model-metadata
             provider "gpt-5.6-terra")))
      (is (= 0.2d0
             (cadr-ai:model-metadata-input-price luna)))
      (is (= 1.2d0
             (cadr-ai:model-metadata-output-price luna)))
      (is (= 0.02d0
             (cadr-ai:model-metadata-cache-read-price luna)))
      (is (= 0.25d0
             (cadr-ai:model-metadata-cache-write-price luna)))
      (is (= 2d0
             (cadr-ai:model-metadata-input-price terra)))
      (is (= 12d0
             (cadr-ai:model-metadata-output-price terra)))
      (let ((tier
              (first
               (cadr-ai:model-metadata-cost-tiers luna))))
        (is (= 0.4d0
               (cadr-ai:model-cost-tier-input-price tier)))
        (is (= 1.8d0
               (cadr-ai:model-cost-tier-output-price tier))))))
  (is (string=
       "OpenCode Go"
       (cadr-ai:provider-definition-name
        (cadr-ai:find-provider-definition
         :opencode-go)))))

(test vertex-auth-resolution-distinguishes-api-key-and-adc
  (is
   (equal
    '(:type :api-key :api-key "real-key")
    (cadr-ai:resolve-vertex-auth
     '(("GOOGLE_CLOUD_API_KEY" . "real-key"))
     :file-exists-p (constantly nil))))
  (is
   (equal
    '(:type :adc :credentials-file "/tmp/adc.json"
      :project "project" :location "global")
    (cadr-ai:resolve-vertex-auth
     '(("GOOGLE_CLOUD_API_KEY" . "<authenticated>")
       ("GOOGLE_APPLICATION_CREDENTIALS" . "/tmp/adc.json")
       ("GOOGLE_CLOUD_PROJECT" . "project")
       ("GOOGLE_CLOUD_LOCATION" . "global"))
     :file-exists-p
     (lambda (path)
       (string= path "/tmp/adc.json")))))
  (signals cadr-ai:configuration-error
    (cadr-ai:resolve-vertex-auth
     '(("GOOGLE_APPLICATION_CREDENTIALS" . "/tmp/missing.json")
       ("GOOGLE_CLOUD_PROJECT" . "project")
       ("GOOGLE_CLOUD_LOCATION" . "global"))
     :file-exists-p (constantly nil))))

(test vertex-service-account-uses-openssl-rs256-and-token-exchange
  (let* ((private-key
           (read-fixture
            "test/fixtures/auth/service-account-private-key.pem"))
         (credential
           (cadr-ai::json-object
            "type" "service_account"
            "project_id" "fixture-project"
            "client_email" "fixture@example.invalid"
            "private_key" private-key
            "token_uri" "https://oauth2.googleapis.com/token"))
         (request
           (cadr-ai:make-vertex-token-request
            credential :issued-at 1700000000))
         (body (cadr-ai:request-spec-raw-body request)))
    (is
     (string=
      "https://oauth2.googleapis.com/token"
      (cadr-ai:request-spec-url request)))
    (is (search
         "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer"
         body))
    (is (search "assertion=" body))
    (is (null (search "BEGIN+PRIVATE+KEY" body)))
    (let* ((calls 0)
          (cadr-ai:*http-request-function*
            (lambda (url &key method headers content
                           connect-timeout read-timeout
                           want-stream force-string force-binary)
              (declare
               (ignore method headers connect-timeout read-timeout
                       want-stream force-string force-binary))
              (incf calls)
              (is (string=
                   "https://oauth2.googleapis.com/token"
                   url))
              (is (search "assertion=" content))
              (values
               "{\"access_token\":\"vertex-token\",\"expires_in\":3600,\"token_type\":\"Bearer\"}"
               200 nil))))
      (is
       (string=
        "vertex-token"
        (cadr-ai:exchange-vertex-access-token
         credential :issued-at 1700000000)))
      (is (= 1 calls)))))

(test vertex-build-request-resolves-service-account-adc
  (let* ((private-key
           (read-fixture
            "test/fixtures/auth/service-account-private-key.pem"))
         (credential
           (cadr-ai::json-object
            "type" "service_account"
            "project_id" "fixture-project"
            "client_email" "fixture@example.invalid"
            "private_key" private-key
            "token_uri" "https://oauth2.googleapis.com/token"))
         (cadr-ai:*http-request-function*
           (lambda (url &key method headers content
                          connect-timeout read-timeout
                          want-stream force-string force-binary)
             (declare
              (ignore url method headers content connect-timeout
                      read-timeout want-stream force-string
                      force-binary))
             (values
              "{\"access_token\":\"vertex-token\"}"
              200 nil))))
    (multiple-value-bind (provider model)
        (cadr-ai:instantiate-provider
         :google-vertex
         :model-id "gemini-3-flash-preview"
         :allow-missing-auth-p t
         :options
         (list
          :credential credential
          :location "us-central1"
          :issued-at 1700000000))
      (let ((request
              (cadr-ai:build-request
               provider model
               (cadr-ai:make-context
                :messages
                (list
                 (cadr-ai:make-user-message
                  :content "hello")))
               :stream-p t)))
        (is
         (search
          "https://us-central1-aiplatform.googleapis.com/v1/projects/fixture-project/locations/us-central1/"
          (cadr-ai:request-spec-url request)))
        (is
         (string=
          "Bearer vertex-token"
          (cdr
           (assoc
            "authorization"
            (cadr-ai:request-spec-headers request)
            :test #'string-equal))))))))

(test device-code-polling-handles-pending-slow-down-and-expiry
  (let ((results
          (list '(:status :pending)
                '(:status :slow-down :interval 7)
                '(:status :complete :value "token")))
        (waits nil))
    (is
     (string=
      "token"
      (cadr-ai:poll-device-authorization
       (lambda () (pop results))
       :interval 2
       :expires-in 30
       :sleep-function (lambda (seconds) (push seconds waits))
       :time-function
       (let ((time 0))
         (lambda () (prog1 time (incf time)))))))
    (is (equal '(7 2) waits)))
  (signals cadr-ai:authentication-error
    (cadr-ai:poll-device-authorization
     (lambda () '(:status :expired))
     :interval 1
     :expires-in 30
     :sleep-function (constantly nil))))

(test cloudflare-placeholders-are-materialized-before-dispatch
  (is
   (string=
    "https://gateway.ai.cloudflare.com/v1/account/gateway/openai"
    (cadr-ai:materialize-cloudflare-url
     "https://gateway.ai.cloudflare.com/v1/{accountId}/{gatewayId}/openai"
     "account" "gateway")))
  (signals cadr-ai:configuration-error
    (cadr-ai:materialize-cloudflare-url
     "https://gateway.ai.cloudflare.com/v1/{accountId}/{gatewayId}/openai"
     nil "gateway")))

(test radius-config-refresh-is-atomic-and-validates-models
  (let* ((old
           (list
            (cadr-ai:make-model-metadata
             :provider :radius :id "old" :api :pi-messages)))
         (new
           (cadr-ai:radius-models-from-config
            :radius
            (cadr-ai::parse-json
             "{\"baseUrl\":\"https://radius.example\",\"models\":[{\"id\":\"new\",\"name\":\"New\",\"reasoning\":false,\"input\":[\"text\"],\"cost\":{\"input\":1,\"output\":2,\"cacheRead\":0,\"cacheWrite\":0},\"contextWindow\":32000,\"maxTokens\":4096}]}"))))
    (is (= 1 (length new)))
    (is (string= "new" (cadr-ai:model-metadata-id (first new))))
    (signals cadr-ai:configuration-error
      (cadr-ai:radius-models-from-config
       :radius
       (cadr-ai::parse-json "{\"models\":[{\"name\":\"missing id\"}]}")))
    (is (string= "old" (cadr-ai:model-metadata-id (first old))))))

(test provider-device-oauth-parsers-enforce-trusted-urls-and-token-shapes
  (let ((xai
          (cadr-ai:parse-xai-device-authorization
           (cadr-ai::json-object
            "device_code" "device"
            "user_code" "user"
            "verification_uri" "https://x.ai/activate"
            "verification_uri_complete"
            "https://x.ai/activate?code=user"
            "interval" 0
            "expires_in" 600))))
    (is (null (getf xai :interval)))
    (is (string=
         "https://x.ai/activate?code=user"
         (getf xai :verification-uri-complete))))
  (signals cadr-ai:authentication-error
    (cadr-ai:parse-xai-device-authorization
     (cadr-ai::json-object
      "device_code" "device"
      "user_code" "user"
      "verification_uri" "file:///tmp/evil"
      "expires_in" 600)))
  (let ((kimi
          (cadr-ai:parse-kimi-device-authorization
           (cadr-ai::json-object
            "device_code" "device"
            "user_code" "user"
            "verification_uri" "https://auth.kimi.com/device"
            "verification_uri_complete"
            "https://auth.kimi.com/device?code=user"))))
    (is (= 5 (getf kimi :interval)))
    (is (= 900 (getf kimi :expires-in))))
  (let ((github
          (cadr-ai:parse-github-device-authorization
           (cadr-ai::json-object
            "device_code" "device"
            "user_code" "user"
            "verification_uri" "https://github.com/login/device"
            "expires_in" 900))))
    (is (string= "device" (getf github :device-code))))
  (let ((credential
          (cadr-ai:oauth-token-credential
           :xai
           (cadr-ai::json-object
            "access_token" "new"
            "expires_in" 3600)
           :previous-refresh-token "old"
           :expiry-skew-milliseconds 300000)))
    (is (string=
         "old"
         (cadr-ai:oauth-credential-refresh credential)))
    (is (string=
         "new"
         (cadr-ai:oauth-credential-access credential)))))

(test github-copilot-oauth-token-routing-and-model-filter-match-baseline
  (is (string=
       "https://api.individual.githubcopilot.com"
       (cadr-ai:github-copilot-base-url
        "tid=x;proxy-ep=proxy.individual.githubcopilot.com;exp=1")))
  (is (string=
       "https://copilot-api.github.example"
       (cadr-ai:github-copilot-base-url
        nil "github.example")))
  (let ((response
          (cadr-ai::json-object
           "data"
           (vector
            (cadr-ai::json-object
             "id" "enabled"
             "model_picker_enabled" t
             "policy" (cadr-ai::json-object "state" "enabled")
             "capabilities"
             (cadr-ai::json-object
              "supports"
              (cadr-ai::json-object "tool_calls" t)))
            (cadr-ai::json-object
             "id" "disabled"
             "model_picker_enabled" t
             "policy"
             (cadr-ai::json-object "state" "disabled"))))))
    (is (equal
         '("enabled")
         (cadr-ai:selectable-github-copilot-model-ids
          response)))))

(test radius-oauth-authorization-url-is-pkce-bound
  (let ((url
          (cadr-ai:radius-authorization-url
           "https://radius.example/authorize"
           "challenge" "state")))
    (is (search "client_id=pi-gateway" url))
    (is (search "code_challenge=challenge" url))
    (is (search "state=state" url))
    (is (search
         "redirect_uri=http%3A%2F%2F127.0.0.1%3A1456%2Foauth%2Fcallback"
         url))))
