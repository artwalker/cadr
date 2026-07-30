(in-package #:cadr-ai/tests)
(in-suite cadr-ai-suite)

(defun completions-provider-and-model ()
  (values
   (cadr-ai:make-openai-completions-provider :api-key "deepseek-test")
   (cadr-ai:make-model :id "deepseek-v4-flash"
                     :provider :deepseek
                     :api :openai-completions
                     :base-url "https://api.deepseek.com"
                     :max-tokens 8192
                     :supports-tools-p t
                     :reasoning-p t)))

(test openai-completions-builds-tool-history
  (multiple-value-bind (provider model)
      (completions-provider-and-model)
    (let* ((context
             (cadr-ai:make-context
              :system-prompt "Be exact."
              :messages
              (list
               (cadr-ai:make-user-message :content "Inspect.")
               (cadr-ai:make-assistant-message
                :content
                (list
                 (cadr-ai:make-thinking-content
                  :thinking "Need a file."
                  :signature "reasoning_content")
                 (cadr-ai:make-tool-call
                  :id "call-1"
                  :name "read"
                  :arguments (cadr-ai::json-object "path" "README.md")))
                :api :openai-completions
                :provider :deepseek
                :model "deepseek-v4-flash"
                :stop-reason :tool-use)
               (cadr-ai:make-tool-result-message
                :tool-call-id "call-1"
                :tool-name "read"
                :content (list (cadr-ai:make-text-content :text "hello"))))
              :tools
              (list
               (cadr-ai:make-tool
                :name "read"
                :description "Read file"
                :parameters (sample-schema)))))
           (request
             (cadr-ai:build-request provider model context
                                  :stream-p t
                                  :max-tokens 2048
                                  :temperature 0.2))
           (payload (cadr-ai:request-spec-payload request))
           (messages (cadr-ai::json-get payload "messages")))
      (is (string= "https://api.deepseek.com/v1/chat/completions"
                   (cadr-ai:request-spec-url request)))
      (is (string= "Bearer deepseek-test"
                   (cdr (assoc "authorization"
                               (cadr-ai:request-spec-headers request)
                               :test #'string-equal))))
      (is (eq t (cadr-ai::json-get payload "stream")))
      (is (eq t (cadr-ai::json-get
                 (cadr-ai::json-get payload "stream_options")
                 "include_usage")))
      (is (= 4 (length messages)))
      (is (string= "system" (cadr-ai::json-get (aref messages 0) "role")))
      (is (string= "assistant"
                   (cadr-ai::json-get (aref messages 2) "role")))
      (is (string= "Need a file."
                   (cadr-ai::json-get (aref messages 2)
                                    "reasoning_content")))
      (is (string= "tool" (cadr-ai::json-get (aref messages 3) "role")))
      (is (= 1 (length (cadr-ai::json-get payload "tools")))))))

(test openai-completions-parses-complete-tool-call-and-usage
  (multiple-value-bind (provider model)
      (completions-provider-and-model)
    (let* ((response
             (cadr-ai::parse-json
              "{\"id\":\"chatcmpl-1\",\"choices\":[{\"finish_reason\":\"tool_calls\",\"message\":{\"content\":\"\",\"reasoning_content\":\"thinking\",\"tool_calls\":[{\"id\":\"call_7\",\"type\":\"function\",\"function\":{\"name\":\"read\",\"arguments\":\"{\\\"path\\\":\\\"README.md\\\"}\"}}]}}],\"usage\":{\"prompt_tokens\":12,\"completion_tokens\":7,\"prompt_tokens_details\":{\"cached_tokens\":2},\"completion_tokens_details\":{\"reasoning_tokens\":3}}}"))
           (message
             (cadr-ai:parse-complete-response provider model response)))
      (is (eq :tool-use (cadr-ai:assistant-message-stop-reason message)))
      (is (string= "chatcmpl-1"
                   (cadr-ai:assistant-message-response-id message)))
      (is (typep (first (cadr-ai:assistant-message-content message))
                 'cadr-ai:thinking-content))
      (is (typep (second (cadr-ai:assistant-message-content message))
                 'cadr-ai:tool-call))
      (is (= 10 (cadr-ai:usage-input
                 (cadr-ai:assistant-message-usage message))))
      (is (= 7 (cadr-ai:usage-output
                (cadr-ai:assistant-message-usage message))))
      (is (= 2 (cadr-ai:usage-cache-read
                (cadr-ai:assistant-message-usage message))))
      (is (= 3 (cadr-ai:usage-reasoning
                (cadr-ai:assistant-message-usage message)))))))

(test recorded-deepseek-chat-completions-stream
  (multiple-value-bind (provider model)
      (completions-provider-and-model)
    (let ((events nil)
          (*http-request-function*
            (lambda (url &rest arguments)
              (declare (ignore url arguments))
              (values
               (open (fixture-path
                      "test/fixtures/sse/deepseek-tool.sse")
                     :direction :input
                     :element-type '(unsigned-byte 8))
               200
               '(("content-type" . "text/event-stream"))))))
      (let ((message
              (cadr-ai:stream-chat
               provider model (sample-context)
               (lambda (event) (push event events)))))
        (setf events (nreverse events))
        (is (eq :tool-use
                (cadr-ai:assistant-message-stop-reason message)))
        (is (typep (second (cadr-ai:assistant-message-content message))
                   'cadr-ai:tool-call))
        (is (equal "README.md"
                   (cadr-ai::json-get
                    (cadr-ai:tool-call-arguments
                     (second
                      (cadr-ai:assistant-message-content message)))
                    "path")))
        (is (= 25 (cadr-ai:usage-total
                   (cadr-ai:assistant-message-usage message))))
        (is (member :thinking-delta (collect-event-types events)))
        (is (member :tool-call-delta (collect-event-types events)))
        (is (eq :done
                (cadr-ai:stream-event-type (car (last events)))))))))

(test openai-completions-preserves-routed-response-model
  (multiple-value-bind (provider model)
      (completions-provider-and-model)
    (let ((response
            (cadr-ai::json-object
             "id" "chatcmpl-routed"
             "model" "anthropic/claude-opus-4.8"
             "choices"
             (vector
              (cadr-ai::json-object
               "message"
               (cadr-ai::json-object "content" "ok")
               "finish_reason" "stop")))))
      (let ((message
              (cadr-ai:parse-complete-response
               provider model response)))
        (is (string=
             (cadr-ai:model-id model)
             (cadr-ai:assistant-message-model message)))
        (is (string=
             "anthropic/claude-opus-4.8"
             (cadr-ai:assistant-message-response-model message))))
      (setf (gethash "model" response)
            (cadr-ai:model-id model))
      (is (null
           (cadr-ai:assistant-message-response-model
            (cadr-ai:parse-complete-response
             provider model response)))))))
