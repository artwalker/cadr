(in-package #:cadr-agent)

(defun session-header-candidate (octets)
  (handler-case
      (let ((line
              (sb-ext:octets-to-string
               octets :external-format :utf-8)))
        (if
            (zerop
             (length
              (string-trim
               '(#\Space #\Tab #\Newline #\Return)
               line)))
            :skip
            (let ((object (cadr-ai::parse-json line)))
              (if
                  (and
                   (hash-table-p object)
                   (string=
                    "session"
                    (cadr-ai::json-get object "type" ""))
                   (stringp
                    (cadr-ai::json-get object "id")))
                  object
                  :invalid))))
    (error () :skip)))

(defun read-session-header-for-discovery (path)
  (handler-case
      (with-open-file
          (stream path
                  :direction :input
                  :element-type '(unsigned-byte 8))
        (let ((line
                (make-array
                 256
                 :element-type '(unsigned-byte 8)
                 :adjustable t
                 :fill-pointer 0))
              (scanned 0))
          (labels
              ((inspect-line ()
                 (let ((candidate
                         (session-header-candidate
                          line)))
                   (setf (fill-pointer line) 0)
                   (cond
                     ((eq candidate :skip) nil)
                     ((eq candidate :invalid)
                      (return-from
                          read-session-header-for-discovery
                        nil))
                     (t
                      (return-from
                          read-session-header-for-discovery
                        candidate))))))
            (loop
              (when
                  (= scanned
                     +max-session-header-scan-bytes+)
                (let ((probe
                        (read-byte stream nil :eof)))
                  (if (eq probe :eof)
                      (progn
                        (inspect-line)
                        (return nil))
                      (return nil))))
              (let ((octet
                      (read-byte stream nil :eof)))
                (when (eq octet :eof)
                  (inspect-line)
                  (return nil))
                (incf scanned)
                (if (= octet 10)
                    (inspect-line)
                    (vector-push-extend
                     octet line)))))))
    (error () nil)))

(defun list-sessions (&key
                            (directory
                              (default-session-directory))
                            cwd
                            progress-function)
  (let* ((session-directory
           (uiop:ensure-directory-pathname directory))
         (canonical-cwd
           (and cwd (canonical-session-cwd cwd))))
    (unless (probe-file session-directory)
      (return-from list-sessions nil))
    (sort
     (loop with paths =
             (directory
              (merge-pathnames
               "*.jsonl" session-directory))
           with total = (length paths)
           for path in paths
           for loaded from 1
           for header =
             (read-session-header-for-discovery
              path)
           ;; pi@4e58f324f SessionManager.list onProgress: invoked per
           ;; scanned session file with 1-based loaded and total counts.
           do (when progress-function
                (funcall progress-function loaded total))
           when
             (and
              header
              (or
               (null canonical-cwd)
               (string=
                canonical-cwd
                (cadr-ai::json-get
                 header "cwd" ""))))
             append
             (let ((session
                     (handler-case
                         (load-session path)
                       (session-error
                           (condition)
                         (if
                             (eql
                              1
                              (session-error-line
                               condition))
                             (error condition)
                             nil)))))
               (if session
                   (list session)
                   nil)))
     #'> :key #'session-modified-timestamp)))

(defun resume-session
    (id &key (directory (default-session-directory)))
  (let ((session
          (find id
                (list-sessions :directory directory)
                :key #'session-id
                :test #'string=)))
    (or session
        (session-failure
         (uiop:ensure-directory-pathname directory)
         nil
         "Session not found: ~A" id))))

(defun continue-session (&key
                               (directory
                                 (default-session-directory))
                               cwd)
  (first
   (list-sessions
    :directory directory
    :cwd (or cwd (uiop:getcwd)))))

