(in-package #:cadr-agent/tests)
(in-suite cadr-agent-suite)

(test sqlite-session-storage-applies-schema-and-reopens-materialized-state
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((database
             (merge-pathnames "sessions.sqlite" sessions))
           (repository
             (cadr-agent:make-sqlite-session-repository
              :database-path database))
           (session
             (cadr-agent:session-repository-create
              repository
              :id "session-1"
              :cwd cwd
              :metadata '(:profile "reviewer")))
           (root
             (cadr-agent:harness-session-append-message
              session
              (cadr-ai:make-user-message
               :content "root"
               :timestamp 100))))
      (cadr-agent:harness-session-append-message
       session
       (cadr-ai:make-assistant-message
        :content
        (list
         (cadr-ai:make-text-content :text "child"))
        :api :openai-responses
        :provider :openai
        :model "mock"
        :usage
        (cadr-ai:make-usage
         :input 10
         :output 20
         :cache-read 30
         :cache-write 40
         :cost
         (cadr-ai:make-cost :total 1d0))
        :stop-reason :stop
        :timestamp 101))
      (cadr-agent:harness-session-set-name
       session "  Reopened Session  ")
      (cadr-agent:harness-session-set-leaf-id
       session root)
      (let ((db
              (sqlite:connect database)))
        (unwind-protect
             (progn
               (is
                (equal
                 '("001_initial.sql")
                 (mapcar
                  #'first
                  (sqlite:execute-to-list
                   db
                   "SELECT id FROM migrations ORDER BY id"))))
               (let ((tables
                       (mapcar
                        #'first
                        (sqlite:execute-to-list
                         db
                         "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name"))))
                 (dolist
                     (name
                      '("sessions"
                        "session_entries"
                        "session_sequences"
                        "branch_entries"
                        "session_materialized"
                        "entry_materialized"))
                   (is (member name tables
                               :test #'string=))))
               (is
                (string=
                 root
                 (sqlite:execute-single
                  db
                  "SELECT active_leaf_id FROM sessions WHERE id = ?"
                  "session-1"))))
          (sqlite:disconnect db)))
      (cadr-agent:harness-session-cleanup session)
      (let ((reopened
              (cadr-agent:session-repository-open
               repository
               (cadr-agent:harness-session-metadata
                session))))
        (is
         (string=
          root
          (cadr-agent:harness-session-leaf-id
           reopened)))
        (is
         (string=
          "Reopened Session"
          (cadr-agent:harness-session-name
           reopened)))
        (is
         (= 4
            (length
             (cadr-agent:harness-session-entries
              reopened))))
        (let ((stats
                (cadr-agent:harness-session-stats
                 reopened)))
          (is (= 2 (getf stats :message-count)))
          (is (= 100 (getf stats :total-tokens)))
          (is (= 1d0 (getf stats :cost-total))))
        (cadr-agent:harness-session-cleanup
         reopened)))))

(test sqlite-session-repository-lists-forks-deletes-and-rolls-back
  (with-session-directories (sessions cwd other-cwd)
    (let* ((database
             (merge-pathnames "sessions.sqlite" sessions))
           (repository
             (cadr-agent:make-sqlite-session-repository
              :database-path database))
           (source
             (cadr-agent:session-repository-create
              repository
              :id "source"
              :cwd cwd))
           (root
             (cadr-agent:harness-session-append-message
              source
              (cadr-ai:make-user-message
               :content "root"
               :timestamp 100))))
      (cadr-agent:harness-session-append-message
       source
       (cadr-ai:make-user-message
        :content "child"
        :timestamp 101))
      (is
       (equal
        '("source")
        (mapcar
         #'cadr-agent:session-metadata-id
         (cadr-agent:session-repository-list
          repository :cwd cwd))))
      (let ((fork
              (cadr-agent:session-repository-fork
               repository
               (cadr-agent:harness-session-metadata
                source)
               :id "fork"
               :cwd other-cwd
               :entry-id root
               :position :at)))
        (is
         (= 1
            (length
             (cadr-agent:harness-session-entries
              fork))))
        (cadr-agent:harness-session-cleanup fork))
      (let ((duplicate
              (storage-user-entry
               root nil "duplicate" 102))
            (before
              (length
               (cadr-agent:harness-session-entries
                source))))
        (signals cadr-agent:session-error
          (cadr-agent:session-storage-append-entry
           (cadr-agent:harness-session-storage
            source)
           duplicate))
        (is
         (= before
            (length
             (cadr-agent:harness-session-entries
              source)))))
      (cadr-agent:harness-session-cleanup source)
      (let ((metadata
              (find
               "source"
               (cadr-agent:session-repository-list
                repository)
               :key
               #'cadr-agent:session-metadata-id
               :test #'string=)))
        (cadr-agent:session-repository-delete
         repository metadata)
        (signals cadr-agent:session-error
          (cadr-agent:session-repository-open
           repository metadata))
        (signals cadr-agent:session-error
          (cadr-agent:session-repository-delete
           repository metadata))))))

(test sqlite-named-parameter-adapter-matches-reference-contract
  (with-session-directories (sessions cwd other-cwd)
    (values cwd other-cwd)
    (let ((database
            (merge-pathnames "adapter.sqlite" sessions)))
      (let ((db (sqlite:connect database)))
        (unwind-protect
             (progn
               (sqlite:execute-non-query
                db
                "CREATE TABLE items (id INTEGER PRIMARY KEY, text TEXT NOT NULL)")
               (cadr-agent:sqlite-execute-named
                db
                "INSERT INTO items (id, text) VALUES ($id, $text)"
                '(("$id" . 1)
                  ("$text" . "hello")))
               (is
                (string=
                 "hello"
                 (cadr-agent:sqlite-query-single-named
                  db
                  "SELECT text FROM items WHERE id = $id"
                  '(("$id" . 1))))))
          (sqlite:disconnect db))))))

(test sqlite-session-storage-materializes-new-branches
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((database
             (merge-pathnames "branches.sqlite" sessions))
           (repository
             (cadr-agent:make-sqlite-session-repository
              :database-path database))
           (session
             (cadr-agent:session-repository-create
              repository
              :id "session-1"
              :cwd cwd))
           (root
             (cadr-agent:harness-session-append-message
              session
              (cadr-ai:make-user-message
               :content "root"
               :timestamp 100)))
           (first-child
             (cadr-agent:harness-session-append-message
              session
              (cadr-ai:make-user-message
               :content "first"
               :timestamp 101))))
      (cadr-agent:harness-session-set-leaf-id
       session root)
      (let ((second-child
              (cadr-agent:harness-session-append-message
               session
               (cadr-ai:make-user-message
                :content "second"
                :timestamp 102))))
        (let ((db (sqlite:connect database)))
          (unwind-protect
               (let ((rows
                       (sqlite:execute-to-list
                        db
                        "SELECT branch_id, entry_id
                           FROM branch_entries
                          WHERE session_id = ?
                          ORDER BY branch_id, entry_seq"
                        "session-1")))
                 (is
                  (= 3
                     (length
                      (remove-duplicates
                       (mapcar #'first rows)
                       :test #'string=))))
                 (is
                  (= 3
                     (count root rows
                            :key #'second
                            :test #'string=)))
                 (is
                  (= 1
                     (count first-child rows
                            :key #'second
                            :test #'string=)))
                 (is
                  (= 1
                     (count second-child rows
                            :key #'second
                            :test #'string=))))
            (sqlite:disconnect db))))
      (cadr-agent:harness-session-cleanup
       session))))

(test sqlite-session-ingests-pairing-fixture-then-open-read-walk
  ;; Production path used by scripts/goal20-paired-paths.lisp sqlite_session.
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((root (asdf:system-source-directory "cadr-agent"))
           (fixture
             (merge-pathnames
              "test/fixtures/goal20-paired-paths/session.jsonl"
              root))
           (database
             (merge-pathnames "paired.sqlite" sessions))
           (source (cadr-agent:load-session fixture))
           (repository
             (cadr-agent:make-sqlite-session-repository
              :database-path database))
           (written
             (cadr-agent:session-repository-create
              repository
              :id (cadr-agent:session-id source)
              :cwd cwd)))
      (dolist (entry (cadr-agent:session-entries source))
        (cadr-agent:harness-session-append-entry written entry))
      (let ((metadata (cadr-agent:harness-session-metadata written))
            (source-count (length (cadr-agent:session-entries source)))
            (source-leaf (cadr-agent:session-leaf-id source)))
        (cadr-agent:harness-session-cleanup written)
        (let ((opened
                (cadr-agent:session-repository-open
                 repository metadata)))
          (is (= source-count
                 (length (cadr-agent:harness-session-entries opened))))
          (is (string= source-leaf
                       (cadr-agent:harness-session-leaf-id opened)))
          (is (plusp
               (length (cadr-agent:harness-session-branch opened))))
          (cadr-agent:harness-session-cleanup opened))))))
