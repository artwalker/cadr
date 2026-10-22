(in-package #:cadr-ai/tests)
(in-suite cadr-ai-suite)

(defun error-image (data)
  (cadr-ai:make-image-content :mime-type "image/png" :data data))

(defun error-tool-result (id name content &key error-p)
  (cadr-ai:make-tool-result-message
   :tool-call-id id
   :tool-name name
   :content content
   :is-error error-p))

(defun error-tool-assistant (provider api model-id)
  (cadr-ai:make-assistant-message
   :content
   (list
    (cadr-ai:make-tool-call
     :id "call-1" :name "codemode"
     :arguments (cadr-ai::json-object))
    (cadr-ai:make-tool-call
     :id "call-2" :name "read"
     :arguments (cadr-ai::json-object)))
   :api api
   :provider provider
   :model model-id
   :stop-reason :tool-use))

(test anthropic-error-tool-images-follow-the-turn
  ;; pi@4a080252f anthropic-messages.ts #10794.
  (let* ((model
           (cadr-ai:make-model
            :id "claude-test"
            :provider :anthropic
            :api :anthropic-messages
            :base-url "https://api.anthropic.com"
            :max-tokens 1024))
         (encoded
           (cadr-ai::anthropic-messages
            model
            (list
             (cadr-ai:make-user-message :content "Show the screenshots")
             (error-tool-assistant
              :anthropic :anthropic-messages "claude-test")
             (error-tool-result
              "call-1" "codemode"
              (list
               (cadr-ai:make-text-content :text "Script failed")
               (error-image "AAAA")
               (error-image "CCCC")
               (cadr-ai:make-text-content :text "Script error"))
              :error-p t)
             (error-tool-result
              "call-2" "read"
              (list (error-image "BBBB"))))))
         (turn (aref encoded 2))
         (content (cadr-ai::json-get turn "content"))
         (failed (aref content 0))
         (succeeded (aref content 1)))
    (is (string= "user" (cadr-ai::json-get turn "role")))
    (is (= 5 (length content)))
    (is (string= "tool_result" (cadr-ai::json-get failed "type")))
    (is (string=
         "Script failed
(image attached after the tool results)
Script error"
         (cadr-ai::json-get failed "content")))
    (is (eq t (cadr-ai::json-get failed "is_error")))
    (is (string= "call-2" (cadr-ai::json-get succeeded "tool_use_id")))
    (is (not (cadr-ai::json-get succeeded "is_error")))
    (is (string= "BBBB"
                 (cadr-ai::json-get
                  (cadr-ai::json-get
                   (aref (cadr-ai::json-get succeeded "content") 0)
                   "source")
                  "data")))
    (is (string=
         "Images from the error result of tool call call-1 (codemode):"
         (cadr-ai::json-get (aref content 2) "text")))
    (is (string= "AAAA"
                 (cadr-ai::json-get
                  (cadr-ai::json-get (aref content 3) "source")
                  "data")))
    (is (string= "CCCC"
                 (cadr-ai::json-get
                  (cadr-ai::json-get (aref content 4) "source")
                  "data"))))
  (let* ((model
           (cadr-ai:make-model
            :id "claude-test"
            :provider :anthropic
            :api :anthropic-messages
            :base-url "https://api.anthropic.com"
            :max-tokens 1024))
         (encoded
           (cadr-ai::anthropic-messages
            model
            (list
             (cadr-ai:make-user-message :content "Run it")
             (cadr-ai:make-assistant-message
              :content
              (list
               (cadr-ai:make-tool-call
                :id "call-1" :name "codemode"
                :arguments (cadr-ai::json-object)))
              :api :anthropic-messages
              :provider :anthropic
              :model "claude-test"
              :stop-reason :tool-use)
             (error-tool-result
              "call-1" "codemode"
              (list (cadr-ai:make-text-content :text "Script failed"))
              :error-p t))))
         (result (aref (cadr-ai::json-get (aref encoded 2) "content") 0)))
    (is (string= "Script failed" (cadr-ai::json-get result "content")))
    (is (eq t (cadr-ai::json-get result "is_error")))))

(test bedrock-claude-error-tool-images-follow-the-turn
  (let* ((claude
           (cadr-ai:make-model
            :id "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
            :provider :amazon-bedrock
            :api :bedrock-converse-stream
            :base-url "https://bedrock-runtime.us-east-1.amazonaws.com"
            :max-tokens 1024
            :reasoning-p t))
         (encoded
           (cadr-ai::bedrock-messages
            (cadr-ai:make-context
             :messages
             (list
              (error-tool-assistant
               :amazon-bedrock :bedrock-converse-stream
               (cadr-ai:model-id claude))
              (error-tool-result
               "call-1" "codemode"
               (list
                (cadr-ai:make-text-content :text "Script failed")
                (error-image "AAAA")
                (cadr-ai:make-text-content :text "Script error"))
               :error-p t)
              (error-tool-result
               "call-2" "read"
               (list (error-image "BBBB")))))
            claude))
         (content (cadr-ai::json-get (aref encoded 1) "content"))
         (failed (cadr-ai::json-get (aref content 0) "toolResult"))
         (failed-content (cadr-ai::json-get failed "content"))
         (succeeded (cadr-ai::json-get (aref content 1) "toolResult")))
    (is (= 4 (length content)))
    (is (string= "error" (cadr-ai::json-get failed "status")))
    (is (string= "Script failed"
                 (cadr-ai::json-get (aref failed-content 0) "text")))
    (is (string= "(image attached after the tool results)"
                 (cadr-ai::json-get (aref failed-content 1) "text")))
    (is (string= "Script error"
                 (cadr-ai::json-get (aref failed-content 2) "text")))
    (is (string= "success" (cadr-ai::json-get succeeded "status")))
    (is (string= "png"
                 (cadr-ai::json-get
                  (cadr-ai::json-get
                   (aref (cadr-ai::json-get succeeded "content") 0)
                   "image")
                  "format")))
    (is (string=
         "Images from the error result of tool call call-1 (codemode):"
         (cadr-ai::json-get (aref content 2) "text")))
    (is (string= "AAAA"
                 (cadr-ai::json-get
                  (cadr-ai::json-get
                   (cadr-ai::json-get (aref content 3) "image")
                   "source")
                  "bytes"))))
  (let* ((nova
           (cadr-ai:make-model
            :id "amazon.nova-lite-v1:0"
            :provider :amazon-bedrock
            :api :bedrock-converse-stream
            :base-url "https://bedrock-runtime.us-east-1.amazonaws.com"
            :max-tokens 1024))
         (encoded
           (cadr-ai::bedrock-messages
            (cadr-ai:make-context
             :messages
             (list
              (error-tool-result
               "call-1" "codemode"
               (list
                (cadr-ai:make-text-content :text "Script failed")
                (error-image "AAAA"))
               :error-p t)))
            nova))
         (result
           (cadr-ai::json-get
            (aref (cadr-ai::json-get (aref encoded 0) "content") 0)
            "toolResult"))
         (body (cadr-ai::json-get result "content")))
    (is (string= "error" (cadr-ai::json-get result "status")))
    (is (string= "Script failed" (cadr-ai::json-get (aref body 0) "text")))
    (is (string= "AAAA"
                 (cadr-ai::json-get
                  (cadr-ai::json-get (cadr-ai::json-get (aref body 1) "image")
                                     "source")
                  "bytes")))))
