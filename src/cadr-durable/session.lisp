(in-package #:cadr-durable)

(defstruct doc-definition
  name version scope history initial family-p fork)

(defun conversation-fork (scope history fork)
  (or fork
      (and (string= scope "conversation")
           (if (string= history "rewindable") "asOf" "current"))))

(defun define-doc (name &key (version 1) (scope "conversation") (history "latest")
                          initial family fork)
  (make-doc-definition :name name :version version :scope scope :history history
                       :initial (or initial (cadr-chord:json-object))
                       :family-p family
                       :fork (conversation-fork scope history fork)))

(defstruct cached-doc tracker id)

(defun cached-value (cached)
  (cadr-chord:tracker-value (cached-doc-tracker cached)))

(defstruct tx-draft definition scope-id key change new-p id)

(defstruct tx session (writes nil) (drafts nil) (wrote nil) (splices nil))

(defvar *tx* nil)

(defstruct session
  storage
  (failed nil)
  (closed nil)
  (cache (make-hash-table :test #'equal)))

(defun assert-live-session (session)
  (when (session-failed session)
    (fail-session)))

(defun open-session (storage)
  (make-session :storage storage))

(defun session-failed-p (session)
  (session-failed session))

(defun session-close (session)
  (setf (session-closed session) t)
  (storage-close (session-storage session)))

(defun cache-key (name scope-id key)
  (list name scope-id key))

(defun remember-doc (session definition scope-id key tracker id)
  (setf (gethash (cache-key (doc-definition-name definition) scope-id key)
                 (session-cache session))
        (make-cached-doc :tracker tracker :id id)))

(defun tx-doc (tx definition scope-id &optional key)
  (when (tx-wrote tx)
    (error 'read-after-write
           :text "Tx.doc() cannot read tables after the first table write"))
  (let* ((session (tx-session tx))
         (cached (gethash (cache-key (doc-definition-name definition) scope-id key)
                          (session-cache session)))
         (existing (unless cached
                     (storage-find-document
                      (session-storage session)
                      (doc-definition-name definition)
                      (doc-definition-scope definition)
                      scope-id key :current)))
         (tracker (cond
                    (cached (cached-doc-tracker cached))
                    (existing (cadr-chord:track (cdr existing)))
                    (t (cadr-chord:track (cadr-chord:copy-json
                                          (doc-definition-initial definition))))))
         (change (cadr-chord:tracker-begin-change tracker)))
    (push (make-tx-draft :definition definition :scope-id scope-id :key key
                         :change change :new-p (not (or cached existing))
                         :id (cond (cached (cached-doc-id cached))
                                   (existing (document-record-id (car existing)))))
          (tx-drafts tx))
    (cadr-chord:change-state change)))

(defun doc-set (document key value)
  (setf (gethash key document) (cadr-chord:copy-json value)))

(defun tx-append-entry (tx &key conversation-id kind model data id by-task-id)
  (setf (tx-wrote tx) t)
  (let ((entry (make-entry
                :id (or id (storage-mint-id (session-storage (tx-session tx))))
                :conversation-id conversation-id
                :kind kind :model model :data data :by-task-id by-task-id)))
    (push (cons :entry entry) (tx-writes tx))
    entry))

(defun tx-scan-entries (tx conversation-id &key order limit cursor)
  (when (tx-wrote tx)
    (error 'read-after-write
           :text "Tx.scanEntries() cannot read tables after the first table write"))
  (storage-scan-entries (session-storage (tx-session tx)) conversation-id
                        :order order :limit limit :cursor cursor))

(defun abort-drafts (tx)
  (dolist (draft (tx-drafts tx))
    (cadr-chord:change-abort (tx-draft-change draft))))

(defun find-json-path (node target &optional path)
  (cond
    ((eq node target) path)
    ((hash-table-p node)
     (let ((found nil))
       (maphash (lambda (key value)
                  (unless found
                    (setf found (find-json-path value target (append path (list key))))))
                node)
       found))
    ((and (vectorp node) (not (stringp node)))
     (loop for item across node
           for index from 0
           for found = (find-json-path item target (append path (list (princ-to-string index))))
           when found return found))))

(defun note-splice (array kind &optional item)
  (when *tx*
    (let ((log (tx-splices *tx*)))
      (if (and (eq kind :pop) log (eq (first (car log)) :push) (eq (second (car log)) array))
          (setf (tx-splices *tx*) (cdr log))
          (push (list kind array item) (tx-splices *tx*))))))

(defun draft-push (array item)
  (vector-push-extend item array)
  (note-splice array :push)
  (length array))

(defun draft-pop (array)
  (let ((item (vector-pop array)))
    (note-splice array :pop item)
    item))

(defun draft-shift (array)
  (let ((first (aref array 0)))
    (loop for index from 0 below (1- (length array))
          do (setf (aref array index) (aref array (1+ index))))
    (vector-pop array)
    (note-splice array :shift first)
    first))

(defun draft-unshift (array item)
  (adjust-array array (1+ (length array)) :fill-pointer (1+ (length array)))
  (loop for index from (1- (length array)) downto 1
        do (setf (aref array index) (aref array (1- index))))
  (setf (aref array 0) item)
  (note-splice array :unshift item)
  (length array))

(defun structural-ops (draft)
  (let ((root (cadr-chord:change-state (tx-draft-change draft)))
        (ops nil))
    (dolist (entry (reverse (tx-splices *tx*)))
      (let ((path (find-json-path root (second entry))))
        (when path
          (case (first entry)
            (:shift (push (list "p" path 0 1 nil) ops))
            (:unshift (push (list "p" path 0 0 (list (third entry))) ops))))))
    (nreverse ops)))

(defun publish-draft (draft)
  (let* ((change (tx-draft-change draft))
         (preparation (cadr-chord:change-prepare change))
         (ops (or (cadr-chord:preparation-ops preparation)
                  (structural-ops draft)))
         (base (cadr-chord::change-base change))
         (published (if ops (cadr-chord:apply-immutable base ops) base)))
    (setf (cadr-chord:tracker-value (cadr-chord::change-tracker change)) published)
    (cadr-chord:change-abort change)
    (values published ops)))

(defun prepare-drafts (session tx)
  (let ((*tx* tx))
  (dolist (draft (reverse (tx-drafts tx)))
    (multiple-value-bind (published ops) (publish-draft draft)
      (let ((definition (tx-draft-definition draft)))
        (cond
          ((tx-draft-new-p draft)
           (let* ((storage (session-storage session))
                  (id (storage-mint-id storage))
                  (tracker (cadr-chord::change-tracker (tx-draft-change draft))))
             (setf (cadr-chord:tracker-value tracker) published)
             (push (cons :document-create
                         (list :record
                               (make-document-record
                                :id id
                                :kind (doc-definition-name definition)
                                :scope-kind (doc-definition-scope definition)
                                :scope-id (tx-draft-scope-id draft)
                                :key (tx-draft-key draft)
                                :version (doc-definition-version definition)
                                :history (doc-definition-history definition)
                                :fork (doc-definition-fork definition))
                               :content
                               (make-document-revision
                                :kind "base"
                                :version (doc-definition-version definition)
                                :value published)))
                   (tx-writes tx))
             (remember-doc session definition (tx-draft-scope-id draft)
                           (tx-draft-key draft) tracker id)))
          (ops
           (push (cons :document-change
                       (list :id (tx-draft-id draft)
                             :content
                             (make-document-revision
                              :kind "delta"
                              :version (doc-definition-version definition)
                              :ops ops)))
                 (tx-writes tx))
           (remember-doc session definition (tx-draft-scope-id draft)
                         (tx-draft-key draft)
                         (cadr-chord::change-tracker (tx-draft-change draft))
                         (tx-draft-id draft)))))))))

(defun storage-document-records (storage)
  (record-list (durable-state-documents (storage-state storage)) #'copy-document-record))

(defun fork-member-name (record)
  (if (document-record-key record)
      (format nil "~A/~A" (document-record-kind record) (document-record-key record))
      (document-record-kind record)))

(defun live-fork-documents (storage scope-id at policy)
  (let ((best (make-hash-table :test #'equal)))
    (dolist (record (storage-document-records storage))
      (when (and (string= (document-record-scope-kind record) "conversation")
                 (eql (document-record-scope-id record) scope-id)
                 (string= (or (document-record-fork record) "") policy)
                 (document-alive-p record at))
        (let* ((address (list (document-record-kind record) (document-record-key record)))
               (previous (gethash address best)))
          (when (or (null previous)
                    (> (document-record-id record) (document-record-id previous)))
            (setf (gethash address best) record)))))
    (loop for record being the hash-values of best collect record)))

(defun push-fork-copy (session tx seen record at child-id)
  (let ((address (list (document-record-kind record) (document-record-key record))))
    (when (gethash address seen)
      (error "Fork selects multiple source documents for ~A" (fork-member-name record)))
    (setf (gethash address seen) t)
    (push (cons :document-create
                (list :record
                      (make-document-record
                       :id (storage-mint-id (session-storage session))
                       :kind (document-record-kind record)
                       :scope-kind "conversation"
                       :scope-id child-id
                       :key (document-record-key record)
                       :version (document-record-version record)
                       :history (document-record-history record)
                       :fork (document-record-fork record))
                      :content
                      (make-document-revision
                       :kind "base"
                       :version (document-record-version record)
                       :value (cadr-chord:copy-json (revision-value record at)))))
          (tx-writes tx))))

(defun copy-fork-documents (session tx owner-id parent-id at child-id)
  (let ((seen (make-hash-table :test #'equal))
        (storage (session-storage session)))
    (dolist (record (live-fork-documents storage owner-id at "asOf"))
      (push-fork-copy session tx seen record at child-id))
    (dolist (record (live-fork-documents storage parent-id :current "current"))
      (push-fork-copy session tx seen record nil child-id))))

(defun session-fork (session parent-id at)
  (assert-live-session session)
  (let ((visible (storage-entry (session-storage session) at parent-id)))
    (unless visible
      (error "Entry ~A is not visible from conversation ~A" at parent-id))
    (let ((child nil)
          (entry (car visible))
          (seq (cdr visible)))
      (session-commit session
                      (lambda (tx)
                        (setf (tx-wrote tx) t)
                        (setf child (storage-mint-id (session-storage session)))
                        (push (cons :conversation
                                    (make-conversation :id child :parent-id parent-id
                                                       :parent-at at))
                              (tx-writes tx))
                        (copy-fork-documents session tx (entry-conversation-id entry)
                                             parent-id seq child)))
      child)))

(defun session-commit (session function)
  (assert-live-session session)
  (let ((tx (make-tx :session session)))
    (handler-case (let ((*tx* tx)) (funcall function tx))
      (error (condition)
        (abort-drafts tx)
        (error condition)))
    (prepare-drafts session tx)
    (handler-case
        (storage-commit (session-storage session) (nreverse (tx-writes tx)))
      (error (condition)
        (setf (session-failed session) t)
        (error condition)))))

(defun session-snapshot (session definition scope-id &optional key)
  (assert-live-session session)
  (let* ((name (doc-definition-name definition))
         (cached (gethash (cache-key name scope-id key) (session-cache session))))
    (if cached
        (cached-value cached)
        (let ((found (storage-find-document
                      (session-storage session) name
                      (doc-definition-scope definition) scope-id key :current)))
          (when found
            (let ((tracker (cadr-chord:track (cdr found))))
              (remember-doc session definition scope-id key tracker
                            (document-record-id (car found)))
              (cadr-chord:tracker-value tracker)))))))
