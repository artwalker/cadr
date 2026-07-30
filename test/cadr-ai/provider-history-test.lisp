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
    (is (string= "Foreign reasoning"
                 (cadr-ai::json-get (aref assistant-parts 0) "text")))
    (is (null (cadr-ai::json-get (aref assistant-parts 0) "thought")))
    (is (null (cadr-ai::json-get (aref assistant-parts 0)
                               "thoughtSignature")))))

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
