(in-package #:cadr-env)

(defconstant +ping-seconds+ 5)
(defconstant +silence-seconds+ 30)

(defparameter *host-os* nil)

(defun host-os ()
  (or *host-os*
      (let ((type (string-downcase (software-type))))
        (cond ((search "linux" type) "linux")
              ((search "darwin" type) "macos")
              ((or (search "windows" type) (search "mingw" type)) "windows")
              (t "linux")))))

(defun host-arch ()
  (let ((arch (string-downcase (machine-type))))
    (cond ((or (search "x86-64" arch) (search "x86_64" arch) (search "amd64" arch)) "x86_64")
          ((or (search "aarch64" arch) (search "arm64" arch)) "aarch64")
          ((search "x86" arch) "x86")
          (t arch))))

(defun silence-exceeded-p (last now)
  (> (- now last) (* +silence-seconds+ internal-time-units-per-second)))

(defun hello-json ()
  (json-object "protocol" +protocol-version+
               "version" +package-version+
               "os" (host-os)
               "arch" (host-arch)
               "home" (or (sb-ext:posix-getenv "HOME") "")
               "separator" (host-separator)
               "tmpdir" (host-tmpdir)
               "cwd" (namestring (uiop:getcwd))
               "driveCwds" (json-object)
               "pid" (sb-posix:getpid)
               "features" (if (equal (sb-ext:posix-getenv "CADR_ENV_OMIT_LIST_FILES") "1")
                              (json-array)
                              (json-array "listFiles"))))

(defun send-frame (server frame)
  (sb-thread:with-mutex ((server-output-lock server))
    (unless (server-closed server)
      (write-frame (server-stream server) frame))))

(defun send-result (server id json &optional (payload #()))
  (send-frame server (make-frame +result+ id json payload)))

(defun send-error (server id condition)
  (send-frame server (make-frame +error+ id (failure-json condition))))

(defun send-event (server id json payload)
  (send-frame server (make-frame +event+ id json payload)))

(defun dispatch-op (server id request payload emit control)
  (let ((op (json-string request "op")))
    (cond
      ((equal op "hello") (hello-json))
      ((equal op "lstat") (op-lstat request))
      ((equal op "realpath") (op-realpath request))
      ((equal op "write") (op-write request payload server))
      ((equal op "writeChunk") (op-write-chunk request payload server))
      ((equal op "truncate") (op-truncate request))
      ((equal op "fsync") (op-fsync request))
      ((equal op "rename") (op-rename request))
      ((equal op "mkdir") (op-mkdir request))
      ((equal op "rm") (op-rm request))
      ((equal op "mkdtemp") (op-mkdtemp request))
      ((equal op "open") (op-open request server))
      ((equal op "pread") (op-pread request server))
      ((equal op "fstat") (op-fstat request server))
      ((equal op "scanLines")
       (op-scan-lines request server (lambda () (control-aborted-p control))))
      ((equal op "opendir") (op-opendir request server))
      ((equal op "readdir") (op-readdir request server))
      ((equal op "close") (op-close request server))
      ((equal op "listFiles")
       (op-list-files request (lambda () (control-aborted-p control))))
      ((equal op "exec")
       (run-exec request (lambda (json bytes) (funcall emit json bytes)) control))
      ((equal op "pty")
       (run-pty server id request (lambda (json bytes) (funcall emit json bytes)) control))
      ((equal op "ptyWrite") (pty-write server request payload))
      ((equal op "ptyResize") (pty-resize server request))
      ((equal op "ptyForeground") (pty-foreground server request))
      ((equal op "watch")
       (run-watch request (lambda (json bytes) (funcall emit json bytes)) control))
      (t (env-failure "EINVAL" (format nil "unknown operation ~A" op))))))

(defun finish-op (server id producer)
  (handler-case
      (multiple-value-bind (json payload) (funcall producer)
        (send-result server id json (or payload #())))
    (env-failure (condition)
      (send-error server id condition))
    (error (condition)
      (send-error server id
                  (make-instance 'env-failure :code "unknown"
                                 :message (princ-to-string condition))))))

(defun long-op-p (op)
  ;; listFiles and scanLines leave the reader. A cancel written behind the
  ;; request is registered before the walk, then applied between entries or chunks.
  (member op '("exec" "pty" "watch" "listFiles" "scanLines") :test #'equal))

(defun remember-control (server id control)
  (sb-thread:with-mutex ((server-controls-lock server))
    (setf (gethash id (server-controls server)) control)))

(defun forget-control (server id)
  (sb-thread:with-mutex ((server-controls-lock server))
    (remhash id (server-controls server))))

(defun find-control (server id)
  (sb-thread:with-mutex ((server-controls-lock server))
    (gethash id (server-controls server))))

(defun handle-request (server frame)
  (let* ((id (frame-id frame))
         (request (frame-json frame))
         (control (make-control)))
    (cond
      ((not (json-object-p request))
       (send-error server id (make-condition 'env-failure :code "EINVAL" :message "invalid JSON")))
      ((member (json-string request "op") '("ptyWrite" "ptyResize" "ptyForeground") :test #'equal)
       (finish-op server id (lambda () (dispatch-op server id request (frame-payload frame) nil nil))))
      (t
       (remember-control server id control)
       (flet ((emit (json bytes) (send-event server id json bytes)))
         (if (long-op-p (json-string request "op"))
             (sb-thread:make-thread
              (lambda ()
                (unwind-protect
                     (finish-op server id
                                (lambda ()
                                  (dispatch-op server id request (frame-payload frame) #'emit control)))
                  (forget-control server id)))
              :name "env-operation")
             (unwind-protect
                  (finish-op server id
                             (lambda ()
                               (dispatch-op server id request (frame-payload frame) #'emit control)))
               (forget-control server id))))))))

(defun handle-cancel (server frame)
  (let ((control (find-control server (frame-id frame))))
    (when control
      (control-cancel control (equal (json-string (frame-json frame) "mode") "kill")))))

(defun handle-frame (server frame)
  (case (frame-kind frame)
    (#.+ping+ nil)
    (#.+cancel+ (handle-cancel server frame))
    (#.+request+ (handle-request server frame))
    (t nil)))

(defun kill-server-processes (server)
  (maphash (lambda (id terminal)
             (declare (ignore id))
             (kill-group (terminal-pid terminal)))
           (server-terminals server))
  (close-all-handles server))

(defun serve-frames (input output)
  (let ((server (make-server :stream output)))
    (setf (server-last-input server) (get-internal-real-time))
    (let ((worker
            (sb-thread:make-thread
             (lambda ()
               (loop with ticks = 0
                     until (server-closed server)
                     do (sleep 0.2)
                        (incf ticks 0.2)
                        (when (silence-exceeded-p (server-last-input server)
                                                  (get-internal-real-time))
                          (kill-server-processes server)
                          (setf (server-closed server) t)
                          (return))
                        (when (>= ticks +ping-seconds+)
                          (setf ticks 0)
                          (ignore-errors
                            (send-frame server (make-frame +ping+ 0 (empty-json)))))))
             :name "env-ping")))
      (unwind-protect
           (loop for frame = (handler-case (read-frame input)
                               (error ()
                                 (setf (server-closed server) t)
                                 nil))
                 while (and frame (not (server-closed server)))
                 do (setf (server-last-input server) (get-internal-real-time))
                    (handle-frame server frame))
        (setf (server-closed server) t)
        (kill-server-processes server)
        (cadr-core:stop-thread-for-cleanup worker :timeout 1d0)))))

(defun write-text-line (stream text)
  (if (subtypep (stream-element-type stream) 'character)
      (progn (write-line text stream) (finish-output stream))
      (progn
        (write-sequence (utf8-bytes (concatenate 'string text (string #\Newline))) stream)
        (finish-output stream))))

(defun daemon-command (argv &key (stdout *standard-output*) (stderr *error-output*)
                              (stdin *standard-input*))
  (cond
    ((equal argv '("--version"))
     (write-text-line stdout (concatenate 'string (wire-literal :version-name) +package-version+))
     0)
    ((and (equal (first argv) "serve")
          (equal (second argv) "--token")
          (stringp (third argv))
          (null (cdddr argv)))
     (write-text-line stdout (concatenate 'string (wire-literal :banner) (third argv)))
     (serve-frames stdin stdout)
     0)
    (t
     (write-text-line stderr (wire-literal :usage))
     2)))

(defun stream-fd (stream fallback)
  (if (sb-sys:fd-stream-p stream)
      (sb-sys:fd-stream-fd stream)
      fallback))

(defun daemon-stdio (argv)
  "Speak the daemon protocol on this process's standard streams.
The streams SBCL opened are character streams; the protocol is bytes, so the
descriptors are duplicated and reopened before the banner."
  (let ((in-fd (sb-posix:dup (stream-fd *standard-input* 0)))
        (out-fd (sb-posix:dup (stream-fd *standard-output* 1)))
        (err-fd (sb-posix:dup (stream-fd *error-output* 2))))
    (close *standard-input*)
    (close *standard-output*)
    (close *error-output*)
    (let ((stdin (sb-sys:make-fd-stream in-fd :input t
                                        :element-type '(unsigned-byte 8)
                                        :buffering :none :auto-close t))
          (stdout (sb-sys:make-fd-stream out-fd :output t
                                         :element-type '(unsigned-byte 8)
                                         :buffering :none :auto-close t))
          (stderr (sb-sys:make-fd-stream err-fd :output t
                                         :element-type '(unsigned-byte 8)
                                         :buffering :none :auto-close t)))
      (let ((status (handler-case
                        (daemon-command argv :stdin stdin :stdout stdout :stderr stderr)
                      (error (condition)
                        (ignore-errors
                          (write-sequence (utf8-bytes (princ-to-string condition)) stderr)
                          (write-byte 10 stderr)
                          (finish-output stderr))
                        1))))
        (ignore-errors (finish-output stdout))
        (ignore-errors (finish-output stderr))
        (sb-ext:exit :code status)))))
