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
  source-ids
  first-kept-id
  (tokens-before 0)
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
  retained-tail
  (%seen 0 :type fixnum))

(defstruct session-json-message
  role
  content
  timestamp
  usage
  extra)

(defstruct session-json-block
  type
  primary
  secondary
  extra)

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
  (lock (sb-thread:make-mutex :name "cadr-session"))
  %journal-stream
  %journal-octets)

(defun canonical-session-cwd (cwd)
  (namestring
   (truename (uiop:ensure-directory-pathname cwd))))

(defun default-session-directory ()
  (cadr-core:agent-sessions-directory))

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
    ((cadr-ai::json-object-pairs-p value)
     (let ((copy (cadr-ai::json-object)))
       (loop for (key item) on (cdr value) by #'cddr
             do (cadr-ai::json-put
                 copy
                 (if (stringp key)
                     key
                     (symbol-json-name key))
                 (json-safe-value item)))
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
  ;; Closed session/message vocab.  Same keyword as STRING-UPCASE
  ;; intern.  Not JSON intern expand.
  (or
   (cond
     ((or (eq value "stop") (string= value "stop")) :stop)
     ((or (eq value "toolUse") (string= value "toolUse")) :tooluse)
     ((or (eq value "openai-completions")
          (string= value "openai-completions"))
      :openai-completions)
     ((or (eq value "goal20faux") (string= value "goal20faux"))
      :goal20faux)
     ((or (eq value "user") (string= value "user")) :user)
     ((or (eq value "assistant") (string= value "assistant"))
      :assistant)
     ((or (eq value "error") (string= value "error")) :error))
   (intern (string-upcase value) "KEYWORD")))

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
          (push (diagnostic-detail-keyword key) result)
          (push (diagnostic-json-value-to-lisp item) result))
        value)
       (nreverse result)))
    ((cadr-ai::json-object-pairs-p value)
     (let ((result nil))
       (loop for (key item) on (cdr value) by #'cddr
             do
             (push (diagnostic-detail-keyword key) result)
             (push (diagnostic-json-value-to-lisp item) result))
       (nreverse result)))
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
  (unless (hash-table-p object)
    (return-from content-block-from-json object))
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
    ((listp value) value)
    ((vectorp value)
     (if (or (zerop (length value))
             (not (hash-table-p (aref value 0))))
         (coerce value 'list)
         (loop for object across value
               collect
               (content-block-from-json object))))
    (t
     (error "Session content must be an array"))))

(defun usage-cost-amount (object key &optional legacy)
  (coerce
   (or (if legacy
           (json-get-either object key legacy)
           (cadr-ai::json-get object key))
       0)
   'double-float))

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
          :input (usage-cost-amount cost "input")
          :output (usage-cost-amount cost "output")
          :cache-read
          (usage-cost-amount cost "cacheRead" "cache_read")
          :cache-write
          (usage-cost-amount cost "cacheWrite" "cache_write")
          :total (usage-cost-amount cost "total"))
         (cadr-ai:make-cost)))))

(defun message-from-json (object)
  (when (session-json-message-p object)
    (return-from message-from-json
      (let ((type (session-json-message-role object))
            (content (session-json-message-content object))
            (extra (session-json-message-extra object)))
        (cond
          ((string= type "user")
           (cadr-ai:make-user-message
            :content
            (if (stringp content)
                content
                (content-blocks-from-json content))
            :timestamp (session-json-message-timestamp object)))
          ((string= type "assistant")
           (cadr-ai:make-assistant-message
            :content (content-blocks-from-json content)
            :api (keyword-from-json (getf extra :api))
            :provider (keyword-from-json (getf extra :provider))
            :model (getf extra :model)
            :response-id (getf extra :response-id)
            :usage
            (or (session-json-message-usage object)
                (cadr-ai:make-usage))
            :stop-reason
            (keyword-from-json (getf extra :stop-reason))
            :error-message (getf extra :error-message)
            :raw-stop-reason (getf extra :raw-stop-reason)
            :diagnostics
            (map
             'list
             #'assistant-diagnostic-from-json
             (or (getf extra :diagnostics) #()))
            :timestamp
            (session-json-message-timestamp object)))
          ((member type '("toolResult" "tool_result")
                   :test #'string=)
           (cadr-ai:make-tool-result-message
            :tool-call-id (getf extra :tool-call-id)
            :tool-name (getf extra :tool-name)
            :content (content-blocks-from-json content)
            :details (getf extra :details)
            :is-error (eq t (getf extra :is-error))
            :timestamp
            (session-json-message-timestamp object)))
          ((member type '("bashExecution" "bash_execution")
                   :test #'string=)
           (make-bash-execution-message
            :command (or (getf extra :command) "")
            :output (or (getf extra :output) "")
            :exit-code (getf extra :exit-code)
            :cancelled-p (not (null (getf extra :cancelled)))
            :truncated-p (not (null (getf extra :truncated)))
            :full-output-path (getf extra :full-output-path)
            :timestamp
            (session-json-message-timestamp object)
            :exclude-from-context-p
            (not (null (getf extra :exclude-from-context)))))
          ((string= type "custom")
           (cadr-ai:make-user-message
            :content
            (if (stringp content)
                content
                (content-blocks-from-json content))
            :timestamp
            (session-json-message-timestamp object)))
          (t
           (error "Unknown message type: ~S" type))))))
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

(defun make-session-octet-buffer ()
  (make-array 4096
              :element-type '(unsigned-byte 8)
              :fill-pointer 0
              :adjustable t))

(defun emit-session-ascii (buffer text)
  (declare (type (vector (unsigned-byte 8)) buffer)
           (type string text))
  (loop for char across text
        do (vector-push-extend (char-code char) buffer))
  nil)

(defun emit-json-string (buffer value)
  ;; Dual of cadr-ai::write-json-string.  ASCII unescaped runs are
  ;; copied as bytes; UTF-8 is only used on a payload window.
  (declare (type (vector (unsigned-byte 8)) buffer)
           (type string value))
  (flet ((emit-unescaped (start end ascii-p)
           (declare (type fixnum start end))
           (if ascii-p
               (loop for index from start below end
                     do (vector-push-extend
                         (char-code (char value index))
                         buffer))
               (let ((octets
                       (sb-ext:string-to-octets
                        value
                        :external-format :utf-8
                        :start start
                        :end end)))
                 (loop for byte across octets
                       do (vector-push-extend byte buffer)))))
         (emit-u-escape (code)
           (vector-push-extend #x5c buffer)
           (vector-push-extend #x75 buffer)
           (loop for shift from 12 downto 0 by 4
                 for nibble = (ldb (byte 4 shift) code)
                 do (vector-push-extend
                     (if (< nibble 10)
                         (+ #x30 nibble)
                         (+ #x37 nibble))
                     buffer))))
    (vector-push-extend #x22 buffer)
    (let ((length (length value))
          (start 0)
          (ascii-p t))
      (declare (type fixnum length start))
      (loop for index from 0 below length
            for character = (char value index)
            for code = (char-code character)
            do
            (cond
              ((<= #xd800 code #xdfff)
               (when (< start index)
                 (emit-unescaped start index ascii-p))
               (setf start (1+ index)
                     ascii-p t))
              ((or (char= character #\")
                   (char= character #\\)
                   (char= character #\Backspace)
                   (char= character #\Page)
                   (char= character #\Newline)
                   (char= character #\Return)
                   (char= character #\Tab)
                   (< code #x20))
               (when (< start index)
                 (emit-unescaped start index ascii-p))
               (case character
                 (#\"
                  (vector-push-extend #x5c buffer)
                  (vector-push-extend #x22 buffer))
                 (#\\
                  (vector-push-extend #x5c buffer)
                  (vector-push-extend #x5c buffer))
                 (#\Backspace
                  (vector-push-extend #x5c buffer)
                  (vector-push-extend #x62 buffer))
                 (#\Page
                  (vector-push-extend #x5c buffer)
                  (vector-push-extend #x66 buffer))
                 (#\Newline
                  (vector-push-extend #x5c buffer)
                  (vector-push-extend #x6e buffer))
                 (#\Return
                  (vector-push-extend #x5c buffer)
                  (vector-push-extend #x72 buffer))
                 (#\Tab
                  (vector-push-extend #x5c buffer)
                  (vector-push-extend #x74 buffer))
                 (otherwise
                  (emit-u-escape code)))
               (setf start (1+ index)
                     ascii-p t))
              (t
               (when (>= code 128)
                 (setf ascii-p nil)))))
      (when (< start length)
        (emit-unescaped start length ascii-p)))
    (vector-push-extend #x22 buffer)
    nil))

(defun emit-json-value (buffer value)
  ;; Dual of cadr-ai::write-json-value.  Numbers stay ASCII digits.
  (declare (type (vector (unsigned-byte 8)) buffer))
  (labels ((emit-integer (number)
             (cond
               ((minusp number)
                (vector-push-extend #x2d buffer)
                (emit-integer (- number)))
               ((< number 10)
                (vector-push-extend (+ #x30 number) buffer))
               (t
                (multiple-value-bind (quotient remainder)
                    (truncate number 10)
                  (emit-integer quotient)
                  (vector-push-extend (+ #x30 remainder) buffer))))))
    (cond
      ((eq value 'null) (emit-session-ascii buffer "null"))
      ((eq value t) (emit-session-ascii buffer "true"))
      ((null value) (emit-session-ascii buffer "false"))
      ((stringp value) (emit-json-string buffer value))
      ((integerp value) (emit-integer value))
      ((rationalp value)
       (emit-session-ascii
        buffer
        (cadr-ai::terminating-rational-json-text value)))
      ((floatp value)
       (when (or (sb-ext:float-infinity-p value)
                 (sb-ext:float-nan-p value))
         (error "Cannot encode non-finite float ~S as JSON"
                value))
       (emit-session-ascii
        buffer
        (substitute
         #\e #\d
         (substitute
          #\e #\D
          (write-to-string
           (coerce value 'double-float)
           :readably t)))))
      ((hash-table-p value)
       (vector-push-extend #x7b buffer)
       (loop for key in
             (sort
              (loop for key being the hash-keys of value
                    collect key)
              #'string<)
             for first-p = t then nil
             do
             (emit-json-key buffer first-p key)
             (emit-json-value buffer (gethash key value)))
       (vector-push-extend #x7d buffer))
      ((cadr-ai::json-object-pairs-p value)
       (vector-push-extend #x7b buffer)
       (loop for key in
             (sort
              (loop for (pair-key) on (cdr value) by #'cddr
                    collect pair-key)
              #'string<)
             for first-p = t then nil
             do
             (emit-json-key buffer first-p key)
             (emit-json-value buffer (cadr-ai::json-get value key)))
       (vector-push-extend #x7d buffer))
      ((or (vectorp value) (listp value))
       (vector-push-extend #x5b buffer)
       (loop for item across (coerce value 'vector)
             for first-p = t then nil
             do
             (unless first-p
               (vector-push-extend #x2c buffer))
             (emit-json-value buffer item))
       (vector-push-extend #x5d buffer))
      (t
       (error "Cannot encode ~S as JSON" value))))
  nil)

(defun emit-json-key (buffer first-p key)
  (unless first-p
    (vector-push-extend #x2c buffer))
  (emit-json-string buffer key)
  (vector-push-extend #x3a buffer)
  nil)

(defun write-session-content-block (block buffer)
  (vector-push-extend #x7b buffer)
  (cond
    ((typep block 'cadr-ai:text-content)
     (let ((signature (cadr-ai:text-content-signature block)))
       (when signature
         (emit-json-key buffer t "signature")
         (emit-json-value buffer signature))
       (emit-json-key buffer (not signature) "text")
       (emit-json-value buffer (cadr-ai:text-content-text block))
       (emit-json-key buffer nil "type")
       (emit-json-value buffer "text")))
    ((typep block 'cadr-ai:thinking-content)
     (let ((signature (cadr-ai:thinking-content-signature block)))
       (emit-json-key buffer t "redacted")
       (emit-json-value
        buffer
        (cadr-ai:thinking-content-redacted-p block))
       (when signature
         (emit-json-key buffer nil "signature")
         (emit-json-value buffer signature))
       (emit-json-key buffer nil "thinking")
       (emit-json-value
        buffer
        (cadr-ai:thinking-content-thinking block))
       (emit-json-key buffer nil "type")
       (emit-json-value buffer "thinking")))
    ((typep block 'cadr-ai:image-content)
     (emit-json-key buffer t "data")
     (emit-json-value buffer (cadr-ai:image-content-data block))
     (emit-json-key buffer nil "mimeType")
     (emit-json-value buffer (cadr-ai:image-content-mime-type block))
     (emit-json-key buffer nil "type")
     (emit-json-value buffer "image"))
    ((typep block 'cadr-ai:tool-call)
     (let ((signature (cadr-ai:tool-call-thought-signature block)))
       (emit-json-key buffer t "arguments")
       (emit-json-value
        buffer
        (json-safe-value (cadr-ai:tool-call-arguments block)))
       (emit-json-key buffer nil "id")
       (emit-json-value buffer (cadr-ai:tool-call-id block))
       (emit-json-key buffer nil "name")
       (emit-json-value buffer (cadr-ai:tool-call-name block))
       (when signature
         (emit-json-key buffer nil "thoughtSignature")
         (emit-json-value buffer signature))
       (emit-json-key buffer nil "type")
       (emit-json-value buffer "toolCall")))
    (t
     (error "Unsupported session content block: ~S" block)))
  (vector-push-extend #x7d buffer))

(defun write-session-content (content buffer)
  (if (stringp content)
      (emit-json-value buffer content)
      (let ((first-p t))
        (vector-push-extend #x5b buffer)
        (map nil
             (lambda (block)
               (unless first-p
                 (vector-push-extend #x2c buffer))
               (setf first-p nil)
               (write-session-content-block block buffer))
             content)
        (vector-push-extend #x5d buffer))))

(defun write-session-usage (usage buffer)
  (let ((cost (cadr-ai:usage-cost usage))
        (reasoning (cadr-ai:usage-reasoning usage)))
    (vector-push-extend #x7b buffer)
    (emit-json-key buffer t "cacheRead")
    (emit-json-value buffer (cadr-ai:usage-cache-read usage))
    (emit-json-key buffer nil "cacheWrite")
    (emit-json-value buffer (cadr-ai:usage-cache-write usage))
    (emit-json-key buffer nil "cost")
    (vector-push-extend #x7b buffer)
    (emit-json-key buffer t "cacheRead")
    (emit-json-value buffer (cadr-ai:cost-cache-read cost))
    (emit-json-key buffer nil "cacheWrite")
    (emit-json-value buffer (cadr-ai:cost-cache-write cost))
    (emit-json-key buffer nil "input")
    (emit-json-value buffer (cadr-ai:cost-input cost))
    (emit-json-key buffer nil "output")
    (emit-json-value buffer (cadr-ai:cost-output cost))
    (emit-json-key buffer nil "total")
    (emit-json-value buffer (cadr-ai:cost-total cost))
    (vector-push-extend #x7d buffer)
    (emit-json-key buffer nil "input")
    (emit-json-value buffer (cadr-ai:usage-input usage))
    (emit-json-key buffer nil "output")
    (emit-json-value buffer (cadr-ai:usage-output usage))
    (when reasoning
      (emit-json-key buffer nil "reasoning")
      (emit-json-value buffer reasoning))
    (emit-json-key buffer nil "total")
    (emit-json-value buffer (cadr-ai:usage-total usage))
    (vector-push-extend #x7d buffer)))

(defun write-session-message (message buffer)
  (vector-push-extend #x7b buffer)
  (cond
    ((typep message 'cadr-ai:user-message)
     (emit-json-key buffer t "content")
     (write-session-content
      (cadr-ai:user-message-content message) buffer)
     (emit-json-key buffer nil "role")
     (emit-json-value buffer "user")
     (emit-json-key buffer nil "timestamp")
     (emit-json-value buffer (cadr-ai:user-message-timestamp message)))
    ((typep message 'cadr-ai:assistant-message)
     (let ((diagnostics (cadr-ai:assistant-message-diagnostics message))
           (error-message (cadr-ai:assistant-message-error-message message))
           (raw-stop (cadr-ai:assistant-message-raw-stop-reason message))
           (response-id (cadr-ai:assistant-message-response-id message)))
       (emit-json-key buffer t "api")
       (emit-json-value
        buffer
        (symbol-json-name (cadr-ai:assistant-message-api message)))
       (emit-json-key buffer nil "content")
       (write-session-content
        (cadr-ai:assistant-message-content message) buffer)
       (when diagnostics
         (emit-json-key buffer nil "diagnostics")
         (emit-json-value
          buffer
          (map 'vector #'assistant-diagnostic-to-json diagnostics)))
       (when error-message
         (emit-json-key buffer nil "errorMessage")
         (emit-json-value buffer error-message))
       (emit-json-key buffer nil "model")
       (emit-json-value buffer (cadr-ai:assistant-message-model message))
       (emit-json-key buffer nil "provider")
       (emit-json-value
        buffer
        (symbol-json-name (cadr-ai:assistant-message-provider message)))
       (when raw-stop
         (emit-json-key buffer nil "rawStopReason")
         (emit-json-value buffer raw-stop))
       (when response-id
         (emit-json-key buffer nil "responseId")
         (emit-json-value buffer response-id))
       (emit-json-key buffer nil "role")
       (emit-json-value buffer "assistant")
       (emit-json-key buffer nil "stopReason")
       (emit-json-value
        buffer
        (symbol-json-name
         (cadr-ai:assistant-message-stop-reason message)))
       (emit-json-key buffer nil "timestamp")
       (emit-json-value
        buffer
        (cadr-ai:assistant-message-timestamp message))
       (emit-json-key buffer nil "usage")
       (write-session-usage
        (cadr-ai:assistant-message-usage message) buffer)))
    ((typep message 'bash-execution-message)
     (let ((exit-code (bash-execution-message-exit-code message))
           (full-path (bash-execution-message-full-output-path message)))
       (emit-json-key buffer t "cancelled")
       (emit-json-value
        buffer
        (bash-execution-message-cancelled-p message))
       (emit-json-key buffer nil "command")
       (emit-json-value
        buffer
        (bash-execution-message-command message))
       (emit-json-key buffer nil "excludeFromContext")
       (emit-json-value
        buffer
        (bash-execution-message-exclude-from-context-p message))
       (when (integerp exit-code)
         (emit-json-key buffer nil "exitCode")
         (emit-json-value buffer exit-code))
       (when full-path
         (emit-json-key buffer nil "fullOutputPath")
         (emit-json-value buffer full-path))
       (emit-json-key buffer nil "output")
       (emit-json-value
        buffer
        (bash-execution-message-output message))
       (emit-json-key buffer nil "role")
       (emit-json-value buffer "bashExecution")
       (emit-json-key buffer nil "timestamp")
       (emit-json-value
        buffer
        (bash-execution-message-timestamp message))
       (emit-json-key buffer nil "truncated")
       (emit-json-value
        buffer
        (bash-execution-message-truncated-p message))))
    ((typep message 'cadr-ai:tool-result-message)
     (emit-json-key buffer t "content")
     (write-session-content
      (cadr-ai:tool-result-message-content message) buffer)
     (emit-json-key buffer nil "details")
     (emit-json-value
      buffer
      (json-safe-value
       (cadr-ai:tool-result-message-details message)))
     (emit-json-key buffer nil "isError")
     (emit-json-value
      buffer
      (cadr-ai:tool-result-message-is-error message))
     (emit-json-key buffer nil "role")
     (emit-json-value buffer "toolResult")
     (emit-json-key buffer nil "timestamp")
     (emit-json-value
      buffer
      (cadr-ai:tool-result-message-timestamp message))
     (emit-json-key buffer nil "toolCallId")
     (emit-json-value
      buffer
      (cadr-ai:tool-result-message-tool-call-id message))
     (emit-json-key buffer nil "toolName")
     (emit-json-value
      buffer
      (cadr-ai:tool-result-message-tool-name message)))
    (t
     (error "Unsupported session message: ~S" message)))
  (vector-push-extend #x7d buffer))

(defun emit-session-message-entry (entry buffer)
  ;; Schema-specific octet emit.  Keys stay string< order so the
  ;; JSONL bytes match stringify of session-entry-to-json.
  (vector-push-extend #x7b buffer)
  (emit-json-key buffer t "id")
  (emit-json-value buffer (session-entry-id entry))
  (emit-json-key buffer nil "message")
  (write-session-message (session-entry-message entry) buffer)
  (emit-json-key buffer nil "parentId")
  (emit-json-value
   buffer
   (or (session-entry-parent-id entry) 'null))
  (emit-json-key buffer nil "timestamp")
  (emit-json-value
   buffer
   (session-timestamp-json (session-entry-timestamp entry)))
  (emit-json-key buffer nil "type")
  (emit-json-value buffer "message")
  (vector-push-extend #x7d buffer)
  buffer)

(defun write-session-octets (stream buffer &key newline-p)
  (let ((element-type (stream-element-type stream)))
    (if (or (equal element-type '(unsigned-byte 8))
            (and (not (subtypep element-type 'character))
                 (subtypep element-type '(unsigned-byte 8))))
        (progn
          (write-sequence buffer stream)
          (when newline-p
            (write-byte 10 stream)))
        (progn
          (write-string
           (sb-ext:octets-to-string
            buffer :external-format :utf-8)
           stream)
          (when newline-p
            (terpri stream)))))
  nil)

(defun write-session-message-entry (entry stream)
  (let ((buffer (make-session-octet-buffer)))
    (emit-session-message-entry entry buffer)
    (write-session-octets stream buffer)))

(defun write-jsonl-object (stream object &optional buffer)
  (let ((buffer (or buffer (make-session-octet-buffer))))
    (setf (fill-pointer buffer) 0)
    (emit-json-value buffer object)
    (write-session-octets stream buffer :newline-p t)
    (finish-output stream)))

(defun write-session-entry-jsonl (stream entry &optional buffer)
  (if (or (eq (session-entry-type entry) :message)
          (and (stringp (session-entry-type entry))
               (string= (session-entry-type entry) "message")))
      (let ((buffer (or buffer (make-session-octet-buffer))))
        (setf (fill-pointer buffer) 0)
        (emit-session-message-entry entry buffer)
        (write-session-octets stream buffer :newline-p t)
        (finish-output stream))
      (write-jsonl-object stream (session-entry-to-json entry) buffer)))
