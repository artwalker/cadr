(in-package #:cadr-ai/tests)

(defparameter *project-root*
  (asdf:system-source-directory "cadr-ai"))

(defun fixture-path (relative)
  (merge-pathnames relative *project-root*))

(defun read-fixture (relative)
  (uiop:read-file-string (fixture-path relative)))

(defun parse-json (source)
  (cadr-ai::parse-json source))

(defun json-equal-p (left right)
  (cond
    ((and (cadr-ai::json-object-p left)
          (cadr-ai::json-object-p right))
     (let ((left-keys (cadr-ai::json-keys left))
           (right-keys (cadr-ai::json-keys right)))
       (and (= (length left-keys) (length right-keys))
            (loop for key in left-keys
                  always
                  (and (cadr-ai::json-present-p right key)
                       (json-equal-p
                        (cadr-ai::json-get left key)
                        (cadr-ai::json-get right key)))))))
    ((and (vectorp left) (vectorp right))
     (and (= (length left) (length right))
          (loop for index below (length left)
                always (json-equal-p (aref left index) (aref right index)))))
    (t
     (equalp left right))))

(defun sample-schema ()
  (cadr-ai::json-as-hash-table
   (parse-json
    "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"}},\"required\":[\"path\"]}")))

(defun sample-context ()
  (make-context
   :system-prompt "Be precise."
   :messages (list (make-user-message :content "Inspect README.md" :timestamp 1))
   :tools (list (make-tool :name "read"
                           :description "Read a file."
                           :parameters (sample-schema)))))

(defun provider-case (provider-name)
  (ecase provider-name
    (:anthropic
     (values (make-anthropic-provider :api-key "anthropic-test")
             (make-model :id "claude-test"
                         :provider :anthropic
                         :api :anthropic-messages
                         :base-url "https://api.anthropic.com"
                         :max-tokens 4096)))
    (:openai
     (values (make-openai-provider :api-key "openai-test")
             (make-model :id "gpt-test"
                         :provider :openai
                         :api :openai-responses
                         :base-url "https://api.openai.com"
                         :max-tokens 4096)))
    (:google
     (values (make-google-provider :api-key "google-test")
             (make-model :id "gemini-3.6-flash"
                         :provider :google
                         :api :google-generative-ai
                         :base-url "https://generativelanguage.googleapis.com/v1beta"
                         :max-tokens 4096)))
    (:bedrock
     (values (make-bedrock-provider :api-key "bedrock-test")
             (make-model :id "us.anthropic.claude-sonnet-4-5"
                         :provider :amazon-bedrock
                         :api :bedrock-converse-stream
                         :base-url "https://bedrock-runtime.us-east-1.amazonaws.com"
                         :max-tokens 4096)))
    (:mistral
     (values (make-mistral-provider :api-key "mistral-test")
             (make-model :id "mistral-small-latest"
                         :provider :mistral
                         :api :mistral-conversations
                         :base-url "https://api.mistral.ai"
                         :max-tokens 4096)))
    (:azure
     (values (make-azure-openai-provider :api-key "azure-test")
             (make-model :id "gpt-4.1"
                         :provider :azure-openai-responses
                         :api :azure-openai-responses
                         :base-url "https://goal20.openai.azure.com/openai/v1"
                         :max-tokens 4096)))
    (:vertex
     (values (make-vertex-provider :api-key "vertex-test")
             (make-model :id "gemini-3.6-flash"
                         :provider :google-vertex
                         :api :google-vertex
                         :base-url "https://aiplatform.googleapis.com/v1"
                         :max-tokens 4096)))
    (:codex
     (values (make-openai-codex-provider
              :oauth-access-token
              "eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJodHRwczovL2FwaS5vcGVuYWkuY29tL2F1dGgiOnsiY2hhdGdwdF9hY2NvdW50X2lkIjoiZ29hbDIwLWNvZGV4LWFjY291bnQifX0.sig"
              :oauth-account-id "goal20-codex-account")
             (make-model :id "gpt-5.5"
                         :provider :openai-codex
                         :api :openai-codex-responses
                         :base-url "https://chatgpt.com/backend-api"
                         :max-tokens 4096)))))

(defun first-text (message)
  (let ((block (find-if (lambda (item)
                          (typep item 'cadr-ai:text-content))
                        (assistant-message-content message))))
    (and block (text-content-text block))))

(defun collect-event-types (events)
  (mapcar #'stream-event-type events))
