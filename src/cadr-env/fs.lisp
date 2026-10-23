(in-package #:cadr-env)

(defconstant +scan-chunk+ 65536)
(defconstant +max-handles+ 4096)

(sb-alien:define-alien-routine ("pread" %pread) sb-alien:long
  (fd sb-alien:int)
  (buffer (* (sb-alien:unsigned 8)))
  (count sb-alien:unsigned-long)
  (offset sb-alien:long))

(sb-alien:define-alien-routine ("statx" %statx) sb-alien:int
  (dirfd sb-alien:int)
  (path sb-alien:c-string)
  (flags sb-alien:int)
  (mask sb-alien:unsigned-int)
  (buffer (* (sb-alien:unsigned 8))))

(defstruct server
  (handles (make-hash-table :test #'eql))
  (next-handle 0)
  (controls (make-hash-table :test #'eql))
  (groups (make-hash-table :test #'eql))
  (terminals (make-hash-table :test #'eql))
  (output-lock (sb-thread:make-mutex :name "env-output"))
  (last-input (get-internal-real-time))
  (closed nil)
  stream)

(defstruct file-handle
  id kind fd entries index path)

(defun host-separator ()
  "/")

(defun strip-slash (path)
  (if (and (> (length path) 1) (char= (char path (1- (length path))) #\/))
      (subseq path 0 (1- (length path)))
      path))

(defun host-tmpdir ()
  (strip-slash (or (sb-ext:posix-getenv "TMPDIR")
                   (sb-ext:posix-getenv "TMP")
                   (sb-ext:posix-getenv "TEMP")
                   "/tmp")))

(defun parent-directory (path)
  (let ((slash (position #\/ path :from-end t)))
    (cond ((null slash) nil)
          ((zerop slash) "/")
          (t (subseq path 0 slash)))))

(defun path-name (path)
  (let ((slash (position #\/ path :from-end t)))
    (if slash (subseq path (1+ slash)) path)))

(defun file-kind (mode)
  (let ((type (logand mode #o170000)))
    (cond ((= type #o100000) "file")
          ((= type #o040000) "directory")
          ((= type #o120000) "symlink")
          (t "other"))))

(defun mtime-nsec (path)
  (let ((buffer (make-array 256 :element-type '(unsigned-byte 8) :initial-element 0)))
    (if (zerop (%statx -100 path #x100 #x7ff (sb-sys:vector-sap buffer)))
        (let ((offset 136))
          (logior (aref buffer offset)
                  (ash (aref buffer (+ offset 1)) 8)
                  (ash (aref buffer (+ offset 2)) 16)
                  (ash (aref buffer (+ offset 3)) 24)))
        0)))

(defun info-from-stat (path stat)
  (json-object "name" (path-name path)
               "kind" (file-kind (sb-posix:stat-mode stat))
               "size" (sb-posix:stat-size stat)
               "mtimeSec" (sb-posix:stat-mtime stat)
               "mtimeNsec" (mtime-nsec path)
               "dev" (sb-posix:stat-dev stat)
               "ino" (sb-posix:stat-ino stat)))

(defun lstat-info (path)
  (info-from-stat path (call-posix "lstat" path (lambda () (sb-posix:lstat path)))))

(defun op-lstat (request)
  (lstat-info (require-string request "path")))

(defun op-realpath (request)
  (let ((path (require-string request "path")))
    (handler-case
        (json-object "path" (namestring (truename path)))
      (file-error ()
        (io-failure sb-posix:enoent "realpath" path)))))

(defun ensure-parents (path)
  (let ((parent (parent-directory path)))
    (when (and parent (not (equal parent "/")))
      (mkdir-recursive parent))))

(defun write-octets (path payload append)
  (call-posix "open" path
              (lambda ()
                (with-open-file (stream path :direction :output
                                        :element-type '(unsigned-byte 8)
                                        :if-exists (if append :append :supersede)
                                        :if-does-not-exist :create)
                  (write-sequence payload stream)))))

(defun op-write (request payload handles)
  (let* ((path (require-string request "path"))
         (append (json-flag request "append"))
         (parents (json-flag request "parents" t))
         (keep (json-flag request "keep")))
    (when parents (ensure-parents path))
    (write-octets path payload append)
    (if keep
        (let ((fd (call-posix "open" path
                              (lambda ()
                                (sb-posix:open path
                                               (logior sb-posix:o-wronly
                                                       sb-posix:o-append)
                                               #o666)))))
          (json-object "handle" (register-handle handles :chunk fd path)))
        (empty-json))))

(defun op-write-chunk (request payload handles)
  (let* ((id (require-u64 request "handle"))
         (handle (lookup-handle handles id)))
    (unless (eq (file-handle-kind handle) :chunk)
      (env-failure "EBADF" "EBADF: bad file descriptor"))
    (handler-case
        (progn
          (sb-sys:with-pinned-objects (payload)
            (sb-posix:write (file-handle-fd handle) (sb-sys:vector-sap payload)
                            (length payload)))
          (empty-json))
      (sb-posix:syscall-error (condition)
        (setf (file-handle-kind handle) :dead)
        (io-failure (sb-posix:syscall-errno condition) "write"
                    (file-handle-path handle))))))

(defun op-truncate (request)
  (let ((path (require-string request "path"))
        (size (require-u64 request "size")))
    (call-posix "truncate" path (lambda () (sb-posix:truncate path size)))
    (empty-json)))

(defun op-fsync (request)
  (let* ((path (require-string request "path"))
         (stat (call-posix "lstat" path (lambda () (sb-posix:lstat path)))))
    (when (= (logand (sb-posix:stat-mode stat) #o170000) #o040000)
      (env-failure "EISDIR"
                   (format nil "EISDIR: illegal operation on a directory, open '~A'" path)
                   :syscall "open" :path path))
    (let ((fd (call-posix "open" path (lambda () (sb-posix:open path sb-posix:o-rdonly 0)))))
      (unwind-protect
           (call-posix "fsync" path (lambda () (sb-posix:fsync fd)))
        (ignore-errors (sb-posix:close fd))))
    (empty-json)))

(defun op-rename (request)
  (let ((from (require-string request "from"))
        (to (require-string request "to")))
    (call-posix "rename" from (lambda () (sb-posix:rename from to)) to)
    (empty-json)))

(defun mkdir-one (path)
  (handler-case
      (sb-posix:mkdir path #o777)
    (sb-posix:syscall-error (condition)
      (let ((errno (sb-posix:syscall-errno condition)))
        (cond
          ((eql errno sb-posix:eexist)
           (handler-case
               (let ((stat (sb-posix:lstat path)))
                 (if (= (logand (sb-posix:stat-mode stat) #o170000) #o040000)
                     nil
                     (io-failure sb-posix:eexist "mkdir" path)))
             (sb-posix:syscall-error ()
               (io-failure errno "mkdir" path))))
          (t (io-failure errno "mkdir" path)))))))

(defun mkdir-recursive (path)
  (when (or (null path) (equal path "") (equal path "/"))
    (return-from mkdir-recursive nil))
  (let ((parent (parent-directory path)))
    (when parent
      (handler-case (sb-posix:lstat parent)
        (sb-posix:syscall-error (condition)
          (when (eql (sb-posix:syscall-errno condition) sb-posix:enoent)
            (mkdir-recursive parent))))))
  (mkdir-one path))

(defun op-mkdir (request)
  (mkdir-recursive (require-string request "path"))
  (empty-json))

(defun remove-tree (path force)
  (handler-case
      (let* ((stat (sb-posix:lstat path))
             (kind (logand (sb-posix:stat-mode stat) #o170000)))
        (cond
          ((= kind #o120000)
           (sb-posix:unlink path))
          ((= kind #o040000)
           (env-failure "ERR_FS_EISDIR"
                        (format nil "Path is a directory: rm returned EISDIR (is a directory) ~A" path)
                        :path path))
          (t (sb-posix:unlink path))))
    (sb-posix:syscall-error (condition)
      (if (and force (eql (sb-posix:syscall-errno condition) sb-posix:enoent))
          nil
          (io-failure (sb-posix:syscall-errno condition) "unlink" path)))))

(defun remove-recursive (path force)
  (handler-case
      (let* ((stat (sb-posix:lstat path))
             (kind (logand (sb-posix:stat-mode stat) #o170000)))
        (cond
          ((= kind #o120000) (sb-posix:unlink path))
          ((= kind #o040000)
           (dolist (entry (directory-entries path))
             (remove-recursive (concatenate 'string (strip-slash path) "/" entry) force))
           (handler-case (sb-posix:rmdir path)
             (sb-posix:syscall-error (condition)
               (io-failure (sb-posix:syscall-errno condition) "rmdir" path))))
          (t (sb-posix:unlink path))))
    (sb-posix:syscall-error (condition)
      (if (and force (eql (sb-posix:syscall-errno condition) sb-posix:enoent))
          nil
          (io-failure (sb-posix:syscall-errno condition) "unlink" path)))))

(defun op-rm (request)
  (let ((path (require-string request "path"))
        (recursive (json-flag request "recursive"))
        (force (json-flag request "force")))
    (if recursive
        (remove-recursive path force)
        (remove-tree path force))
    (empty-json)))

(defun random-temp-char ()
  (let ((alphabet "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"))
    (char alphabet (random (length alphabet)))))

(defun op-mkdtemp (request)
  (let ((prefix (require-string request "prefix")))
    (loop for attempt from 1 to 128
          do (let ((path (concatenate 'string prefix
                                      (with-output-to-string (stream)
                                        (dotimes (i 6)
                                          (write-char (random-temp-char) stream))))))
               (handler-case
                   (progn
                     (sb-posix:mkdir path #o700)
                     (return-from op-mkdtemp (json-object "path" path)))
                 (sb-posix:syscall-error (condition)
                   (unless (eql (sb-posix:syscall-errno condition) sb-posix:eexist)
                     (io-failure (sb-posix:syscall-errno condition) "mkdir"
                                 (concatenate 'string prefix "XXXXXX")))))))
    (env-failure "EEXIST" "mkdtemp failed")))

(defun directory-entries (path)
  (let ((dir (call-posix "opendir" path (lambda () (sb-posix:opendir path))))
        (names nil))
    (unwind-protect
         (loop for entry = (sb-posix:readdir dir)
               until (sb-alien:null-alien entry)
               do (let ((name (sb-posix:dirent-name entry)))
                    (unless (or (equal name ".") (equal name ".."))
                      (push name names))))
      (sb-posix:closedir dir))
    (nreverse names)))

(defun register-handle (handles kind fd path &optional entries)
  (when (>= (hash-table-count (server-handles handles)) +max-handles+)
    (env-failure "EMFILE" "EMFILE: too many open files"))
  (let* ((id (incf (server-next-handle handles)))
         (handle (make-file-handle :id id :kind kind :fd fd :path path
                                   :entries entries :index 0)))
    (setf (gethash id (server-handles handles)) handle)
    id))

(defun lookup-handle (handles id)
  (or (gethash id (server-handles handles))
      (env-failure "EBADF" "EBADF: bad file descriptor")))

(defun close-handle (handle)
  (when (and (file-handle-fd handle) (not (eq (file-handle-kind handle) :dir)))
    (ignore-errors (sb-posix:close (file-handle-fd handle))))
  (setf (file-handle-kind handle) :closed
        (file-handle-fd handle) nil))

(defun op-close (request handles)
  (let ((handle (lookup-handle handles (require-u64 request "handle"))))
    (close-handle handle)
    (remhash (file-handle-id handle) (server-handles handles))
    (empty-json)))

(defun open-read-handle (path handles)
  (let* ((fd (call-posix "open" path (lambda () (sb-posix:open path sb-posix:o-rdonly 0))))
         (stat (handler-case (sb-posix:fstat fd)
                 (sb-posix:syscall-error (condition)
                   (sb-posix:close fd)
                   (io-failure (sb-posix:syscall-errno condition) "fstat" path)))))
    (json-object "handle" (register-handle handles :read fd path)
                 "stat" (info-from-stat path stat))))

(defun open-binary-handle (path handles nofollow)
  (let ((stat (call-posix "lstat" path (lambda () (sb-posix:lstat path)))))
    (when (and nofollow (= (logand (sb-posix:stat-mode stat) #o170000) #o120000))
      (env-failure "SYMLINK" "Refusing to follow a symbolic link" :path path))
    (let ((kind (logand (sb-posix:stat-mode stat) #o170000)))
      (cond
        ((= kind #o040000)
         (env-failure "EISDIR"
                      (format nil "EISDIR: illegal operation on a directory, open '~A'" path)
                      :syscall "open" :path path))
        ((/= kind #o100000)
         (env-failure "NOT_REGULAR" "not a regular file" :path path))))
    (let ((fd (call-posix "open" path
                          (lambda ()
                            (sb-posix:open path
                                           (logior sb-posix:o-rdonly sb-posix:o-nonblock)
                                           0)))))
      (json-object "handle" (register-handle handles :binary fd path)))))

(defun op-open (request handles)
  (let ((path (require-string request "path"))
        (mode (json-string request "mode"))
        (nofollow (json-flag request "noFollow")))
    (if (equal mode "read")
        (open-read-handle path handles)
        (open-binary-handle path handles nofollow))))

(defun read-fd (fd count)
  (let ((buffer (make-array count :element-type '(unsigned-byte 8))))
    (handler-case
        (let ((read (sb-sys:with-pinned-objects (buffer)
                      (sb-posix:read fd (sb-sys:vector-sap buffer) (length buffer)))))
          (subseq buffer 0 (max read 0)))
      (sb-posix:syscall-error (condition)
        (io-failure (sb-posix:syscall-errno condition) "read" "")))))

(defun pread-fd (fd offset count)
  (let ((buffer (make-array count :element-type '(unsigned-byte 8))))
    (let ((read (%pread fd (sb-sys:vector-sap buffer) count offset)))
      (when (< read 0)
        (env-failure "EIO" "pread failed"))
      (subseq buffer 0 read))))

(defun op-pread (request handles)
  (let* ((handle (lookup-handle handles (require-u64 request "handle")))
         (length (or (json-u64 request "length") 65536))
         (offset (json-get request "offset"))
         (fd (file-handle-fd handle)))
    (unless fd (env-failure "EBADF" "EBADF: bad file descriptor"))
    (values (empty-json)
            (if (and (integerp offset) (>= offset 0))
                (pread-fd fd offset length)
                (read-fd fd length)))))

(defun op-fstat (request handles)
  (let* ((handle (lookup-handle handles (require-u64 request "handle")))
         (fd (file-handle-fd handle)))
    (unless fd (env-failure "EBADF" "EBADF: bad file descriptor"))
    (info-from-stat (file-handle-path handle)
                    (call-posix "fstat" (file-handle-path handle)
                                (lambda () (sb-posix:fstat fd))))))

(defun op-scan-lines (request handles aborted)
  (let* ((handle (lookup-handle handles (require-u64 request "handle")))
         (start (require-u64 request "startLine"))
         (end (json-u64 request "endLine"))
         (fd (file-handle-fd handle)))
    (when (and end (<= end start))
      (env-failure "EINVAL" "Invalid line range"))
    (unless fd (env-failure "EBADF" "EBADF: bad file descriptor"))
    (let ((scanner (make-line-scan start end)))
      (loop
        (when (and aborted (funcall aborted))
          (env-failure "aborted" "aborted"))
        (let ((chunk (read-fd fd +scan-chunk+)))
          (when (zerop (length chunk))
            (return (line-scan-finish scanner)))
          (line-scan-push scanner chunk))))))

(defun op-opendir (request handles)
  (let* ((path (require-string request "path"))
         (entries (directory-entries path)))
    (json-object "handle" (register-handle handles :dir nil path
                                           (coerce entries 'vector)))))

(defun entry-record (directory name)
  (let ((full (concatenate 'string (strip-slash directory) "/" name)))
    (handler-case
        (json-object "name" name "info" (lstat-info full))
      (env-failure (condition)
        (json-object "name" name
                     "error" (json-object "code" (env-failure-code condition)
                                          "message" (env-failure-message condition)))))))

(defun op-readdir (request handles)
  (let* ((handle (lookup-handle handles (require-u64 request "handle")))
         (max (or (json-u64 request "max") 256))
         (entries (file-handle-entries handle))
         (index (file-handle-index handle))
         (end (min (length entries) (+ index max)))
         (page (json-array)))
    (unless (eq (file-handle-kind handle) :dir)
      (env-failure "EBADF" "EBADF: bad file descriptor"))
    (loop for cursor from index below end
          do (json-push page (entry-record (file-handle-path handle)
                                           (aref entries cursor))))
    (setf (file-handle-index handle) end)
    (json-object "entries" page "done" (>= end (length entries)))))

(defun close-all-handles (handles)
  (maphash (lambda (id handle)
             (declare (ignore id))
             (close-handle handle))
           (server-handles handles))
  (clrhash (server-handles handles)))
