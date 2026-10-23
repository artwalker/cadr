(in-package #:cadr-durable)

(defstruct durable-storage
  kind
  state
  (closed nil)
  path
  prefix
  database
  fsync)

(defun storage-label (storage)
  (ecase (durable-storage-kind storage)
    (:memory "MemoryStorage")
    (:jsonl "JsonlStorage")
    (:sqlite "SqliteStorage")))

(defun assert-open (storage)
  (when (durable-storage-closed storage)
    (error "~A is closed" (storage-label storage))))

(defun make-memory-storage ()
  (make-durable-storage :kind :memory :state (make-durable-state)))

(defun storage-state (storage)
  (assert-open storage)
  (durable-storage-state storage))

(defun storage-mint-id (storage)
  (state-mint-id (storage-state storage)))

(defun storage-conversation (storage id)
  (state-conversation (storage-state storage) id))

(defun storage-scan-conversations (storage &key order limit cursor owner-kind owner-id)
  (state-scan-conversations (storage-state storage)
                            :order order :limit limit :cursor cursor
                            :owner-kind owner-kind :owner-id owner-id))

(defun storage-entry (storage id &optional conversation-id)
  (state-entry (storage-state storage) id conversation-id))

(defun storage-scan-entries (storage conversation-id &key order limit cursor)
  (state-scan-entries (storage-state storage) conversation-id
                      :order order :limit limit :cursor cursor))

(defun storage-task (storage id)
  (state-task (storage-state storage) id))

(defun storage-scan-tasks (storage &key status order limit cursor)
  (state-scan-tasks (storage-state storage)
                    :status status :order order :limit limit :cursor cursor))

(defun storage-submission (storage id)
  (state-submission (storage-state storage) id))

(defun storage-submission-by-request (storage conversation-id request-id)
  (state-submission-by-request (storage-state storage) conversation-id request-id))

(defun storage-find-document (storage kind scope-kind scope-id key at)
  (state-find-document (storage-state storage) kind scope-kind scope-id key at))

(defun storage-closed-p (storage)
  (durable-storage-closed storage))

(defun path-vector (path)
  (apply #'cadr-chord:json-array (or path nil)))

(defun path-list (value)
  (when value (coerce value 'list)))

(defun encode-op (op)
  (let ((verb (first op)))
    (cond
      ((string= verb "r") (cadr-chord:json-array "r" (second op)))
      ((string= verb "p")
       (cadr-chord:json-array "p" (path-vector (second op)) (third op) (fourth op)
                              (apply #'cadr-chord:json-array (fifth op))))
      ((string= verb "m")
       (cadr-chord:json-array "m" (path-vector (second op))
                              (apply #'cadr-chord:json-array (third op))))
      ((cddr op)
       (cadr-chord:json-array verb (path-vector (second op)) (third op)))
      (t (cadr-chord:json-array verb (path-vector (second op)))))))

(defun decode-op (op)
  (let ((verb (aref op 0)))
    (cond
      ((string= verb "r") (list "r" (aref op 1)))
      ((string= verb "p")
       (list "p" (path-list (aref op 1)) (aref op 2) (aref op 3) (coerce (aref op 4) 'list)))
      ((string= verb "m")
       (list "m" (path-list (aref op 1)) (coerce (aref op 2) 'list)))
      ((> (length op) 2)
       (list verb (path-list (aref op 1)) (aref op 2)))
      (t (list verb (path-list (aref op 1)))))))

(defun encode-ops (ops)
  (when ops
    (apply #'cadr-chord:json-array (mapcar #'encode-op ops))))

(defun decode-ops (value)
  (when value
    (map 'list #'decode-op value)))

(defun json-or-null (value)
  (if value (json-text value) cadr-chord:+json-null+))

(defun present-json (value)
  (if (or (null value) (cadr-chord:json-null-p value))
      nil
      value))

(defun encode-revision (revision)
  (cadr-chord:json-object
   "kind" (document-revision-kind revision)
   "version" (document-revision-version revision)
   "value" (json-or-null (document-revision-value revision))
   "ops" (json-or-null (encode-ops (document-revision-ops revision)))
   "seq" (or (document-revision-seq revision) cadr-chord:+json-null+)))

(defun decode-revision (object)
  (make-document-revision
   :kind (hash-get object "kind")
   :version (hash-get object "version")
   :value (present-json (hash-get object "value"))
   :ops (decode-ops (present-json (hash-get object "ops")))
   :seq (present-json (hash-get object "seq"))))

(defun encode-state (state)
  (cadr-chord:json-object
   "seq" (durable-state-seq state)
   "nextId" (durable-state-next-id state)
   "conversations"
   (apply #'cadr-chord:json-array
          (mapcar #'encode-conversation
                  (record-list (durable-state-conversations state) #'identity)))
   "entries"
   (apply #'cadr-chord:json-array
          (mapcar #'encode-entry
                  (record-list (durable-state-entries state) #'identity)))
   "tasks"
   (apply #'cadr-chord:json-array
          (mapcar #'encode-task
                  (record-list (durable-state-tasks state) #'identity)))
   "submissions"
   (apply #'cadr-chord:json-array
          (mapcar #'encode-submission
                  (record-list (durable-state-submissions state) #'identity)))
   "documents"
   (apply #'cadr-chord:json-array
          (mapcar #'encode-document
                  (record-list (durable-state-documents state) #'identity)))))

(defun encode-conversation (conversation)
  (let ((object (cadr-chord:json-object "id" (conversation-id conversation)
                                        "ownerKind" (conversation-owner-kind conversation))))
    (when (conversation-parent-id conversation)
      (cadr-chord:json-put object "parentId" (conversation-parent-id conversation))
      (cadr-chord:json-put object "parentAt" (conversation-parent-at conversation)))
    (when (conversation-owner-id conversation)
      (cadr-chord:json-put object "ownerId" (conversation-owner-id conversation)))
    object))

(defun encode-entry (entry)
  (let ((object (cadr-chord:json-object
                 "id" (entry-id entry)
                 "conversationId" (entry-conversation-id entry)
                 "kind" (entry-kind entry)
                 "commitSeq" (or (entry-commit-seq entry) 0))))
    (when (entry-model entry) (cadr-chord:json-put object "model" (entry-model entry)))
    (when (entry-data entry) (cadr-chord:json-put object "data" (entry-data entry)))
    (when (entry-head entry) (cadr-chord:json-put object "head" (entry-head entry)))
    (when (entry-by-task-id entry)
      (cadr-chord:json-put object "byTaskId" (entry-by-task-id entry)))
    object))

(defun encode-task (task)
  (let ((object (cadr-chord:json-object
                 "id" (task-record-id task)
                 "kind" (task-record-kind task)
                 "version" (task-record-version task)
                 "conversationId" (task-record-conversation-id task)
                 "state" (task-state-json (task-record-state task))
                 "abortRequested" (and (task-record-abort-requested task) t))))
    (when (task-record-owner task)
      (cadr-chord:json-put object "owner" (task-record-owner task)))
    (when (task-record-input task)
      (cadr-chord:json-put object "input" (task-record-input task)))
    (when (task-record-restarts task)
      (cadr-chord:json-put object "restarts" (task-record-restarts task)))
    (when (task-record-abort-reason task)
      (cadr-chord:json-put object "abortReason" (task-record-abort-reason task)))
    (when (task-record-background task)
      (cadr-chord:json-put object "background" t))
    object))

(defun encode-submission (submission)
  (let ((object (cadr-chord:json-object
                 "id" (submission-record-id submission)
                 "conversationId" (submission-record-conversation-id submission)
                 "type" (submission-record-type submission)
                 "status" (submission-record-status submission))))
    (when (submission-record-request-id submission)
      (cadr-chord:json-put object "requestId" (submission-record-request-id submission)))
    (when (submission-record-entry submission)
      (cadr-chord:json-put object "entry" (submission-record-entry submission)))
    (when (submission-record-answer submission)
      (cadr-chord:json-put object "answer" (submission-record-answer submission)))
    (when (submission-record-reason submission)
      (cadr-chord:json-put object "reason" (submission-record-reason submission)))
    object))

(defun encode-document (document)
  (let ((object (cadr-chord:json-object
                 "id" (document-record-id document)
                 "kind" (document-record-kind document)
                 "scopeKind" (document-record-scope-kind document)
                 "version" (document-record-version document)
                 "history" (document-record-history document)
                 "fork" (or (document-record-fork document) cadr-chord:+json-null+)
                 "revisions" (apply #'cadr-chord:json-array
                                    (mapcar #'encode-revision
                                            (document-record-revisions document))))))
    (when (document-record-scope-id document)
      (cadr-chord:json-put object "scopeId" (document-record-scope-id document)))
    (when (document-record-key document)
      (cadr-chord:json-put object "key" (document-record-key document)))
    (when (document-record-created-at document)
      (cadr-chord:json-put object "createdAt" (document-record-created-at document)))
    (when (document-record-retired-at document)
      (cadr-chord:json-put object "retiredAt" (document-record-retired-at document)))
    object))

(defun decode-conversation (object)
  (make-conversation :id (hash-get object "id")
                     :parent-id (present-json (hash-get object "parentId"))
                     :parent-at (present-json (hash-get object "parentAt"))
                     :owner-kind (or (hash-get object "ownerKind") "ownerless")
                     :owner-id (present-json (hash-get object "ownerId"))))

(defun decode-entry (object)
  (make-entry :id (hash-get object "id")
              :conversation-id (hash-get object "conversationId")
              :kind (hash-get object "kind")
              :model (present-json (hash-get object "model"))
              :data (present-json (hash-get object "data"))
              :head (present-json (hash-get object "head"))
              :by-task-id (present-json (hash-get object "byTaskId"))
              :commit-seq (hash-get object "commitSeq")))

(defun decode-task (object)
  (make-task-record :id (hash-get object "id")
                    :kind (hash-get object "kind")
                    :version (or (hash-get object "version") 1)
                    :conversation-id (hash-get object "conversationId")
                    :owner (present-json (hash-get object "owner"))
                    :input (present-json (hash-get object "input"))
                    :state (hash-get object "state")
                    :restarts (present-json (hash-get object "restarts"))
                    :abort-requested (hash-get object "abortRequested")
                    :abort-reason (present-json (hash-get object "abortReason"))
                    :background (hash-get object "background")))

(defun decode-submission (object)
  (make-submission-record :id (hash-get object "id")
                          :conversation-id (hash-get object "conversationId")
                          :request-id (present-json (hash-get object "requestId"))
                          :type (hash-get object "type")
                          :status (hash-get object "status")
                          :entry (present-json (hash-get object "entry"))
                          :answer (present-json (hash-get object "answer"))
                          :reason (present-json (hash-get object "reason"))))

(defun decode-document (object)
  (make-document-record :id (hash-get object "id")
                        :kind (hash-get object "kind")
                        :scope-kind (hash-get object "scopeKind")
                        :scope-id (present-json (hash-get object "scopeId"))
                        :key (present-json (hash-get object "key"))
                        :version (or (hash-get object "version") 1)
                        :history (or (hash-get object "history") "latest")
                        :fork (present-json (hash-get object "fork"))
                        :created-at (present-json (hash-get object "createdAt"))
                        :retired-at (present-json (hash-get object "retiredAt"))
                        :revisions (map 'list #'decode-revision (hash-get object "revisions"))))

(defun install-decoded (state decoder id-reader collection table claim)
  (when collection
    (loop for object across collection
          for record = (funcall decoder object)
          do (funcall claim state record)
             (setf (gethash (funcall id-reader record) table) record))))

(defun decode-state (object)
  (let ((state (make-durable-state
                :seq (hash-get object "seq")
                :next-id (hash-get object "nextId"))))
    (install-decoded state #'decode-conversation #'conversation-id
                     (hash-get object "conversations")
                     (durable-state-conversations state)
                     (lambda (state record)
                       (claim-id state (conversation-id record) "conversation" nil)))
    (install-decoded state #'decode-entry #'entry-id
                     (hash-get object "entries")
                     (durable-state-entries state)
                     (lambda (state record)
                       (claim-id state (entry-id record) "entry" nil)))
    (install-decoded state #'decode-task #'task-record-id
                     (hash-get object "tasks")
                     (durable-state-tasks state)
                     (lambda (state record)
                       (claim-id state (task-record-id record) "task" t)))
    (install-decoded state #'decode-submission #'submission-record-id
                     (hash-get object "submissions")
                     (durable-state-submissions state)
                     (lambda (state record)
                       (claim-id state (submission-record-id record) "submission" t)
                       (when (submission-record-request-id record)
                         (setf (gethash (cons (submission-record-conversation-id record)
                                              (submission-record-request-id record))
                                        (durable-state-requests state))
                               (submission-record-id record)))))
    (install-decoded state #'decode-document #'document-record-id
                     (hash-get object "documents")
                     (durable-state-documents state)
                     (lambda (state record)
                       (claim-id state (document-record-id record) "document" nil)))
    state))

(defun persist-storage (storage next)
  (ecase (durable-storage-kind storage)
    (:memory nil)
    (:jsonl (persist-jsonl storage next))
    (:sqlite (persist-sqlite storage next))))

(defun storage-commit (storage writes)
  (assert-open storage)
  (let ((next (commit-state (durable-storage-state storage) writes)))
    (unless (eq next (durable-storage-state storage))
      (persist-storage storage next)
      (setf (durable-storage-state storage) next))
    (durable-state-seq (durable-storage-state storage))))

(defun storage-close (storage)
  (assert-open storage)
  (setf (durable-storage-closed storage) t)
  (when (eq (durable-storage-kind storage) :sqlite)
    (cadr-chord:sqlite-close (durable-storage-database storage)))
  nil)

(defun read-bytes (path)
  (with-open-file (stream path :direction :input :element-type '(unsigned-byte 8)
                               :if-does-not-exist nil)
    (if (null stream)
        nil
        (let ((buffer (make-array (file-length stream) :element-type '(unsigned-byte 8))))
          (read-sequence buffer stream)
          buffer))))

(defun write-bytes (path bytes)
  (with-open-file (stream path :direction :output :element-type '(unsigned-byte 8)
                               :if-exists :supersede :if-does-not-exist :create)
    (write-sequence bytes stream)))

(defun trim-torn-tail (bytes)
  (if (or (null bytes) (zerop (length bytes)))
      bytes
      (if (= (aref bytes (1- (length bytes))) (char-code #\Newline))
          bytes
          (let ((end (position (char-code #\Newline) bytes :from-end t)))
            (if end (subseq bytes 0 (1+ end)) (make-array 0 :element-type '(unsigned-byte 8)))))))

(defun jsonl-sidecar-name-p (name)
  (let ((length (length name)))
    (flet ((match (prefix)
             (let ((prefix-length (length prefix)))
               (and (> length (+ prefix-length 6))
                    (string= name prefix :end1 prefix-length)
                    (string= name ".jsonl" :start1 (- length 6))
                    (let ((id (subseq name prefix-length (- length 6))))
                      (and (plusp (length id))
                           (every #'digit-char-p id)
                           (or (= (length id) 1)
                               (char/= (char id 0) #\0))))))))
      (or (match "doc-") (match "task-")))))

(defun jsonl-visit-lines (path name visitor)
  (let* ((raw (read-bytes path))
         (trimmed (trim-torn-tail raw)))
    (when (and raw (not (equalp raw trimmed)))
      (write-bytes path trimmed))
    (when (and trimmed (plusp (length trimmed)))
      (let ((start 0)
            (number 1))
        (loop for end from 0 below (length trimmed)
              when (= (aref trimmed end) 10)
                do (let ((text (handler-case
                                   (sb-ext:octets-to-string
                                    trimmed :start start :end end
                                    :external-format :utf-8)
                                 (error ()
                                   (error "Invalid UTF-8 in complete ~A line ~A"
                                          name number)))))
                     (funcall visitor text number))
                   (setf start (1+ end))
                   (incf number))))))

(defun open-jsonl-storage (directory &key fsync)
  (let ((directory (uiop:ensure-directory-pathname directory)))
    (ensure-directories-exist directory)
    (let ((state (make-durable-state))
          (path (merge-pathnames "main.jsonl" directory)))
      (jsonl-visit-lines
       path "main.jsonl"
       (lambda (text number)
         (unless (zerop (length text))
           (handler-case (setf state (decode-state (text-json text)))
             (error ()
               (error "Malformed complete main.jsonl line ~A" number))))))
      (dolist (name (sort (remove-if-not
                           #'jsonl-sidecar-name-p
                           (mapcar #'file-namestring (uiop:directory-files directory)))
                          #'string<))
        (jsonl-visit-lines
         (merge-pathnames name directory) name
         (lambda (text number)
           (handler-case (text-json text)
             (error ()
               (error "Malformed complete ~A line ~A" name number))))))
      (make-durable-storage :kind :jsonl :state state :path path :fsync fsync))))

(defun persist-jsonl (storage state)
  (let ((line (concatenate 'string (json-text (encode-state state)) #(#\Newline))))
    (with-open-file (stream (durable-storage-path storage)
                            :direction :output :element-type '(unsigned-byte 8)
                            :if-exists :append :if-does-not-exist :create)
      (write-sequence (sb-ext:string-to-octets line :external-format :utf-8) stream)
      (finish-output stream)
      (when (durable-storage-fsync storage)
        (sb-posix:fsync (sb-sys:fd-stream-fd stream))))))

(defun sql-name (prefix name)
  (concatenate 'string (or prefix "") name))

(defun sqlite-names (prefix)
  (let ((tables '("durable_schema" "durable_metadata" "record_ids" "conversations" "entries"
                  "tasks" "submissions" "documents" "document_revisions"))
        (indexes '("conversations_by_owner_conversation" "conversations_by_owner_task"
                   "entries_by_conversation" "entry_heads_by_conversation" "tasks_by_status"
                   "tasks_by_conversation" "tasks_by_kind" "tasks_by_abort_requested"
                   "tasks_by_background" "submissions_by_request" "submissions_by_conversation"
                   "submissions_by_status" "documents_by_address" "documents_by_scope"
                   "documents_by_scope_kind" "document_revisions_by_kind")))
    (values (mapcar (lambda (name) (sql-name prefix name)) tables)
            (mapcar (lambda (name) (sql-name prefix name)) indexes))))

(defun create-sqlite-schema (database prefix)
  (multiple-value-bind (tables indexes) (sqlite-names prefix)
    (declare (ignore indexes))
    (cadr-chord:sqlite-exec
     database
     (format nil "CREATE TABLE IF NOT EXISTS ~A (version INTEGER NOT NULL)" (first tables)))
    (cadr-chord:sqlite-exec
     database
     (format nil "CREATE TABLE IF NOT EXISTS ~A (key TEXT PRIMARY KEY, value TEXT NOT NULL)"
             (second tables)))
    (cadr-chord:sqlite-exec
     database
     (format nil "CREATE TABLE IF NOT EXISTS ~A (id INTEGER PRIMARY KEY, table_name TEXT NOT NULL)"
             (third tables)))
    (cadr-chord:sqlite-exec
     database
     (format nil "CREATE TABLE IF NOT EXISTS ~A (id INTEGER PRIMARY KEY, parent_id INTEGER, parent_at INTEGER, owner_kind TEXT, owner_id INTEGER)"
             (fourth tables)))
    (cadr-chord:sqlite-exec
     database
     (format nil "CREATE TABLE IF NOT EXISTS ~A (id INTEGER PRIMARY KEY, conversation_id INTEGER NOT NULL, kind TEXT NOT NULL, model TEXT, data TEXT, head INTEGER, by_task_id INTEGER, commit_seq INTEGER NOT NULL)"
             (fifth tables)))
    (cadr-chord:sqlite-exec
     database
     (format nil "CREATE TABLE IF NOT EXISTS ~A (id INTEGER PRIMARY KEY, payload TEXT NOT NULL)"
             (sixth tables)))
    (cadr-chord:sqlite-exec
     database
     (format nil "CREATE TABLE IF NOT EXISTS ~A (id INTEGER PRIMARY KEY, payload TEXT NOT NULL)"
             (seventh tables)))
    (cadr-chord:sqlite-exec
     database
     (format nil "CREATE TABLE IF NOT EXISTS ~A (id INTEGER PRIMARY KEY, payload TEXT NOT NULL)"
             (eighth tables)))
    (cadr-chord:sqlite-exec
     database
     (format nil "CREATE TABLE IF NOT EXISTS ~A (document_id INTEGER NOT NULL, ordinal INTEGER NOT NULL, payload TEXT NOT NULL)"
             (ninth tables)))
    (cadr-chord:sqlite-exec
     database
     (format nil "CREATE INDEX IF NOT EXISTS ~A ON ~A (owner_id)"
             (sql-name prefix "conversations_by_owner_task") (fourth tables)))
    (cadr-chord:sqlite-exec
     database
     (format nil "CREATE INDEX IF NOT EXISTS ~A ON ~A (conversation_id)"
             (sql-name prefix "entries_by_conversation") (fifth tables)))
    (cadr-chord:sqlite-exec
     database
     (format nil "CREATE INDEX IF NOT EXISTS ~A ON ~A (id)"
             (sql-name prefix "tasks_by_status") (sixth tables)))))

(defun metadata-value (database prefix key)
  (let ((row (cadr-chord:sqlite-get
              database
              (format nil "SELECT value FROM ~A WHERE key = ?" (sql-name prefix "durable_metadata"))
              key)))
    (when row (hash-get row "value"))))

(defun open-sqlite-storage (path &key prefix)
  (when prefix
    (cadr-chord:validate-sqlite-schema-prefix prefix))
  (let ((path (namestring path)))
  (ensure-directories-exist path)
  (let ((database (cadr-chord:open-node-sqlite-database path)))
    (unwind-protect
         (let ((metadata (sql-name prefix "durable_metadata")))
           (if (cadr-chord:sqlite-get
                database
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?"
                metadata)
               (let ((seq (metadata-value database prefix "seq")))
                 (unless seq
                   (error "Durable SQLite metadata is missing"))
                 (make-durable-storage
                  :kind :sqlite :database database :prefix prefix :path path
                  :state (decode-state (text-json (metadata-value database prefix "state")))))
               (progn
                 (create-sqlite-schema database prefix)
                 (let ((state (make-durable-state)))
                   (cadr-chord:sqlite-run
                    database
                    (format nil "INSERT INTO ~A (key, value) VALUES ('seq', '0')" metadata))
                   (cadr-chord:sqlite-run
                    database
                    (format nil "INSERT INTO ~A (key, value) VALUES ('state', ?)" metadata)
                    (json-text (encode-state state)))
                   (make-durable-storage
                    :kind :sqlite :database database :prefix prefix :path path :state state)))))
      (when (eq (cadr-chord:sqlite-get database "SELECT 1") nil)
        nil)))))

(defun persist-sqlite (storage state)
  (let* ((database (durable-storage-database storage))
         (prefix (durable-storage-prefix storage))
         (metadata (sql-name prefix "durable_metadata"))
         (payload (json-text (encode-state state))))
    (cadr-chord:sqlite-transaction
     database
     (lambda (handle)
       (cadr-chord:sqlite-handle-run
        handle
        (format nil "UPDATE ~A SET value = ? WHERE key = 'state'" metadata)
        payload)
       (cadr-chord:sqlite-handle-run
        handle
        (format nil "UPDATE ~A SET value = ? WHERE key = 'seq'" metadata)
        (princ-to-string (durable-state-seq state)))))))
