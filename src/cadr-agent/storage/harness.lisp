(in-package #:cadr-agent)

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
  ;; Baseline v0.84.2: setName accepts undefined to clear the name.
  (let ((entry
          (make-storage-child-entry
           (harness-session-storage session)
           :session-info)))
    (setf
     (session-entry-name entry)
     (and name (sanitize-session-name name)))
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

