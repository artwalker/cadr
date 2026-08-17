(in-package #:cadr-agent)

(defparameter +sqlite-session-schema+
  '("CREATE TABLE IF NOT EXISTS migrations (
       id TEXT PRIMARY KEY,
       applied_at TEXT NOT NULL
     )"
    "CREATE TABLE IF NOT EXISTS sessions (
       id TEXT PRIMARY KEY,
       created_at TEXT NOT NULL,
       cwd TEXT NOT NULL,
       parent_session_id TEXT NULL,
       metadata TEXT NULL,
       active_leaf_id TEXT NULL
     ) WITHOUT ROWID"
    "CREATE INDEX IF NOT EXISTS idx_sessions_created_at
       ON sessions(created_at DESC)"
    "CREATE INDEX IF NOT EXISTS idx_sessions_cwd
       ON sessions(cwd)"
    "CREATE INDEX IF NOT EXISTS idx_sessions_parent
       ON sessions(parent_session_id)"
    "CREATE TABLE IF NOT EXISTS session_entries (
       session_id TEXT NOT NULL,
       id TEXT NOT NULL,
       entry_seq INTEGER NOT NULL,
       parent_id TEXT NULL,
       type TEXT NOT NULL,
       timestamp TEXT NOT NULL,
       payload TEXT NOT NULL,
       PRIMARY KEY (session_id, id)
     )"
    "CREATE UNIQUE INDEX IF NOT EXISTS
       idx_session_entries_session_seq
       ON session_entries(session_id, entry_seq)"
    "CREATE INDEX IF NOT EXISTS
       idx_session_entries_session_parent
       ON session_entries(session_id, parent_id)"
    "CREATE INDEX IF NOT EXISTS
       idx_session_entries_session_type
       ON session_entries(session_id, type)"
    "CREATE TABLE IF NOT EXISTS session_sequences (
       session_id TEXT PRIMARY KEY,
       next_seq INTEGER NOT NULL
     ) WITHOUT ROWID"
    "CREATE TABLE IF NOT EXISTS branch_entries (
       session_id TEXT NOT NULL,
       branch_id TEXT NOT NULL,
       entry_id TEXT NOT NULL,
       entry_seq INTEGER NOT NULL,
       PRIMARY KEY (session_id, branch_id, entry_id)
     ) WITHOUT ROWID"
    "CREATE INDEX IF NOT EXISTS
       idx_branch_entries_session_branch
       ON branch_entries(session_id, branch_id)"
    "CREATE INDEX IF NOT EXISTS
       idx_branch_entries_session_branch_seq
       ON branch_entries(session_id, branch_id, entry_seq)"
    "CREATE INDEX IF NOT EXISTS
       idx_branch_entries_session_entry
       ON branch_entries(session_id, entry_id)"
    "CREATE TABLE IF NOT EXISTS session_materialized (
       session_id TEXT PRIMARY KEY,
       payload TEXT NOT NULL
     ) WITHOUT ROWID"
    "CREATE TABLE IF NOT EXISTS entry_materialized (
       session_id TEXT NOT NULL,
       entry_seq INTEGER NOT NULL,
       type TEXT NOT NULL,
       payload TEXT NOT NULL,
       PRIMARY KEY (session_id, entry_seq, type)
     ) WITHOUT ROWID"
    "CREATE INDEX IF NOT EXISTS
       idx_entry_materialized_session_type_seq
       ON entry_materialized(session_id, type, entry_seq)"))

(defun apply-sqlite-session-migrations (database)
  (sqlite:execute-non-query
   database
   (first +sqlite-session-schema+))
  (unless
      (sqlite:execute-single
       database
       "SELECT id FROM migrations WHERE id = ?"
       "001_initial.sql")
    (sqlite:with-transaction database
      (dolist (statement
               (rest +sqlite-session-schema+))
        (sqlite:execute-non-query
         database statement))
      (sqlite:execute-non-query
       database
       "INSERT INTO migrations (id, applied_at) VALUES (?, ?)"
       "001_initial.sql"
       (current-iso8601))))
  database)

(defun configure-sqlite-session-database
    (database)
  (sqlite:execute-non-query
   database "PRAGMA journal_mode=WAL")
  (sqlite:execute-non-query
   database "PRAGMA synchronous=FULL")
  (sqlite:set-busy-timeout database 5000)
  (apply-sqlite-session-migrations
   database))

(defun open-sqlite-session-database (path)
  (handler-case
      (let ((database
              (sqlite:connect path
                              :busy-timeout 5000)))
        (handler-case
            (progn
              (configure-sqlite-session-database
               database)
              database)
          (error (cause)
            (ignore-errors
              (sqlite:disconnect database))
            (error cause))))
    (error (cause)
      (session-failure
       path nil
       "Cannot open SQLite session database: ~A"
       cause))))

(defun sqlite-execute-named
    (database sql parameters)
  (apply
   #'sqlite:execute-non-query/named
   database sql
   (loop for (name . value) in parameters
         append (list name value))))

(defun sqlite-query-single-named
    (database sql parameters)
  (apply
   #'sqlite:execute-single/named
   database sql
   (loop for (name . value) in parameters
         append (list name value))))

(defclass sqlite-session-storage
    (memory-session-storage)
  ((database
    :initarg :database
    :reader sqlite-storage-database)
   (database-path
    :initarg :database-path
    :reader sqlite-storage-database-path)
   (session-id
    :initarg :session-id
    :reader sqlite-storage-session-id)
   (active-branch-id
    :initform nil
    :accessor sqlite-storage-active-branch-id)
   (closed-p
    :initform nil
    :accessor sqlite-storage-closed-p)))

(defun sqlite-entry-type-name (entry)
  (string-downcase
   (substitute
    #\_ #\-
    (symbol-name
     (session-entry-type entry)))))

(defun sqlite-session-data-json (data)
  (and
   data
   (cadr-ai::stringify-json
    (json-safe-value data))))

(defun sqlite-session-data-from-json (text)
  (and
   text
   (let ((parsed
           (cadr-ai::parse-json text)))
     (unless (hash-table-p parsed)
       (session-failure
        nil nil
        "SQLite session metadata must be an object"))
     (json-object-to-plist parsed))))

(defun sqlite-create-storage
    (database database-path
     &key id cwd parent-session-id metadata
       created-at)
  (let* ((session-id
           (or id (make-session-id)))
         (timestamp
           (or created-at
               (current-iso8601)))
         (cwd-text
           (if (pathnamep cwd)
               (namestring cwd)
               (princ-to-string cwd)))
         (session-metadata
           (make-session-metadata
            :id session-id
            :created-at timestamp
            :cwd cwd-text
            :path (pathname database-path)
            :parent-session-id
            parent-session-id
            :data metadata)))
    (unless (metadata-json-data-p metadata)
      (session-failure
       database-path nil
       "SQLite session metadata must be an object"))
    (handler-case
        (sqlite:with-transaction database
          (sqlite:execute-non-query
           database
           "INSERT INTO sessions
              (id, created_at, cwd, parent_session_id,
               metadata, active_leaf_id)
            VALUES (?, ?, ?, ?, ?, ?)"
           session-id timestamp cwd-text
           parent-session-id
           (sqlite-session-data-json metadata)
           nil)
          (sqlite:execute-non-query
           database
           "INSERT INTO session_sequences
              (session_id, next_seq)
            VALUES (?, ?)"
           session-id 1)
          (sqlite:execute-non-query
           database
           "INSERT INTO session_materialized
              (session_id, payload)
            VALUES (?, ?)"
           session-id
           (cadr-ai::stringify-json
            (cadr-ai::json-object
             "messageCount" 0
             "cachedTokens" 0
             "uncachedTokens" 0
             "totalTokens" 0
             "costTotal" 0d0))))
      (error (cause)
        (session-failure
         database-path nil
         "Cannot create SQLite session ~A: ~A"
         session-id cause)))
    (make-instance
     'sqlite-session-storage
     :metadata session-metadata
     :database database
     :database-path database-path
     :session-id session-id)))

(defun sqlite-row-to-entry
    (row storage line-number)
  (destructuring-bind
      (id parent-id type timestamp payload)
      row
    (declare (ignore id parent-id type timestamp))
    (let ((object
            (handler-case
                (cadr-ai::parse-json payload)
              (error (cause)
                (storage-failure
                 storage
                 "Invalid SQLite entry payload: ~A"
                 cause)))))
      (record-to-session-entry
       object
       (sqlite-storage-database-path
        storage)
       line-number
       (memory-storage-by-id storage)))))

(defun sqlite-open-storage
    (database database-path session-id)
  (let ((row
          (first
           (sqlite:execute-to-list
            database
            "SELECT id, created_at, cwd,
                    parent_session_id, metadata,
                    active_leaf_id
               FROM sessions
              WHERE id = ?"
            session-id))))
    (unless row
      (session-failure
       database-path nil
       "Session not found: ~A"
       session-id))
    (destructuring-bind
        (id created-at cwd parent-session-id
            metadata-json active-leaf-id)
        row
      (let ((storage
              (make-instance
               'sqlite-session-storage
               :metadata
               (make-session-metadata
                :id id
                :created-at created-at
                :cwd cwd
                :path (pathname database-path)
                :parent-session-id
                parent-session-id
                :data
                (sqlite-session-data-from-json
                 metadata-json))
               :database database
               :database-path database-path
               :session-id id))
            (line-number 1))
        (dolist
            (entry-row
             (sqlite:execute-to-list
              database
              "SELECT id, parent_id, type,
                      timestamp, payload
                 FROM session_entries
                WHERE session_id = ?
                ORDER BY entry_seq"
              session-id))
          (incf line-number)
          (let ((entry
                  (sqlite-row-to-entry
                   entry-row storage line-number)))
            (commit-memory-storage-entry
             storage entry)))
        (when
            (and
             active-leaf-id
             (not
              (gethash
               active-leaf-id
               (memory-storage-by-id storage))))
          (storage-failure
           storage
           "SQLite active leaf does not exist: ~A"
           active-leaf-id))
        (setf
         (memory-storage-leaf-id storage)
         active-leaf-id)
        storage))))

(defun sqlite-projected-storage
    (storage entry)
  (make-memory-session-storage
   :metadata
   (session-storage-metadata storage)
   :entries
   (append
    (session-storage-entries storage)
    (list entry))))

(defun storage-current-model (storage)
  (let ((model nil))
    (dolist
        (entry
         (session-storage-entries storage))
      (let ((next (model-plist-from-entry entry)))
        (when next
          (setf model next))))
    model))

(defun storage-current-thinking-level
    (storage)
  (let ((level nil))
    (dolist
        (entry
         (session-storage-entries storage))
      (when
          (eq :thinking-level-change
              (session-entry-type entry))
        (setf
         level
         (session-entry-thinking-level
          entry))))
    level))

(defun sqlite-materialized-payload (storage)
  (let* ((stats
           (session-storage-stats storage))
         (object
           (cadr-ai::json-object
            "messageCount"
            (getf stats :message-count)
            "cachedTokens"
            (getf stats :cached-tokens)
            "uncachedTokens"
            (getf stats :uncached-tokens)
            "totalTokens"
            (getf stats :total-tokens)
            "costTotal"
            (getf stats :cost-total))))
    (when (session-storage-name storage)
      (cadr-ai::json-put
       object "name"
       (session-storage-name storage)))
    (let ((model (storage-current-model storage))
          (level (storage-current-thinking-level storage)))
      (when model
        (cadr-ai::json-put
         object "currentModel"
         (json-safe-value model)))
      (when level
        (cadr-ai::json-put
         object "currentThinkingLevel"
         level)))
    (cadr-ai::stringify-json object)))

(defun sqlite-next-entry-sequence (storage)
  (or
   (sqlite:execute-single
    (sqlite-storage-database storage)
    "SELECT next_seq
       FROM session_sequences
      WHERE session_id = ?"
    (sqlite-storage-session-id storage))
   (storage-failure
    storage
    "Missing SQLite session sequence")))

(defun sqlite-entry-has-child-p
    (storage parent-id)
  (and
   parent-id
   (find
    parent-id
    (session-storage-entries storage)
    :key #'session-entry-parent-id
    :test #'equal)))

(defun sqlite-materialize-branch
    (storage leaf-id)
  (let* ((database
           (sqlite-storage-database storage))
         (session-id
           (sqlite-storage-session-id storage))
         (branch-id
           (make-session-id))
         (path
           (session-storage-path
            storage leaf-id)))
    (dolist (entry path)
      (let ((sequence
              (sqlite:execute-single
               database
               "SELECT entry_seq
                  FROM session_entries
                 WHERE session_id = ?
                   AND id = ?"
               session-id
               (session-entry-id entry))))
        (unless sequence
          (storage-failure
           storage
           "Missing SQLite entry row: ~A"
           (session-entry-id entry)))
        (sqlite:execute-non-query
         database
         "INSERT INTO branch_entries
            (session_id, branch_id, entry_id, entry_seq)
          VALUES (?, ?, ?, ?)"
         session-id branch-id
         (session-entry-id entry)
         sequence)))
    (setf
     (sqlite-storage-active-branch-id storage)
     branch-id)
    branch-id))

(defun ensure-sqlite-active-branch
    (storage entry)
  (let ((type
          (session-entry-type entry))
        (parent-id
          (session-entry-parent-id entry)))
    (cond
      ((eq :leaf type)
       (sqlite-materialize-branch
        storage
        (session-entry-target-id entry)))
      ((or
        (null
         (sqlite-storage-active-branch-id
          storage))
        (sqlite-entry-has-child-p
         storage parent-id))
       (sqlite-materialize-branch
        storage parent-id))))
  (or
   (sqlite-storage-active-branch-id storage)
   (setf
    (sqlite-storage-active-branch-id storage)
    (make-session-id))))

(defmethod session-storage-append-entry
    ((storage sqlite-session-storage)
     entry)
  (when (sqlite-storage-closed-p storage)
    (storage-failure
     storage "SQLite session storage is closed"))
  (sb-thread:with-mutex
      ((memory-storage-lock storage))
    (validate-storage-entry storage entry)
    (let* ((database
             (sqlite-storage-database storage))
           (session-id
             (sqlite-storage-session-id storage))
           (sequence
             (sqlite-next-entry-sequence storage))
           (projected
             (sqlite-projected-storage
              storage entry))
           (previous-active-branch-id
             (sqlite-storage-active-branch-id
              storage))
           (branch-id nil))
      (handler-case
          (sqlite:with-transaction database
            (setf
             branch-id
             (ensure-sqlite-active-branch
              storage entry))
            (sqlite:execute-non-query
             database
             "INSERT INTO session_entries
                (session_id, id, entry_seq,
                 parent_id, type, timestamp, payload)
              VALUES (?, ?, ?, ?, ?, ?, ?)"
             session-id
             (session-entry-id entry)
             sequence
             (session-entry-parent-id entry)
             (sqlite-entry-type-name entry)
             (session-timestamp-json
              (session-entry-timestamp entry))
             (cadr-ai::stringify-json
              (session-entry-to-json entry)))
            (sqlite:execute-non-query
             database
             "UPDATE session_sequences
                 SET next_seq = ?
               WHERE session_id = ?"
             (1+ sequence)
             session-id)
            (sqlite:execute-non-query
             database
             "UPDATE sessions
                 SET active_leaf_id = ?
               WHERE id = ?"
             (storage-entry-leaf-id entry)
             session-id)
            (sqlite:execute-non-query
             database
             "INSERT INTO branch_entries
                (session_id, branch_id,
                 entry_id, entry_seq)
              VALUES (?, ?, ?, ?)"
             session-id branch-id
             (session-entry-id entry)
             sequence)
            (sqlite:execute-non-query
             database
             "UPDATE session_materialized
                 SET payload = ?
               WHERE session_id = ?"
             (sqlite-materialized-payload
              projected)
             session-id)
            (when
                (member
                 (session-entry-type entry)
                 '(:label :session-info))
              (sqlite:execute-non-query
               database
               "INSERT INTO entry_materialized
                  (session_id, entry_seq,
                   type, payload)
                VALUES (?, ?, ?, ?)"
               session-id sequence
               (sqlite-entry-type-name entry)
               (cadr-ai::stringify-json
                (session-entry-to-json
                 entry)))))
        (error (cause)
          (setf
           (sqlite-storage-active-branch-id
            storage)
           previous-active-branch-id)
          (storage-failure
           storage
           "Cannot append SQLite session entry ~A: ~A"
           (session-entry-id entry)
           cause)))
      (commit-memory-storage-entry
       storage entry)))
  (session-entry-id entry))

(defmethod session-storage-cleanup
    ((storage sqlite-session-storage))
  (unless (sqlite-storage-closed-p storage)
    (sqlite:disconnect
     (sqlite-storage-database storage))
    (setf
     (sqlite-storage-closed-p storage)
     t))
  nil)

(defclass sqlite-session-repository ()
  ((database-path
    :initarg :database-path
    :reader sqlite-repository-database-path)))

(defun make-sqlite-session-repository
    (&key database-path)
  (make-instance
   'sqlite-session-repository
   :database-path
   (pathname database-path)))

(defun ensure-sqlite-database-directory (path)
  (ensure-directories-exist
   (merge-pathnames
    "anchor"
    (uiop:pathname-directory-pathname
     (pathname path)))))

(defun repository-open-sqlite-database
    (repository)
  (let ((path
          (sqlite-repository-database-path
           repository)))
    (ensure-sqlite-database-directory path)
    (open-sqlite-session-database path)))

(defmethod session-repository-create
    ((repository sqlite-session-repository)
     &key id cwd parent-session-path
       parent-session-id metadata)
  (declare (ignore parent-session-path))
  (let ((database
          (repository-open-sqlite-database
           repository)))
    (handler-case
        (make-harness-session
         :storage
         (sqlite-create-storage
          database
          (sqlite-repository-database-path
           repository)
          :id id
          :cwd cwd
          :parent-session-id
          parent-session-id
          :metadata metadata))
      (error (cause)
        (ignore-errors
          (sqlite:disconnect database))
        (error cause)))))

(defmethod session-repository-open
    ((repository sqlite-session-repository)
     metadata)
  (let ((path
          (sqlite-repository-database-path
           repository)))
    (unless (probe-file path)
      (session-failure
       path nil "Session not found: ~A"
       (session-metadata-id metadata)))
    (let ((database
            (repository-open-sqlite-database
             repository)))
      (handler-case
          (make-harness-session
           :storage
           (sqlite-open-storage
            database path
            (session-metadata-id
             metadata)))
        (error (cause)
          (ignore-errors
            (sqlite:disconnect database))
          (error cause))))))

(defun sqlite-row-to-metadata (row path)
  (destructuring-bind
      (id created-at cwd parent-session-id
          metadata-json)
      row
    (make-session-metadata
     :id id
     :created-at created-at
     :cwd cwd
     :path (pathname path)
     :parent-session-id parent-session-id
     :data
     (sqlite-session-data-from-json
      metadata-json))))

(defmethod session-repository-list
    ((repository sqlite-session-repository)
     &key cwd)
  (let ((path
          (sqlite-repository-database-path
           repository)))
    (unless (probe-file path)
      (return-from session-repository-list
        nil))
    (let ((database
            (repository-open-sqlite-database
             repository)))
      (unwind-protect
           (mapcar
            (lambda (row)
              (sqlite-row-to-metadata
               row path))
            (if cwd
                (sqlite:execute-to-list
                 database
                 "SELECT id, created_at, cwd,
                         parent_session_id, metadata
                    FROM sessions
                   WHERE cwd = ?
                   ORDER BY created_at DESC"
                 (if (pathnamep cwd)
                     (namestring cwd)
                     (princ-to-string cwd)))
                (sqlite:execute-to-list
                 database
                 "SELECT id, created_at, cwd,
                         parent_session_id, metadata
                    FROM sessions
                   ORDER BY created_at DESC")))
        (sqlite:disconnect database)))))

(defmethod session-repository-delete
    ((repository sqlite-session-repository)
     metadata)
  (let ((database
          (repository-open-sqlite-database
           repository))
        (id
          (session-metadata-id metadata)))
    (unwind-protect
         (handler-case
             (progn
               (unless
                   (sqlite:execute-single
                    database
                    "SELECT id FROM sessions WHERE id = ?"
                    id)
                 (session-failure
                  (sqlite-repository-database-path
                   repository)
                  nil
                  "Session not found: ~A"
                  id))
               (sqlite:with-transaction database
                 (dolist
                     (table
                      '("branch_entries"
                        "session_entries"
                        "entry_materialized"
                        "session_materialized"
                        "session_sequences"))
                   (sqlite:execute-non-query
                    database
                    (format
                     nil
                     "DELETE FROM ~A WHERE session_id = ?"
                     table)
                    id))
                 (sqlite:execute-non-query
                  database
                  "DELETE FROM sessions WHERE id = ?"
                  id)))
           (error (cause)
             (if (typep cause 'session-error)
                 (error cause)
                 (session-failure
                  (sqlite-repository-database-path
                   repository)
                  nil
                  "Cannot delete SQLite session ~A: ~A"
                  id cause))))
      (sqlite:disconnect database)))
  nil)

(defmethod session-repository-fork
    ((repository sqlite-session-repository)
     source-metadata
     &key id cwd parent-session-path
       parent-session-id metadata entry-id
       (position :before))
  (declare (ignore parent-session-path))
  (let* ((source
           (session-repository-open
            repository source-metadata))
         (entries
           (unwind-protect
                (session-entries-to-fork
                 (harness-session-storage
                  source)
                 entry-id position)
             (harness-session-cleanup
              source)))
         (fork
           (session-repository-create
            repository
            :id id
            :cwd
            (or cwd
                (session-metadata-cwd
                 source-metadata))
            :parent-session-id
            (or parent-session-id
                (session-metadata-id
                 source-metadata))
            :metadata
            (or metadata
                (session-metadata-data
                 source-metadata)))))
    (handler-case
        (progn
          (dolist (entry entries)
            (harness-session-append-entry
             fork entry))
          fork)
      (error (cause)
        (harness-session-cleanup fork)
        (error cause)))))
