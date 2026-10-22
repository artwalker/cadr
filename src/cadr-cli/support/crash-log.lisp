(in-package #:cadr-cli)

(defparameter +crash-log-max-records+ 5)
(defparameter +crash-log-max-age-ms+
  (* 7 24 60 60 1000))

(defun crash-log-path (&optional (agent-dir (cadr-core:coding-agent-directory)))
  (merge-pathnames "crashes.json" agent-dir))

(defun crash-record-from-json (object)
  (when (hash-table-p object)
    (let ((timestamp (cadr-ai::json-get object "timestamp"))
          (message (cadr-ai::json-get object "message")))
      (when (and (stringp timestamp) (stringp message))
        (list
         :timestamp timestamp
         :version (cadr-ai::json-get object "version")
         :kind (cadr-ai::json-get object "kind")
         :message message
         :stack (cadr-ai::json-get object "stack")
         :session-file (cadr-ai::json-get object "sessionFile")
         :cwd (cadr-ai::json-get object "cwd")
         :notified
         (let ((value (cadr-ai::json-get object "notified")))
           (cond
             ((eq value 'null) nil)
             ((null value) nil)
             (t (and value t)))))))))

(defun crash-record-to-json (record &key include-notified-p)
  (let ((object (make-hash-table :test #'equal)))
    (setf (gethash "timestamp" object) (getf record :timestamp))
    (setf (gethash "version" object)
          (or (getf record :version) (cadr-ai::cadr-version)))
    (setf (gethash "kind" object)
          (or (getf record :kind) "fatal_error"))
    (setf (gethash "message" object) (getf record :message))
    (setf (gethash "stack" object)
          (or (getf record :stack) 'null))
    (setf (gethash "sessionFile" object)
          (or (getf record :session-file) 'null))
    (setf (gethash "cwd" object)
          (or (getf record :cwd) ""))
    (when (and include-notified-p (getf record :notified))
      (setf (gethash "notified" object) t))
    object))

(defun read-crash-log (&optional (path (crash-log-path)))
  (unless (probe-file path)
    (return-from read-crash-log nil))
  (handler-case
      (let ((parsed
              (cadr-ai::parse-json
               (uiop:read-file-string path))))
        (cond
          ((listp parsed)
           (remove
            nil
            (mapcar
             (lambda (item)
               (crash-record-from-json
                (if (hash-table-p item)
                    item
                    (cadr-ai::json-object))))
             parsed)))
          ((and (vectorp parsed)
                (not (stringp parsed)))
           (loop for item across parsed
                 for record = (crash-record-from-json item)
                 when record collect record))
          (t nil)))
    (error () nil)))

(defun write-crash-log (records &optional (path (crash-log-path)))
  (ensure-directories-exist path)
  (let ((payload
          (with-output-to-string (out)
            (cadr-ai::write-json-value
             (map 'vector
                  (lambda (record)
                    (crash-record-to-json
                     record :include-notified-p t))
                  records)
             out)
            (terpri out))))
    (atomic-write-utf8 path payload)
    path))

(defun crash-log-for-diagnostics
    (&optional (path (crash-log-path)))
  (mapcar
   (lambda (record)
     (list
      :timestamp (getf record :timestamp)
      :version (getf record :version)
      :kind (getf record :kind)
      :message (getf record :message)
      :stack (getf record :stack)
      :session-file (getf record :session-file)
      :cwd (getf record :cwd)))
   (read-crash-log path)))

(defun clear-crash-log (&optional (path (crash-log-path)))
  (ignore-errors
    (when (probe-file path)
      (delete-file path)))
  nil)

(defun record-crash
    (&key
       (kind "fatal_error")
       error
       message
       stack
       session-file
       (cwd (uiop:getcwd))
       (path (crash-log-path)))
  (handler-case
      (let* ((text
               (or message
                   (when (typep error 'condition)
                     (princ-to-string error))
                   (and error (princ-to-string error))
                   "Unknown error"))
             (stack-text
               (or stack
                   (when (typep error 'condition)
                     (ignore-errors
                       (cadr-ai::fatal-condition-diagnostic
                        error)))))
             (record
               (list
                :timestamp (cadr-core:current-utc-iso8601)
                :version (cadr-ai::cadr-version)
                :kind kind
                :message text
                :stack stack-text
                :session-file
                (and session-file
                     (uiop:native-namestring session-file))
                :cwd
                (etypecase cwd
                  (null "")
                  (pathname (uiop:native-namestring cwd))
                  (string cwd))
                :notified nil))
             (next
               (append (read-crash-log path) (list record))))
        (when (> (length next) +crash-log-max-records+)
          (setf next
                (subseq next
                        (- (length next) +crash-log-max-records+))))
        (write-crash-log next path)
        record)
    (error () nil)))

(defun crash-record-age-ms (record &optional (now-ms (cadr-core:unix-milliseconds)))
  (handler-case
      (- now-ms
         (cadr-core:iso8601-to-milliseconds
          (getf record :timestamp)))
    (error () most-positive-fixnum)))

(defun take-unnotified-crash
    (&optional
       (path (crash-log-path))
       (now-ms (cadr-core:unix-milliseconds)))
  (let* ((records (read-crash-log path))
         (crash
           (find-if
            (lambda (record)
              (and (not (getf record :notified))
                   (<= (crash-record-age-ms record now-ms)
                       +crash-log-max-age-ms+)))
            (reverse records))))
    (unless crash
      (return-from take-unnotified-crash nil))
    (ignore-errors
      (write-crash-log
       (mapcar
        (lambda (record)
          (if (getf record :notified)
              record
              (append
               (loop for (key val) on record by #'cddr
                     unless (eq key :notified)
                       append (list key val))
               (list :notified t))))
        records)
       path))
    crash))

(defun crash-announcement-text (crash)
  (let* ((when
           (or (getf crash :timestamp) "an unknown time"))
         (message (or (getf crash :message) "Unknown error"))
         (name (cadr-ai::cadr-product-display-name)))
    (format
     nil
     "~A crashed on ~A (~A). Run /bug to report it; the crash details are attached automatically."
     name when message)))
