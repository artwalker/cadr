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

(test chat-completions-url-keeps-single-v1-segment
  ;; Regression: uiop:string-suffix-p argument order was reversed, so
  ;; bases already ending in /v1 (e.g. opencode-go) got /v1 appended a
  ;; second time and the provider hit a 404.
  (is (string=
       "https://opencode.ai/zen/go/v1/chat/completions"
       (cadr-ai::chat-completions-url
        "https://opencode.ai/zen/go/v1")))
  (is (string=
       "https://api.deepseek.com/v1/chat/completions"
       (cadr-ai::chat-completions-url
        "https://api.deepseek.com")))
  (is (string=
       "https://api.deepseek.com/v1/chat/completions"
       (cadr-ai::chat-completions-url
        "https://api.deepseek.com/v1")))
  (is (string=
       "https://api.deepseek.com/chat/completions"
       (cadr-ai::chat-completions-url
        "https://api.deepseek.com/chat/completions")))
  (is (string=
       "https://api.deepseek.com/v1/chat/completions"
       (cadr-ai::chat-completions-url
        "https://api.deepseek.com/v1/chat/completions"))))

(defun stream-completions-text-deltas (provider model deltas)
  (let ((events nil)
        (*http-request-function*
          (lambda (url &rest arguments)
            (declare (ignore url arguments))
            (values
             (make-string-input-stream
              (with-output-to-string (output)
                (dolist (delta deltas)
                  (format
                   output "data: ~A~%~%"
                   (cadr-ai::stringify-json
                    (cadr-ai::json-object
                     "choices"
                     (vector
                      (cadr-ai::json-object
                       "delta"
                       (cadr-ai::json-object
                        "content" delta)
                       "finish_reason" 'cadr-ai::null))))))
                (format
                 output
                 "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}~%~%")))
             200
             '(("content-type" . "text/event-stream"))))))
    (values
     (cadr-ai:stream-chat
      provider model
      (cadr-ai:make-context
       :messages
       (list
        (cadr-ai:make-user-message :content "repeat")))
      (lambda (event)
        (push event events)))
     (nreverse events))))

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

(test openai-completions-stream-text-is-character-exact-for-all-delta-boundaries
  (multiple-value-bind (provider model)
      (completions-provider-and-model)
    (let* ((expected
             "The exit code was 7 and there are 12 steps and 3 files.")
           (character-deltas
             (loop for character across expected
                   collect (string character)))
           (cases
             (append
              (loop for split from 0 to (length expected)
                    collect
                    (list (subseq expected 0 split)
                          (subseq expected split)))
              (list
               character-deltas
               '("The exit code was" " " "7" " and there are" " "
                 "12" " steps and" " " "3" " files.")
               '("The exit code was" " 7" " and there are" " 12"
                 " steps and" " 3" " files.")))))
      (dolist (deltas cases)
        (multiple-value-bind (message events)
            (stream-completions-text-deltas
             provider model deltas)
          (is (string= expected (first-text message)))
          (is
           (string=
            expected
            (format
             nil "~{~A~}"
             (loop for event in events
                   when
                     (eq :text-delta
                         (cadr-ai:stream-event-type event))
                     collect
                     (cadr-ai:stream-event-delta event))))))))
    (dolist
        (case
         '(("12345" ("1" "2" "3" "4" "5"))
           ("7 starts at line zero" ("7" " starts at line zero"))
           ("alpha  12 omega" ("alpha" "  " "12" " omega"))))
      (multiple-value-bind (message events)
          (stream-completions-text-deltas
           provider model (second case))
        (declare (ignore events))
        (is (string= (first case) (first-text message)))))))

(test openai-completions-nonstream-text-is-character-exact
  (multiple-value-bind (provider model)
      (completions-provider-and-model)
    (let* ((expected
             "The exit code was 7 and there are 12 steps and 3 files.")
           (response
             (cadr-ai::json-object
              "choices"
              (vector
               (cadr-ai::json-object
                "message"
                (cadr-ai::json-object "content" expected)
                "finish_reason" "stop"))))
           (message
             (cadr-ai:parse-complete-response
              provider model response)))
      (is (string= expected (first-text message))))))

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

(test completions-without-finish-reason-follow-compat-contract
  (multiple-value-bind (provider ignored-model)
      (completions-provider-and-model)
    (declare (ignore ignored-model))
    (labels
        ((run-case (supports-finish-reason &optional tool-p)
           (let* ((model
                    (cadr-ai:make-model
                     :id "compatible"
                     :provider :compatible
                     :api :openai-completions
                     :base-url "https://example.invalid/v1"
                     :max-tokens 1024
                     :compat
                     (list :supports-finish-reason
                           supports-finish-reason)))
                  (*http-request-function*
                    (lambda (url &rest arguments)
                      (declare (ignore url arguments))
                      (values
                       (make-string-input-stream
                        (if tool-p
                            (format
                             nil
                             "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call-1\",\"function\":{\"name\":\"read\",\"arguments\":\"{}\"}}]},\"finish_reason\":null}]}~%~%data: [DONE]~%~%")
                            (format
                             nil
                             "data: {\"choices\":[{\"delta\":{\"content\":\"hello\"},\"finish_reason\":null}]}~%~%data: [DONE]~%~%")))
                       200
                       '(("content-type"
                          . "text/event-stream"))))))
             (cadr-ai:stream-chat
              provider model
              (cadr-ai:make-context
               :messages
               (list
                (cadr-ai:make-user-message
                 :content "hello")))
              (lambda (event)
                (declare (ignore event)))))))
      (let ((message (run-case nil)))
        (is (eq :stop
                (cadr-ai:assistant-message-stop-reason
                 message)))
        (is (string= "hello" (first-text message))))
      (let ((message (run-case nil t)))
        (is (eq :tool-use
                (cadr-ai:assistant-message-stop-reason
                 message)))
        (is (typep
             (first
              (cadr-ai:assistant-message-content message))
             'cadr-ai:tool-call)))
      (let ((message (run-case t)))
        (is (eq :error
                (cadr-ai:assistant-message-stop-reason
                 message)))
        (is (search
             "terminal"
             (cadr-ai:assistant-message-error-message
              message)))))))

(defun completions-thinking-from-delta (model delta)
  ;; Baseline openai-completions.ts:489-509. One SSE chunk, then
  ;; inspect the thinking block (if any).
  (let* ((provider
           (cadr-ai:make-openai-completions-provider
            :api-key "test"))
         (state
           (cadr-ai::make-provider-stream-state
            :message (cadr-ai::empty-assistant-message model)))
         (payload
           (cadr-ai::stringify-json
            (cadr-ai::json-object
             "id" "chatcmpl-think"
             "choices"
             (vector
              (cadr-ai::json-object
               "delta" delta
               "finish_reason" 'cadr-ai::null))))))
    (cadr-ai::reduce-provider-sse-event
     provider state
     (cadr-ai::make-sse-event :data payload)
     (lambda (event) (declare (ignore event))))
    (let ((block
            (find-if
             (lambda (item)
               (typep item 'cadr-ai:thinking-content))
             (cadr-ai:assistant-message-content
              (cadr-ai::provider-stream-state-message state)))))
      (values
       (and block (cadr-ai:thinking-content-thinking block))
       (and block (cadr-ai:thinking-content-signature block))))))

(test openai-completions-stream-reads-first-nonempty-reasoning-field
  ;; Baseline openai-completions.ts:492-509. First nonempty of
  ;; reasoning_content / reasoning / reasoning_text. Dual emit
  ;; does not double. opencode-go + reasoning uses the
  ;; reasoning_content signature.
  (let ((model
          (cadr-ai:make-model
           :id "mimo-v2.5"
           :provider :opencode-go
           :api :openai-completions
           :base-url "https://opencode.ai/zen/go/v1"
           :max-tokens 1024
           :reasoning-p t)))
    (multiple-value-bind (text signature)
        (completions-thinking-from-delta
         model
         (cadr-ai::json-object "reasoning" "via reasoning"))
      (is (string= "via reasoning" text))
      (is (string= "reasoning_content" signature)))
    (multiple-value-bind (text signature)
        (completions-thinking-from-delta
         model
         (cadr-ai::json-object "reasoning_text" "via text"))
      (is (string= "via text" text))
      (is (string= "reasoning_text" signature)))
    (multiple-value-bind (text signature)
        (completions-thinking-from-delta
         model
         (cadr-ai::json-object
          "reasoning_content" "once"
          "reasoning" "once"))
      (is (string= "once" text))
      (is (string= "reasoning_content" signature)))
    (let ((other
            (cadr-ai:make-model
             :id "other"
             :provider :deepseek
             :api :openai-completions
             :base-url "https://api.deepseek.com"
             :max-tokens 1024
             :reasoning-p t)))
      (multiple-value-bind (text signature)
          (completions-thinking-from-delta
           other
           (cadr-ai::json-object "reasoning" "plain"))
        (is (string= "plain" text))
        (is (string= "reasoning" signature))))))

(test unknown-openai-completions-endpoint-is-not-strict
  (let ((unknown
          (cadr-ai:make-model
           :id "local-model"
           :provider :local-compat
           :api :openai-completions
           :base-url "http://127.0.0.1:9/v1"
           :max-tokens 1024))
        (builtin
          (cadr-ai:make-model
           :id "deepseek-v4-flash"
           :provider :deepseek
           :api :openai-completions
           :base-url "https://api.deepseek.com"
           :max-tokens 1024))
        (advertised
          (cadr-ai:make-model
           :id "local-model"
           :provider :local-compat
           :api :openai-completions
           :base-url "http://127.0.0.1:9/v1"
           :max-tokens 1024
           :compat '(:supports-strict-mode t)))
        (cerebras
          (cadr-ai:make-model
           :id "llama"
           :provider :cerebras
           :api :openai-completions
           :base-url "https://api.cerebras.ai"
           :max-tokens 1024)))
    (is (null (cadr-ai::completions-strict-mode-p unknown)))
    (is (eq t (cadr-ai::completions-strict-mode-p builtin)))
    (is (eq t (cadr-ai::completions-strict-mode-p advertised)))
    (is (null (cadr-ai::completions-strict-mode-p cerebras)))))

(test goal24-cerebras-omits-tool-strict
  (let* ((model
           (cadr-ai:make-model
            :id "gpt-oss-120b"
            :provider :cerebras
            :api :openai-completions
            :base-url "https://api.cerebras.ai/v1"
            :max-tokens 4096
            :supports-tools-p t))
         (tools
           (list
            (cadr-ai:make-tool
             :name "t1"
             :description "strict tool"
             :parameters (sample-schema)
             :constrained-sampling
             '(:type :json-schema :strict :prefer))
            (cadr-ai:make-tool
             :name "t2"
             :description "non-strict tool"
             :parameters (sample-schema))))
         (payload-tools
           (cadr-ai::openai-chat-tools model tools)))
    (is (= 2 (length payload-tools)))
    (loop for tool across payload-tools
          for function = (cadr-ai::json-get tool "function")
          do (is (not (cadr-ai::json-present-p function "strict"))))))

(defun opencode-completion-header (session-id name)
  (cdr
   (assoc
    name
    (request-spec-headers
     (build-request
      (cadr-ai:make-openai-completions-provider :api-key "key")
      (make-model
       :id "test"
       :provider :opencode
       :api :openai-completions
       :base-url "https://opencode.ai/zen/v1"
       :max-tokens 16)
      (sample-context)
      :stream-p t
      :max-tokens 16
      :session-id session-id))
    :test #'string-equal)))

(test opencode-session-header-requires-session-id
  (is (null (opencode-completion-header nil "x-opencode-session")))
  (is (null (opencode-completion-header nil "x-opencode-client")))
  (is (string= "sess-1"
               (opencode-completion-header "sess-1" "x-opencode-session")))
  (is (string= "cadr"
               (opencode-completion-header "sess-1" "x-opencode-client"))))

(defun feed-completions-deltas (model deltas)
  (let* ((provider
           (cadr-ai:make-openai-completions-provider :api-key "test"))
         (state
           (cadr-ai::make-provider-stream-state
            :message (cadr-ai::empty-assistant-message model)
            :model model)))
    (dolist (delta deltas)
      (cadr-ai::reduce-provider-sse-event
       provider state
       (cadr-ai::make-sse-event
        :data
        (cadr-ai::stringify-json
         (cadr-ai::json-object
          "id" "chatcmpl-test"
          "choices"
          (vector
           (cadr-ai::json-object
            "delta" delta
            "finish_reason" 'cadr-ai::null)))))
       (lambda (event) (declare (ignore event)))))
    (cadr-ai::reduce-provider-sse-event
     provider state
     (cadr-ai::make-sse-event
      :data
      (cadr-ai::stringify-json
       (cadr-ai::json-object
        "id" "chatcmpl-test"
        "choices"
        (vector
         (cadr-ai::json-object
          "delta" (cadr-ai::json-object)
          "finish_reason" "stop")))))
     (lambda (event) (declare (ignore event))))
    (cadr-ai::provider-stream-state-message state)))

(defun completions-block-types (message)
  (mapcar
   (lambda (block)
     (cond
       ((typep block 'cadr-ai:thinking-content) :thinking)
       ((typep block 'cadr-ai:text-content) :text)
       ((typep block 'cadr-ai:tool-call) :tool-call)))
   (cadr-ai:assistant-message-content message)))

(defun replay-assistant-payload (model message)
  (let* ((provider
           (cadr-ai:make-openai-completions-provider :api-key "test"))
         (request
           (cadr-ai:build-request
            provider model
            (cadr-ai:make-context
             :messages
             (list
              (cadr-ai:make-user-message :content "continue")
              message))
            :stream-p t
            :max-tokens 64))
         (messages
           (cadr-ai::json-get
            (cadr-ai:request-spec-payload request)
            "messages")))
    (find "assistant" messages
          :key (lambda (item) (cadr-ai::json-get item "role"))
          :test #'string=)))

(test completions-same-delta-puts-thinking-before-text
  ;; pi@71023aec1 openai-completions.ts #10926.
  (let ((model
          (cadr-ai:make-model
           :id "proxy-model"
           :provider :openrouter
           :api :openai-completions
           :base-url "https://openrouter.ai/api/v1"
           :max-tokens 1024
           :reasoning-p t)))
    (let ((message
            (feed-completions-deltas
             model
             (list
              (cadr-ai::json-object
               "reasoning_content" "thinking"
               "content" "answer")))))
      (is (equal '(:thinking :text) (completions-block-types message)))
      (is (string= "thinking"
                   (cadr-ai:thinking-content-thinking
                    (first (cadr-ai:assistant-message-content message)))))
      (is (string= "reasoning_content"
                   (cadr-ai:thinking-content-signature
                    (first (cadr-ai:assistant-message-content message)))))
      (is (string= "answer"
                   (cadr-ai:text-content-text
                    (second (cadr-ai:assistant-message-content message))))))
    (let* ((detail
             (cadr-ai::json-object
              "type" "reasoning.encrypted"
              "id" "call_1"
              "data" "encrypted-signature"))
           (message
             (feed-completions-deltas
              model
              (list
               (cadr-ai::json-object
                "reasoning_details" (vector detail)
                "content" "answer"))))
           (thinking
             (first (cadr-ai:assistant-message-content message))))
      (is (equal '(:thinking :text) (completions-block-types message)))
      (is (string= "answer"
                   (cadr-ai:text-content-text
                    (second (cadr-ai:assistant-message-content message)))))
      (is (string=
           (cadr-ai::stringify-json (vector detail))
           (cadr-ai:thinking-content-signature thinking)))
      (let ((payload (replay-assistant-payload model message)))
        (is (not (cadr-ai::json-present-p payload "reasoning_content")))
        (is (equalp
             (vector detail)
             (cadr-ai::json-get payload "reasoning_details")))))
    (let* ((detail
             (cadr-ai::json-object
              "type" "reasoning.text"
              "text" "I should call the read tool."
              "signature" "sha256:signed-text"))
           (message
             (feed-completions-deltas
              model
              (list
               (cadr-ai::json-object
                "reasoning" "I should call the read tool."
                "reasoning_details" (vector detail)))))
           (thinking
             (first (cadr-ai:assistant-message-content message)))
           (payload (replay-assistant-payload model message)))
      (is (string= "I should call the read tool."
                   (cadr-ai:thinking-content-thinking thinking)))
      (is (string=
           (cadr-ai::stringify-json (vector detail))
           (cadr-ai:thinking-content-signature thinking)))
      (is (not (cadr-ai::json-present-p payload "reasoning")))
      (is (not (cadr-ai::json-present-p payload "reasoning_content")))
      (is (equalp
           (vector detail)
           (cadr-ai::json-get payload "reasoning_details"))))))

(test completions-reasoning-details-merge-and-replay-in-order
  (let* ((model
           (cadr-ai:make-model
            :id "google/gemini-test"
            :provider :openrouter
            :api :openai-completions
            :base-url "https://openrouter.ai/api/v1"
            :max-tokens 1024
            :reasoning-p t))
         (text-delta
           (cadr-ai::json-object
            "type" "reasoning.text" "text" "The" "index" 0))
         (text-rest
           (cadr-ai::json-object
            "type" "reasoning.text"
            "text" " user wants the time."
            "signature" "sha256:text-signature"
            "format" "openai-responses-v1"
            "index" 0))
         (summary-delta
           (cadr-ai::json-object
            "type" "reasoning.summary" "summary" "Looked" "index" 0))
         (summary-rest
           (cadr-ai::json-object
            "type" "reasoning.summary"
            "summary" " up time."
            "format" "openai-responses-v1"
            "index" 0))
         (encrypted
           (cadr-ai::json-object
            "type" "reasoning.encrypted"
            "id" "call_1"
            "data" "encrypted-signature"))
         (later-summary
           (cadr-ai::json-object
            "type" "reasoning.summary"
            "summary" "After encrypted block."
            "format" "openai-responses-v1"
            "index" 0))
         (expected
           (vector
            (cadr-ai::json-object
             "type" "reasoning.text"
             "text" "The user wants the time."
             "index" 0
             "signature" "sha256:text-signature"
             "format" "openai-responses-v1")
            (cadr-ai::json-object
             "type" "reasoning.summary"
             "summary" "Looked up time."
             "index" 0
             "format" "openai-responses-v1")
            encrypted
            later-summary))
         (message
           (feed-completions-deltas
            model
            (list
             (cadr-ai::json-object "reasoning_details" (vector text-delta))
             (cadr-ai::json-object "reasoning_details" (vector text-rest))
             (cadr-ai::json-object "reasoning_details" (vector summary-delta))
             (cadr-ai::json-object "reasoning_details" (vector summary-rest))
             (cadr-ai::json-object "reasoning_details" (vector encrypted))
             (cadr-ai::json-object
              "reasoning_details" (vector later-summary)))))
         (thinking
           (find-if (lambda (block)
                      (typep block 'cadr-ai:thinking-content))
                    (cadr-ai:assistant-message-content message))))
    (is (string= "" (cadr-ai:thinking-content-thinking thinking)))
    (is (string=
         (cadr-ai::stringify-json expected)
         (cadr-ai:thinking-content-signature thinking)))
    (let ((payload (replay-assistant-payload model message)))
      (is (not (cadr-ai::json-present-p payload "reasoning")))
      (is (not (cadr-ai::json-present-p payload "reasoning_content")))
      (is (equalp expected
                  (cadr-ai::json-get payload "reasoning_details"))))))

(test completions-legacy-tool-signature-replays-as-reasoning-details
  (let* ((model
           (cadr-ai:make-model
            :id "google/gemini-test"
            :provider :openrouter
            :api :openai-completions
            :base-url "https://openrouter.ai/api/v1"
            :max-tokens 1024
            :reasoning-p t))
         (detail
           (cadr-ai::json-object
            "type" "reasoning.encrypted"
            "id" "call_1"
            "data" "encrypted-signature"))
         (message
           (cadr-ai:make-assistant-message
            :content
            (list
             (cadr-ai:make-tool-call
              :id "call_1"
              :name "read"
              :arguments (cadr-ai::json-object "path" "README.md")
              :thought-signature (cadr-ai::stringify-json detail)))
            :api :openai-completions
            :provider :openrouter
            :model "google/gemini-test"
            :stop-reason :tool-use))
         (payload (replay-assistant-payload model message)))
    (is (not (cadr-ai::json-present-p payload "reasoning_content")))
    (is (equalp (vector detail)
                (cadr-ai::json-get payload "reasoning_details")))))

(defun xiaomi-catalog-model (provider id)
  (let ((meta (cadr-ai:find-model-metadata provider id)))
    (make-model
     :id id
     :provider provider
     :api (cadr-ai:model-metadata-api meta)
     :base-url (cadr-ai:model-metadata-base-url meta)
     :reasoning-p (cadr-ai:model-metadata-reasoning-p meta)
     :thinking-level-map (cadr-ai:model-metadata-thinking-level-map meta)
     :compat (cadr-ai:model-metadata-compat meta))))

(defun xiaomi-thinking-payload (model reasoning)
  (request-spec-payload
   (build-request
    (cadr-ai:make-openai-completions-provider :api-key "test-xiaomi-key")
    model
    (make-context
     :messages
     (list (make-user-message :content "test" :timestamp 0)))
    :stream-p t
    :reasoning reasoning)))

(test xiaomi-mimo-thinking-is-an-off-on-toggle
  (dolist (provider '(:xiaomi :xiaomi-token-plan-cn
                      :xiaomi-token-plan-ams :xiaomi-token-plan-sgp))
    (let ((models
            (loop for metadata
                  in (cadr-ai:list-model-metadata provider)
                  when (cadr-ai:model-metadata-reasoning-p metadata)
                    collect
                    (xiaomi-catalog-model
                     provider
                     (cadr-ai:model-metadata-id metadata)))))
      (is (not (null models)))
      (dolist (model models)
        (is (equal '(:off :high)
                   (cadr-ai:supported-thinking-levels model)))
        (is (eq :high (cadr-ai:clamp-thinking-level model :minimal)))
        (is (eq :off (cadr-ai:clamp-thinking-level model :off)))
        (let ((enabled (xiaomi-thinking-payload model :high))
              (disabled (xiaomi-thinking-payload model nil)))
          (is (string=
               "enabled"
               (cadr-ai::json-get
                (cadr-ai::json-get enabled "thinking")
                "type")))
          (is (not (cadr-ai::json-present-p enabled "reasoning_effort")))
          (is (string=
               "disabled"
               (cadr-ai::json-get
                (cadr-ai::json-get disabled "thinking")
                "type")))
          (is (not
               (cadr-ai::json-present-p
                disabled "reasoning_effort"))))))))

(defun sampling-close-p (expected actual)
  (and (numberp actual)
       (< (abs (- (coerce expected 'double-float)
                  (coerce actual 'double-float)))
          1d-9)
       t))

(defun sampling-request-payload
    (provider model &key reasoning sampling-params temperature)
  (request-spec-payload
   (build-request
    provider
    model
    (make-context
     :messages
     (list (make-user-message :content "hi" :timestamp 0)))
    :stream-p nil
    :temperature temperature
    :reasoning reasoning
    :sampling-params sampling-params)))

(test sampling-params-follow-the-effective-thinking-level
  ;; pi@71023aec1 simple-options.ts resolveSamplingParams (#9776).
  ;; low is present with a null map value, so the request clamps to
  ;; high. Level params override the model defaults, and request
  ;; params override the level. Named temperature is written first,
  ;; so the merged table replaces it.
  (let* ((clamped
           (make-model
            :id "sample-model"
            :provider :openai
            :api :openai-completions
            :base-url "https://api.openai.com/v1"
            :max-tokens 128
            :reasoning-p t
            :thinking-level-map '((:low) (:medium))
            :sampling-params
            (cadr-ai::json-object
             "temperature" 1
             "top_p" 0.95d0)
            :sampling-params-by-thinking-level
            (list
             (cons :high
                   (cadr-ai::json-object
                    "temperature" 0.8d0
                    "top_k" 64)))))
         (off-model
           (make-model
            :id "off-model"
            :provider :openai
            :api :openai-completions
            :base-url "https://api.openai.com/v1"
            :max-tokens 128
            :reasoning-p nil
            :sampling-params-by-thinking-level
            (list
             (cons :off
                   (cadr-ai::json-object
                    "temperature" 0.7d0)))))
         (override
           (make-model
            :id "override-model"
            :provider :openai
            :api :openai-responses
            :base-url "https://api.openai.com/v1"
            :max-tokens 128
            :reasoning-p t
            :thinking-level-map '((:low . "low"))
            :sampling-params-by-thinking-level
            (list
             (cons :low
                   (cadr-ai::json-object
                    "temperature" 0.6d0
                    "top_p" 0.95d0)))))
         (completions
           (cadr-ai:make-openai-completions-provider
            :api-key "sampling-test"))
         (responses
           (cadr-ai:make-openai-provider
            :api-key "sampling-test"))
         (azure
           (cadr-ai:make-azure-openai-provider
            :api-key "sampling-test"
            :options
            '(:azure-base-url
              "https://example.openai.azure.com/openai/v1")))
         (clamped-payload
           (sampling-request-payload
            completions clamped
            :reasoning :low
            :temperature 0.1d0))
         (off-payload
           (sampling-request-payload completions off-model))
         (responses-payload
           (sampling-request-payload
            responses override
            :reasoning :low
            :sampling-params
            (cadr-ai::json-object "top_p" 0.5d0)))
         (azure-payload
           (sampling-request-payload
            azure
            (cadr-ai::copy-model-with
             override
             :api :openai-responses)
            :reasoning :low
            :sampling-params
            (cadr-ai::json-object "top_p" 0.5d0))))
    (is (eq t
            (sampling-close-p
             0.8d0
             (cadr-ai::json-get clamped-payload "temperature"))))
    (is (eq t
            (sampling-close-p
             0.95d0
             (cadr-ai::json-get clamped-payload "top_p"))))
    (is (= 64
           (cadr-ai::json-get clamped-payload "top_k")))
    (is (eq t
            (sampling-close-p
             0.7d0
             (cadr-ai::json-get off-payload "temperature"))))
    (is (not
         (cadr-ai::json-present-p off-payload "top_p")))
    (is (eq t
            (sampling-close-p
             0.6d0
             (cadr-ai::json-get responses-payload "temperature"))))
    (is (eq t
            (sampling-close-p
             0.5d0
             (cadr-ai::json-get responses-payload "top_p"))))
    (is (eq t
            (sampling-close-p
             0.6d0
             (cadr-ai::json-get azure-payload "temperature"))))
    (is (eq t
            (sampling-close-p
             0.5d0
             (cadr-ai::json-get azure-payload "top_p"))))))
