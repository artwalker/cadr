(in-package #:cadr-agent)

(defstruct session-metadata
  (id "" :type string)
  (created-at "" :type string)
  cwd
  path
  parent-session-path
  parent-session-id
  data)

(defgeneric session-storage-metadata (storage))
(defgeneric session-storage-leaf-id (storage))
(defgeneric session-storage-set-leaf-id
    (storage leaf-id))
(defgeneric session-storage-create-entry-id
    (storage))
(defgeneric session-storage-append-entry
    (storage entry))
(defgeneric session-storage-entry
    (storage id))
(defgeneric session-storage-entries
    (storage &key after-entry-seq limit))
(defgeneric session-storage-find-entries
    (storage type))
(defgeneric session-storage-label
    (storage id))
(defgeneric session-storage-name
    (storage))
(defgeneric session-storage-stats
    (storage))
(defgeneric session-storage-path
    (storage leaf-id))
(defgeneric session-storage-cleanup
    (storage))

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

(defun current-iso8601 ()
  (milliseconds-to-iso8601
   (cadr-ai::unix-milliseconds)))

(defun ensure-session-metadata
    (metadata &key id cwd path
                   parent-session-path
                   parent-session-id data)
  (or
   metadata
   (make-session-metadata
    :id (or id (make-session-id))
    :created-at (current-iso8601)
    :cwd cwd
    :path path
    :parent-session-path parent-session-path
    :parent-session-id parent-session-id
    :data data)))

(defun storage-failure
    (storage format-control &rest arguments)
  (apply
   #'session-failure
   (and
    storage
    (ignore-errors
      (session-metadata-path
       (session-storage-metadata storage))))
   nil
   format-control
   arguments))

(defun storage-entry-leaf-id (entry)
  (if (eq :leaf
          (session-entry-type entry))
      (session-entry-target-id entry)
      (session-entry-id entry)))

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

(defstruct harness-session
  storage
  (context-entry-transforms nil :type list)
  (entry-projectors nil :type list))

(defun harness-session-metadata (session)
  (session-storage-metadata
   (harness-session-storage session)))

(defun harness-session-leaf-id (session)
  (session-storage-leaf-id
   (harness-session-storage session)))

(defun harness-session-set-leaf-id
    (session leaf-id)
  (session-storage-set-leaf-id
   (harness-session-storage session)
   leaf-id))

(defun harness-session-entry
    (session id)
  (session-storage-entry
   (harness-session-storage session)
   id))

(defun harness-session-entries
    (session &key after-entry-seq limit)
  (session-storage-entries
   (harness-session-storage session)
   :after-entry-seq after-entry-seq
   :limit limit))

(defun harness-session-name (session)
  (session-storage-name
   (harness-session-storage session)))

(defun harness-session-stats (session)
  (session-storage-stats
   (harness-session-storage session)))

(defun harness-session-branch
    (session &optional
               (leaf-id
                 (harness-session-leaf-id
                  session)))
  (session-storage-path
   (harness-session-storage session)
   leaf-id))

(defun harness-session-build-context-entries
    (session &key entry-transforms)
  (let ((entries
          (harness-session-branch session)))
    (dolist
        (transform
         (append
          (harness-session-context-entry-transforms
           session)
          entry-transforms))
      (setf entries
            (copy-list
             (funcall transform entries))))
    entries))

(defun harness-custom-entry-messages
    (session entry index entries entry-projectors)
  (let* ((projectors
           (append
            (harness-session-entry-projectors
             session)
            entry-projectors))
         (projector
           (cdr
            (assoc
             (session-entry-custom-type entry)
             projectors
             :test #'string=))))
    (and
     projector
     (copy-list
      (funcall
       projector entry index entries)))))

(defun harness-context-entry-messages
    (session entry index entries
     entry-projectors)
  (case (session-entry-type entry)
    (:message
     (list
      (session-entry-message entry)))
    (:custom-message
     (list
      (cadr-ai:make-user-message
       :content
       (session-entry-content entry)
       :timestamp
       (session-entry-timestamp entry))))
    (:compaction
     (append
      (list
       (compaction-summary-message entry))
      (copy-list
       (session-entry-retained-tail
        entry))))
    (:branch-summary
     (list
      (cadr-ai:make-user-message
       :content
       (format
        nil
        "The following is a summary of a branch that this conversation came back from:~%~%<summary>~%~A~%</summary>"
        (session-entry-summary entry))
       :timestamp
       (session-entry-timestamp entry))))
    (:custom
     (harness-custom-entry-messages
      session entry index entries
      entry-projectors))
    (otherwise nil)))

(defun harness-session-build-context
    (session
     &key entry-transforms entry-projectors)
  (let ((thinking-level "off")
        (model nil)
        (active-tool-names nil)
        (path
          (harness-session-branch
           session)))
    (dolist (entry path)
      (case (session-entry-type entry)
        (:thinking-level-change
         (setf
          thinking-level
          (session-entry-thinking-level
           entry)))
        (:model-change
         (setf
          model
          (list
           :provider
           (session-entry-provider entry)
           :model-id
           (session-entry-model-id entry))))
        (:message
         (let ((message
                 (session-entry-message entry)))
           (when
               (typep
                message
                'cadr-ai:assistant-message)
             (setf
              model
              (list
               :provider
               (string-downcase
                (symbol-name
                 (cadr-ai:assistant-message-provider
                  message)))
               :model-id
               (cadr-ai:assistant-message-model
                message))))))
        (:active-tools-change
         (setf
          active-tool-names
          (copy-list
           (session-entry-active-tool-names
            entry))))))
    (let ((entries
            (harness-session-build-context-entries
             session
             :entry-transforms
             entry-transforms)))
      (list
       :thinking-level thinking-level
       :model model
       :active-tool-names active-tool-names
       :messages
       (loop for entry in entries
             for index from 0
             append
             (harness-context-entry-messages
              session entry index entries
              entry-projectors))))))

(defun harness-session-cleanup (session)
  (session-storage-cleanup
   (harness-session-storage session)))

(defun harness-session-append-entry
    (session entry)
  (session-storage-append-entry
   (harness-session-storage session)
   entry))

(defun harness-session-append-message
    (session message)
  (let* ((storage
           (harness-session-storage session))
         (entry
           (make-session-entry
            :type :message
            :id
            (session-storage-create-entry-id
             storage)
            :parent-id
            (session-storage-leaf-id
             storage)
            :timestamp
            (message-timestamp message)
            :message message)))
    (harness-session-append-entry
     session entry)))

(defun harness-session-append-thinking-level
    (session thinking-level)
  (let ((entry
          (make-storage-child-entry
           (harness-session-storage session)
           :thinking-level-change)))
    (setf
     (session-entry-thinking-level entry)
     thinking-level)
    (harness-session-append-entry
     session entry)))

(defun harness-session-append-model
    (session provider model-id)
  (let ((entry
          (make-storage-child-entry
           (harness-session-storage session)
           :model-change)))
    (setf
     (session-entry-provider entry) provider
     (session-entry-model-id entry) model-id)
    (harness-session-append-entry
     session entry)))

(defun harness-session-append-active-tools
    (session active-tool-names)
  (unless (every #'stringp
                 active-tool-names)
    (storage-failure
     (harness-session-storage session)
     "Active tool names must be strings"))
  (let ((entry
          (make-storage-child-entry
           (harness-session-storage session)
           :active-tools-change)))
    (setf
     (session-entry-active-tool-names entry)
     (copy-list active-tool-names))
    (harness-session-append-entry
     session entry)))

(defun harness-session-append-compaction
    (session summary first-kept-id
     tokens-before
     &key details usage from-hook-p
       retained-tail)
  (let ((entry
          (make-storage-child-entry
           (harness-session-storage session)
           :compaction)))
    (setf
     (session-entry-summary entry) summary
     (session-entry-first-kept-id entry)
     first-kept-id
     (session-entry-tokens-before entry)
     tokens-before
     (session-entry-details entry) details
     (session-entry-usage entry) usage
     (session-entry-from-hook-p entry)
     (not (null from-hook-p))
     (session-entry-retained-tail entry)
     (copy-list retained-tail))
    (harness-session-append-entry
     session entry)))

(defun harness-session-append-custom
    (session custom-type &optional data)
  (let ((entry
          (make-storage-child-entry
           (harness-session-storage session)
           :custom)))
    (setf
     (session-entry-custom-type entry)
     custom-type
     (session-entry-data entry)
     data)
    (harness-session-append-entry
     session entry)))

(defun harness-session-append-custom-message
    (session custom-type content display-p
     &key details)
  (let ((entry
          (make-storage-child-entry
           (harness-session-storage session)
           :custom-message)))
    (setf
     (session-entry-custom-type entry)
     custom-type
     (session-entry-content entry)
     (if (stringp content)
         content
         (copy-list content))
     (session-entry-display-p entry)
     (not (null display-p))
     (session-entry-details entry)
     details)
    (harness-session-append-entry
     session entry)))

(defun harness-session-set-name
    (session name)
  (let ((entry
          (make-storage-child-entry
           (harness-session-storage session)
           :session-info)))
    (setf
     (session-entry-name entry)
     (sanitize-session-name name))
    (harness-session-append-entry
     session entry)))

(defun harness-session-set-label
    (session target-id label)
  (unless
      (harness-session-entry
       session target-id)
    (storage-failure
     (harness-session-storage session)
     "Session entry not found: ~A"
     target-id))
  (let ((entry
          (make-storage-child-entry
           (harness-session-storage session)
           :label)))
    (setf
     (session-entry-target-id entry)
     target-id
     (session-entry-label entry)
     label)
    (harness-session-append-entry
     session entry)))

(defun harness-session-move-to
    (session entry-id
     &key summary details usage from-hook-p)
  (when
      (and
       entry-id
       (null
        (harness-session-entry
         session entry-id)))
    (storage-failure
     (harness-session-storage session)
     "Session entry not found: ~A"
     entry-id))
  (harness-session-set-leaf-id
   session entry-id)
  (when summary
    (let ((entry
            (make-storage-child-entry
             (harness-session-storage session)
             :branch-summary)))
      (setf
       (session-entry-parent-id entry)
       entry-id
       (session-entry-from-id entry)
       (or entry-id "root")
       (session-entry-summary entry)
       summary
       (session-entry-details entry)
       details
       (session-entry-usage entry)
       usage
       (session-entry-from-hook-p entry)
       (not (null from-hook-p)))
      (harness-session-append-entry
       session entry))))

(defgeneric session-repository-create
    (repository
     &key id cwd parent-session-path
       parent-session-id metadata))
(defgeneric session-repository-open
    (repository metadata))
(defgeneric session-repository-list
    (repository &key cwd))
(defgeneric session-repository-delete
    (repository metadata))
(defgeneric session-repository-fork
    (repository source-metadata
     &key id cwd parent-session-path
       parent-session-id metadata entry-id
       position))

(defstruct (memory-session-repository
            (:constructor
                make-memory-session-repository
                ()))
  (sessions
    (make-hash-table :test #'equal)
    :type hash-table))

(defmethod session-repository-create
    ((repository memory-session-repository)
     &key id cwd parent-session-path
       parent-session-id metadata)
  (let* ((session-id
           (or id (make-session-id)))
         (session-metadata
           (make-session-metadata
            :id session-id
            :created-at (current-iso8601)
            :cwd cwd
            :parent-session-path
            parent-session-path
            :parent-session-id
            parent-session-id
            :data metadata))
         (session
           (make-harness-session
            :storage
            (make-memory-session-storage
             :metadata session-metadata))))
    (setf
     (gethash
      session-id
      (memory-session-repository-sessions
       repository))
     session)
    session))

(defmethod session-repository-open
    ((repository memory-session-repository)
     metadata)
  (or
   (gethash
    (session-metadata-id metadata)
    (memory-session-repository-sessions
     repository))
   (storage-failure
    nil "Session not found: ~A"
    (session-metadata-id metadata))))

(defmethod session-repository-list
    ((repository memory-session-repository)
     &key cwd)
  (sort
   (loop for session
           being the hash-values of
           (memory-session-repository-sessions
            repository)
         for metadata =
           (harness-session-metadata session)
         when
           (or
            (null cwd)
            (equal cwd
                   (session-metadata-cwd
                    metadata)))
           collect metadata)
   #'string>
   :key #'session-metadata-created-at))

(defmethod session-repository-delete
    ((repository memory-session-repository)
     metadata)
  (remhash
   (session-metadata-id metadata)
   (memory-session-repository-sessions
    repository))
  nil)

(defun session-entries-to-fork
    (storage entry-id position)
  (unless entry-id
    (return-from session-entries-to-fork
      (session-storage-entries storage)))
  (let ((target
          (session-storage-entry
           storage entry-id)))
    (unless target
      (storage-failure
       storage "Invalid fork target: ~A"
       entry-id))
    (let ((effective-leaf
            (if (eq position :at)
                entry-id
                (progn
                  (unless
                      (and
                       (eq :message
                           (session-entry-type
                            target))
                       (typep
                        (session-entry-message target)
                        'cadr-ai:user-message))
                    (storage-failure
                     storage
                     "Fork target must be a user message: ~A"
                     entry-id))
                  (session-entry-parent-id
                   target)))))
      (session-storage-path
       storage effective-leaf))))

(defmethod session-repository-fork
    ((repository memory-session-repository)
     source-metadata
     &key id cwd parent-session-path
       parent-session-id metadata entry-id
       (position :before))
  (declare (ignore parent-session-path
                   parent-session-id))
  (let* ((source
           (session-repository-open
            repository source-metadata))
         (entries
           (session-entries-to-fork
            (harness-session-storage source)
            entry-id position))
         (fork
           (session-repository-create
            repository
            :id id
            :cwd (or cwd
                     (session-metadata-cwd
                      source-metadata))
            :metadata
            (or metadata
                (session-metadata-data
                 source-metadata)))))
    (dolist (entry entries)
      (session-storage-append-entry
       (harness-session-storage fork)
       entry))
    fork))

(defclass jsonl-session-storage
    (memory-session-storage)
  ((environment
    :initarg :environment
    :reader jsonl-storage-environment)
   (file-path
    :initarg :file-path
    :reader jsonl-storage-file-path)))

(defun execution-value-or-session-error
    (thunk description path)
  (multiple-value-bind (value error)
      (funcall thunk)
    (if error
        (session-failure
         path nil "~A: ~A"
         description
         (harness-operation-error-message
          error))
        value)))

(defun metadata-json-data-p (value)
  (or
   (null value)
   (hash-table-p value)
   (plist-like-p value)))

(defun jsonl-header-object (metadata)
  (let ((header
          (cadr-ai::json-object
           "type" "session"
           "version" 3
           "id"
           (session-metadata-id metadata)
           "timestamp"
           (session-metadata-created-at metadata)
           "cwd"
           (or
            (session-metadata-cwd metadata)
            ""))))
    (when
        (session-metadata-parent-session-path
         metadata)
      (cadr-ai::json-put
       header "parentSession"
       (princ-to-string
        (session-metadata-parent-session-path
         metadata))))
    (when (session-metadata-data metadata)
      (unless
          (metadata-json-data-p
           (session-metadata-data metadata))
        (session-failure
         (session-metadata-path metadata)
         1
         "Session header metadata must be an object"))
      (cadr-ai::json-put
       header "metadata"
       (json-safe-value
        (session-metadata-data metadata))))
    header))

(defun json-object-to-plist (object)
  (let ((result nil))
    (maphash
     (lambda (key value)
       (setf
        (getf result
              (intern
               (string-upcase key)
               :keyword))
        (cond
          ((hash-table-p value)
           (json-object-to-plist value))
          ((vectorp value)
           (map 'list
                (lambda (item)
                  (if (hash-table-p item)
                      (json-object-to-plist item)
                      item))
                value))
          ((cadr-ai::json-null-p value)
           nil)
          (t value))))
     object)
    result))

(defun parse-jsonl-header
    (line path)
  (let ((header
          (handler-case
              (cadr-ai::parse-json line)
            (error (cause)
              (session-failure
               path 1
               "First line is not a valid session header: ~A"
               cause)))))
    (validate-session-header header path)
    (unless
        (= 3
           (cadr-ai::json-get
            header "version" 0))
      (session-failure
       path 1 "Unsupported session version"))
    (let ((metadata
            (cadr-ai::json-get
             header "metadata")))
      (when
          (and metadata
               (not
                (cadr-ai::json-null-p metadata))
               (not (hash-table-p metadata)))
        (session-failure
         path 1
         "Session header metadata must be an object")))
    header))

(defun header-to-session-metadata
    (header path)
  (let ((data
          (cadr-ai::json-get
           header "metadata")))
    (make-session-metadata
     :id (cadr-ai::json-get header "id")
     :created-at
     (cadr-ai::json-get header "timestamp")
     :cwd (cadr-ai::json-get header "cwd")
     :path (pathname path)
     :parent-session-path
     (json-null-to-nil
      (cadr-ai::json-get
       header "parentSession"))
     :data
     (and
      (hash-table-p data)
      (json-object-to-plist data)))))

(defun load-jsonl-session-metadata
    (environment path)
  (let ((lines
          (execution-value-or-session-error
           (lambda ()
             (execution-env-read-text-lines
              environment path
              :max-lines 1))
           "Cannot read session header"
           path)))
    (unless
        (and
         lines
         (plusp
          (length
           (string-trim
            '(#\Space #\Tab #\Newline
              #\Return)
            (first lines)))))
      (session-failure
       path 1 "Missing session header"))
    (header-to-session-metadata
     (parse-jsonl-header
      (first lines) path)
     path)))

(defun create-jsonl-session-storage
    (environment path
     &key id cwd parent-session-path
       metadata created-at)
  (let* ((absolute
           (execution-path environment path))
         (session-metadata
           (make-session-metadata
            :id (or id (make-session-id))
            :created-at
            (or created-at
                (current-iso8601))
            :cwd
            (if (pathnamep cwd)
                (namestring cwd)
                cwd)
            :path (pathname absolute)
            :parent-session-path
            parent-session-path
            :data metadata))
         (storage
           (make-instance
            'jsonl-session-storage
            :metadata session-metadata
            :environment environment
            :file-path absolute)))
    (execution-value-or-session-error
     (lambda ()
       (execution-env-write-file
        environment absolute
        (format
         nil "~A~%"
         (cadr-ai::stringify-json
          (jsonl-header-object
           session-metadata)))))
     "Cannot create JSONL session"
     absolute)
    storage))

(defun open-jsonl-session-storage
    (environment path)
  (let* ((absolute
           (execution-path environment path))
         (text
           (execution-value-or-session-error
            (lambda ()
              (execution-env-read-text-file
               environment absolute))
            "Cannot read JSONL session"
            absolute))
         (lines
           (remove-if
            (lambda (line)
              (zerop
               (length
                (string-trim
                 '(#\Space #\Tab #\Return)
                 line))))
            (uiop:split-string
             text :separator '(#\Newline)))))
    (unless lines
      (session-failure
       absolute 1 "Missing session header"))
    (let* ((header
             (parse-jsonl-header
              (first lines) absolute))
           (storage
             (make-instance
              'jsonl-session-storage
              :metadata
              (header-to-session-metadata
               header absolute)
              :environment environment
              :file-path absolute))
           (line-number 1))
      (dolist (line (rest lines))
        (incf line-number)
        (let ((object
                (handler-case
                    (cadr-ai::parse-json line)
                  (error (cause)
                    (session-failure
                     absolute line-number
                     "Invalid JSONL session entry: ~A"
                     cause)))))
          (let ((entry
                  (record-to-session-entry
                   object absolute line-number
                   (memory-storage-by-id
                    storage))))
            (commit-memory-storage-entry
             storage entry))))
      storage)))

(defmethod session-storage-append-entry
    ((storage jsonl-session-storage)
     entry)
  (sb-thread:with-mutex
      ((memory-storage-lock storage))
    (validate-storage-entry storage entry)
    (execution-value-or-session-error
     (lambda ()
       (execution-env-append-file
        (jsonl-storage-environment storage)
        (jsonl-storage-file-path storage)
        (format
         nil "~A~%"
         (cadr-ai::stringify-json
          (session-entry-to-json entry)))))
     "Cannot append JSONL session entry"
     (jsonl-storage-file-path storage))
    (commit-memory-storage-entry
     storage entry))
  (session-entry-id entry))

(defclass jsonl-session-repository ()
  ((environment
    :initarg :environment
    :reader jsonl-repository-environment)
   (sessions-root
    :initarg :sessions-root
    :reader jsonl-repository-sessions-root)))

(defun make-jsonl-session-repository
    (&key environment sessions-root)
  (make-instance
   'jsonl-session-repository
   :environment environment
   :sessions-root
   (execution-path
    environment sessions-root)))

(defun encode-session-cwd (cwd)
  (let* ((text
           (if (pathnamep cwd)
               (namestring cwd)
               (princ-to-string cwd)))
         (without-root
           (string-left-trim
            '(#\/ #\\) text))
         (encoded
           (substitute-if
            #\-
            (lambda (character)
              (member character
                      '(#\/ #\\ #\:)))
            without-root)))
    (format nil "--~A--" encoded)))

(defun jsonl-repository-session-directory
    (repository cwd)
  (execution-normalize-path
   (format
    nil "~A/~A"
    (jsonl-repository-sessions-root
     repository)
    (encode-session-cwd cwd))
   (node-execution-env-cwd
    (jsonl-repository-environment
     repository))))

(defmethod session-repository-create
    ((repository jsonl-session-repository)
     &key id cwd parent-session-path
       parent-session-id metadata)
  (declare (ignore parent-session-id))
  (let* ((environment
           (jsonl-repository-environment
            repository))
         (session-id
           (or id (make-session-id)))
         (created-at
           (current-iso8601))
         (directory
           (jsonl-repository-session-directory
            repository cwd))
         (file-name
           (format
            nil "~A_~A.jsonl"
            (cl-ppcre:regex-replace-all
             "[:.]" created-at "-")
            session-id))
         (path
           (format
            nil "~A/~A"
            (string-right-trim "/" directory)
            file-name)))
    (execution-value-or-session-error
     (lambda ()
       (execution-env-create-directory
        environment directory
        :recursive-p t))
     "Cannot create session directory"
     directory)
    (make-harness-session
     :storage
     (create-jsonl-session-storage
      environment path
      :id session-id
      :cwd cwd
      :parent-session-path
      parent-session-path
      :metadata metadata
      :created-at created-at))))

(defmethod session-repository-open
    ((repository jsonl-session-repository)
     metadata)
  (let ((environment
          (jsonl-repository-environment
           repository))
        (path
          (session-metadata-path metadata)))
    (multiple-value-bind (exists error)
        (execution-env-exists-p
         environment path)
      (when error
        (session-failure
         path nil "Cannot check session: ~A"
         (harness-operation-error-message
          error)))
      (unless exists
        (session-failure
         path nil "Session not found: ~A"
         path)))
    (make-harness-session
     :storage
     (open-jsonl-session-storage
      environment path))))

(defun jsonl-repository-directories
    (repository cwd)
  (if cwd
      (list
       (jsonl-repository-session-directory
        repository cwd))
      (let ((root
              (jsonl-repository-sessions-root
               repository))
            (environment
              (jsonl-repository-environment
               repository)))
        (multiple-value-bind (exists error)
            (execution-env-exists-p
             environment root)
          (when error
            (session-failure
             root nil "Cannot check sessions root: ~A"
             (harness-operation-error-message
              error)))
          (unless exists
            (return-from
                jsonl-repository-directories
              nil)))
        (remove-if-not
         (lambda (info)
           (eq :directory
               (execution-file-info-kind
                info)))
         (execution-value-or-session-error
          (lambda ()
            (execution-env-list-directory
             environment root))
          "Cannot list sessions root"
          root)))))

(defmethod session-repository-list
    ((repository jsonl-session-repository)
     &key cwd)
  (let ((environment
          (jsonl-repository-environment
           repository))
        (sessions nil))
    (dolist
        (directory
         (jsonl-repository-directories
          repository cwd))
      (let ((path
              (if
                  (typep directory
                         'execution-file-info)
                  (execution-file-info-path
                   directory)
                  directory)))
        (multiple-value-bind (exists error)
            (execution-env-exists-p
             environment path)
          (when error
            (session-failure
             path nil
             "Cannot check session directory: ~A"
             (harness-operation-error-message
              error)))
          (when exists
            (dolist
                (entry
                 (execution-value-or-session-error
                  (lambda ()
                    (execution-env-list-directory
                     environment path))
                  "Cannot list session directory"
                  path))
              (when
                  (and
                   (eq :file
                       (execution-file-info-kind
                        entry))
                   (uiop:string-suffix-p
                    (execution-file-info-name
                     entry)
                    ".jsonl"))
                (handler-case
                    (push
                     (load-jsonl-session-metadata
                      environment
                      (execution-file-info-path
                       entry))
                     sessions)
                  (session-error ()))))))))
    (sort sessions #'string>
          :key
          #'session-metadata-created-at)))

(defmethod session-repository-delete
    ((repository jsonl-session-repository)
     metadata)
  (execution-value-or-session-error
   (lambda ()
     (execution-env-remove
      (jsonl-repository-environment
       repository)
      (session-metadata-path metadata)
      :force-p t))
   "Cannot delete session"
   (session-metadata-path metadata))
  nil)

(defmethod session-repository-fork
    ((repository jsonl-session-repository)
     source-metadata
     &key id cwd parent-session-path
       parent-session-id metadata entry-id
       (position :before))
  (declare (ignore parent-session-id))
  (let* ((source
           (session-repository-open
            repository source-metadata))
         (entries
           (session-entries-to-fork
            (harness-session-storage source)
            entry-id position))
         (fork
           (session-repository-create
            repository
            :id id
            :cwd (or cwd
                     (session-metadata-cwd
                      source-metadata))
            :parent-session-path
            (or parent-session-path
                (namestring
                 (session-metadata-path
                  source-metadata)))
            :metadata
            (or metadata
                (session-metadata-data
                 source-metadata)))))
    (dolist (entry entries)
      (harness-session-append-entry
       fork entry))
    fork))
