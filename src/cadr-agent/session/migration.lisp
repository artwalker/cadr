(in-package #:cadr-agent)

(defconstant +session-seen-parent-id+ 1)
(defconstant +session-seen-target-id+ 2)
(defconstant +session-seen-tokens-before+ 4)
(defconstant +session-seen-content+ 8)

(defun mark-session-seen (entry bit)
  (setf (session-entry-%seen entry)
        (logior (session-entry-%seen entry) bit)))

(defun session-seen-p (entry bit)
  (logtest bit (session-entry-%seen entry)))

(defun session-record-put (entry key value)
  (when (plusp (length key))
    (case (char key 0)
      (#\t
       (cond
         ((or (eq key "type") (string= key "type"))
          (setf (session-entry-type entry) value))
         ((or (eq key "timestamp") (string= key "timestamp"))
          (setf (session-entry-timestamp entry) value))
         ((string= key "tokensBefore")
          (mark-session-seen entry +session-seen-tokens-before+)
          (setf (session-entry-tokens-before entry) value))
         ((string= key "thinkingLevel")
          (setf (session-entry-thinking-level entry) value))
         ((string= key "targetId")
          (mark-session-seen entry +session-seen-target-id+)
          (setf (session-entry-target-id entry) value))))
      (#\i
       (when (or (eq key "id") (string= key "id"))
         (setf (session-entry-id entry) value)))
      (#\p
       (cond
         ((or (eq key "parentId") (string= key "parentId"))
          (mark-session-seen entry +session-seen-parent-id+)
          (setf (session-entry-parent-id entry) value))
         ((or (eq key "provider") (string= key "provider"))
          (setf (session-entry-provider entry) value))))
      (#\m
       (cond
         ((or (eq key "message") (string= key "message"))
          (setf (session-entry-message entry) value))
         ((string= key "modelId")
          (setf (session-entry-model-id entry) value))))
      (#\s
       (cond
         ((or (eq key "summary") (string= key "summary"))
          (setf (session-entry-summary entry) value))
         ((string= key "sourceIds")
          (setf (session-entry-source-ids entry) value))))
      (#\f
       (cond
         ((string= key "firstKeptEntryId")
          (setf (session-entry-first-kept-id entry) value))
         ((string= key "fromId")
          (setf (session-entry-from-id entry) value))
         ((string= key "fromHook")
          (setf (session-entry-from-hook-p entry)
                (eq t value)))))
      (#\a
       (when (string= key "activeToolNames")
         (setf (session-entry-active-tool-names entry) value)))
      (#\d
       (cond
         ((or (eq key "details") (string= key "details"))
          (setf (session-entry-details entry) value))
         ((or (eq key "data") (string= key "data"))
          (setf (session-entry-data entry) value))
         ((or (eq key "display") (string= key "display"))
          (setf (session-entry-display-p entry) (eq t value)))))
      (#\u
       (when (or (eq key "usage") (string= key "usage"))
         (setf (session-entry-usage entry) value)))
      (#\c
       (cond
         ((string= key "customType")
          (setf (session-entry-custom-type entry) value))
         ((or (eq key "content") (string= key "content"))
          (mark-session-seen entry +session-seen-content+)
          (setf (session-entry-content entry) value))))
      (#\l
       (when (or (eq key "label") (string= key "label"))
         (setf (session-entry-label entry) value)))
      (#\n
       (when (or (eq key "name") (string= key "name"))
         (setf (session-entry-name entry) value)))
      (#\r
       (when (string= key "retainedTail")
         (setf (session-entry-retained-tail entry) value))))))

(defun parse-session-record (line)
  (let ((entry (make-session-entry)))
    (labels
        ((usage-or-hash (value)
           (cond
             ((or (null value)
                  (cadr-ai::json-null-p value))
              nil)
             ((typep value 'cadr-ai:usage) value)
             ((hash-table-p value)
              (usage-from-json value))
             (t value)))
         (put-cost-field (cost field value)
           (let ((amount (coerce (or value 0) 'double-float)))
             (cond
               ((or (eq field "input") (string= field "input"))
                (setf (cadr-ai:cost-input cost) amount))
               ((or (eq field "output") (string= field "output"))
                (setf (cadr-ai:cost-output cost) amount))
               ((or (eq field "cacheRead")
                    (string= field "cacheRead")
                    (string= field "cache_read"))
                (setf (cadr-ai:cost-cache-read cost) amount))
               ((or (eq field "cacheWrite")
                    (string= field "cacheWrite")
                    (string= field "cache_write"))
                (setf (cadr-ai:cost-cache-write cost) amount))
               ((or (eq field "total") (string= field "total"))
                (setf (cadr-ai:cost-total cost) amount)))))
         (visit-cost ()
           (let ((cost (cadr-ai:make-cost)))
             (values
              (lambda (field value)
                (put-cost-field cost field value))
              (lambda () cost))))
         (put-usage-field (usage field value)
           (cond
             ((or (eq field "input") (string= field "input"))
              (setf (cadr-ai:usage-input usage) (or value 0)))
             ((or (eq field "output") (string= field "output"))
              (setf (cadr-ai:usage-output usage) (or value 0)))
             ((or (eq field "cacheRead")
                  (string= field "cacheRead")
                  (string= field "cache_read"))
              (setf (cadr-ai:usage-cache-read usage) (or value 0)))
             ((or (eq field "cacheWrite")
                  (string= field "cacheWrite")
                  (string= field "cache_write"))
              (setf (cadr-ai:usage-cache-write usage)
                    (or value 0)))
             ((or (eq field "reasoning")
                  (string= field "reasoning"))
              (setf (cadr-ai:usage-reasoning usage) value))
             ((or (eq field "total") (string= field "total"))
              (setf (cadr-ai:usage-total usage) (or value 0)))
             ((or (eq field "cost") (string= field "cost"))
              (setf (cadr-ai:usage-cost usage)
                    (cond
                      ((typep value 'cadr-ai:cost) value)
                      ((hash-table-p value)
                       (cadr-ai:make-cost
                        :input (usage-cost-amount value "input")
                        :output (usage-cost-amount value "output")
                        :cache-read
                        (usage-cost-amount
                         value "cacheRead" "cache_read")
                        :cache-write
                        (usage-cost-amount
                         value "cacheWrite" "cache_write")
                        :total
                        (usage-cost-amount value "total")))
                      (t (cadr-ai:make-cost)))))))
         (visit-usage ()
           (let ((usage (cadr-ai:make-usage)))
             (values
              (lambda (field value)
                (put-usage-field usage field value))
              (lambda () usage))))
         (keep-extra (bag key value)
           (when value
             (setf (session-json-message-extra bag)
                   (list* key value
                          (session-json-message-extra bag)))))
         (put-message-field (bag field value)
           (when (plusp (length field))
             (case (char field 0)
               (#\r
                (cond
                  ((or (eq field "role") (string= field "role"))
                   (setf (session-json-message-role bag) value))
                  ((or (eq field "responseId")
                       (string= field "responseId")
                       (string= field "response_id"))
                   (keep-extra bag :response-id value))
                  ((or (eq field "rawStopReason")
                       (string= field "rawStopReason")
                       (string= field "raw_stop_reason"))
                   (keep-extra bag :raw-stop-reason value))))
               (#\t
                (cond
                  ((or (eq field "type") (string= field "type"))
                   (unless (session-json-message-role bag)
                     (setf (session-json-message-role bag) value)))
                  ((or (eq field "timestamp")
                       (string= field "timestamp"))
                   (setf (session-json-message-timestamp bag)
                         value))
                  ((or (eq field "toolCallId")
                       (string= field "toolCallId")
                       (string= field "tool_call_id"))
                   (keep-extra bag :tool-call-id value))
                  ((or (eq field "toolName")
                       (string= field "toolName")
                       (string= field "tool_name"))
                   (keep-extra bag :tool-name value))
                  ((or (eq field "truncated")
                       (string= field "truncated"))
                   (keep-extra bag :truncated value))))
               (#\c
                (cond
                  ((or (eq field "content")
                       (string= field "content"))
                   (setf (session-json-message-content bag) value))
                  ((or (eq field "command")
                       (string= field "command"))
                   (keep-extra bag :command value))
                  ((or (eq field "cancelled")
                       (string= field "cancelled"))
                   (keep-extra bag :cancelled value))))
               (#\a
                (when (or (eq field "api") (string= field "api"))
                  (keep-extra bag :api value)))
               (#\p
                (when (or (eq field "provider")
                          (string= field "provider"))
                  (keep-extra bag :provider value)))
               (#\m
                (when (or (eq field "model") (string= field "model"))
                  (keep-extra bag :model value)))
               (#\u
                (when (or (eq field "usage") (string= field "usage"))
                  (setf (session-json-message-usage bag)
                        (usage-or-hash value))))
               (#\s
                (when (or (eq field "stopReason")
                          (string= field "stopReason")
                          (string= field "stop_reason"))
                  (keep-extra bag :stop-reason value)))
               (#\e
                (cond
                  ((or (eq field "errorMessage")
                       (string= field "errorMessage")
                       (string= field "error_message"))
                   (keep-extra bag :error-message value))
                  ((or (eq field "exitCode")
                       (string= field "exitCode")
                       (string= field "exit_code"))
                   (keep-extra bag :exit-code value))
                  ((or (eq field "excludeFromContext")
                       (string= field "excludeFromContext")
                       (string= field "exclude_from_context"))
                   (keep-extra bag :exclude-from-context value))))
               (#\d
                (cond
                  ((or (eq field "diagnostics")
                       (string= field "diagnostics"))
                   (keep-extra bag :diagnostics value))
                  ((or (eq field "details")
                       (string= field "details"))
                   (keep-extra bag :details value))))
               (#\i
                (when (or (eq field "isError")
                          (string= field "isError")
                          (string= field "is_error"))
                  (keep-extra bag :is-error value)))
               (#\o
                (when (or (eq field "output")
                          (string= field "output"))
                  (keep-extra bag :output value)))
               (#\f
                (when (or (eq field "fullOutputPath")
                          (string= field "fullOutputPath")
                          (string= field "full_output_path"))
                  (keep-extra bag :full-output-path value))))))
         (visit-message ()
           (let ((bag (make-session-json-message)))
             (values
              (lambda (field value)
                (put-message-field bag field value))
              (lambda () bag))))
         (keep-block-extra (block key value)
           (when value
             (setf (session-json-block-extra block)
                   (list* key value
                          (session-json-block-extra block)))))
         (put-block-field (block field value)
           (when (plusp (length field))
             (case (char field 0)
               (#\t
                (cond
                  ((or (eq field "type") (string= field "type"))
                   (setf (session-json-block-type block) value))
                  ((or (eq field "text") (string= field "text"))
                   (setf (session-json-block-primary block) value))
                  ((or (eq field "thinking")
                       (string= field "thinking"))
                   (setf (session-json-block-primary block) value))
                  ((or (eq field "thoughtSignature")
                       (string= field "thoughtSignature")
                       (string= field "thought_signature"))
                   (keep-block-extra
                    block :thought-signature value))))
               (#\s
                (when (or (eq field "signature")
                          (string= field "signature"))
                  (setf (session-json-block-secondary block)
                        value)))
               (#\r
                (when (or (eq field "redacted")
                          (string= field "redacted"))
                  (keep-block-extra block :redacted value)))
               (#\d
                (when (or (eq field "data") (string= field "data"))
                  (setf (session-json-block-primary block) value)))
               (#\m
                (when (or (eq field "mimeType")
                          (string= field "mimeType")
                          (string= field "mime_type"))
                  (keep-block-extra block :mime-type value)))
               (#\i
                (when (or (eq field "id") (string= field "id"))
                  (setf (session-json-block-primary block) value)))
               (#\n
                (when (or (eq field "name") (string= field "name"))
                  (setf (session-json-block-secondary block)
                        value)))
               (#\a
                (when (or (eq field "arguments")
                          (string= field "arguments"))
                  (keep-block-extra block :arguments value))))))
         (finish-content-block (block)
           (let ((type (session-json-block-type block))
                 (primary (session-json-block-primary block))
                 (secondary (session-json-block-secondary block))
                 (extra (session-json-block-extra block)))
             (cond
               ((string= type "text")
                (cadr-ai:make-text-content
                 :text (or primary "")
                 :signature secondary))
               ((string= type "thinking")
                (cadr-ai:make-thinking-content
                 :thinking (or primary "")
                 :signature secondary
                 :redacted-p (eq t (getf extra :redacted))))
               ((string= type "image")
                (cadr-ai:make-image-content
                 :mime-type
                 (or (getf extra :mime-type) "image/png")
                 :data (or primary "")))
               ((member type '("toolCall" "tool_call")
                        :test #'string=)
                (cadr-ai:make-tool-call
                 :id (or primary "")
                 :name (or secondary "")
                 :arguments
                 (let ((arguments (getf extra :arguments)))
                   (cond
                     ((cadr-ai::json-object-pairs-p arguments)
                      arguments)
                     ((hash-table-p arguments)
                      arguments)
                     (t '(:json-object))))
                 :thought-signature
                 (getf extra :thought-signature)))
               (t
                (error "Unknown content block type: ~S" type)))))
         (visit-content-block ()
           (let ((block (make-session-json-block)))
             (values
              (lambda (field value)
                (put-block-field block field value))
              (lambda ()
                (finish-content-block block)))))
         (visit-arguments ()
           (let ((pairs nil))
             (values
              (lambda (field value)
                (setf pairs (list* field value pairs)))
              (lambda ()
                (cons :json-object pairs)))))
         (nest (key)
           (cond
             ((or (eq key "message") (string= key "message"))
              (visit-message))
             ((or (eq key "usage") (string= key "usage"))
              (visit-usage))
             ((or (eq key "cost") (string= key "cost"))
              (visit-cost))
             ((or (eq key "arguments") (string= key "arguments"))
              (visit-arguments))
             ((or (eq key "content") (string= key "content"))
              (values #'visit-content-block nil :array)))))
      (cadr-ai::parse-json-object-fields
       line
       (lambda (key value)
         (session-record-put entry key value))
       #'nest))
    entry))

(defun parse-session-line (line path line-number &key raw-hash-p)
  (handler-case
      (if raw-hash-p
          (cadr-ai::parse-json line)
          (parse-session-record line))
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
        (line-number 0)
        (header nil)
        (raw-hash-p t))
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
                             line path line-number
                             :raw-hash-p raw-hash-p)
                          (session-error () nil))))
                  (when object
                    (unless header
                      (setf header object)
                      (setf raw-hash-p
                            (let ((version
                                    (cadr-ai::json-get
                                     object "version" 1)))
                              (or (not (integerp version))
                                  (< version 3)))))
                    (push object objects)))))))
      (session-error (condition)
        (error condition))
      (error (cause)
        (session-failure
         path line-number "Cannot load session: ~A" cause)))
    (unless objects
      (session-failure path 1 "Session file has no header"))
    (nreverse objects)))

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

(defun persist-migrated-session (objects path)
  (cadr-core:call-with-atomic-output-file
   path
   (lambda (stream)
     (dolist (object objects)
       (write-jsonl-object stream object)))
   :durability :flush))

(defun vector-of-strings-p (value)
  (and (vectorp value)
       (every #'stringp value)))

(defun json-null-to-nil (value)
  (if (cadr-ai::json-null-p value)
      nil
      value))

(defun session-entry-from-hash (object)
  (let ((entry (make-session-entry)))
    (maphash
     (lambda (key value)
       (session-record-put entry key value))
     object)
    entry))

(defun require-session-slot (value name path line-number)
  (when (null value)
    (session-failure
     path line-number
     "Session record is missing ~A" name))
  value)

(defun finalize-session-entry
    (entry path line-number by-id)
  (let* ((type
           (let ((raw (session-entry-type entry)))
             (cond
               ((keywordp raw) raw)
               ((stringp raw)
                (intern
                 (string-upcase
                  (substitute #\- #\_ raw))
                 "KEYWORD"))
               (t raw))))
         (id (session-entry-id entry))
         (parent-id
           (progn
             (unless (session-seen-p
                      entry +session-seen-parent-id+)
               (session-failure
                path line-number
                "Session record is missing parentId"))
             (json-null-to-nil
              (session-entry-parent-id entry))))
         (timestamp-value
           (require-session-slot
            (session-entry-timestamp entry)
            "timestamp" path line-number))
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
          '(:message
            :thinking-level-change
            :model-change
            :active-tools-change
            :compaction
            :branch-summary
            :custom
            :custom-message
            :label
            :session-info
            :leaf))
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
    (setf (session-entry-type entry) type
          (session-entry-parent-id entry) parent-id
          (session-entry-timestamp entry) timestamp)
    (let ((usage-object (session-entry-usage entry)))
      (case type
        (:message
         (setf
          (session-entry-message entry)
          (message-from-json
           (require-session-slot
            (session-entry-message entry)
            "message" path line-number))))
        (:thinking-level-change
         (let ((value
                 (require-session-slot
                  (session-entry-thinking-level entry)
                  "thinkingLevel" path line-number)))
           (unless (stringp value)
             (session-failure
              path line-number
              "Invalid thinking level entry at line ~D"
              line-number))))
        (:model-change
         (let ((provider
                 (require-session-slot
                  (session-entry-provider entry)
                  "provider" path line-number))
               (model-id
                 (require-session-slot
                  (session-entry-model-id entry)
                  "modelId" path line-number)))
           (unless (and (stringp provider)
                        (stringp model-id))
             (session-failure
              path line-number
              "Invalid model change entry at line ~D"
              line-number))))
        (:active-tools-change
         (let ((names
                 (require-session-slot
                  (session-entry-active-tool-names entry)
                  "activeToolNames" path line-number)))
           (unless (vector-of-strings-p names)
             (session-failure
              path line-number
              "Invalid active tools entry at line ~D"
              line-number))
           (setf
            (session-entry-active-tool-names entry)
            (coerce names 'list))))
        (:compaction
         (let* ((summary
                  (require-session-slot
                   (session-entry-summary entry)
                   "summary" path line-number))
                (source-ids
                  (or
                   (session-entry-source-ids entry)
                   #()))
                (first-kept-id
                  (require-session-slot
                   (session-entry-first-kept-id entry)
                   "firstKeptEntryId" path line-number))
                (tokens-before
                  (progn
                    (unless
                        (session-seen-p
                         entry
                         +session-seen-tokens-before+)
                      (session-failure
                       path line-number
                       "Session record is missing tokensBefore"))
                    (session-entry-tokens-before entry))))
           (unless
               (and
                (stringp summary)
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
            (session-entry-source-ids entry)
            (coerce source-ids 'list)
            (session-entry-tokens-before entry)
            tokens-before
            (session-entry-usage entry)
            (and usage-object
                 (if (hash-table-p usage-object)
                     (usage-from-json usage-object)
                     usage-object))
            (session-entry-retained-tail entry)
            (let ((tail
                    (session-entry-retained-tail entry)))
              (and
               (vectorp tail)
               (loop for message across tail
                     collect
                     (message-from-json
                      message)))))))
        (:branch-summary
         (let ((from-id
                 (require-session-slot
                  (session-entry-from-id entry)
                  "fromId" path line-number))
               (summary
                 (require-session-slot
                  (session-entry-summary entry)
                  "summary" path line-number)))
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
            (session-entry-usage entry)
            (and usage-object
                 (if (hash-table-p usage-object)
                     (usage-from-json usage-object)
                     usage-object)))))
        (:custom
         (let ((custom-type
                 (require-session-slot
                  (session-entry-custom-type entry)
                  "customType" path line-number)))
           (unless (stringp custom-type)
             (session-failure
              path line-number
              "Invalid custom entry at line ~D"
              line-number))))
        (:custom-message
         (let ((custom-type
                 (require-session-slot
                  (session-entry-custom-type entry)
                  "customType" path line-number))
               (content
                 (progn
                   (unless
                       (session-seen-p
                        entry +session-seen-content+)
                     (session-failure
                      path line-number
                      "Session record is missing content"))
                   (session-entry-content entry))))
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
            (session-entry-content entry)
            (cond
              ((stringp content) content)
              ((null content) nil)
              (t
               (content-blocks-from-json
                content))))))
        (:label
         (let ((target-id
                 (progn
                   (unless
                       (session-seen-p
                        entry +session-seen-target-id+)
                     (session-failure
                      path line-number
                      "Session record is missing targetId"))
                   (session-entry-target-id entry)))
               (label
                 (json-null-to-nil
                  (session-entry-label entry))))
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
        (:session-info
         (let ((name
                 (json-null-to-nil
                  (session-entry-name entry))))
           (unless (or (null name) (stringp name))
             (session-failure
              path line-number
              "Invalid session info at line ~D"
              line-number))
           (setf (session-entry-name entry) name)))
        (:leaf
         (let ((target-id
                 (progn
                   (unless
                       (session-seen-p
                        entry +session-seen-target-id+)
                     (session-failure
                      path line-number
                      "Session record is missing targetId"))
                   (json-null-to-nil
                    (session-entry-target-id entry)))))
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

(defun record-to-session-entry
    (object path line-number by-id)
  (cond
    ((session-entry-p object)
     (finalize-session-entry
      object path line-number by-id))
    ((hash-table-p object)
     (finalize-session-entry
      (session-entry-from-hash object)
      path line-number by-id))
    (t
     (session-failure
      path line-number
      "Session record must be an object"))))

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
