(in-package #:cadr-chord)

(defun validate-sqlite-schema-prefix (prefix)
  (unless (and (stringp prefix)
               (plusp (length prefix))
               (or (alpha-char-p (char prefix 0)) (char= (char prefix 0) #\_))
               (every (lambda (character)
                        (or (alphanumericp character) (char= character #\_)))
                      prefix))
    (error "Invalid SQLite schema prefix ~A" (canonical-json prefix)))
  (when (and (>= (length prefix) 7)
             (string-equal prefix "sqlite_" :end1 7))
    (error "SQLite schema prefix ~A is reserved" (canonical-json prefix)))
  prefix)

(defstruct sqlite-database connection statements (closed nil) (mutex (sb-thread:make-mutex :name "chord-sqlite")))

(defun sqlite-row (statement)
  (let ((row (json-object)))
    (loop for name in (sqlite::statement-column-names statement)
          for index from 0
          for value = (sqlite:statement-column-value statement index)
          do (setf (gethash name row) (if (null value) +json-null+ value)))
    row))

(defun sqlite-prepare (database sql)
  (or (gethash sql (sqlite-database-statements database))
      (setf (gethash sql (sqlite-database-statements database))
            (sqlite:prepare-statement (sqlite-database-connection database) sql))))

(defun call-with-sqlite (database function)
  (sb-thread:with-mutex ((sqlite-database-mutex database))
    (funcall function)))

(defmacro with-sqlite ((database) &body body)
  `(call-with-sqlite ,database (lambda () ,@body)))

(defun open-node-sqlite-database (path &key (busy-timeout-ms 5000) (wal-auto-checkpoint-pages 1000))
  (unless (or (string= path ":memory:") (null (pathname-directory (pathname path))))
    (ensure-directories-exist (directory-namestring (pathname path))))
  (let* ((connection (sqlite:connect path :busy-timeout busy-timeout-ms))
         (database (make-sqlite-database :connection connection
                                         :statements (make-hash-table :test #'equal))))
    (sqlite:execute-non-query connection "PRAGMA journal_mode = WAL")
    (sqlite:execute-non-query connection "PRAGMA synchronous = NORMAL")
    (sqlite:execute-non-query connection
                              (format nil "PRAGMA wal_autocheckpoint = ~A" wal-auto-checkpoint-pages))
    (sqlite:execute-non-query connection
                              (format nil "PRAGMA busy_timeout = ~A" busy-timeout-ms))
    database))

(defun bind-statement (statement params)
  (loop for value in params
        for index from 1
        do (sqlite:bind-parameter statement index (if (json-null-p value) nil value))))

(defun sqlite-run-unlocked (database sql params)
  (let ((statement (sqlite-prepare database sql)))
    (sqlite:reset-statement statement)
    (sqlite:clear-statement-bindings statement)
    (bind-statement statement params)
    (sqlite:step-statement statement)
    nil))

(defun sqlite-get-unlocked (database sql params)
  (let ((statement (sqlite-prepare database sql)))
    (sqlite:reset-statement statement)
    (sqlite:clear-statement-bindings statement)
    (bind-statement statement params)
    (when (sqlite:step-statement statement)
      (sqlite-row statement))))

(defun sqlite-all-unlocked (database sql params)
  (let ((statement (sqlite-prepare database sql))
        (rows nil))
    (sqlite:reset-statement statement)
    (sqlite:clear-statement-bindings statement)
    (bind-statement statement params)
    (loop while (sqlite:step-statement statement)
          do (push (sqlite-row statement) rows))
    (nreverse rows)))

(defun sqlite-exec (database sql)
  (with-sqlite (database)
    (sqlite:execute-non-query (sqlite-database-connection database) sql)
    nil))

(defun sqlite-run (database sql &rest params)
  (with-sqlite (database)
    (sqlite-run-unlocked database sql params)))

(defun sqlite-get (database sql &rest params)
  (with-sqlite (database)
    (sqlite-get-unlocked database sql params)))

(defun sqlite-all (database sql &rest params)
  (with-sqlite (database)
    (sqlite-all-unlocked database sql params)))

(defstruct sqlite-handle database (active t))

(defun sqlite-transaction (database function)
  (with-sqlite (database)
    (let ((connection (sqlite-database-connection database))
          (handle (make-sqlite-handle :database database)))
      (sqlite:execute-non-query connection "BEGIN IMMEDIATE")
      (handler-case
          (unwind-protect
               (funcall function handle)
            (setf (sqlite-handle-active handle) nil))
        (error (condition)
          (handler-case (sqlite:execute-non-query connection "ROLLBACK")
            (error ()
              (error "SQLite transaction failed and rollback failed")))
          (error condition))
        (:no-error (value)
          (sqlite:execute-non-query connection "COMMIT")
          value)))))

(defun assert-handle (handle)
  (unless (sqlite-handle-active handle)
    (error "SQLite transaction handle is no longer active")))

(defun sqlite-handle-exec (handle sql)
  (assert-handle handle)
  (sqlite:execute-non-query (sqlite-database-connection (sqlite-handle-database handle)) sql))

(defun sqlite-handle-run (handle sql &rest params)
  (assert-handle handle)
  (sqlite-run-unlocked (sqlite-handle-database handle) sql params))

(defun sqlite-handle-get (handle sql &rest params)
  (assert-handle handle)
  (sqlite-get-unlocked (sqlite-handle-database handle) sql params))

(defun sqlite-close (database)
  (unless (sqlite-database-closed database)
    (ignore-errors
      (sqlite:execute-non-query (sqlite-database-connection database)
                                "PRAGMA wal_checkpoint(TRUNCATE)"))
    (ignore-errors (sqlite:disconnect (sqlite-database-connection database)))
    (setf (sqlite-database-closed database) t))
  nil)

(defun apply-sqlite-migrations (database migrations &key table)
  (validate-sqlite-schema-prefix table)
  (loop for migration in migrations
        for index from 1
        do (unless (eql (getf migration :version) index)
             (error "SQLite migrations must have contiguous versions starting at 1")))
  (sqlite-transaction
   database
   (lambda (transaction)
     (sqlite-handle-exec transaction
                         (format nil "CREATE TABLE IF NOT EXISTS ~A (
                            singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
                            version INTEGER NOT NULL CHECK (version >= 0)
                          ) STRICT" table))
     (sqlite-handle-run transaction
                        (format nil "INSERT OR IGNORE INTO ~A (singleton, version) VALUES (1, 0)" table))
     (let* ((row (sqlite-handle-get transaction
                                    (format nil "SELECT version FROM ~A WHERE singleton = 1" table)))
            (stored (json-get row "version"))
            (supported (or (getf (car (last migrations)) :version) 0)))
       (when (> stored supported)
         (error "SQLite schema version ~A is newer than supported version ~A" stored supported))
       (dolist (migration migrations)
         (when (> (getf migration :version) stored)
           (dolist (statement (getf migration :statements))
             (sqlite-handle-exec transaction statement))
           (sqlite-handle-run transaction
                              (format nil "UPDATE ~A SET version = ? WHERE singleton = 1" table)
                              (getf migration :version)))))))
  nil)

(defparameter +max-safe-integer+ 9007199254740991)

(defstruct durable-storage exec transaction)
(defstruct durable-cursor next to-array)
(defstruct durable-adapter storage queue)

(defvar *durable-queues* (make-hash-table :test #'eq))

(defun durable-queue (storage)
  (or (gethash storage *durable-queues*)
      (setf (gethash storage *durable-queues*)
            (sb-thread:make-mutex :name "chord-durable"))))

(defun bind-durable (value)
  (cond
    ((integerp value)
     (if (<= (- +max-safe-integer+) value +max-safe-integer+)
         value
         (error "Durable Object SQL cannot bind ~A without losing precision" value)))
    ((stringp value) value)
    ((json-null-p value) nil)
    ((vectorp value) value)
    (t value)))

(defun durable-row (row)
  (let ((copy (json-object)))
    (dolist (key (json-keys row))
      (let ((value (gethash key row)))
        (setf (gethash key copy)
              (cond
                ((null value) +json-null+)
                ((stringp value) value)
                ((vectorp value)
                 (let ((octets (make-array (length value) :element-type '(unsigned-byte 8))))
                   (replace octets value)
                   octets))
                (t value)))))
    copy))

(defun make-durable-object-sqlite-database (storage)
  (make-durable-adapter :storage storage :queue (durable-queue storage)))

(defun durable-object-storage (database)
  (durable-adapter-storage database))

(defun durable-exec-cursor (database sql params)
  (let* ((storage (durable-adapter-storage database))
         (bound (mapcar #'bind-durable params)))
    (apply (durable-storage-exec storage) sql bound)))

(defun sqlite-get-durable (database sql &rest params)
  (sb-thread:with-mutex ((durable-adapter-queue database))
    (let ((cursor (durable-exec-cursor database sql params)))
      (let ((step (funcall (durable-cursor-next cursor))))
        (unless (json-get step "done")
          (durable-row (json-get step "value")))))))

(defun sqlite-all-durable (database sql &rest params)
  (sb-thread:with-mutex ((durable-adapter-queue database))
    (let ((cursor (durable-exec-cursor database sql params)))
      (mapcar #'durable-row (funcall (durable-cursor-to-array cursor))))))
