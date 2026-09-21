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

(defstruct session-list-info
  id
  path
  cwd
  name
  parent-session
  (created 0 :type integer)
  (modified 0 :type integer)
  (message-count 0 :type integer)
  first-message
  (all-messages-text "" :type string))

(defun session-list-info-file-mtime-ms (path)
  (handler-case
      (* (sb-posix:stat-mtime (sb-posix:stat path)) 1000)
    (error () 0)))

(defun read-session-list-info (path &key expected-cwd)
  ;; One open, buffered LF walk. Header via parse-session-header-octets;
  ;; later lines via parse-session-record-octets (schema walker).
  ;; Not load-session. Not by-id. Not entry cons. Not labels table.
  (handler-case
      (with-open-file
          (stream path
                  :direction :input
                  :element-type '(unsigned-byte 8))
        (let ((chunk
                (make-array
                 65536
                 :element-type '(unsigned-byte 8)))
              (pending
                (make-array
                 256
                 :element-type '(unsigned-byte 8)
                 :adjustable t
                 :fill-pointer 0))
              (info nil)
              (header-scanned 0)
              (mtime-ms
                (session-list-info-file-mtime-ms path))
              (last-activity 0)
              (corpus nil))
          (labels
              ((blank-p (octets start end)
                 (loop for index from start below end
                       for unit = (aref octets index)
                       always
                       (or (= unit 32)
                           (= unit 9)
                           (= unit 13)
                           (= unit 10))))
               (accept-header (octets start end)
                 (when
                     (>
                      (- end start)
                      +max-session-header-scan-bytes+)
                   (return-from read-session-list-info nil))
                 (let ((header
                         (handler-case
                             (parse-session-header-octets
                              octets start end)
                           (error () nil))))
                   (unless
                       (and header
                            (string=
                             "session"
                             (session-file-header-type header))
                            (stringp
                             (session-file-header-id header)))
                     (return-from read-session-list-info nil))
                   (setf info
                         (make-session-list-info
                          :id (session-file-header-id header)
                          :path path
                          :cwd (session-file-header-cwd header)
                          :parent-session
                          (session-file-header-parent-session
                           header)
                          :created mtime-ms
                          :modified 0))
                   (when
                       (and expected-cwd
                            (not
                             (string=
                              expected-cwd
                              (or
                               (session-list-info-cwd info)
                               ""))))
                     (return-from read-session-list-info nil))))
               (note-message (entry)
                 (incf (session-list-info-message-count info))
                 (let ((message (session-entry-message entry)))
                   (flet ((note-text (role timestamp text)
                            (when
                                (and
                                 (stringp role)
                                 (or (string= role "user")
                                     (string= role "assistant"))
                                 (integerp timestamp))
                              (setf last-activity
                                    (max last-activity timestamp)))
                            (when
                                (and
                                 (stringp text)
                                 (plusp
                                  (length
                                   (string-trim
                                    '(#\Space #\Tab #\Newline
                                      #\Return)
                                    text)))
                                 (or (string= role "user")
                                     (string= role "assistant")))
                              (push text corpus)
                              (when
                                  (and
                                   (null
                                    (session-list-info-first-message
                                     info))
                                   (string= role "user"))
                                (setf
                                 (session-list-info-first-message
                                  info)
                                 text)))))
                     (cond
                       ((session-json-message-p message)
                        (note-text
                         (session-json-message-role message)
                         (session-json-message-timestamp message)
                         (content-text
                          (session-json-message-content message)
                          "")))
                       ((typep message 'cadr-ai:user-message)
                        (note-text
                         "user"
                         (cadr-ai:user-message-timestamp message)
                         (content-text
                          (cadr-ai:user-message-content message)
                          "")))
                       ((typep message
                               'cadr-ai:assistant-message)
                        (note-text
                         "assistant"
                         (cadr-ai:assistant-message-timestamp
                          message)
                         (content-text
                          (cadr-ai:assistant-message-content
                           message)
                          "")))))))
               (accept-entry (octets start end)
                 (let ((entry
                         (handler-case
                             (parse-session-record-octets
                              octets start end)
                           (error () nil))))
                   (when entry
                     (case
                         (session-type-keyword
                          (session-entry-type entry))
                       (:session-info
                        (let ((name (session-entry-name entry)))
                          (when (stringp name)
                            (setf
                             (session-list-info-name info)
                             name))))
                       (:message
                        (note-message entry))))))
               (handle-line (octets start end)
                 (unless (blank-p octets start end)
                   (if (null info)
                       (accept-header octets start end)
                       (accept-entry octets start end))))
               (flush-pending ()
                 (when (plusp (fill-pointer pending))
                   (handle-line
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
                          (handle-line chunk start lf))
                         (t
                          (loop for copy of-type fixnum
                                from start below lf
                                do (vector-push-extend
                                    (aref chunk copy)
                                    pending))
                          (handle-line
                           pending
                           0
                           (fill-pointer pending))
                          (setf (fill-pointer pending) 0)))
                       (setf start (1+ lf)))))))
            (loop
              (when
                  (and
                   (null info)
                   (>= header-scanned
                       +max-session-header-scan-bytes+))
                (return-from read-session-list-info nil))
              (let* ((room
                       (if info
                           (length chunk)
                           (- +max-session-header-scan-bytes+
                              header-scanned)))
                     (end (min (length chunk) room))
                     (count
                       (read-sequence
                        chunk stream :end end)))
                (declare (type fixnum count))
                (when (zerop count)
                  (flush-pending)
                  (return))
                (unless info
                  (incf header-scanned count))
                (scan-chunk count)))
            (when info
              (setf (session-list-info-modified info)
                    (if (plusp last-activity)
                        last-activity
                        mtime-ms)
                    (session-list-info-all-messages-text info)
                    (if corpus
                        (format nil "~{~A~^ ~}" (nreverse corpus))
                        "")))
            info)))
    (error () nil)))

(defun session-list-publish-partial-p (loaded total interval)
  ;; pi@ecac0a9c4 listSessionsFromDir / listAll: first, every N, and last.
  (or (= loaded 1)
      (zerop (mod loaded interval))
      (= loaded total)))

(defun call-session-list-progress
    (progress-function loaded total
     &optional publish-partial-p partial-infos)
  ;; Two-arg callers stay valid on non-publish ticks. Publish ticks
  ;; always pass a third argument (possibly NIL) so empty partials
  ;; still match baseline's defined partialSessions array.
  (when progress-function
    (if publish-partial-p
        (funcall progress-function loaded total partial-infos)
        (funcall progress-function loaded total))))

(defun list-session-infos (&key
                                 (directory
                                   (default-session-directory))
                                 cwd
                                 progress-function)
  ;; pi@ecac0a9c4 SessionListProgress: (loaded, total, partialSessions?).
  ;; cwd-filtered listing publishes every 10; list-all (no cwd) every 100.
  (let* ((session-directory
           (uiop:ensure-directory-pathname directory))
         (canonical-cwd
           (and cwd (canonical-session-cwd cwd)))
         (publish-interval
           (if canonical-cwd 10 100)))
    (unless (probe-file session-directory)
      (return-from list-session-infos nil))
    (let* ((paths
             (directory
              (merge-pathnames
               "*.jsonl" session-directory)))
           (total (length paths))
           (partial nil)
           (infos
             (loop for path in paths
                   for loaded from 1
                   for info =
                     (read-session-list-info
                      path
                      :expected-cwd canonical-cwd)
                   do
                   (when info
                     (push info partial))
                   (when progress-function
                     (let ((publish-partial-p
                             (session-list-publish-partial-p
                              loaded total publish-interval)))
                       (call-session-list-progress
                        progress-function
                        loaded
                        total
                        publish-partial-p
                        (when publish-partial-p
                          (sort
                           (copy-list partial)
                           #'>
                           :key #'session-list-info-modified)))))
                   when info
                     collect info)))
      (sort infos #'> :key #'session-list-info-modified))))

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
           ;; pi@13cbf77df SessionManager.list onProgress: invoked per
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
  (let ((info
          (find id
                (list-session-infos :directory directory)
                :key #'session-list-info-id
                :test #'string=)))
    (if info
        (load-session (session-list-info-path info))
        (session-failure
         (uiop:ensure-directory-pathname directory)
         nil
         "Session not found: ~A" id))))

(defun continue-session (&key
                               (directory
                                 (default-session-directory))
                               cwd)
  (let ((info
          (first
           (list-session-infos
            :directory directory
            :cwd (or cwd (uiop:getcwd))))))
    (and info
         (load-session (session-list-info-path info)))))
