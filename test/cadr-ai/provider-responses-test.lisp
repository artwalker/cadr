(in-package #:cadr-ai/tests)
(in-suite cadr-ai-suite)

(test complete-response-fixtures-normalize-messages-and-usage
  (dolist (provider-name '(:anthropic :openai :google))
    (multiple-value-bind (provider model)
        (provider-case provider-name)
      (let* ((relative (format nil
                               "test/fixtures/responses/~(~A~)-complete.json"
                               provider-name))
             (response (parse-json (read-fixture relative)))
             (message (parse-complete-response provider model response)))
        (is (eq :stop (assistant-message-stop-reason message)))
        (is (string= "Hello from fixture." (first-text message)))
        (is (= 11 (usage-input (assistant-message-usage message))))
        (is (= 5 (usage-output (assistant-message-usage message)))
            "~A output usage differs" provider-name)
        (is (= 2 (usage-cache-read (assistant-message-usage message))))
        (is (= 18 (usage-total (assistant-message-usage message))))))))

(test complete-chat-uses-real-nonstream-request-path
  (multiple-value-bind (provider model)
      (provider-case :openai)
    (let ((captured nil))
      (let ((*http-request-function*
              (lambda (url &rest arguments)
                (setf captured (list url arguments))
                (values (read-fixture
                         "test/fixtures/responses/openai-complete.json")
                        200
                        '(("content-type" . "application/json"))))))
      (let ((message (complete-chat provider model (sample-context)
                                    :max-tokens 4096)))
        (is (eq :stop (assistant-message-stop-reason message)))
        (is (string= "Hello from fixture." (first-text message)))
        (is (null (getf (second captured) :want-stream)))
        (is (string= "https://api.openai.com/v1/responses"
                     (first captured))))))))

(test complete-chat-keeps-single-v1-or-codex-base-segment
  ;; Regression: reversed uiop:string-suffix-p arguments produced
  ;; /v1/v1/responses and /codex/codex/responses for bases that
  ;; already carried the suffix.
  (dolist (case
           (list
            (list :key
                  "https://fixture.invalid/v1"
                  "https://fixture.invalid/v1/responses")
            (list :key
                  "https://fixture.invalid"
                  "https://fixture.invalid/v1/responses")
            (list :oauth
                  "https://fixture.invalid/codex"
                  "https://fixture.invalid/codex/responses")))
    (destructuring-bind (auth-kind base expected) case
      (let* ((provider
               (cadr-ai:make-openai-provider
                :api-key (when (eq auth-kind :key) "key")
                :oauth-access-token
                (when (eq auth-kind :oauth) "token")
                :oauth-account-id
                (when (eq auth-kind :oauth) "account")))
             (model
               (cadr-ai:make-model
                :id "gpt-test"
                :provider :openai
                :api :openai-responses
                :base-url base
                :max-tokens 4096))
             (captured nil))
        (let ((*http-request-function*
                (lambda (url &rest arguments)
                  (declare (ignore arguments))
                  (setf captured url)
                  (values
                   (read-fixture
                    "test/fixtures/responses/openai-complete.json")
                   200
                   '(("content-type" . "application/json"))))))
          (complete-chat provider model (sample-context)
                         :max-tokens 4096)
          (is (string= expected captured)))))))

(test complete-chat-normalizes-api-errors
  (multiple-value-bind (provider model)
      (provider-case :google)
    (let ((*http-request-function*
            (lambda (url &rest arguments)
              (declare (ignore url arguments))
              (values "{\"error\":{\"code\":429,\"message\":\"slow down\",\"status\":\"RESOURCE_EXHAUSTED\"}}"
                      429
                      '(("retry-after" . "2"))))))
      (let ((message (complete-chat provider model (sample-context))))
        (is (eq :error (assistant-message-stop-reason message)))
        (is (search "slow down"
                    (assistant-message-error-message message)))))))

(test complete-chat-honors-immediate-abort
  (multiple-value-bind (provider model)
      (provider-case :anthropic)
    (let* ((called-p nil)
           (*http-request-function*
            (lambda (url &rest arguments)
              (declare (ignore url arguments))
              (setf called-p t)
              (error "HTTP must not be called"))))
      (let ((message
              (complete-chat provider model (sample-context)
                             :abort-p (constantly t))))
        (is (not called-p))
        (is (eq :aborted (assistant-message-stop-reason message)))))))

(defun responses-failed-without-message (model)
  (let* ((provider (make-openai-provider :api-key "test"))
         (state
           (cadr-ai::make-provider-stream-state
            :message (cadr-ai::empty-assistant-message model)))
         (payload
           (cadr-ai::stringify-json
            (cadr-ai::json-object
             "type" "response.failed"
             "response"
             (cadr-ai::json-object
              "error" (cadr-ai::json-object))))))
    (handler-case
        (progn
          (cadr-ai::reduce-provider-sse-event
           provider state
           (cadr-ai::make-sse-event :data payload)
           (lambda (event) (declare (ignore event))))
          nil)
      (cadr-ai:api-error (condition)
        condition))))

(test openai-responses-failed-labels-non-openai-provider
  ;; Baseline openai-responses.ts catch: provider id, not always OpenAI.
  (let* ((model
           (make-model
            :id "copilot-gpt"
            :provider :github-copilot
            :api :openai-responses
            :base-url "https://api.githubcopilot.com"
            :max-tokens 4096))
         (condition (responses-failed-without-message model))
         (message (cadr-ai:cadr-error-message condition)))
    (is (eq :github-copilot (cadr-ai:api-error-provider condition)))
    (is (string= "github-copilot response failed" message))))

(test openai-responses-failed-keeps-openai-display-label
  (let* ((model
           (make-model
            :id "gpt-test"
            :provider :openai
            :api :openai-responses
            :base-url "https://api.openai.com"
            :max-tokens 4096))
         (condition (responses-failed-without-message model))
         (message (cadr-ai:cadr-error-message condition)))
    (is (eq :openai (cadr-ai:api-error-provider condition)))
    (is (string= "OpenAI response failed" message))))

(test openai-responses-build-request-carries-model-provider
  (let* ((model
           (make-model
            :id "copilot-gpt"
            :provider :github-copilot
            :api :openai-responses
            :base-url "https://api.githubcopilot.com"
            :max-tokens 4096))
         (request
           (build-request
            (make-openai-provider :api-key "test")
            model
            (sample-context)
            :stream-p t
            :max-tokens 4096)))
    (is (eq :github-copilot
            (cadr-ai::request-spec-provider request)))))
