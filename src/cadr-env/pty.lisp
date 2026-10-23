(in-package #:cadr-env)

(defconstant +max-cells+ 4096)
(defconstant +tiocswinsz+ #x5414)
(defconstant +tiocsctty+ #x540e)

(sb-alien:define-alien-routine ("posix_openpt" %posix-openpt) sb-alien:int
  (flags sb-alien:int))

(sb-alien:define-alien-routine ("grantpt" %grantpt) sb-alien:int
  (fd sb-alien:int))

(sb-alien:define-alien-routine ("unlockpt" %unlockpt) sb-alien:int
  (fd sb-alien:int))

(sb-alien:define-alien-routine ("ptsname" %ptsname) sb-alien:c-string
  (fd sb-alien:int))

(sb-alien:define-alien-routine ("ioctl" %ioctl) sb-alien:int
  (fd sb-alien:int)
  (request sb-alien:unsigned-long)
  (argument sb-alien:system-area-pointer))

(sb-alien:define-alien-routine ("tcgetpgrp" %tcgetpgrp) sb-alien:int
  (fd sb-alien:int))

(defstruct terminal
  master
  pid
  (input (make-array 0 :element-type '(unsigned-byte 8) :adjustable t :fill-pointer 0))
  (lock (sb-thread:make-mutex :name "env-terminal"))
  (ended nil))

(defun cell-size (request key)
  (let ((value (json-u64 request key)))
    (if (and value (<= 1 value +max-cells+))
        value
        (env-failure "EINVAL" (format nil "~A must be between 1 and ~A" key +max-cells+)))))

(defun set-window-size (fd cols rows)
  (let ((buffer (make-array 8 :element-type '(unsigned-byte 8) :initial-element 0)))
    (setf (aref buffer 0) (ldb (byte 8 0) rows)
          (aref buffer 1) (ldb (byte 8 8) rows)
          (aref buffer 2) (ldb (byte 8 0) cols)
          (aref buffer 3) (ldb (byte 8 8) cols))
    (%ioctl fd +tiocswinsz+ (sb-sys:vector-sap buffer))))

(defun open-pty (cols rows)
  (let ((master (%posix-openpt (logior 2 256))))
    (when (< master 0)
      (env-failure "spawn_error" "posix_openpt failed"))
    (when (< (%grantpt master) 0)
      (env-failure "spawn_error" "grantpt failed"))
    (when (< (%unlockpt master) 0)
      (env-failure "spawn_error" "unlockpt failed"))
    (set-window-size master cols rows)
    (let ((name (%ptsname master)))
      (unless (stringp name)
        (env-failure "spawn_error" "ptsname failed"))
      (values master (sb-posix:open name (logior sb-posix:o-rdwr) 0)))))

(defun login-shell (request)
  (let* ((env (json-get request "env"))
         (from-request (when (json-object-p env) (json-string env "SHELL")))
         (shell (or (and from-request (path-exists-p from-request) from-request)
                    (and (sb-ext:posix-getenv "SHELL")
                         (path-exists-p (sb-ext:posix-getenv "SHELL"))
                         (sb-ext:posix-getenv "SHELL"))
                    "/bin/sh")))
    (values shell (concatenate 'string "-" (path-name shell)))))

(defun pty-command (request)
  (let ((argv (json-get request "argv")))
    (cond
      ((json-null-p argv) (login-shell request))
      ((eq argv +absent+) (login-shell request))
      ((and (json-array-p argv) (plusp (length argv)))
       (values (resolve-program (aref argv 0) (merged-env request))
               (aref argv 0)
               (coerce (subseq argv 1) 'list)))
      (t (env-failure "EINVAL" "argv must be a non-empty array of strings")))))

(defun spawn-pty (request slave-name)
  (multiple-value-bind (program argv0 rest) (pty-command request)
    (let ((cwd (json-string request "cwd")))
      (unless (and cwd (path-exists-p cwd))
        (env-failure "spawn_error" (format nil "Working directory does not exist: ~A" cwd)))
      (posix-spawn program argv0 (or rest nil) (env-strings (merged-env request)) cwd
                   (lambda (actions)
                     (%actions-open actions 0 slave-name sb-posix:o-rdwr 0)
                     (%actions-dup2 actions 0 1)
                     (%actions-dup2 actions 0 2))))))

(defun find-terminal (server request)
  (let ((target (json-u64 request "target")))
    (unless target
      (env-failure "EINVAL" "missing field target"))
    (or (gethash target (server-terminals server))
        (env-failure "EBADF" "no running terminal with this id"))))

(defun pty-write (server request payload)
  (let ((terminal (find-terminal server request)))
    (when (terminal-ended terminal)
      (env-failure "EBADF" "the terminal has ended"))
    (sb-thread:with-mutex ((terminal-lock terminal))
      (loop for byte across payload
            do (vector-push-extend byte (terminal-input terminal))))
    (empty-json)))

(defun pty-resize (server request)
  (let ((terminal (find-terminal server request))
        (cols (cell-size request "cols"))
        (rows (cell-size request "rows")))
    (set-window-size (terminal-master terminal) cols rows)
    (empty-json)))

(defun process-comm (pid)
  (let ((path (format nil "/proc/~A/comm" pid)))
    (when (probe-file path)
      (string-trim '(#\Newline #\Return #\Space)
                   (read-text-file path)))))

(defun pty-foreground (server request)
  (let* ((terminal (find-terminal server request))
         (group (%tcgetpgrp (terminal-master terminal))))
    (if (or (<= group 0) (= group (terminal-pid terminal)))
        (json-object "foreground" +json-null+)
        (json-object "foreground"
                     (json-object "pid" group
                                  "name" (or (process-comm group) +json-null+))))))

(defun read-master (fd)
  (let ((buffer (make-array 4096 :element-type '(unsigned-byte 8))))
    (let ((count (ignore-errors
                   (sb-sys:with-pinned-objects (buffer)
                     (sb-posix:read fd (sb-sys:vector-sap buffer) (length buffer))))))
      (cond ((or (null count) (minusp count)) nil)
            ((zerop count) #())
            (t (subseq buffer 0 count))))))

(defun run-pty (server id request emit control)
  (unless (pty-supported-p)
    (env-failure "ENOTSUP" "Terminals are not supported on this system yet"))
  (when (and control (control-aborted control))
    (env-failure "aborted" "aborted"))
  (let ((cols (cell-size request "cols"))
        (rows (cell-size request "rows")))
    (multiple-value-bind (master slave) (open-pty cols rows)
      (sb-posix:fcntl master sb-posix:f-setfl
                      (logior (sb-posix:fcntl master sb-posix:f-getfl)
                              sb-posix:o-nonblock))
      (let* ((slave-name (%ptsname master))
             (pid (spawn-pty request slave-name)))
        (%c-close slave)
        (let ((terminal (make-terminal :master master :pid pid)))
          (setf (gethash id (server-terminals server)) terminal)
          (funcall emit (json-object "kind" "started" "pid" pid) #())
          (unwind-protect
               (let ((status nil))
                 (loop
                   (when (and control (control-aborted control))
                     (kill-group pid)
                     (remhash id (server-terminals server))
                     (setf (terminal-ended terminal) t)
                     (env-failure "aborted" "aborted"))
                   (sb-thread:with-mutex ((terminal-lock terminal))
                     (when (plusp (length (terminal-input terminal)))
                       (ignore-errors
                         (let ((input (terminal-input terminal)))
                           (sb-sys:with-pinned-objects (input)
                             (sb-posix:write master (sb-sys:vector-sap input) (length input))))
                         (setf (fill-pointer (terminal-input terminal)) 0))))
                   (let ((chunk (read-master master)))
                     (when (and chunk (plusp (length chunk)))
                       (funcall emit (json-object "kind" "output") chunk)))
                   (multiple-value-bind (child code) (sb-posix:waitpid pid sb-posix:wnohang)
                     (when (plusp child)
                       (setf status code)
                       (return)))
                   (sleep 0.02))
                 (sleep 0.1)
                 (loop for chunk = (read-master master)
                       while (and chunk (plusp (length chunk)))
                       do (funcall emit (json-object "kind" "output") chunk))
                 (json-object "exitCode" (status-code status)))
            (setf (terminal-ended terminal) t)
            (remhash id (server-terminals server))
            (ignore-errors (%c-close master))))))))

(defun pty-supported-p ()
  (not (equal (host-os) "windows")))
