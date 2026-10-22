(in-package #:cadr-ai/tests)
(in-suite cadr-ai-suite)

(defun history-request (provider-name messages)
  (multiple-value-bind (provider model)
      (provider-case provider-name)
    (build-request
     provider
     model
     (make-context :messages messages)
     :stream-p t
     :max-tokens 4096)))

(defun object-with-key (objects key)
  (find-if (lambda (object)
             (cadr-ai::json-present-p object key))
           (coerce objects 'list)))

(defun safe-provider-id-p (id)
  (and (<= (length id) 64)
       (every (lambda (character)
                (or (alphanumericp character)
                    (char= character #\_)
                    (char= character #\-)))
              id)))

(defun orphaned-tool-history ()
  (list
   (cadr-ai:make-user-message :content "Use the tool.")
   (cadr-ai:make-assistant-message
    :api :openai-responses
    :provider :openai
    :model "foreign-model"
    :stop-reason :tool-use
    :content
    (list
     (cadr-ai:make-tool-call
      :id "call.bad|fc.bad?"
      :name "read"
      :arguments (cadr-ai::json-object "path" "README.md")
      :thought-signature "foreign-signature")))
   (cadr-ai:make-user-message :content "Never mind.")))

(defun blank-tool-history (api provider model-id text)
  (list
   (cadr-ai:make-user-message :content "Run it.")
   (cadr-ai:make-assistant-message
    :api api
    :provider provider
    :model model-id
    :stop-reason :tool-use
    :content
    (list
     (cadr-ai:make-tool-call
      :id "call-1"
      :name "bash"
      :arguments (cadr-ai::json-object "command" "true"))))
   (cadr-ai:make-tool-result-message
    :tool-call-id "call-1"
    :tool-name "bash"
    :content
    (list (cadr-ai:make-text-content :text text)))))

(defun responses-tool-output (payload)
  (cadr-ai::json-get
   (object-with-key (cadr-ai::json-get payload "input") "output")
   "output"))

(defun completions-tool-content (model-id messages)
  (let ((encoded
          (cadr-ai::openai-chat-messages
           (cadr-ai:make-model
            :id model-id
            :provider :openai
            :api :openai-completions
            :base-url "https://api.openai.com"
            :max-tokens 16)
           (make-context :messages messages))))
    (cadr-ai::json-get
     (find-if
      (lambda (message)
        (string= "tool" (cadr-ai::json-get message "role")))
      (coerce encoded 'list))
     "content")))

(defun google-function-responses (payload)
  (loop for content across (cadr-ai::json-get payload "contents")
        nconc
        (loop for part across (cadr-ai::json-get content "parts")
              when (cadr-ai::json-present-p part "functionResponse")
                collect
                (cadr-ai::json-get
                 (cadr-ai::json-get part "functionResponse")
                 "response"))))

(defun image-capable-history-request (provider-name messages)
  (multiple-value-bind (provider model)
      (provider-case provider-name)
    (setf (cadr-ai:model-supports-images-p model) t)
    (build-request
     provider
     model
     (make-context :messages messages)
     :stream-p t
     :max-tokens 4096)))

(defun javascript-trim-only-samples ()
  ;; pi@4a080252f hasText is textResult.trim().length > 0.
  ;; Node String.prototype.trim on these code points is empty.
  ;; U+200B is not WhiteSpace and stays visible text.
  (list (string (code-char #x000B))
        (string (code-char #x000C))
        (string (code-char #x00A0))
        (string (code-char #xFEFF))
        (string (code-char #x2028))
        (string (code-char #x2029))
        (string (code-char #x1680))
        (string (code-char #x3000))
        (format nil "~C~C~C"
                (code-char #x000B)
                (code-char #x2003)
                (code-char #x202F))))

(test whitespace-only-tool-output-uses-the-empty-placeholder
  ;; pi@4a080252f #8720. A bare CR LF is not tool output.
  (dolist (text (list ""
                      (format nil "~C~C" #\Return #\Newline)
                      (format nil " ~C~C" #\Newline #\Tab)))
    (let* ((openai
             (request-spec-payload
              (history-request
               :openai
               (blank-tool-history
                :openai-responses :openai "gpt-test" text))))
           (output
             (object-with-key
              (cadr-ai::json-get openai "input") "output")))
      (is (string= "(no tool output)"
                   (cadr-ai::json-get output "output"))))
    (let* ((messages
             (cadr-ai::openai-chat-messages
              (cadr-ai:make-model
               :id "gpt-test"
               :provider :openai
               :api :openai-completions
               :base-url "https://api.openai.com"
               :max-tokens 16)
              (make-context
               :messages
               (blank-tool-history
                :openai-completions :openai "gpt-test" text))))
           (tool
             (find-if
              (lambda (message)
                (string= "tool"
                         (cadr-ai::json-get message "role")))
              (coerce messages 'list))))
      (is (string= "(no tool output)"
                   (cadr-ai::json-get tool "content"))))
    (let* ((google
             (request-spec-payload
              (history-request
               :google
               (blank-tool-history
                :google-generative-ai :google
                "gemini-3.6-flash" text))))
           (contents (cadr-ai::json-get google "contents"))
           (part
             (object-with-key
              (cadr-ai::json-get (aref contents 2) "parts")
              "functionResponse"))
           (response
             (cadr-ai::json-get
              (cadr-ai::json-get part "functionResponse")
              "response")))
      (is (string= ""
                   (cadr-ai::json-get response "output"))))))

(test javascript-trim-whitespace-is-empty-tool-output
  ;; pi@4a080252f google-shared.ts, openai-responses-shared.ts,
  ;; openai-completions.ts. hasText is textResult.trim().length > 0.
  (dolist (text (javascript-trim-only-samples))
    (let ((history
            (blank-tool-history
             :openai-responses :openai "gpt-test" text)))
      (is (string= "(no tool output)"
                   (responses-tool-output
                    (request-spec-payload
                     (history-request :openai history)))))
      (is (string= "(no tool output)"
                   (completions-tool-content "gpt-test" history))))
    (let* ((google
             (request-spec-payload
              (history-request
               :google
               (blank-tool-history
                :google-generative-ai :google
                "gemini-3.6-flash" text))))
           (response (first (google-function-responses google))))
      (is (= 1 (hash-table-count response)))
      (is (string= "" (cadr-ai::json-get response "output"))))
    (let* ((vertex
             (request-spec-payload
              (history-request
               :vertex
               (blank-tool-history
                :google-vertex :google-vertex
                "gemini-3.6-flash" text))))
           (response (first (google-function-responses vertex))))
      (is (= 1 (hash-table-count response)))
      (is (string= "" (cadr-ai::json-get response "output")))))
  (let* ((visible
           (format nil "~Cbeta text~C"
                   (code-char #x00A0)
                   (code-char #x000B)))
         (kept (string (code-char #x200B)))
         (history
           (blank-tool-history
            :openai-responses :openai "gpt-test" visible)))
    (is (string= visible
                 (responses-tool-output
                  (request-spec-payload
                   (history-request :openai history)))))
    (is (string= visible
                 (completions-tool-content "gpt-test" history)))
    (is (string= kept
                 (responses-tool-output
                  (request-spec-payload
                   (history-request
                    :openai
                    (blank-tool-history
                     :openai-responses :openai "gpt-test" kept))))))
    (is (string= kept
                 (completions-tool-content
                  "gpt-test"
                  (blank-tool-history
                   :openai-completions :openai "gpt-test" kept))))
    (dolist (provider-name '(:google :vertex))
      (let* ((api (if (eq provider-name :google)
                      :google-generative-ai
                      :google-vertex))
             (provider (if (eq provider-name :google)
                           :google
                           :google-vertex))
             (response
               (first
                (google-function-responses
                 (request-spec-payload
                  (history-request
                   provider-name
                   (blank-tool-history
                    api provider "gemini-3.6-flash" visible)))))))
        (is (string= visible
                     (cadr-ai::json-get response "output")))))))

(test whitespace-only-image-tool-result-uses-attached-image-placeholder
  ;; pi@4a080252f google-shared-image-tool-result-routing.test.ts
  ;; "treats whitespace-only tool result text as no text".
  ;; Success is output, failure is error, and the value is the same.
  (let* ((space-newline (format nil " ~C" #\Newline))
         (history
           (list
            (cadr-ai:make-user-message :content "read the files")
            (cadr-ai:make-assistant-message
             :api :google-generative-ai
             :provider :google
             :model "gemini-3-pro-preview"
             :stop-reason :tool-use
             :content
             (list
              (cadr-ai:make-tool-call
               :id "call_a" :name "read"
               :arguments (cadr-ai::json-object "path" "a.txt"))
              (cadr-ai:make-tool-call
               :id "call_img" :name "read"
               :arguments (cadr-ai::json-object "path" "image.png"))
              (cadr-ai:make-tool-call
               :id "call_b" :name "read"
               :arguments (cadr-ai::json-object "path" "b.txt"))))
            (cadr-ai:make-tool-result-message
             :tool-call-id "call_a" :tool-name "read"
             :content
             (list (cadr-ai:make-text-content
                    :text (format nil "~C~C" #\Return #\Newline))))
            (cadr-ai:make-tool-result-message
             :tool-call-id "call_img" :tool-name "read"
             :content
             (list (cadr-ai:make-text-content :text space-newline)
                   (cadr-ai:make-image-content
                    :data "abc" :mime-type "image/png")))
            (cadr-ai:make-tool-result-message
             :tool-call-id "call_b" :tool-name "read"
             :content
             (list (cadr-ai:make-text-content :text "beta text")))))
         (responses
           (google-function-responses
            (request-spec-payload
             (image-capable-history-request :google history)))))
    (is (= 3 (length responses)))
    (is (string= "" (cadr-ai::json-get (first responses) "output")))
    (is (string= "(see attached image)"
                 (cadr-ai::json-get (second responses) "output")))
    (is (string= "beta text"
                 (cadr-ai::json-get (third responses) "output"))))
  (let* ((history
           (list
            (cadr-ai:make-user-message :content "read the files")
            (cadr-ai:make-assistant-message
             :api :google-vertex
             :provider :google-vertex
             :model "gemini-3-pro-preview"
             :stop-reason :tool-use
             :content
             (list
              (cadr-ai:make-tool-call
               :id "call_err" :name "read"
               :arguments (cadr-ai::json-object "path" "image.png"))))
            (cadr-ai:make-tool-result-message
             :tool-call-id "call_err" :tool-name "read"
             :is-error t
             :content
             (list (cadr-ai:make-text-content
                    :text (string (code-char #x00A0)))
                   (cadr-ai:make-image-content
                    :data "abc" :mime-type "image/png")))))
         (google
           (first
            (google-function-responses
             (request-spec-payload
              (image-capable-history-request :google history)))))
         (vertex
           (first
            (google-function-responses
             (request-spec-payload
              (image-capable-history-request :vertex history))))))
    (is (= 1 (hash-table-count google)))
    (is (string= "(see attached image)"
                 (cadr-ai::json-get google "error")))
    (is (= 1 (hash-table-count vertex)))
    (is (string= "(see attached image)"
                 (cadr-ai::json-get vertex "error"))))
  (let* ((text (string (code-char #x000C)))
         (history
           (blank-tool-history
            :openai-completions :openai "gpt-test" text)))
    (setf (cadr-ai:tool-result-message-content
           (third history))
          (list (cadr-ai:make-text-content :text text)
                (cadr-ai:make-image-content
                 :data "abc" :mime-type "image/png")))
    (is (string= "(see attached image)"
                 (completions-tool-content "gpt-test" history)))))

(test orphaned-tool-calls-receive-synthetic-error-results
  (let* ((anthropic
           (request-spec-payload
            (history-request :anthropic (orphaned-tool-history))))
         (messages (cadr-ai::json-get anthropic "messages"))
         (tool-result-message (aref messages 2))
         (tool-result
           (aref (cadr-ai::json-get tool-result-message "content") 0)))
    (is (string= "user" (cadr-ai::json-get tool-result-message "role")))
    (is (string= "tool_result" (cadr-ai::json-get tool-result "type")))
    (is (eq t (cadr-ai::json-get tool-result "is_error")))
    (is (string= "No result provided"
                 (cadr-ai::json-get tool-result "content"))))
  (let* ((openai
           (request-spec-payload
            (history-request :openai (orphaned-tool-history))))
         (output
           (object-with-key (cadr-ai::json-get openai "input") "output")))
    (is (string= "function_call_output"
                 (cadr-ai::json-get output "type")))
    (is (string= "No result provided"
                 (cadr-ai::json-get output "output"))))
  (let* ((google
           (request-spec-payload
            (history-request :google (orphaned-tool-history))))
         (contents (cadr-ai::json-get google "contents"))
         (tool-result-message (aref contents 2))
         (response-part
           (object-with-key (cadr-ai::json-get tool-result-message "parts")
                            "functionResponse"))
         (response (cadr-ai::json-get response-part "functionResponse"))
         (id (cadr-ai::json-get response "id")))
    (is (safe-provider-id-p id))
    (is (string=
         "No result provided"
         (cadr-ai::json-get (cadr-ai::json-get response "response") "error")))))

(test foreign-history-is-made-safe-for-gemini-3.6
  (let* ((original-id
           "call.bad|fc.bad?abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
         (history
           (list
            (cadr-ai:make-user-message :content "Use the tool.")
            (cadr-ai:make-assistant-message
             :api :openai-responses
             :provider :openai
             :model "foreign-model"
             :stop-reason :tool-use
             :content
             (list
              (cadr-ai:make-thinking-content
               :thinking "Foreign reasoning"
               :signature "opaque-reasoning")
              (cadr-ai:make-text-content
               :text "Calling now."
               :signature "opaque-text")
              (cadr-ai:make-tool-call
               :id original-id
               :name "read"
               :arguments (cadr-ai::json-object "path" "README.md")
               :thought-signature "opaque-tool")))
            (cadr-ai:make-tool-result-message
             :tool-call-id original-id
             :tool-name "read"
             :content (list (cadr-ai:make-text-content :text "contents")))))
         (payload
           (request-spec-payload (history-request :google history)))
         (contents (cadr-ai::json-get payload "contents"))
         (assistant-parts (cadr-ai::json-get (aref contents 1) "parts"))
         (function-part (object-with-key assistant-parts "functionCall"))
         (function-call (cadr-ai::json-get function-part "functionCall"))
         (normalized-id (cadr-ai::json-get function-call "id"))
         (response-part
           (object-with-key
            (cadr-ai::json-get (aref contents 2) "parts")
            "functionResponse"))
         (function-response
           (cadr-ai::json-get response-part "functionResponse")))
    (is (safe-provider-id-p normalized-id))
    (is (string= normalized-id
                 (cadr-ai::json-get function-response "id")))
    (is (null (cadr-ai::json-get function-part "thoughtSignature")))
    ;; pi@4a080252f #10995 / #11000 — foreign thinking is dropped, not
    ;; sent as plain text. Visible text and the tool call remain.
    (is (string= "Calling now."
                 (cadr-ai::json-get (aref assistant-parts 0) "text")))
    (is (null (cadr-ai::json-get (aref assistant-parts 0) "thought")))
    (is (null (cadr-ai::json-get (aref assistant-parts 0)
                               "thoughtSignature")))
    (is (cadr-ai::json-present-p
         (aref assistant-parts 1) "functionCall"))))

(test cross-model-thinking-is-dropped-not-sent-as-text
  ;; pi@4a080252f transform-messages-cross-model-thinking.test.ts / #11000
  (let* ((normalize (lambda (id &rest _) (declare (ignore _)) id))
         (target
           (make-model
            :id "moonshotai/Kimi-K3"
            :name "Kimi K3"
            :api :openai-completions
            :provider :sference
            :base-url "https://example.test/v1"
            :reasoning-p t
            :context-window 1048576
            :max-tokens 32768))
         (prepared
           (cadr-ai::prepare-messages-for-model
            (list
             (cadr-ai:make-user-message :content "Why?")
             (cadr-ai:make-assistant-message
              :api :openai-completions
              :provider :sference
              :model "zai-org/GLM-5.3"
              :stop-reason :tool-use
              :content
              (list
               (cadr-ai:make-thinking-content
                :thinking "proxy or TLS"
                :signature "reasoning_content")
               (cadr-ai:make-text-content :text "Checking TLS.")
               (cadr-ai:make-tool-call
                :id "call_1" :name "bash"
                :arguments (cadr-ai::json-object "command" "curl -v"))))
             (cadr-ai:make-tool-result-message
              :tool-call-id "call_1" :tool-name "bash"
              :content (list (cadr-ai:make-text-content :text "TLSv1.2"))))
            target
            normalize))
         (assistant
           (find-if (lambda (message)
                      (typep message 'cadr-ai:assistant-message))
                    prepared)))
    (is (= 2 (length (cadr-ai:assistant-message-content assistant))))
    (is (typep (first (cadr-ai:assistant-message-content assistant))
               'cadr-ai:text-content))
    (is (string= "Checking TLS."
                 (cadr-ai:text-content-text
                  (first (cadr-ai:assistant-message-content assistant)))))
    (is (typep (second (cadr-ai:assistant-message-content assistant))
               'cadr-ai:tool-call))
    (is (notany
         (lambda (block) (typep block 'cadr-ai:thinking-content))
         (cadr-ai:assistant-message-content assistant)))))

(test consecutive-anthropic-tool-results-share-one-user-turn
  (let* ((assistant
           (cadr-ai:make-assistant-message
            :api :anthropic-messages
            :provider :anthropic
            :model "claude-test"
            :stop-reason :tool-use
            :content
            (list
             (cadr-ai:make-tool-call
              :id "call_1" :name "read"
              :arguments (cadr-ai::json-object "path" "a"))
             (cadr-ai:make-tool-call
              :id "call_2" :name "read"
              :arguments (cadr-ai::json-object "path" "b")))))
         (messages
           (cadr-ai::json-get
            (request-spec-payload
             (history-request
              :anthropic
              (list
               assistant
               (cadr-ai:make-tool-result-message
                :tool-call-id "call_1" :tool-name "read"
                :content (list (cadr-ai:make-text-content :text "a")))
               (cadr-ai:make-tool-result-message
                :tool-call-id "call_2" :tool-name "read"
                :content (list (cadr-ai:make-text-content :text "b"))))))
            "messages")))
    (is (= 2 (length messages)))
    (is (= 2 (length (cadr-ai::json-get (aref messages 1) "content"))))))

(test incomplete-and-empty-assistant-messages-are-not-replayed
  (let* ((history
           (list
            (cadr-ai:make-user-message :content "First")
            (cadr-ai:make-assistant-message
             :api :google-generative-ai
             :provider :google
             :model "gemini-3.6-flash"
             :stop-reason :aborted
             :content (list (cadr-ai:make-text-content :text "partial")))
            (cadr-ai:make-assistant-message
             :api :google-generative-ai
             :provider :google
             :model "gemini-3.6-flash"
             :stop-reason :stop
             :content nil)
            (cadr-ai:make-user-message :content "Second")))
         (contents
           (cadr-ai::json-get
            (request-spec-payload (history-request :google history))
            "contents")))
    (is (= 2 (length contents)))
    (is (every (lambda (content)
                 (string= "user" (cadr-ai::json-get content "role")))
               (coerce contents 'list)))))
