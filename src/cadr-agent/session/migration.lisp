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
    (cadr-ai::parse-json-object-fields
     line
     (lambda (key value)
       (session-record-put entry key value)))
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
                 (usage-from-json usage-object))
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
                 (usage-from-json usage-object)))))
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
