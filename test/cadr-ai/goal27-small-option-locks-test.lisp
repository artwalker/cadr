(in-package #:cadr-ai/tests)
(in-suite cadr-ai-suite)

(defun goal49-completions-model (&key compat (max-tokens 16384))
  (make-model
   :id "zai-org/glm-5.2"
   :name "GLM 5.2"
   :provider :local-vllm
   :api :openai-completions
   :base-url "http://127.0.0.1:9/v1"
   :max-tokens max-tokens
   :context-window 262144
   :reasoning-p t
   :compat compat))

(defun goal49-completions-payload
    (model &key reasoning thinking-budgets max-tokens)
  (request-spec-payload
   (build-request
    (cadr-ai:make-openai-completions-provider :api-key "test")
    model
    (make-context
     :messages
     (list (make-user-message :content "Hi")))
    :stream-p t
    :reasoning reasoning
    :thinking-budgets thinking-budgets
    :max-tokens max-tokens)))

(defun goal49-budget (payload field)
  (cadr-ai::json-get payload field))

(test completions-thinking-budgets-follow-the-v140-request
  ;; pi@4a080252f packages/ai/test/openai-completions-thinking-token-budget.test.ts
  (let ((alias
          (goal49-completions-model
           :compat '(:thinking-format :zai
                     :supports-thinking-token-budget t))))
    (is (= 4096
           (goal49-budget
            (goal49-completions-payload
             alias
             :reasoning :medium
             :thinking-budgets '(:medium 4096))
            "thinking_token_budget")))
    (let ((plain
            (goal49-completions-payload
             (goal49-completions-model
              :compat '(:thinking-format :zai))
             :reasoning :medium
             :thinking-budgets '(:medium 4096))))
      (is (not (cadr-ai::json-present-p plain "thinking_token_budget")))
      (is (not (cadr-ai::json-present-p plain "thinking_budget")))
      (is (not (cadr-ai::json-present-p plain "thinking_budget_tokens"))))
    (is (not
         (cadr-ai::json-present-p
          (goal49-completions-payload
           alias
           :thinking-budgets '(:high 8192))
          "thinking_token_budget")))
    (is (= 8192
           (goal49-budget
            (goal49-completions-payload
             alias
             :reasoning :xhigh
             :thinking-budgets '(:high 8192))
            "thinking_token_budget")))
    (is (= 8192
           (goal49-budget
            (goal49-completions-payload
             alias
             :reasoning :max
             :thinking-budgets '(:high 8192))
            "thinking_token_budget")))
    (is (= (- 16384 1024)
           (goal49-budget
            (goal49-completions-payload alias :reasoning :high)
            "thinking_token_budget")))
    (is (= (- 4096 1024)
           (goal49-budget
            (goal49-completions-payload
             alias
             :reasoning :high
             :thinking-budgets '(:high 8192)
             :max-tokens 4096)
            "thinking_token_budget")))
    (is (not
         (cadr-ai::json-present-p
          (goal49-completions-payload
           alias
           :reasoning :high
           :thinking-budgets '(:high 0))
          "thinking_token_budget"))))
  (dolist (field '("thinking_budget" "thinking_budget_tokens"))
    (let ((payload
            (goal49-completions-payload
             (goal49-completions-model
              :compat (list :thinking-format :qwen
                            :thinking-token-budget-field field))
             :reasoning :medium
             :thinking-budgets '(:medium 4096))))
      (is (= 4096 (goal49-budget payload field)))
      (is (not (cadr-ai::json-present-p
                payload "thinking_token_budget")))))
  (let ((payload
          (goal49-completions-payload
           (goal49-completions-model
            :compat '(:thinking-format :zai
                      :supports-thinking-token-budget t
                      :thinking-token-budget-field "thinking_budget"))
           :reasoning :medium
           :thinking-budgets '(:medium 4096))))
    (is (= 4096 (goal49-budget payload "thinking_budget")))
    (is (not (cadr-ai::json-present-p
              payload "thinking_token_budget"))))
  (let* ((model
           (goal49-completions-model
            :compat '(:thinking-format :chat-template
                      :chat-template-kwargs
                      (("enable_thinking" :var "thinking.enabled")
                       ("thinking_budget" :var "thinking.budget")))))
         (on
           (goal49-completions-payload model :reasoning :high))
         (kwargs (cadr-ai::json-get on "chat_template_kwargs")))
    (is (eq t (cadr-ai::json-get kwargs "enable_thinking")))
    (is (= (- 16384 1024)
           (cadr-ai::json-get kwargs "thinking_budget")))
    (is (not (cadr-ai::json-present-p on "thinking_token_budget")))
    (let* ((off (goal49-completions-payload model))
           (off-kwargs
             (cadr-ai::json-get off "chat_template_kwargs")))
      (is (cadr-ai::json-present-p off-kwargs "enable_thinking"))
      (is (null (cadr-ai::json-get off-kwargs "enable_thinking")))
      (is (not (cadr-ai::json-present-p
                off-kwargs "thinking_budget"))))))

(defun goal49-pi-messages-request (&key debug)
  (build-request
   (make-pi-messages-provider :api-key "test-key")
   (make-model
    :id "auto"
    :provider :pi
    :api :pi-messages
    :base-url "http://127.0.0.1:9/v1/")
   (make-context
    :messages (list (make-user-message :content "Hi")))
   :stream-p t
   :debug debug))

(test pi-messages-debug-appends-a-query-and-stays-out-of-the-body
  ;; pi@4a080252f packages/ai/test/pi-messages.test.ts
  ;; "appends debug=1 and reports response headers via onResponse"
  (let ((request (goal49-pi-messages-request :debug t)))
    (is (string=
         "http://127.0.0.1:9/v1/messages?debug=1"
         (request-spec-url request)))
    (is (not (cadr-ai::json-present-p
              (cadr-ai::json-get
               (request-spec-payload request) "options")
              "debug"))))
  (is (string=
       "http://127.0.0.1:9/v1/messages"
       (request-spec-url (goal49-pi-messages-request))))
  (is (string=
       "http://127.0.0.1:9/v1/messages"
       (request-spec-url
        (goal49-pi-messages-request :debug nil))))
  (let ((seen-url nil))
    (let ((*http-request-function*
            (lambda (url &key &allow-other-keys)
              (setf seen-url url)
              (values
               (make-string-input-stream
                (format nil "data: {\"type\":\"done\",\"reason\":\"stop\"}~%~%"))
               200
               '(("content-type" . "text/event-stream")
                 ("x-pi-gateway-upstream-provider" . "anthropic"))))))
      (let ((message
              (stream-chat
               (make-pi-messages-provider :api-key "test-key")
               (make-model
                :id "auto"
                :provider :pi
                :api :pi-messages
                :base-url "http://127.0.0.1:9/v1")
               (make-context
                :messages
                (list (make-user-message :content "Hi")))
               #'identity
               :debug t)))
        (declare (ignore message))))
    (is (string= "http://127.0.0.1:9/v1/messages?debug=1" seen-url))))
