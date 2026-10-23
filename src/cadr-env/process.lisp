(in-package #:cadr-env)

(defconstant +spawn-setsigdef+ #x04)
(defconstant +spawn-setsigmask+ #x08)
(defconstant +spawn-setsid+ #x80)

(sb-alien:define-alien-routine ("posix_spawn" %posix-spawn) sb-alien:int
  (pid sb-alien:system-area-pointer)
  (file sb-alien:c-string)
  (actions sb-alien:system-area-pointer)
  (attributes sb-alien:system-area-pointer)
  (argv (* (* char)))
  (envp (* (* char))))

(sb-alien:define-alien-routine ("posix_spawn_file_actions_init" %actions-init) sb-alien:int
  (actions sb-alien:system-area-pointer))

(sb-alien:define-alien-routine ("posix_spawn_file_actions_destroy" %actions-destroy) sb-alien:int
  (actions sb-alien:system-area-pointer))

(sb-alien:define-alien-routine ("posix_spawn_file_actions_adddup2" %actions-dup2) sb-alien:int
  (actions sb-alien:system-area-pointer)
  (old sb-alien:int)
  (new sb-alien:int))

(sb-alien:define-alien-routine ("posix_spawn_file_actions_addclose" %actions-close) sb-alien:int
  (actions sb-alien:system-area-pointer)
  (fd sb-alien:int))

(sb-alien:define-alien-routine ("posix_spawn_file_actions_addopen" %actions-open) sb-alien:int
  (actions sb-alien:system-area-pointer)
  (fd sb-alien:int)
  (path sb-alien:c-string)
  (flags sb-alien:int)
  (mode sb-alien:int))

(sb-alien:define-alien-routine ("posix_spawn_file_actions_addchdir_np" %actions-chdir) sb-alien:int
  (actions sb-alien:system-area-pointer)
  (path sb-alien:c-string))

(sb-alien:define-alien-routine ("posix_spawnattr_init" %attr-init) sb-alien:int
  (attributes sb-alien:system-area-pointer))

(sb-alien:define-alien-routine ("posix_spawnattr_destroy" %attr-destroy) sb-alien:int
  (attributes sb-alien:system-area-pointer))

(sb-alien:define-alien-routine ("posix_spawnattr_setflags" %attr-flags) sb-alien:int
  (attributes sb-alien:system-area-pointer)
  (flags sb-alien:short))

(sb-alien:define-alien-routine ("posix_spawnattr_setsigmask" %attr-mask) sb-alien:int
  (attributes sb-alien:system-area-pointer)
  (mask sb-alien:system-area-pointer))

(sb-alien:define-alien-routine ("posix_spawnattr_setsigdefault" %attr-default) sb-alien:int
  (attributes sb-alien:system-area-pointer)
  (mask sb-alien:system-area-pointer))

(sb-alien:define-alien-routine ("close" %c-close) sb-alien:int
  (fd sb-alien:int))

(defstruct control
  (aborted nil)
  (killed nil))

(defun control-cancel (control kill)
  (if kill
      (setf (control-killed control) t)
      (setf (control-aborted control) t))
  (sb-thread:barrier (:write)))

(defun control-aborted-p (control)
  (sb-thread:barrier (:read))
  (and control (control-aborted control)))

(defun c-string (text)
  (let* ((octets (sb-ext:string-to-octets text :external-format :utf-8 :null-terminate t))
         (alien (sb-alien:make-alien sb-alien:char (length octets))))
    (loop for index from 0 below (length octets)
          do (let ((byte (aref octets index)))
               (setf (sb-alien:deref alien index)
                     (if (> byte 127) (- byte 256) byte))))
    alien))

(defun c-vector (strings)
  (let ((vector (sb-alien:make-alien (* sb-alien:char) (1+ (length strings)))))
    (loop for text in strings
          for index from 0
          do (setf (sb-alien:deref vector index) (c-string text)))
    (setf (sb-alien:deref vector (length strings))
          (sb-alien:sap-alien (sb-sys:int-sap 0) (* sb-alien:char)))
    vector))

(defun path-exists-p (path)
  (handler-case
      (progn (sb-posix:stat path) t)
    (sb-posix:syscall-error () nil)))

(defun shell-program (shell-path)
  (cond
    (shell-path
     (if (path-exists-p shell-path)
         shell-path
         (env-failure "shell_unavailable"
                      (format nil "Custom shell path not found: ~A" shell-path))))
    ((path-exists-p "/bin/bash") "/bin/bash")
    (t "/bin/sh")))

(defun resolve-program (program env)
  (when (find #\/ program)
    (return-from resolve-program program))
  (let ((path (or (cdr (assoc "PATH" env :test #'equal))
                  (sb-ext:posix-getenv "PATH")
                  "")))
    (or (loop for directory in (loop for start = 0 then (1+ end)
                                     for end = (position #\: path :start start)
                                     collect (subseq path start (or end (length path)))
                                     while end)
              for candidate = (concatenate 'string directory "/" program)
              when (path-exists-p candidate)
                return candidate)
        program)))

(defun merged-env (request)
  (let ((pairs nil))
    (when (json-flag request "inheritEnv" t)
      (dolist (item (sb-ext:posix-environ))
        (let ((equals (position #\= item)))
          (when equals
            (push (cons (subseq item 0 equals) (subseq item (1+ equals))) pairs)))))
    (let ((env (json-get request "env")))
      (when (json-object-p env)
        (maphash (lambda (key value)
                   (when (stringp value)
                     (setf pairs (cons (cons key value)
                                       (remove key pairs :key #'car :test #'equal)))))
                 env)))
    (nreverse pairs)))

(defun env-strings (pairs)
  (mapcar (lambda (pair) (concatenate 'string (car pair) "=" (cdr pair))) pairs))

(defun command-spec (request)
  (let ((command (json-string request "command"))
        (argv (json-get request "argv"))
        (cwd (json-string request "cwd")))
    (unless cwd
      (env-failure "EINVAL" "exec needs cwd"))
    (unless (path-exists-p cwd)
      (env-failure "spawn_error"
                   (format nil "Working directory does not exist: ~A~%Cannot execute bash commands." cwd)))
    (cond
      (command
       (values (shell-program (json-string request "shellPath"))
               (list "-c" command)
               cwd))
      ((json-array-p argv)
       (when (zerop (length argv))
         (env-failure "spawn_error" "Empty argv: no program to run"))
       (let ((pairs (merged-env request)))
         (values (resolve-program (aref argv 0) pairs)
                 (coerce (subseq argv 1) 'list)
                 cwd)))
      (t (env-failure "EINVAL" "exec needs command or argv")))))

(defun kill-group (pid)
  (ignore-errors (sb-posix:kill (- pid) 9))
  (ignore-errors (sb-posix:kill pid 9)))

(defun default-signals (bytes)
  (loop for signal from 1 to 31
        unless (member signal '(9 19))
          do (let ((bit (1- signal)))
               (setf (aref bytes (floor bit 8))
                     (logior (aref bytes (floor bit 8)) (ash 1 (mod bit 8)))))))

(defun posix-spawn (program argv0 args env-list cwd actions-fn)
  (let ((actions (make-array 128 :element-type '(unsigned-byte 8) :initial-element 0))
        (attributes (make-array 512 :element-type '(unsigned-byte 8) :initial-element 0))
        (mask (make-array 128 :element-type '(unsigned-byte 8) :initial-element 0))
        (defaults (make-array 128 :element-type '(unsigned-byte 8) :initial-element 0))
        (pid-bytes (make-array 4 :element-type '(unsigned-byte 8) :initial-element 0))
        (argv-alien (c-vector (cons argv0 args)))
        (env-alien (c-vector env-list)))
    (default-signals defaults)
    (sb-sys:with-pinned-objects (actions attributes mask defaults pid-bytes)
      (let ((action-sap (sb-sys:vector-sap actions))
            (attribute-sap (sb-sys:vector-sap attributes)))
        (%actions-init action-sap)
        (%attr-init attribute-sap)
        (unwind-protect
             (progn
               (funcall actions-fn action-sap)
               (unless (zerop (%actions-chdir action-sap cwd))
                 (env-failure "spawn_error" "chdir failed"))
               (%attr-flags attribute-sap (logior +spawn-setsid+ +spawn-setsigdef+ +spawn-setsigmask+))
               (%attr-mask attribute-sap (sb-sys:vector-sap mask))
               (%attr-default attribute-sap (sb-sys:vector-sap defaults))
               (let ((status (%posix-spawn (sb-sys:vector-sap pid-bytes) program
                                           action-sap attribute-sap argv-alien env-alien)))
                 (unless (zerop status)
                   (env-failure "spawn_error" "posix_spawn failed"))
                 (logior (aref pid-bytes 0)
                         (ash (aref pid-bytes 1) 8)
                         (ash (aref pid-bytes 2) 16)
                         (ash (aref pid-bytes 3) 24))))
          (%actions-destroy action-sap)
          (%attr-destroy attribute-sap))))))

(defun spawn-session (program args cwd env-list)
  (let ((stdin (sb-posix:open "/dev/null" sb-posix:o-rdonly))
        (out (multiple-value-list (sb-posix:pipe)))
        (err (multiple-value-list (sb-posix:pipe))))
    (let ((out-read (first out))
          (out-write (second out))
          (err-read (first err))
          (err-write (second err)))
      (unwind-protect
           (let ((pid (posix-spawn program program args env-list cwd
                                   (lambda (actions)
                                     (%actions-dup2 actions stdin 0)
                                     (%actions-dup2 actions out-write 1)
                                     (%actions-dup2 actions err-write 2)
                                     (dolist (fd (list stdin out-read out-write err-read err-write))
                                       (when (> fd 2)
                                         (%actions-close actions fd)))))))
             (values pid out-read err-read))
        (%c-close stdin)
        (%c-close out-write)
        (%c-close err-write)))))

(defun drain-fd (fd into lock)
  (let ((buffer (make-array 8192 :element-type '(unsigned-byte 8))))
    (loop for count = (ignore-errors
                         (sb-sys:with-pinned-objects (buffer)
                           (sb-posix:read fd (sb-sys:vector-sap buffer) (length buffer))))
          while (and count (plusp count))
          do (sb-thread:with-mutex (lock)
               (loop for index from 0 below count
                     do (vector-push-extend (aref buffer index) into))))))

(defun fresh-buffer ()
  (make-array 0 :element-type '(unsigned-byte 8) :adjustable t :fill-pointer 0))

(defun wait-status (pid)
  (multiple-value-bind (child status) (sb-posix:waitpid pid 0)
    (declare (ignore child))
    status))

(defun status-code (status)
  (cond ((sb-posix:wifsignaled status) (+ 128 (sb-posix:wtermsig status)))
        ((sb-posix:wifexited status) (sb-posix:wexitstatus status))
        (t 1)))

(defun uuid-v4 ()
  (let ((bytes (make-array 16 :element-type '(unsigned-byte 8))))
    (dotimes (index 16)
      (setf (aref bytes index) (random 256)))
    (setf (aref bytes 6) (logior #x40 (logand (aref bytes 6) #x0f))
          (aref bytes 8) (logior #x80 (logand (aref bytes 8) #x3f)))
    (format nil "~{~2,'0x~}-~{~2,'0x~}-~{~2,'0x~}-~{~2,'0x~}-~{~2,'0x~}"
            (coerce (subseq bytes 0 4) 'list)
            (coerce (subseq bytes 4 6) 'list)
            (coerce (subseq bytes 6 8) 'list)
            (coerce (subseq bytes 8 10) 'list)
            (coerce (subseq bytes 10 16) 'list))))

(defun spill-file (chunks)
  (let* ((directory (json-get (op-mkdtemp (json-object "prefix"
                                                       (concatenate 'string (host-tmpdir) "/tmp-")))
                              "path"))
         (path (concatenate 'string directory "/" (wire-literal :spill-prefix) (uuid-v4) ".log")))
    (with-open-file (stream path :direction :output :element-type '(unsigned-byte 8)
                            :if-exists :append :if-does-not-exist :create)
      (dolist (chunk chunks)
        (write-sequence chunk stream)))
    path))

(defun maybe-spill (chunks raw-bytes newlines after-bytes after-lines)
  (when (and after-bytes after-lines
             (or (> raw-bytes after-bytes)
                 (> newlines after-lines)))
    (spill-file chunks)))

(defun decode-all (octets)
  (utf8-decode (make-utf8-decoder) octets :last t))

(defun emit-output (emit stream text &optional skipped)
  (when (or (plusp (length text)) skipped)
    (let ((json (json-object "kind" "output" "stream" stream)))
      (when skipped (json-put json "skipped" skipped))
      (funcall emit json (utf8-bytes text)))))

(defun deliver-captured (emit window stdout stderr)
  (if window
      (let ((pending (make-pending window)))
        (let ((text (decode-all stdout)))
          (pending-push pending "stdout" text))
        (let ((text (decode-all stderr)))
          (pending-push pending "stderr" text))
        (dolist (event (pending-take pending))
          (emit-output emit (output-event-stream event) (output-event-text event)
                       (output-event-skipped event))))
      (progn
        (emit-output emit "stdout" (decode-all stdout))
        (emit-output emit "stderr" (decode-all stderr)))))

(defun run-exec (request emit control)
  (when (and control (control-aborted control))
    (env-failure "aborted" "aborted"))
  (multiple-value-bind (program args cwd) (command-spec request)
    (let* ((env (env-strings (merged-env request)))
           (timeout (json-get request "timeoutMs")))
      (multiple-value-bind (pid out-fd err-fd) (spawn-session program args cwd env)
        (let* ((stdout (fresh-buffer))
               (stderr (fresh-buffer))
               (lock (sb-thread:make-mutex :name "env-output-bytes"))
               (readers (list (sb-thread:make-thread (lambda () (drain-fd out-fd stdout lock))
                                                     :name "env-stdout")
                              (sb-thread:make-thread (lambda () (drain-fd err-fd stderr lock))
                                                     :name "env-stderr")))
               (deadline (when (realp timeout)
                           (+ (get-internal-real-time)
                              (round (* timeout (/ internal-time-units-per-second 1000))))))
               (status nil)
               (timed-out nil)
               (aborted nil))
          (unwind-protect
               (loop
                 (when (and control (progn (sb-thread:barrier (:read)) (control-killed control)))
                   (kill-group pid))
                 (when (and control (control-aborted control))
                   (setf aborted t)
                   (kill-group pid))
                 (when (and deadline (>= (get-internal-real-time) deadline))
                   (setf timed-out t)
                   (kill-group pid))
                 (multiple-value-bind (child code) (sb-posix:waitpid pid sb-posix:wnohang)
                   (when (plusp child)
                     (setf status code)
                     (return)))
                 (sleep 0.02))
            (dolist (reader readers)
              (cadr-core:join-active-thread
               reader :reason "env exec output drain"))
            (ignore-errors (%c-close out-fd))
            (ignore-errors (%c-close err-fd)))
          (let* ((spill (json-get request "spill"))
                 (path (maybe-spill
                        (list stdout stderr)
                        (+ (length stdout) (length stderr))
                        (+ (count 10 stdout) (count 10 stderr))
                        (when (json-object-p spill) (json-u64 spill "afterBytes"))
                        (when (json-object-p spill) (json-u64 spill "afterLines"))))
                 (window (window-from-json (json-get request "window"))))
            (deliver-captured emit window stdout stderr)
            (cond
              (timed-out
               (env-failure "timeout" "timeout"
                            :extra (when path (json-object "spillPath" path))))
              (aborted
               (env-failure "aborted" "aborted"
                            :extra (when path (json-object "spillPath" path))))
              (t
               (let ((result (json-object "exitCode" (status-code status))))
                 (when path (json-put result "spillPath" path))
                 result)))))))))
