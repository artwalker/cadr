(in-package #:cadr-ai/tests)

(in-suite cadr-ai-suite)

(defun goal24-fireworks-catalog-model (id)
  (cadr-ai::model-from-metadata
   (cadr-ai:find-model-metadata :fireworks id)))

(defun goal24-fireworks-tool (name description schema-json)
  (make-tool
   :name name
   :description description
   :parameters (parse-json schema-json)))

(defun goal24-fireworks-discovery-context (model loader-name)
  (make-context
   :messages
   (list
    (make-user-message :content "Look up alpha." :timestamp 0)
    (cadr-ai:make-assistant-message
     :api (cadr-ai::model-api model)
     :provider (cadr-ai::model-provider model)
     :model (cadr-ai::model-id model)
     :stop-reason :tool-use
     :content
     (list
      (cadr-ai:make-thinking-content
       :thinking "Find a lookup tool."
       :signature "")
      (cadr-ai:make-tool-call
       :id "search1"
       :name loader-name
       :arguments (cadr-ai::json-object "query" "lookup"))))
    (cadr-ai:make-tool-result-message
     :tool-call-id "search1"
     :tool-name loader-name
     :content (list (make-text-content :text "Found lookup."))
     :added-tool-names '("lookup")))
   :tools
   (list
    (goal24-fireworks-tool
     loader-name
     "Find tools"
     "{\"type\":\"object\",\"properties\":{\"query\":{\"type\":\"string\"}},\"required\":[\"query\"]}")
    (goal24-fireworks-tool
     "lookup"
     "Look up a synthetic key"
     "{\"type\":\"object\",\"properties\":{\"key\":{\"type\":\"string\"}},\"required\":[\"key\"]}"))))

(defparameter *goal24-fireworks-deferred-ids*
  '("accounts/fireworks/models/deepseek-v4-flash-0731"
    "accounts/fireworks/models/qwen3p8-max"
    "accounts/fireworks/models/kimi-k2p6"))

(defparameter *goal24-fireworks-loader-names*
  '("ToolSearch" "tool_search" "discover_tools"))

(test goal24-fireworks-catalog-stamps-tool-references
  (dolist (id *goal24-fireworks-deferred-ids*)
    (let ((model (goal24-fireworks-catalog-model id)))
      (is (eq t
              (getf (cadr-ai::model-compat model)
                    :supports-tool-references))))))

(test goal24-fireworks-deferred-tools-serialize-discovery
  (dolist (id *goal24-fireworks-deferred-ids*)
    (let ((model (goal24-fireworks-catalog-model id)))
      (dolist (loader-name *goal24-fireworks-loader-names*)
        (let* ((payload
                 (request-spec-payload
                  (build-request
                   (make-anthropic-provider :api-key "key")
                   model
                   (goal24-fireworks-discovery-context model loader-name)
                   :stream-p t)))
               (tools (cadr-ai::json-get payload "tools"))
               (messages (cadr-ai::json-get payload "messages"))
               (last-message (aref messages (1- (length messages))))
               (content (cadr-ai::json-get last-message "content"))
               (loader
                 (find loader-name tools
                       :key (lambda (item)
                              (cadr-ai::json-get item "name"))
                       :test #'string=))
               (lookup
                 (find "lookup" tools
                       :key (lambda (item)
                              (cadr-ai::json-get item "name"))
                       :test #'string=))
               (result
                 (find "tool_result" content
                       :key (lambda (item)
                              (cadr-ai::json-get item "type"))
                       :test #'string=))
               (references (cadr-ai::json-get result "content")))
          (is (= 2 (length tools)))
          (is (hash-table-p loader))
          (is (null (cadr-ai::json-get loader "defer_loading")))
          (is (eq t (cadr-ai::json-get lookup "defer_loading")))
          (is (string= "tool_reference"
                       (cadr-ai::json-get (aref references 0) "type")))
          (is (string= "lookup"
                       (cadr-ai::json-get (aref references 0)
                                          "tool_name"))))))))
