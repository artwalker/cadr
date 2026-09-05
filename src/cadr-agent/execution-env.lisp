(in-package #:cadr-agent)

(defclass execution-tool-context ()
  ((env :initarg :env :reader execution-tool-context-env)))

(defun make-execution-tool-context (&key env)
  (make-instance 'execution-tool-context
                 :env (or env (make-node-execution-env))))

(defgeneric execution-tool-resolve-path (context path &optional base-directory))
(defgeneric execution-tool-read-text (context path))
(defgeneric execution-tool-read-binary (context path))
(defgeneric execution-tool-write (context path content))
(defgeneric execution-tool-exec
    (context command &key cwd timeout signal on-stdout on-stderr))

(defmethod execution-tool-resolve-path
    ((context execution-tool-context) path &optional base-directory)
  (execution-env-absolute-path
   (execution-tool-context-env context)
   (if base-directory
       (execution-env-join-path
        (execution-tool-context-env context) base-directory path)
       path)))

(defmethod execution-tool-read-text ((context execution-tool-context) path)
  (execution-env-read-text-file (execution-tool-context-env context) path))

(defmethod execution-tool-read-binary ((context execution-tool-context) path)
  (execution-env-read-binary-file (execution-tool-context-env context) path))

(defmethod execution-tool-write ((context execution-tool-context) path content)
  (execution-env-write-file (execution-tool-context-env context) path content))

(defmethod execution-tool-exec
    ((context execution-tool-context) command
     &key cwd timeout signal on-stdout on-stderr)
  (execution-env-exec
   (execution-tool-context-env context) command
   :cwd cwd :timeout timeout :signal signal
   :on-stdout on-stdout :on-stderr on-stderr))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-posix))

(defstruct harness-operation-error
  code
  (message "" :type string)
  path
  cause)

(defstruct execution-file-info
  (name "" :type string)
  (path "" :type string)
  kind
  (size 0 :type (integer 0 *))
  (mtime-ms 0 :type integer))

(defstruct execution-result
  (stdout "" :type string)
  (stderr "" :type string)
  (exit-code 0 :type integer))

(defstruct (node-execution-env
            (:constructor %make-node-execution-env))
  (cwd "" :type string)
  shell-path
  shell-environment
  (active-processes
    (make-hash-table)
    :type hash-table)
  (lock
    (sb-thread:make-mutex
     :name "cadr-execution-environment")))

(defun make-node-execution-env
    (&key cwd shell-path shell-environment)
  (%make-node-execution-env
   :cwd
   (execution-normalize-path
    (or cwd (uiop:getcwd))
    (uiop:getcwd))
   :shell-path
   (and shell-path
        (execution-normalize-path
         shell-path
         (or cwd (uiop:getcwd))))
   :shell-environment shell-environment))

(defun execution-error
    (code message &key path cause)
  (make-harness-operation-error
   :code code
   :message message
   :path path
   :cause cause))

(defun execution-signal-aborted-p (signal)
  (and
   signal
   (typep signal 'extension-cancellation-signal)
   (extension-cancellation-aborted-p signal)))

(defun execution-aborted-error (signal &optional path)
  (when (execution-signal-aborted-p signal)
    (execution-error
     :aborted "aborted" :path path)))

(defun split-execution-path (path)
  (uiop:split-string path :separator '(#\/)))

(defun execution-posix-absolute-p (text)
  (and (plusp (length text))
       (char= (char text 0) #\/)))

(defun execution-join-parts (parts)
  (with-output-to-string (out)
    (loop for part in parts
          for first = t then nil
          do
          (unless first
            (write-char #\/ out))
          (write-string
           (if (stringp part)
               part
               (princ-to-string part))
           out))))

(defun execution-normalize-path (path cwd)
  (let* ((text
           (if (stringp path)
               path
               (princ-to-string path)))
         (expanded
           (cond
             ((string= text "~")
              (namestring
               (user-homedir-pathname)))
             ((uiop:string-prefix-p "~/" text)
              (concatenate
               'string
               (namestring
                (user-homedir-pathname))
               (subseq text 2)))
             ((uiop:string-prefix-p
               "file://" text)
              (subseq text 7))
             (t text)))
         (absolute
           (if (execution-posix-absolute-p expanded)
               expanded
               (concatenate
                'string
                (string-right-trim
                 "/" (namestring
                      (uiop:ensure-directory-pathname
                       cwd)))
                "/" expanded)))
         (stack nil))
    (dolist (part (split-execution-path absolute))
      (cond
        ((or (zerop (length part))
             (string= "." part)))
        ((string= ".." part)
         (when stack (pop stack)))
        (t (push part stack))))
    (if (null stack)
        "/"
        (with-output-to-string (out)
          (dolist (part (nreverse stack))
            (write-char #\/ out)
            (write-string part out))))))

(defun execution-env-absolute-path
    (environment path &key signal)
  (let ((error
          (execution-aborted-error
           signal path)))
    (if error
        (values nil error)
        (values
         (execution-normalize-path
          path
          (node-execution-env-cwd
           environment))
         nil))))

(defun execution-env-join-path
    (environment parts &key signal)
  (let ((error
          (execution-aborted-error signal)))
    (if error
        (values nil error)
        (values
         (execution-normalize-path
          (execution-join-parts parts)
          (node-execution-env-cwd
           environment))
         nil))))

(defun execution-path (environment path)
  (execution-normalize-path
   path
   (node-execution-env-cwd environment)))

(defun classify-file-error (cause path)
  (let ((message (princ-to-string cause)))
    (execution-error
     (cond
       ((search "No such file" message)
        :not-found)
       ((search "not a directory" message
                :test #'char-equal)
        :not-directory)
       ((search "Is a directory" message
                :test #'char-equal)
        :is-directory)
       ((or
         (search "Permission denied" message
                 :test #'char-equal)
         (search "Operation not permitted" message
                 :test #'char-equal))
        :permission-denied)
       (t :unknown))
     message :path path :cause cause)))

(defun call-signaled-operation
    (signal function &optional path)
  ;; Baseline packages/agent/src/harness/env/nodejs.ts abortResult
  ;; :123 then try / toFileError :97. Temps pass no path
  ;; (createTempDir :671).
  (let ((error
          (execution-aborted-error signal path)))
    (if error
        (values nil error)
        (handler-case
            (values (funcall function) nil)
          (error (cause)
            (values
             nil
             (if path
                 (classify-file-error cause path)
                 (execution-error
                  :unknown
                  (princ-to-string cause)
                  :cause cause))))))))

(defun call-file-operation
    (environment path signal function)
  (let ((absolute
          (execution-path environment path)))
    (call-signaled-operation
     signal
     (lambda ()
       (funcall function absolute))
     absolute)))

(defun execution-env-read-text-file
    (environment path &key signal)
  (call-file-operation
   environment path signal
   (lambda (absolute)
     (uiop:read-file-string
      absolute :external-format :utf-8))))

(defun execution-env-read-text-lines
    (environment path &key max-lines signal)
  (call-file-operation
   environment path signal
   (lambda (absolute)
     (with-open-file
         (stream absolute
                 :direction :input
                 :external-format :utf-8)
       (loop repeat
               (or max-lines
                   most-positive-fixnum)
             for line =
               (read-line stream nil nil)
             while line
             collect line)))))

(defun execution-env-read-binary-file
    (environment path &key signal)
  (call-file-operation
   environment path signal
   (lambda (absolute)
     (with-open-file
         (stream absolute
                 :direction :input
                 :element-type
                 '(unsigned-byte 8))
       (let ((content
               (make-array
                (file-length stream)
                :element-type
                '(unsigned-byte 8))))
         (read-sequence content stream)
         content)))))

(defun ensure-file-parent (path)
  (ensure-directories-exist
   (merge-pathnames
    "anchor"
    (uiop:pathname-directory-pathname
     (pathname path)))))

(defun write-execution-file
    (absolute content append-p)
  (ensure-file-parent absolute)
  (if (stringp content)
      (with-open-file
          (stream absolute
                  :direction :output
                  :if-exists
                  (if append-p
                      :append
                      :supersede)
                  :if-does-not-exist :create
                  :external-format :utf-8)
        (write-string content stream))
      (with-open-file
          (stream absolute
                  :direction :output
                  :if-exists
                  (if append-p
                      :append
                      :supersede)
                  :if-does-not-exist :create
                  :element-type
                  '(unsigned-byte 8))
        (write-sequence content stream)))
  nil)

(defun execution-env-write-file
    (environment path content &key signal)
  (call-file-operation
   environment path signal
   (lambda (absolute)
     (write-execution-file
      absolute content nil))))

(defun execution-env-append-file
    (environment path content &key signal)
  (call-file-operation
   environment path signal
   (lambda (absolute)
     (write-execution-file
      absolute content t))))

(defun stat-file-kind (stat)
  (cond
    ((sb-posix:s-isreg
      (sb-posix:stat-mode stat))
     :file)
    ((sb-posix:s-isdir
      (sb-posix:stat-mode stat))
     :directory)
    ((sb-posix:s-islnk
      (sb-posix:stat-mode stat))
     :symlink)
    (t :invalid)))

(defun file-name-from-path (path)
  (let ((trimmed
          (string-right-trim "/" path)))
    (subseq
     trimmed
     (1+
      (or
       (position #\/ trimmed
                 :from-end t)
       -1)))))

(defun execution-file-info-for-path (path)
  (let ((stat (sb-posix:lstat path)))
    (make-execution-file-info
     :name (file-name-from-path path)
     :path path
     :kind (stat-file-kind stat)
     :size (sb-posix:stat-size stat)
     :mtime-ms
     (* 1000
        (sb-posix:stat-mtime stat)))))

(defun execution-env-file-info
    (environment path &key signal)
  (call-file-operation
   environment path signal
   #'execution-file-info-for-path))

(defun execution-env-list-directory
    (environment path &key signal)
  (call-file-operation
   environment path signal
   (lambda (absolute)
     (unless (uiop:directory-exists-p
              absolute)
       (error "Not a directory: ~A"
              absolute))
     (mapcar
      (lambda (entry)
        (execution-file-info-for-path
         (string-right-trim
          "/" (namestring entry))))
      (let ((directory
              (uiop:ensure-directory-pathname
               absolute)))
        (append
         (uiop:directory-files directory)
         (uiop:subdirectories directory)))))))

(defun execution-env-canonical-path
    (environment path &key signal)
  (call-file-operation
   environment path signal
   (lambda (absolute)
     (namestring (truename absolute)))))

(defun execution-env-exists-p
    (environment path &key signal)
  ;; Baseline nodejs.ts:644-648. Not-found is success=false.
  ;; Abort/classify stay in call-file-operation.
  (multiple-value-bind (value error)
      (call-file-operation
       environment path signal
       (lambda (absolute)
         (sb-posix:lstat absolute)
         t))
    (if (and error
             (eq :not-found
                 (harness-operation-error-code error)))
        (values nil nil)
        (values value error))))

(defun execution-env-create-directory
    (environment path
     &key (recursive-p t) signal)
  (call-file-operation
   environment path signal
   (lambda (absolute)
     (if recursive-p
         (ensure-directories-exist
          (merge-pathnames
           "anchor"
           (uiop:ensure-directory-pathname
            absolute)))
         (sb-posix:mkdir absolute #o755))
     nil)))

(defun execution-env-remove
    (environment path
     &key recursive-p force-p signal)
  ;; Baseline nodejs.ts:661-668 rm + toFileError. Abort/classify
  ;; live in call-file-operation; only the rm policy stays here.
  (call-file-operation
   environment path signal
   (lambda (absolute)
     (cond
       ((uiop:directory-exists-p absolute)
        (if recursive-p
            (uiop:delete-directory-tree
             (uiop:ensure-directory-pathname absolute)
             :validate t
             :if-does-not-exist
             (if force-p :ignore :error))
            (sb-posix:rmdir absolute)))
       ((probe-file absolute)
        (delete-file absolute))
       ((not force-p)
        (error "No such file: ~A" absolute)))
     nil)))

(defun unique-execution-temp-path
    (prefix suffix directory-p)
  (loop repeat 1000
        for path =
          (merge-pathnames
           (format nil "~A~36R~A"
                   prefix
                   (random
                    most-positive-fixnum)
                   suffix)
           (uiop:temporary-directory))
        unless (probe-file path)
          do
          (if directory-p
              (ensure-directories-exist
               (merge-pathnames
                "anchor"
                (uiop:ensure-directory-pathname
                 path)))
              (with-open-file
                  (stream path
                          :direction :output
                          :if-exists :error
                          :if-does-not-exist
                          :create)
                (values)))
          (return
            (namestring
             (if directory-p
                 (uiop:ensure-directory-pathname
                  path)
                 path)))
        finally
          (error
           "Cannot allocate temporary path")))

(defun execution-env-create-temp-directory
    (environment &key (prefix "tmp-") signal)
  (declare (ignore environment))
  ;; Baseline nodejs.ts:671-676 mkdtemp + toFileError, no path.
  (call-signaled-operation
   signal
   (lambda ()
     (unique-execution-temp-path prefix "" t))))

(defun execution-env-create-temp-file
    (environment
     &key (prefix "") (suffix "") signal)
  (declare (ignore environment))
  ;; Baseline nodejs.ts:679-688. Lisp picks a unique path instead
  ;; of mkdtemp+uuid; abort/classify stay in call-signaled-operation.
  (call-signaled-operation
   signal
   (lambda ()
     (unique-execution-temp-path prefix suffix nil))))

(defun environment-alist ()
  (loop for entry in (sb-ext:posix-environ)
        for separator = (position #\= entry)
        when separator
          collect
          (cons
           (subseq entry 0 separator)
           (subseq entry (1+ separator)))))

(defun merge-execution-environment
    (environment extra inherit-p)
  (let ((result
          (if inherit-p
              (environment-alist)
              nil)))
    (dolist
        (layer
         (if inherit-p
             (list
              (node-execution-env-shell-environment
               environment)
              extra)
             (list extra)))
      (dolist (pair layer)
        (setf
         (cdr
          (or
           (assoc (car pair) result
                  :test #'string=)
           (let ((new (cons (car pair) "")))
             (push new result)
             new)))
         (cdr pair))))
    (mapcar
     (lambda (pair)
       (format nil "~A=~A"
               (car pair) (cdr pair)))
     result)))

(defun terminate-execution-process-group (pid)
  (dolist (signal '("-TERM" "-KILL"))
    (ignore-errors
      (uiop:run-program
       (list
        "/bin/kill" signal "--"
        (format nil "-~D" pid))
       :ignore-error-status t
       :output nil
       :error-output nil))
    (when (string= signal "-TERM")
      (sleep 0.05))))

(defun execution-group-path ()
  (loop repeat 1000
        for path =
          (merge-pathnames
           (format nil "cadr-exec-~36R.pgid"
                   (random
                    most-positive-fixnum))
           (uiop:temporary-directory))
        unless (probe-file path)
          return path
        finally
          (error
           "Cannot allocate execution group file")))

(defun read-execution-group-id (path)
  (loop repeat 100
        when (probe-file path)
          do
          (let ((text
                  (ignore-errors
                    (uiop:read-file-string
                     path))))
            (when
                (and text
                     (plusp (length text)))
              (return
                (parse-integer
                 text :junk-allowed t))))
        do (sleep 0.01)
        finally
          (error
           "Execution process group did not initialize")))

(defun read-execution-stream
    (stream callback capture error-place)
  (lambda ()
    (handler-case
        (loop for character =
                (read-char stream nil :eof)
              until (eq character :eof)
              do
          (write-char character capture)
          (when callback
            (funcall callback
                     (string character))))
      (error (cause)
        (setf (symbol-value error-place)
              cause)))))

(defun execution-wrapper-argv
    (group-path shell command)
  (list
   "/bin/sh" "-c"
   "exec /usr/bin/setsid --fork --wait /bin/sh -c 'printf %s \"$$\" > \"$1\"; exec \"$2\" -lc \"$3\" 2>&3' cadr-exec-wrapper \"$1\" \"$2\" \"$3\" 3>&2 2>/dev/null"
   "cadr-setsid-wrapper"
   (namestring group-path)
   shell command))

(defun execution-env-exec
    (execution-environment command
     &key cwd environment
       (inherit-environment-p t)
       timeout signal
       on-stdout on-stderr)
  (let* ((shell
           (or
            (node-execution-env-shell-path
             execution-environment)
            "/bin/bash")))
    (when (execution-signal-aborted-p signal)
      (return-from execution-env-exec
        (values
         nil
         (execution-error
          :aborted "aborted"))))
    (when (and timeout
               (or
                (not (realp timeout))
                (<= timeout 0)))
      (return-from execution-env-exec
        (values
         nil
         (execution-error
          :timeout
          "Invalid timeout: must be a positive number of seconds"))))
    (unless (probe-file shell)
      (return-from execution-env-exec
        (values
         nil
         (execution-error
          :shell-unavailable
          (format nil
                  "Custom shell path not found: ~A"
                  shell)))))
    (let ((working-directory
            (execution-normalize-path
             (or cwd
                 (node-execution-env-cwd
                  execution-environment))
             (node-execution-env-cwd
              execution-environment))))
      (unless
          (uiop:directory-exists-p
           working-directory)
        (return-from execution-env-exec
          (values
           nil
           (execution-error
            :spawn-error
            (format nil
                    "Working directory does not exist: ~A"
                    working-directory)))))
      (let* ((group-path
               (execution-group-path))
             (process
               (handler-case
                   (uiop:launch-program
                    (execution-wrapper-argv
                     group-path shell command)
                    :directory working-directory
                    :environment
                    (merge-execution-environment
                     execution-environment
                     environment
                     inherit-environment-p)
                    :input nil
                    :output :stream
                    :error-output :stream
                    :wait nil)
                 (error (cause)
                   (return-from execution-env-exec
                     (values
                      nil
                      (execution-error
                       :spawn-error
                       (princ-to-string cause)
                       :cause cause))))))
             (group-id
               (read-execution-group-id
                group-path))
             (stdout
               (make-string-output-stream))
             (stderr
               (make-string-output-stream))
             (stdout-error-symbol
               (gensym "STDOUT-ERROR"))
             (stderr-error-symbol
               (gensym "STDERR-ERROR"))
             (deadline
               (and timeout
                    (+ (get-internal-real-time)
                       (round
                        (* timeout
                           internal-time-units-per-second)))))
             (timed-out-p nil)
             (aborted-p nil))
        (set stdout-error-symbol nil)
        (set stderr-error-symbol nil)
        (sb-thread:with-mutex
            ((node-execution-env-lock
              execution-environment))
          (setf
           (gethash
            group-id
            (node-execution-env-active-processes
             execution-environment))
           t))
        (let ((stdout-thread
                (sb-thread:make-thread
                 (read-execution-stream
                  (uiop:process-info-output
                   process)
                  on-stdout stdout
                  stdout-error-symbol)
                 :name "cadr-exec-stdout"))
              (stderr-thread
                (sb-thread:make-thread
                 (read-execution-stream
                  (uiop:process-info-error-output
                   process)
                  on-stderr stderr
                  stderr-error-symbol)
                 :name "cadr-exec-stderr")))
          (unwind-protect
               (progn
                 (loop while
                         (uiop:process-alive-p
                          process)
                       do
                   (cond
                     ((execution-signal-aborted-p
                       signal)
                      (setf aborted-p t)
                      (terminate-execution-process-group
                       group-id)
                      (return))
                     ((and deadline
                           (>=
                            (get-internal-real-time)
                            deadline))
                      (setf timed-out-p t)
                      (terminate-execution-process-group
                       group-id)
                      (return))
                     ((or
                       (symbol-value
                        stdout-error-symbol)
                       (symbol-value
                        stderr-error-symbol))
                      (terminate-execution-process-group
                       group-id)
                      (return)))
                   (sleep 0.01))
                 (let ((exit-code
                         (or
                          (uiop:wait-process
                           process)
                          128)))
                   (cadr-core:stop-thread-for-cleanup
                    stdout-thread)
                   (cadr-core:stop-thread-for-cleanup
                    stderr-thread)
                   (cond
                     (aborted-p
                      (values
                       nil
                       (execution-error
                        :aborted "aborted")))
                     (timed-out-p
                      (values
                       nil
                       (execution-error
                        :timeout
                        (format nil
                                "Command timed out after ~A seconds"
                                timeout))))
                     ((or
                       (symbol-value
                        stdout-error-symbol)
                       (symbol-value
                        stderr-error-symbol))
                      (let ((cause
                              (or
                               (symbol-value
                                stdout-error-symbol)
                               (symbol-value
                                stderr-error-symbol))))
                        (values
                         nil
                         (execution-error
                          :callback-error
                          (princ-to-string
                           cause)
                          :cause cause))))
                     (t
                      (values
                       (make-execution-result
                        :stdout
                        (get-output-stream-string
                         stdout)
                        :stderr
                        (get-output-stream-string
                         stderr)
                        :exit-code exit-code)
                       nil)))))
            (when
                (uiop:process-alive-p
                 process)
              (terminate-execution-process-group
               group-id))
            (sb-thread:with-mutex
                ((node-execution-env-lock
                  execution-environment))
              (remhash
               group-id
               (node-execution-env-active-processes
                execution-environment)))
            (when (probe-file group-path)
              (delete-file group-path))))))))

(defun execution-env-cleanup (environment)
  (let ((pids nil))
    (sb-thread:with-mutex
        ((node-execution-env-lock environment))
      (maphash
       (lambda (pid present-p)
         (declare (ignore present-p))
         (push pid pids))
       (node-execution-env-active-processes
        environment))
      (clrhash
       (node-execution-env-active-processes
        environment)))
    (dolist (pid pids)
      (terminate-execution-process-group
       pid)))
  nil)
