(in-package #:cadr-core/tests)

(in-suite cadr-core-suite)

(defun durable-error-text (thunk)
  (handler-case (progn (funcall thunk) nil)
    (error (condition) (princ-to-string condition))))

(defun durable-json (pairs)
  (let ((object (cadr-chord:json-object)))
    (loop for (key value) on pairs by #'cddr
          do (cadr-chord:json-put object key value))
    object))

(test durable-memory-reserves-root-and-rejects-a-second-owner
  (let ((storage (cadr-durable:make-memory-storage)))
    (cadr-durable:storage-commit
     storage (list (cons :conversation (cadr-durable:make-conversation))))
    (is (= 1 (cadr-durable:conversation-id
              (cadr-durable:storage-conversation storage 1))))
    (is (equal '("pi.user" "pi.assistant" "pi.system" "pi.tool-result"
                 "pi.reset" "pi.compaction")
               (list (cadr-durable:user-entry-kind)
                     (cadr-durable:assistant-entry-kind)
                     (cadr-durable:system-entry-kind)
                     (cadr-durable:tool-result-entry-kind)
                     (cadr-durable:reset-entry-kind)
                     (cadr-durable:compaction-entry-kind))))
    (is (string= "ID 1 already belongs to conversation"
                 (durable-error-text
                  (lambda ()
                    (cadr-durable:storage-commit
                     storage (list (cons :conversation
                                         (cadr-durable:make-conversation :id 1))))))))
    (cadr-durable:storage-close storage)
    (is (string= "MemoryStorage is closed"
                 (durable-error-text
                  (lambda () (cadr-durable:storage-mint-id storage)))))))

(test durable-mint-stops-at-the-end-of-the-safe-integer-space
  (let ((storage (cadr-durable:make-memory-storage)))
    (cadr-durable:storage-commit
     storage
     (list (cons :conversation (cadr-durable:make-conversation))
           (cons :entry (cadr-durable:make-entry
                         :id cadr-durable:+max-safe-integer+
                         :conversation-id 1 :kind "pi.user"))))
    (is (string= "ID space is exhausted"
                 (durable-error-text
                  (lambda () (cadr-durable:storage-mint-id storage)))))
    (is (string= "ID space is exhausted"
                 (durable-error-text
                  (lambda () (cadr-durable:storage-mint-id storage)))))))

(test durable-failed-commit-keeps-the-previous-records
  (let ((storage (cadr-durable:make-memory-storage)))
    (cadr-durable:storage-commit
     storage (list (cons :conversation (cadr-durable:make-conversation))
                   (cons :task (cadr-durable:make-task-record
                                :id 2 :kind "job" :conversation-id 1
                                :state (cadr-chord:json-object "status" "pending")))))
    (is (string= "ID 2 already belongs to task"
                 (durable-error-text
                  (lambda ()
                    (cadr-durable:storage-commit
                     storage
                     (list (cons :entry (cadr-durable:make-entry
                                         :id 2 :conversation-id 1 :kind "pi.user"))
                           (cons :submission
                                 (cadr-durable::make-submission-record
                                  :id 3 :conversation-id 1 :type "input"
                                  :status "queued"))))))))
    (is (cadr-durable:storage-task storage 2))
    (is (null (cadr-durable:storage-entry storage 3)))))

(test durable-jsonl-drops-a-torn-tail-and-rejects-a-malformed-line
  (let ((directory (merge-pathnames (format nil "cadr-durable-~A/" (random 1000000))
                                    (uiop:temporary-directory))))
    (ensure-directories-exist directory)
    (unwind-protect
         (progn
           (let ((storage (cadr-durable:open-jsonl-storage directory)))
             (cadr-durable:storage-commit
              storage (list (cons :conversation (cadr-durable:make-conversation))))
             (cadr-durable:storage-close storage))
           (let ((path (merge-pathnames "main.jsonl" directory)))
             (with-open-file (stream path :direction :output :if-exists :append
                                          :element-type '(unsigned-byte 8))
               (write-sequence (sb-ext:string-to-octets "{torn" :external-format :utf-8)
                               stream)))
           (let ((storage (cadr-durable:open-jsonl-storage directory)))
             (is (= 1 (cadr-durable:conversation-id
                       (cadr-durable:storage-conversation storage 1))))
             (cadr-durable:storage-close storage))
           (with-open-file (stream (merge-pathnames "broken.jsonl" directory)
                                   :direction :output :if-exists :supersede)
             (write-line "{bad}" stream))
           (with-open-file (stream (merge-pathnames "doc-01.jsonl" directory)
                                   :direction :output :if-exists :supersede)
             (write-line "{bad}" stream))
           (let ((storage (cadr-durable:open-jsonl-storage directory)))
             (is (= 1 (cadr-durable:conversation-id
                       (cadr-durable:storage-conversation storage 1))))
             (cadr-durable:storage-close storage))
           (let* ((path (merge-pathnames "main.jsonl" directory))
                  (line (1+ (count #\Newline (uiop:read-file-string path)))))
             (with-open-file (stream path :direction :output :if-exists :append)
               (write-line "{bad}" stream))
             (is (string= (format nil "Malformed complete main.jsonl line ~A" line)
                          (durable-error-text
                           (lambda () (cadr-durable:open-jsonl-storage directory))))))
           (let ((sidecar (merge-pathnames (format nil "cadr-durable-side-~A/" (random 1000000))
                                           (uiop:temporary-directory))))
             (unwind-protect
                  (progn
                    (cadr-durable:storage-close
                     (cadr-durable:open-jsonl-storage sidecar))
                    (with-open-file (stream (merge-pathnames "doc-99.jsonl" sidecar)
                                            :direction :output :if-exists :supersede)
                      (write-line "{bad}" stream))
                    (is (string= "Malformed complete doc-99.jsonl line 1"
                                 (durable-error-text
                                  (lambda () (cadr-durable:open-jsonl-storage sidecar)))))
                    (delete-file (merge-pathnames "doc-99.jsonl" sidecar))
                    (with-open-file (stream (merge-pathnames "task-7.jsonl" sidecar)
                                            :direction :output :if-exists :supersede)
                      (write-line "{bad}" stream))
                    (is (string= "Malformed complete task-7.jsonl line 1"
                                 (durable-error-text
                                  (lambda () (cadr-durable:open-jsonl-storage sidecar)))))
                    (delete-file (merge-pathnames "task-7.jsonl" sidecar))
                    (with-open-file (stream (merge-pathnames "doc-99.jsonl" sidecar)
                                            :direction :output :if-exists :supersede)
                      (write-line "{}" stream))
                    (is (string= "Invalid sidecar record in doc-99.jsonl line 1"
                                 (durable-error-text
                                  (lambda () (cadr-durable:open-jsonl-storage sidecar)))))
                    (delete-file (merge-pathnames "doc-99.jsonl" sidecar))
                    (with-open-file (stream (merge-pathnames "doc-99.jsonl" sidecar)
                                            :direction :output :if-exists :supersede)
                      (write-line "" stream))
                    (is (string= "Malformed complete doc-99.jsonl line 1"
                                 (durable-error-text
                                  (lambda () (cadr-durable:open-jsonl-storage sidecar)))))
                    (delete-file (merge-pathnames "doc-99.jsonl" sidecar))
                    (with-open-file (stream (merge-pathnames "doc-99.jsonl" sidecar)
                                            :direction :output :if-exists :supersede)
                      (write-line "{\"format\":1,\"type\":\"record\",\"seq\":1,\"ordinal\":0,\"payload\":{\"type\":\"document\",\"id\":1,\"content\":{\"kind\":\"base\",\"version\":1,\"value\":{}}}}" stream))
                    (is (null (durable-error-text
                               (lambda ()
                                 (cadr-durable:storage-close
                                  (cadr-durable:open-jsonl-storage sidecar))))))
                    (delete-file (merge-pathnames "doc-99.jsonl" sidecar))
                    (with-open-file (stream (merge-pathnames "task-7.jsonl" sidecar)
                                            :direction :output :if-exists :supersede)
                      (write-line "{\"format\":1,\"type\":\"record\",\"seq\":1,\"ordinal\":0,\"payload\":{\"type\":\"task\",\"value\":{\"id\":7,\"state\":{\"status\":\"terminal\"}}}}" stream))
                    (is (string= "Invalid live task record in task-7.jsonl line 1"
                                 (durable-error-text
                                  (lambda () (cadr-durable:open-jsonl-storage sidecar))))))
               (uiop:delete-directory-tree sidecar :validate t)))
           (let ((blank (merge-pathnames (format nil "cadr-durable-blank-~A/" (random 1000000))
                                         (uiop:temporary-directory))))
             (unwind-protect
                  (progn
                    (ensure-directories-exist blank)
                    (with-open-file (stream (merge-pathnames "main.jsonl" blank)
                                            :direction :output :if-exists :supersede)
                      (write-line "" stream))
                    (is (string= "Malformed complete main.jsonl line 1"
                                 (durable-error-text
                                  (lambda () (cadr-durable:open-jsonl-storage blank))))))
               (uiop:delete-directory-tree blank :validate t))))
      (uiop:delete-directory-tree directory :validate t))))

(test durable-sqlite-reopens-and-namespaces-its-tables
  (let* ((directory (merge-pathnames (format nil "cadr-durable-sql-~A/" (random 1000000))
                                     (uiop:temporary-directory)))
         (path (merge-pathnames "storage.sqlite" directory)))
    (ensure-directories-exist directory)
    (unwind-protect
         (progn
           (let ((storage (cadr-durable:open-sqlite-storage path :prefix "pi_")))
             (cadr-durable:storage-commit
              storage (list (cons :conversation (cadr-durable:make-conversation))))
             (let ((names (mapcar (lambda (row) (cadr-chord:json-get row "name"))
                                  (cadr-chord:sqlite-all
                                   (cadr-durable::durable-storage-database storage)
                                   "SELECT name FROM sqlite_master WHERE name LIKE 'pi_%'"))))
               (is (member "pi_tasks" names :test #'string=))
               (is (member "pi_conversations" names :test #'string=)))
             (cadr-durable:storage-close storage))
           (let ((storage (cadr-durable:open-sqlite-storage path :prefix "pi_")))
             (is (= 1 (cadr-durable:conversation-id
                       (cadr-durable:storage-conversation storage 1))))
             (cadr-durable:storage-close storage))
           (let ((database (cadr-chord:open-node-sqlite-database (namestring path))))
             (cadr-chord:sqlite-exec database "DELETE FROM pi_durable_metadata")
             (cadr-chord:sqlite-close database))
           (is (string= "Durable SQLite metadata is missing"
                        (durable-error-text
                         (lambda () (cadr-durable:open-sqlite-storage path :prefix "pi_"))))))
      (uiop:delete-directory-tree directory :validate t))))

(test durable-sqlite-rejects-a-bad-prefix-before-creating-the-directory
  (let* ((directory (merge-pathnames (format nil "cadr-durable-prefix-~A/" (random 1000000))
                                     (uiop:temporary-directory)))
         (nested (merge-pathnames "nested/" directory))
         (path (merge-pathnames "storage.sqlite" nested)))
    (unwind-protect
         (progn
           (is (search "Invalid SQLite schema prefix"
                       (durable-error-text
                        (lambda ()
                          (cadr-durable:open-sqlite-storage path :prefix "bad-prefix")))))
           (is (null (probe-file nested))))
      (when (probe-file directory)
        (uiop:delete-directory-tree directory :validate t)))))

(test durable-documents-publish-one-base-and-share-unchanged-parts
  (let* ((storage (cadr-durable:make-memory-storage))
         (session (cadr-durable:open-session storage))
         (doc (cadr-durable:define-doc
               "live"
               :initial (cadr-chord:json-object
                         "message" "hi"
                         "items" (cadr-chord:json-array "a" "b")
                         "nested" (cadr-chord:json-object "count" 0)
                         "other" (cadr-chord:json-object "label" "x")))))
    (cadr-durable:storage-commit
     storage (list (cons :conversation (cadr-durable:make-conversation))))
    (cadr-durable:session-commit
     session
     (lambda (tx)
       (let ((live (cadr-durable:tx-doc tx doc 1)))
         (setf (gethash "message" live) "edited"))))
    (let ((found (cadr-durable:storage-find-document storage "live" "conversation" 1 nil :current)))
      (is (string= "base" (cadr-durable::document-revision-kind
                           (first (cadr-durable::document-record-revisions (car found))))))
      (is (string= "edited" (gethash "message" (cdr found)))))
    (let ((first (cadr-durable:session-snapshot session doc 1)))
      (cadr-durable:session-commit
       session
       (lambda (tx)
         (setf (gethash "count" (gethash "nested" (cadr-durable:tx-doc tx doc 1))) 1)))
      (let ((second (cadr-durable:session-snapshot session doc 1)))
        (is (= 0 (gethash "count" (gethash "nested" first))))
        (is (= 1 (gethash "count" (gethash "nested" second))))
        (is (eq (gethash "items" first) (gethash "items" second)))))
    (is (null (cadr-durable:session-snapshot session doc 99)))
    (let ((before (cadr-durable::durable-state-seq
                   (cadr-durable::durable-storage-state storage))))
      (cadr-durable:session-commit
       session
       (lambda (tx)
         (let ((items (gethash "items" (cadr-durable:tx-doc tx doc 1))))
           (cadr-durable:draft-push items "z")
           (cadr-durable:draft-pop items))))
      (is (= before (cadr-durable::durable-state-seq
                     (cadr-durable::durable-storage-state storage)))))
    (let ((before (cadr-durable:session-snapshot session doc 1)))
      (cadr-durable:session-commit
       session
       (lambda (tx)
         (let* ((items (gethash "items" (cadr-durable:tx-doc tx doc 1)))
                (first (cadr-durable:draft-shift items)))
           (cadr-durable:draft-unshift items first))))
      (let ((after (cadr-durable:session-snapshot session doc 1)))
        (is (string= (cadr-chord:canonical-json before) (cadr-chord:canonical-json after)))
        (is (not (eq before after)))))
    (let ((value (cadr-chord:json-object "label" "shared")))
      (cadr-durable:session-commit
       session
       (lambda (tx)
         (let ((live (cadr-durable:tx-doc tx doc 1)))
           (cadr-durable:doc-set live "other" value)
           (cadr-durable:doc-set live "copy" value)
           (setf (gethash "label" value) "mutated"))))
      (let ((snapshot (cadr-durable:session-snapshot session doc 1)))
        (is (string= "shared" (gethash "label" (gethash "other" snapshot))))
        (is (string= "shared" (gethash "label" (gethash "copy" snapshot))))
        (is (not (eq (gethash "copy" snapshot) (gethash "other" snapshot))))
        (is (not (eq (gethash "other" snapshot) value)))))))

(test durable-read-after-write-and-session-failure-are-exact
  (let* ((storage (cadr-durable:make-memory-storage))
         (session (cadr-durable:open-session storage)))
    (cadr-durable:storage-commit
     storage (list (cons :conversation (cadr-durable:make-conversation))))
    (is (string= "Tx.scanEntries() cannot read tables after the first table write"
                 (durable-error-text
                  (lambda ()
                    (cadr-durable:session-commit
                     session
                     (lambda (tx)
                       (cadr-durable:tx-append-entry
                        tx :conversation-id 1 :kind "pi.user"
                        :model (cadr-chord:json-object "role" "user" "content" "hi"))
                       (cadr-durable:tx-scan-entries tx 1)))))))
    (cadr-durable:storage-close storage)
    (is (string= "MemoryStorage is closed"
                 (durable-error-text
                  (lambda ()
                    (cadr-durable:session-commit session (lambda (tx) (declare (ignore tx))))))))
    (is (string= "Session failed after a storage error; close and reopen it"
                 (durable-error-text
                  (lambda ()
                    (cadr-durable:session-commit session (lambda (tx) (declare (ignore tx))))))))))

(test durable-fork-copies-the-store-as-of-the-entry
  (let* ((storage (cadr-durable:make-memory-storage))
         (session (cadr-durable:open-session storage)))
    (cadr-durable:storage-commit
     storage (list (cons :conversation (cadr-durable:make-conversation))))
    (cadr-durable:codemode-store session 1 "token" "first")
    (cadr-durable:session-commit
     session
     (lambda (tx)
       (cadr-durable:tx-append-entry
        tx :conversation-id 1 :kind "pi.user"
        :model (cadr-chord:json-object "role" "user" "content" "go"))))
    (let ((entry (first (cadr-durable:page-items
                         (cadr-durable:storage-scan-entries storage 1
                                                           :order "ascending" :limit 1)))))
      (is (string= "Entry 99 is not visible from conversation 1"
                   (durable-error-text
                    (lambda () (cadr-durable:session-fork session 1 99)))))
      (let ((child (cadr-durable:session-fork session 1 (cadr-durable:entry-id entry))))
        (cadr-durable:codemode-store session 1 "token" "later")
        (is (string= "first" (cadr-durable:codemode-load session child "token")))
        (is (string= "later" (cadr-durable:codemode-load session 1 "token")))))))

(defun durable-policy-doc (name history fork &key family)
  (cadr-durable:define-doc name :scope "conversation" :history history :fork fork
                           :family family
                           :initial (cadr-chord:json-object "value" "initial")))

(defun durable-set-doc (session definition scope value &optional key)
  (cadr-durable:session-commit
   session
   (lambda (tx)
     (setf (gethash "value" (cadr-durable:tx-doc tx definition scope key)) value))))

(defun durable-doc-value (session definition scope &optional key)
  (let ((snapshot (cadr-durable:session-snapshot session definition scope key)))
    (when snapshot (gethash "value" snapshot))))

(test durable-fork-copies-as-of-and-current-and-leaves-initial
  (let* ((storage (cadr-durable:make-memory-storage))
         (session (cadr-durable:open-session storage))
         (as-of (durable-policy-doc "fork.policies.as-of" "rewindable" "asOf"))
         (current (durable-policy-doc "fork.policies.current" "latest" "current"))
         (initial (durable-policy-doc "fork.policies.initial" "latest" "initial"))
         (as-family (durable-policy-doc "fork.policies.as-of-family" "rewindable" "asOf"
                                        :family t))
         (current-family (durable-policy-doc "fork.policies.current-family" "latest" "current"
                                             :family t)))
    (cadr-durable:storage-commit
     storage (list (cons :conversation (cadr-durable:make-conversation))))
    (cadr-durable:session-commit
     session
     (lambda (tx)
       (setf (gethash "value" (cadr-durable:tx-doc tx as-of 1)) "as-at-fork")
       (setf (gethash "value" (cadr-durable:tx-doc tx current 1)) "current-at-fork")
       (setf (gethash "value" (cadr-durable:tx-doc tx initial 1)) "parent-only")
       (setf (gethash "value" (cadr-durable:tx-doc tx as-family 1 "a")) "family-as-a")
       (setf (gethash "value" (cadr-durable:tx-doc tx as-family 1 "b")) "family-as-b")
       (setf (gethash "value" (cadr-durable:tx-doc tx current-family 1 "a")) "family-current-a")
       (cadr-durable:tx-append-entry tx :conversation-id 1 :kind "fork-point")))
    (durable-set-doc session as-of 1 "as-after-fork")
    (durable-set-doc session current 1 "current-when-copied")
    (durable-set-doc session as-family 1 "family-as-after" "a")
    (durable-set-doc session current-family 1 "family-current-when-copied" "a")
    (let* ((entry (find "fork-point" (cadr-durable:page-items
                                      (cadr-durable:storage-scan-entries
                                       storage 1 :order "ascending" :limit 10))
                        :key #'cadr-durable:entry-kind :test #'string=))
           (child (cadr-durable:session-fork session 1 (cadr-durable:entry-id entry))))
      (is (string= "as-at-fork" (durable-doc-value session as-of child)))
      (is (string= "current-when-copied" (durable-doc-value session current child)))
      (is (null (cadr-durable:session-snapshot session initial child)))
      (is (string= "family-as-a" (durable-doc-value session as-family child "a")))
      (is (string= "family-as-b" (durable-doc-value session as-family child "b")))
      (is (string= "family-current-when-copied"
                   (durable-doc-value session current-family child "a")))
      (durable-set-doc session as-of child "child-independent")
      (is (string= "as-after-fork" (durable-doc-value session as-of 1)))
      (is (string= "child-independent" (durable-doc-value session as-of child)))
      (durable-set-doc session initial child "child-created")
      (is (string= "child-created" (durable-doc-value session initial child))))))

(test durable-fork-uses-the-entry-owner-for-as-of-and-the-parent-for-current
  (let* ((storage (cadr-durable:make-memory-storage))
         (session (cadr-durable:open-session storage))
         (as-of (durable-policy-doc "fork.ancestry.as-of" "rewindable" "asOf"))
         (current (durable-policy-doc "fork.ancestry.current" "latest" "current")))
    (cadr-durable:storage-commit
     storage (list (cons :conversation (cadr-durable:make-conversation))))
    (cadr-durable:session-commit
     session
     (lambda (tx)
       (setf (gethash "value" (cadr-durable:tx-doc tx as-of 1)) "root-at-entry")
       (setf (gethash "value" (cadr-durable:tx-doc tx current 1)) "root-current")
       (cadr-durable:tx-append-entry tx :conversation-id 1 :kind "root")))
    (let* ((inherited (find "root" (cadr-durable:page-items
                                    (cadr-durable:storage-scan-entries
                                     storage 1 :order "ascending" :limit 10))
                            :key #'cadr-durable:entry-kind :test #'string=))
           (parent (cadr-durable:session-fork session 1 (cadr-durable:entry-id inherited))))
      (cadr-durable:session-commit
       session
       (lambda (tx)
         (setf (gethash "value" (cadr-durable:tx-doc tx as-of parent)) "parent-at-own-entry")
         (setf (gethash "value" (cadr-durable:tx-doc tx current parent)) "parent-current")
         (cadr-durable:tx-append-entry tx :conversation-id parent :kind "parent")))
      (let ((parent-entry (find "parent" (cadr-durable:page-items
                                          (cadr-durable:storage-scan-entries
                                           storage parent :order "ascending" :limit 10))
                                :key #'cadr-durable:entry-kind :test #'string=)))
        (let ((inherited-fork (cadr-durable:session-fork
                               session parent (cadr-durable:entry-id inherited))))
          (is (string= "root-at-entry" (durable-doc-value session as-of inherited-fork)))
          (is (string= "parent-current" (durable-doc-value session current inherited-fork))))
        (let ((own-fork (cadr-durable:session-fork
                         session parent (cadr-durable:entry-id parent-entry))))
          (is (string= "parent-at-own-entry" (durable-doc-value session as-of own-fork)))
          (is (string= "parent-current" (durable-doc-value session current own-fork))))))))

(defun durable-job (&key abort)
  (let ((phases (make-hash-table :test #'equal)))
    (setf (gethash "a" phases)
          (lambda (task runtime)
            (declare (ignore task))
            (cadr-durable:runtime-commit
             runtime (lambda () (cadr-chord:json-object "phase" "b")))))
    (setf (gethash "b" phases)
          (lambda (task runtime)
            (declare (ignore task))
            (cadr-durable:runtime-commit
             runtime
             (lambda ()
               (cadr-chord:json-object
                "status" "terminal"
                "outcome" (cadr-chord:json-object "status" "completed" "result" "ok"))))))
    (cadr-durable:define-task "job" :initial (lambda (input)
                                               (declare (ignore input))
                                               (cadr-chord:json-object "phase" "a"))
                                    :phases phases :abort abort)))

(test durable-tasks-resume-park-and-show-the-graph
  (let* ((reports nil)
         (registry (cadr-durable:make-registry))
         (storage (cadr-durable:make-memory-storage)))
    (cadr-durable:registry-install registry (durable-job))
    (let ((harness (cadr-durable:open-harness storage :registry registry
                                              :on-report (lambda (event) (push event reports)))))
      (let ((task (cadr-durable:harness-create-task harness "job" (cadr-chord:json-object))))
        (is (string= "terminal" (cadr-chord:json-get (cadr-durable:task-record-state task) "status")))
        (is (string= "completed"
                     (cadr-chord:json-get
                      (cadr-chord:json-get (cadr-durable:task-record-state task) "outcome")
                      "status")))))
    (let* ((clock 0)
           (sleep-phases (make-hash-table :test #'equal))
           (sleep-registry (cadr-durable:make-registry)))
      (setf (gethash "wait" sleep-phases)
            (lambda (task runtime)
              (declare (ignore task))
              (cadr-durable:runtime-sleep-until
               runtime 5 (cadr-chord:json-object "phase" "wait"))))
      (cadr-durable:registry-install
       sleep-registry
       (cadr-durable:define-task "sleeper"
         :initial (lambda (input) (declare (ignore input))
                    (cadr-chord:json-object "phase" "wait"))
         :phases sleep-phases))
      (let* ((sleep-storage (cadr-durable:make-memory-storage))
             (harness (cadr-durable:open-harness
                       sleep-storage :registry sleep-registry
                       :now (lambda () clock))))
        (cadr-durable:harness-create-task harness "sleeper" (cadr-chord:json-object))
        (let ((node (cadr-chord:json-get
                     (cadr-chord:json-get (cadr-durable:harness-task-graph harness) "tasks")
                     "2")))
          (is (string= "sleeping" (cadr-chord:json-get (cadr-chord:json-get node "state") "status")))
          (is (string= "wait" (cadr-chord:json-get (cadr-chord:json-get node "state") "phase")))
          (is (= 5 (cadr-chord:json-get (cadr-chord:json-get node "state") "until"))))
        (setf clock 5)
        (cadr-durable:harness-resume harness)))
    (let ((park-storage (cadr-durable:make-memory-storage)))
      (cadr-durable:storage-commit
       park-storage
       (list (cons :conversation (cadr-durable:make-conversation))
             (cons :task (cadr-durable:make-task-record
                          :id 2 :kind "job" :conversation-id 1 :restarts 4
                          :state (cadr-chord:json-object "status" "running" "phase" "a")))))
      (let ((harness (cadr-durable:open-harness park-storage :registry registry
                                                :on-report (lambda (event) (push event reports)))))
        (is (= 5 (cadr-durable:task-record-restarts (cadr-durable:storage-task park-storage 2))))
        (is (= 0 (cadr-durable:harness-active-count harness)))
        (let ((node (cadr-chord:json-get
                     (cadr-chord:json-get (cadr-durable:harness-task-graph harness) "tasks")
                     "2")))
          (is (string= "pending" (cadr-chord:json-get (cadr-chord:json-get node "state") "status")))
          (is (string= "restart_limit" (cadr-chord:json-get node "blocked"))))
        (is (search "it is parked until retryTask()"
                    (cadr-chord:json-get (first reports) "message")))
        (cadr-durable:harness-retry-task harness 2)
        (is (string= "terminal"
                     (cadr-chord:json-get
                      (cadr-durable:task-record-state (cadr-durable:storage-task park-storage 2))
                      "status")))))
    (let* ((wait-phases (make-hash-table :test #'equal))
           (wait-registry (cadr-durable:make-registry)))
      (setf (gethash "hold" wait-phases)
            (lambda (task runtime)
              (declare (ignore task))
              (cadr-durable:runtime-commit
               runtime
               (lambda ()
                 (cadr-chord:json-object
                  "status" "waiting" "phase" "hold"
                  "on" (cadr-chord:json-array 9) "policy" "any")))))
      (cadr-durable:registry-install
       wait-registry
       (cadr-durable:define-task "waiter"
         :initial (lambda (input) (declare (ignore input))
                    (cadr-chord:json-object "phase" "hold"))
         :phases wait-phases))
      (let* ((wait-storage (cadr-durable:make-memory-storage))
             (harness (cadr-durable:open-harness wait-storage :registry wait-registry)))
        (cadr-durable:harness-create-task harness "waiter" (cadr-chord:json-object))
        (let* ((node (cadr-chord:json-get
                      (cadr-chord:json-get (cadr-durable:harness-task-graph harness) "tasks")
                      "2"))
               (state (cadr-chord:json-get node "state")))
        (is (string= "waiting" (cadr-chord:json-get state "status")))
        (is (string= "hold" (cadr-chord:json-get state "phase")))
        (is (string= "any" (cadr-chord:json-get state "policy")))
        (is (= 9 (aref (cadr-chord:json-get state "on") 0))))))))

(test durable-a-phase-without-progress-and-an-abort-without-a-terminal-outcome-fault
  (let* ((phases (make-hash-table :test #'equal))
         (registry (cadr-durable:make-registry))
         (storage (cadr-durable:make-memory-storage)))
    (setf (gethash "a" phases) (lambda (task runtime) (declare (ignore task runtime)) nil))
    (cadr-durable:registry-install
     registry
     (cadr-durable:define-task "job"
       :initial (lambda (input) (declare (ignore input)) (cadr-chord:json-object "phase" "a"))
       :phases phases
       :abort (lambda (task runtime) (declare (ignore task runtime)) nil)))
    (let* ((harness (cadr-durable:open-harness storage :registry registry))
           (task (cadr-durable:harness-create-task harness "job" (cadr-chord:json-object))))
      (is (search "Task job phase a returned without durable progress"
                  (cadr-chord:json-get
                   (cadr-chord:json-get
                    (cadr-chord:json-get (cadr-durable:task-record-state task) "outcome")
                    "error")
                   "message")))
      (let ((aborted (cadr-durable:harness-create-task harness "job" (cadr-chord:json-object))))
        (declare (ignore aborted))
        (let ((again (cadr-durable:storage-task storage 2)))
          (cadr-durable:harness-abort-task harness (cadr-durable:task-record-id again))
          (is (search "Abort handler of task"
                      (cadr-chord:json-get
                       (cadr-chord:json-get
                        (cadr-chord:json-get
                         (cadr-durable:task-record-state
                          (cadr-durable:storage-task storage (cadr-durable:task-record-id again)))
                         "outcome")
                        "error")
                       "message"))))))))

(test durable-submit-deduplicates-request-ids-and-rejects-a-busy-conversation
  (let* ((storage (cadr-durable:make-memory-storage))
         (saw nil)
         (harness (cadr-durable:open-harness
                   storage :model (lambda (messages)
                                    (declare (ignore messages))
                                    "pong"))))
    (setf (cadr-durable::harness-model harness)
          (lambda (messages)
            (push messages saw)
            (when (cadr-durable::harness-busy harness)
              (is (search "Conversation 1 is busy"
                          (durable-error-text
                           (lambda ()
                             (cadr-durable:harness-submit
                              harness "again" :when-busy "reject"))))))
            "pong"))
    (let ((first (cadr-durable:harness-submit harness "ping" :request-id "r1")))
      (is (string= "done" (cadr-durable:submission-status first)))
      (is (cadr-durable:submission-answer first))
      (let ((second (cadr-durable:harness-submit harness "ping" :request-id "r1")))
        (is (= (cadr-durable:submission-id first) (cadr-durable:submission-id second))))
      (is (= 1 (length saw))))))

(test durable-read-write-edit-and-bash-match-the-upstream-diagnostics
  (let* ((directory (merge-pathnames (format nil "cadr-durable-tools-~A/" (random 1000000))
                                     (uiop:temporary-directory)))
         (env (cadr-durable:make-directory-env directory)))
    (ensure-directories-exist directory)
    (unwind-protect
         (progn
           (is (search "No execution environment"
                       (durable-error-text (lambda () (cadr-durable:execute-read nil "x")))))
           (let ((lines (with-output-to-string (stream)
                          (loop repeat 100 do (write-line "line" stream)))))
             (cadr-durable:execute-write env "sample.txt" lines)
             (let* ((result (cadr-durable:execute-read env "sample.txt" :offset 41 :limit 20))
                    (diagnostic (first (cadr-durable:tool-result-diagnostics result)))
                    (text (cadr-chord:json-get
                           (aref (cadr-durable:tool-result-output result) 0) "text")))
               (is (string= "info" (cadr-chord:json-get diagnostic "severity")))
               (is (null (cadr-chord:json-get diagnostic "code")))
               (is (null (nth-value 1 (gethash "code" diagnostic))))
               (is (string= "41 more lines in file. Use offset=61 to continue."
                            (cadr-chord:json-get diagnostic "message")))
               (is (null (cadr-durable:tool-result-details result)))
               (is (string= (format nil "~{~A~^~%~}" (make-list 20 :initial-element "line")) text))
               (is (= 1 (length (cadr-durable:tool-result-diagnostics result)))))
             (let* ((from-start (cadr-durable:execute-read env "sample.txt" :limit 20))
                    (diagnostic (first (cadr-durable:tool-result-diagnostics from-start))))
               (is (string= "info" (cadr-chord:json-get diagnostic "severity")))
               (is (null (nth-value 1 (gethash "code" diagnostic))))
               (is (string= "81 more lines in file. Use offset=21 to continue."
                            (cadr-chord:json-get diagnostic "message")))
               (is (null (cadr-durable:tool-result-details from-start))))
             (let* ((at-end (cadr-durable:execute-read env "sample.txt" :offset 101))
                    (text (cadr-chord:json-get
                           (aref (cadr-durable:tool-result-output at-end) 0) "text")))
               (is (null (cadr-durable:tool-result-diagnostics at-end)))
               (is (null (cadr-durable:tool-result-details at-end)))
               (is (string= "" text)))
             (is (string= "Offset 102 is beyond end of file (101 lines total)"
                          (durable-error-text
                           (lambda ()
                             (cadr-durable:execute-read env "sample.txt" :offset 102)))))
           (cadr-durable:execute-write
            env "joined.txt"
            (with-output-to-string (stream)
              (loop for index from 1 to 100
                    do (unless (= index 1) (write-char #\Newline stream))
                       (write-string "line" stream))))
           (let* ((joined (cadr-durable:execute-read env "joined.txt" :offset 41 :limit 20))
                  (diagnostic (first (cadr-durable:tool-result-diagnostics joined))))
             (is (string= "info" (cadr-chord:json-get diagnostic "severity")))
             (is (null (nth-value 1 (gethash "code" diagnostic))))
             (is (string= "40 more lines in file. Use offset=61 to continue."
                          (cadr-chord:json-get diagnostic "message")))
             (is (null (cadr-durable:tool-result-details joined))))
           (let* ((joined-start (cadr-durable:execute-read env "joined.txt" :limit 20))
                  (diagnostic (first (cadr-durable:tool-result-diagnostics joined-start))))
             (is (string= "80 more lines in file. Use offset=21 to continue."
                          (cadr-chord:json-get diagnostic "message")))
             (is (null (cadr-durable:tool-result-details joined-start))))
           (is (string= "Offset 101 is beyond end of file (100 lines total)"
                        (durable-error-text
                         (lambda ()
                           (cadr-durable:execute-read env "joined.txt" :offset 101)))))
           (cadr-durable:execute-write
            env "long.txt"
            (concatenate 'string (make-string 40000 :initial-element #\é) #(#\Newline) "next" #(#\Newline)))
           (let* ((result (cadr-durable:execute-read env "long.txt"))
                  (diagnostic (first (cadr-durable:tool-result-diagnostics result)))
                  (text (cadr-chord:json-get
                         (aref (cadr-durable:tool-result-output result) 0) "text"))
                  (truncation (cadr-chord:json-get
                               (cadr-durable:tool-result-details result) "truncation")))
             (is (string= (make-string 25600 :initial-element #\é) text))
             (is (null (search "next" text)))
             (is (string= "warn" (cadr-chord:json-get diagnostic "severity")))
             (is (string= "truncated" (cadr-chord:json-get diagnostic "code")))
             (is (string= "Line 1 is 78.1KB, exceeds the 50.0KB limit; showing its first 50.0KB. Use bash: sed -n '1p' long.txt | tail -c +51201"
                          (cadr-chord:json-get diagnostic "message")))
             (is (eq t (cadr-chord:json-get truncation "truncated")))
             (is (eq t (cadr-chord:json-get truncation "firstLineExceedsLimit")))
             (is (= 51200 (cadr-chord:json-get truncation "outputBytes")))
             (is (= 1 (cadr-chord:json-get truncation "outputLines")))
             (is (string= "bytes" (cadr-chord:json-get truncation "truncatedBy")))
             (is (= 2 (cadr-chord:json-get truncation "totalLines")))
             (is (= 80006 (cadr-chord:json-get truncation "totalBytes")))
             (is (null (cadr-chord:json-get truncation "lastLinePartial")))
             (is (eq t (nth-value 1 (gethash "lastLinePartial" truncation))))
             (is (null (nth-value 1 (gethash "content" truncation))))
             (is (= 2000 (cadr-chord:json-get truncation "maxLines")))
             (is (= 51200 (cadr-chord:json-get truncation "maxBytes")))
             (is (= 1 (length (cadr-durable:tool-result-diagnostics result)))))
           (cadr-durable:execute-write
            env "large.txt"
            (with-output-to-string (stream)
              (loop for index from 1 to 2500
                    do (unless (= index 1) (write-char #\Newline stream))
                       (format stream "Line ~A" index))))
           (let* ((result (cadr-durable:execute-read env "large.txt"))
                  (diagnostic (first (cadr-durable:tool-result-diagnostics result)))
                  (text (cadr-chord:json-get
                         (aref (cadr-durable:tool-result-output result) 0) "text"))
                  (truncation (cadr-chord:json-get
                               (cadr-durable:tool-result-details result) "truncation")))
             (is (string= "Showing lines 1-2000 of 2500. Use offset=2001 to continue."
                          (cadr-chord:json-get diagnostic "message")))
             (is (string= "truncated" (cadr-chord:json-get diagnostic "code")))
             (is (eq t (cadr-chord:json-get truncation "truncated")))
             (is (string= "lines" (cadr-chord:json-get truncation "truncatedBy")))
             (is (= 2500 (cadr-chord:json-get truncation "totalLines")))
             (is (= 2000 (cadr-chord:json-get truncation "outputLines")))
             (is (null (cadr-chord:json-get truncation "firstLineExceedsLimit")))
             (is (search "Line 2000" text))
             (is (null (search "Line 2001" text))))
           (cadr-durable:execute-write
            env "exact.txt"
            (with-output-to-string (stream)
              (loop repeat 2000 do (write-line "x" stream))))
           (let ((result (cadr-durable:execute-read env "exact.txt")))
             (is (null (cadr-durable:tool-result-diagnostics result)))
             (is (null (cadr-durable:tool-result-details result))))
           (cadr-durable:execute-write
            env "terminated.txt"
            (with-output-to-string (stream)
              (loop repeat 2500 do (write-line "x" stream))))
           (let* ((result (cadr-durable:execute-read env "terminated.txt"))
                  (diagnostic (first (cadr-durable:tool-result-diagnostics result)))
                  (truncation (cadr-chord:json-get
                               (cadr-durable:tool-result-details result) "truncation")))
             (is (string= "Showing lines 1-2000 of 2501. Use offset=2001 to continue."
                          (cadr-chord:json-get diagnostic "message")))
             (is (string= "truncated" (cadr-chord:json-get diagnostic "code")))
             (is (= 2500 (cadr-chord:json-get truncation "totalLines")))
             (is (= 2000 (cadr-chord:json-get truncation "outputLines"))))
             (let ((png #(137 80 78 71 13 10 26 10 0 0 0 13 73 72 68 82 0 0 0 1
                          0 0 0 1 8 6 0 0 0 31 21 196 137 0 0 0 13 73 68 65 84
                          120 156 99 96 96 96 248 15 0 1 4 1 0 95 229 195 75 0
                          0 0 0 73 69 78 68 174 66 96 130)))
             (with-open-file (stream (merge-pathnames "dot.png" directory)
                                     :direction :output :element-type '(unsigned-byte 8)
                                     :if-exists :supersede)
               (write-sequence png stream))
             (let* ((result (cadr-durable:execute-read env "dot.png"))
                    (diagnostic (first (cadr-durable:tool-result-diagnostics result))))
               (is (string= "info" (cadr-chord:json-get diagnostic "severity")))
               (is (string= "image" (cadr-chord:json-get diagnostic "code")))
               (is (string= "Read image file [image/png]."
                            (cadr-chord:json-get diagnostic "message")))
               (is (string= "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGD4DwABBAEAX+XDSwAAAABJRU5ErkJggg=="
                            (cadr-chord:json-get
                             (aref (cadr-durable:tool-result-output result) 0) "data")))))
           (with-open-file (stream (merge-pathnames "dot.bmp" directory)
                                   :direction :output :element-type '(unsigned-byte 8)
                                   :if-exists :supersede)
             (write-sequence #(66 77 0 0) stream))
           (is (search "dot.bmp is an image (image/bmp) that needs converting"
                       (durable-error-text (lambda () (cadr-durable:execute-read env "dot.bmp")))))
           (cadr-durable:execute-write env "note.txt" "alpha beta")
           (is (search "Successfully wrote to nested/out.txt"
                       (cadr-chord:json-get
                        (aref (cadr-durable:tool-result-output
                               (cadr-durable:execute-write env "nested/out.txt" "ok"))
                              0)
                        "text")))
           (is (search "Could not find the exact text"
                       (durable-error-text
                        (lambda ()
                          (cadr-durable:execute-edit
                           env "note.txt"
                           (list (cadr-chord:json-object "oldText" "missing" "newText" "x")))))))
           (let* ((result (cadr-durable:execute-edit
                           env "note.txt"
                           (list (cadr-chord:json-object "oldText" "alpha" "newText" "gamma"))))
                  (details (cadr-durable:tool-result-details result)))
             (is (search "Successfully replaced 1 block(s) in note.txt."
                         (cadr-chord:json-get (aref (cadr-durable:tool-result-output result) 0) "text")))
             (is (string= (format nil "-1 alpha beta~%+1 gamma beta")
                          (cadr-chord:json-get details "diff")))
             (is (= 1 (cadr-chord:json-get details "firstChangedLine")))
             (is (string= (format nil "--- note.txt~%+++ note.txt~%@@ -1,1 +1,1 @@~%-alpha beta~%\\ No newline at end of file~%+gamma beta~%\\ No newline at end of file~%")
                          (cadr-chord:json-get details "patch"))))
           (cadr-durable:execute-write env "edit.txt" (format nil "alpha~%beta~%gamma~%delta~%"))
           (let* ((result (cadr-durable:execute-edit
                           env "edit.txt"
                           (list (cadr-chord:json-object "oldText" (format nil "alpha~%")
                                                        "newText" (format nil "ALPHA~%"))
                                 (cadr-chord:json-object "oldText" (format nil "gamma~%")
                                                        "newText" (format nil "GAMMA~%")))))
                  (details (cadr-durable:tool-result-details result)))
             (is (string= (format nil "-1 alpha~%+1 ALPHA~% 2 beta~%-3 gamma~%+3 GAMMA~% 4 delta")
                          (cadr-chord:json-get details "diff")))
             (is (= 1 (cadr-chord:json-get details "firstChangedLine")))
             (is (string= (format nil "--- edit.txt~%+++ edit.txt~%@@ -1,4 +1,4 @@~%-alpha~%+ALPHA~% beta~%-gamma~%+GAMMA~% delta~%")
                          (cadr-chord:json-get details "patch"))))
           (let* ((input (cadr-chord:json-object "path" "note.txt" "edits" "[{\"oldText\":\"a\",\"newText\":\"b\"}]"))
                  (before (cadr-chord:canonical-json input))
                  (prepared (cadr-durable:prepare-edit-arguments input)))
             (is (string= before (cadr-chord:canonical-json input)))
             (is (vectorp (cadr-chord:json-get prepared "edits"))))
           (let ((failed (cadr-durable:execute-bash env "exit 3")))
             (is (cadr-durable:tool-result-error-p failed))
             (is (string= "Command exited with code 3"
                          (cadr-chord:json-get (first (cadr-durable:tool-result-diagnostics failed))
                                               "message"))))
           (is (string= "Invalid timeout: must be a finite number of seconds"
                        (durable-error-text
                         (lambda () (cadr-durable:execute-bash env "true" :timeout -1)))))
           (is (search "Invalid timeout: maximum is 2147483.647 seconds"
                       (durable-error-text
                        (lambda () (cadr-durable:execute-bash env "true" :timeout 3000000))))))
      (uiop:delete-directory-tree directory :validate t)))))

(test durable-codemode-replays-the-journal-and-refuses-a-different-path
  (let ((sandbox (cadr-durable:make-codemode-sandbox :fingerprint "one"))
        (calls 0)
        (saved nil)
        (step (list :kind :tool :name "read" :args (cadr-chord:json-object "path" "a"))))
    (handler-case
        (cadr-durable:codemode-run
         sandbox (list step)
         :invoke (lambda (call) (declare (ignore call)) (incf calls) "body")
         :before-deliver (lambda (journal)
                           (setf saved journal)
                           (error "cut")))
      (error () nil))
    (is (= 1 calls))
    (is (not (null saved)))
    (cadr-durable:codemode-run sandbox (list step) :journal saved
                               :invoke (lambda (call) (declare (ignore call)) (incf calls) "body"))
    (is (= 1 calls))
    (is (search "but was a tool call"
                (durable-error-text
                 (lambda ()
                   (cadr-durable:codemode-run
                    sandbox (list (list :kind :global :name "other" :args (cadr-chord:json-object)))
                    :journal saved
                    :invoke (lambda (call) (declare (ignore call)) "no"))))))
    (is (search "it ended after result 0"
                (durable-error-text
                 (lambda ()
                   (cadr-durable:codemode-run sandbox nil :journal saved
                                              :invoke (lambda (call) (declare (ignore call)) "no"))))))
    (is (search "sandbox changed since it started (one -> two)"
                (durable-error-text
                 (lambda ()
                   (cadr-durable:codemode-run
                    (cadr-durable:make-codemode-sandbox :fingerprint "two")
                    (list step) :journal saved :recorded-fingerprint "one"
                    :invoke (lambda (call) (declare (ignore call)) "no"))))))
    (is (search "it waits without making call 99, which it made before"
                (durable-error-text
                 (lambda ()
                   (cadr-durable:codemode-run
                    sandbox nil
                    :journal (list (cadr-durable::make-journal-entry
                                    :seq 1 :kind :tool :name "echo" :id 99))
                    :acks '((0 . 1))
                    :invoke (lambda (call) (declare (ignore call)) "no"))))))
    (is (search "after result 1 it had made 2 calls, where it had made 7"
                (durable-error-text
                 (lambda ()
                   (cadr-durable:codemode-run
                    sandbox nil
                    :journal (list (cadr-durable::make-journal-entry
                                    :seq 1 :kind :tool :name "echo" :id 1
                                    :issued-after 7))
                    :acks '((1 . 2))
                    :invoke (lambda (call) (declare (ignore call)) "no"))))))
    (is (search "its first run made 3 calls, where it had made 2"
                (durable-error-text
                 (lambda ()
                   (cadr-durable:codemode-run
                    sandbox nil
                    :first-issued 2
                    :acks '((0 . 3))
                    :invoke (lambda (call) (declare (ignore call)) "no"))))))
    (setf (cadr-durable::codemode-sandbox-closed sandbox) t)
    (is (string= "The code mode sandbox was closed while the script ran"
                 (durable-error-text
                  (lambda () (cadr-durable:codemode-run sandbox (list step)
                                                       :invoke (lambda (call)
                                                                 (declare (ignore call)) "no"))))))))

(defun durable-schema-span (name)
  (cdr (assoc name
              (cadr-telemetry:telemetry-schema-spans cadr-durable:*durable-telemetry-schema*)
              :test #'string=)))

(defun durable-schema-metric (name)
  (cdr (assoc name
              (cadr-telemetry:telemetry-schema-metrics cadr-durable:*durable-telemetry-schema*)
              :test #'string=)))

(defun durable-schema-attribute (attributes name)
  (cdr (assoc name attributes :test #'string=)))

(defun durable-attribute-matches (attribute type description &key required values cardinality)
  (and (string= type (cadr-telemetry:telemetry-attribute-definition-type attribute))
       (string= description (cadr-telemetry:telemetry-attribute-definition-description attribute))
       (eq required (cadr-telemetry::telemetry-attribute-definition-required attribute))
       (equal values (cadr-telemetry::telemetry-attribute-definition-values attribute))
       (equal cardinality (cadr-telemetry::telemetry-attribute-definition-cardinality attribute))))

(test durable-telemetry-schema-matches-v140-field-for-field
  (let* ((schema cadr-durable:*durable-telemetry-schema*)
         (submit (durable-schema-span "pi.durable.submit"))
         (phase (durable-schema-span "pi.durable.phase"))
         (reports (durable-schema-metric "pi.durable.reports"))
         (duration (durable-schema-metric "pi.durable.phase.duration"))
         (active (durable-schema-metric "pi.durable.tasks.active"))
         (submit-start (cadr-telemetry::telemetry-span-definition-start-attributes submit))
         (submit-end (cadr-telemetry::telemetry-span-definition-end-attributes submit))
         (submit-events (cadr-telemetry::telemetry-span-definition-events submit))
         (phase-start (cadr-telemetry::telemetry-span-definition-start-attributes phase))
         (phase-end (cadr-telemetry::telemetry-span-definition-end-attributes phase))
         (phase-events (cadr-telemetry::telemetry-span-definition-events phase))
         (entry (cdr (assoc "pi.durable.entry" submit-events :test #'string=)))
         (submission (cdr (assoc "pi.durable.submission" submit-events :test #'string=)))
         (report (cdr (assoc "pi.durable.report" submit-events :test #'string=)))
         (checkpoint (cdr (assoc "pi.durable.checkpoint" phase-events :test #'string=)))
         (replay (cdr (assoc "pi.durable.replay" phase-events :test #'string=))))
    (is (eq schema (cadr-telemetry:define-telemetry-schema schema)))
    (is (= 1 (cadr-telemetry:telemetry-schema-version schema)))
    (is (string= "Public submission admission and its commit. Inputs start root traces linked to their callers; writes are children. Internal admissions emit phase events only."
                 (cadr-telemetry:telemetry-span-definition-description submit)))
    (is (equal '(:kind "any") (cadr-telemetry::telemetry-span-definition-parents submit)))
    (is (equal '(:kind "any") (cadr-telemetry::telemetry-span-definition-parents phase)))
    (is (not (eq (cadr-telemetry::telemetry-span-definition-parents submit)
                 (cadr-telemetry::telemetry-span-definition-parents phase))))
    (is (durable-attribute-matches
         (durable-schema-attribute submit-start "submission.type")
         "string" "Submission type." :required t :values '("input" "write")))
    (is (durable-attribute-matches
         (durable-schema-attribute submit-start "conversation.id")
         "number" "Conversation ID." :required t :cardinality "high"))
    (is (durable-attribute-matches
         (durable-schema-attribute submit-end "submission.id")
         "number" "Admitted submission ID." :cardinality "high"))
    (is (durable-attribute-matches
         (durable-schema-attribute submit-end "result")
         "string" "Admission result; stale writes report done."
         :values '("queued" "placed" "done")))
    (is (equal '(:default "ok" :error-when "Admission failed.")
               (cadr-telemetry::telemetry-span-definition-status submit)))
    (is (string= "One task phase invocation, including its decision commit, never a wait or restart."
                 (cadr-telemetry:telemetry-span-definition-description phase)))
    (is (durable-attribute-matches
         (durable-schema-attribute phase-start "task.id")
         "number" "Task ID." :required t :cardinality "high"))
    (is (durable-attribute-matches
         (durable-schema-attribute phase-start "task.name")
         "string" "Registered task name." :required t))
    (is (durable-attribute-matches
         (durable-schema-attribute phase-start "phase")
         "string" "Invoked checkpoint phase." :required t))
    (is (durable-attribute-matches
         (durable-schema-attribute phase-start "kind")
         "string" "Invocation kind." :required t :values '("run" "abort")))
    (is (durable-attribute-matches
         (durable-schema-attribute phase-start "attempt")
         "number" "Checkpoint attempt, when present." :required nil))
    (is (durable-attribute-matches
         (durable-schema-attribute phase-start "resumed")
         "boolean" "First invocation of a task loaded in this process." :required t))
    (is (durable-attribute-matches
         (durable-schema-attribute phase-end "outcome")
         "string" "next=<phase>, waiting, sleeping, done, faulted, or aborted."))
    (is (durable-attribute-matches
         (durable-schema-attribute phase-end "tool.name")
         "string" "Called tool name."))
    (is (durable-attribute-matches
         (durable-schema-attribute phase-end "tool.call_id")
         "string" "Transcript tool call ID." :cardinality "high"))
    (is (equal '(:default "ok"
                 :error-when
                 "Faulted, failed, and orphaned outcomes use task_faulted, task_failed, and task_orphaned with a diagnostic capped at 500 characters. Aborted outcomes keep status ok.")
               (cadr-telemetry::telemetry-span-definition-status phase)))
    (is (eq entry (cdr (assoc "pi.durable.entry" phase-events :test #'string=))))
    (is (eq submission (cdr (assoc "pi.durable.submission" phase-events :test #'string=))))
    (is (eq report (cdr (assoc "pi.durable.report" phase-events :test #'string=))))
    (is (string= "A transcript entry was committed; content remains in the transcript."
                 (getf entry :description)))
    (is (durable-attribute-matches
         (durable-schema-attribute (getf entry :attributes) "entry.id")
         "number" "Transcript entry ID." :required t :cardinality "high"))
    (is (durable-attribute-matches
         (durable-schema-attribute (getf entry :attributes) "entry.kind")
         "string" "Entry kind." :required t))
    (is (string= "A submission was settled." (getf submission :description)))
    (is (durable-attribute-matches
         (durable-schema-attribute (getf submission :attributes) "submission.id")
         "number" "Submission ID." :required t :cardinality "high"))
    (is (durable-attribute-matches
         (durable-schema-attribute (getf submission :attributes) "status")
         "string" "Settlement." :required t :values '("done" "unanswered")))
    (is (durable-attribute-matches
         (durable-schema-attribute (getf submission :attributes) "answer.entry_id")
         "number" "Answer entry ID." :required nil :cardinality "high"))
    (is (string= "A report was raised; no error payload is recorded."
                 (getf report :description)))
    (is (durable-attribute-matches
         (durable-schema-attribute (getf report :attributes) "type")
         "string" "ReportInfo type." :required t
         :values '("session_failed" "task_faulted" "task_parked" "migration_failed"
                   "task_outdated" "task_error" "extension_error" "host_error"
                   "listener_error")))
    (is (durable-attribute-matches
         (durable-schema-attribute (getf report :attributes) "reason")
         "string" "Fixed report reason, when present." :required nil
         :values '("threw" "restart_limit" "missing_task" "incompatible_task")))
    (is (durable-attribute-matches
         (durable-schema-attribute (getf report :attributes) "extension")
         "string" "Registered extension name, when present." :required nil))
    (is (durable-attribute-matches
         (durable-schema-attribute (getf report :attributes) "task.id")
         "number" "Task ID, when present." :required nil :cardinality "high"))
    (is (eq (durable-schema-attribute (getf report :attributes) "type")
            (durable-schema-attribute
             (cadr-telemetry::telemetry-metric-definition-attributes reports) "type")))
    (is (string= "The running checkpoint's phase changed while the invocation continued."
                 (getf checkpoint :description)))
    (is (durable-attribute-matches
         (durable-schema-attribute (getf checkpoint :attributes) "phase")
         "string" "Committed checkpoint phase." :required t))
    (is (string= "A nested tool call was answered from its stored result."
                 (getf replay :description)))
    (is (durable-attribute-matches
         (durable-schema-attribute (getf replay :attributes) "tool.name")
         "string" "Called tool name." :required t))
    (is (string= "counter" (cadr-telemetry:telemetry-metric-definition-kind reports)))
    (is (string= "Reports raised, grouped by their fixed ReportInfo type."
                 (cadr-telemetry:telemetry-metric-definition-description reports)))
    (is (null (cadr-telemetry:telemetry-metric-definition-unit reports)))
    (is (string= "histogram" (cadr-telemetry:telemetry-metric-definition-kind duration)))
    (is (string= "ms" (cadr-telemetry:telemetry-metric-definition-unit duration)))
    (is (string= "Duration of a phase invocation and its decision commit."
                 (cadr-telemetry:telemetry-metric-definition-description duration)))
    (is (durable-attribute-matches
         (durable-schema-attribute
          (cadr-telemetry::telemetry-metric-definition-attributes duration) "task")
         "string" "Registered task name." :required t))
    (is (durable-attribute-matches
         (durable-schema-attribute
          (cadr-telemetry::telemetry-metric-definition-attributes duration) "phase")
         "string" "Invoked checkpoint phase." :required t))
    (is (durable-attribute-matches
         (durable-schema-attribute
          (cadr-telemetry::telemetry-metric-definition-attributes duration) "outcome")
         "string" "Phase outcome." :required t))
    (is (string= "upDownCounter" (cadr-telemetry:telemetry-metric-definition-kind active)))
    (is (string= "Live tasks held by this Harness; decremented at terminal settlement or close."
                 (cadr-telemetry:telemetry-metric-definition-description active)))
    (is (null (cadr-telemetry:telemetry-metric-definition-unit active)))
    (is (durable-attribute-matches
         (durable-schema-attribute
          (cadr-telemetry::telemetry-metric-definition-attributes active) "task")
         "string" "Registered task name." :required t))))

(defun durable-recorded-spans (telemetry name)
  (remove-if-not
   (lambda (span)
     (string= name (cadr-telemetry:recorded-telemetry-span-name span)))
   (cadr-telemetry:in-memory-telemetry-spans telemetry)))

(defun durable-span-attr (span name)
  (cdr (assoc name (cadr-telemetry:recorded-telemetry-span-attributes span)
              :test #'string=)))

(defun durable-event-named (span name)
  (find name (cadr-telemetry:recorded-telemetry-span-events span)
        :key #'cadr-telemetry:recorded-telemetry-event-name
        :test #'string=))

(test durable-submit-emits-a-root-span-and-keeps-content-out
  (let ((telemetry (cadr-telemetry:make-in-memory-telemetry))
        (storage (cadr-durable:make-memory-storage))
        (failures nil)
        (harness nil))
    (is (eq cadr-telemetry:*noop-telemetry-context*
            (cadr-durable::harness-telemetry
             (cadr-durable:open-harness
              (cadr-durable:make-memory-storage)
              :model (lambda (messages)
                       (declare (ignore messages))
                       "x")))))
    (setf harness
          (cadr-durable:open-harness
           storage :telemetry telemetry
           :model (lambda (messages)
                    (declare (ignore messages))
                    (handler-case
                        (cadr-durable:harness-submit
                         harness "nested-private" :when-busy "reject")
                      (error (condition) (push condition failures)))
                    "visible-answer")))
    (cadr-telemetry:telemetry-start-span
     telemetry "caller"
     (lambda (caller)
       (let ((done (cadr-durable:harness-submit
                    harness "private-input" :request-id "dedupe"
                    :context-telemetry caller)))
         (is (string= "done" (cadr-durable:submission-status done)))
         (let ((again (cadr-durable:harness-submit
                       harness "another-private-input" :request-id "dedupe"
                       :context-telemetry caller)))
           (is (eql (cadr-durable:submission-id done)
                    (cadr-durable:submission-id again))))))
     :attributes nil)
    (let ((submits (durable-recorded-spans telemetry "pi.durable.submit")))
      (is (= 3 (length submits)))
      (let* ((fresh (find "placed" submits :key (lambda (span) (durable-span-attr span "result"))
                                         :test #'equal))
             (entry (durable-event-named fresh "pi.durable.entry"))
             (caller (find "caller" (cadr-telemetry:in-memory-telemetry-spans telemetry)
                           :key #'cadr-telemetry:recorded-telemetry-span-name
                           :test #'string=)))
        (is (null (cadr-telemetry:recorded-telemetry-span-parent-id fresh)))
        (is (string= "input" (durable-span-attr fresh "submission.type")))
        (is (= 1 (durable-span-attr fresh "conversation.id")))
        (is (equal "placed" (durable-span-attr fresh "result")))
        (is (eql (cadr-durable:submission-id
                  (cadr-durable:storage-submission-by-request storage 1 "dedupe"))
                 (durable-span-attr fresh "submission.id")))
        (is (string= "pi.user"
                     (cdr (assoc "entry.kind"
                                 (cadr-telemetry:recorded-telemetry-event-attributes entry)
                                 :test #'string=))))
        (is (equal '("pi.durable.entry")
                   (mapcar #'cadr-telemetry:recorded-telemetry-event-name
                           (cadr-telemetry:recorded-telemetry-span-events fresh))))
        (let* ((phases (durable-recorded-spans telemetry "pi.durable.phase"))
               (phase (first phases))
               (events (cadr-telemetry:recorded-telemetry-span-events phase))
               (settled (durable-event-named phase "pi.durable.submission"))
               (answer (cadr-durable:submission-answer
                        (cadr-durable:storage-submission-by-request storage 1 "dedupe")))
               (generation (cadr-durable:storage-task
                            storage (durable-span-attr phase "task.id"))))
          (is (= 1 (length phases)))
          (is (eql (cadr-telemetry:recorded-telemetry-span-id fresh)
                   (cadr-telemetry:recorded-telemetry-span-parent-id phase)))
          (is (equal (cadr-telemetry:recorded-telemetry-span-context fresh)
                     (cadr-telemetry:recorded-telemetry-span-parent-context phase)))
          (is (string= "pi.generation" (durable-span-attr phase "task.name")))
          (is (string= "request" (durable-span-attr phase "phase")))
          (is (string= "run" (durable-span-attr phase "kind")))
          (is (string= "done" (durable-span-attr phase "outcome")))
          (is (= 1 (durable-span-attr phase "attempt")))
          (is (null (durable-span-attr phase "resumed")))
          (is (assoc "resumed"
                     (cadr-telemetry:recorded-telemetry-span-attributes phase)
                     :test #'string=))
          (is (equal '("pi.durable.entry" "pi.durable.submission")
                     (mapcar #'cadr-telemetry:recorded-telemetry-event-name events)))
          (is (string= "pi.assistant"
                       (cdr (assoc "entry.kind"
                                   (cadr-telemetry:recorded-telemetry-event-attributes
                                    (first events))
                                   :test #'string=))))
          (is (eql answer
                   (cdr (assoc "entry.id"
                               (cadr-telemetry:recorded-telemetry-event-attributes
                                (first events))
                               :test #'string=))))
          (is (equal "done"
                     (cdr (assoc "status"
                                 (cadr-telemetry:recorded-telemetry-event-attributes settled)
                                 :test #'string=))))
          (is (eql answer
                   (cdr (assoc "answer.entry_id"
                               (cadr-telemetry:recorded-telemetry-event-attributes settled)
                               :test #'string=))))
          (is (eql (cadr-durable:submission-id
                    (cadr-durable:storage-submission-by-request storage 1 "dedupe"))
                   (cdr (assoc "submission.id"
                               (cadr-telemetry:recorded-telemetry-event-attributes settled)
                               :test #'string=))))
          (is (string= "pi.generation" (cadr-durable:task-record-kind generation)))
          (is (string= "terminal"
                       (cadr-chord:json-get (cadr-durable:task-record-state generation)
                                            "status")))
          (is (string= "completed"
                       (cadr-chord:json-get
                        (cadr-chord:json-get (cadr-durable:task-record-state generation)
                                             "outcome")
                        "status")))
          (is (equal (cadr-telemetry:recorded-telemetry-span-context fresh)
                     (cadr-durable::task-record-trace generation)))
          (is (= 1 (length (remove-if-not
                            (lambda (metric)
                              (and (string= "pi.durable.phase.duration"
                                            (cadr-telemetry:recorded-measurement-name metric))
                                   (string= "pi.generation"
                                            (cdr (assoc "task"
                                                        (cadr-telemetry:recorded-measurement-attributes
                                                         metric)
                                                        :test #'string=)))
                                   (string= "request"
                                            (cdr (assoc "phase"
                                                        (cadr-telemetry:recorded-measurement-attributes
                                                         metric)
                                                        :test #'string=)))
                                   (string= "done"
                                            (cdr (assoc "outcome"
                                                        (cadr-telemetry:recorded-measurement-attributes
                                                         metric)
                                                        :test #'string=)))))
                            (cadr-telemetry:in-memory-measurements telemetry))))))
        (is (equal (cadr-telemetry:recorded-telemetry-span-context fresh)
                   (cadr-durable::submission-record-trace
                    (cadr-durable:storage-submission-by-request storage 1 "dedupe"))))
        (is (equal (cadr-telemetry:recorded-telemetry-span-context caller)
                   (cadr-telemetry:recorded-telemetry-link-context
                    (first (cadr-telemetry:recorded-telemetry-span-links fresh)))))
        (let ((duplicate (find "done" submits
                               :key (lambda (span) (durable-span-attr span "result"))
                               :test #'equal)))
          (is (null (cadr-telemetry:recorded-telemetry-span-events duplicate)))
          (is (not (equal (cadr-telemetry:recorded-telemetry-span-context duplicate)
                          (cadr-durable::submission-record-trace
                           (cadr-durable:storage-submission-by-request storage 1 "dedupe")))))))
      (let ((rejected (find-if (lambda (span)
                                 (eq :error
                                     (cadr-telemetry:telemetry-status-kind
                                      (cadr-telemetry:recorded-telemetry-span-status span))))
                               submits)))
        (is (string= "" (cadr-telemetry:telemetry-status-error-message
                         (cadr-telemetry:recorded-telemetry-span-status rejected))))
        (is (null (durable-span-attr rejected "submission.id")))
        (is (typep (first failures) 'cadr-durable:conversation-busy))))
    (is (null (search "private-input"
                      (format nil "~A" (cadr-telemetry:in-memory-telemetry-spans telemetry)))))
    (is (null (search "visible-answer"
                      (format nil "~A" (cadr-telemetry:in-memory-telemetry-spans telemetry)))))
    (is (null (search "nested-private"
                      (format nil "~A" (cadr-telemetry:in-memory-telemetry-spans telemetry)))))))

(test durable-phase-report-clock-and-replay-follow-the-v140-vocabulary
  (let* ((telemetry (cadr-telemetry:make-in-memory-telemetry))
         (reports nil)
         (clock-calls 0)
         (registry (cadr-durable:make-registry))
         (phases (make-hash-table :test #'equal))
         (storage (cadr-durable:make-memory-storage)))
    (setf (gethash "call" phases)
          (lambda (task runtime)
            (declare (ignore task))
            (cadr-durable:runtime-commit
             runtime (lambda () (cadr-chord:json-object "status" "running" "phase" "call")))
            (cadr-durable:runtime-commit
             runtime (lambda () (cadr-chord:json-object "status" "running" "phase" "call")))
            (cadr-durable:runtime-commit
             runtime (lambda () (cadr-chord:json-object "status" "running" "phase" "finish")))
            (cadr-durable:runtime-now runtime)
            (cadr-durable:runtime-now runtime)))
    (setf (gethash "finish" phases)
          (lambda (task runtime)
            (declare (ignore task runtime))
            (error "private-fault-payload~A" (make-string 520 :initial-element #\x))))
    (cadr-durable:registry-install
     registry
     (cadr-durable:define-task "job"
       :initial (lambda (input) (declare (ignore input))
                  (cadr-chord:json-object "phase" "call"))
       :phases phases
       :abort (lambda (task runtime)
                (declare (ignore task))
                (cadr-durable:runtime-commit
                 runtime (lambda ()
                           (cadr-chord:json-object
                            "status" "terminal"
                            "outcome" (cadr-chord:json-object
                                       "status" "aborted"
                                       "reason" "private-abort-reason")))))))
    (let ((harness (cadr-durable:open-harness
                    storage :registry registry :telemetry telemetry
                    :now (lambda ()
                           (incf clock-calls)
                           (when (= clock-calls 1)
                             (error "private-clock-error"))
                           10)
                    :on-report (lambda (event) (push event reports)))))
      (let ((task (cadr-durable:harness-create-task
                   harness "job" (cadr-chord:json-object))))
        (is (string= "terminal"
                     (cadr-chord:json-get (cadr-durable:task-record-state task) "status")))
        (let ((phases (durable-recorded-spans telemetry "pi.durable.phase")))
          (is (= 2 (length phases)))
          (is (every (lambda (span)
                       (and (null (cadr-telemetry:recorded-telemetry-span-parent-id span))
                            (string= "job" (durable-span-attr span "task.name"))
                            (string= "run" (durable-span-attr span "kind"))
                            (null (durable-span-attr span "resumed"))
                            (assoc "resumed"
                                   (cadr-telemetry:recorded-telemetry-span-attributes span)
                                   :test #'string=)))
                     phases))
          (is (string= "next=finish" (durable-span-attr (first phases) "outcome")))
          (is (string= "call" (durable-span-attr (first phases) "phase")))
          (let ((checkpoints
                  (remove-if-not
                   (lambda (event)
                     (string= "pi.durable.checkpoint"
                              (cadr-telemetry:recorded-telemetry-event-name event)))
                   (cadr-telemetry:recorded-telemetry-span-events (first phases)))))
            (is (= 1 (length checkpoints)))
            (is (string= "finish"
                         (cdr (assoc "phase"
                                     (cadr-telemetry:recorded-telemetry-event-attributes
                                      (first checkpoints))
                                     :test #'string=)))))
          (let ((fault (second phases))
                (event (durable-event-named (second phases) "pi.durable.report")))
            (is (eq :error (cadr-telemetry:telemetry-status-kind
                            (cadr-telemetry:recorded-telemetry-span-status fault))))
            (is (string= "task_faulted"
                         (cadr-telemetry:telemetry-status-error-name
                          (cadr-telemetry:recorded-telemetry-span-status fault))))
            (is (= 500 (length (cadr-telemetry:telemetry-status-error-message
                                (cadr-telemetry:recorded-telemetry-span-status fault)))))
            (is (string= "faulted" (durable-span-attr fault "outcome")))
            (is (equal "task_faulted"
                       (cdr (assoc "type"
                                   (cadr-telemetry:recorded-telemetry-event-attributes event)
                                   :test #'string=))))
            (is (equal "threw"
                       (cdr (assoc "reason"
                                   (cadr-telemetry:recorded-telemetry-event-attributes event)
                                   :test #'string=))))
            (is (eql (cadr-durable:task-record-id task)
                     (cdr (assoc "task.id"
                                 (cadr-telemetry:recorded-telemetry-event-attributes event)
                                 :test #'string=))))
            (is (null (assoc "message"
                             (cadr-telemetry:recorded-telemetry-event-attributes event)
                             :test #'string=)))
            (is (null (search "private-clock-error"
                              (format nil "~A"
                                      (cadr-telemetry:recorded-telemetry-span-events fault)))))))
        (cadr-durable:harness-abort-task harness (cadr-durable:task-record-id task))
        (let ((abort (find "abort" (durable-recorded-spans telemetry "pi.durable.phase")
                           :key (lambda (span) (durable-span-attr span "kind"))
                           :test #'string=)))
          (is (string= "aborted" (durable-span-attr abort "outcome")))
          (is (eq :ok (cadr-telemetry:telemetry-status-kind
                       (cadr-telemetry:recorded-telemetry-span-status abort))))
          (is (null (search "private-abort-reason"
                            (format nil "~A" (cadr-telemetry:in-memory-telemetry-spans telemetry))))))
        (is (equal '("host_error" "task_faulted")
                   (mapcar (lambda (metric)
                             (cdr (assoc "type"
                                         (cadr-telemetry:recorded-measurement-attributes metric)
                                         :test #'string=)))
                           (remove-if-not
                            (lambda (metric)
                              (string= "pi.durable.reports"
                                       (cadr-telemetry:recorded-measurement-name metric)))
                            (cadr-telemetry:in-memory-measurements telemetry)))))
        (is (= 2 clock-calls))
        (is (some (lambda (event)
                    (let ((message (cadr-chord:json-get event "message")))
                      (and message (search "private-clock-error" message))))
                  reports))
        (cadr-durable:harness-close harness)
        (is (= 0 (reduce #'+
                         (mapcar #'cadr-telemetry:recorded-measurement-value
                                 (remove-if-not
                                  (lambda (metric)
                                    (string= "pi.durable.tasks.active"
                                             (cadr-telemetry:recorded-measurement-name metric)))
                                  (cadr-telemetry:in-memory-measurements telemetry)))
                         :initial-value 0)))))))

(test durable-loaded-task-is-resumed-once-and-commits-emit-after-success
  (let* ((telemetry (cadr-telemetry:make-in-memory-telemetry))
         (registry (cadr-durable:make-registry))
         (phases (make-hash-table :test #'equal))
         (storage (cadr-durable:make-memory-storage)))
    (setf (gethash "finish" phases)
          (lambda (task runtime)
            (declare (ignore task))
            (cadr-durable:runtime-commit
             runtime (lambda ()
                       (cadr-chord:json-object
                        "status" "terminal"
                        "outcome" (cadr-chord:json-object "status" "completed" "result" "ok"))))))
    (cadr-durable:registry-install
     registry
     (cadr-durable:define-task "loaded"
       :initial (lambda (input) (declare (ignore input))
                  (cadr-chord:json-object "phase" "finish"))
       :phases phases))
    (cadr-durable:storage-commit
     storage
     (list (cons :conversation (cadr-durable:make-conversation))
           (cons :task (cadr-durable:make-task-record
                        :id 2 :kind "loaded" :conversation-id 1
                        :state (cadr-chord:json-object "status" "pending" "phase" "finish"
                                                       "attempt" 3)))))
    (let ((harness (cadr-durable:open-harness storage :registry registry :telemetry telemetry)))
      (cadr-durable:harness-resume harness)
      (let ((span (first (durable-recorded-spans telemetry "pi.durable.phase"))))
        (is (eq t (durable-span-attr span "resumed")))
        (is (= 3 (durable-span-attr span "attempt")))
        (is (string= "done" (durable-span-attr span "outcome"))))
      (cadr-telemetry:telemetry-start-span
       telemetry "commit"
       (lambda (span)
         (let ((cadr-durable::*durable-span* span))
           (handler-case
               (cadr-durable:session-commit
                (cadr-durable:open-session storage)
                (lambda (tx)
                  (declare (ignore tx))
                  (error "rollback")))
             (error () nil))
           (is (null (cadr-telemetry:recorded-telemetry-span-events
                      (find "commit"
                            (cadr-telemetry:in-memory-telemetry-spans telemetry)
                            :key #'cadr-telemetry:recorded-telemetry-span-name
                            :test #'string=))))
           (cadr-durable:storage-commit
            storage
            (list (cons :entry (cadr-durable:make-entry
                                :id 9 :conversation-id 1 :kind "app.note"))
                  (cons :submission
                        (cadr-durable::make-submission-record
                         :id 10 :conversation-id 1 :type "write" :status "done"
                         :entry 9))))))
       :attributes nil)
      (let ((span (find "commit" (cadr-telemetry:in-memory-telemetry-spans telemetry)
                        :key #'cadr-telemetry:recorded-telemetry-span-name
                        :test #'string=)))
        (is (equal '("pi.durable.entry" "pi.durable.submission")
                   (mapcar #'cadr-telemetry:recorded-telemetry-event-name
                           (cadr-telemetry:recorded-telemetry-span-events span))))
        (is (null (assoc "answer.entry_id"
                         (cadr-telemetry:recorded-telemetry-event-attributes
                          (second (cadr-telemetry:recorded-telemetry-span-events span)))
                         :test #'string=))))
      (let ((sandbox (cadr-durable:make-codemode-sandbox)))
        (cadr-telemetry:telemetry-start-span
         telemetry "replay"
         (lambda (span)
           (let ((cadr-durable::*durable-span* span))
             (cadr-durable:codemode-run
              sandbox '((:kind :tool :name "once"))
              :journal (list (cadr-durable::make-journal-entry
                              :seq 1 :kind :tool :name "once" :result "kept"))
              :invoke (lambda (step)
                        (declare (ignore step))
                        (error "reran")))))
         :attributes nil)
        (let ((span (find "replay" (cadr-telemetry:in-memory-telemetry-spans telemetry)
                          :key #'cadr-telemetry:recorded-telemetry-span-name
                          :test #'string=)))
          (is (equal "once"
                     (cdr (assoc "tool.name"
                                 (cadr-telemetry:recorded-telemetry-event-attributes
                                  (durable-event-named span "pi.durable.replay"))
                                 :test #'string=)))))))))

(defun durable-span-named (telemetry name)
  (find name (cadr-telemetry:in-memory-telemetry-spans telemetry)
        :key #'cadr-telemetry:recorded-telemetry-span-name
        :test #'string=))

(defun durable-report-types (telemetry)
  (mapcar (lambda (metric)
            (cdr (assoc "type"
                        (cadr-telemetry:recorded-measurement-attributes metric)
                        :test #'string=)))
          (remove-if-not
           (lambda (metric)
             (string= "pi.durable.reports"
                      (cadr-telemetry:recorded-measurement-name metric)))
           (cadr-telemetry:in-memory-measurements telemetry))))

(test durable-busy-input-results-are-placed-then-queued
  (let* ((telemetry (cadr-telemetry:make-in-memory-telemetry))
         (storage (cadr-durable:make-memory-storage))
         (harness nil))
    (setf harness
          (cadr-durable:open-harness
           storage :telemetry telemetry
           :model (lambda (messages)
                    (declare (ignore messages))
                    (let ((second (cadr-durable:harness-submit
                                   harness "second" :request-id "queued")))
                      (is (string= "queued" (cadr-durable:submission-status second)))
                      (let ((duplicate (cadr-durable:harness-submit
                                        harness "ignored" :request-id "queued")))
                        (is (eql (cadr-durable:submission-id second)
                                 (cadr-durable:submission-id duplicate)))
                        (is (string= "queued" (cadr-durable:submission-status duplicate)))))
                    "second-answer")))
    (cadr-durable:harness-submit harness "first")
    (let ((submits (durable-recorded-spans telemetry "pi.durable.submit")))
      (is (equal '("placed" "queued" "queued")
                 (mapcar (lambda (span) (durable-span-attr span "result")) submits)))
      (is (null (cadr-telemetry:recorded-telemetry-span-events (second submits))))
      (is (null (cadr-telemetry:recorded-telemetry-span-events (third submits))))
      (is (equal (cadr-telemetry:recorded-telemetry-span-context (second submits))
                 (cadr-durable::submission-record-trace
                  (cadr-durable:storage-submission-by-request storage 1 "queued"))))
      (is (not (equal (cadr-telemetry:recorded-telemetry-span-context (third submits))
                      (cadr-durable::submission-record-trace
                       (cadr-durable:storage-submission-by-request storage 1 "queued"))))))
    (is (null (search "second-answer"
                      (format nil "~A" (cadr-telemetry:in-memory-telemetry-spans telemetry)))))
    (is (null (search "ignored"
                      (format nil "~A" (cadr-telemetry:in-memory-telemetry-spans telemetry)))))))

(test durable-public-write-stays-open-as-a-child-of-its-caller
  (let* ((telemetry (cadr-telemetry:make-in-memory-telemetry))
         (storage (cadr-durable:make-memory-storage))
         (harness (cadr-durable:open-harness
                   storage :telemetry telemetry
                   :model (lambda (messages)
                            (declare (ignore messages))
                            (error "write ran the model")))))
    (cadr-telemetry:telemetry-start-span
     telemetry "caller"
     (lambda (caller)
       (let ((submission (cadr-durable:harness-submit
                          harness nil :type "write" :context-telemetry caller
                          :entry (cadr-chord:json-object
                                  "kind" "app.note" "data" "private-note"))))
         (is (string= "done" (cadr-durable:submission-status submission)))
         (let* ((recorded-caller (durable-span-named telemetry "caller"))
                (span (first (durable-recorded-spans telemetry "pi.durable.submit")))
                (events (cadr-telemetry:recorded-telemetry-span-events span)))
           (is (eql (cadr-telemetry:recorded-telemetry-span-id recorded-caller)
                    (cadr-telemetry:recorded-telemetry-span-parent-id span)))
           (is (equal (cadr-telemetry:recorded-telemetry-span-context recorded-caller)
                      (cadr-telemetry:recorded-telemetry-span-parent-context span)))
           (is (null (cadr-telemetry:recorded-telemetry-span-links span)))
           (is (equal "done" (durable-span-attr span "result")))
           (is (string= "write" (durable-span-attr span "submission.type")))
           (is (equal '("pi.durable.entry" "pi.durable.submission")
                      (mapcar #'cadr-telemetry:recorded-telemetry-event-name events)))
           (is (string= "app.note"
                        (cdr (assoc "entry.kind"
                                    (cadr-telemetry:recorded-telemetry-event-attributes
                                     (first events))
                                    :test #'string=))))
           (is (equal "done"
                      (cdr (assoc "status"
                                  (cadr-telemetry:recorded-telemetry-event-attributes
                                   (second events))
                                  :test #'string=))))
           (is (null (assoc "answer.entry_id"
                            (cadr-telemetry:recorded-telemetry-event-attributes
                             (second events))
                            :test #'string=)))
           (is (equal (cadr-telemetry:recorded-telemetry-span-context span)
                      (cadr-durable::submission-record-trace submission))))))
     :attributes nil)
    (is (null (search "private-note"
                      (format nil "~A" (cadr-telemetry:in-memory-telemetry-spans telemetry)))))))

(test durable-failed-and-orphaned-outcomes-collapse-to-faulted
  (dolist (status '("faulted" "failed" "orphaned"))
    (let* ((telemetry (cadr-telemetry:make-in-memory-telemetry))
           (message (with-output-to-string (stream)
                      (loop repeat 80 do (write-string "diagnostic " stream))))
           (registry (cadr-durable:make-registry))
           (phases (make-hash-table :test #'equal))
           (storage (cadr-durable:make-memory-storage)))
      (setf (gethash "fail" phases)
            (lambda (task runtime)
              (declare (ignore task))
              (cond
                ((string= status "faulted")
                 (error "~A" message))
                ((string= status "orphaned")
                 (cadr-durable:runtime-commit
                  runtime (lambda ()
                            (cadr-chord:json-object
                             "status" "terminal"
                             "outcome" (cadr-chord:json-object
                                        "status" "orphaned"
                                        "reason" message)))))
                (t
                 (cadr-durable:runtime-commit
                  runtime (lambda ()
                            (cadr-chord:json-object
                             "status" "terminal"
                             "outcome" (cadr-chord:json-object
                                        "status" "failed"
                                        "error" (cadr-chord:json-object
                                                 "message" message
                                                 "detail" "private-error-detail")))))))))
      (cadr-durable:registry-install
       registry
       (cadr-durable:define-task "job"
         :initial (lambda (input)
                    (declare (ignore input))
                    (cadr-chord:json-object "phase" "fail"))
         :phases phases))
      (let* ((harness (cadr-durable:open-harness storage :registry registry :telemetry telemetry))
             (task (cadr-durable:harness-create-task
                    harness "job" (cadr-chord:json-object)
                    :trace '(("unknown" . "carrier"))))
             (span (first (durable-recorded-spans telemetry "pi.durable.phase")))
             (recorded (format nil "~A~A"
                               (cadr-telemetry:recorded-telemetry-span-attributes span)
                               (cadr-telemetry:recorded-telemetry-span-events span)))
             (outcome (cadr-chord:json-get
                       (cadr-chord:json-get (cadr-durable:task-record-state task) "outcome")
                       "status")))
        (is (string= status outcome))
        (is (null (cadr-telemetry:recorded-telemetry-span-parent-id span)))
        (is (string= "faulted" (durable-span-attr span "outcome")))
        (is (eq :error (cadr-telemetry:telemetry-status-kind
                        (cadr-telemetry:recorded-telemetry-span-status span))))
        (is (string= (format nil "task_~A" status)
                     (cadr-telemetry:telemetry-status-error-name
                      (cadr-telemetry:recorded-telemetry-span-status span))))
        (is (= 500 (length (cadr-telemetry:telemetry-status-error-message
                            (cadr-telemetry:recorded-telemetry-span-status span)))))
        (is (string= "diagnostic"
                     (subseq (cadr-telemetry:telemetry-status-error-message
                              (cadr-telemetry:recorded-telemetry-span-status span))
                             0 10)))
        (is (null (search "diagnostic" recorded)))
        (is (null (search "private-error-detail"
                          (format nil "~A" (cadr-telemetry:in-memory-telemetry-spans telemetry)))))
        (is (null (search "private-exception-name"
                          (format nil "~A" (cadr-telemetry:in-memory-telemetry-spans telemetry)))))
        (when (string= status "faulted")
          (let ((event (durable-event-named span "pi.durable.report")))
            (is (equal "task_faulted"
                       (cdr (assoc "type"
                                   (cadr-telemetry:recorded-telemetry-event-attributes event)
                                   :test #'string=))))
            (is (equal "threw"
                       (cdr (assoc "reason"
                                   (cadr-telemetry:recorded-telemetry-event-attributes event)
                                   :test #'string=))))
            (is (eql (cadr-durable:task-record-id task)
                     (cdr (assoc "task.id"
                                 (cadr-telemetry:recorded-telemetry-event-attributes event)
                                 :test #'string=))))))))))

(test durable-no-progress-and-bare-abort-report-threw
  (let* ((telemetry (cadr-telemetry:make-in-memory-telemetry))
         (registry (cadr-durable:make-registry))
         (idle (make-hash-table :test #'equal))
         (held (make-hash-table :test #'equal))
         (storage (cadr-durable:make-memory-storage)))
    (setf (gethash "idle" idle)
          (lambda (task runtime)
            (declare (ignore task runtime))))
    (setf (gethash "hold" held)
          (lambda (task runtime)
            (declare (ignore task))
            (cadr-durable:runtime-commit
             runtime (lambda ()
                       (cadr-chord:json-object "status" "running" "phase" "hold")))))
    (cadr-durable:registry-install
     registry
     (cadr-durable:define-task "idle"
       :initial (lambda (input)
                  (declare (ignore input))
                  (cadr-chord:json-object "phase" "idle"))
       :phases idle))
    (cadr-durable:registry-install
     registry
     (cadr-durable:define-task "hold"
       :initial (lambda (input)
                  (declare (ignore input))
                  (cadr-chord:json-object "phase" "hold"))
       :phases held
       :abort (lambda (task runtime)
                (declare (ignore task runtime)))))
    (let ((harness (cadr-durable:open-harness storage :registry registry :telemetry telemetry)))
      (cadr-durable:harness-create-task harness "idle" (cadr-chord:json-object))
      (let* ((held-task (cadr-durable:harness-create-task
                         harness "hold" (cadr-chord:json-object)))
             (abort (cadr-durable:harness-abort-task
                     harness (cadr-durable:task-record-id held-task)))
             (phases (durable-recorded-spans telemetry "pi.durable.phase"))
             (idle-span (find "idle" phases
                              :key (lambda (span) (durable-span-attr span "phase"))
                              :test #'string=))
             (abort-span (find "abort" phases
                               :key (lambda (span) (durable-span-attr span "kind"))
                               :test #'string=)))
        (declare (ignore abort))
        (dolist (span (list idle-span abort-span))
          (let ((event (durable-event-named span "pi.durable.report")))
            (is (string= "faulted" (durable-span-attr span "outcome")))
            (is (equal "threw"
                       (cdr (assoc "reason"
                                   (cadr-telemetry:recorded-telemetry-event-attributes event)
                                   :test #'string=))))
            (is (null (search "no_progress"
                              (format nil "~A"
                                      (cadr-telemetry:recorded-telemetry-event-attributes event)))))
            (is (null (search "abort"
                              (cdr (assoc "reason"
                                          (cadr-telemetry:recorded-telemetry-event-attributes event)
                                          :test #'string=)))))))))))

(test durable-phase-inherits-the-creator-and-drops-an-explicit-root
  (let* ((telemetry (cadr-telemetry:make-in-memory-telemetry))
         (registry (cadr-durable:make-registry))
         (phases (make-hash-table :test #'equal))
         (storage (cadr-durable:make-memory-storage)))
    (setf (gethash "finish" phases)
          (lambda (task runtime)
            (declare (ignore task))
            (cadr-durable:runtime-commit
             runtime (lambda ()
                       (cadr-chord:json-object
                        "status" "terminal"
                        "outcome" (cadr-chord:json-object "status" "completed"))))))
    (cadr-durable:registry-install
     registry
     (cadr-durable:define-task "traced"
       :initial (lambda (input)
                  (declare (ignore input))
                  (cadr-chord:json-object "phase" "finish"))
       :phases phases))
    (let ((harness (cadr-durable:open-harness storage :registry registry :telemetry telemetry))
          (tasks nil))
      (cadr-telemetry:telemetry-start-span
       telemetry "creator"
       (lambda (creator)
         (setf tasks
               (list (cadr-durable:harness-create-task
                      harness "traced" (cadr-chord:json-object)
                      :context-telemetry creator)
                     (cadr-durable:harness-create-task
                      harness "traced" (cadr-chord:json-object)
                      :context-telemetry creator :trace nil)
                     (cadr-durable:harness-create-task
                      harness "traced" (cadr-chord:json-object)
                      :context-telemetry creator :trace "root"))))
       :attributes nil)
      (let ((creator (durable-span-named telemetry "creator"))
            (phase-spans (durable-recorded-spans telemetry "pi.durable.phase")))
        (is (= 3 (length phase-spans)))
        (is (equal (list (cadr-telemetry:recorded-telemetry-span-context creator)
                         (cadr-telemetry:recorded-telemetry-span-context creator)
                         nil)
                   (mapcar #'cadr-durable::task-record-trace tasks)))
        (is (equal (list (cadr-telemetry:recorded-telemetry-span-id creator)
                         (cadr-telemetry:recorded-telemetry-span-id creator)
                         nil)
                   (mapcar #'cadr-telemetry:recorded-telemetry-span-parent-id phase-spans)))
        (is (equal (cadr-telemetry:recorded-telemetry-span-context creator)
                   (cadr-telemetry:recorded-telemetry-span-parent-context (first phase-spans))))
        (is (null (cadr-telemetry:recorded-telemetry-span-parent-context (third phase-spans))))))))

(test durable-reopened-phase-keeps-the-stored-parent
  (let* ((directory (merge-pathnames (format nil "cadr-durable-trace-~A/" (random 1000000))
                                     (uiop:temporary-directory)))
         (telemetry (cadr-telemetry:make-in-memory-telemetry))
         (registry (cadr-durable:make-registry))
         (phases (make-hash-table :test #'equal))
         (creator-context nil)
         (task-id nil))
    (ensure-directories-exist directory)
    (setf (gethash "hold" phases)
          (lambda (task runtime)
            (cadr-durable:runtime-commit
             runtime (lambda ()
                       (cadr-chord:json-object
                        "status" "running" "phase" "hold"
                        "count" (1+ (or (cadr-chord:json-get
                                         (cadr-durable:task-record-state task) "count")
                                        0)))))))
    (cadr-durable:registry-install
     registry
     (cadr-durable:define-task "held"
       :initial (lambda (input)
                  (declare (ignore input))
                  (cadr-chord:json-object "phase" "hold"))
       :phases phases))
    (unwind-protect
         (progn
           (let ((storage (cadr-durable:open-jsonl-storage directory)))
             (let ((harness (cadr-durable:open-harness
                             storage :registry registry :telemetry telemetry)))
               (cadr-telemetry:telemetry-start-span
                telemetry "creator"
                (lambda (creator)
                  (setf creator-context (cadr-telemetry:telemetry-inject
                                         (cadr-telemetry:telemetry-span-propagation creator)
                                         creator))
                  (setf task-id
                        (cadr-durable:task-record-id
                         (cadr-durable:harness-create-task
                          harness "held" (cadr-chord:json-object)
                          :context-telemetry creator))))
                :attributes nil))
             (cadr-durable:storage-close storage))
           (let* ((reopened (cadr-telemetry:make-in-memory-telemetry))
                  (storage (cadr-durable:open-jsonl-storage directory))
                  (harness (cadr-durable:open-harness
                            storage :registry registry :telemetry reopened)))
             (cadr-durable:harness-resume harness)
             (let ((span (first (durable-recorded-spans reopened "pi.durable.phase"))))
               (is (eq t (durable-span-attr span "resumed")))
               (is (string= "hold" (durable-span-attr span "phase")))
               (is (equal creator-context
                          (cadr-telemetry:recorded-telemetry-span-parent-context span)))
               (is (equal creator-context
                          (cadr-durable::task-record-trace
                           (cadr-durable:storage-task storage task-id)))))
             (cadr-durable:storage-close storage)))
      (uiop:delete-directory-tree directory :validate t :if-does-not-exist :ignore))))

(test durable-checkpoint-fires-again-after-leaving-and-returning
  (let* ((telemetry (cadr-telemetry:make-in-memory-telemetry))
         (registry (cadr-durable:make-registry))
         (phases (make-hash-table :test #'equal))
         (storage (cadr-durable:make-memory-storage)))
    (setf (gethash "call" phases)
          (lambda (task runtime)
            (declare (ignore task))
            (cadr-durable:runtime-commit
             runtime (lambda () (cadr-chord:json-object "status" "running" "phase" "call")))
            (cadr-durable:runtime-commit
             runtime (lambda () (cadr-chord:json-object "status" "running" "phase" "other")))
            (cadr-durable:runtime-commit
             runtime (lambda () (cadr-chord:json-object "status" "running" "phase" "call")))))
    (cadr-durable:registry-install
     registry
     (cadr-durable:define-task "job"
       :initial (lambda (input)
                  (declare (ignore input))
                  (cadr-chord:json-object "phase" "call"))
       :phases phases))
    (let ((harness (cadr-durable:open-harness storage :registry registry :telemetry telemetry)))
      (cadr-durable:harness-create-task harness "job" (cadr-chord:json-object))
      (is (equal '("other" "call")
                 (mapcar (lambda (event)
                           (cdr (assoc "phase"
                                       (cadr-telemetry:recorded-telemetry-event-attributes event)
                                       :test #'string=)))
                         (remove-if-not
                          (lambda (event)
                            (string= "pi.durable.checkpoint"
                                     (cadr-telemetry:recorded-telemetry-event-name event)))
                          (cadr-telemetry:recorded-telemetry-span-events
                           (first (durable-recorded-spans telemetry "pi.durable.phase"))))))))))

(test durable-session-failure-counts-without-starting-a-span
  (let* ((telemetry (cadr-telemetry:make-in-memory-telemetry))
         (reports nil)
         (closed-before-report nil)
         (storage (cadr-durable:make-memory-storage))
         (harness (cadr-durable:open-harness
                   storage :telemetry telemetry
                   :on-report (lambda (event)
                                (setf closed-before-report
                                      (cadr-durable:storage-closed-p storage))
                                (push event reports))))
         (session (cadr-durable:open-session storage :harness harness)))
    (is (search "Unknown conversation"
                (durable-error-text
                 (lambda ()
                   (cadr-durable:session-commit
                    session
                    (lambda (tx)
                      (cadr-durable:tx-append-entry
                       tx :conversation-id 999 :kind "app.failed")))))))
    (is (cadr-durable:session-failed-p session))
    (is (eq t closed-before-report))
    (is (cadr-durable:storage-closed-p storage))
    (is (null (cadr-telemetry:in-memory-telemetry-spans telemetry)))
    (is (equal '("session_failed") (durable-report-types telemetry)))
    (is (search "Unknown conversation"
                (cadr-chord:json-get (first reports) "message")))
    (is (search "Session failed after a storage error; close and reopen it"
                (durable-error-text
                 (lambda () (cadr-durable:harness-submit harness "later")))))
    (is (search "Session failed after a storage error; close and reopen it"
                (durable-error-text
                 (lambda ()
                   (cadr-durable:session-commit
                    session
                    (lambda (tx)
                      (declare (ignore tx))
                      nil))))))
    (is (null (cadr-telemetry:in-memory-telemetry-spans telemetry)))
    (is (equal '("session_failed") (durable-report-types telemetry)))
    (is (null (search "Unknown conversation"
                      (format nil "~A" (cadr-telemetry:in-memory-measurements telemetry)))))
    (is (null (search "app.failed"
                      (format nil "~A"
                              (append (cadr-telemetry:in-memory-telemetry-spans telemetry)
                                      (cadr-telemetry:in-memory-measurements telemetry))))))))
