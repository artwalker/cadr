(in-package #:cadr-storage/tests)

(in-suite cadr-storage-suite)

(defmacro with-storage-directory
    ((directory) &body body)
  `(let ((,directory
           (uiop:ensure-directory-pathname
            (uiop:temporary-directory))))
     (let ((,directory
             (merge-pathnames
              (format nil "cadr-storage-~36R/"
                      (random most-positive-fixnum))
              ,directory)))
       (ensure-directories-exist
        (merge-pathnames "anchor" ,directory))
       (unwind-protect
            (progn ,@body)
         (uiop:delete-directory-tree
          ,directory
          :validate t
          :if-does-not-exist :ignore)))))

(test standalone-storage-package-exports-the-reference-contract
  (dolist
      (name
       '("SQLITE-SESSION-REPOSITORY"
         "SQLITE-SESSION-STORAGE"
         "MAKE-SQLITE-SESSION-REPOSITORY"
         "OPEN-SQLITE-DATABASE"
         "CLOSE-SQLITE-DATABASE"
         "APPLY-SQLITE-MIGRATIONS"
         "SQLITE-EXECUTE-NAMED"
         "SQLITE-QUERY-SINGLE-NAMED"))
    (multiple-value-bind (symbol status)
        (find-symbol name :cadr-storage)
      (is symbol)
      (is (eq :external status)))))

(test standalone-storage-repository-creates-reopens-lists-forks-and-deletes
  (with-storage-directory (root)
    (let* ((database
             (merge-pathnames "sessions.sqlite" root))
           (cwd
             (merge-pathnames "workspace/" root))
           (repository
             (cadr-storage:make-sqlite-session-repository
              :database-path database))
           (session
             (cadr-agent:session-repository-create
              repository
              :id "source"
              :cwd cwd
              :metadata '(:purpose "wave5")))
           (entry
             (cadr-agent:harness-session-append-message
              session
              (cadr-ai:make-user-message
               :content "hello"
               :timestamp 100))))
      (cadr-agent:harness-session-cleanup session)
      (let ((metadata
              (first
               (cadr-agent:session-repository-list
                repository :cwd cwd))))
        (is (string=
             "source"
             (cadr-agent:session-metadata-id metadata)))
        (let ((reopened
                (cadr-agent:session-repository-open
                 repository metadata)))
          (is (= 1
                 (length
                  (cadr-agent:harness-session-entries
                   reopened))))
          (cadr-agent:harness-session-cleanup reopened))
        (let ((fork
                (cadr-agent:session-repository-fork
                 repository metadata
                 :id "fork"
                 :cwd cwd
                 :entry-id entry
                 :position :at)))
          (is (= 1
                 (length
                  (cadr-agent:harness-session-entries
                   fork))))
          (cadr-agent:harness-session-cleanup fork))
        (is (= 2
               (length
                (cadr-agent:session-repository-list
                 repository))))
        (cadr-agent:session-repository-delete
         repository metadata)
        (is (= 1
               (length
                (cadr-agent:session-repository-list
                 repository))))))))

(test standalone-storage-adapter-applies-migrations-and-named-parameters
  (with-storage-directory (root)
    (let* ((path
             (merge-pathnames "adapter.sqlite" root))
           (database
             (cadr-storage:open-sqlite-database path)))
      (unwind-protect
           (progn
             (cadr-storage:apply-sqlite-migrations
              database)
             (is
              (string=
               "001_initial.sql"
               (sqlite:execute-single
                database
                "SELECT id FROM migrations")))
             (sqlite:execute-non-query
              database
              "CREATE TABLE named_values
                 (id INTEGER PRIMARY KEY, value TEXT)")
             (cadr-storage:sqlite-execute-named
              database
              "INSERT INTO named_values
                 (id, value) VALUES ($id, $value)"
              '(("$id" . 1)
                ("$value" . "ok")))
             (is
              (string=
               "ok"
               (cadr-storage:sqlite-query-single-named
                database
                "SELECT value FROM named_values
                  WHERE id = $id"
                '(("$id" . 1))))))
        (cadr-storage:close-sqlite-database
         database)))))
