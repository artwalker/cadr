(in-package #:cadr-ai/tests)

(in-suite cadr-ai-suite)

(defun goal12-tool (name &key grammar)
  (make-tool
   :name name
   :description (format nil "Use ~A." name)
   :parameters
   (if grammar
       (parse-json
        "{\"type\":\"object\",\"properties\":{\"query\":{\"type\":\"string\"}},\"required\":[\"query\"]}")
       (sample-schema))
   :constrained-sampling
   (and grammar
        '(:type :grammar
          :variants (:openai-lark "start: /.+/")))))

(defun goal12-tool-history-context (&key tools)
  (make-context
   :messages
   (list
    (cadr-ai:make-assistant-message
     :api :openai-responses
     :provider :openai
     :model "source"
     :stop-reason :tool-use
     :content
     (list
      (cadr-ai:make-tool-call
       :id "load-call|fc_load_item"
       :name "tool_search"
       :arguments (cadr-ai::json-object "query" "write"))))
    (cadr-ai:make-tool-result-message
     :tool-call-id "load-call|fc_load_item"
     :tool-name "tool_search"
     :content (list (make-text-content :text "loaded"))
     :added-tool-names '("write")))
   :tools (or tools (list (goal12-tool "read") (goal12-tool "write")))))

(test goal12-responses-preserve-native-ids-and-hash-foreign-ids
  (let* ((long-id
           "msg_foreign_signature_that_is_longer_than_sixty_four_characters_0123456789")
         (foreign-item "foreign item with spaces and punctuation?!")
         (native-source
           (cadr-ai:make-assistant-message
            :api :openai-responses
            :provider :openai
            :model "gpt-test"
            :stop-reason :stop
            :content
            (list
             (cadr-ai:make-text-content
              :text "answer"
              :signature
              (cadr-ai::stringify-json
               (cadr-ai::json-object "v" 1 "id" long-id))))))
         (foreign-source
           (cadr-ai:make-assistant-message
            :api :openai-completions
            :provider :deepseek
            :model "foreign"
            :stop-reason :tool-use
            :content
            (list
             (cadr-ai:make-tool-call
              :id (format nil "call@bad|~A" foreign-item)
              :name "read"
              :arguments (cadr-ai::json-object "path" "README.md")))))
         (model
           (make-model
            :id "gpt-test" :provider :openai :api :openai-responses
            :base-url "https://api.openai.com" :max-tokens 4096))
         (payload
           (request-spec-payload
            (build-request
             (make-openai-provider :api-key "key") model
             (make-context :messages (list native-source foreign-source)) :stream-p t)))
         (input (cadr-ai::json-get payload "input"))
         (text-item (aref input 0))
         (tool-item (aref input 1)))
    (is (string= (format nil "msg_~A" (cadr-ai:short-hash long-id))
                 (cadr-ai::json-get text-item "id")))
    (is (string= "call_bad" (cadr-ai::json-get tool-item "call_id")))
    (is (string= (format nil "fc_~A" (cadr-ai:short-hash foreign-item))
                 (cadr-ai::json-get tool-item "id")))))

(test goal12-responses-deferred-and-grammar-tools-match-baseline-wire-shape
  (let* ((model
           (make-model
            :id "gpt-test" :provider :openai :api :openai-responses
            :base-url "https://api.openai.com" :max-tokens 4096
            :compat '(:supports-tool-search t
                      :supports-openai-grammar-tools t)))
         (grammar (goal12-tool "grammar" :grammar t))
         (context
           (goal12-tool-history-context
            :tools (list (goal12-tool "read") (goal12-tool "write") grammar)))
         (payload
           (request-spec-payload
            (build-request
             (make-openai-provider :api-key "key") model context :stream-p t)))
         (tools (cadr-ai::json-get payload "tools"))
         (input (cadr-ai::json-get payload "input"))
         (custom (find "custom" tools :key (lambda (item) (cadr-ai::json-get item "type"))
                                   :test #'string=))
         (search-output
           (find "tool_search_output" input
                 :key (lambda (item) (cadr-ai::json-get item "type"))
                 :test #'string=))
         (search-call
           (find "tool_search_call" input
                 :key (lambda (item) (cadr-ai::json-get item "type"))
                 :test #'string=)))
    (is (= 2 (length tools)))
    (is (not (find "write" tools :key (lambda (item) (cadr-ai::json-get item "name"))
                                       :test #'string=)))
    (is (hash-table-p custom))
    (is (string= "grammar"
                 (cadr-ai::json-get custom "name")))
    (is (string= "lark"
                 (cadr-ai::json-get (cadr-ai::json-get custom "format") "syntax")))
    (is (hash-table-p search-output))
    (is (hash-table-p search-call))
    (is (uiop:string-prefix-p
         "cadr_tool_load_"
         (cadr-ai::json-get search-call "call_id")))
    (is (string=
         (cadr-ai::json-get search-call "call_id")
         (cadr-ai::json-get search-output "call_id")))
    (let ((loaded (cadr-ai::json-get search-output "tools")))
      (is (= 1 (length loaded)))
      (is (string= "write" (cadr-ai::json-get (aref loaded 0) "name")))
      (is (eq t (cadr-ai::json-get (aref loaded 0) "defer_loading"))))))

(test goal12-anthropic-deferred-tools-use-references-and-sibling-output
  (let* ((model
           (make-model
            :id "claude-sonnet-4-6" :provider :anthropic
            :api :anthropic-messages :base-url "https://api.anthropic.com"
            :max-tokens 4096 :compat '(:supports-tool-references t)))
         (payload
           (request-spec-payload
            (build-request
             (cadr-ai:make-anthropic-provider :api-key "key") model
             (goal12-tool-history-context) :stream-p t)))
         (tools (cadr-ai::json-get payload "tools"))
         (messages (cadr-ai::json-get payload "messages"))
         (last-message (aref messages (1- (length messages))))
         (content (cadr-ai::json-get last-message "content")))
    (is (= 2 (length tools)))
    (let ((deferred
            (find "write" tools
                  :key (lambda (item) (cadr-ai::json-get item "name"))
                  :test #'string=)))
      (is (eq t (cadr-ai::json-get deferred "defer_loading"))))
    (let* ((result
             (find "tool_result" content
                   :key (lambda (item) (cadr-ai::json-get item "type"))
                   :test #'string=))
           (references (cadr-ai::json-get result "content")))
      (is (string= "tool_reference"
                   (cadr-ai::json-get (aref references 0) "type")))
      (is (string= "write"
                   (cadr-ai::json-get (aref references 0) "tool_name")))
      (is (find "loaded" content
                :key (lambda (item) (cadr-ai::json-get item "text"))
                :test #'string=)))))

(test goal12-kimi-deferred-tools-move-from-request-to-transcript
  (let* ((model
           (make-model
            :id "kimi-for-coding" :provider :kimi-coding
            :api :openai-completions :base-url "https://api.kimi.com/coding/v1"
            :max-tokens 4096 :compat '(:deferred-tools-mode :kimi)))
         (payload
           (request-spec-payload
            (build-request
             (cadr-ai:make-openai-completions-provider :api-key "key") model
             (goal12-tool-history-context) :stream-p t)))
         (tools (cadr-ai::json-get payload "tools"))
         (messages (cadr-ai::json-get payload "messages"))
         (loader
           (find-if
            (lambda (message)
              (and (string= "system" (or (cadr-ai::json-get message "role") ""))
                   (cadr-ai::json-present-p message "tools")))
            messages)))
    (is (= 1 (length tools)))
    (is (string= "read"
                 (cadr-ai::json-get
                  (cadr-ai::json-get (aref tools 0) "function") "name")))
    (is (hash-table-p loader))
    (is (string= "write"
                 (cadr-ai::json-get
                  (cadr-ai::json-get
                   (aref (cadr-ai::json-get loader "tools") 0) "function")
                  "name")))))

(defun goal13-emit-json-event (provider state emit payload)
  (cadr-ai::reduce-provider-sse-event
   provider state
   (cadr-ai::make-sse-event
    :data (cadr-ai::stringify-json payload))
   emit))

(defun goal13-streamed-tool-call (state)
  (find-if
   (lambda (block) (typep block 'cadr-ai:tool-call))
   (assistant-message-content
    (cadr-ai::provider-stream-state-message state))))

(defun goal13-stream-tool-arguments (provider fragments authoritative)
  (let* ((state
           (cadr-ai::make-provider-stream-state
            :message (cadr-ai:make-assistant-message)))
         (events nil)
         (emit (lambda (event) (push event events))))
    (etypecase provider
      (cadr-ai:openai-provider
       (goal13-emit-json-event
        provider state emit
        (cadr-ai::json-object
         "type" "response.output_item.added" "output_index" 0
         "item"
         (cadr-ai::json-object
          "type" "function_call" "id" "fc_1" "call_id" "c1"
          "name" "read" "arguments" "")))
       (dolist (fragment fragments)
         (goal13-emit-json-event
          provider state emit
          (cadr-ai::json-object
           "type" "response.function_call_arguments.delta"
           "output_index" 0 "delta" fragment)))
       (goal13-emit-json-event
        provider state emit
        (cadr-ai::json-object
         "type" "response.function_call_arguments.done"
         "output_index" 0 "arguments" authoritative))
       (goal13-emit-json-event
        provider state emit
        (cadr-ai::json-object
         "type" "response.output_item.done" "output_index" 0
         "item"
         (cadr-ai::json-object
          "type" "function_call" "id" "fc_1" "call_id" "c1"
          "name" "read" "arguments" authoritative))))
      (cadr-ai:openai-completions-provider
       (loop for fragment in fragments
             for first-p = t then nil
             do
                (goal13-emit-json-event
                 provider state emit
                 (cadr-ai::json-object
                  "id" "r"
                  "choices"
                  (cadr-ai::json-array
                   (cadr-ai::json-object
                    "delta"
                    (cadr-ai::json-object
                     "tool_calls"
                     (cadr-ai::json-array
                      (cadr-ai::json-object
                       "index" 0
                       "id" (if first-p "c1" 'cadr-ai::null)
                       "function"
                       (cadr-ai::json-object
                        "name" (if first-p "read" 'cadr-ai::null)
                        "arguments" fragment))))
                    "finish_reason" 'cadr-ai::null)))))
       (goal13-emit-json-event
        provider state emit
        (cadr-ai::json-object
         "id" "r"
         "choices"
         (cadr-ai::json-array
          (cadr-ai::json-object
           "delta" (cadr-ai::json-object)
           "finish_reason" "tool_calls")))))
      (cadr-ai:anthropic-provider
       (goal13-emit-json-event
        provider state emit
        (cadr-ai::json-object
         "type" "content_block_start" "index" 0
         "content_block"
         (cadr-ai::json-object
          "type" "tool_use" "id" "c1" "name" "read"
          "input" (cadr-ai::json-object))))
       (dolist (fragment fragments)
         (goal13-emit-json-event
          provider state emit
          (cadr-ai::json-object
           "type" "content_block_delta" "index" 0
           "delta"
           (cadr-ai::json-object
            "type" "input_json_delta" "partial_json" fragment))))
       (goal13-emit-json-event
        provider state emit
        (cadr-ai::json-object
         "type" "content_block_stop" "index" 0))))
    (values state (nreverse events))))

(test goal13-streamed-tool-arguments-are-exact-at-every-delta-boundary
  (let ((arguments
          "{\"path\":\"/root/projects/sonechka/src/product/work.rs\",\"offset\":0,\"limit\":349}"))
    (loop for split from 0 to (length arguments)
          do
             (dolist
                 (provider
                  (list
                   (make-openai-provider :api-key "key")
                   (cadr-ai:make-openai-completions-provider :api-key "key")
                   (cadr-ai:make-anthropic-provider :api-key "key")))
               (multiple-value-bind (state events)
                   (goal13-stream-tool-arguments
                    provider
                    (list (subseq arguments 0 split)
                          (subseq arguments split))
                    arguments)
                 (declare (ignore events))
                 (is
                  (string=
                   arguments
                   (gethash
                    (if
                        (typep provider
                               'cadr-ai:openai-completions-provider)
                        100000
                        0)
                    (cadr-ai::provider-stream-state-partial-json state))))
                 (let ((call (goal13-streamed-tool-call state)))
                   (is
                    (string=
                     "/root/projects/sonechka/src/product/work.rs"
                     (cadr-ai::json-get
                      (cadr-ai:tool-call-arguments call) "path")))
                   (is (= 0 (cadr-ai::json-get
                             (cadr-ai:tool-call-arguments call) "offset")))
                   (is (= 349 (cadr-ai::json-get
                               (cadr-ai:tool-call-arguments call) "limit")))))))))

(test goal13-openai-authoritative-tool-arguments-replace-corrupt-deltas
  (let* ((correct
           "{\"path\":\"/root/projects/sonechka/src/product/work.rs\",\"offset\":0,\"limit\":349}")
         (corrupt
           "{\"path\":\"/root/projects/sonechka/src/product/work.rs}},{\",\"offset\":0,\"limit\":349}"))
    (multiple-value-bind (state events)
        (goal13-stream-tool-arguments
         (make-openai-provider :api-key "key")
         (list corrupt)
         correct)
      (is
       (string=
        correct
        (gethash
         0 (cadr-ai::provider-stream-state-partial-json state))))
      (is
       (string=
        "/root/projects/sonechka/src/product/work.rs"
        (cadr-ai::json-get
         (cadr-ai:tool-call-arguments
          (goal13-streamed-tool-call state))
         "path")))
      (is
       (= 1
          (count :tool-call-end events
                 :key #'cadr-ai:stream-event-type))))))

(test goal12-mistral-tool-call-ids-are-exactly-nine-alphanumerics
  (let* ((context
           (make-context
            :messages
            (list
             (cadr-ai:make-assistant-message
              :api :openai-completions :provider :foreign :model "foreign"
              :stop-reason :tool-use
              :content
              (list
               (cadr-ai:make-tool-call
                :id "not valid and much too long" :name "read"
                :arguments (cadr-ai::json-object "path" "README.md"))))
             (cadr-ai:make-tool-result-message
              :tool-call-id "not valid and much too long" :tool-name "read"
              :content (list (make-text-content :text "ok"))))))
         (model
           (make-model
            :id "mistral-small-latest" :provider :mistral
            :api :mistral-conversations :base-url "https://api.mistral.ai"
            :max-tokens 4096))
         (messages
           (cadr-ai::json-get
            (request-spec-payload
             (build-request
              (cadr-ai:make-mistral-provider :api-key "key") model context :stream-p t))
            "messages"))
         (call-id
           (cadr-ai::json-get
            (aref (cadr-ai::json-get (aref messages 0) "tool_calls") 0) "id"))
         (result-id (cadr-ai::json-get (aref messages 1) "tool_call_id")))
    (is (= 9 (length call-id)))
    (is (every #'alphanumericp call-id))
    (is (string= call-id result-id))))

(test mistral-zai-glm-5-2-sends-reasoning-effort-not-prompt-mode
  ;; Upstream #9375: Mistral-hosted GLM-5.2 ignores prompt_mode.
  (let* ((model
           (make-model
            :id "zai-glm-5-2"
            :provider :mistral
            :api :mistral-conversations
            :base-url "https://api.mistral.ai"
            :max-tokens 4096
            :reasoning-p t))
         (payload
           (request-spec-payload
            (build-request
             (cadr-ai:make-mistral-provider :api-key "key")
             model
             (sample-context)
             :stream-p t
             :reasoning :high))))
    (is (string= "high"
                 (cadr-ai::json-get payload "reasoning_effort")))
    (is (not (cadr-ai::json-present-p payload "prompt_mode"))))
  (let* ((magistral
           (make-model
            :id "magistral-medium-latest"
            :provider :mistral
            :api :mistral-conversations
            :base-url "https://api.mistral.ai"
            :max-tokens 4096
            :reasoning-p t))
         (payload
           (request-spec-payload
            (build-request
             (cadr-ai:make-mistral-provider :api-key "key")
             magistral
             (sample-context)
             :stream-p t
             :reasoning :high))))
    (is (string= "reasoning"
                 (cadr-ai::json-get payload "prompt_mode")))
    (is (not (cadr-ai::json-present-p payload "reasoning_effort")))))
