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
                                  (lambda () (cadr-durable:open-jsonl-storage sidecar))))))
               (uiop:delete-directory-tree sidecar :validate t))))
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
                    (diagnostic (first (cadr-durable:tool-result-diagnostics result))))
               (is (string= "info" (cadr-chord:json-get diagnostic "severity")))
               (is (null (cadr-chord:json-get diagnostic "code")))
               (is (string= "40 more lines in file. Use offset=61 to continue."
                            (cadr-chord:json-get diagnostic "message")))))
           (cadr-durable:execute-write
            env "long.txt"
            (concatenate 'string (make-string 40000 :initial-element #\é) #(#\Newline) "next" #(#\Newline)))
           (let* ((result (cadr-durable:execute-read env "long.txt"))
                  (diagnostic (first (cadr-durable:tool-result-diagnostics result))))
             (is (string= "warn" (cadr-chord:json-get diagnostic "severity")))
             (is (string= "truncated" (cadr-chord:json-get diagnostic "code")))
             (is (search "Line 1 is 78.1KB, exceeds the 50.0KB limit"
                         (cadr-chord:json-get diagnostic "message")))
             (is (search "tail -c +51201" (cadr-chord:json-get diagnostic "message"))))
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
      (uiop:delete-directory-tree directory :validate t))))

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

(test durable-telemetry-schema-names-the-submit-span-and-the-report-metric
  (let ((schema cadr-durable:*durable-telemetry-schema*))
    (is (= 1 (cadr-telemetry:telemetry-schema-version schema)))
    (is (assoc "pi.durable.submit" (cadr-telemetry:telemetry-schema-spans schema) :test #'string=))
    (is (assoc "pi.durable.reports" (cadr-telemetry:telemetry-schema-metrics schema) :test #'string=))))
