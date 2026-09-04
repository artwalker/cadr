(in-package #:cadr-agent)

(defconstant +session-header-read-buffer-size+ 4096)

(defun blank-header-octets-p (octets start end)
  (loop for index from start below end
        for unit = (aref octets index)
        always
        (or (= unit 32)
            (= unit 9)
            (= unit 13)
            (= unit 10))))

(defun session-header-candidate (octets &optional (start 0) end)
  (let ((end (or end (length octets))))
    (cond
      ((or (>= start end)
           (blank-header-octets-p octets start end))
       :skip)
      (t
       (handler-case
           (let ((header
                   (parse-session-header-octets
                    octets start end)))
             (if
                 (and
                  (string=
                   "session"
                   (session-file-header-type header))
                  (stringp
                   (session-file-header-id header)))
                 header
                 :invalid))
         (error () :skip))))))

(defun read-session-header-for-discovery (path)
  ;; Buffered read-sequence + parse-session-header-octets.
  ;; Sibling of load-session header walk. Not per-byte read-byte.
  ;; Not string JSON roundtrip.
  (handler-case
      (with-open-file
          (stream path
                  :direction :input
                  :element-type '(unsigned-byte 8))
        (let ((chunk
                (make-array
                 +session-header-read-buffer-size+
                 :element-type '(unsigned-byte 8)))
              (pending
                (make-array
                 256
                 :element-type '(unsigned-byte 8)
                 :adjustable t
                 :fill-pointer 0))
              (scanned 0))
          (labels
              ((finish (candidate)
                 (cond
                   ((eq candidate :skip) nil)
                   ((eq candidate :invalid)
                    (return-from
                        read-session-header-for-discovery
                      nil))
                   (t
                    (return-from
                        read-session-header-for-discovery
                      candidate))))
               (inspect-range (octets start end)
                 (finish
                  (session-header-candidate
                   octets start end)))
               (flush-pending ()
                 (when (plusp (fill-pointer pending))
                   (inspect-range
                    pending 0 (fill-pointer pending))
                   (setf (fill-pointer pending) 0)))
               (scan-chunk (count)
                 (let ((start 0))
                   (declare (type fixnum start count))
                   (loop
                     (let ((lf
                             (octet-find-lf
                              chunk start count)))
                       (unless lf
                         (when (< start count)
                           (loop for copy of-type fixnum
                                 from start below count
                                 do (vector-push-extend
                                     (aref chunk copy)
                                     pending)))
                         (return))
                       (cond
                         ((zerop (fill-pointer pending))
                          (inspect-range chunk start lf))
                         (t
                          (loop for copy of-type fixnum
                                from start below lf
                                do (vector-push-extend
                                    (aref chunk copy)
                                    pending))
                          (inspect-range
                           pending
                           0
                           (fill-pointer pending))
                          (setf (fill-pointer pending) 0)))
                       (setf start (1+ lf)))))))
            (loop
              (let ((room
                      (- +max-session-header-scan-bytes+
                         scanned)))
                (when (<= room 0)
                  (let ((probe
                          (read-byte stream nil :eof)))
                    (if (eq probe :eof)
                        (progn
                          (flush-pending)
                          (return nil))
                        (return nil))))
                (let* ((want
                         (min
                          (length chunk)
                          room))
                       (count
                         (read-sequence
                          chunk stream
                          :end want)))
                  (declare (type fixnum count))
                  (when (zerop count)
                    (flush-pending)
                    (return nil))
                  (incf scanned count)
                  (scan-chunk count)))))))
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
           ;; pi@b79e4cc83 SessionManager.list onProgress: invoked per
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
                (session-header-ref
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
