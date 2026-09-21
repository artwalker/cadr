(in-package #:cadr-ai/tests)
(in-suite cadr-ai-suite)

(test provider-request-payloads-match-reference-fixtures
  (dolist (provider-name '(:anthropic :openai :google))
    (multiple-value-bind (provider model)
        (provider-case provider-name)
      (dolist (stream-p '(nil t))
        (let* ((suffix (if stream-p "stream" "complete"))
               (relative (format nil
                                 "test/fixtures/requests/~(~A~)-~A.json"
                                 provider-name suffix))
               (expected (parse-json (read-fixture relative)))
               (request (build-request provider model (sample-context)
                                       :stream-p stream-p
                                       :max-tokens 4096
                                       :cache-retention :none)))
          (is (eql stream-p (request-spec-stream-p request)))
          (is (json-equal-p expected (request-spec-payload request))
              "~A ~A payload differs" provider-name suffix))))))

(test provider-request-paths-and-auth-headers
  (multiple-value-bind (provider model)
      (provider-case :anthropic)
    (let ((request (build-request provider model (sample-context)
                                  :stream-p t)))
      (is (string= "https://api.anthropic.com/v1/messages"
                   (request-spec-url request)))
      (is (string= "anthropic-test"
                   (cdr (assoc "x-api-key"
                               (request-spec-headers request)
                               :test #'string-equal))))))
  (multiple-value-bind (provider model)
      (provider-case :openai)
    (let ((request (build-request provider model (sample-context)
                                  :stream-p t)))
      (is (string= "https://api.openai.com/v1/responses"
                   (request-spec-url request)))
      (is (string= "Bearer openai-test"
                   (cdr (assoc "authorization"
                               (request-spec-headers request)
                               :test #'string-equal))))))
  (multiple-value-bind (provider model)
      (provider-case :google)
    (let ((stream-request (build-request provider model (sample-context)
                                         :stream-p t))
          (complete-request (build-request provider model (sample-context)
                                           :stream-p nil)))
      (is (string=
           "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:streamGenerateContent?alt=sse"
           (request-spec-url stream-request)))
      (is (string=
           "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent"
           (request-spec-url complete-request)))
      (is (string= "google-test"
                   (cdr (assoc "x-goog-api-key"
                               (request-spec-headers stream-request)
                               :test #'string-equal)))))))

(test gemini-3.6-omits-deprecated-sampling-parameters
  (multiple-value-bind (provider model)
      (provider-case :google)
    (let* ((request (build-request provider model (sample-context)
                                   :stream-p t
                                   :max-tokens 4096
                                   :temperature 0.7))
           (generation-config
             (cadr-ai::json-get (request-spec-payload request)
                              "generationConfig")))
      (is (hash-table-p generation-config))
      (is (not (cadr-ai::json-present-p generation-config "temperature")))
      (is (not (cadr-ai::json-present-p generation-config "top_p")))
      (is (not (cadr-ai::json-present-p generation-config "top_k"))))))

(test codex-responses-omits-ordinary-openai-output-limit
  (let* ((codex-model
           (make-model
            :id "gpt-5.5"
            :provider :openai-codex
            :api :openai-codex-responses
            :base-url "https://chatgpt.com/backend-api"))
         (openai-model
           (make-model
            :id "gpt-5.5"
            :provider :openai
            :api :openai-responses
            :base-url "https://api.openai.com"))
         (context (sample-context))
         (openai-request
           (build-request
            (make-openai-provider :api-key "openai-test")
            openai-model
            context
            :stream-p t
            :max-tokens 4096))
         (codex-request
           (build-request
            (cadr-ai:make-openai-codex-provider
             :oauth-access-token "oauth-test"
             :oauth-account-id "acct-test")
            codex-model
            context
            :stream-p t
            :max-tokens 4096)))
    ;; Ordinary Responses supports max_output_tokens; the ChatGPT Codex
    ;; endpoint rejects that parameter and Pi never sends it.
    (is (= 4096
           (cadr-ai::json-get
            (request-spec-payload openai-request)
            "max_output_tokens")))
    (is (not
         (cadr-ai::json-present-p
          (request-spec-payload codex-request)
          "max_output_tokens")))))

(test goal24-codex-omitted-reasoning-sends-off-effort
  (let ((provider
          (cadr-ai:make-openai-codex-provider
           :oauth-access-token "oauth-test"
           :oauth-account-id "acct-test"))
        (unmapped
          (make-model
           :id "goal24-codex"
           :provider :openai-codex
           :api :openai-codex-responses
           :base-url "https://chatgpt.com/backend-api"
           :reasoning-p t))
        (null-off
          (make-model
           :id "goal24-codex"
           :provider :openai-codex
           :api :openai-codex-responses
           :base-url "https://chatgpt.com/backend-api"
           :reasoning-p t
           :thinking-level-map '((:off . nil))))
        (mapped-low
          (make-model
           :id "goal24-codex"
           :provider :openai-codex
           :api :openai-codex-responses
           :base-url "https://chatgpt.com/backend-api"
           :reasoning-p t
           :thinking-level-map '((:off . "low")))))
    (let* ((payload
             (request-spec-payload
              (build-request provider unmapped (sample-context)
                             :stream-p t)))
           (reasoning (cadr-ai::json-get payload "reasoning")))
      (is (string= "none" (cadr-ai::json-get reasoning "effort")))
      (is (not (cadr-ai::json-present-p reasoning "summary"))))
    (is (not
         (cadr-ai::json-present-p
          (request-spec-payload
           (build-request provider null-off (sample-context)
                          :stream-p t))
          "reasoning")))
    (is (string=
         "low"
         (cadr-ai::json-get
          (cadr-ai::json-get
           (request-spec-payload
            (build-request provider mapped-low (sample-context)
                           :stream-p t))
           "reasoning")
          "effort")))))

(test providers-reject-missing-api-key
  (let ((model (make-model :id "gpt-test"
                           :provider :openai
                           :api :openai-responses
                           :base-url "https://api.openai.com"
                           :max-tokens 4096)))
    (signals cadr-ai:configuration-error
      (build-request (make-openai-provider :api-key "")
                     model
                     (sample-context)
                     :stream-p t))))
