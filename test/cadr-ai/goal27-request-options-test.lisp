(in-package #:cadr-ai/tests)

(in-suite cadr-ai-suite)

(defparameter +goal13-none-high-levels+
  '((:off . "none")
    (:minimal . nil)
    (:low . nil)
    (:medium . nil)
    (:high . "high")
    (:xhigh . nil)
    (:max . nil)))

(defparameter +goal13-glm-5-2-levels+
  '((:off . "none")
    (:minimal . nil)
    (:low . nil)
    (:medium . nil)
    (:high . "high")
    (:xhigh . nil)
    (:max . "max")))

(defparameter +goal13-glm-5-3-levels+
  '((:off . nil)
    (:minimal . nil)
    (:low . "low")
    (:medium . nil)
    (:high . "high")
    (:xhigh . nil)
    (:max . "max")))

(defun goal13-context ()
  (make-context
   :messages
   (list (make-user-message :content "Hello" :timestamp 1))))

(defun goal13-close (left right)
  (< (abs (- (coerce left 'double-float)
             (coerce right 'double-float)))
     1d-9))

(defun goal13-responses-model
    (&key (id "custom-model")
          (api :openai-responses)
          (provider :openai)
          reasoning-p
          map
          sampling)
  (make-model
   :id id
   :name id
   :provider provider
   :api api
   :base-url (if (eq api :openai-codex-responses)
                 "https://chatgpt.com/backend-api"
                 "https://api.openai.com/v1")
   :max-tokens 16384
   :context-window 128000
   :reasoning-p reasoning-p
   :thinking-level-map map
   :sampling-params-by-thinking-level sampling))

(defun goal13-responses-payload (model &rest keys)
  (request-spec-payload
   (apply #'build-request
          (make-openai-provider :api-key "sk-test-key")
          model
          (goal13-context)
          :stream-p t
          keys)))

(defun goal13-codex-payload (model &rest keys)
  (request-spec-payload
   (apply #'build-request
          (make-openai-codex-provider
           :oauth-access-token "oauth-test"
           :oauth-account-id "acct-test")
          model
          (goal13-context)
          :stream-p t
          keys)))

(defun goal13-mistral-model (id reasoning-p &optional map)
  (make-model
   :id id
   :name id
   :provider :mistral
   :api :mistral-conversations
   :base-url "http://127.0.0.1:9"
   :max-tokens 16384
   :context-window 128000
   :reasoning-p reasoning-p
   :thinking-level-map map))

(defun goal13-mistral-payload (model &rest keys)
  (request-spec-payload
   (apply #'build-request
          (make-mistral-provider :api-key "fake-key")
          model
          (goal13-context)
          :stream-p t
          keys)))

(defun goal13-sampling-levels ()
  (list (cons :off (cadr-ai::json-object "temperature" 0.7d0))
        (cons :medium (cadr-ai::json-object "temperature" 0.8d0))))

(test responses-reasoning-summary-is-caller-controlled
  ;; pi@4a080252f openai-responses.ts buildParams and
  ;; packages/ai/test/sampling-options.test.ts.
  (let* ((model
           (goal13-responses-model
            :reasoning-p t
            :sampling (goal13-sampling-levels)))
         (summary-only (goal13-responses-payload
                        model :reasoning-summary "auto"))
         (detailed
           (goal13-responses-payload
            model :reasoning :high :reasoning-summary "detailed"))
         (null-summary
           (goal13-responses-payload
            model :reasoning-summary nil))
         (azure
           (request-spec-payload
            (build-request
             (make-azure-openai-provider
              :api-key "test"
              :options '(:azure-base-url
                         "https://example.openai.azure.com/openai/v1"))
             (goal13-responses-model
              :api :azure-openai-responses
              :provider :azure
              :reasoning-p t
              :sampling (goal13-sampling-levels))
             (goal13-context)
             :stream-p t
             :service-tier "flex"
             :reasoning-summary "concise"))))
    (is (string= "medium"
                 (cadr-ai::json-get
                  (cadr-ai::json-get summary-only "reasoning")
                  "effort")))
    (is (string= "auto"
                 (cadr-ai::json-get
                  (cadr-ai::json-get summary-only "reasoning")
                  "summary")))
    (is (goal13-close
         0.8d0
         (cadr-ai::json-get summary-only "temperature")))
    (is (string= "high"
                 (cadr-ai::json-get
                  (cadr-ai::json-get detailed "reasoning")
                  "effort")))
    (is (string= "detailed"
                 (cadr-ai::json-get
                  (cadr-ai::json-get detailed "reasoning")
                  "summary")))
    (is (string= "none"
                 (cadr-ai::json-get
                  (cadr-ai::json-get null-summary "reasoning")
                  "effort")))
    (is (not (cadr-ai::json-present-p
              (cadr-ai::json-get null-summary "reasoning")
              "summary")))
    (is (string= "medium"
                 (cadr-ai::json-get
                  (cadr-ai::json-get azure "reasoning")
                  "effort")))
    (is (string= "concise"
                 (cadr-ai::json-get
                  (cadr-ai::json-get azure "reasoning")
                  "summary")))
    (is (goal13-close
         0.8d0
         (cadr-ai::json-get azure "temperature")))
    ;; AzureOpenAIResponsesOptions has no serviceTier.
    (is (not (cadr-ai::json-present-p azure "service_tier")))))

(test responses-service-tier-is-sent-only-when-supplied
  ;; pi@4a080252f openai-responses.ts. Undefined omits the field.
  ;; null is sent as JSON null.
  (let ((model (goal13-responses-model :id "gpt-5.4" :reasoning-p t)))
    (is (not (cadr-ai::json-present-p
              (goal13-responses-payload model)
              "service_tier")))
    (is (string= "flex"
                 (cadr-ai::json-get
                  (goal13-responses-payload model :service-tier "flex")
                  "service_tier")))
    (is (cadr-ai::json-null-p
         (cadr-ai::json-get
          (goal13-responses-payload model :service-tier nil)
          "service_tier")))))

(test codex-verbosity-summary-and-service-tier
  ;; pi@4a080252f openai-codex-responses.ts buildRequestBody.
  (let ((model
          (goal13-responses-model
           :id "gpt-5.1-codex"
           :provider :openai-codex
           :api :openai-codex-responses
           :reasoning-p t)))
    (is (string= "low"
                 (cadr-ai::json-get
                  (cadr-ai::json-get (goal13-codex-payload model) "text")
                  "verbosity")))
    (is (string= "medium"
                 (cadr-ai::json-get
                  (cadr-ai::json-get
                   (goal13-codex-payload model :text-verbosity "medium")
                   "text")
                  "verbosity")))
    (is (string= "low"
                 (cadr-ai::json-get
                  (cadr-ai::json-get
                   (goal13-codex-payload model :text-verbosity "")
                   "text")
                  "verbosity")))
    (is (string= "priority"
                 (cadr-ai::json-get
                  (goal13-codex-payload model :service-tier "priority")
                  "service_tier")))
    (is (not (cadr-ai::json-present-p
              (goal13-codex-payload model)
              "service_tier")))
    (let ((with-effort
            (goal13-codex-payload
             model :reasoning :low :reasoning-summary "off")))
      (is (string= "low"
                   (cadr-ai::json-get
                    (cadr-ai::json-get with-effort "reasoning")
                    "effort")))
      (is (string= "off"
                   (cadr-ai::json-get
                    (cadr-ai::json-get with-effort "reasoning")
                    "summary"))))
    (let ((null-summary
            (goal13-codex-payload
             model :reasoning :low :reasoning-summary nil)))
      (is (string= "auto"
                   (cadr-ai::json-get
                    (cadr-ai::json-get null-summary "reasoning")
                    "summary"))))
    (let ((empty-summary
            (goal13-codex-payload
             model :reasoning :low :reasoning-summary "")))
      (is (string= ""
                   (cadr-ai::json-get
                    (cadr-ai::json-get empty-summary "reasoning")
                    "summary"))))
    (let ((summary-only
            (goal13-codex-payload
             model :reasoning-summary "detailed")))
      (is (string= "none"
                   (cadr-ai::json-get
                    (cadr-ai::json-get summary-only "reasoning")
                    "effort")))
      (is (not (cadr-ai::json-present-p
                (cadr-ai::json-get summary-only "reasoning")
                "summary"))))))

(test mistral-prompt-mode-follows-the-thinking-level-map
  ;; pi@4a080252f packages/ai/test/mistral-reasoning-mode.test.ts.
  (let ((magistral
          (goal13-mistral-payload
           (goal13-mistral-model "magistral-medium-latest" t)
           :reasoning :medium)))
    (is (string= "reasoning"
                 (cadr-ai::json-get magistral "prompt_mode")))
    (is (not (cadr-ai::json-present-p magistral "reasoning_effort"))))
  (let ((off
          (goal13-mistral-payload
           (goal13-mistral-model "magistral-medium-latest" t))))
    (is (not (cadr-ai::json-present-p off "prompt_mode")))
    (is (not (cadr-ai::json-present-p off "reasoning_effort"))))
  (dolist (entry
           (list (list "mistral-small-2603" +goal13-none-high-levels+)
                 (list "mistral-medium-latest" +goal13-none-high-levels+)
                 (list "zai-glm-5-2" +goal13-glm-5-2-levels+)))
    (destructuring-bind (id map) entry
      (let ((enabled
              (goal13-mistral-payload
               (goal13-mistral-model id t map)
               :reasoning :high))
            (clamped
              (goal13-mistral-payload
               (goal13-mistral-model id t map)
               :reasoning :low))
            (disabled
              (goal13-mistral-payload
               (goal13-mistral-model id t map))))
        (is (string= "high"
                     (cadr-ai::json-get enabled "reasoning_effort")))
        (is (not (cadr-ai::json-present-p enabled "prompt_mode")))
        (is (string= "high"
                     (cadr-ai::json-get clamped "reasoning_effort")))
        (is (string= "none"
                     (cadr-ai::json-get disabled "reasoning_effort")))
        (is (not (cadr-ai::json-present-p disabled "prompt_mode"))))))
  (is (string= "max"
               (cadr-ai::json-get
                (goal13-mistral-payload
                 (goal13-mistral-model
                  "zai-glm-5-2" t +goal13-glm-5-2-levels+)
                 :reasoning :max)
                "reasoning_effort")))
  (dolist (level '(:low :high :max))
    (let ((payload
            (goal13-mistral-payload
             (goal13-mistral-model
              "zai-glm-5-3" t +goal13-glm-5-3-levels+)
             :reasoning level)))
      (is (string= (string-downcase (symbol-name level))
                   (cadr-ai::json-get payload "reasoning_effort")))
      (is (not (cadr-ai::json-present-p payload "prompt_mode")))))
  (is (string= "high"
               (cadr-ai::json-get
                (goal13-mistral-payload
                 (goal13-mistral-model
                  "zai-glm-5-3" t +goal13-glm-5-3-levels+)
                 :reasoning :medium)
                "reasoning_effort")))
  (let ((glm-off
          (goal13-mistral-model
           "zai-glm-5-3" t +goal13-glm-5-3-levels+)))
    (is (not (cadr-ai::json-present-p
              (goal13-mistral-payload glm-off)
              "reasoning_effort")))
    (is (string= "low"
                 (cadr-ai::json-get
                  (goal13-mistral-payload glm-off :reasoning :off)
                  "reasoning_effort"))))
  (is (not (cadr-ai::json-present-p
            (goal13-mistral-payload
             (goal13-mistral-model
              "empty-effort" t '((:high . "") (:off . "none")))
             :reasoning :high)
            "reasoning_effort")))
  (let ((plain
          (goal13-mistral-payload
           (goal13-mistral-model "mistral-medium-2505" nil)
           :reasoning :medium))
        (forced
          (goal13-mistral-payload
           (goal13-mistral-model "mistral-medium-2505" nil)
           :prompt-mode "reasoning")))
    (is (not (cadr-ai::json-present-p plain "prompt_mode")))
    (is (not (cadr-ai::json-present-p plain "reasoning_effort")))
    (is (string= "reasoning"
                 (cadr-ai::json-get forced "prompt_mode")))))

(defun goal13-usage-event (response-tier &key (input 100000) (cached 0))
  (let ((response
          (cadr-ai::json-object
           "status" "completed"
           "usage"
           (cadr-ai::json-object
            "input_tokens" input
            "output_tokens" input
            "total_tokens" (* input 2)
            "input_tokens_details"
            (cadr-ai::json-object "cached_tokens" cached)))))
    (when response-tier
      (cadr-ai::json-put response "service_tier" response-tier))
    (cadr-ai::json-object
     "type" "response.completed"
     "response" response)))

(defun goal13-priced-usage
    (model &key service-tier service-tier-p response-tier
           (input 100000) (cached 0))
  (let* ((provider
               (if (eq (cadr-ai:model-api model) :openai-codex-responses)
               (make-openai-codex-provider
                :oauth-access-token "oauth-test"
                :oauth-account-id "acct-test")
               (make-openai-provider :api-key "sk-test-key")))
         (state
           (cadr-ai::make-provider-stream-state
            :message (cadr-ai::empty-assistant-message model)))
         (cadr-ai::*responses-request-service-tier* service-tier)
         (cadr-ai::*responses-request-service-tier-p* service-tier-p))
    (cadr-ai::reduce-provider-sse-event
     provider state
     (cadr-ai::make-sse-event
      :data (cadr-ai::stringify-json
             (goal13-usage-event
              response-tier :input input :cached cached)))
     (lambda (event) (declare (ignore event))))
    (assistant-message-usage
     (cadr-ai::provider-stream-state-message state))))

(defun goal13-catalog-charge (provider-id model-id tokens price-reader)
  (* (/ (coerce tokens 'double-float) 1000000d0)
     (funcall price-reader
              (cadr-ai:find-model-metadata provider-id model-id))))

(test responses-service-tier-multiplies-returned-usage
  ;; pi@4a080252f openai-responses-compat.test.ts and
  ;; openai-codex-stream.test.ts.
  (dolist (case
           '(("gpt-5.4" "priority" "priority" 2d0 nil)
             ("gpt-5.5" "priority" "priority" 2.5d0 nil)
             ("gpt-5.5" "flex" "flex" 0.5d0 nil)
             ("gpt-6-luna" "priority" "fast" 2d0 nil)
             ("gpt-6-luna" "fast" "fast" 2d0 nil)
             ("gpt-5.4" "priority" "default" 1d0 nil)))
    (destructuring-bind (id request response multiplier codex-p) case
      (declare (ignore codex-p))
      (let ((usage
              (goal13-priced-usage
               (goal13-responses-model :id id :reasoning-p t)
               :service-tier request
               :service-tier-p t
               :response-tier response)))
        (is (goal13-close
             (* multiplier
                (goal13-catalog-charge
                 :openai id 100000
                 #'cadr-ai:model-metadata-input-price))
             (cadr-ai:cost-input (cadr-ai:usage-cost usage))))
        (is (goal13-close
             (* multiplier
                (goal13-catalog-charge
                 :openai id 100000
                 #'cadr-ai:model-metadata-output-price))
             (cadr-ai:cost-output (cadr-ai:usage-cost usage)))))))
  (let ((usage
          (goal13-priced-usage
           (goal13-responses-model :id "gpt-5.4" :reasoning-p t)
           :service-tier "priority"
           :service-tier-p t
           :response-tier "priority"
           :input 100000
           :cached 20000)))
    (is (goal13-close
         (* 2d0
            (goal13-catalog-charge
             :openai "gpt-5.4" 80000
             #'cadr-ai:model-metadata-input-price))
         (cadr-ai:cost-input (cadr-ai:usage-cost usage))))
    (is (goal13-close
         (* 2d0
            (goal13-catalog-charge
             :openai "gpt-5.4" 20000
             #'cadr-ai:model-metadata-cache-read-price))
         (cadr-ai:cost-cache-read (cadr-ai:usage-cost usage)))))
  (dolist (case
           '(("gpt-6-luna" "flex" "default" 0.5d0)
             ("gpt-6-luna" "priority" "default" 2d0)
             ("gpt-6-luna" "fast" "fast" 1d0)))
    (destructuring-bind (id request response multiplier) case
      (let ((usage
              (goal13-priced-usage
               (goal13-responses-model
                :id id
                :provider :openai-codex
                :api :openai-codex-responses
                :reasoning-p t)
               :service-tier request
               :service-tier-p t
               :response-tier response)))
        (is (goal13-close
             (* multiplier
                (goal13-catalog-charge
                 :openai-codex id 100000
                 #'cadr-ai:model-metadata-input-price))
             (cadr-ai:cost-input (cadr-ai:usage-cost usage))))
        (is (goal13-close
             (* multiplier
                (goal13-catalog-charge
                 :openai-codex id 100000
                 #'cadr-ai:model-metadata-output-price))
             (cadr-ai:cost-output (cadr-ai:usage-cost usage))))))
  (is (= 2.5d0)
         (cadr-ai::responses-service-tier-multiplier
          "gpt-5.5" "priority" t)))
  (is (= 1d0
         (cadr-ai::responses-service-tier-multiplier
          "gpt-5.5" "fast" t)))
  (is (= 2.5d0
         (cadr-ai::responses-service-tier-multiplier
          "gpt-5.5" "fast" nil)))
  (is (= 0.5d0
         (cadr-ai::responses-service-tier-multiplier
          "gpt-5.1-codex" "flex" t))))

(test stream-chat-applies-the-requested-service-tier
  ;; The stream entry binds the request tier the reducer prices with.
  (let ((seen nil)
        (model (goal13-responses-model :id "gpt-5.4" :reasoning-p t))
        (*http-request-function*
          (lambda (url &rest arguments)
            (declare (ignore url arguments))
            (values
             (flexi-streams:make-in-memory-input-stream
              (babel:string-to-octets
               (format nil "data: ~A~%~%"
                       (cadr-ai::stringify-json
                        (goal13-usage-event "priority")))
               :encoding :utf-8))
             200
             '(("content-type" . "text/event-stream"))))))
    (let ((message
            (stream-chat
             (make-openai-provider :api-key "sk-test-key")
             model
             (goal13-context)
             (lambda (event) (declare (ignore event)))
             :service-tier "priority"
             :transport :sse
             :on-payload
             (lambda (payload request-model)
               (declare (ignore request-model))
               (setf seen payload)
               nil))))
      (is (string= "priority"
                   (cadr-ai::json-get seen "service_tier")))
      (is (goal13-close
           (* 2d0
              (goal13-catalog-charge
               :openai "gpt-5.4" 100000
               #'cadr-ai:model-metadata-input-price))
           (cadr-ai:cost-input
            (cadr-ai:usage-cost (assistant-message-usage message))))))))
