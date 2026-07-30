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
