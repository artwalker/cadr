(in-package #:cadr-env)

(defstruct env-ok value)

(defstruct env-err code message path)

(defconstant +read-file-unknown-chunk+ (* 64 1024))
(defconstant +read-file-max+ #.(1- (expt 2 31)))
(defconstant +line-chunk+ (* 64 1024))
(defconstant +max-timeout-ms+ 2147483647)

(defstruct remote-env
  connection id cwd
  (running (make-hash-table :test #'eql))
  (running-lock (sb-thread:make-mutex :name "env-running")))

(defstruct remote-dir-reader env handle session path (done nil) (closed nil))

(defstruct remote-line-reader
  env handle session path
  (offset 0)
  (buffered "")
  (ended nil)
  (closed nil)
  (decoder (make-utf8-decoder)))

(defstruct remote-watcher env abort mode (closed nil) thread)

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

(defun posix-normalize (path)
  (let ((absolute (and (plusp (length path)) (char= (char path 0) #\/)))
        (parts nil))
    (loop for start = 0 then (1+ end)
          for end = (position #\/ path :start start)
          for segment = (subseq path start (or end (length path)))
          do (cond
               ((or (equal segment "") (equal segment ".")) nil)
               ((equal segment "..")
                (when parts (pop parts)))
               (t (push segment parts)))
          while end)
    (let ((body (format nil "~{~A~^/~}" (nreverse parts))))
      (cond (absolute (if (equal body "") "/" (concatenate 'string "/" body)))
            ((equal body "") ".")
            (t body)))))

(defun posix-join (parts)
  (let ((joined nil))
    (dolist (part parts)
      (when (and (stringp part) (plusp (length part)))
        (setf joined (if joined (concatenate 'string joined "/" part) part))))
    (if joined (posix-normalize joined) ".")))

(defun concat-bytes (chunks total)
  (cond
    ((null chunks) (make-array 0 :element-type '(unsigned-byte 8)))
    ((and (null (cdr chunks)) (= (length (car chunks)) total)) (car chunks))
    (t (let ((bytes (make-array total :element-type '(unsigned-byte 8)))
             (position 0))
         (dolist (chunk chunks)
           (replace bytes chunk :start1 position)
           (incf position (length chunk)))
         bytes))))

(defun child-path (directory name)
  (if (equal (strip-slash directory) "/")
      (concatenate 'string "/" name)
      (concatenate 'string (strip-slash directory) "/" name)))

(defun utf8-bytes< (left right)
  (let ((a (utf8-bytes left))
        (b (utf8-bytes right)))
    (loop for index from 0
          do (cond
               ((and (>= index (length a)) (>= index (length b))) (return nil))
               ((>= index (length a)) (return t))
               ((>= index (length b)) (return nil))
               ((< (aref a index) (aref b index)) (return t))
               ((> (aref a index) (aref b index)) (return nil))))))

(defun remote-describe (path stat)
  (let ((kind (json-get stat "kind")))
    (when (or (not (stringp kind)) (equal kind "other"))
      (error 'remote-error :code "EINVAL" :message "Unsupported file type" :path path))
    (list :name (path-name path)
          :path path
          :kind kind
          :size (json-get stat "size")
          :mtime-ms (+ (* (let ((seconds (json-get stat "mtimeSec")))
                            (if (integerp seconds) seconds 0))
                          1000)
                       (/ (let ((nsec (json-get stat "mtimeNsec")))
                            (if (integerp nsec) nsec 0))
                          1000000.0)))))

(defun remember-running (env id session)
  (sb-thread:with-mutex ((remote-env-running-lock env))
    (setf (gethash id (remote-env-running env)) session)))

(defun forget-running (env id)
  (when id
    (sb-thread:with-mutex ((remote-env-running-lock env))
      (remhash id (remote-env-running env)))))

(defun remote-resolve (env path)
  (let* ((info (spawn-info (remote-env-connection env)))
         (home (json-get info "home")))
    (cond
      ((equal path "~") (posix-normalize home))
      ((and (>= (length path) 2) (char= (char path 0) #\~)
            (member (char path 1) '(#\/ #\\)))
       (posix-normalize (concatenate 'string (strip-slash home) (subseq path 1))))
      ((and (>= (length path) 7) (string= path "file://" :end1 7))
       (let ((file (file-url-path path)))
         (if file (posix-normalize file) path)))
      ((and (plusp (length path)) (char= (char path 0) #\/))
       (posix-normalize path))
      (t (posix-normalize (concatenate 'string (strip-slash (remote-env-cwd env)) "/" path))))))

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
  (let ((request (json-object "handle" handle "length" length)))
    (when (integerp offset)
      (json-put request "offset" offset))
    (multiple-value-bind (json payload)
        (spawn-request (remote-env-connection env) "pread" request :session session)
      (declare (ignore json))
      payload)))

(defun remote-read-until-end (env handle session)
  (let ((chunks nil)
        (total 0))
    (loop
      (let ((chunk (remote-pread env handle session nil +read-file-unknown-chunk+)))
        (when (zerop (length chunk))
          (return (concat-bytes (nreverse chunks) total)))
        (push chunk chunks)
        (incf total (length chunk))))))

(defun remote-read-bytes (env resolved)
  (multiple-value-bind (handle session stat) (remote-open-read env resolved)
    (unwind-protect
         (let ((size (if (and (json-object-p stat) (equal (json-get stat "kind") "file"))
                         (json-get stat "size")
                         0)))
           (cond
             ((and (integerp size) (> size +read-file-max+))
              (error 'remote-error :code "unknown"
                     :message (format nil "File size (~A) is greater than 2 GiB" size)
                     :path resolved))
             ((and (integerp size) (plusp size))
              (let ((bytes (make-array size :element-type '(unsigned-byte 8)))
                    (filled 0))
                (loop while (< filled size)
                      for chunk = (remote-pread env handle session filled
                                                (min +read-chunk+ (- size filled)))
                      do (when (zerop (length chunk)) (return))
                         (replace bytes chunk :start1 filled)
                         (incf filled (length chunk)))
                (if (= filled size) bytes (subseq bytes 0 filled))))
             (t (remote-read-until-end env handle session))))
      (ignore-errors
        (spawn-request (remote-env-connection env) "close"
                       (json-object "handle" handle)
                       :session session)))))

(defun remote-read-text-file (env path)
  (remote-catch path
    (lambda ()
      (utf8-decode (make-utf8-decoder)
                   (remote-read-bytes env (remote-resolve env path))
                   :last t))))

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

(defun safe-index-p (value)
  (and (integerp value) (<= 0 value +js-max-safe-integer+)))

(defun remote-reader-read (reader offset length)
  (cond
    ((remote-reader-closed reader)
     (make-env-err :code "invalid" :message "Binary reader is closed"
                   :path (remote-reader-path reader)))
    ((not (and (safe-index-p offset) (safe-index-p length)))
     (make-env-err :code "invalid"
                   :message "Offset and length must be non-negative safe integers"
                   :path (remote-reader-path reader)))
    (t
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
            (if (zerop (length bytes))
                (make-array 0 :element-type '(unsigned-byte 8))
                (coerce bytes '(vector (unsigned-byte 8))))))))))

(defun remote-reader-close (reader)
  (setf (remote-reader-closed reader) t)
  (ignore-errors
    (spawn-request (remote-env-connection (remote-reader-env reader)) "close"
                   (json-object "handle" (remote-reader-handle reader))
                   :session (remote-reader-session reader))))

(defun js-timeout-text (timeout)
  (cond
    ((integerp timeout) (princ-to-string timeout))
    ((and (realp timeout) (= timeout (round timeout)))
     (princ-to-string (round timeout)))
    (t (let ((text (princ-to-string timeout)))
         (if (and (>= (length text) 2)
                  (string-equal (subseq text (- (length text) 2)) "d0"))
             (subseq text 0 (- (length text) 2))
             text)))))

(defun remote-exec-fail (condition timeout)
  (let ((code (remote-error-code condition)))
    (make-env-err :code (cond ((equal code "timeout") "timeout")
                              ((equal code "aborted") "aborted")
                              ((or (equal code "spawn_error")
                                   (equal code "shell_unavailable")
                                   (equal code "callback_error"))
                               code)
                              (t "unknown"))
                  :message (if (equal code "timeout")
                               (format nil "timeout:~A" (js-timeout-text timeout))
                               (remote-error-message condition)))))

(defun output-info (json)
  (let ((info (json-object "stream" (if (equal (json-get json "stream") "stderr")
                                        "stderr" "stdout")))
        (skipped (json-get json "skipped")))
    (when (json-object-p skipped)
      (json-put info "skipped" skipped))
    info))

(defun remote-exec (env command &key on-output timeout abort window cwd)
  (when (env-abort-p abort)
    (return-from remote-exec (make-env-err :code "aborted" :message "aborted")))
  (when timeout
    (cond
      ((or (not (realp timeout))
           (and (floatp timeout)
                (or (sb-ext:float-nan-p timeout) (sb-ext:float-infinity-p timeout)))
           (<= timeout 0))
       (return-from remote-exec
         (make-env-err :code "timeout"
                       :message "Invalid timeout: must be a finite number of seconds")))
      ((> (* timeout 1000) +max-timeout-ms+)
       (return-from remote-exec
         (make-env-err :code "timeout"
                       :message "Invalid timeout: maximum is 2147483.647 seconds")))))
  (let ((callback-error nil)
        (running-id nil)
        (cell (or abort (make-env-abort))))
    (handler-case
        (let ((request (json-object "cwd" (if cwd (remote-resolve env cwd) (remote-env-cwd env))
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
          (unwind-protect
               (let ((reply (spawn-request (remote-env-connection env) "exec" request
                                           :abort cell
                                           :on-start (lambda (id session)
                                                       (setf running-id id)
                                                       (remember-running env id session))
                                           :on-event (lambda (json payload)
                                                       (when (and on-output
                                                                  (equal (json-get json "kind") "output")
                                                                  (not callback-error))
                                                         (let ((text (utf8-string payload)))
                                                           (unless (equal text "")
                                                             (handler-case
                                                                 (funcall on-output text (output-info json))
                                                               (error (condition)
                                                                 (setf callback-error condition)
                                                                 (env-abort cell))))))))))
                 (if callback-error
                     (make-env-err :code "callback_error"
                                   :message (princ-to-string callback-error))
                     (make-env-ok :value (json-get reply "exitCode"))))
            (forget-running env running-id)))
      (remote-error (condition)
        (if callback-error
            (make-env-err :code "callback_error" :message (princ-to-string callback-error))
            (remote-exec-fail condition timeout))))))

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

(defun remote-file-info (env path)
  (remote-catch path
    (lambda ()
      (let ((resolved (remote-resolve env path)))
        (remote-describe resolved
                         (spawn-request (remote-env-connection env) "lstat"
                                        (json-object "path" resolved)))))))

(defun remote-exists (env path)
  (let ((info (remote-file-info env path)))
    (cond ((env-ok-p info) (make-env-ok :value t))
          ((equal (env-err-code info) "not_found") (make-env-ok :value nil))
          (t info))))

(defun remote-create-dir (env path &key (recursive t))
  (remote-catch path
    (lambda ()
      (spawn-request (remote-env-connection env) "mkdir"
                     (json-object "path" (remote-resolve env path)
                                  "recursive" (and recursive t)))
      nil)))

(defun remote-remove (env path &key recursive force)
  (remote-catch path
    (lambda ()
      (spawn-request (remote-env-connection env) "rm"
                     (json-object "path" (remote-resolve env path)
                                  "recursive" (and recursive t)
                                  "force" (and force t)))
      nil)))

(defun remote-truncate-file (env path size)
  (remote-catch path
    (lambda ()
      (let ((resolved (remote-resolve env path)))
        (unless (safe-index-p size)
          (error 'remote-error :code "EINVAL"
                 :message "File size must be a non-negative safe integer"
                 :path resolved))
        (spawn-request (remote-env-connection env) "truncate"
                       (json-object "path" resolved "size" size))
        nil))))

(defun remote-flush-file (env path)
  (remote-catch path
    (lambda ()
      (spawn-request (remote-env-connection env) "fsync"
                     (json-object "path" (remote-resolve env path)))
      nil)))

(defun remote-rename-file (env source destination)
  (let (from to)
    (handler-case
        (setf from (remote-resolve env source)
              to (remote-resolve env destination))
      (error (condition)
        (return-from remote-rename-file
          (make-env-err :code "unknown" :message (princ-to-string condition) :path source))))
    (remote-catch from
      (lambda ()
        (spawn-request (remote-env-connection env) "rename"
                       (json-object "path" from "to" to))
        nil))))

(defun remote-canonical-path (env path)
  (remote-catch path
    (lambda ()
      (json-get (spawn-request (remote-env-connection env) "realpath"
                               (json-object "path" (remote-resolve env path)))
                "path"))))

(defun remote-absolute-path (env path)
  (handler-case
      (make-env-ok :value (remote-resolve env path))
    (error (condition)
      (make-env-err :code "unknown" :message (princ-to-string condition) :path path))))

(defun remote-join-path (env parts)
  (declare (ignore env))
  (handler-case
      (make-env-ok :value (posix-join parts))
    (error (condition)
      (make-env-err :code "unknown" :message (princ-to-string condition)))))

(defun remote-create-temp-dir (env &optional prefix)
  (remote-catch nil
    (lambda ()
      (let ((tmpdir (json-get (spawn-info (remote-env-connection env)) "tmpdir")))
        (json-get (spawn-request (remote-env-connection env) "mkdtemp"
                                 (json-object "path" (child-path tmpdir (or prefix "tmp-"))))
                  "path")))))

(defun remote-create-temp-file (env &key prefix suffix)
  (let ((dir (remote-create-temp-dir env "tmp-")))
    (unless (env-ok-p dir)
      (return-from remote-create-temp-file dir))
    (remote-catch (env-ok-value dir)
      (lambda ()
        (let ((path (child-path (env-ok-value dir)
                                (format nil "~A~8,'0X~A" (or prefix "")
                                        (random (expt 2 32)) (or suffix "")))))
          (spawn-request (remote-env-connection env) "write"
                         (json-object "path" path "append" nil "parents" nil)
                         :payload #())
          path)))))

(defun remote-cleanup (env)
  (let ((pairs nil))
    (sb-thread:with-mutex ((remote-env-running-lock env))
      (maphash (lambda (id session) (push (cons id session) pairs))
               (remote-env-running env))
      (clrhash (remote-env-running env)))
    (dolist (pair pairs)
      (spawn-kill (remote-env-connection env) (car pair) (cdr pair))))
  nil)

(defun entry-infos (directory entries &key skip-missing)
  (let ((infos nil))
    (loop for entry across entries
          for name = (json-get entry "name")
          for problem = (json-get entry "error")
          for full = (child-path directory name)
          do (cond
               ((and skip-missing (json-object-p problem)
                     (equal (json-get problem "code") "ENOENT"))
                nil)
               ((json-object-p problem)
                (error 'remote-error :code (json-get problem "code")
                       :message (json-get problem "message") :path full))
               (t (let ((info (json-get entry "info")))
                    (when (and (json-object-p info)
                               (not (equal (json-get info "kind") "other")))
                      (push (remote-describe full info) infos))))))
    (nreverse infos)))

(defun remote-list-dir (env path)
  (remote-catch path
    (lambda ()
      (let* ((resolved (remote-resolve env path))
             (opened (spawn-request (remote-env-connection env) "opendir"
                                    (json-object "path" resolved)))
             (handle (json-get opened "handle"))
             (session (spawn-session-id-of (remote-env-connection env)))
             (entries nil))
        (unwind-protect
             (loop
               (let ((page (spawn-request (remote-env-connection env) "readdir"
                                          (json-object "handle" handle "max" 1000)
                                          :session session)))
                 (setf entries (nconc entries (entry-infos resolved (json-get page "entries"))))
                 (when (eq (json-get page "done") t)
                   (return))))
          (ignore-errors
            (spawn-request (remote-env-connection env) "close"
                           (json-object "handle" handle) :session session)))
        (sort entries (lambda (left right) (utf8-bytes< (getf left :name) (getf right :name))))))))

(defun remote-open-dir-reader (env path)
  (remote-catch path
    (lambda ()
      (let* ((resolved (remote-resolve env path))
             (opened (spawn-request (remote-env-connection env) "opendir"
                                    (json-object "path" resolved))))
        (make-remote-dir-reader :env env
                                :handle (json-get opened "handle")
                                :session (spawn-session-id-of (remote-env-connection env))
                                :path resolved)))))

(defun remote-dir-close (reader)
  (unless (remote-dir-reader-closed reader)
    (setf (remote-dir-reader-closed reader) t)
    (ignore-errors
      (spawn-request (remote-env-connection (remote-dir-reader-env reader)) "close"
                     (json-object "handle" (remote-dir-reader-handle reader))
                     :session (remote-dir-reader-session reader)))))

(defun remote-dir-next (reader max-entries)
  (cond
    ((remote-dir-reader-closed reader)
     (make-env-err :code "invalid" :message "Directory reader is closed"
                   :path (remote-dir-reader-path reader)))
    ((not (and (integerp max-entries) (plusp max-entries)
               (<= max-entries +js-max-safe-integer+)))
     (make-env-err :code "invalid" :message "maxEntries must be a positive safe integer"
                   :path (remote-dir-reader-path reader)))
    (t
     (remote-catch (remote-dir-reader-path reader)
       (lambda ()
         (let ((collected nil))
           (loop while (and (not (remote-dir-reader-done reader))
                            (< (length collected) max-entries))
                 do (let ((page (spawn-request (remote-env-connection (remote-dir-reader-env reader))
                                               "readdir"
                                               (json-object "handle" (remote-dir-reader-handle reader)
                                                            "max" (- max-entries (length collected)))
                                               :session (remote-dir-reader-session reader))))
                      (setf collected (nconc collected
                                             (entry-infos (remote-dir-reader-path reader)
                                                          (json-get page "entries")
                                                          :skip-missing t))
                            (remote-dir-reader-done reader) (eq (json-get page "done") t))))
           (list :entries collected :done (remote-dir-reader-done reader))))))))

(defun remote-open-text-line-reader (env path)
  (remote-catch path
    (lambda ()
      (let* ((resolved (remote-resolve env path))
             (reply (spawn-request (remote-env-connection env) "open"
                                   (json-object "path" resolved "mode" "read"))))
        (make-remote-line-reader :env env
                                 :handle (json-get reply "handle")
                                 :session (spawn-session-id-of (remote-env-connection env))
                                 :path resolved)))))

(defun remote-line-close (reader)
  (unless (remote-line-reader-closed reader)
    (setf (remote-line-reader-closed reader) t
          (remote-line-reader-buffered reader) "")
    (ignore-errors
      (spawn-request (remote-env-connection (remote-line-reader-env reader)) "close"
                     (json-object "handle" (remote-line-reader-handle reader))
                     :session (remote-line-reader-session reader)))))

(defun remote-line-read (reader)
  (cond
    ((remote-line-reader-closed reader)
     (make-env-err :code "invalid" :message "Text line reader is closed"
                   :path (remote-line-reader-path reader)))
    (t
     (remote-catch (remote-line-reader-path reader)
       (lambda ()
         (loop
           (let* ((buffered (remote-line-reader-buffered reader))
                  (newline (position #\Newline buffered)))
             (when newline
               (setf (remote-line-reader-buffered reader) (subseq buffered (1+ newline)))
               (return (list :text (subseq buffered 0 newline) :terminated t))))
           (when (remote-line-reader-ended reader)
             (let ((buffered (remote-line-reader-buffered reader)))
               (setf (remote-line-reader-buffered reader) "")
               (return (if (equal buffered "")
                           nil
                           (list :text buffered :terminated nil)))))
           (let ((bytes (remote-pread (remote-line-reader-env reader)
                                      (remote-line-reader-handle reader)
                                      (remote-line-reader-session reader)
                                      (remote-line-reader-offset reader)
                                      +line-chunk+)))
             (incf (remote-line-reader-offset reader) (length bytes))
             (if (zerop (length bytes))
                 (setf (remote-line-reader-buffered reader)
                       (concatenate 'string (remote-line-reader-buffered reader)
                                    (utf8-decode (remote-line-reader-decoder reader) #() :last t))
                       (remote-line-reader-ended reader) t)
                 (setf (remote-line-reader-buffered reader)
                       (concatenate 'string (remote-line-reader-buffered reader)
                                    (utf8-decode (remote-line-reader-decoder reader) bytes)))))))))))

(defun remote-read-text-lines (env path &key max-lines)
  (when (and max-lines (<= max-lines 0))
    (return-from remote-read-text-lines (make-env-ok :value nil)))
  (let ((opened (remote-open-text-line-reader env path)))
    (unless (env-ok-p opened)
      (return-from remote-read-text-lines opened))
    (let ((reader (env-ok-value opened))
          (lines nil))
      (unwind-protect
           (loop
             (when (and max-lines (>= (length lines) max-lines))
               (return (make-env-ok :value (nreverse lines))))
             (let ((line (remote-line-read reader)))
               (cond
                 ((not (env-ok-p line)) (return line))
                 ((null (env-ok-value line)) (return (make-env-ok :value (nreverse lines))))
                 (t (push (getf (env-ok-value line) :text) lines)))))
        (remote-line-close reader)))))

(defun remote-reader-info (reader)
  (if (remote-reader-closed reader)
      (make-env-err :code "invalid" :message "Binary reader is closed"
                    :path (remote-reader-path reader))
      (remote-catch (remote-reader-path reader)
        (lambda ()
          (remote-describe (remote-reader-path reader)
                           (spawn-request (remote-env-connection (remote-reader-env reader))
                                          "fstat"
                                          (json-object "handle" (remote-reader-handle reader))
                                          :session (remote-reader-session reader)))))))

(defun remote-reader-scan-lines (reader &key (start-line 0) end-line)
  (cond
    ((remote-reader-closed reader)
     (make-env-err :code "invalid" :message "Binary reader is closed"
                   :path (remote-reader-path reader)))
    ((not (and (safe-index-p start-line)
               (or (null end-line) (and (safe-index-p end-line) (> end-line start-line)))))
     (make-env-err :code "invalid" :message "Invalid line range"
                   :path (remote-reader-path reader)))
    (t
     (remote-catch (remote-reader-path reader)
       (lambda ()
         (let ((request (json-object "handle" (remote-reader-handle reader)
                                     "startLine" start-line)))
           (when end-line (json-put request "endLine" end-line))
           (spawn-request (remote-env-connection (remote-reader-env reader))
                          "scanLines" request
                          :session (remote-reader-session reader))))))))

(defun watch-target-json (env target)
  (let ((object (json-object "path" (remote-resolve env (getf target :path))
                             "recursive" (and (getf target :recursive) t)))
        (exclude (getf target :exclude)))
    (when exclude
      (json-put object "exclude"
                (json-object "hidden" (and (getf exclude :hidden) t)
                             "names" (apply #'json-array (or (getf exclude :names) nil)))))
    object))

(defun remote-watch (env targets on-change &key mode poll-interval-ms abort)
  (when (env-abort-p abort)
    (return-from remote-watch (make-env-err :code "aborted" :message "aborted")))
  (let* ((request (json-object "targets" (apply #'json-array
                                                (mapcar (lambda (target)
                                                          (watch-target-json env target))
                                                        targets))))
         (cell (or abort (make-env-abort)))
         (ready nil)
         (failed nil)
         (lock (sb-thread:make-mutex :name "env-watch-ready"))
         (wait (sb-thread:make-waitqueue :name "env-watch-ready"))
         (watcher (make-remote-watcher :env env :abort cell :mode "native")))
    (when mode (json-put request "mode" mode))
    (when poll-interval-ms (json-put request "pollIntervalMs" poll-interval-ms))
    (setf (remote-watcher-thread watcher)
          (sb-thread:make-thread
           (lambda ()
             (handler-case
                 (spawn-request (remote-env-connection env) "watch" request
                                :abort cell
                                :on-event (lambda (json payload)
                                            (declare (ignore payload))
                                            (cond
                                              ((equal (json-get json "kind") "ready")
                                               (setf (remote-watcher-mode watcher)
                                                     (if (equal (json-get json "mode") "polling")
                                                         "polling" "native"))
                                               (sb-thread:with-mutex (lock)
                                                 (setf ready t)
                                                 (sb-thread:condition-broadcast wait)))
                                              ((and (equal (json-get json "kind") "change")
                                                    (not (remote-watcher-closed watcher))
                                                    on-change)
                                               (let ((paths (json-get json "paths")))
                                                 (funcall on-change
                                                          (if (eq (json-get json "overflow") t)
                                                              (list :overflow t)
                                                              (list :paths (if (json-array-p paths)
                                                                               (coerce paths 'list)
                                                                               nil)))))))))
               (error (condition)
                 (sb-thread:with-mutex (lock)
                   (setf failed condition)
                   (sb-thread:condition-broadcast wait)))))
           :name "env-remote-watch"))
    (sb-thread:with-mutex (lock)
      (loop with waited = nil
            until (or ready failed)
            do (when waited (return))
               (setf waited t)
               (sb-thread:condition-wait wait lock :timeout 10)))
    (cond
      (failed
       (env-abort cell)
       (cadr-core:join-active-thread (remote-watcher-thread watcher) :reason "env watch failed")
       (if (typep failed 'remote-error)
           (remote-fail failed nil)
           (make-env-err :code "unknown" :message (princ-to-string failed))))
      (ready (make-env-ok :value watcher))
      (t
       (env-abort cell)
       (cadr-core:join-active-thread (remote-watcher-thread watcher) :reason "env watch timeout")
       (make-env-err :code "unknown" :message "watch did not become ready")))))

(defun remote-watcher-close (watcher)
  (unless (remote-watcher-closed watcher)
    (setf (remote-watcher-closed watcher) t)
    (env-abort (remote-watcher-abort watcher))
    (when (remote-watcher-thread watcher)
      (cadr-core:join-active-thread (remote-watcher-thread watcher)
                                    :reason "env watch close"))))
