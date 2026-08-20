(in-package #:cadr-ai/tests)
(in-suite cadr-ai-suite)

(test pairing-provider-anthropic-recorded-sse-stays-put
  ;; scripts/goal20-paired-paths.lisp provider_anthropic.stream_roundtrip.
  ;; Drives shipped stream-chat, not a reimplementation. No live socket.
  (multiple-value-bind (provider model)
      (provider-case :anthropic)
    (let ((events nil)
          (*http-request-function*
            (lambda (url &rest arguments)
              (declare (ignore url arguments))
              (values
               (open
                (fixture-path
                 "test/fixtures/goal20-paired-paths/anthropic-messages.sse")
                :direction :input
                :element-type '(unsigned-byte 8))
               200
               '(("content-type" . "text/event-stream"))))))
      (let ((message
              (stream-chat
               provider model (sample-context)
               (lambda (event) (push event events)))))
        (is (eq :tool-use (assistant-message-stop-reason message)))
        (is (= 4096 (usage-input (assistant-message-usage message))))
        (is (= 512 (usage-output (assistant-message-usage message))))
        (is (find-if
             (lambda (block) (typep block 'cadr-ai:tool-call))
             (assistant-message-content message)))))))

(test pairing-provider-google-recorded-sse-stays-put
  ;; scripts/goal20-paired-paths.lisp provider_google.stream_roundtrip.
  ;; Drives shipped stream-chat, not a reimplementation. No live socket.
  ;; gemini-3.6-flash keeps tool-call ids (google-gemini-3-model-p).
  (multiple-value-bind (provider model)
      (provider-case :google)
    (let ((events nil)
          (*http-request-function*
            (lambda (url &rest arguments)
              (declare (ignore url arguments))
              (values
               (open
                (fixture-path
                 "test/fixtures/goal20-paired-paths/google-generative-ai.sse")
                :direction :input
                :element-type '(unsigned-byte 8))
               200
               '(("content-type" . "text/event-stream"))))))
      (let ((message
              (stream-chat
               provider model (sample-context)
               (lambda (event) (push event events)))))
        (is (eq :tool-use (assistant-message-stop-reason message)))
        (is (= 4096 (usage-input (assistant-message-usage message))))
        (is (= 512 (usage-output (assistant-message-usage message))))
        (is (find-if
             (lambda (block) (typep block 'cadr-ai:tool-call))
             (assistant-message-content message)))))))

(test pairing-provider-bedrock-recorded-event-stream-stays-put
  ;; scripts/goal20-paired-paths.lisp provider_bedrock.stream_roundtrip.
  ;; Drives shipped stream-chat, not a reimplementation. No live socket.
  (multiple-value-bind (provider model)
      (provider-case :bedrock)
    (let ((events nil)
          (*http-request-function*
            (lambda (url &rest arguments)
              (declare (ignore url arguments))
              (values
               (open
                (fixture-path
                 "test/fixtures/goal20-paired-paths/bedrock-converse-stream.bin")
                :direction :input
                :element-type '(unsigned-byte 8))
               200
               '(("content-type" . "application/vnd.amazon.eventstream"))))))
      (let ((message
              (stream-chat
               provider model (sample-context)
               (lambda (event) (push event events)))))
        (is (eq :tool-use (assistant-message-stop-reason message)))
        (is (= 4096 (usage-input (assistant-message-usage message))))
        (is (= 512 (usage-output (assistant-message-usage message))))
        (is (find-if
             (lambda (block) (typep block 'cadr-ai:tool-call))
             (assistant-message-content message)))))))

(test pairing-provider-mistral-recorded-sse-stays-put
  ;; scripts/goal20-paired-paths.lisp provider_mistral.stream_roundtrip.
  ;; Drives shipped stream-chat, not a reimplementation. No live socket.
  (multiple-value-bind (provider model)
      (provider-case :mistral)
    (let ((events nil)
          (*http-request-function*
            (lambda (url &rest arguments)
              (declare (ignore url arguments))
              (values
               (open
                (fixture-path
                 "test/fixtures/goal20-paired-paths/mistral-conversations.sse")
                :direction :input
                :element-type '(unsigned-byte 8))
               200
               '(("content-type" . "text/event-stream"))))))
      (let ((message
              (stream-chat
               provider model (sample-context)
               (lambda (event) (push event events)))))
        (is (eq :tool-use (assistant-message-stop-reason message)))
        (is (= 4096 (usage-input (assistant-message-usage message))))
        (is (= 512 (usage-output (assistant-message-usage message))))
        (is (find-if
             (lambda (block) (typep block 'cadr-ai:tool-call))
             (assistant-message-content message)))))))

(test pairing-provider-openai-responses-recorded-sse-stays-put
  ;; scripts/goal20-paired-paths.lisp provider_openai_responses.stream_roundtrip.
  ;; Drives shipped stream-chat, not a reimplementation. No live socket.
  (multiple-value-bind (provider model)
      (provider-case :openai)
    (let ((events nil)
          (*http-request-function*
            (lambda (url &rest arguments)
              (declare (ignore url arguments))
              (values
               (open
                (fixture-path
                 "test/fixtures/goal20-paired-paths/openai-responses.sse")
                :direction :input
                :element-type '(unsigned-byte 8))
               200
               '(("content-type" . "text/event-stream"))))))
      (let ((message
              (stream-chat
               provider model (sample-context)
               (lambda (event) (push event events)))))
        (is (eq :tool-use (assistant-message-stop-reason message)))
        (is (= 4096 (usage-input (assistant-message-usage message))))
        (is (= 512 (usage-output (assistant-message-usage message))))
        (is (find-if
             (lambda (block) (typep block 'cadr-ai:tool-call))
             (assistant-message-content message)))))))

(test pairing-provider-codex-recorded-sse-stays-put
  ;; scripts/goal20-paired-paths.lisp provider_codex.stream_roundtrip.
  ;; Drives shipped stream-chat, not a reimplementation. No live socket.
  ;; :transport :sse skips the Codex websocket probe.
  (multiple-value-bind (provider model)
      (provider-case :codex)
    (let ((events nil)
          (*http-request-function*
            (lambda (url &rest arguments)
              (declare (ignore url arguments))
              (values
               (open
                (fixture-path
                 "test/fixtures/goal20-paired-paths/openai-codex-responses.sse")
                :direction :input
                :element-type '(unsigned-byte 8))
               200
               '(("content-type" . "text/event-stream"))))))
      (let ((message
              (stream-chat
               provider model (sample-context)
               (lambda (event) (push event events))
               :transport :sse)))
        (is (eq :tool-use (assistant-message-stop-reason message)))
        (is (= 4096 (usage-input (assistant-message-usage message))))
        (is (= 512 (usage-output (assistant-message-usage message))))
        (is (find-if
             (lambda (block) (typep block 'cadr-ai:tool-call))
             (assistant-message-content message)))))))

(test pairing-provider-vertex-recorded-sse-stays-put
  ;; scripts/goal20-paired-paths.lisp provider_vertex.stream_roundtrip.
  ;; Drives shipped stream-chat, not a reimplementation. No live socket.
  ;; gemini-3.6-flash keeps tool-call ids (google-gemini-3-model-p).
  (multiple-value-bind (provider model)
      (provider-case :vertex)
    (let ((events nil)
          (*http-request-function*
            (lambda (url &rest arguments)
              (declare (ignore url arguments))
              (values
               (open
                (fixture-path
                 "test/fixtures/goal20-paired-paths/google-vertex.sse")
                :direction :input
                :element-type '(unsigned-byte 8))
               200
               '(("content-type" . "text/event-stream"))))))
      (let ((message
              (stream-chat
               provider model (sample-context)
               (lambda (event) (push event events)))))
        (is (eq :tool-use (assistant-message-stop-reason message)))
        (is (= 4096 (usage-input (assistant-message-usage message))))
        (is (= 512 (usage-output (assistant-message-usage message))))
        (is (find-if
             (lambda (block) (typep block 'cadr-ai:tool-call))
             (assistant-message-content message)))))))

(test pairing-provider-vertex-adc-fixture-stays-put
  ;; Inventory fixture for provider_vertex: ADC JSON is parsed by the
  ;; shipped reader. Token exchange stays off the wire.
  (let ((credential
          (cadr-ai::read-google-application-credential
           (fixture-path
            "test/fixtures/goal20-paired-paths/vertex-adc.json"))))
    (is (string= "authorized_user"
                 (cadr-ai::json-get credential "type")))
    (is (string= "goal20-vertex-project"
                 (cadr-ai::json-get credential "quota_project_id")))
    (let ((spec
            (cadr-ai::make-vertex-token-request credential :issued-at 0)))
      (is (search "oauth2.googleapis.com/token" (request-spec-url spec))))))

(test pairing-provider-azure-openai-recorded-sse-stays-put
  ;; scripts/goal20-paired-paths.lisp provider_azure_openai.stream_roundtrip.
  ;; Drives shipped stream-chat, not a reimplementation. No live socket.
  (multiple-value-bind (provider model)
      (provider-case :azure)
    (let ((events nil)
          (*http-request-function*
            (lambda (url &rest arguments)
              (declare (ignore url arguments))
              (values
               (open
                (fixture-path
                 "test/fixtures/goal20-paired-paths/azure-openai-responses.sse")
                :direction :input
                :element-type '(unsigned-byte 8))
               200
               '(("content-type" . "text/event-stream"))))))
      (let ((message
              (stream-chat
               provider model (sample-context)
               (lambda (event) (push event events)))))
        (is (eq :tool-use (assistant-message-stop-reason message)))
        (is (= 4096 (usage-input (assistant-message-usage message))))
        (is (= 512 (usage-output (assistant-message-usage message))))
        (is (find-if
             (lambda (block) (typep block 'cadr-ai:tool-call))
             (assistant-message-content message)))))))

(test pairing-provider-pi-messages-recorded-sse-stays-put
  ;; scripts/goal20-paired-paths.lisp provider_pi_messages.stream_roundtrip.
  ;; Drives shipped stream-chat, not a reimplementation. No live socket.
  (multiple-value-bind (provider model)
      (provider-case :pi-messages)
    (let ((events nil)
          (*http-request-function*
            (lambda (url &rest arguments)
              (declare (ignore url arguments))
              (values
               (open
                (fixture-path
                 "test/fixtures/goal20-paired-paths/pi-messages.sse")
                :direction :input
                :element-type '(unsigned-byte 8))
               200
               '(("content-type" . "text/event-stream"))))))
      (let ((message
              (stream-chat
               provider model (sample-context)
               (lambda (event) (push event events)))))
        (is (eq :tool-use (assistant-message-stop-reason message)))
        (is (= 4096 (usage-input (assistant-message-usage message))))
        (is (= 512 (usage-output (assistant-message-usage message))))
        (is (find-if
             (lambda (block) (typep block 'cadr-ai:tool-call))
             (assistant-message-content message)))))))

(test recorded-sse-fixtures-normalize-events-and-final-message
  (dolist (provider-name '(:anthropic :openai :google))
    (multiple-value-bind (provider model)
        (provider-case provider-name)
      (let ((events nil))
        (let ((*http-request-function*
                (lambda (url &rest arguments)
                  (declare (ignore url arguments))
                  (values
                   (open (fixture-path
                          (format nil
                                  "test/fixtures/sse/~(~A~)-tool.sse"
                                  provider-name))
                         :direction :input
                         :element-type '(unsigned-byte 8))
                   200
                   '(("content-type" . "text/event-stream"))))))
        (let ((message (stream-chat
                        provider model (sample-context)
                        (lambda (event) (push event events))
                        :max-tokens 4096)))
          (setf events (nreverse events))
          (is (eq :tool-use (assistant-message-stop-reason message)))
          (is (= (ecase provider-name
                   (:anthropic 677)
                   (:openai 79)
                   (:google 188))
                 (usage-total (assistant-message-usage message))))
          (is (member :tool-call-start (collect-event-types events)))
          (is (member :tool-call-delta (collect-event-types events)))
          (is (member :tool-call-end (collect-event-types events)))
          (is (eq :done (stream-event-type (car (last events)))))
          (is (eq :tool-use
                  (stream-event-reason (car (last events)))))))))))

(test stream-ending-without-provider-terminal-event-is-an-error
  (multiple-value-bind (provider model)
      (provider-case :openai)
    (let ((events nil))
      (let ((*http-request-function*
              (lambda (url &rest arguments)
                (declare (ignore url arguments))
                (values
                 (make-string-input-stream
                  (format nil
                          "data: {\"type\":\"response.created\",\"response\":{\"id\":\"resp_early\"}}~%~%"))
                 200
                 '(("content-type" . "text/event-stream"))))))
      (let ((message (stream-chat provider model (sample-context)
                                  (lambda (event) (push event events)))))
        (is (eq :error (assistant-message-stop-reason message)))
        (is (search "terminal"
                    (assistant-message-error-message message)))
        (is (eq :error (stream-event-type (first events)))))))))

(test stream-abort-preserves-partial-content-and-terminates
  (multiple-value-bind (provider model)
      (provider-case :openai)
    (let ((events nil)
          (abort-p nil))
      (let ((*http-request-function*
              (lambda (url &rest arguments)
                (declare (ignore url arguments))
                (values
                 (make-string-input-stream
                  (format
                   nil
                   "data: {\"type\":\"response.created\",\"response\":{\"id\":\"resp_abort\"}}~%~%data: {\"type\":\"response.output_item.added\",\"output_index\":0,\"item\":{\"type\":\"message\",\"id\":\"msg_abort\",\"role\":\"assistant\",\"content\":[]}}~%~%data: {\"type\":\"response.output_text.delta\",\"output_index\":0,\"delta\":\"partial\"}~%~%data: {\"type\":\"response.output_text.delta\",\"output_index\":0,\"delta\":\" ignored\"}~%~%data: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp_abort\",\"status\":\"completed\",\"usage\":{\"input_tokens\":1,\"output_tokens\":2,\"total_tokens\":3}}}~%~%"))
                 200
                 '(("content-type" . "text/event-stream"))))))
        (let ((message
                (stream-chat
                 provider model (sample-context)
                 (lambda (event)
                   (push event events)
                   (when (eq :text-delta (stream-event-type event))
                     (setf abort-p t)))
                 :abort-p (lambda () abort-p))))
          (setf events (nreverse events))
          (is (eq :aborted (assistant-message-stop-reason message)))
          (is (string= "partial" (first-text message)))
          (is (eq :error (stream-event-type (car (last events)))))
          (is (eq :aborted
                  (stream-event-reason (car (last events))))))))))

(test stream-request-lifecycle-callbacks-cover-payload-headers-and-response
  (multiple-value-bind (provider model)
      (provider-case :openai)
    (let ((payload-seen-p nil)
          (headers-seen nil)
          (response-seen nil))
      (let ((*http-request-function*
              (lambda (url &rest arguments)
                (declare (ignore url))
                (setf headers-seen
                      (copy-tree
                       (getf arguments :headers)))
                (values
                 (open
                  (fixture-path
                   "test/fixtures/sse/openai-tool.sse")
                  :direction :input
                  :element-type '(unsigned-byte 8))
                 200
                 '(("X-Provider" . "ok"))))))
        (let ((message
                (stream-chat
                 provider model (sample-context)
                 (lambda (event)
                   (declare (ignore event)))
                 :on-payload
                 (lambda (payload callback-model)
                   (is (eq model callback-model))
                   (setf payload-seen-p t)
                   (cadr-ai::json-put
                    payload "metadata"
                    (cadr-ai::json-object
                     "trace" "payload"))
                   payload)
                 :transform-headers
                 (lambda (headers)
                   (append headers
                           '(("X-Trace" . "headers"))))
                 :on-response
                 (lambda (response callback-model)
                   (is (eq model callback-model))
                   (setf response-seen response)))))
          (is (not (null payload-seen-p)))
          (is (string=
               "headers"
               (cdr
                (assoc "X-Trace" headers-seen
                       :test #'string-equal))))
          (is (= 200
                 (getf response-seen :status)))
          (is (string=
               "ok"
               (cdr
                (assoc "X-Provider"
                       (getf response-seen :headers)
                       :test #'string-equal))))
          (is (eq :tool-use
                  (assistant-message-stop-reason
                  message))))))))

(test openai-responses-reasoning-summary-parts-emit-exact-thinking-events
  (multiple-value-bind (provider ignored-model)
      (provider-case :openai)
    (declare (ignore ignored-model))
    (let* ((model
             (cadr-ai:make-model
              :id "gpt-reasoning"
              :provider :openai-codex
              :api :openai-codex-responses
              :base-url "https://chatgpt.com/backend-api"
              :max-tokens 4096
              :reasoning-p t))
           (events nil)
           (*http-request-function*
             (lambda (url &rest arguments)
               (declare (ignore url arguments))
               (values
                (make-string-input-stream
                 (format
                  nil
                  "data: {\"type\":\"response.created\",\"response\":{\"id\":\"resp_reasoning\"}}~%~%data: {\"type\":\"response.output_item.added\",\"output_index\":0,\"item\":{\"type\":\"reasoning\",\"id\":\"rs_1\",\"summary\":[]}}~%~%data: {\"type\":\"response.reasoning_summary_text.delta\",\"output_index\":0,\"delta\":\"Planning exact output\"}~%~%data: {\"type\":\"response.reasoning_summary_part.done\",\"output_index\":0,\"summary_index\":0,\"part\":{\"type\":\"summary_text\",\"text\":\"Planning exact output\"}}~%~%data: {\"type\":\"response.reasoning_summary_text.delta\",\"output_index\":0,\"delta\":\"Checking 12 steps\"}~%~%data: {\"type\":\"response.output_item.done\",\"output_index\":0,\"item\":{\"type\":\"reasoning\",\"id\":\"rs_1\",\"summary\":[{\"type\":\"summary_text\",\"text\":\"Planning exact output\"},{\"type\":\"summary_text\",\"text\":\"Checking 12 steps\"}]}}~%~%data: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp_reasoning\",\"status\":\"completed\",\"usage\":{\"input_tokens\":1,\"output_tokens\":2,\"total_tokens\":3}}}~%~%"))
                200
                '(("content-type" . "text/event-stream"))))))
      (let* ((message
               (cadr-ai:stream-chat
                provider model (sample-context)
                (lambda (event)
                  (push event events))
                :reasoning :high))
             (thinking
               (find-if
                (lambda (block)
                  (typep block 'cadr-ai:thinking-content))
                (cadr-ai:assistant-message-content message)))
             (thinking-events
               (remove-if-not
                (lambda (event)
                  (member
                   (cadr-ai:stream-event-type event)
                   '(:thinking-start :thinking-delta :thinking-end)))
                (nreverse events))))
        (is (string=
             (format nil "Planning exact output~%~%Checking 12 steps")
             (cadr-ai:thinking-content-thinking thinking)))
        (is (equal
             '(:thinking-start :thinking-delta :thinking-delta
               :thinking-delta :thinking-end)
             (mapcar #'cadr-ai:stream-event-type thinking-events)))
        (is (string=
             (format nil "Planning exact output~%~%Checking 12 steps")
             (format
              nil "~{~A~}"
              (loop for event in thinking-events
                    when (eq :thinking-delta
                             (cadr-ai:stream-event-type event))
                    collect (cadr-ai:stream-event-delta event)))))
        (is (string=
             (format nil "~%~%")
             (cadr-ai:stream-event-delta
              (third thinking-events))))))))

(defparameter *thinking-matrix-levels*
  '(:off :minimal :low :medium :high :xhigh :max))

(defun thinking-matrix-provider-model
    (provider-id model-id requested-level)
  (cadr-ai:instantiate-provider
   provider-id
   :api-key "fixture-key"
   :oauth-access-token "fixture-oauth"
   :oauth-account-id "fixture-account"
   :base-url "https://fixture.invalid/v1"
   :model-id model-id
   :reasoning requested-level
   :allow-missing-auth-p t
   :options
   '(:cloudflare-account-id "fixture-account"
     :cloudflare-gateway-id "fixture-gateway"
     :azure-base-url "https://fixture.invalid/v1"
     :region "us-east-1"
     :project "fixture-project"
     :location "us-central1"
     :environment (("AWS_REGION" . "us-east-1")))))

(defun thinking-matrix-json-value (object &rest path)
  (loop with value = object
        for key in path
        do (setf value
                 (and (hash-table-p value)
                      (cadr-ai::json-get value key)))
        finally (return value)))

(defun thinking-matrix-payload-state (api payload)
  (case api
    ((:anthropic-messages)
     (let ((thinking (cadr-ai::json-get payload "thinking")))
       (cond
         ((not (hash-table-p thinking)) :absent)
         ((string= "disabled"
                   (cadr-ai::json-get thinking "type"))
          :off)
         (t :on))))
    ((:openai-responses :openai-codex-responses
      :azure-openai-responses)
     (let ((reasoning (cadr-ai::json-get payload "reasoning")))
       (cond
         ((not (hash-table-p reasoning)) :absent)
         ((string= "none"
                   (cadr-ai::json-get reasoning "effort"))
          :off)
         (t :on))))
    ((:google-generative-ai)
     (let ((thinking
             (cadr-ai::json-get payload "thinkingConfig")))
       (cond
         ((not (hash-table-p thinking)) :absent)
         ((eql 0 (cadr-ai::json-get thinking "thinkingBudget"))
          :off)
         (t :on))))
    ((:google-vertex)
     (let ((thinking (cadr-ai::json-get payload "thinkingConfig")))
       (cond
         ((not (hash-table-p thinking)) :absent)
         ((eql 0 (cadr-ai::json-get thinking "thinkingBudget"))
          :off)
         (t :on))))
    ((:bedrock-converse-stream)
     (if (hash-table-p
          (cadr-ai::json-get payload
                             "additionalModelRequestFields"))
         :on
         :absent))
    ((:mistral-conversations)
     (if (or (cadr-ai::json-present-p payload "reasoning_effort")
             (cadr-ai::json-present-p payload "prompt_mode"))
         :on
         :absent))
    ((:pi-messages)
     (if (cadr-ai::json-present-p
          (cadr-ai::json-get payload "options") "reasoning")
         :on
         :absent))
    ((:openai-completions)
     (let ((enable-present-p
             (cadr-ai::json-present-p payload "enable_thinking"))
           (enable (cadr-ai::json-get payload "enable_thinking"))
           (effort (cadr-ai::json-get payload "reasoning_effort"))
           (reasoning (cadr-ai::json-get payload "reasoning"))
           (thinking (cadr-ai::json-get payload "thinking")))
       (cond
         ((and enable-present-p (not enable)) :off)
         ((eq t enable) :on)
         ((stringp effort)
          (if (member effort '("none" "off" "disabled")
                      :test #'string-equal)
              :off
              :on))
         ((hash-table-p reasoning)
          (let ((nested-effort
                  (cadr-ai::json-get reasoning "effort")))
            (cond
              ((and (cadr-ai::json-present-p reasoning "enabled")
                    (not (cadr-ai::json-get reasoning "enabled")))
               :off)
              ((and (stringp nested-effort)
                    (member nested-effort
                            '("none" "off" "disabled")
                            :test #'string-equal))
               :off)
              ((or (eq t (cadr-ai::json-get reasoning "enabled"))
                   (cadr-ai::json-present-p reasoning "effort"))
               :on)
              (t :absent))))
         ((hash-table-p thinking)
          (if (string= "disabled"
                       (or (cadr-ai::json-get thinking "type") ""))
              :off
              :on))
         ((stringp thinking)
          (if (member thinking '("none" "off" "disabled")
                      :test #'string-equal)
              :off
              :on))
         (t :absent))))
    (otherwise
     (error "Unhandled thinking-matrix API: ~A" api))))

(defun thinking-matrix-baseline-completions-state (model reasoning)
  (let ((format (cadr-ai::completions-thinking-format model)))
    (if reasoning
        (case format
          (:ant-ling
           (if (stringp
                (cadr-ai::model-thinking-level-value
                 model reasoning))
               :on
               :absent))
          ((:zai :qwen :qwen-chat-template :chat-template :deepseek
            :openrouter :together :string-thinking)
           :on)
          (otherwise
           (if (cadr-ai::completions-supports-reasoning-effort-p
                model)
               :on
               :absent)))
        (case format
          ((:zai :qwen :qwen-chat-template :chat-template :together)
           :off)
          ((:deepseek :openrouter)
           (if (and
                (cadr-ai::model-thinking-level-present-p model :off)
                (null
                 (cadr-ai::model-thinking-level-value model :off)))
               :absent
               :off))
          (:string-thinking
           (if (stringp
                (cadr-ai::model-thinking-level-value model :off))
               :off
               :absent))
          (otherwise
           (if (and
                (cadr-ai::completions-supports-reasoning-effort-p
                 model)
                (stringp
                 (cadr-ai::model-thinking-level-value model :off)))
               :off
               :absent))))))

(defun thinking-matrix-baseline-payload-state (model reasoning)
  (let ((api (cadr-ai:model-api model)))
    (unless (cadr-ai:model-reasoning-p model)
      (return-from thinking-matrix-baseline-payload-state :absent))
    (case api
      (:anthropic-messages
       (if reasoning
           :on
           (if (and
                (cadr-ai::model-thinking-level-present-p model :off)
                (null
                 (cadr-ai::model-thinking-level-value model :off)))
               :absent
               :off)))
      ((:openai-responses :azure-openai-responses)
       (if reasoning
           :on
           (if (or
                (eq :github-copilot (cadr-ai:model-provider model))
                (and
                 (cadr-ai::model-thinking-level-present-p model :off)
                 (null
                  (cadr-ai::model-thinking-level-value model :off))))
               :absent
               :off)))
      (:openai-codex-responses
       (if reasoning :on :absent))
      ((:google-generative-ai :google-vertex)
       (if reasoning
           :on
           (if (or
                (cadr-ai::google-gemini-3-pro-p model)
                (cadr-ai::google-gemini-3-flash-p model)
                (cadr-ai::google-gemma-4-p model))
               :on
               :off)))
      (:bedrock-converse-stream
       (if (and reasoning
                (cadr-ai::bedrock-claude-model-p model))
           :on
           :absent))
      (:mistral-conversations
       (if reasoning :on :absent))
      (:pi-messages
       (if reasoning :on :absent))
      (:openai-completions
       (thinking-matrix-baseline-completions-state model reasoning))
      (otherwise
       (error "Unhandled thinking-matrix API: ~A" api)))))

(defun thinking-matrix-event-data (api thinking-p)
  (case api
    ((:anthropic-messages)
     (if thinking-p
         '("{\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"thinking\"}}"
           "{\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"thinking_delta\",\"thinking\":\"matrix thought\"}}"
           "{\"type\":\"content_block_stop\",\"index\":0}")
         nil))
    ((:openai-responses :openai-codex-responses
      :azure-openai-responses)
     (if thinking-p
         '("{\"type\":\"response.output_item.added\",\"output_index\":0,\"item\":{\"type\":\"reasoning\",\"id\":\"rs_matrix\",\"summary\":[]}}"
           "{\"type\":\"response.reasoning_summary_text.delta\",\"output_index\":0,\"delta\":\"matrix thought\"}"
           "{\"type\":\"response.output_item.done\",\"output_index\":0,\"item\":{\"type\":\"reasoning\",\"id\":\"rs_matrix\",\"summary\":[{\"type\":\"summary_text\",\"text\":\"matrix thought\"}]}}")
         nil))
    ((:openai-completions :mistral-conversations)
     (if thinking-p
         '("{\"id\":\"chat_matrix\",\"choices\":[{\"delta\":{\"reasoning_content\":\"matrix thought\"},\"finish_reason\":null}]}"
           "{\"id\":\"chat_matrix\",\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}")
         nil))
    ((:google-generative-ai :google-vertex)
     (if thinking-p
         '("{\"candidates\":[{\"content\":{\"parts\":[{\"thought\":true,\"text\":\"matrix thought\"}]}}]}"
           "{\"candidates\":[{\"content\":{\"parts\":[]},\"finishReason\":\"STOP\"}]}")
         nil))
    ((:bedrock-converse-stream)
     (if thinking-p
         '("{\"contentBlockDelta\":{\"contentBlockIndex\":0,\"delta\":{\"reasoningContent\":{\"text\":\"matrix thought\"}}}}"
           "{\"contentBlockDelta\":{\"contentBlockIndex\":1,\"delta\":{\"text\":\"answer\"}}}"
           "{\"messageStop\":{\"stopReason\":\"end_turn\"}}")
         nil))
    ((:pi-messages)
     (if thinking-p
         '("{\"type\":\"thinking_start\",\"contentIndex\":0}"
           "{\"type\":\"thinking_delta\",\"contentIndex\":0,\"delta\":\"matrix thought\"}"
           "{\"type\":\"thinking_end\",\"contentIndex\":0}")
         nil))
    (otherwise
     (error "Unhandled thinking-matrix API: ~A" api))))

(defun thinking-matrix-event-types (provider model thinking-p)
  (let ((events nil)
        (state
          (cadr-ai::make-provider-stream-state
           :message (cadr-ai::empty-assistant-message model))))
    (dolist (data
             (thinking-matrix-event-data
              (cadr-ai:model-api model) thinking-p))
      (cadr-ai::reduce-provider-sse-event
       provider state
       (cadr-ai::make-sse-event :data data)
       (lambda (event) (push event events))))
    (mapcar #'cadr-ai:stream-event-type
            (remove-if-not
             (lambda (event)
               (member (cadr-ai:stream-event-type event)
                       '(:thinking-start :thinking-delta :thinking-end)))
             (nreverse events)))))

(test every-built-in-provider-and-api-has-thinking-level-hit-miss-contract
  (dolist (definition (cadr-ai:list-provider-definitions))
    (let* ((provider-id
             (cadr-ai:provider-definition-id definition))
           (default-model-id
             (cadr-ai:provider-definition-default-model definition))
           (catalog-hit
             (ignore-errors
               (cadr-ai:find-model-metadata
                provider-id default-model-id)))
           (model-cases
             (append
              (when catalog-hit
                (list (cons :hit default-model-id)))
              (list
               (cons :miss
                     (format nil "matrix-unknown-~(~A~)"
                             provider-id))))))
      (when (eq provider-id :radius)
        (is (null catalog-hit)
            "Radius is dynamic and intentionally has no static hit"))
      (dolist (model-case model-cases)
        (dolist (level *thinking-matrix-levels*)
          (multiple-value-bind (provider model)
              (thinking-matrix-provider-model
               provider-id (cdr model-case) level)
            (let* ((effective-level
                     (cadr-ai:clamp-thinking-level model level))
                   (reasoning
                     (unless (eq effective-level :off)
                       effective-level))
                   (expected-payload-state
                     (thinking-matrix-baseline-payload-state
                      model reasoning))
                   (expected-thinking-events-p
                     (and reasoning
                          (cadr-ai:model-reasoning-p model)))
                   (request
                     (cadr-ai:build-request
                      provider model (sample-context)
                      :stream-p t
                      :reasoning reasoning))
                   (payload-state
                     (thinking-matrix-payload-state
                      (cadr-ai:model-api model)
                      (cadr-ai:request-spec-payload request)))
                   (label
                     (format nil "~A/~A/~A/~A"
                             provider-id (car model-case)
                             (cadr-ai:model-api model) level)))
                (is (eq expected-payload-state payload-state)
                    "~A request thinking state differs: expected ~A, got ~A"
                    label expected-payload-state payload-state)
                (is
                 (equal
                  (if expected-thinking-events-p
                      '(:thinking-start :thinking-delta :thinking-end)
                      nil)
                  (thinking-matrix-event-types
                   provider model expected-thinking-events-p))
                 "~A thinking event sequence differs" label))))))))
