(in-package #:cadr-durable)

(defconstant +root-conversation-id+ 1)
(defconstant +max-safe-integer+ 9007199254740991)
(defconstant +default-max-lines+ 2000)
(defconstant +default-max-bytes+ (* 50 1024))
(defconstant +default-restart-limit+ 5)

(defun user-entry-kind () "pi.user")
(defun assistant-entry-kind () "pi.assistant")
(defun system-entry-kind () "pi.system")
(defun tool-result-entry-kind () "pi.tool-result")
(defun reset-entry-kind () "pi.reset")
(defun compaction-entry-kind () "pi.compaction")

(defstruct (conversation (:constructor %make-conversation))
  id parent-id parent-at (owner-kind "ownerless") owner-id)

(defun make-conversation (&key (id +root-conversation-id+) parent-id parent-at
                            (owner-kind "ownerless") owner-id)
  (%make-conversation :id id :parent-id parent-id :parent-at parent-at
                      :owner-kind owner-kind :owner-id owner-id))

(defstruct (entry (:constructor %make-entry))
  id conversation-id kind model data head by-task-id commit-seq)

(defun make-entry (&key id conversation-id kind model data head by-task-id commit-seq)
  (%make-entry :id id :conversation-id conversation-id :kind kind :model model
               :data data :head head :by-task-id by-task-id :commit-seq commit-seq))

(defstruct (task-record (:constructor %make-task-record))
  id kind version conversation-id owner input state restarts
  (abort-requested nil) abort-reason (background nil))

(defun make-task-record (&key id kind (version 1) conversation-id owner input state
                           restarts abort-requested abort-reason background)
  (%make-task-record :id id :kind kind :version version :conversation-id conversation-id
                     :owner owner :input input :state state :restarts restarts
                     :abort-requested abort-requested :abort-reason abort-reason
                     :background background))

(defstruct submission-record
  id conversation-id request-id type status entry answer reason)

(defstruct document-record
  id kind scope-kind scope-id key (version 1) (history "latest") fork
  created-at retired-at revisions)

(defstruct document-revision kind version value ops seq)

(defstruct (page (:constructor make-page (items next)))
  items next)

(defstruct durable-state
  (ids (make-hash-table :test #'eql))
  (conversations (make-hash-table :test #'eql))
  (entries (make-hash-table :test #'eql))
  (tasks (make-hash-table :test #'eql))
  (submissions (make-hash-table :test #'eql))
  (documents (make-hash-table :test #'eql))
  (requests (make-hash-table :test #'equal))
  (next-id 2)
  (seq 0))

(defun copy-table (table)
  (let ((copy (make-hash-table :test (hash-table-test table))))
    (maphash (lambda (key value) (setf (gethash key copy) value)) table)
    copy))

(defun copy-state (state)
  (make-durable-state
   :ids (copy-table (durable-state-ids state))
   :conversations (copy-table (durable-state-conversations state))
   :entries (copy-table (durable-state-entries state))
   :tasks (copy-table (durable-state-tasks state))
   :submissions (copy-table (durable-state-submissions state))
   :documents (copy-table (durable-state-documents state))
   :requests (copy-table (durable-state-requests state))
   :next-id (durable-state-next-id state)
   :seq (durable-state-seq state)))

(defun note-id (state id table)
  (when (and (integerp id) (> id +max-safe-integer+))
    (error "ID space is exhausted"))
  (setf (gethash id (durable-state-ids state)) table)
  (when (integerp id)
    (setf (durable-state-next-id state)
          (max (durable-state-next-id state) (1+ id)))))

(defun claim-id (state id table replacing-ok)
  (let ((existing (gethash id (durable-state-ids state))))
    (cond
      ((and existing (not (and replacing-ok (string= existing table))))
       (error "ID ~A already belongs to ~A" id existing))
      ((null existing)
       (note-id state id table)))))

(defun require-conversation (state id)
  (or (gethash id (durable-state-conversations state))
      (request-error (format nil "Unknown conversation: ~A" id))))

(defun cursor-after (cursor)
  (when cursor
    (let ((after (cadr-chord:json-get cursor "after"))
          (order (cadr-chord:json-get cursor "order" cadr-chord:+json-absent+)))
      (unless (and (integerp after) (<= 0 after +max-safe-integer+))
        (request-error "Invalid storage cursor"))
      (when (and (not (cadr-chord:json-absent-p order))
                 (not (member order '("ascending" "descending") :test #'string=)))
        (request-error "Invalid storage cursor"))
      (values after (if (cadr-chord:json-absent-p order) nil order)))))

(defun resolve-order (requested cursor fallback)
  (when (and requested
             (not (member requested '("ascending" "descending") :test #'string=)))
    (request-error (format nil "Invalid scan order: ~A" requested)))
  (multiple-value-bind (after stored) (cursor-after cursor)
    (let ((order (or stored requested fallback)))
      (when (and requested stored (not (string= requested stored)))
        (request-error
         (format nil "The cursor continues a ~A scan; the query asks for ~A"
                 stored requested)))
      (values (or requested order) after))))

(defun next-cursor (id order)
  (cadr-chord:json-object "after" id "order" order))

(defun sorted-ids (table)
  (sort (loop for id being the hash-keys of table collect id) #'<))

(defun page-ids (ids order after limit)
  (let* ((filtered
           (if (string= order "ascending")
               (remove-if (lambda (id) (and after (<= id after))) ids)
               (nreverse (remove-if (lambda (id) (and after (>= id after))) ids))))
         (items (subseq filtered 0 (min limit (length filtered)))))
    (if (> (length filtered) limit)
        (make-page items (next-cursor (car (last items)) order))
        (make-page items nil))))

(defun ancestor-bounds (state conversation-id upper)
  (require-conversation state conversation-id)
  (let ((segments nil)
        (current conversation-id)
        (bound upper))
    (loop
      (push (cons current bound) segments)
      (let ((conversation (gethash current (durable-state-conversations state))))
        (unless (conversation-parent-id conversation) (return))
        (setf bound (if bound
                        (min bound (conversation-parent-at conversation))
                        (conversation-parent-at conversation)))
        (setf current (conversation-parent-id conversation))))
    (nreverse segments)))

(defun entry-visible-p (state conversation-id entry-id)
  (let ((entry (gethash entry-id (durable-state-entries state))))
    (when entry
      (some (lambda (segment)
              (and (= (entry-conversation-id entry) (car segment))
                   (or (null (cdr segment)) (<= entry-id (cdr segment)))))
            (ancestor-bounds state conversation-id nil)))))

(defun visible-entry-ids (state conversation-id order)
  (let ((ids nil))
    (dolist (segment (ancestor-bounds state conversation-id nil))
      (dolist (id (sorted-ids (durable-state-entries state)))
        (let ((entry (gethash id (durable-state-entries state))))
          (when (and (= (entry-conversation-id entry) (car segment))
                     (or (null (cdr segment)) (<= id (cdr segment))))
            (push id ids)))))
    (setf ids (sort (delete-duplicates ids) #'<))
    (if (string= order "descending") (nreverse ids) ids)))

(defun apply-conversation (state value)
  (claim-id state (conversation-id value) "conversation" nil)
  (setf (gethash (conversation-id value) (durable-state-conversations state)) value))

(defun apply-entry (state value seq)
  (require-conversation state (entry-conversation-id value))
  (claim-id state (entry-id value) "entry" nil)
  (setf (entry-commit-seq value) seq)
  (setf (gethash (entry-id value) (durable-state-entries state)) value))

(defun apply-task (state value)
  (require-conversation state (task-record-conversation-id value))
  (claim-id state (task-record-id value) "task" t)
  (setf (gethash (task-record-id value) (durable-state-tasks state)) value))

(defun apply-submission (state value)
  (require-conversation state (submission-record-conversation-id value))
  (claim-id state (submission-record-id value) "submission" t)
  (setf (gethash (submission-record-id value) (durable-state-submissions state)) value)
  (when (submission-record-request-id value)
    (setf (gethash (cons (submission-record-conversation-id value)
                         (submission-record-request-id value))
                   (durable-state-requests state))
          (submission-record-id value))))

(defun address-key (kind scope-kind scope-id key)
  (list kind scope-kind scope-id key))

(defun document-address-key (record)
  (address-key (document-record-kind record)
               (document-record-scope-kind record)
               (document-record-scope-id record)
               (document-record-key record)))

(defun current-document (state key)
  (let ((found nil))
    (maphash (lambda (id record)
               (declare (ignore id))
               (when (and (null (document-record-retired-at record))
                          (equal (document-address-key record) key))
                 (setf found record)))
             (durable-state-documents state))
    found))

(defun apply-document-create (state record content seq)
  (claim-id state (document-record-id record) "document" nil)
  (when (gethash (document-record-id record) (durable-state-documents state))
    (error "Document ~A already exists" (document-record-id record)))
  (let ((live (current-document state (document-address-key record))))
    (when (and live (not (document-record-retired-at record)))
      (error "Document address already has a current incarnation")))
  (setf (document-record-created-at record) (or (document-record-created-at record) seq))
  (setf (document-record-revisions record)
        (list (make-document-revision :kind "base" :version (document-revision-version content)
                                      :value (document-revision-value content) :seq seq)))
  (setf (gethash (document-record-id record) (durable-state-documents state)) record))

(defun apply-document-change (state id content seq)
  (let ((existing (gethash id (durable-state-documents state))))
    (unless existing (error "Unknown document: ~A" id))
    (when (document-record-retired-at existing)
      (error "Document ~A is retired" id))
    (when (string= (document-revision-kind content) "delta")
      (let ((previous (car (last (document-record-revisions existing)))))
        (unless previous (error "Document ~A delta has no base" id))
        (unless (= (document-revision-version previous) (document-revision-version content))
          (error "Document ~A version transition requires a base" id))))
    (let ((copy (copy-document-record existing)))
      (setf (document-record-revisions copy)
            (append (document-record-revisions existing) (list content)))
      (setf (document-revision-seq (car (last (document-record-revisions copy)))) seq)
      (setf (gethash id (durable-state-documents state)) copy))))

(defun apply-document-retire (state id at)
  (let ((existing (gethash id (durable-state-documents state))))
    (unless existing (error "Unknown document: ~A" id))
    (when (document-record-retired-at existing)
      (error "Document ~A is retired" id))
    (let ((copy (copy-document-record existing)))
      (setf (document-record-retired-at copy) at)
      (setf (gethash id (durable-state-documents state)) copy))))

(defun commit-state (state writes)
  (let ((next (copy-state state))
        (seq (1+ (durable-state-seq state))))
    (if (null writes)
        state
        (progn
          (setf (durable-state-seq next) seq)
          (dolist (write writes)
            (ecase (car write)
              (:conversation (apply-conversation next (cdr write)))
              (:entry (apply-entry next (cdr write) seq))
              (:task (apply-task next (cdr write)))
              (:submission (apply-submission next (cdr write)))
              (:document-create
               (apply-document-create next (getf (cdr write) :record)
                                      (getf (cdr write) :content) seq))
              (:document-change
               (apply-document-change next (getf (cdr write) :id)
                                      (getf (cdr write) :content) seq))
              (:document-retire
               (apply-document-retire next (getf (cdr write) :id)
                                      (or (getf (cdr write) :at) seq)))))
          next))))

(defun state-mint-id (state)
  (when (> (durable-state-next-id state) +max-safe-integer+)
    (error "ID space is exhausted"))
  (prog1 (durable-state-next-id state)
    (incf (durable-state-next-id state))))

(defun state-conversation (state id)
  (let ((found (gethash id (durable-state-conversations state))))
    (when found (copy-conversation found))))

(defun state-entry (state id &optional conversation-id)
  (let ((found (gethash id (durable-state-entries state))))
    (when (and found conversation-id)
      (unless (entry-visible-p state conversation-id id)
        (setf found nil)))
    (when found
      (cons (copy-entry found) (entry-commit-seq found)))))

(defun state-scan-conversations (state &key order limit cursor owner-kind owner-id)
  (multiple-value-bind (resolved after) (resolve-order order cursor "ascending")
    (let ((ids (sorted-ids (durable-state-conversations state))))
      (setf ids
            (remove-if
             (lambda (id)
               (let ((conversation (gethash id (durable-state-conversations state))))
                 (or (and owner-kind
                          (not (string= (conversation-owner-kind conversation) owner-kind)))
                     (and owner-id
                          (not (eql (conversation-owner-id conversation) owner-id))))))
             ids))
      (let ((page (page-ids ids resolved after (or limit 50))))
        (setf (page-items page)
              (mapcar (lambda (id)
                        (copy-conversation
                         (gethash id (durable-state-conversations state))))
                      (page-items page)))
        page))))

(defun state-scan-entries (state conversation-id &key order limit cursor)
  (multiple-value-bind (resolved after) (resolve-order order cursor "descending")
    (let* ((ids (visible-entry-ids state conversation-id "ascending"))
           (page (page-ids ids resolved after (or limit 50))))
      (setf (page-items page)
            (mapcar (lambda (id) (copy-entry (gethash id (durable-state-entries state))))
                    (page-items page)))
      page)))

(defun state-task (state id)
  (let ((found (gethash id (durable-state-tasks state))))
    (when found (copy-task-record found))))

(defun state-scan-tasks (state &key status order limit cursor)
  (multiple-value-bind (resolved after) (resolve-order order cursor "ascending")
    (let ((ids (sorted-ids (durable-state-tasks state))))
      (when status
        (setf ids
              (remove-if
               (lambda (id)
                 (let ((task (gethash id (durable-state-tasks state))))
                   (not (string= (cadr-chord:json-get (task-record-state task) "status")
                                 status))))
               ids)))
      (let ((page (page-ids ids resolved after (or limit 50))))
        (setf (page-items page)
              (mapcar (lambda (id)
                        (copy-task-record (gethash id (durable-state-tasks state))))
                      (page-items page)))
        page))))

(defun state-submission (state id)
  (let ((found (gethash id (durable-state-submissions state))))
    (when found (copy-submission-record found))))

(defun state-submission-by-request (state conversation-id request-id)
  (let ((id (gethash (cons conversation-id request-id) (durable-state-requests state))))
    (when id (state-submission state id))))

(defun revision-value (record at)
  (let ((value nil)
        (version (document-record-version record)))
    (dolist (revision (document-record-revisions record))
      (when (or (null at) (<= (or (document-revision-seq revision) 0) at))
        (cond
          ((string= (document-revision-kind revision) "base")
           (setf value (cadr-chord:copy-json (document-revision-value revision))
                 version (document-revision-version revision)))
          ((/= version (document-revision-version revision))
           (error "Document ~A crosses a stored version boundary without a base"
                  (document-record-id record)))
          (t
           (setf value (cadr-chord:apply-immutable value (ops-as-lists (document-revision-ops revision))))))))
    value))

(defun ops-as-lists (ops)
  (if (listp ops)
      ops
      (map 'list (lambda (op) (coerce op 'list)) ops)))

(defun document-alive-p (record at)
  (and record
       (<= (or (document-record-created-at record) 0) (if (eql at :current) most-positive-fixnum at))
       (or (null (document-record-retired-at record))
           (and (not (eql at :current))
                (< at (document-record-retired-at record))))))

(defun state-find-document (state kind scope-kind scope-id key at)
  (let ((found nil))
    (maphash (lambda (id record)
               (declare (ignore id))
               (when (and (string= (document-record-kind record) kind)
                          (string= (document-record-scope-kind record) scope-kind)
                          (eql (document-record-scope-id record) scope-id)
                          (equal (document-record-key record) key)
                          (document-alive-p record at))
                 (when (or (null found)
                           (> (document-record-id record) (document-record-id found)))
                   (setf found record))))
             (durable-state-documents state))
    (when found
      (cons (copy-document-record found)
            (revision-value found (if (eql at :current) nil at))))))

(defun json-text (value)
  (cadr-chord:canonical-json value))

(defun text-json (text)
  (cadr-chord::parse-json text))

(defun hash-get (object key)
  (cadr-chord:json-get object key))

(defun ensure-hash (value)
  (if (hash-table-p value) value (cadr-chord:json-object)))

(defun task-state-json (state)
  (if (hash-table-p state) state (cadr-chord:json-object "status" "pending")))

(defun record-list (table copier)
  (mapcar (lambda (id) (funcall copier (gethash id table))) (sorted-ids table)))
