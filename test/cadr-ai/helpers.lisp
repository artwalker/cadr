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
    ((and (hash-table-p left) (hash-table-p right))
     (and (= (hash-table-count left) (hash-table-count right))
          (loop for key being the hash-keys of left
                always (multiple-value-bind (value found-p)
                           (gethash key right)
                         (and found-p
                              (json-equal-p (gethash key left) value))))))
    ((and (vectorp left) (vectorp right))
     (and (= (length left) (length right))
          (loop for index below (length left)
                always (json-equal-p (aref left index) (aref right index)))))
    (t
     (equalp left right))))

(defun sample-schema ()
  (parse-json
   "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"}},\"required\":[\"path\"]}"))

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
                         :max-tokens 4096)))))

(defun first-text (message)
  (let ((block (find-if (lambda (item)
                          (typep item 'cadr-ai:text-content))
                        (assistant-message-content message))))
    (and block (text-content-text block))))

(defun collect-event-types (events)
  (mapcar #'stream-event-type events))
