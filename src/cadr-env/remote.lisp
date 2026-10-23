(in-package #:cadr-env)

(defstruct env-ok value)

(defstruct env-err code message path)

(defstruct remote-env connection id cwd)

(defstruct remote-reader env handle session path (closed nil))

(defun remote-fail (condition &optional path)
  (let ((code (remote-error-code condition))
        (message (remote-error-message condition)))
    (make-env-err :code (cond ((equal code "aborted") "aborted")
                              ((equal code "ENOENT") "not_found")
                              ((member code '("EACCES" "EPERM") :test #'equal) "permission_denied")
                              ((equal code "ENOTDIR") "not_directory")
                              ((equal code "EISDIR") "is_directory")
                              ((member code '("EINVAL" "SYMLINK" "NOT_REGULAR") :test #'equal) "invalid")
                              (t "unknown"))
          :message message
          :path (or (remote-error-path condition) path))))

(defun remote-resolve (env path)
  (let* ((info (spawn-info (remote-env-connection env)))
         (home (json-get info "home")))
    (cond
      ((equal path "~") home)
      ((and (>= (length path) 2) (char= (char path 0) #\~)
            (member (char path 1) '(#\/ #\\)))
       (concatenate 'string (strip-slash home) (subseq path 1)))
      ((and (>= (length path) 7) (string= path "file://" :end1 7))
       (or (file-url-path path) path))
      ((and (plusp (length path)) (char= (char path 0) #\/)) path)
      (t (concatenate 'string (strip-slash (remote-env-cwd env)) "/" path)))))

(defun remote-catch (path function)
  (handler-case
      (make-env-ok :value (funcall function))
    (remote-error (condition) (remote-fail condition path))
    (env-failure (condition)
      (make-env-err :code (env-failure-code condition)
                    :message (env-failure-message condition)
                    :path (or (env-failure-path condition) path)))))

(defun remote-write (env path content append &key abort)
  (let ((bytes (if (stringp content) (utf8-bytes content) content)))
    (remote-catch path
      (lambda ()
        (let* ((resolved (remote-resolve env path))
               (first (subseq bytes 0 (min +write-chunk+ (length bytes))))
               (keep (> (length bytes) +write-chunk+)))
          (when (and (not append) (env-abort-p abort))
            (error 'remote-error :code "aborted" :message "aborted" :path resolved))
          (let ((reply (spawn-request (remote-env-connection env) "write"
                                      (json-object "path" resolved "append" (and append t)
                                                   "keep" (and keep t))
                                      :payload first :abort (unless append abort))))
            (when keep
              (let ((handle (json-get reply "handle"))
                    (session (spawn-session-id-of (remote-env-connection env))))
                (unwind-protect
                     (loop for offset from +write-chunk+ below (length bytes) by +write-chunk+
                           do (when (and (not append) (env-abort-p abort))
                                (error 'remote-error :code "aborted" :message "The operation was aborted"
                                       :path resolved))
                              (spawn-request (remote-env-connection env) "writeChunk"
                                             (json-object "handle" handle)
                                             :payload (subseq bytes offset
                                                              (min (+ offset +write-chunk+) (length bytes)))
                                             :session session
                                             :abort (unless append abort)))
                  (ignore-errors
                    (spawn-request (remote-env-connection env) "close"
                                   (json-object "handle" handle)
                                   :session session))))))
          nil)))))

(defun remote-write-file (env path content &key abort)
  (remote-write env path content nil :abort abort))

(defun remote-append-file (env path content &key abort)
  (remote-write env path content t :abort abort))

(defun remote-open-read (env resolved)
  (let ((reply (spawn-request (remote-env-connection env) "open"
                              (json-object "path" resolved "mode" "read"))))
    (values (json-get reply "handle")
            (spawn-session-id-of (remote-env-connection env))
            (json-get reply "stat"))))

(defun remote-pread (env handle session offset length)
  (multiple-value-bind (json payload)
      (spawn-request (remote-env-connection env) "pread"
                     (json-object "handle" handle "offset" offset "length" length)
                     :session session)
    (declare (ignore json))
    payload))

(defun remote-read-bytes (env resolved)
  (multiple-value-bind (handle session stat) (remote-open-read env resolved)
    (unwind-protect
         (let ((size (if (and (json-object-p stat) (equal (json-get stat "kind") "file"))
                         (json-get stat "size")
                         0)))
           (cond
             ((not (integerp size)) #())
             ((zerop size) #())
             (t
              (let ((bytes (make-array size :element-type '(unsigned-byte 8)))
                    (filled 0))
                (loop while (< filled size)
                      for chunk = (remote-pread env handle session filled
                                                (min +read-chunk+ (- size filled)))
                      do (when (zerop (length chunk)) (return))
                         (replace bytes chunk :start1 filled)
                         (incf filled (length chunk)))
                (if (= filled size) bytes (subseq bytes 0 filled))))))
      (ignore-errors
        (spawn-request (remote-env-connection env) "close"
                       (json-object "handle" handle)
                       :session session)))))

(defun remote-read-text-file (env path)
  (remote-catch path
    (lambda ()
      (utf8-string (remote-read-bytes env (remote-resolve env path))))))

(defun remote-read-binary-file (env path)
  (remote-catch path
    (lambda ()
      (remote-read-bytes env (remote-resolve env path)))))

(defun remote-open-binary-reader (env path &key no-follow)
  (remote-catch path
    (lambda ()
      (let* ((resolved (remote-resolve env path))
             (reply (spawn-request (remote-env-connection env) "open"
                                   (json-object "path" resolved
                                                "noFollow" (and no-follow t)))))
        (make-remote-reader :env env
                            :handle (json-get reply "handle")
                            :session (spawn-session-id-of (remote-env-connection env))
                            :path resolved)))))

(defun remote-reader-read (reader offset length)
  (if (remote-reader-closed reader)
      (make-env-err :code "invalid" :message "Binary reader is closed"
                    :path (remote-reader-path reader))
      (remote-catch (remote-reader-path reader)
        (lambda ()
          (let ((bytes (make-array 0 :element-type '(unsigned-byte 8) :adjustable t :fill-pointer 0))
                (filled 0))
            (loop while (< filled length)
                  for want = (min +read-chunk+ (- length filled))
                  for chunk = (remote-pread (remote-reader-env reader)
                                            (remote-reader-handle reader)
                                            (remote-reader-session reader)
                                            (+ offset filled)
                                            want)
                  do (when (zerop (length chunk)) (return))
                     (loop for byte across chunk do (vector-push-extend byte bytes))
                     (incf filled (length chunk))
                     (when (< (length chunk) want) (return)))
            bytes)))))

(defun remote-reader-close (reader)
  (setf (remote-reader-closed reader) t)
  (ignore-errors
    (spawn-request (remote-env-connection (remote-reader-env reader)) "close"
                   (json-object "handle" (remote-reader-handle reader))
                   :session (remote-reader-session reader))))

(defun remote-exec-fail (condition)
  (let ((code (remote-error-code condition)))
    (make-env-err :code (cond ((equal code "timeout") "timeout")
                              ((equal code "aborted") "aborted")
                              ((or (equal code "spawn_error") (equal code "shell_unavailable")) code)
                              (t "unknown"))
                  :message (remote-error-message condition))))

(defun remote-exec (env command &key on-output timeout abort window)
  (when (env-abort-p abort)
    (return-from remote-exec (make-env-err :code "aborted" :message "aborted")))
  (when (and timeout (or (not (realp timeout)) (<= timeout 0)))
    (return-from remote-exec
      (make-env-err :code "timeout" :message "Invalid timeout: must be a finite number of seconds")))
  (handler-case
      (let ((request (json-object "cwd" (remote-env-cwd env)
                                  "inheritEnv" t
                                  "env" (json-object))))
        (if (stringp command)
            (json-put request "command" command)
            (json-put request "argv" (apply #'json-array (coerce command 'list))))
        (when timeout
          (json-put request "timeoutMs" (round (* timeout 1000))))
        (when window
          (json-put request "window"
                    (json-object "maxBytes" (getf window :max-bytes)
                                 "maxLines" (getf window :max-lines)
                                 "minIntervalMs" (getf window :min-interval-ms)
                                 "bytesPerSecond" (getf window :bytes-per-second))))
        (let ((reply (spawn-request (remote-env-connection env) "exec" request
                                    :abort abort
                                    :on-event (lambda (json payload)
                                                (when (and on-output (equal (json-get json "kind") "output"))
                                                  (funcall on-output
                                                           (utf8-string payload)
                                                           (let ((skipped (json-get json "skipped")))
                                                             (when (json-object-p skipped) skipped))))))))
          (make-env-ok :value (json-get reply "exitCode"))))
    (remote-error (condition) (remote-exec-fail condition))))

(defun remote-list-files (env path &key exclude max-entries abort)
  (handler-case
      (let ((resolved (remote-resolve env path)))
        (when max-entries
          (unless (list-files-bound-p max-entries)
            (return-from remote-list-files
              (make-env-err :code "invalid"
                            :message "maxEntries must be a non-negative safe integer"
                            :path resolved))))
        (when (env-abort-p abort)
          (return-from remote-list-files
            (make-env-err :code "aborted" :message "aborted" :path resolved)))
        (let ((features (json-get (spawn-info (remote-env-connection env)) "features")))
          (unless (and (json-array-p features) (find "listFiles" features :test #'equal))
            (return-from remote-list-files
              (make-env-err :code "not_supported"
                            :message (wire-literal :list-unsupported)
                            :path resolved))))
        (let ((request (json-object "path" resolved)))
          (when exclude (json-put request "exclude" (apply #'json-array exclude)))
          (when max-entries (json-put request "maxEntries" max-entries))
          (multiple-value-bind (json payload)
              (spawn-request (remote-env-connection env) "listFiles" request :abort abort)
            (make-env-ok :value (list :entries (decode-list-entries payload)
                                      :truncated (eq (json-get json "truncated") t))))))
    (remote-error (condition) (remote-fail condition path))))

(defun decode-list-entries (payload)
  (let ((items nil)
        (start 0))
    (loop while (< start (length payload))
          for end = (position 0 payload :start (1+ start))
          while end
          do (let ((kind (cond ((= (aref payload start) +kind-file+) "file")
                               ((= (aref payload start) +kind-directory+) "directory")
                               ((= (aref payload start) +kind-symlink+) "symlink"))))
               (when kind
                 (push (list :path (utf8-string payload :start (1+ start) :end end)
                             :kind kind)
                       items)))
             (setf start (1+ end)))
    (nreverse items)))
