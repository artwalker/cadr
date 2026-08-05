(in-package #:cadr-agent)

(defconstant +max-session-header-scan-bytes+
  (* 1024 1024))

(defstruct session-entry
  type
  id
  parent-id
  timestamp
  message
  summary
  (source-ids nil :type list)
  first-kept-id
  (tokens-before 0 :type (integer 0 *))
  thinking-level
  provider
  model-id
  active-tool-names
  from-id
  details
  usage
  (from-hook-p nil :type boolean)
  custom-type
  data
  content
  (display-p nil :type boolean)
  target-id
  label
  name
  retained-tail)

(defstruct (session
            (:constructor %make-session))
  id
  timestamp
  cwd
  path
  parent-session
  name
  modified-timestamp
  (labels (make-hash-table :test #'equal)
          :type hash-table)
  (%entries nil :type list)
  %entries-tail
  %entries-tail-head
  (by-id (make-hash-table :test #'equal) :type hash-table)
  leaf-id
  (persisted-p nil :type boolean)
  (lock (sb-thread:make-mutex :name "cadr-session")))

(defun canonical-session-cwd (cwd)
  (namestring
   (truename (uiop:ensure-directory-pathname cwd))))

(defun default-session-directory ()
  (merge-pathnames
   ".cadr/sessions/"
   (user-homedir-pathname)))

(defun make-session-id ()
  (cadr-ai:uuid-v7))

(defun milliseconds-to-iso8601 (milliseconds)
  (cadr-core:milliseconds-to-utc-iso8601 milliseconds))

(defun iso8601-to-milliseconds (value)
  (cond
    ((integerp value) value)
    ((and (stringp value) (>= (length value) 19))
     (cadr-core:iso8601-to-milliseconds value))
    (t
     (error "Invalid session timestamp: ~S" value))))

(defun session-timestamp-json (milliseconds)
  (milliseconds-to-iso8601 milliseconds))

(defun session-failure (path line format-control &rest arguments)
  (error
   'session-error
   :path path
   :line line
   :message
   (apply #'format nil format-control arguments)))

(defun symbol-json-name (symbol)
  (string-downcase (symbol-name symbol)))

(defun plist-like-p (value)
  (and (listp value)
       (evenp (length value))
       (loop for tail on value by #'cddr
             for key = (first tail)
             always
             (or (keywordp key)
                 (stringp key)))))

(defun json-safe-value (value)
  (cond
    ((null value) nil)
    ((stringp value) value)
    ((hash-table-p value)
     (let ((copy (cadr-ai::json-object)))
       (maphash
        (lambda (key item)
          (cadr-ai::json-put
           copy
           (if (stringp key)
               key
               (symbol-json-name key))
           (json-safe-value item)))
        value)
       copy))
    ((vectorp value)
     (map 'vector #'json-safe-value value))
    ((plist-like-p value)
     (let ((object (cadr-ai::json-object)))
       (loop for (key item) on value by #'cddr
             do (cadr-ai::json-put
                 object
                 (if (stringp key)
                     key
                     (symbol-json-name key))
                 (json-safe-value item)))
       object))
    ((listp value)
     (map 'vector #'json-safe-value value))
    ((pathnamep value)
     (namestring value))
    ((and (symbolp value) (not (member value '(nil t))))
     (symbol-json-name value))
    (t value)))

(defun content-block-to-json (block)
  (cond
    ((typep block 'cadr-ai:text-content)
     (let ((object
             (cadr-ai::json-object
              "type" "text"
              "text" (cadr-ai:text-content-text block))))
       (when (cadr-ai:text-content-signature block)
         (cadr-ai::json-put
          object "signature"
          (cadr-ai:text-content-signature block)))
       object))
    ((typep block 'cadr-ai:thinking-content)
     (let ((object
             (cadr-ai::json-object
              "type" "thinking"
              "thinking"
              (cadr-ai:thinking-content-thinking block)
              "redacted"
              (cadr-ai:thinking-content-redacted-p block))))
       (when (cadr-ai:thinking-content-signature block)
         (cadr-ai::json-put
          object "signature"
          (cadr-ai:thinking-content-signature block)))
       object))
    ((typep block 'cadr-ai:image-content)
     (cadr-ai::json-object
      "type" "image"
      "mimeType" (cadr-ai:image-content-mime-type block)
      "data" (cadr-ai:image-content-data block)))
    ((typep block 'cadr-ai:tool-call)
     (let ((object
             (cadr-ai::json-object
              "type" "toolCall"
              "id" (cadr-ai:tool-call-id block)
              "name" (cadr-ai:tool-call-name block)
              "arguments"
              (json-safe-value
               (cadr-ai:tool-call-arguments block)))))
       (when (cadr-ai:tool-call-thought-signature block)
         (cadr-ai::json-put
          object "thoughtSignature"
          (cadr-ai:tool-call-thought-signature block)))
       object))
    (t
     (error "Unsupported session content block: ~S" block))))

(defun content-blocks-to-json (blocks)
  (map 'vector #'content-block-to-json blocks))

(defun usage-to-json (usage)
  (let* ((cost (cadr-ai:usage-cost usage))
         (object
           (cadr-ai::json-object
            "input" (cadr-ai:usage-input usage)
            "output" (cadr-ai:usage-output usage)
            "cacheRead" (cadr-ai:usage-cache-read usage)
            "cacheWrite" (cadr-ai:usage-cache-write usage)
            "total" (cadr-ai:usage-total usage)
            "cost"
            (cadr-ai::json-object
             "input" (cadr-ai:cost-input cost)
             "output" (cadr-ai:cost-output cost)
             "cacheRead" (cadr-ai:cost-cache-read cost)
             "cacheWrite" (cadr-ai:cost-cache-write cost)
             "total" (cadr-ai:cost-total cost)))))
    (when (cadr-ai:usage-reasoning usage)
      (cadr-ai::json-put
       object "reasoning" (cadr-ai:usage-reasoning usage)))
    object))

(defun diagnostic-detail-json-key (key)
  (case key
    (:error-code "errorCode")
    (:request-id "requestId")
    (otherwise
     (if (stringp key)
         key
         (symbol-json-name key)))))

(defun diagnostic-details-to-json (details)
  (if (plist-like-p details)
      (let ((object (cadr-ai::json-object)))
        (loop for (key value) on details by #'cddr
              do
              (cadr-ai::json-put
               object
               (diagnostic-detail-json-key key)
               (json-safe-value value)))
        object)
      (json-safe-value details)))

(defun assistant-diagnostic-to-json (diagnostic)
  (let ((object
          (cadr-ai::json-object
           "type"
           (symbol-json-name
            (cadr-ai:assistant-message-diagnostic-type diagnostic))
           "timestamp"
           (cadr-ai:assistant-message-diagnostic-timestamp diagnostic))))
    (when (cadr-ai:assistant-message-diagnostic-details diagnostic)
      (cadr-ai::json-put
       object "details"
       (diagnostic-details-to-json
        (cadr-ai:assistant-message-diagnostic-details diagnostic))))
    (when (cadr-ai:assistant-message-diagnostic-error diagnostic)
      (cadr-ai::json-put
       object "error"
       (json-safe-value
        (cadr-ai:assistant-message-diagnostic-error diagnostic))))
    object))

(defun diagnostic-detail-keyword (key)
  (cond
    ((string= key "errorCode") :error-code)
    ((string= key "requestId") :request-id)
    (t
     (intern (string-upcase key) "KEYWORD"))))

(defun message-to-json (message)
  (cond
    ((typep message 'cadr-ai:user-message)
     (cadr-ai::json-object
      "role" "user"
      "content"
      (let ((content (cadr-ai:user-message-content message)))
        (if (stringp content)
            content
            (content-blocks-to-json content)))
      "timestamp" (cadr-ai:user-message-timestamp message)))
    ((typep message 'cadr-ai:assistant-message)
     (let ((object
             (cadr-ai::json-object
              "role" "assistant"
              "content"
              (content-blocks-to-json
               (cadr-ai:assistant-message-content message))
              "api"
              (symbol-json-name
               (cadr-ai:assistant-message-api message))
              "provider"
              (symbol-json-name
               (cadr-ai:assistant-message-provider message))
              "model" (cadr-ai:assistant-message-model message)
              "usage"
              (usage-to-json
               (cadr-ai:assistant-message-usage message))
              "stopReason"
              (symbol-json-name
               (cadr-ai:assistant-message-stop-reason message))
              "timestamp"
              (cadr-ai:assistant-message-timestamp message))))
       (when (cadr-ai:assistant-message-response-id message)
         (cadr-ai::json-put
          object "responseId"
          (cadr-ai:assistant-message-response-id message)))
       (when (cadr-ai:assistant-message-error-message message)
         (cadr-ai::json-put
          object "errorMessage"
          (cadr-ai:assistant-message-error-message message)))
       (when (cadr-ai:assistant-message-raw-stop-reason message)
         (cadr-ai::json-put
          object "rawStopReason"
          (cadr-ai:assistant-message-raw-stop-reason message)))
       (when (cadr-ai:assistant-message-diagnostics message)
         (cadr-ai::json-put
          object "diagnostics"
          (map
           'vector
           #'assistant-diagnostic-to-json
           (cadr-ai:assistant-message-diagnostics message))))
       object))
    ((typep message 'bash-execution-message)
     (let ((object
             (cadr-ai::json-object
              "role" "bashExecution"
              "command"
              (bash-execution-message-command message)
              "output"
              (bash-execution-message-output message)
              "cancelled"
              (bash-execution-message-cancelled-p message)
              "truncated"
              (bash-execution-message-truncated-p message)
              "timestamp"
              (bash-execution-message-timestamp message)
              "excludeFromContext"
              (bash-execution-message-exclude-from-context-p
               message))))
       (when (integerp
              (bash-execution-message-exit-code message))
         (cadr-ai::json-put
          object "exitCode"
          (bash-execution-message-exit-code message)))
       (when (bash-execution-message-full-output-path message)
         (cadr-ai::json-put
          object "fullOutputPath"
          (bash-execution-message-full-output-path message)))
       object))
    ((typep message 'cadr-ai:tool-result-message)
     (cadr-ai::json-object
      "role" "toolResult"
      "toolCallId"
      (cadr-ai:tool-result-message-tool-call-id message)
      "toolName"
      (cadr-ai:tool-result-message-tool-name message)
      "content"
      (content-blocks-to-json
       (cadr-ai:tool-result-message-content message))
      "details"
      (json-safe-value
       (cadr-ai:tool-result-message-details message))
      "isError"
      (cadr-ai:tool-result-message-is-error message)
      "timestamp"
      (cadr-ai:tool-result-message-timestamp message)))
    (t
     (error "Unsupported session message: ~S" message))))

(defun keyword-from-json (value)
  (unless (stringp value)
    (error "Expected a symbolic JSON string"))
  (intern (string-upcase value) "KEYWORD"))

(defun json-get-either (object primary legacy)
  (multiple-value-bind (value present-p)
      (gethash primary object)
    (if present-p
        value
        (cadr-ai::json-get object legacy))))

(defun diagnostic-json-value-to-lisp (value)
  (cond
    ((stringp value) value)
    ((hash-table-p value)
     (let ((result nil))
       (maphash
        (lambda (key item)
          (setf result
                (append
                 result
                 (list
                  (diagnostic-detail-keyword key)
                  (diagnostic-json-value-to-lisp item)))))
        value)
       result))
    ((vectorp value)
     (map 'list #'diagnostic-json-value-to-lisp value))
    (t value)))

(defun assistant-diagnostic-from-json (object)
  (cadr-ai:make-assistant-message-diagnostic
   :type
   (keyword-from-json
    (cadr-ai::json-get object "type"))
   :timestamp
   (cadr-ai::json-get object "timestamp")
   :details
   (diagnostic-json-value-to-lisp
    (cadr-ai::json-get object "details"))
   :error
   (diagnostic-json-value-to-lisp
    (cadr-ai::json-get object "error"))))

(defun content-block-from-json (object)
  (let ((type (cadr-ai::json-get object "type")))
    (cond
      ((string= type "text")
       (cadr-ai:make-text-content
        :text (cadr-ai::json-get object "text")
        :signature (cadr-ai::json-get object "signature")))
      ((string= type "thinking")
       (cadr-ai:make-thinking-content
        :thinking (cadr-ai::json-get object "thinking")
        :signature (cadr-ai::json-get object "signature")
        :redacted-p
        (eq t (cadr-ai::json-get object "redacted"))))
      ((string= type "image")
       (cadr-ai:make-image-content
        :mime-type
        (json-get-either object "mimeType" "mime_type")
        :data (cadr-ai::json-get object "data")))
      ((member type '("toolCall" "tool_call")
               :test #'string=)
       (cadr-ai:make-tool-call
        :id (cadr-ai::json-get object "id")
        :name (cadr-ai::json-get object "name")
        :arguments
        (cadr-ai::json-get object "arguments")
        :thought-signature
        (json-get-either
         object "thoughtSignature" "thought_signature")))
      (t
       (error "Unknown content block type: ~S" type)))))

(defun content-blocks-from-json (value)
  (cond
    ((null value) nil)
    ((vectorp value)
     (loop for object across value
           collect
           (content-block-from-json object)))
    (t
     (error "Session content must be an array"))))

(defun usage-from-json (object)
  (let ((cost (cadr-ai::json-get object "cost")))
    (cadr-ai:make-usage
     :input (or (cadr-ai::json-get object "input") 0)
     :output (or (cadr-ai::json-get object "output") 0)
     :cache-read
     (or (json-get-either object "cacheRead" "cache_read") 0)
     :cache-write
     (or (json-get-either object "cacheWrite" "cache_write") 0)
     :reasoning (cadr-ai::json-get object "reasoning")
     :total (cadr-ai::json-get object "total")
     :cost
     (if (hash-table-p cost)
         (cadr-ai:make-cost
          :input
          (coerce
           (or (cadr-ai::json-get cost "input") 0)
           'double-float)
          :output
          (coerce
           (or (cadr-ai::json-get cost "output") 0)
           'double-float)
          :cache-read
          (coerce
           (or
            (json-get-either
             cost "cacheRead" "cache_read")
            0)
           'double-float)
          :cache-write
          (coerce
           (or
            (json-get-either
             cost "cacheWrite" "cache_write")
            0)
           'double-float)
          :total
          (coerce
           (or (cadr-ai::json-get cost "total") 0)
           'double-float))
         (cadr-ai:make-cost)))))

(defun message-from-json (object)
  (let ((type
          (or
           (cadr-ai::json-get object "role")
           (cadr-ai::json-get object "type")))
        (content (cadr-ai::json-get object "content")))
    (cond
      ((string= type "user")
       (cadr-ai:make-user-message
        :content
        (if (stringp content)
            content
            (content-blocks-from-json content))
        :timestamp (cadr-ai::json-get object "timestamp")))
      ((string= type "assistant")
       (cadr-ai:make-assistant-message
        :content (content-blocks-from-json content)
        :api (keyword-from-json
              (cadr-ai::json-get object "api"))
        :provider (keyword-from-json
                   (cadr-ai::json-get object "provider"))
        :model (cadr-ai::json-get object "model")
        :response-id
        (json-get-either object "responseId" "response_id")
        :usage
        (usage-from-json
         (cadr-ai::json-get object "usage"))
        :stop-reason
        (keyword-from-json
              (json-get-either
               object "stopReason" "stop_reason"))
        :error-message
        (json-get-either
         object "errorMessage" "error_message")
        :raw-stop-reason
        (json-get-either
         object "rawStopReason" "raw_stop_reason")
        :diagnostics
        (map
         'list
         #'assistant-diagnostic-from-json
         (or
          (cadr-ai::json-get object "diagnostics")
          #()))
        :timestamp (cadr-ai::json-get object "timestamp")))
      ((member type '("toolResult" "tool_result")
               :test #'string=)
       (cadr-ai:make-tool-result-message
        :tool-call-id
        (json-get-either object "toolCallId" "tool_call_id")
        :tool-name
        (json-get-either object "toolName" "tool_name")
        :content (content-blocks-from-json content)
        :details (cadr-ai::json-get object "details")
        :is-error
        (eq t
            (json-get-either object "isError" "is_error"))
        :timestamp (cadr-ai::json-get object "timestamp")))
      ((member type '("bashExecution" "bash_execution")
               :test #'string=)
       (make-bash-execution-message
        :command (or (cadr-ai::json-get object "command") "")
        :output (or (cadr-ai::json-get object "output") "")
        :exit-code
        (json-get-either object "exitCode" "exit_code")
        :cancelled-p
        (not (null (cadr-ai::json-get object "cancelled")))
        :truncated-p
        (not (null (cadr-ai::json-get object "truncated")))
        :full-output-path
        (json-get-either
         object "fullOutputPath" "full_output_path")
        :timestamp (cadr-ai::json-get object "timestamp")
        :exclude-from-context-p
        (not
         (null
          (json-get-either
           object "excludeFromContext"
           "exclude_from_context")))))
      ((string= type "custom")
       (cadr-ai:make-user-message
        :content
        (if (stringp content)
            content
            (content-blocks-from-json content))
        :timestamp (cadr-ai::json-get object "timestamp")))
      (t
       (error "Unknown message type: ~S" type)))))

(defun write-jsonl-object (stream object)
  (write-string (cadr-ai::stringify-json object) stream)
  (terpri stream)
  (finish-output stream))
