(in-package #:cadr-agent)

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
