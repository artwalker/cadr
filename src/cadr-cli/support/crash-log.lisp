(in-package #:cadr-cli)

(defparameter +crash-log-max-records+ 5)
(defparameter +crash-log-max-age-ms+
  (* 7 24 60 60 1000))

(defun crash-log-path (&optional (agent-dir (cadr-core:coding-agent-directory)))
  (merge-pathnames "crashes.json" agent-dir))

(defun crash-kind-wire (kind)
  (cond
    ((stringp kind) kind)
    ((eq kind :fatal-error) "fatal_error")
    ((eq kind :uncaught-exception) "uncaught_exception")
    (t "fatal_error")))

(defun crash-kind-from-wire (value)
  (cond
    ((string= value "uncaught_exception") :uncaught-exception)
    ((string= value "fatal_error") :fatal-error)
    ((stringp value) value)
    (t :fatal-error)))

(defun crash-record-from-json (object)
  (when (hash-table-p object)
    (let ((timestamp (cadr-ai::json-get object "timestamp"))
          (message (cadr-ai::json-get object "message")))
      (when (and (stringp timestamp) (stringp message))
        (list
         :timestamp timestamp
         :version (cadr-ai::json-get object "version")
         :kind (crash-kind-from-wire
                (cadr-ai::json-get object "kind"))
         :message message
         :stack
         (let ((stack (cadr-ai::json-get object "stack")))
           (if (eq stack 'null) nil stack))
         :session-file
         (let ((session-file
                 (cadr-ai::json-get object "sessionFile")))
           (if (eq session-file 'null) nil session-file))
         :cwd (or (cadr-ai::json-get object "cwd") "")
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
          (crash-kind-wire (getf record :kind)))
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
            (mapcar #'crash-record-from-json parsed)))
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
     (crash-record-to-json record :include-notified-p nil))
   (read-crash-log path)))

(defun clear-crash-log (&optional (path (crash-log-path)))
  (ignore-errors
    (when (probe-file path)
      (delete-file path)))
  nil)

(defun record-crash
    (&key
       (kind :fatal-error)
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
                     (let ((printed (princ-to-string error)))
                       (if (plusp (length printed))
                           printed
                           (string (type-of error)))))
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
                :kind (crash-kind-from-wire (crash-kind-wire kind))
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

(defun crash-record-age-ms
    (record &optional (now-ms (cadr-core:unix-milliseconds)))
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

(defun format-crash-local-when (timestamp)
  (handler-case
      (let* ((ms (cadr-core:iso8601-to-milliseconds timestamp))
             (universal
               (+ (floor ms 1000)
                  cadr-core::+unix-universal-time-offset+)))
        (multiple-value-bind
              (second minute hour day month year)
            (decode-universal-time universal)
          (let* ((hour12 (mod hour 12))
                 (hour12 (if (zerop hour12) 12 hour12))
                 (ampm (if (< hour 12) "AM" "PM")))
            (format nil "~D/~D/~D, ~D:~2,'0D:~2,'0D ~A"
                    month day year hour12 minute second ampm))))
    (error () (or timestamp "an unknown time"))))

(defun crash-announcement-text (crash)
  (let* ((when
           (format-crash-local-when
            (getf crash :timestamp)))
         (message (or (getf crash :message) "Unknown error"))
         (name (cadr-ai::cadr-product-display-name)))
    (format
     nil
     "~A crashed on ~A (~A). Run /bug to report it; the crash details are attached automatically."
     name when message)))

(defun crash-report-instructions (&optional session-file)
  (let* ((slug (cadr-ai::cadr-product-slug))
         (resume
           (if session-file
               (format nil "run `~A -r` to resume the session, then"
                       slug)
               (format nil "start ~A and" slug))))
    (format
     nil
     "To report this crash: ~A run /bug. The crash details are attached automatically."
     resume)))
