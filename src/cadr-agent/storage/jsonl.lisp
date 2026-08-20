(in-package #:cadr-agent)

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
   (cadr-ai::json-object-p value)
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
    (cadr-ai::json-map-entries
     object
     (lambda (key value)
       (setf
        (getf result
              (intern
               (string-upcase key)
               :keyword))
        (cond
          ((cadr-ai::json-object-p value)
           (json-object-to-plist value))
          ((and (vectorp value) (not (stringp value)))
           (map 'list
                (lambda (item)
                  (if (cadr-ai::json-object-p item)
                      (json-object-to-plist item)
                      item))
                value))
          ((cadr-ai::json-null-p value)
           nil)
          (t value)))))
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
               (not (cadr-ai::json-object-p metadata)))
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
