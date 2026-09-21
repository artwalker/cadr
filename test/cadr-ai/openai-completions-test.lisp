(in-package #:cadr-ai/tests)
(in-suite cadr-ai-suite)

(defun completions-provider-and-model ()
  (values
   (cadr-ai:make-openai-completions-provider :api-key "deepseek-test")
   (cadr-ai:make-model :id "deepseek-flash"
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
                :model "deepseek-flash"
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
