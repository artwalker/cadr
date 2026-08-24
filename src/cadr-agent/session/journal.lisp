(in-package #:cadr-agent)

(defun message-timestamp (message)
  (etypecase message
    (cadr-ai:user-message
     (cadr-ai:user-message-timestamp message))
    (cadr-ai:assistant-message
     (cadr-ai:assistant-message-timestamp message))
    (cadr-ai:tool-result-message
     (cadr-ai:tool-result-message-timestamp message))
    (bash-execution-message
     (bash-execution-message-timestamp message))))

(defun make-session-entry-id (by-id)
  ;; Process *random-state*, seeded once per image. Reseeding from the
  ;; OS on every attempt dominated journal_append.
  (loop repeat 100
        for id =
          (string-downcase
           (format nil "~8,'0X"
                   (random #x100000000)))
        unless (gethash id by-id)
          return id
        finally
           (session-failure
            nil nil "Cannot allocate a unique session entry id")))

(defun session-entries (session)
  (copy-list (session-%entries session)))

(defun session-entry-count (session)
  ;; pi SessionManager.getEntries().length
  (length (session-%entries session)))

(defun put-session-details-and-usage (base entry)
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
  base)

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
     (put-session-details-and-usage base entry)
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
     (put-session-details-and-usage base entry))
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
         (cadr-ai:assistant-message-timestamp message))
        ((typep message 'bash-execution-message)
         (bash-execution-message-timestamp message))))))

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

(defun close-session-journal-stream (session)
  (let ((stream (session-%journal-stream session)))
    (when (streamp stream)
      (ignore-errors
       (when (open-stream-p stream)
         (finish-output stream)
         (close stream))))
    (setf (session-%journal-stream session) nil)))

(defun open-session-journal-stream (session &key create-p)
  (close-session-journal-stream session)
  (setf
   (session-%journal-stream session)
   (open
    (session-path session)
    :direction :output
    :element-type '(unsigned-byte 8)
    :if-exists (if create-p :error :append)
    :if-does-not-exist (if create-p :create :error))))

(defun session-journal-stream (session &key create-p)
  (let ((stream (session-%journal-stream session)))
    (if (and (not create-p)
             (streamp stream)
             (open-stream-p stream))
        stream
        (open-session-journal-stream session :create-p create-p))))

(defun append-session-entry (session entry)
  (sb-thread:with-mutex
      ((session-lock session))
    (let ((buffer
            (or (session-%journal-octets session)
                (setf (session-%journal-octets session)
                      (make-session-octet-buffer)))))
    (cond
      ((session-persisted-p session)
       (handler-case
           (write-session-entry-jsonl
            (session-journal-stream session)
            entry
            buffer)
         (error (cause)
           (close-session-journal-stream session)
           (session-failure
            (session-path session) nil
            "Cannot append session entry: ~A" cause))))
      ((assistant-session-entry-p entry)
       (handler-case
           (let ((stream
                   (session-journal-stream session :create-p t)))
             (write-jsonl-object
              stream (session-header-to-json session) buffer)
             (dolist
                 (buffered-entry
                  (append
                   (session-%entries session)
                   (list entry)))
               (write-session-entry-jsonl
                stream buffered-entry buffer)))
         (error (cause)
           (close-session-journal-stream session)
           (session-failure
            (session-path session) nil
            "Cannot create session: ~A" cause)))
       (setf (session-persisted-p session) t))))
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
     (session-entry-id entry)
     (session-%messages-leaf session) nil
     (session-%messages-cache session) nil)
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
  (unless (stringp summary)
    (session-failure
     (session-path session) nil
     "Compaction summary must be a string"))
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
  ;; Baseline v0.84.2: setName accepts undefined to clear the name.
  (unless (or (null name) (stringp name))
    (session-failure
     (session-path session) nil
     "Session name must be a string"))
  (let* ((sanitized (and name (sanitize-session-name name)))
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
        sanitized
        (plusp (length sanitized))
        sanitized)))))

(defun session-label (session entry-id)
  (gethash entry-id (session-labels session)))

(defun session-branch (session entry-id)
  (unless (gethash entry-id (session-by-id session))
    (session-failure
     (session-path session) nil
     "Session entry not found: ~A" entry-id))
  (setf (session-leaf-id session) entry-id
        (session-%messages-leaf session) nil
        (session-%messages-cache session) nil)
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
  (when (and (session-%messages-cache session)
             (equal leaf-id (session-%messages-leaf session)))
    (return-from session-messages
      (copy-list (session-%messages-cache session))))
  (let ((messages
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
                  (otherwise nil)))))
    (setf (session-%messages-leaf session) leaf-id
          (session-%messages-cache session) messages)
    (copy-list messages)))
