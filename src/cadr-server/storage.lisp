(in-package #:cadr-server)

(defun ensure-server-directory (directory)
  (let ((directory
          (uiop:ensure-directory-pathname
           directory)))
    (ensure-directories-exist
     (merge-pathnames "anchor" directory))
    directory))

(defun read-json-file (path)
  (cadr-ai::parse-json
   (uiop:read-file-string
    path :external-format :utf-8)))

(defun write-json-file (path value)
  (ensure-server-directory
   (uiop:pathname-directory-pathname
    path))
  (cadr-core:call-with-atomic-output-file
   path
   (lambda (stream)
     (write-string
      (cadr-ai::stringify-json value)
      stream)
     (terpri stream))
   :durability :flush)
  value)

(defun machine-record-json (record)
  (let ((object
          (cadr-ai::json-object
           "id" (machine-record-id record)
           "createdAt"
           (machine-record-created-at record))))
    (when (machine-record-last-seen-at
           record)
      (cadr-ai::json-put
       object "lastSeenAt"
       (machine-record-last-seen-at
        record)))
    (when (machine-record-label record)
      (cadr-ai::json-put
       object "label"
       (machine-record-label record)))
    object))

(defun json-machine-record (object)
  (make-machine-record
   :id (cadr-ai::json-get object "id")
   :created-at
   (cadr-ai::json-get object "createdAt")
   :last-seen-at
   (cadr-ai::json-get object "lastSeenAt")
   :label
   (cadr-ai::json-get object "label")))

(defun instance-record-json (record)
  (let ((object
          (cadr-ai::json-object
           "id" (instance-record-id record)
           "status"
           (string-downcase
            (symbol-name
             (instance-record-status record)))
           "cwd" (instance-record-cwd record)
           "createdAt"
           (instance-record-created-at record))))
    (dolist
        (entry
         `(("lastSeenAt"
            . ,(instance-record-last-seen-at
                record))
           ("label"
            . ,(instance-record-label
                record))
           ("sessionId"
            . ,(instance-record-session-id
                record))
           ("sessionFile"
            . ,(instance-record-session-file
                record))
           ("radiusPiId"
            . ,(instance-record-radius-pi-id
                record))))
      (when (cdr entry)
        (cadr-ai::json-put
         object (car entry) (cdr entry))))
    object))

(defun json-instance-record (object)
  (let ((status
          (cadr-ai::json-get
           object "status")))
    (make-instance-record
     :id (cadr-ai::json-get object "id")
     :status
     (and status
          (intern
           (string-upcase status)
           :keyword))
     :cwd (cadr-ai::json-get object "cwd")
     :created-at
     (cadr-ai::json-get object "createdAt")
     :last-seen-at
     (cadr-ai::json-get object "lastSeenAt")
     :label
     (cadr-ai::json-get object "label")
     :session-id
     (cadr-ai::json-get object "sessionId")
     :session-file
     (cadr-ai::json-get object "sessionFile")
     :radius-pi-id
     (cadr-ai::json-get object "radiusPiId"))))

(defun load-machine
    (&optional (directory (server-directory)))
  (let ((path
          (server-machine-path directory)))
    (and (probe-file path)
         (json-machine-record
          (read-json-file path)))))

(defun save-machine
    (directory machine)
  (write-json-file
   (server-machine-path directory)
   (machine-record-json machine))
  machine)

(defun delete-machine
    (&optional (directory (server-directory)))
  (let ((path
          (server-machine-path directory)))
    (when (probe-file path)
      (delete-file path)))
  nil)

(defun load-instances
    (&optional (directory (server-directory)))
  (let ((path
          (server-instances-path directory)))
    (if (not (probe-file path))
        nil
        (map 'list
             #'json-instance-record
             (read-json-file path)))))

(defun save-instances
    (directory instances)
  (write-json-file
   (server-instances-path directory)
   (cadr-ai::list-json-array
    (mapcar
     #'instance-record-json
     instances)))
  instances)

(defun get-stored-instance
    (directory instance-id)
  (find instance-id
        (load-instances directory)
        :key #'instance-record-id
        :test #'string=))

(defun upsert-instance
    (directory instance)
  (let* ((instances
           (load-instances directory))
         (existing
           (position
            (instance-record-id instance)
            instances
            :key #'instance-record-id
            :test #'string=)))
    (if existing
        (setf (nth existing instances)
              instance)
        (setf instances
              (append instances
                      (list instance))))
    (save-instances
     directory instances)
    instance))

(defun remove-instance
    (directory instance-id)
  (save-instances
   directory
   (remove
    instance-id
    (load-instances directory)
    :key #'instance-record-id
    :test #'string=))
  nil)
