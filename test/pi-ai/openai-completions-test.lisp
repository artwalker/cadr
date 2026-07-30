(in-package #:pi-ai/tests)
(in-suite pi-ai-suite)

(defun completions-provider-and-model ()
  (values
   (pi-ai:make-openai-completions-provider :api-key "deepseek-test")
   (pi-ai:make-model :id "deepseek-v4-flash"
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
             (pi-ai:make-context
              :system-prompt "Be exact."
              :messages
              (list
               (pi-ai:make-user-message :content "Inspect.")
               (pi-ai:make-assistant-message
                :content
                (list
                 (pi-ai:make-thinking-content
                  :thinking "Need a file."
                  :signature "reasoning_content")
                 (pi-ai:make-tool-call
                  :id "call-1"
                  :name "read"
                  :arguments (pi-ai::json-object "path" "README.md")))
                :api :openai-completions
                :provider :deepseek
                :model "deepseek-v4-flash"
                :stop-reason :tool-use)
               (pi-ai:make-tool-result-message
                :tool-call-id "call-1"
                :tool-name "read"
                :content (list (pi-ai:make-text-content :text "hello"))))
              :tools
              (list
               (pi-ai:make-tool
                :name "read"
                :description "Read file"
                :parameters (sample-schema)))))
           (request
             (pi-ai:build-request provider model context
                                  :stream-p t
                                  :max-tokens 2048
                                  :temperature 0.2))
           (payload (pi-ai:request-spec-payload request))
           (messages (pi-ai::json-get payload "messages")))
      (is (string= "https://api.deepseek.com/v1/chat/completions"
                   (pi-ai:request-spec-url request)))
      (is (string= "Bearer deepseek-test"
                   (cdr (assoc "authorization"
                               (pi-ai:request-spec-headers request)
                               :test #'string-equal))))
      (is (eq t (pi-ai::json-get payload "stream")))
      (is (eq t (pi-ai::json-get
                 (pi-ai::json-get payload "stream_options")
                 "include_usage")))
      (is (= 4 (length messages)))
      (is (string= "system" (pi-ai::json-get (aref messages 0) "role")))
      (is (string= "assistant"
                   (pi-ai::json-get (aref messages 2) "role")))
      (is (string= "Need a file."
                   (pi-ai::json-get (aref messages 2)
                                    "reasoning_content")))
      (is (string= "tool" (pi-ai::json-get (aref messages 3) "role")))
      (is (= 1 (length (pi-ai::json-get payload "tools")))))))

(test openai-completions-parses-complete-tool-call-and-usage
  (multiple-value-bind (provider model)
      (completions-provider-and-model)
    (let* ((response
             (pi-ai::parse-json
              "{\"id\":\"chatcmpl-1\",\"choices\":[{\"finish_reason\":\"tool_calls\",\"message\":{\"content\":\"\",\"reasoning_content\":\"thinking\",\"tool_calls\":[{\"id\":\"call_7\",\"type\":\"function\",\"function\":{\"name\":\"read\",\"arguments\":\"{\\\"path\\\":\\\"README.md\\\"}\"}}]}}],\"usage\":{\"prompt_tokens\":12,\"completion_tokens\":7,\"prompt_tokens_details\":{\"cached_tokens\":2},\"completion_tokens_details\":{\"reasoning_tokens\":3}}}"))
           (message
             (pi-ai:parse-complete-response provider model response)))
      (is (eq :tool-use (pi-ai:assistant-message-stop-reason message)))
      (is (string= "chatcmpl-1"
                   (pi-ai:assistant-message-response-id message)))
      (is (typep (first (pi-ai:assistant-message-content message))
                 'pi-ai:thinking-content))
      (is (typep (second (pi-ai:assistant-message-content message))
                 'pi-ai:tool-call))
      (is (= 10 (pi-ai:usage-input
                 (pi-ai:assistant-message-usage message))))
      (is (= 7 (pi-ai:usage-output
                (pi-ai:assistant-message-usage message))))
      (is (= 2 (pi-ai:usage-cache-read
                (pi-ai:assistant-message-usage message))))
      (is (= 3 (pi-ai:usage-reasoning
                (pi-ai:assistant-message-usage message)))))))

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
              (pi-ai:stream-chat
               provider model (sample-context)
               (lambda (event) (push event events)))))
        (setf events (nreverse events))
        (is (eq :tool-use
                (pi-ai:assistant-message-stop-reason message)))
        (is (typep (second (pi-ai:assistant-message-content message))
                   'pi-ai:tool-call))
        (is (equal "README.md"
                   (pi-ai::json-get
                    (pi-ai:tool-call-arguments
                     (second
                      (pi-ai:assistant-message-content message)))
                    "path")))
        (is (= 25 (pi-ai:usage-total
                   (pi-ai:assistant-message-usage message))))
        (is (member :thinking-delta (collect-event-types events)))
        (is (member :tool-call-delta (collect-event-types events)))
        (is (eq :done
                (pi-ai:stream-event-type (car (last events)))))))))
