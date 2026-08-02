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
  (let ((state (make-random-state t)))
    (string-downcase
     (format nil "~36R-~36R"
             (cadr-ai::unix-milliseconds)
             (random
              most-positive-fixnum
              state)))))

(defun milliseconds-to-iso8601 (milliseconds)
  (multiple-value-bind
        (second minute hour day month year)
      (decode-universal-time
       (+ 2208988800
          (floor milliseconds 1000))
       0)
    (format nil
            "~4,'0D-~2,'0D-~2,'0DT~2,'0D:~2,'0D:~2,'0D.~3,'0DZ"
            year month day hour minute second
            (mod milliseconds 1000))))

(defun iso8601-to-milliseconds (value)
  (cond
    ((integerp value) value)
    ((and
      (stringp value)
      (>= (length value) 19))
     (handler-case
         (let* ((year (parse-integer value :start 0 :end 4))
                (month (parse-integer value :start 5 :end 7))
                (day (parse-integer value :start 8 :end 10))
                (hour (parse-integer value :start 11 :end 13))
                (minute (parse-integer value :start 14 :end 16))
                (second (parse-integer value :start 17 :end 19))
                (dot (position #\. value :start 19))
                (zone
                  (or
                   (position #\Z value :start 19)
                   (length value)))
                (fraction
                  (if dot
                      (subseq
                       value
                       (1+ dot)
                       (min zone (+ dot 4)))
                      "0"))
                (millisecond
                  (parse-integer
                   (concatenate
                    'string
                    fraction
                    (make-string
                     (max 0 (- 3 (length fraction)))
                     :initial-element #\0)))))
           (+ (* 1000
                 (- (encode-universal-time
                     second minute hour day month year 0)
                    2208988800))
              millisecond))
       (error ()
         (error "Invalid ISO-8601 timestamp: ~S" value))))
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

(defun message-timestamp (message)
  (etypecase message
    (cadr-ai:user-message
     (cadr-ai:user-message-timestamp message))
    (cadr-ai:assistant-message
     (cadr-ai:assistant-message-timestamp message))
    (cadr-ai:tool-result-message
     (cadr-ai:tool-result-message-timestamp message))))

(defun make-session-entry-id (by-id)
  (loop repeat 100
        for id =
          (string-downcase
           (format nil "~8,'0X"
                   (random
                    #x100000000
                    (make-random-state t))))
        unless (gethash id by-id)
          return id
        finally
           (session-failure
            nil nil "Cannot allocate a unique session entry id")))

(defun session-entries (session)
  (copy-list (session-%entries session)))

(defun session-entry-to-json (entry)
  (let ((base
          (cadr-ai::json-object
           "type"
           (case (session-entry-type entry)
             (:message "message")
             (:thinking-level-change
              "thinking_level_change")
             (:model-change "model_change")
             (:active-tools-change
              "active_tools_change")
             (:compaction "compaction")
             (:branch-summary "branch_summary")
             (:custom "custom")
             (:custom-message "custom_message")
             (:label "label")
             (:session-info "session_info")
             (:leaf "leaf"))
           "id" (session-entry-id entry)
           "parentId"
           (or
            (session-entry-parent-id entry)
            'null)
           "timestamp"
           (session-timestamp-json
            (session-entry-timestamp entry)))))
    (ecase (session-entry-type entry)
    (:message
     (cadr-ai::json-put
      base "message"
      (message-to-json
       (session-entry-message entry))))
    (:thinking-level-change
     (cadr-ai::json-put
      base "thinkingLevel"
      (session-entry-thinking-level entry)))
    (:model-change
     (cadr-ai::json-put
      base "provider"
      (session-entry-provider entry))
     (cadr-ai::json-put
      base "modelId"
      (session-entry-model-id entry)))
    (:active-tools-change
     (cadr-ai::json-put
      base "activeToolNames"
      (coerce
       (session-entry-active-tool-names entry)
       'vector)))
    (:compaction
     (cadr-ai::json-put
      base "summary" (session-entry-summary entry))
     (cadr-ai::json-put
      base "firstKeptEntryId"
      (session-entry-first-kept-id entry))
     (cadr-ai::json-put
      base "tokensBefore"
      (session-entry-tokens-before entry))
     (when (session-entry-details entry)
       (cadr-ai::json-put
        base "details"
        (json-safe-value
         (session-entry-details entry))))
     (when (session-entry-usage entry)
       (cadr-ai::json-put
        base "usage"
        (usage-to-json
         (session-entry-usage entry))))
     (when (session-entry-from-hook-p entry)
       (cadr-ai::json-put base "fromHook" t))
     (when (session-entry-retained-tail entry)
       (cadr-ai::json-put
        base "retainedTail"
        (map
         'vector
         #'message-to-json
         (session-entry-retained-tail entry)))))
    (:branch-summary
     (cadr-ai::json-put
      base "fromId" (session-entry-from-id entry))
     (cadr-ai::json-put
      base "summary" (session-entry-summary entry))
     (when (session-entry-details entry)
       (cadr-ai::json-put
        base "details"
        (json-safe-value
         (session-entry-details entry))))
     (when (session-entry-usage entry)
       (cadr-ai::json-put
        base "usage"
        (usage-to-json
         (session-entry-usage entry))))
     (when (session-entry-from-hook-p entry)
       (cadr-ai::json-put base "fromHook" t)))
    (:custom
     (cadr-ai::json-put
      base "customType"
      (session-entry-custom-type entry))
     (when (session-entry-data entry)
       (cadr-ai::json-put
        base "data"
        (json-safe-value
         (session-entry-data entry)))))
    (:custom-message
     (cadr-ai::json-put
      base "customType"
      (session-entry-custom-type entry))
     (cadr-ai::json-put
      base "content"
      (let ((content (session-entry-content entry)))
        (if (stringp content)
            content
            (content-blocks-to-json content))))
     (cadr-ai::json-put
      base "display"
      (session-entry-display-p entry))
     (when (session-entry-details entry)
       (cadr-ai::json-put
        base "details"
        (json-safe-value
         (session-entry-details entry)))))
    (:label
     (cadr-ai::json-put
      base "targetId"
      (session-entry-target-id entry))
     (when (session-entry-label entry)
       (cadr-ai::json-put
        base "label"
        (session-entry-label entry))))
    (:session-info
     (when (session-entry-name entry)
       (cadr-ai::json-put
        base "name"
        (session-entry-name entry))))
    (:leaf
     (cadr-ai::json-put
      base "targetId"
      (or
       (session-entry-target-id entry)
       'null))))
    base))

(defun session-header-to-json (session)
  (let ((header
          (cadr-ai::json-object
           "type" "session"
           "version" 3
           "id" (session-id session)
           "timestamp"
           (session-timestamp-json
            (session-timestamp session))
           "cwd" (session-cwd session))))
    (when (session-parent-session session)
      (cadr-ai::json-put
       header "parentSession"
       (session-parent-session session)))
    header))

(defun assistant-session-entry-p (entry)
  (and
   (eq :message (session-entry-type entry))
   (typep
    (session-entry-message entry)
    'cadr-ai:assistant-message)))

(defun session-entry-activity-timestamp (entry)
  (when (eq :message (session-entry-type entry))
    (let ((message (session-entry-message entry)))
      (cond
        ((typep message 'cadr-ai:user-message)
         (cadr-ai:user-message-timestamp message))
        ((typep message 'cadr-ai:assistant-message)
         (cadr-ai:assistant-message-timestamp message))))))

(defun create-session (&key
                             (directory
                               (default-session-directory))
                             cwd
                             id
                             parent-session
                             (timestamp
                               (cadr-ai::unix-milliseconds)))
  (let* ((session-directory
           (uiop:ensure-directory-pathname directory))
         (canonical-cwd
           (canonical-session-cwd
            (or cwd (uiop:getcwd))))
         (session-id (or id (make-session-id)))
         (path
           (merge-pathnames
            (format nil "~A.jsonl" session-id)
            session-directory)))
    (ensure-directories-exist
     (merge-pathnames "anchor" session-directory))
    (%make-session
     :id session-id
     :timestamp timestamp
     :cwd canonical-cwd
     :path path
     :parent-session parent-session
     :modified-timestamp timestamp)))

(defun ensure-session-entries-tail (session)
  (let ((entries (session-%entries session)))
    (cond
      ((null entries)
       (setf
        (session-%entries-tail session) nil
        (session-%entries-tail-head session) nil))
      ((or
        (not
         (eq entries
             (session-%entries-tail-head session)))
        (null (session-%entries-tail session))
        (not
         (null
          (cdr (session-%entries-tail session)))))
       (setf
        (session-%entries-tail session) (last entries)
        (session-%entries-tail-head session) entries))))
  (session-%entries-tail session))

(defun append-session-entry (session entry)
  (sb-thread:with-mutex
      ((session-lock session))
    (cond
      ((session-persisted-p session)
       (handler-case
           (with-open-file
               (stream (session-path session)
                       :direction :output
                       :if-exists :append
                       :if-does-not-exist :error
                       :external-format :utf-8)
             (write-jsonl-object
              stream (session-entry-to-json entry)))
         (error (cause)
           (session-failure
            (session-path session) nil
            "Cannot append session entry: ~A" cause))))
      ((assistant-session-entry-p entry)
       (handler-case
           (with-open-file
               (stream (session-path session)
                       :direction :output
                       :if-exists :error
                       :if-does-not-exist :create
                       :external-format :utf-8)
             (write-jsonl-object
              stream (session-header-to-json session))
             (dolist
                 (buffered-entry
                  (append
                   (session-%entries session)
                   (list entry)))
               (write-jsonl-object
                stream
                (session-entry-to-json
                 buffered-entry))))
         (error (cause)
           (session-failure
            (session-path session) nil
            "Cannot create session: ~A" cause)))
       (setf (session-persisted-p session) t)))
    (let ((cell (list entry)))
      (if (session-%entries session)
          (setf
           (cdr (ensure-session-entries-tail session)) cell
           (session-%entries-tail session) cell)
          (setf
           (session-%entries session) cell
           (session-%entries-tail session) cell
           (session-%entries-tail-head session) cell)))
    (setf
     (gethash (session-entry-id entry)
              (session-by-id session))
     entry
     (session-leaf-id session)
     (session-entry-id entry))
    (let ((activity
            (session-entry-activity-timestamp
             entry)))
      (when activity
        (setf
         (session-modified-timestamp session)
         (max
          (session-modified-timestamp session)
          activity)))))
  (session-entry-id entry))

(defun session-append-message (session message)
  (append-session-entry
   session
   (make-session-entry
    :type :message
    :id (make-session-entry-id
         (session-by-id session))
    :parent-id (session-leaf-id session)
    :timestamp (message-timestamp message)
    :message message)))

(defun session-append-compaction
    (session summary source-ids first-kept-id tokens-before
     &key details usage from-hook-p)
  (unless (and (stringp summary)
               (plusp (length summary)))
    (session-failure
     (session-path session) nil
     "Compaction summary must not be empty"))
  (unless (and (stringp first-kept-id)
               (gethash first-kept-id
                        (session-by-id session)))
    (session-failure
     (session-path session) nil
     "Compaction first-kept entry does not exist: ~S"
     first-kept-id))
  (dolist (id source-ids)
    (unless (gethash id (session-by-id session))
      (session-failure
       (session-path session) nil
       "Compaction source entry does not exist: ~S" id)))
  (append-session-entry
   session
   (make-session-entry
    :type :compaction
    :id (make-session-entry-id
         (session-by-id session))
    :parent-id (session-leaf-id session)
    :timestamp (cadr-ai::unix-milliseconds)
    :summary summary
    :source-ids (copy-list source-ids)
    :first-kept-id first-kept-id
    :tokens-before tokens-before
    :details details
    :usage usage
    :from-hook-p (not (null from-hook-p)))))

(defun make-session-child-entry (session type)
  (make-session-entry
   :type type
   :id (make-session-entry-id
        (session-by-id session))
   :parent-id (session-leaf-id session)
   :timestamp (cadr-ai::unix-milliseconds)))

(defun session-append-thinking-level-change
    (session thinking-level)
  (unless
      (and
       (stringp thinking-level)
       (plusp (length thinking-level)))
    (session-failure
     (session-path session) nil
     "Thinking level must be a non-empty string"))
  (let ((entry
          (make-session-child-entry
           session :thinking-level-change)))
    (setf
     (session-entry-thinking-level entry)
     thinking-level)
    (append-session-entry session entry)))

(defun session-append-model-change
    (session provider model-id)
  (unless
      (and
       (stringp provider)
       (plusp (length provider))
       (stringp model-id)
       (plusp (length model-id)))
    (session-failure
     (session-path session) nil
     "Model change provider and model id must be non-empty strings"))
  (let ((entry
          (make-session-child-entry
           session :model-change)))
    (setf
     (session-entry-provider entry) provider
     (session-entry-model-id entry) model-id)
    (append-session-entry session entry)))

(defun session-append-branch-summary
    (session from-id summary
     &key details usage from-hook-p)
  (unless
      (and
       (stringp from-id)
       (gethash from-id (session-by-id session))
       (stringp summary)
       (plusp (length summary)))
    (session-failure
     (session-path session) nil
     "Branch summary requires an existing from id and non-empty summary"))
  (let ((entry
          (make-session-child-entry
           session :branch-summary)))
    (setf
     (session-entry-from-id entry) from-id
     (session-entry-summary entry) summary
     (session-entry-details entry) details
     (session-entry-usage entry) usage
     (session-entry-from-hook-p entry)
     (not (null from-hook-p)))
    (append-session-entry session entry)))

(defun session-append-custom
    (session custom-type &optional data)
  (unless
      (and
       (stringp custom-type)
       (plusp (length custom-type)))
    (session-failure
     (session-path session) nil
     "Custom entry type must be a non-empty string"))
  (let ((entry
          (make-session-child-entry
           session :custom)))
    (setf
     (session-entry-custom-type entry) custom-type
     (session-entry-data entry) data)
    (append-session-entry session entry)))

(defun valid-custom-message-content-p (content)
  (or
   (stringp content)
   (and
    (typep content 'sequence)
    (every
     (lambda (block)
       (or
        (typep block 'cadr-ai:text-content)
        (typep block 'cadr-ai:image-content)))
     content))))

(defun session-append-custom-message
    (session custom-type content
     &key details (display-p nil))
  (unless
      (and
       (stringp custom-type)
       (plusp (length custom-type))
       (valid-custom-message-content-p content))
    (session-failure
     (session-path session) nil
     "Invalid custom message entry"))
  (let ((entry
          (make-session-child-entry
           session :custom-message)))
    (setf
     (session-entry-custom-type entry) custom-type
     (session-entry-content entry)
     (if (stringp content)
         content
         (coerce content 'list))
     (session-entry-details entry) details
     (session-entry-display-p entry)
     (not (null display-p)))
    (append-session-entry session entry)))

(defun session-set-label (session target-id label)
  (unless
      (and
       (stringp target-id)
       (gethash target-id (session-by-id session))
       (or (null label) (stringp label)))
    (session-failure
     (session-path session) nil
     "Label target must exist and label must be a string or NIL"))
  (let ((entry
          (make-session-child-entry
           session :label)))
    (setf
     (session-entry-target-id entry) target-id
     (session-entry-label entry) label)
    (prog1
        (append-session-entry session entry)
      (if (and label (plusp (length label)))
          (setf
           (gethash target-id
                    (session-labels session))
           label)
          (remhash target-id
                   (session-labels session))))))

(defun sanitize-session-name (name)
  (string-trim
   '(#\Space #\Tab #\Newline #\Return)
   (cl-ppcre:regex-replace-all
    "[\\r\\n]+"
    name " ")))

(defun session-set-name (session name)
  (unless (stringp name)
    (session-failure
     (session-path session) nil
     "Session name must be a string"))
  (let* ((sanitized (sanitize-session-name name))
         (entry
           (make-session-child-entry
            session :session-info)))
    (setf
     (session-entry-name entry) sanitized)
    (prog1
        (append-session-entry session entry)
      (setf
       (session-name session)
       (and
        (plusp (length sanitized))
        sanitized)))))

(defun session-label (session entry-id)
  (gethash entry-id (session-labels session)))

(defun session-branch (session entry-id)
  (unless (gethash entry-id (session-by-id session))
    (session-failure
     (session-path session) nil
     "Session entry not found: ~A" entry-id))
  (setf (session-leaf-id session) entry-id)
  session)

(defun session-path-entries (session &optional
                                      (leaf-id
                                        (session-leaf-id
                                         session)))
  (let ((path nil)
        (seen (make-hash-table :test #'equal))
        (current-id leaf-id))
    (loop while current-id
          do
          (when (gethash current-id seen)
            (session-failure
             (session-path session) nil
             "Cycle in session tree at ~A" current-id))
          (setf (gethash current-id seen) t)
          (let ((entry
                  (gethash current-id
                           (session-by-id session))))
            (unless entry
              (session-failure
               (session-path session) nil
               "Session entry not found: ~A" current-id))
            (push entry path)
            (setf current-id
                  (session-entry-parent-id entry))))
    path))

(defun latest-compaction-entry (entries)
  (find :compaction entries
        :key #'session-entry-type
        :from-end t))

(defun session-context-entries
    (session &optional (leaf-id (session-leaf-id session)))
  (let* ((path (session-path-entries session leaf-id))
         (compaction (latest-compaction-entry path)))
    (unless compaction
      (return-from session-context-entries path))
    (let* ((compaction-position
             (position compaction path :test #'eq))
           (first-kept-position
             (position
              (session-entry-first-kept-id compaction)
              path
              :key #'session-entry-id
              :test #'string=)))
      (unless (and first-kept-position
                   (< first-kept-position
                      compaction-position))
        (session-failure
         (session-path session) nil
         "Invalid compaction boundary ~S"
         (session-entry-first-kept-id compaction)))
      (append
       (list compaction)
       (subseq path
               first-kept-position
               compaction-position)
       (subseq path
               (1+ compaction-position))))))

(defun compaction-summary-message (entry)
  (cadr-ai:make-user-message
   :content
   (format nil
           "The conversation history before this point was compacted into the following summary:~%~%<summary>~%~A~%</summary>"
           (session-entry-summary entry))
   :timestamp (session-entry-timestamp entry)))

(defun session-messages (session &optional
                                   (leaf-id
                                     (session-leaf-id session)))
  (loop for entry in
          (session-context-entries session leaf-id)
        append
        (case (session-entry-type entry)
          (:message
           (list (session-entry-message entry)))
          (:compaction
           (list (compaction-summary-message entry)))
          (:branch-summary
           (list
            (cadr-ai:make-user-message
             :content
             (format nil
                     "The following is a summary of a branch that this conversation came back from:~%~%<summary>~%~A~%</summary>"
                     (session-entry-summary entry))
             :timestamp
             (session-entry-timestamp entry))))
          (:custom-message
           (list
            (cadr-ai:make-user-message
             :content
             (session-entry-content entry)
             :timestamp
             (session-entry-timestamp entry))))
          (otherwise nil))))

(defun parse-session-line (line path line-number)
  (handler-case
      (cadr-ai::parse-json line)
    (error (cause)
      (session-failure
       path line-number
       "Invalid session JSON at line ~D: ~A"
       line-number cause))))

(defun validate-session-header (object path)
  (unless (hash-table-p object)
    (session-failure path 1 "Invalid session header"))
  (let ((version (cadr-ai::json-get object "version" 1)))
    (unless
        (and (string= "session"
                      (cadr-ai::json-get object "type"))
             (member version '(1 2 3))
             (stringp (cadr-ai::json-get object "id"))
             (or
              (integerp
               (cadr-ai::json-get object "timestamp"))
              (stringp
               (cadr-ai::json-get object "timestamp")))
             (stringp (cadr-ai::json-get object "cwd")))
      (session-failure path 1 "Invalid session header")))
  object)

(defun read-session-objects (path)
  (let ((objects nil)
        (line-number 0))
    (handler-case
        (with-open-file
            (stream path
                    :direction :input
                    :external-format :utf-8)
          (loop
            (multiple-value-bind (line missing-newline-p)
                (read-line stream nil :eof)
              (declare (ignore missing-newline-p))
              (when (eq line :eof)
                (return))
              (incf line-number)
              (unless
                  (zerop
                   (length
                    (string-trim
                     '(#\Space #\Tab
                       #\Newline #\Return)
                     line)))
                (let ((object
                        (handler-case
                            (parse-session-line
                             line path line-number)
                          (session-error () nil))))
                  (when object
                    (push object objects)))))))
      (session-error (condition)
        (error condition))
      (error (cause)
        (session-failure
         path line-number "Cannot load session: ~A" cause)))
    (unless objects
      (session-failure path 1 "Session file has no header"))
    (nreverse objects)))

(defun session-header-candidate (octets)
  (handler-case
      (let ((line
              (sb-ext:octets-to-string
               octets :external-format :utf-8)))
        (if
            (zerop
             (length
              (string-trim
               '(#\Space #\Tab #\Newline #\Return)
               line)))
            :skip
            (let ((object (cadr-ai::parse-json line)))
              (if
                  (and
                   (hash-table-p object)
                   (string=
                    "session"
                    (cadr-ai::json-get object "type" ""))
                   (stringp
                    (cadr-ai::json-get object "id")))
                  object
                  :invalid))))
    (error () :skip)))

(defun read-session-header-for-discovery (path)
  (handler-case
      (with-open-file
          (stream path
                  :direction :input
                  :element-type '(unsigned-byte 8))
        (let ((line
                (make-array
                 256
                 :element-type '(unsigned-byte 8)
                 :adjustable t
                 :fill-pointer 0))
              (scanned 0))
          (labels
              ((inspect-line ()
                 (let ((candidate
                         (session-header-candidate
                          line)))
                   (setf (fill-pointer line) 0)
                   (cond
                     ((eq candidate :skip) nil)
                     ((eq candidate :invalid)
                      (return-from
                          read-session-header-for-discovery
                        nil))
                     (t
                      (return-from
                          read-session-header-for-discovery
                        candidate))))))
            (loop
              (when
                  (= scanned
                     +max-session-header-scan-bytes+)
                (let ((probe
                        (read-byte stream nil :eof)))
                  (if (eq probe :eof)
                      (progn
                        (inspect-line)
                        (return nil))
                      (return nil))))
              (let ((octet
                      (read-byte stream nil :eof)))
                (when (eq octet :eof)
                  (inspect-line)
                  (return nil))
                (incf scanned)
                (if (= octet 10)
                    (inspect-line)
                    (vector-push-extend
                     octet line)))))))
    (error () nil)))

(defun migrate-v1-session-objects (objects)
  (let ((by-id (make-hash-table :test #'equal))
        (parent-id nil))
    (cadr-ai::json-put (first objects) "version" 2)
    (loop for object in (rest objects)
          do
      (let ((id (make-session-entry-id by-id)))
        (cadr-ai::json-put object "id" id)
        (cadr-ai::json-put object "parentId" parent-id)
        (setf (gethash id by-id) t
              parent-id id))
      (when
          (and
           (string=
            "compaction"
            (cadr-ai::json-get object "type"))
           (integerp
            (cadr-ai::json-get
             object "firstKeptEntryIndex")))
        (let* ((index
                 (cadr-ai::json-get
                  object "firstKeptEntryIndex"))
               (target
                 (nth index objects)))
          (when
              (and
               target
               (not
                (string=
                 "session"
                 (cadr-ai::json-get target "type"))))
            (cadr-ai::json-put
             object "firstKeptEntryId"
             (cadr-ai::json-get target "id")))
          (remhash "firstKeptEntryIndex" object))))
  objects))

(defun migrate-v2-session-objects (objects)
  (cadr-ai::json-put (first objects) "version" 3)
  (dolist (object (rest objects))
    (when
        (string=
         "message"
         (cadr-ai::json-get object "type"))
      (let ((message
              (cadr-ai::json-get object "message")))
        (when
            (and
             (hash-table-p message)
             (string=
              "hookMessage"
              (or
               (cadr-ai::json-get message "role")
               "")))
          (cadr-ai::json-put
           message "role" "custom")))))
  objects)

(defun migration-temporary-path (path)
  (make-pathname
   :name
   (format nil ".~A-migrate-~A"
           (or (pathname-name path) "session")
           (make-session-id))
   :type "tmp"
   :defaults path))

(defun persist-migrated-session (objects path)
  (let ((temporary (migration-temporary-path path)))
    (unwind-protect
         (progn
           (with-open-file
               (stream temporary
                       :direction :output
                       :if-exists :error
                       :if-does-not-exist :create
                       :external-format :utf-8)
             (dolist (object objects)
               (write-jsonl-object stream object)))
           (uiop:rename-file-overwriting-target
            temporary path))
      (when (probe-file temporary)
        (delete-file temporary)))))

(defun require-json-field (object name path line-number)
  (multiple-value-bind (value present-p)
      (gethash name object)
    (unless present-p
      (session-failure
       path line-number
       "Session record is missing ~A" name))
    value))

(defun vector-of-strings-p (value)
  (and (vectorp value)
       (every #'stringp value)))

(defun json-null-to-nil (value)
  (if (cadr-ai::json-null-p value)
      nil
      value))

(defun record-to-session-entry
    (object path line-number by-id)
  (unless (hash-table-p object)
    (session-failure
     path line-number "Session record must be an object"))
  (let* ((type
           (require-json-field
            object "type" path line-number))
         (id
           (require-json-field
            object "id" path line-number))
         (parent-id
           (json-null-to-nil
            (require-json-field
             object "parentId" path line-number)))
         (timestamp-value
           (require-json-field
            object "timestamp" path line-number))
         (timestamp
           (handler-case
               (iso8601-to-milliseconds timestamp-value)
             (error (cause)
               (session-failure
                path line-number
                "Invalid session timestamp at line ~D: ~A"
                line-number cause)))))
    (unless
        (and
         (member
          type
          '("message"
            "thinking_level_change"
            "model_change"
            "active_tools_change"
            "compaction"
            "branch_summary"
            "custom"
            "custom_message"
            "label"
            "session_info"
            "leaf")
          :test #'string=)
         (stringp id)
         (or (null parent-id)
             (stringp parent-id)))
      (session-failure
       path line-number
       "Invalid session record at line ~D" line-number))
    (when (gethash id by-id)
      (session-failure
       path line-number "Duplicate session entry id: ~A" id))
    (when (and parent-id
               (not (gethash parent-id by-id)))
      (session-failure
       path line-number
       "Missing or forward session parent: ~A" parent-id))
    (let* ((entry
             (make-session-entry
              :type
              (intern
               (string-upcase
                (substitute #\- #\_ type))
               "KEYWORD")
              :id id
              :parent-id parent-id
              :timestamp timestamp))
           (details
             (cadr-ai::json-get object "details"))
           (usage-object
             (cadr-ai::json-get object "usage")))
      (cond
        ((string= type "message")
         (setf
          (session-entry-message entry)
          (message-from-json
           (require-json-field
            object "message" path line-number))))
        ((string= type "thinking_level_change")
         (let ((value
                 (require-json-field
                  object "thinkingLevel"
                  path line-number)))
           (unless (stringp value)
             (session-failure
              path line-number
              "Invalid thinking level entry at line ~D"
              line-number))
           (setf
            (session-entry-thinking-level entry)
            value)))
        ((string= type "model_change")
         (let ((provider
                 (require-json-field
                  object "provider" path line-number))
               (model-id
                 (require-json-field
                  object "modelId" path line-number)))
           (unless (and (stringp provider)
                        (stringp model-id))
             (session-failure
              path line-number
              "Invalid model change entry at line ~D"
              line-number))
           (setf
            (session-entry-provider entry) provider
            (session-entry-model-id entry) model-id)))
        ((string= type "active_tools_change")
         (let ((names
                 (require-json-field
                  object "activeToolNames"
                  path line-number)))
           (unless (vector-of-strings-p names)
             (session-failure
              path line-number
              "Invalid active tools entry at line ~D"
              line-number))
           (setf
            (session-entry-active-tool-names entry)
            (coerce names 'list))))
        ((string= type "compaction")
         (let* ((summary
                  (require-json-field
                   object "summary" path line-number))
                (source-ids
                  (or
                   (cadr-ai::json-get object "sourceIds")
                   #()))
                (first-kept-id
                  (require-json-field
                   object "firstKeptEntryId"
                   path line-number))
                (tokens-before
                  (require-json-field
                   object "tokensBefore"
                   path line-number)))
           (unless
               (and
                (stringp summary)
                (plusp (length summary))
                (vector-of-strings-p source-ids)
                (stringp first-kept-id)
                (integerp tokens-before)
                (not (minusp tokens-before))
                (gethash first-kept-id by-id)
                (every
                 (lambda (source-id)
                   (gethash source-id by-id))
                 source-ids))
             (session-failure
              path line-number
              "Invalid compaction record at line ~D"
              line-number))
           (setf
            (session-entry-summary entry) summary
            (session-entry-source-ids entry)
            (coerce source-ids 'list)
            (session-entry-first-kept-id entry)
            first-kept-id
            (session-entry-tokens-before entry)
            tokens-before
            (session-entry-details entry) details
            (session-entry-usage entry)
            (and usage-object
                 (usage-from-json usage-object))
            (session-entry-from-hook-p entry)
            (eq t
                (cadr-ai::json-get
                 object "fromHook"))
            (session-entry-retained-tail entry)
            (let ((tail
                    (cadr-ai::json-get
                     object "retainedTail")))
              (and
               (vectorp tail)
               (loop for message across tail
                     collect
                     (message-from-json
                      message)))))))
        ((string= type "branch_summary")
         (let ((from-id
                 (require-json-field
                  object "fromId" path line-number))
               (summary
                 (require-json-field
                  object "summary" path line-number)))
           (unless
               (and
                (stringp from-id)
                (or
                 (string= from-id "root")
                 (gethash from-id by-id))
                (stringp summary))
             (session-failure
              path line-number
              "Invalid branch summary at line ~D"
              line-number))
           (setf
            (session-entry-from-id entry) from-id
            (session-entry-summary entry) summary
            (session-entry-details entry) details
            (session-entry-usage entry)
            (and usage-object
                 (usage-from-json usage-object))
            (session-entry-from-hook-p entry)
            (eq t
                (cadr-ai::json-get
                 object "fromHook")))))
        ((string= type "custom")
         (let ((custom-type
                 (require-json-field
                  object "customType" path line-number)))
           (unless (stringp custom-type)
             (session-failure
              path line-number
              "Invalid custom entry at line ~D"
              line-number))
           (setf
            (session-entry-custom-type entry)
            custom-type
            (session-entry-data entry)
            (cadr-ai::json-get object "data"))))
        ((string= type "custom_message")
         (let ((custom-type
                 (require-json-field
                  object "customType" path line-number))
               (content
                 (require-json-field
                  object "content" path line-number)))
           (unless
               (and
                (stringp custom-type)
                (or
                 (null content)
                 (stringp content)
                 (vectorp content)))
             (session-failure
              path line-number
              "Invalid custom message at line ~D"
              line-number))
           (setf
            (session-entry-custom-type entry)
            custom-type
            (session-entry-content entry)
            (cond
              ((stringp content) content)
              ((null content) nil)
              (t
               (content-blocks-from-json
                content)))
            (session-entry-details entry) details
            (session-entry-display-p entry)
            (eq t
                (cadr-ai::json-get
                 object "display")))))
        ((string= type "label")
         (let ((target-id
                 (require-json-field
                  object "targetId" path line-number))
               (label
                 (json-null-to-nil
                  (cadr-ai::json-get object "label"))))
           (unless
               (and
                (stringp target-id)
                (gethash target-id by-id)
                (or (null label)
                    (stringp label)))
             (session-failure
              path line-number
              "Invalid label entry at line ~D"
              line-number))
           (setf
            (session-entry-target-id entry) target-id
            (session-entry-label entry) label)))
        ((string= type "session_info")
         (let ((name
                 (json-null-to-nil
                  (cadr-ai::json-get object "name"))))
           (unless (or (null name) (stringp name))
             (session-failure
              path line-number
              "Invalid session info at line ~D"
              line-number))
           (setf (session-entry-name entry) name)))
        ((string= type "leaf")
         (let ((target-id
                 (json-null-to-nil
                  (require-json-field
                   object "targetId"
                   path line-number))))
           (unless
               (and
                (or
                 (null target-id)
                 (stringp target-id))
                (or
                 (null target-id)
                 (gethash target-id by-id)))
             (session-failure
              path line-number
              "Invalid leaf entry at line ~D"
              line-number))
           (setf
            (session-entry-target-id entry)
            target-id))))
      (setf (gethash id by-id) entry)
      entry)))

(defun load-session (path)
  (let* ((pathname (pathname path))
         (objects (read-session-objects pathname))
         (header
           (validate-session-header
            (first objects) pathname))
         (version (cadr-ai::json-get header "version" 1)))
    (when (< version 3)
      (handler-case
          (progn
            (when (= version 1)
              (migrate-v1-session-objects objects))
            (migrate-v2-session-objects objects)
            (persist-migrated-session objects pathname))
        (session-error (condition)
          (error condition))
        (error (cause)
          (session-failure
           pathname nil
           "Cannot migrate session to v3: ~A" cause))))
    (let ((by-id (make-hash-table :test #'equal))
          (labels (make-hash-table :test #'equal))
          (session-name nil)
          (entries nil)
          (line-number 1))
      (dolist (object (rest objects))
        (incf line-number)
        (let ((entry
                (handler-case
                    (record-to-session-entry
                     object pathname line-number by-id)
           (session-error (condition)
             (error condition))
           (error (cause)
             (session-failure
              pathname line-number
              "Invalid session record at line ~D: ~A"
              line-number cause)))))
          (when (eq :label (session-entry-type entry))
            (if
                (and
                 (session-entry-label entry)
                 (plusp
                  (length
                   (session-entry-label entry))))
                (setf
                 (gethash
                  (session-entry-target-id entry)
                  labels)
                 (session-entry-label entry))
                (remhash
                 (session-entry-target-id entry)
                 labels)))
          (when
              (eq :session-info
                  (session-entry-type entry))
            (setf
             session-name
             (let ((name
                     (session-entry-name entry)))
               (and
                name
                (plusp
                 (length
                  (string-trim
                   '(#\Space #\Tab)
                   name)))
                name))))
          (push entry entries)))
      (setf entries (nreverse entries))
      (let* ((timestamp
               (iso8601-to-milliseconds
                (cadr-ai::json-get
                 header "timestamp")))
             (modified-timestamp
               (reduce
                #'max
                entries
                :key
                (lambda (entry)
                  (or
                   (session-entry-activity-timestamp
                    entry)
                   timestamp))
                :initial-value timestamp)))
        (%make-session
       :id (cadr-ai::json-get header "id")
       :timestamp timestamp
       :cwd (cadr-ai::json-get header "cwd")
       :path pathname
       :parent-session
       (json-null-to-nil
        (cadr-ai::json-get header "parentSession"))
       :name session-name
       :labels labels
       :%entries entries
       :%entries-tail (last entries)
       :%entries-tail-head entries
       :by-id by-id
       :persisted-p t
       :modified-timestamp modified-timestamp
       :leaf-id
       (and entries
            (session-entry-id
             (car (last entries)))))))))

(defun list-sessions (&key
                            (directory
                              (default-session-directory))
                            cwd)
  (let* ((session-directory
           (uiop:ensure-directory-pathname directory))
         (canonical-cwd
           (and cwd (canonical-session-cwd cwd))))
    (unless (probe-file session-directory)
      (return-from list-sessions nil))
    (sort
     (loop for path in
             (directory
              (merge-pathnames
               "*.jsonl" session-directory))
           for header =
             (read-session-header-for-discovery
              path)
           when
             (and
              header
              (or
               (null canonical-cwd)
               (string=
                canonical-cwd
                (cadr-ai::json-get
                 header "cwd" ""))))
             append
             (let ((session
                     (handler-case
                         (load-session path)
                       (session-error
                           (condition)
                         (if
                             (eql
                              1
                              (session-error-line
                               condition))
                             (error condition)
                             nil)))))
               (if session
                   (list session)
                   nil)))
     #'> :key #'session-modified-timestamp)))

(defun resume-session
    (id &key (directory (default-session-directory)))
  (let ((session
          (find id
                (list-sessions :directory directory)
                :key #'session-id
                :test #'string=)))
    (or session
        (session-failure
         (uiop:ensure-directory-pathname directory)
         nil
         "Session not found: ~A" id))))

(defun continue-session (&key
                               (directory
                                 (default-session-directory))
                               cwd)
  (first
   (list-sessions
    :directory directory
    :cwd (or cwd (uiop:getcwd)))))

(defparameter +session-skill-block-scanner+
  (cl-ppcre:create-scanner
   "^<skill name=\"([^\"]+)\" location=\"([^\"]+)\">\\n([\\s\\S]*?)\\n</skill>(?:\\n\\n([\\s\\S]+))?$"))

(defun parse-session-skill-block (text)
  (when (stringp text)
    (multiple-value-bind (match groups)
        (cl-ppcre:scan-to-strings
         +session-skill-block-scanner+
         text)
      (when match
        (values
         (aref groups 0)
         (aref groups 1)
         (aref groups 2)
         (and (> (length groups) 3)
              (aref groups 3))
         t)))))

(defvar *export-html-asset-reader*
  (lambda (relative-path)
    (uiop:read-file-string
     (asdf:system-relative-pathname
      "cadr-agent"
      (format nil
              "src/cadr-agent/export-html/~A"
              relative-path))
     :external-format :utf-8)))

(defparameter +export-html-template+
  (funcall *export-html-asset-reader* "template.html"))
(defparameter +export-html-template-css+
  (funcall *export-html-asset-reader* "template.css"))
(defparameter +export-html-template-js+
  (funcall *export-html-asset-reader* "template.js"))
(defparameter +export-html-marked-js+
  (funcall *export-html-asset-reader* "vendor/marked.min.js"))
(defparameter +export-html-highlight-js+
  (funcall *export-html-asset-reader* "vendor/highlight.min.js"))

(defparameter +export-html-base64-alphabet+
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")

(defparameter +export-html-dark-colors+
  '(("accent" . "#8abeb7")
    ("border" . "#5f87ff")
    ("borderAccent" . "#00d7ff")
    ("borderMuted" . "#505050")
    ("success" . "#b5bd68")
    ("error" . "#cc6666")
    ("warning" . "#ffff00")
    ("muted" . "#808080")
    ("dim" . "#666666")
    ("text" . "#d4d4d4")
    ("thinkingText" . "#808080")
    ("selectedBg" . "#3a3a4a")
    ("userMessageBg" . "#343541")
    ("userMessageText" . "#d4d4d4")
    ("customMessageBg" . "#2d2838")
    ("customMessageText" . "#d4d4d4")
    ("customMessageLabel" . "#9575cd")
    ("toolPendingBg" . "#282832")
    ("toolSuccessBg" . "#283228")
    ("toolErrorBg" . "#3c2828")
    ("toolTitle" . "#d4d4d4")
    ("toolOutput" . "#808080")
    ("mdHeading" . "#f0c674")
    ("mdLink" . "#81a2be")
    ("mdLinkUrl" . "#666666")
    ("mdCode" . "#8abeb7")
    ("mdCodeBlock" . "#b5bd68")
    ("mdCodeBlockBorder" . "#808080")
    ("mdQuote" . "#808080")
    ("mdQuoteBorder" . "#808080")
    ("mdHr" . "#808080")
    ("mdListBullet" . "#8abeb7")
    ("toolDiffAdded" . "#b5bd68")
    ("toolDiffRemoved" . "#cc6666")
    ("toolDiffContext" . "#808080")
    ("syntaxComment" . "#6A9955")
    ("syntaxKeyword" . "#569CD6")
    ("syntaxFunction" . "#DCDCAA")
    ("syntaxVariable" . "#9CDCFE")
    ("syntaxString" . "#CE9178")
    ("syntaxNumber" . "#B5CEA8")
    ("syntaxType" . "#4EC9B0")
    ("syntaxOperator" . "#D4D4D4")
    ("syntaxPunctuation" . "#D4D4D4")
    ("thinkingOff" . "#505050")
    ("thinkingMinimal" . "#6e6e6e")
    ("thinkingLow" . "#5f87af")
    ("thinkingMedium" . "#81a2be")
    ("thinkingHigh" . "#b294bb")
    ("thinkingXhigh" . "#d183e8")
    ("thinkingMax" . "#ff5fff")
    ("bashMode" . "#b5bd68")))

(defparameter +export-html-light-colors+
  '(("accent" . "#5a8080")
    ("border" . "#547da7")
    ("borderAccent" . "#5a8080")
    ("borderMuted" . "#b0b0b0")
    ("success" . "#588458")
    ("error" . "#aa5555")
    ("warning" . "#9a7326")
    ("muted" . "#6c6c6c")
    ("dim" . "#767676")
    ("text" . "#1f2328")
    ("thinkingText" . "#6c6c6c")
    ("selectedBg" . "#d0d0e0")
    ("userMessageBg" . "#e8e8e8")
    ("userMessageText" . "#1f2328")
    ("customMessageBg" . "#ede7f6")
    ("customMessageText" . "#1f2328")
    ("customMessageLabel" . "#7e57c2")
    ("toolPendingBg" . "#e8e8f0")
    ("toolSuccessBg" . "#e8f0e8")
    ("toolErrorBg" . "#f0e8e8")
    ("toolTitle" . "#1f2328")
    ("toolOutput" . "#6c6c6c")
    ("mdHeading" . "#9a7326")
    ("mdLink" . "#547da7")
    ("mdLinkUrl" . "#767676")
    ("mdCode" . "#5a8080")
    ("mdCodeBlock" . "#588458")
    ("mdCodeBlockBorder" . "#6c6c6c")
    ("mdQuote" . "#6c6c6c")
    ("mdQuoteBorder" . "#6c6c6c")
    ("mdHr" . "#6c6c6c")
    ("mdListBullet" . "#588458")
    ("toolDiffAdded" . "#588458")
    ("toolDiffRemoved" . "#aa5555")
    ("toolDiffContext" . "#6c6c6c")
    ("syntaxComment" . "#008000")
    ("syntaxKeyword" . "#0000FF")
    ("syntaxFunction" . "#795E26")
    ("syntaxVariable" . "#001080")
    ("syntaxString" . "#A31515")
    ("syntaxNumber" . "#098658")
    ("syntaxType" . "#267F99")
    ("syntaxOperator" . "#000000")
    ("syntaxPunctuation" . "#000000")
    ("thinkingOff" . "#b0b0b0")
    ("thinkingMinimal" . "#767676")
    ("thinkingLow" . "#547da7")
    ("thinkingMedium" . "#5a8080")
    ("thinkingHigh" . "#875f87")
    ("thinkingXhigh" . "#8b008b")
    ("thinkingMax" . "#af005f")
    ("bashMode" . "#588458")))

(defun encode-export-html-base64 (octets)
  (with-output-to-string (output)
    (loop for position from 0 below (length octets) by 3
          for remaining = (- (length octets) position)
          for first = (aref octets position)
          for second = (if (> remaining 1)
                           (aref octets (1+ position)) 0)
          for third = (if (> remaining 2)
                          (aref octets (+ position 2)) 0)
          for bits = (logior (ash first 16)
                             (ash second 8)
                             third)
          do
          (write-char
           (char +export-html-base64-alphabet+
                 (ldb (byte 6 18) bits))
           output)
          (write-char
           (char +export-html-base64-alphabet+
                 (ldb (byte 6 12) bits))
           output)
          (write-char
           (if (> remaining 1)
               (char +export-html-base64-alphabet+
                     (ldb (byte 6 6) bits))
               #\=)
           output)
          (write-char
           (if (> remaining 2)
               (char +export-html-base64-alphabet+
                     (ldb (byte 6 0) bits))
               #\=)
           output))))

(defun export-html-ansi-color (index)
  (when (<= 0 index 255)
    (cond
      ((< index 16)
       (aref
        #("#000000" "#800000" "#008000" "#808000"
          "#000080" "#800080" "#008080" "#c0c0c0"
          "#808080" "#ff0000" "#00ff00" "#ffff00"
          "#0000ff" "#ff00ff" "#00ffff" "#ffffff")
        index))
      ((< index 232)
       (let* ((cube-index (- index 16))
              (red (floor cube-index 36))
              (green (floor (mod cube-index 36) 6))
              (blue (mod cube-index 6)))
         (flet ((channel (value)
                  (if (zerop value)
                      0
                      (+ 55 (* value 40)))))
           (string-downcase
            (format nil "#~2,'0X~2,'0X~2,'0X"
                    (channel red)
                    (channel green)
                    (channel blue))))))
      (t
       (let ((gray (+ 8 (* (- index 232) 10))))
         (string-downcase
          (format nil "#~2,'0X~2,'0X~2,'0X"
                  gray gray gray)))))))

(defun resolve-export-html-theme-value
    (value variables default-value &optional seen)
  (cond
    ((integerp value)
     (or (export-html-ansi-color value)
         default-value))
    ((not (stringp value)) default-value)
    ((zerop (length value)) default-value)
    ((char= (char value 0) #\#) value)
    ((member value seen :test #'string=)
     default-value)
    (t
     (multiple-value-bind (referenced present-p)
         (if (hash-table-p variables)
             (gethash value variables)
             (values nil nil))
       (if present-p
           (resolve-export-html-theme-value
            referenced variables default-value
            (cons value seen))
           default-value)))))

(defun resolved-export-html-colors
    (theme-name theme-object)
  (let* ((light-p (string= (or theme-name "dark") "light"))
         (base
           (copy-tree
            (if light-p
                +export-html-light-colors+
                +export-html-dark-colors+)))
         (variables
           (and theme-object
                (cadr-ai::json-get
                 theme-object "vars")))
         (colors
           (and theme-object
                (cadr-ai::json-get
                 theme-object "colors")))
         (default-text
           (if light-p "#000000" "#e5e5e7")))
    (when (hash-table-p colors)
      (dolist (entry base)
        (multiple-value-bind (value present-p)
            (gethash (car entry) colors)
          (when present-p
            (setf
             (cdr entry)
             (resolve-export-html-theme-value
              value variables default-text))))))
    base))

(defun parse-export-html-color (value)
  (when (stringp value)
    (or
     (multiple-value-bind (match groups)
         (cl-ppcre:scan-to-strings
          "^#([0-9a-fA-F]{2})([0-9a-fA-F]{2})([0-9a-fA-F]{2})$"
          value)
       (and match
            (list
             (parse-integer (aref groups 0) :radix 16)
             (parse-integer (aref groups 1) :radix 16)
             (parse-integer (aref groups 2) :radix 16))))
     (multiple-value-bind (match groups)
         (cl-ppcre:scan-to-strings
          "^rgb[[:space:]]*\\([[:space:]]*([0-9]+)[[:space:]]*,[[:space:]]*([0-9]+)[[:space:]]*,[[:space:]]*([0-9]+)[[:space:]]*\\)$"
          value)
       (and match
            (list
             (parse-integer (aref groups 0))
             (parse-integer (aref groups 1))
             (parse-integer (aref groups 2))))))))

(defun export-html-channel-luminance (channel)
  (let ((scaled (/ channel 255d0)))
    (if (<= scaled 0.03928d0)
        (/ scaled 12.92d0)
        (expt (/ (+ scaled 0.055d0) 1.055d0)
              2.4d0))))

(defun export-html-adjust-color (rgb factor)
  (format nil "rgb(~D, ~D, ~D)"
          (min 255 (max 0 (floor (+ 0.5d0 (* (first rgb) factor)))))
          (min 255 (max 0 (floor (+ 0.5d0 (* (second rgb) factor)))))
          (min 255 (max 0 (floor (+ 0.5d0 (* (third rgb) factor)))))))

(defun derive-export-html-colors (base-color)
  (let ((rgb (parse-export-html-color base-color)))
    (if (null rgb)
        (list :page "rgb(24, 24, 30)"
              :card "rgb(30, 30, 36)"
              :info "rgb(60, 55, 40)")
        (let* ((red (first rgb))
               (green (second rgb))
               (blue (third rgb))
               (luminance
                 (+ (* 0.2126d0
                       (export-html-channel-luminance red))
                    (* 0.7152d0
                       (export-html-channel-luminance green))
                    (* 0.0722d0
                       (export-html-channel-luminance blue)))))
          (if (> luminance 0.5d0)
              (list
               :page (export-html-adjust-color rgb 0.96d0)
               :card base-color
               :info
               (format nil "rgb(~D, ~D, ~D)"
                       (min 255 (+ red 10))
                       (min 255 (+ green 5))
                       (max 0 (- blue 20))))
              (list
               :page (export-html-adjust-color rgb 0.7d0)
               :card (export-html-adjust-color rgb 0.85d0)
               :info
               (format nil "rgb(~D, ~D, ~D)"
                       (min 255 (+ red 20))
                       (min 255 (+ green 15))
                       blue)))))))

(defun export-html-explicit-colors (theme-object variables)
  (let ((export
          (and theme-object
               (cadr-ai::json-get
                theme-object "export"))))
    (labels ((value (key)
               (when (hash-table-p export)
                 (multiple-value-bind (raw present-p)
                     (gethash key export)
                   (and present-p
                        (resolve-export-html-theme-value
                         raw variables nil))))))
      (list :page (value "pageBg")
            :card (value "cardBg")
            :info (value "infoBg")))))

(defun built-in-export-html-colors (theme-name theme-object)
  (when (null theme-object)
    (cond
      ((string= (or theme-name "dark") "light")
       (list :page "#f8f8f8"
             :card "#ffffff"
             :info "#fffae6"))
      ((string= (or theme-name "dark") "dark")
       (list :page "#18181e"
             :card "#1e1e24"
             :info "#3c3728")))))

(defun export-html-theme-data (theme-name theme-object)
  (let* ((colors
           (resolved-export-html-colors
            theme-name theme-object))
         (derived
           (derive-export-html-colors
            (or (cdr (assoc "userMessageBg" colors
                            :test #'string=))
                "#343541")))
         (explicit
           (or
            (built-in-export-html-colors
             theme-name theme-object)
            (export-html-explicit-colors
             theme-object
             (and theme-object
                  (cadr-ai::json-get
                   theme-object "vars")))))
         (page (or (getf explicit :page)
                   (getf derived :page)))
         (card (or (getf explicit :card)
                   (getf derived :card)))
         (info (or (getf explicit :info)
                   (getf derived :info))))
    (values
     (format nil
             "~{~A~^~%      ~}~%      --exportPageBg: ~A;~%      --exportCardBg: ~A;~%      --exportInfoBg: ~A;"
             (mapcar
              (lambda (entry)
                (format nil "--~A: ~A;"
                        (car entry) (cdr entry)))
              colors)
             page card info)
     page card info)))

(defun export-html-session-data (session)
  (cadr-ai::json-object
   "header" (session-header-to-json session)
   "entries"
   (map 'vector
        #'session-entry-to-json
        (session-%entries session))
   "leafId" (or (session-leaf-id session) 'null)))

(defun export-session-html
    (session path
     &key (theme-name "dark") theme-object)
  (multiple-value-bind
        (theme-vars page-background
         card-background info-background)
      (export-html-theme-data
       theme-name theme-object)
    (let* ((session-data
             (cadr-ai::stringify-json
              (export-html-session-data session)))
           (encoded-data
             (encode-export-html-base64
              (cadr-ai::utf8-octets
               session-data)))
           (css
             (cadr-ai::replace-all
              (cadr-ai::replace-all
               (cadr-ai::replace-all
                (cadr-ai::replace-all
                 +export-html-template-css+
                 "{{THEME_VARS}}" theme-vars)
                "{{BODY_BG}}" page-background)
               "{{CONTAINER_BG}}" card-background)
              "{{INFO_BG}}" info-background))
           (html
             (cadr-ai::replace-all
              (cadr-ai::replace-all
               (cadr-ai::replace-all
                (cadr-ai::replace-all
                 (cadr-ai::replace-all
                  +export-html-template+
                  "{{CSS}}" css)
                 "{{JS}}" +export-html-template-js+)
                "{{SESSION_DATA}}" encoded-data)
               "{{MARKED_JS}}" +export-html-marked-js+)
              "{{HIGHLIGHT_JS}}" +export-html-highlight-js+)))
      (ensure-directories-exist path)
      (with-open-file
          (stream path
                  :direction :output
                  :if-exists :supersede
                  :if-does-not-exist :create
                  :external-format :utf-8)
        (write-string html stream))
      (pathname path))))
