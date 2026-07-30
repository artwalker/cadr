(in-package #:pi-agent)

(defstruct session-entry
  type
  id
  parent-id
  timestamp
  message
  summary
  (source-ids nil :type list)
  first-kept-id
  (tokens-before 0 :type (integer 0 *)))

(defstruct (session
            (:constructor %make-session))
  id
  timestamp
  cwd
  path
  (%entries nil :type list)
  (by-id (make-hash-table :test #'equal) :type hash-table)
  leaf-id
  (lock (sb-thread:make-mutex :name "pi-session")))

(defun canonical-session-cwd (cwd)
  (namestring
   (truename (uiop:ensure-directory-pathname cwd))))

(defun default-session-directory ()
  (merge-pathnames
   ".pi-cl/sessions/"
   (user-homedir-pathname)))

(defun make-session-id ()
  (string-downcase
   (format nil "~36R-~36R"
           (pi-ai::unix-milliseconds)
           (random most-positive-fixnum))))

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
     (let ((copy (pi-ai::json-object)))
       (maphash
        (lambda (key item)
          (pi-ai::json-put
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
     (let ((object (pi-ai::json-object)))
       (loop for (key item) on value by #'cddr
             do (pi-ai::json-put
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
    ((typep block 'pi-ai:text-content)
     (let ((object
             (pi-ai::json-object
              "type" "text"
              "text" (pi-ai:text-content-text block))))
       (when (pi-ai:text-content-signature block)
         (pi-ai::json-put
          object "signature"
          (pi-ai:text-content-signature block)))
       object))
    ((typep block 'pi-ai:thinking-content)
     (let ((object
             (pi-ai::json-object
              "type" "thinking"
              "thinking"
              (pi-ai:thinking-content-thinking block)
              "redacted"
              (pi-ai:thinking-content-redacted-p block))))
       (when (pi-ai:thinking-content-signature block)
         (pi-ai::json-put
          object "signature"
          (pi-ai:thinking-content-signature block)))
       object))
    ((typep block 'pi-ai:image-content)
     (pi-ai::json-object
      "type" "image"
      "mime_type" (pi-ai:image-content-mime-type block)
      "data" (pi-ai:image-content-data block)))
    ((typep block 'pi-ai:tool-call)
     (let ((object
             (pi-ai::json-object
              "type" "tool_call"
              "id" (pi-ai:tool-call-id block)
              "name" (pi-ai:tool-call-name block)
              "arguments"
              (json-safe-value
               (pi-ai:tool-call-arguments block)))))
       (when (pi-ai:tool-call-thought-signature block)
         (pi-ai::json-put
          object "thought_signature"
          (pi-ai:tool-call-thought-signature block)))
       object))
    (t
     (error "Unsupported session content block: ~S" block))))

(defun content-blocks-to-json (blocks)
  (map 'vector #'content-block-to-json blocks))

(defun usage-to-json (usage)
  (let ((object
          (pi-ai::json-object
           "input" (pi-ai:usage-input usage)
           "output" (pi-ai:usage-output usage)
           "cache_read" (pi-ai:usage-cache-read usage)
           "cache_write" (pi-ai:usage-cache-write usage)
           "total" (pi-ai:usage-total usage))))
    (when (pi-ai:usage-reasoning usage)
      (pi-ai::json-put
       object "reasoning" (pi-ai:usage-reasoning usage)))
    object))

(defun message-to-json (message)
  (cond
    ((typep message 'pi-ai:user-message)
     (pi-ai::json-object
      "type" "user"
      "content"
      (let ((content (pi-ai:user-message-content message)))
        (if (stringp content)
            content
            (content-blocks-to-json content)))
      "timestamp" (pi-ai:user-message-timestamp message)))
    ((typep message 'pi-ai:assistant-message)
     (let ((object
             (pi-ai::json-object
              "type" "assistant"
              "content"
              (content-blocks-to-json
               (pi-ai:assistant-message-content message))
              "api"
              (symbol-json-name
               (pi-ai:assistant-message-api message))
              "provider"
              (symbol-json-name
               (pi-ai:assistant-message-provider message))
              "model" (pi-ai:assistant-message-model message)
              "usage"
              (usage-to-json
               (pi-ai:assistant-message-usage message))
              "stop_reason"
              (symbol-json-name
               (pi-ai:assistant-message-stop-reason message))
              "timestamp"
              (pi-ai:assistant-message-timestamp message))))
       (when (pi-ai:assistant-message-response-id message)
         (pi-ai::json-put
          object "response_id"
          (pi-ai:assistant-message-response-id message)))
       (when (pi-ai:assistant-message-error-message message)
         (pi-ai::json-put
          object "error_message"
          (pi-ai:assistant-message-error-message message)))
       (when (pi-ai:assistant-message-raw-stop-reason message)
         (pi-ai::json-put
          object "raw_stop_reason"
          (pi-ai:assistant-message-raw-stop-reason message)))
       object))
    ((typep message 'pi-ai:tool-result-message)
     (pi-ai::json-object
      "type" "tool_result"
      "tool_call_id"
      (pi-ai:tool-result-message-tool-call-id message)
      "tool_name"
      (pi-ai:tool-result-message-tool-name message)
      "content"
      (content-blocks-to-json
       (pi-ai:tool-result-message-content message))
      "details"
      (json-safe-value
       (pi-ai:tool-result-message-details message))
      "is_error"
      (pi-ai:tool-result-message-is-error message)
      "timestamp"
      (pi-ai:tool-result-message-timestamp message)))
    (t
     (error "Unsupported session message: ~S" message))))

(defun keyword-from-json (value)
  (unless (stringp value)
    (error "Expected a symbolic JSON string"))
  (intern (string-upcase value) "KEYWORD"))

(defun content-block-from-json (object)
  (let ((type (pi-ai::json-get object "type")))
    (cond
      ((string= type "text")
       (pi-ai:make-text-content
        :text (pi-ai::json-get object "text")
        :signature (pi-ai::json-get object "signature")))
      ((string= type "thinking")
       (pi-ai:make-thinking-content
        :thinking (pi-ai::json-get object "thinking")
        :signature (pi-ai::json-get object "signature")
        :redacted-p
        (eq t (pi-ai::json-get object "redacted"))))
      ((string= type "image")
       (pi-ai:make-image-content
        :mime-type (pi-ai::json-get object "mime_type")
        :data (pi-ai::json-get object "data")))
      ((string= type "tool_call")
       (pi-ai:make-tool-call
        :id (pi-ai::json-get object "id")
        :name (pi-ai::json-get object "name")
        :arguments
        (pi-ai::json-get object "arguments")
        :thought-signature
        (pi-ai::json-get object "thought_signature")))
      (t
       (error "Unknown content block type: ~S" type)))))

(defun content-blocks-from-json (value)
  (unless (vectorp value)
    (error "Session content must be an array"))
  (loop for object across value
        collect (content-block-from-json object)))

(defun usage-from-json (object)
  (pi-ai:make-usage
   :input (or (pi-ai::json-get object "input") 0)
   :output (or (pi-ai::json-get object "output") 0)
   :cache-read (or (pi-ai::json-get object "cache_read") 0)
   :cache-write (or (pi-ai::json-get object "cache_write") 0)
   :reasoning (pi-ai::json-get object "reasoning")
   :total (pi-ai::json-get object "total")))

(defun message-from-json (object)
  (let ((type (pi-ai::json-get object "type"))
        (content (pi-ai::json-get object "content")))
    (cond
      ((string= type "user")
       (pi-ai:make-user-message
        :content
        (if (stringp content)
            content
            (content-blocks-from-json content))
        :timestamp (pi-ai::json-get object "timestamp")))
      ((string= type "assistant")
       (pi-ai:make-assistant-message
        :content (content-blocks-from-json content)
        :api (keyword-from-json
              (pi-ai::json-get object "api"))
        :provider (keyword-from-json
                   (pi-ai::json-get object "provider"))
        :model (pi-ai::json-get object "model")
        :response-id (pi-ai::json-get object "response_id")
        :usage
        (usage-from-json
         (pi-ai::json-get object "usage"))
        :stop-reason
        (keyword-from-json
         (pi-ai::json-get object "stop_reason"))
        :error-message
        (pi-ai::json-get object "error_message")
        :raw-stop-reason
        (pi-ai::json-get object "raw_stop_reason")
        :timestamp (pi-ai::json-get object "timestamp")))
      ((string= type "tool_result")
       (pi-ai:make-tool-result-message
        :tool-call-id
        (pi-ai::json-get object "tool_call_id")
        :tool-name
        (pi-ai::json-get object "tool_name")
        :content (content-blocks-from-json content)
        :details (pi-ai::json-get object "details")
        :is-error
        (eq t (pi-ai::json-get object "is_error"))
        :timestamp (pi-ai::json-get object "timestamp")))
      (t
       (error "Unknown message type: ~S" type)))))

(defun write-jsonl-object (stream object)
  (write-string (pi-ai::stringify-json object) stream)
  (terpri stream)
  (finish-output stream))

(defun message-timestamp (message)
  (etypecase message
    (pi-ai:user-message
     (pi-ai:user-message-timestamp message))
    (pi-ai:assistant-message
     (pi-ai:assistant-message-timestamp message))
    (pi-ai:tool-result-message
     (pi-ai:tool-result-message-timestamp message))))

(defun make-session-entry-id (by-id)
  (loop repeat 100
        for id = (make-session-id)
        unless (gethash id by-id)
          return id
        finally
           (session-failure
            nil nil "Cannot allocate a unique session entry id")))

(defun session-entries (session)
  (copy-list (session-%entries session)))

(defun session-entry-to-json (entry)
  (ecase (session-entry-type entry)
    (:message
     (pi-ai::json-object
      "type" "message"
      "id" (session-entry-id entry)
      "parentId" (session-entry-parent-id entry)
      "timestamp" (session-entry-timestamp entry)
      "message" (message-to-json
                 (session-entry-message entry))))
    (:compaction
     (pi-ai::json-object
      "type" "compaction"
      "id" (session-entry-id entry)
      "parentId" (session-entry-parent-id entry)
      "timestamp" (session-entry-timestamp entry)
      "summary" (session-entry-summary entry)
      "sourceIds"
      (coerce (session-entry-source-ids entry) 'vector)
      "firstKeptEntryId"
      (session-entry-first-kept-id entry)
      "tokensBefore"
      (session-entry-tokens-before entry)))))

(defun create-session (&key
                             (directory
                               (default-session-directory))
                             cwd
                             id
                             (timestamp
                               (pi-ai::unix-milliseconds)))
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
    (handler-case
        (with-open-file
            (stream path
                    :direction :output
                    :if-exists :error
                    :if-does-not-exist :create
                    :external-format :utf-8)
          (write-jsonl-object
           stream
           (pi-ai::json-object
            "type" "session"
            "version" 2
            "id" session-id
            "timestamp" timestamp
            "cwd" canonical-cwd)))
      (error (cause)
        (session-failure
         path 1 "Cannot create session: ~A" cause)))
    (%make-session
     :id session-id
     :timestamp timestamp
     :cwd canonical-cwd
     :path path)))

(defun append-session-entry (session entry)
  (sb-thread:with-mutex
      ((session-lock session))
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
         "Cannot append session entry: ~A" cause)))
    (setf (session-%entries session)
          (nconc (session-%entries session)
                 (list entry))
          (gethash (session-entry-id entry)
                   (session-by-id session))
          entry
          (session-leaf-id session)
          (session-entry-id entry)))
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
    (session summary source-ids first-kept-id tokens-before)
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
    :timestamp (pi-ai::unix-milliseconds)
    :summary summary
    :source-ids (copy-list source-ids)
    :first-kept-id first-kept-id
    :tokens-before tokens-before)))

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
      (return-from session-context-entries
        (remove-if-not
         (lambda (entry)
           (eq :message
               (session-entry-type entry)))
         path)))
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
       (remove-if-not
        (lambda (entry)
          (eq :message
              (session-entry-type entry)))
        (subseq path
                first-kept-position
                compaction-position))
       (remove-if-not
        (lambda (entry)
          (eq :message
              (session-entry-type entry)))
        (subseq path
                (1+ compaction-position)))))))

(defun compaction-summary-message (entry)
  (pi-ai:make-user-message
   :content
   (format nil
           "Previous context summary (original entries: ~{~A~^, ~}):~%~A"
           (session-entry-source-ids entry)
           (session-entry-summary entry))
   :timestamp (session-entry-timestamp entry)))

(defun session-messages (session &optional
                                   (leaf-id
                                     (session-leaf-id session)))
  (loop for entry in
          (session-context-entries session leaf-id)
        collect
        (ecase (session-entry-type entry)
          (:message
           (session-entry-message entry))
          (:compaction
           (compaction-summary-message entry)))))

(defun parse-session-line (line path line-number)
  (handler-case
      (pi-ai::parse-json line)
    (error (cause)
      (session-failure
       path line-number
       "Invalid session JSON at line ~D: ~A"
       line-number cause))))

(defun validate-session-header (object path)
  (unless (hash-table-p object)
    (session-failure path 1 "Invalid session header"))
  (let ((version (pi-ai::json-get object "version" 1)))
    (unless
        (and (string= "session"
                      (pi-ai::json-get object "type"))
             (member version '(1 2))
             (stringp (pi-ai::json-get object "id"))
             (integerp (pi-ai::json-get object "timestamp"))
             (stringp (pi-ai::json-get object "cwd")))
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
              (when (eq line :eof)
                (return))
              (incf line-number)
              (handler-case
                  (push
                   (parse-session-line
                    line path line-number)
                   objects)
                (session-error (condition)
                  (if (and (> line-number 1)
                           missing-newline-p)
                      (return)
                      (error condition)))))))
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
    (pi-ai::json-put (first objects) "version" 2)
    (dolist (object (rest objects))
      (unless
          (string= "message"
                   (pi-ai::json-get object "type"))
        (error "Invalid v1 session record"))
      (let ((id (make-session-entry-id by-id)))
        (pi-ai::json-put object "id" id)
        (pi-ai::json-put object "parentId" parent-id)
        (setf (gethash id by-id) t
              parent-id id))))
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

(defun record-to-session-entry
    (object path line-number by-id)
  (unless (hash-table-p object)
    (session-failure
     path line-number "Session record must be an object"))
  (let* ((type (require-json-field
                object "type" path line-number))
         (id (require-json-field
              object "id" path line-number))
         (parent-id
           (require-json-field
            object "parentId" path line-number))
         (timestamp
           (require-json-field
            object "timestamp" path line-number)))
    (unless (and (member type
                         '("message" "compaction")
                         :test #'string=)
                 (stringp id)
                 (or (null parent-id)
                     (stringp parent-id))
                 (integerp timestamp))
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
    (let ((entry
            (cond
              ((string= type "message")
               (make-session-entry
                :type :message
                :id id
                :parent-id parent-id
                :timestamp timestamp
                :message
                (message-from-json
                 (require-json-field
                  object "message" path line-number))))
              (t
               (let ((summary
                       (require-json-field
                        object "summary" path line-number))
                     (source-ids
                       (require-json-field
                        object "sourceIds" path line-number))
                     (first-kept-id
                       (require-json-field
                        object "firstKeptEntryId"
                        path line-number))
                     (tokens-before
                       (require-json-field
                        object "tokensBefore"
                        path line-number)))
                 (unless
                     (and (stringp summary)
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
                 (make-session-entry
                  :type :compaction
                  :id id
                  :parent-id parent-id
                  :timestamp timestamp
                  :summary summary
                  :source-ids (coerce source-ids 'list)
                  :first-kept-id first-kept-id
                  :tokens-before tokens-before))))))
      (setf (gethash id by-id) entry)
      entry)))

(defun load-session (path)
  (let* ((pathname (pathname path))
         (objects (read-session-objects pathname))
         (header
           (validate-session-header
            (first objects) pathname))
         (version (pi-ai::json-get header "version" 1)))
    (when (= version 1)
      (handler-case
          (progn
            (migrate-v1-session-objects objects)
            (persist-migrated-session objects pathname))
        (session-error (condition)
          (error condition))
        (error (cause)
          (session-failure
           pathname nil
           "Cannot migrate v1 session: ~A" cause))))
    (let ((by-id (make-hash-table :test #'equal))
          (entries nil)
          (line-number 1))
      (dolist (object (rest objects))
        (incf line-number)
        (push
         (handler-case
             (record-to-session-entry
              object pathname line-number by-id)
           (session-error (condition)
             (error condition))
           (error (cause)
             (session-failure
              pathname line-number
              "Invalid session record at line ~D: ~A"
              line-number cause)))
         entries))
      (setf entries (nreverse entries))
      (%make-session
       :id (pi-ai::json-get header "id")
       :timestamp (pi-ai::json-get header "timestamp")
       :cwd (pi-ai::json-get header "cwd")
       :path pathname
       :%entries entries
       :by-id by-id
       :leaf-id
       (and entries
            (session-entry-id
             (car (last entries))))))))

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
           for session =
             (handler-case
                 (load-session path)
               (session-error (condition)
                 (if (eql 1
                          (session-error-line condition))
                     (error condition)
                     nil)))
           when (and session
                     (or (null canonical-cwd)
                         (string=
                          canonical-cwd
                          (session-cwd session))))
             collect session)
     #'> :key #'session-timestamp)))

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

(defun html-escape (value)
  (with-output-to-string (output)
    (loop for character across (princ-to-string value)
          do
          (case character
            (#\& (write-string "&amp;" output))
            (#\< (write-string "&lt;" output))
            (#\> (write-string "&gt;" output))
            (#\" (write-string "&quot;" output))
            (#\' (write-string "&#39;" output))
            (t (write-char character output))))))

(defun content-block-display-text (block)
  (cond
    ((typep block 'pi-ai:text-content)
     (pi-ai:text-content-text block))
    ((typep block 'pi-ai:thinking-content)
     (format nil "[thinking] ~A"
             (pi-ai:thinking-content-thinking block)))
    ((typep block 'pi-ai:image-content)
     (format nil "[image ~A, ~D base64 characters]"
             (pi-ai:image-content-mime-type block)
             (length (pi-ai:image-content-data block))))
    ((typep block 'pi-ai:tool-call)
     (format nil "[tool ~A ~A]"
             (pi-ai:tool-call-name block)
             (pi-ai::stringify-json
              (json-safe-value
               (pi-ai:tool-call-arguments block)))))
    (t (princ-to-string block))))

(defun message-display-role-and-text (message)
  (cond
    ((typep message 'pi-ai:user-message)
     (values
      "user"
      (let ((content
              (pi-ai:user-message-content message)))
        (if (stringp content)
            content
            (format nil "~{~A~^~%~}"
                    (mapcar
                     #'content-block-display-text
                     (coerce content 'list)))))))
    ((typep message 'pi-ai:assistant-message)
     (values
      "assistant"
      (format nil "~{~A~^~%~}"
              (mapcar
               #'content-block-display-text
               (pi-ai:assistant-message-content message)))))
    ((typep message 'pi-ai:tool-result-message)
     (values
      (format nil "tool-result:~A"
              (pi-ai:tool-result-message-tool-name
               message))
      (format nil "~{~A~^~%~}"
              (mapcar
               #'content-block-display-text
               (pi-ai:tool-result-message-content
                message)))))))

(defun export-session-html (session path)
  (let ((children (make-hash-table :test #'equal))
        (roots nil))
    (dolist (entry (session-%entries session))
      (let ((parent-id
              (session-entry-parent-id entry)))
        (if parent-id
            (setf (gethash parent-id children)
                  (nconc (gethash parent-id children)
                         (list entry)))
            (setf roots (nconc roots (list entry))))))
    (ensure-directories-exist path)
    (with-open-file
        (stream path
                :direction :output
                :if-exists :supersede
                :if-does-not-exist :create
                :external-format :utf-8)
      (write-string
       "<!doctype html><html><head><meta charset=\"utf-8\"><title>"
       stream)
      (write-string
       (html-escape (session-id session)) stream)
      (write-string
       "</title><style>body{font:16px system-ui;max-width:960px;margin:2rem auto;padding:0 1rem}ol{border-left:1px solid #bbb}.node{margin:.8rem 0;padding:.7rem;background:#f6f6f6;border-radius:.4rem}.meta{color:#666;font:12px monospace}.content{white-space:pre-wrap}.compaction{background:#fff3cd}</style></head><body><h1>Session "
       stream)
      (write-string (html-escape (session-id session)) stream)
      (write-string "</h1>" stream)
      (labels
          ((render-entry (entry)
             (format stream
                     "<li><article class=\"node ~A\"><div class=\"meta\">id=~A parent=~A timestamp=~A</div>"
                     (if (eq :compaction
                             (session-entry-type entry))
                         "compaction"
                         "message")
                     (html-escape (session-entry-id entry))
                     (html-escape
                      (or (session-entry-parent-id entry)
                          "root"))
                     (html-escape
                      (session-entry-timestamp entry)))
             (if (eq :compaction
                     (session-entry-type entry))
                 (progn
                   (format stream
                           "<strong>compaction</strong><div class=\"meta\">sources=~A first-kept=~A tokens-before=~D</div><div class=\"content\">"
                           (html-escape
                            (format nil "~{~A~^,~}"
                                    (session-entry-source-ids
                                     entry)))
                           (html-escape
                            (session-entry-first-kept-id
                             entry))
                           (session-entry-tokens-before
                            entry))
                   (write-string
                    (html-escape
                     (session-entry-summary entry))
                    stream))
                 (multiple-value-bind (role text)
                     (message-display-role-and-text
                      (session-entry-message entry))
                   (format stream
                           "<strong>~A</strong><div class=\"content\">~A"
                           (html-escape role)
                           (html-escape text))))
             (write-string "</div></article>" stream)
             (let ((descendants
                     (gethash
                      (session-entry-id entry)
                      children)))
               (when descendants
                 (write-string "<ol>" stream)
                 (dolist (child descendants)
                   (render-entry child))
                 (write-string "</ol>" stream)))
             (write-string "</li>" stream)))
        (write-string "<ol>" stream)
        (dolist (root roots)
          (render-entry root))
        (write-string "</ol></body></html>" stream)))
    (pathname path)))
