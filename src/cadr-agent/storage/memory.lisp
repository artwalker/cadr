(in-package #:cadr-agent)

(defclass memory-session-storage ()
  ((metadata
    :initarg :metadata
    :reader session-storage-metadata)
   (entries
    :initform nil
    :accessor memory-storage-entries)
   (by-id
    :initform
    (make-hash-table :test #'equal)
    :reader memory-storage-by-id)
   (labels
    :initform
    (make-hash-table :test #'equal)
    :reader memory-storage-labels)
   (leaf-id
    :initform nil
    :accessor memory-storage-leaf-id)
   (lock
    :initform
    (sb-thread:make-mutex
     :name "cadr-memory-session-storage")
    :reader memory-storage-lock)))

(defun validate-storage-entry
    (storage entry)
  (unless (typep entry 'session-entry)
    (storage-failure
     storage "Session entry must be a session-entry"))
  (let ((id (session-entry-id entry))
        (parent-id
          (session-entry-parent-id entry))
        (by-id
          (memory-storage-by-id storage)))
    (unless
        (and
         (stringp id)
         (plusp (length id)))
      (storage-failure
       storage "Session entry is missing id"))
    (when (gethash id by-id)
      (storage-failure
       storage "Duplicate session entry id: ~A" id))
    (when
        (and
         parent-id
         (not (gethash parent-id by-id)))
      (storage-failure
       storage
       "Missing session parent: ~A"
       parent-id))
    (when
        (member
         (session-entry-type entry)
         '(:label :leaf))
      (let ((target-id
              (session-entry-target-id entry)))
        (unless
            (or
             (and
              (eq :leaf
                  (session-entry-type entry))
              (null target-id))
             (and
              (stringp target-id)
              (gethash target-id by-id)))
          (storage-failure
           storage
           "Session entry target does not exist: ~S"
           target-id)))))
  entry)

(defun update-storage-label
    (storage entry)
  (when (eq :label
            (session-entry-type entry))
    (let ((label
            (and
             (session-entry-label entry)
             (string-trim
              '(#\Space #\Tab)
              (session-entry-label entry)))))
      (if
          (and label (plusp (length label)))
          (setf
           (gethash
            (session-entry-target-id entry)
            (memory-storage-labels storage))
           label)
          (remhash
           (session-entry-target-id entry)
           (memory-storage-labels storage))))))

(defun commit-memory-storage-entry
    (storage entry)
  (setf
   (memory-storage-entries storage)
   (nconc
    (memory-storage-entries storage)
    (list entry))
   (gethash
    (session-entry-id entry)
    (memory-storage-by-id storage))
   entry
   (memory-storage-leaf-id storage)
   (storage-entry-leaf-id entry))
  (update-storage-label storage entry)
  entry)

(defun initialize-memory-storage
    (storage entries)
  (dolist (entry (copy-list entries))
    (validate-storage-entry storage entry)
    (commit-memory-storage-entry
     storage entry))
  storage)

(defun make-memory-session-storage
    (&key metadata entries)
  (initialize-memory-storage
   (make-instance
    'memory-session-storage
    :metadata
    (ensure-session-metadata metadata))
   entries))

(defmethod session-storage-leaf-id
    ((storage memory-session-storage))
  (let ((leaf-id
          (memory-storage-leaf-id storage)))
    (when
        (and
         leaf-id
         (not
          (gethash
           leaf-id
           (memory-storage-by-id storage))))
      (storage-failure
       storage "Session leaf does not exist: ~A"
       leaf-id))
    leaf-id))

(defun make-storage-child-entry
    (storage type)
  (make-session-entry
   :type type
   :id
   (session-storage-create-entry-id
    storage)
   :parent-id
   (session-storage-leaf-id storage)
   :timestamp
   (cadr-ai::unix-milliseconds)))

(defmethod session-storage-set-leaf-id
    ((storage memory-session-storage)
     leaf-id)
  (when
      (and
       leaf-id
       (not
        (gethash
         leaf-id
         (memory-storage-by-id storage))))
    (storage-failure
     storage "Session entry not found: ~A"
     leaf-id))
  (let ((entry
          (make-storage-child-entry
           storage :leaf)))
    (setf
     (session-entry-target-id entry)
     leaf-id)
    (session-storage-append-entry
     storage entry))
  leaf-id)

(defmethod session-storage-create-entry-id
    ((storage memory-session-storage))
  (make-session-entry-id
   (memory-storage-by-id storage)))

(defmethod session-storage-append-entry
    ((storage memory-session-storage)
     entry)
  (sb-thread:with-mutex
      ((memory-storage-lock storage))
    (validate-storage-entry storage entry)
    (commit-memory-storage-entry
     storage entry))
  (session-entry-id entry))

(defmethod session-storage-entry
    ((storage memory-session-storage)
     id)
  (gethash id (memory-storage-by-id storage)))

(defmethod session-storage-entries
    ((storage memory-session-storage)
     &key after-entry-seq limit)
  (let* ((entries
           (memory-storage-entries storage))
         (start
           (min
            (or after-entry-seq 0)
            (length entries)))
         (end
           (and
            limit
            (min
             (length entries)
             (+ start limit)))))
    (copy-list
     (subseq entries start end))))

(defmethod session-storage-find-entries
    ((storage memory-session-storage)
     type)
  (remove-if-not
   (lambda (entry)
     (eq type
         (session-entry-type entry)))
   (memory-storage-entries storage)))

(defmethod session-storage-label
    ((storage memory-session-storage)
     id)
  (gethash id
           (memory-storage-labels storage)))

(defmethod session-storage-name
    ((storage memory-session-storage))
  (let ((entry
          (car
           (last
            (session-storage-find-entries
             storage :session-info)))))
    (and
     entry
     (session-entry-name entry)
     (let ((name
             (string-trim
              '(#\Space #\Tab)
              (session-entry-name entry))))
       (and
        (plusp (length name))
        name)))))

(defun entry-usage-for-stats (entry)
  (case (session-entry-type entry)
    (:message
     (let ((message
             (session-entry-message entry)))
       (and
        (typep message
               'cadr-ai:assistant-message)
        (cadr-ai:assistant-message-usage
         message))))
    ((:compaction :branch-summary)
     (session-entry-usage entry))
    (otherwise nil)))

(defmethod session-storage-stats
    ((storage memory-session-storage))
  (let ((message-count 0)
        (cached-tokens 0)
        (uncached-tokens 0)
        (total-tokens 0)
        (cost-total 0d0))
    (dolist
        (entry
         (memory-storage-entries storage))
      (when (eq :message
                (session-entry-type entry))
        (incf message-count))
      (let ((usage
              (entry-usage-for-stats entry)))
        (when usage
          (incf cached-tokens
                (cadr-ai:usage-cache-read
                 usage))
          (incf uncached-tokens
                (+
                 (cadr-ai:usage-input usage)
                 (cadr-ai:usage-cache-write
                  usage)))
          (incf total-tokens
                (+
                 (cadr-ai:usage-input usage)
                 (cadr-ai:usage-output usage)
                 (cadr-ai:usage-cache-read
                  usage)
                 (cadr-ai:usage-cache-write
                  usage)))
          (incf cost-total
                (cadr-ai:cost-total
                 (cadr-ai:usage-cost usage))))))
    (list
     :message-count message-count
     :cached-tokens cached-tokens
     :uncached-tokens uncached-tokens
     :total-tokens total-tokens
     :cost-total cost-total)))

(defmethod session-storage-path
    ((storage memory-session-storage)
     leaf-id)
  (when (null leaf-id)
    (return-from session-storage-path nil))
  (let ((path nil)
        (stop-at nil)
        (current
          (session-storage-entry
           storage leaf-id))
        (seen
          (make-hash-table :test #'equal)))
    (unless current
      (storage-failure
       storage "Session entry not found: ~A"
       leaf-id))
    (loop while current
          do
          (when
              (gethash
               (session-entry-id current)
               seen)
            (storage-failure
             storage "Cycle in session tree at ~A"
             (session-entry-id current)))
          (setf
           (gethash
            (session-entry-id current)
            seen)
           t)
          (push current path)
          (when
              (and
               stop-at
               (string=
                stop-at
                (session-entry-id current)))
            (return))
          (when
              (eq :compaction
                  (session-entry-type current))
            (if
                (session-entry-retained-tail current)
                (return)
                (setf
                 stop-at
                 (session-entry-first-kept-id
                  current))))
          (let ((parent-id
                  (session-entry-parent-id current)))
            (if (null parent-id)
                (return)
                (setf
                 current
                 (session-storage-entry
                  storage parent-id))))
          (unless current
            (storage-failure
             storage "Missing session parent")))
    path))

(defmethod session-storage-cleanup
    ((storage memory-session-storage))
  (declare (ignore storage))
  nil)

