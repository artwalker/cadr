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

(defun current-iso8601 ()
  (cadr-core:current-utc-iso8601))

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

