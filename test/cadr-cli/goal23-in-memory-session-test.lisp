(in-package #:cadr-cli/tests)

(in-suite cadr-cli-suite)

(defun goal23-uuid-v7-p (id)
  (and (stringp id)
       (= 36 (length id))
       (char= #\- (char id 8))
       (char= #\- (char id 13))
       (char= #\7 (char id 14))
       (find (char id 19) "89ab")))

(defun goal23-in-memory
    (cwd &key id parent-session entries)
  (cadr-cli:session-manager-resolve
   (cadr-cli:session-manager-in-memory
    cwd
    :id id
    :parent-session parent-session
    :entries entries)))

(defun goal23-user-message (text)
  (cadr-ai:make-user-message
   :content text
   :timestamp (cadr-ai::unix-milliseconds)))

(defun goal23-stored-entries (cwd build)
  (let ((source (goal23-in-memory cwd)))
    (funcall build source)
    (cadr-agent:session-entries source)))

(defun goal23-message-role (entry)
  (let ((message (cadr-agent:session-entry-message entry)))
    (cond
      ((hash-table-p message)
       (cadr-ai::json-get message "role"))
      ((cadr-agent::session-json-message-p message)
       (cadr-agent::session-json-message-role message))
      ((typep message 'cadr-ai:user-message)
       "user")
      (t nil))))

(defun goal23-children (entries parent-id)
  (remove-if-not
   (lambda (entry)
     (equal (cadr-agent:session-entry-parent-id entry) parent-id))
   entries))

(test goal23-in-memory-adopts-entries-verbatim
  (with-test-directory (temporary)
    (let ((entries
            (goal23-stored-entries
             temporary
             (lambda (source)
               (cadr-agent:session-append-message
                source (goal23-user-message "hello"))
               (cadr-agent:session-append-model-change
                source "anthropic" "claude-opus-4-5")
               (cadr-agent:session-append-message
                source (goal23-user-message "again"))))))
      (let ((session
              (goal23-in-memory temporary :entries entries)))
        (is (equal entries (cadr-agent:session-entries session)))))))

(test goal23-in-memory-continues-from-loaded-leaf
  (with-test-directory (temporary)
    (let* ((entries
             (goal23-stored-entries
              temporary
              (lambda (source)
                (cadr-agent:session-append-message
                 source (goal23-user-message "hello"))
                (cadr-agent:session-append-message
                 source (goal23-user-message "again")))))
           (last-id
             (cadr-agent:session-entry-id (car (last entries))))
           (session
             (goal23-in-memory temporary :entries entries))
           (appended-id
             (cadr-agent:session-append-message
              session (goal23-user-message "continued"))))
      (is (string= appended-id (cadr-agent:session-leaf-id session)))
      (is
       (string=
        last-id
        (cadr-agent:session-entry-parent-id
         (find
          appended-id
          (cadr-agent:session-entries session)
          :key #'cadr-agent:session-entry-id
          :test #'string=)))))))

(test goal23-in-memory-never-mints-a-loaded-id
  (with-test-directory (temporary)
    (let* ((entries
             (goal23-stored-entries
              temporary
              (lambda (source)
                (dotimes (index 50)
                  (cadr-agent:session-append-message
                   source
                   (goal23-user-message
                    (format nil "message ~D" index)))))))
           (session
             (goal23-in-memory temporary :entries entries))
           (appended-id
             (cadr-agent:session-append-message
              session (goal23-user-message "continued"))))
      (is
       (not
        (member
         appended-id
         entries
         :key #'cadr-agent:session-entry-id
         :test #'string=))))))

(test goal23-in-memory-rebuilds-branch-tree
  (with-test-directory (temporary)
    (let* ((entries
             (goal23-stored-entries
              temporary
              (lambda (source)
                (let ((first-id
                        (cadr-agent:session-append-message
                         source (goal23-user-message "hello"))))
                  (cadr-agent:session-append-message
                   source (goal23-user-message "abandoned"))
                  (cadr-agent:session-branch source first-id)
                  (cadr-agent:session-append-message
                   source (goal23-user-message "kept"))))))
           (session
             (goal23-in-memory temporary :entries entries))
           (restored (cadr-agent:session-entries session))
           (root (first restored)))
      (is (= 1 (length (goal23-children restored nil))))
      (is
       (= 2
          (length
           (goal23-children
            restored
            (cadr-agent:session-entry-id root))))))))

(test goal23-in-memory-rebuilds-labels
  (with-test-directory (temporary)
    (let* ((labelled-id nil)
           (entries
             (goal23-stored-entries
              temporary
              (lambda (source)
                (setf labelled-id
                      (cadr-agent:session-append-message
                       source (goal23-user-message "hello")))
                (cadr-agent:session-set-label
                 source labelled-id "checkpoint"))))
           (session
             (goal23-in-memory temporary :entries entries)))
      (is
       (string=
        "checkpoint"
        (cadr-agent:session-label session labelled-id))))))

(test goal23-in-memory-resolves-compaction-against-written-first-kept
  (with-test-directory (temporary)
    (let* ((kept-id nil)
           (entries
             (goal23-stored-entries
              temporary
              (lambda (source)
                (cadr-agent:session-append-message
                 source (goal23-user-message "dropped"))
                (setf kept-id
                      (cadr-agent:session-append-message
                       source (goal23-user-message "kept")))
                (cadr-agent:session-append-compaction
                 source "summary so far" (list kept-id)
                 kept-id 1000))))
           (session
             (goal23-in-memory temporary :entries entries))
           (context
             (cadr-agent:session-context-entries session)))
      (is
       (member
        kept-id
        context
        :key #'cadr-agent:session-entry-id
        :test #'string=)))))

(test goal23-in-memory-header-from-options-when-entries-have-none
  (with-test-directory (temporary)
    (let* ((entries
             (goal23-stored-entries
              temporary
              (lambda (source)
                (cadr-agent:session-append-message
                 source (goal23-user-message "hello")))))
           (session
             (goal23-in-memory
              temporary
              :id "restored-session"
              :entries entries)))
      (is (string= "restored-session" (cadr-agent:session-id session)))
      (is
       (string=
        (namestring
         (uiop:ensure-directory-pathname temporary))
        (cadr-agent:session-cwd session))))))

(test goal23-in-memory-generates-session-id-when-options-omit-id
  (with-test-directory (temporary)
    (let* ((entries
             (goal23-stored-entries
              temporary
              (lambda (source)
                (cadr-agent:session-append-message
                 source (goal23-user-message "hello")))))
           (session
             (goal23-in-memory temporary :entries entries)))
      (is (goal23-uuid-v7-p (cadr-agent:session-id session))))))

(test goal23-in-memory-stays-off-the-filesystem
  (with-test-directory (temporary)
    (let* ((entries
             (goal23-stored-entries
              temporary
              (lambda (source)
                (cadr-agent:session-append-message
                 source (goal23-user-message "hello")))))
           (session
             (goal23-in-memory temporary :entries entries)))
      (cadr-agent:session-append-message
       session (goal23-user-message "continued"))
      (is (null (cadr-agent:session-path session)))
      (is (not (cadr-agent:session-persisted-p session)))
      (is
       (null
        (directory
         (merge-pathnames "*.jsonl" temporary)))))))

(test goal23-in-memory-empty-entries-keep-options-id
  (with-test-directory (temporary)
    (let ((session
            (goal23-in-memory
             temporary
             :id "empty-session"
             :entries nil)))
      (is (string= "empty-session" (cadr-agent:session-id session)))
      (is (null (cadr-agent:session-entries session)))
      (is (null (cadr-agent:session-leaf-id session))))))

(test goal23-in-memory-header-among-entries-wins-over-options-id
  (with-test-directory (temporary)
    (let* ((body
             (goal23-stored-entries
              temporary
              (lambda (source)
                (cadr-agent:session-append-message
                 source (goal23-user-message "hello")))))
           (entries
             (cons
              (cadr-ai::json-object
               "type" "session"
               "version" 3
               "id" "stored-session"
               "timestamp" "2026-01-01T00:00:00Z"
               "cwd" "/stored")
              body))
           (session
             (goal23-in-memory
              temporary
              :id "ignored"
              :entries entries)))
      (is (string= "stored-session" (cadr-agent:session-id session)))
      (is (string= "/stored" (cadr-agent:session-cwd session))))))

(test goal23-in-memory-migrates-older-header
  (with-test-directory (temporary)
    (let* ((entries
             (list
              (cadr-ai::json-object
               "type" "session"
               "version" 2
               "id" "v2-session"
               "timestamp" "2026-01-01T00:00:00Z"
               "cwd" (namestring temporary))
              (cadr-ai::json-object
               "type" "message"
               "id" "abc12345"
               "parentId" 'null
               "timestamp" "2026-01-01T00:00:01Z"
               "message"
               (cadr-ai::json-object
                "role" "hookMessage"
                "content" "from a hook"
                "timestamp" 1))))
           (session
             (goal23-in-memory temporary :entries entries))
           (restored (first (cadr-agent:session-entries session))))
      (is (= 3 (cadr-agent:session-version session)))
      (is (string= "custom" (goal23-message-role restored)))
      (is (string= "abc12345" (cadr-agent:session-entry-id restored))))))

(test goal23-in-memory-headerless-entries-skip-hook-message-migration
  (with-test-directory (temporary)
    (let* ((entries
             (list
              (cadr-ai::json-object
               "type" "message"
               "id" "abc12345"
               "parentId" 'null
               "timestamp" "2026-01-01T00:00:01Z"
               "message"
               (cadr-ai::json-object
                "role" "hookMessage"
                "content" "from a hook"
                "timestamp" 1))))
           (session
             (goal23-in-memory temporary :entries entries))
           (restored (first (cadr-agent:session-entries session))))
      (is (string= "hookMessage" (goal23-message-role restored))))))
