(in-package #:cadr-agent)

;;; pi@4a080252f StdioTransport. Newline-delimited JSON-RPC.
;;; Shutdown closes stdin, then SIGTERM, then SIGKILL, on the
;;; server's process group.

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-posix))

(defparameter +mcp-max-stderr-bytes+ (* 64 1024))
(defparameter +mcp-stdio-close-timeout-ms+ 2000)
(defparameter +mcp-stdio-stdin-grace-ms+ 500)

(defvar *mcp-stdio-groups* nil)
(defvar *mcp-stdio-exit-hook-p* nil)

(defun mcp-stdio-install-exit-hook ()
  (unless *mcp-stdio-exit-hook-p*
    (setf *mcp-stdio-exit-hook-p* t)
    (push (lambda ()
            (dolist (pid *mcp-stdio-groups*)
              (ignore-errors
                (sb-posix:kill (- pid) sb-posix:sigterm))))
          sb-ext:*exit-hooks*)))

(defun mcp-kill-process-group (pid signal)
  (handler-case
      (sb-posix:kill (- pid) signal)
    (error ()
      (ignore-errors (sb-posix:kill pid signal)))))

(defstruct (mcp-stdio-transport (:constructor %make-mcp-stdio-transport))
  (command "" :type string)
  args
  cwd
  env
  (inherit-env-p t :type boolean)
  (stderr-mode "pipe" :type string)
  on-stderr
  (max-message-bytes +mcp-max-message-bytes+ :type integer)
  (max-stderr-bytes +mcp-max-stderr-bytes+ :type integer)
  (close-timeout-ms +mcp-stdio-close-timeout-ms+ :type integer)
  process
  pid
  (stderr "" :type string)
  (stdout-buffer "" :type string)
  (started-p nil :type boolean)
  (closed-p nil :type boolean)
  (close-emitted-p nil :type boolean)
  (message-listeners nil :type list)
  (error-listeners nil :type list)
  (close-listeners nil :type list)
  (lock (sb-thread:make-mutex :name "mcp stdio")))

(defun make-mcp-stdio-transport (&key command args cwd env
                                      (inherit-env t)
                                      (stderr "pipe")
                                      on-stderr
                                      (max-message-bytes +mcp-max-message-bytes+)
                                      (max-stderr-bytes +mcp-max-stderr-bytes+)
                                      (close-timeout-ms +mcp-stdio-close-timeout-ms+))
  (%make-mcp-stdio-transport
   :command command
   :args (and args (coerce args 'list))
   :cwd cwd
   :env env
   :inherit-env-p inherit-env
   :stderr-mode stderr
   :on-stderr on-stderr
   :max-message-bytes max-message-bytes
   :max-stderr-bytes max-stderr-bytes
   :close-timeout-ms close-timeout-ms))

(defun mcp-stdio-pid (transport)
  (mcp-stdio-transport-pid transport))

(defun mcp-stdio-stderr (transport)
  (mcp-stdio-transport-stderr transport))

(defun mcp-stdio-listeners (transport slot)
  (sb-thread:with-mutex ((mcp-stdio-transport-lock transport))
    (copy-list (slot-value transport slot))))

(defun mcp-stdio-emit-messages (transport message)
  (dolist (listener (mcp-stdio-listeners transport 'message-listeners))
    (funcall listener message)))

(defun mcp-stdio-emit-error (transport error)
  (let ((normalized
          (if (typep error 'error)
              error
              (make-condition 'simple-error
                              :format-control "~A"
                              :format-arguments (list error)))))
    (dolist (listener (mcp-stdio-listeners transport 'error-listeners))
      (funcall listener normalized))))

(defun mcp-stdio-emit-close (transport)
  (let ((emit nil))
    (sb-thread:with-mutex ((mcp-stdio-transport-lock transport))
      (unless (mcp-stdio-transport-close-emitted-p transport)
        (setf (mcp-stdio-transport-close-emitted-p transport) t
              emit t)))
    (when emit
      (dolist (listener (mcp-stdio-listeners transport 'close-listeners))
        (funcall listener)))))

(defmethod mcp-transport-on-message ((transport mcp-stdio-transport) listener)
  (sb-thread:with-mutex ((mcp-stdio-transport-lock transport))
    (push listener (mcp-stdio-transport-message-listeners transport)))
  (lambda ()
    (sb-thread:with-mutex ((mcp-stdio-transport-lock transport))
      (setf (mcp-stdio-transport-message-listeners transport)
            (remove listener
                    (mcp-stdio-transport-message-listeners transport))))))

(defmethod mcp-transport-on-error ((transport mcp-stdio-transport) listener)
  (sb-thread:with-mutex ((mcp-stdio-transport-lock transport))
    (push listener (mcp-stdio-transport-error-listeners transport)))
  (lambda ()
    (sb-thread:with-mutex ((mcp-stdio-transport-lock transport))
      (setf (mcp-stdio-transport-error-listeners transport)
            (remove listener
                    (mcp-stdio-transport-error-listeners transport))))))

(defmethod mcp-transport-on-close ((transport mcp-stdio-transport) listener)
  (sb-thread:with-mutex ((mcp-stdio-transport-lock transport))
    (push listener (mcp-stdio-transport-close-listeners transport)))
  (lambda ()
    (sb-thread:with-mutex ((mcp-stdio-transport-lock transport))
      (setf (mcp-stdio-transport-close-listeners transport)
            (remove listener
                    (mcp-stdio-transport-close-listeners transport))))))

(defun mcp-utf8-length (text)
  (length (sb-ext:string-to-octets text :external-format :utf-8)))

(defun mcp-stdio-note-stderr (transport text)
  (sb-thread:with-mutex ((mcp-stdio-transport-lock transport))
    (setf (mcp-stdio-transport-stderr transport)
          (concatenate 'string
                       (mcp-stdio-transport-stderr transport)
                       text))
    (when (> (mcp-utf8-length (mcp-stdio-transport-stderr transport))
             (mcp-stdio-transport-max-stderr-bytes transport))
      (setf (mcp-stdio-transport-stderr transport)
            (subseq (mcp-stdio-transport-stderr transport)
                    (max 0
                         (- (length (mcp-stdio-transport-stderr transport))
                            (mcp-stdio-transport-max-stderr-bytes transport)))))))
  (when (mcp-stdio-transport-on-stderr transport)
    (funcall (mcp-stdio-transport-on-stderr transport) text)))

(defun mcp-stdio-take-line (transport)
  (let ((newline (position #\Newline (mcp-stdio-transport-stdout-buffer transport))))
    (unless newline
      (when (> (mcp-utf8-length (mcp-stdio-transport-stdout-buffer transport))
               (mcp-stdio-transport-max-message-bytes transport))
        (setf (mcp-stdio-transport-stdout-buffer transport) "")
        (mcp-stdio-emit-error
         transport
         (make-condition
          'simple-error
          :format-control "MCP stdio message exceeds ~A bytes"
          :format-arguments
          (list (mcp-stdio-transport-max-message-bytes transport)))))
      (return-from mcp-stdio-take-line nil))
    (let ((line (subseq (mcp-stdio-transport-stdout-buffer transport) 0 newline)))
      (setf (mcp-stdio-transport-stdout-buffer transport)
            (subseq (mcp-stdio-transport-stdout-buffer transport) (1+ newline)))
      (when (and (plusp (length line)) (char= (char line (1- (length line))) #\Return))
        (setf line (subseq line 0 (1- (length line)))))
      (cond
        ((> (mcp-utf8-length line)
            (mcp-stdio-transport-max-message-bytes transport))
         (mcp-stdio-emit-error
          transport
          (make-condition
           'simple-error
           :format-control "MCP stdio message exceeds ~A bytes"
           :format-arguments
           (list (mcp-stdio-transport-max-message-bytes transport))))
         t)
        ((zerop (length (string-trim '(#\Space #\Tab #\Return) line)))
         t)
        (t
         (handler-case
             (mcp-stdio-emit-messages
              transport
              (mcp-parse-jsonrpc (mcp-read-json line)))
           (error (condition)
             (mcp-stdio-emit-error transport condition)))
         t)))))

(defun mcp-stdio-read-stdout (transport stream)
  (handler-case
      (loop for character = (read-char stream nil :eof)
            until (eq character :eof)
            do (setf (mcp-stdio-transport-stdout-buffer transport)
                     (concatenate 'string
                                  (mcp-stdio-transport-stdout-buffer transport)
                                  (string character)))
               (loop while (mcp-stdio-take-line transport)))
    (error (condition)
      (mcp-stdio-emit-error transport condition)))
  (let ((rest (string-trim '(#\Space #\Tab #\Return #\Newline)
                           (mcp-stdio-transport-stdout-buffer transport))))
    (when (plusp (length rest))
      (mcp-stdio-emit-error
       transport
       (make-condition 'simple-error
                       :format-control
                       "MCP stdio server closed with an incomplete JSON-RPC message"
                       :format-arguments nil)))
    (setf (mcp-stdio-transport-stdout-buffer transport) "")
    (mcp-stdio-emit-close transport)))

(defun mcp-stdio-read-stderr (transport stream)
  ;; read-sequence on a pipe waits for a full buffer. One character
  ;; returns as soon as the server writes, which is how a stderr tail
  ;; becomes visible before the process exits.
  (handler-case
      (if (subtypep (stream-element-type stream) 'character)
          (loop for character = (read-char stream nil :eof)
                until (eq character :eof)
                do (mcp-stdio-note-stderr transport (string character)))
          (let ((octets (make-array 0
                                    :element-type '(unsigned-byte 8)
                                    :adjustable t
                                    :fill-pointer 0)))
            (loop for byte = (read-byte stream nil :eof)
                  until (eq byte :eof)
                  do (vector-push-extend byte octets)
                     (when (or (= byte 10) (>= (length octets) 1024))
                       (mcp-stdio-note-stderr
                        transport (cadr-ai::utf8-string octets))
                       (setf (fill-pointer octets) 0)))
            (when (plusp (length octets))
              (mcp-stdio-note-stderr transport (cadr-ai::utf8-string octets)))))
    (error (condition)
      (unless (mcp-stdio-transport-closed-p transport)
        (mcp-stdio-emit-error transport condition)))))

(defun mcp-merge-environment (extra inherit-p)
  (let ((table (make-hash-table :test #'equal)))
    (when inherit-p
      (dolist (pair (sb-ext:posix-environ))
        (let ((split (position #\= pair)))
          (when split
            (setf (gethash (subseq pair 0 split) table) pair)))))
    (when extra
      (loop for (key value) on extra by #'cddr
            do (setf (gethash key table)
                     (format nil "~A=~A" key value))))
    (loop for pair being the hash-values of table collect pair)))

(defmethod mcp-transport-start ((transport mcp-stdio-transport))
  (when (mcp-stdio-transport-started-p transport)
    (error "MCP stdio transport already started"))
  (when (mcp-stdio-transport-closed-p transport)
    (error 'mcp-connection-closed-error))
  (setf (mcp-stdio-transport-started-p transport) t)
  (let* ((command
           (cons (mcp-stdio-transport-command transport)
                 (or (mcp-stdio-transport-args transport) nil)))
         (process
           (uiop:launch-program
            command
            :input :stream
            :output :stream
            :error-output (if (string= (mcp-stdio-transport-stderr-mode transport)
                                       "inherit")
                              :interactive
                              :stream)
            :directory (mcp-stdio-transport-cwd transport)
            :environment (mcp-merge-environment
                          (mcp-stdio-transport-env transport)
                          (mcp-stdio-transport-inherit-env-p transport))
            :wait nil))
         (pid (uiop:process-info-pid process)))
    (setf (mcp-stdio-transport-process transport) process
          (mcp-stdio-transport-pid transport) pid)
    (ignore-errors (sb-posix:setpgid pid 0))
    (mcp-stdio-install-exit-hook)
    (push pid *mcp-stdio-groups*)
    (sb-thread:make-thread
     (lambda ()
       (unwind-protect
            (mcp-stdio-read-stdout
             transport (uiop:process-info-output process))
         (setf *mcp-stdio-groups* (remove pid *mcp-stdio-groups*))))
     :name "mcp stdio stdout")
    (let ((stderr (uiop:process-info-error-output process)))
      (when stderr
        (sb-thread:make-thread
         (lambda () (mcp-stdio-read-stderr transport stderr))
         :name "mcp stdio stderr"))))
  nil)

(defmethod mcp-transport-send ((transport mcp-stdio-transport) message &key abort)
  (declare (ignore abort))
  (let ((process (mcp-stdio-transport-process transport))
        (input (and (mcp-stdio-transport-process transport)
                    (uiop:process-info-input
                     (mcp-stdio-transport-process transport)))))
    (unless (and (mcp-stdio-transport-started-p transport)
                 (not (mcp-stdio-transport-closed-p transport))
                 process
                 input
                 (open-stream-p input)
                 (uiop:process-alive-p process))
      (error 'mcp-connection-closed-error))
    (write-string (mcp-write-json message) input)
    (write-char #\Newline input)
    (finish-output input))
  nil)

(defun mcp-stdio-wait-dead (process seconds)
  (loop for elapsed = 0.0 then (+ elapsed 0.01)
        while (and (uiop:process-alive-p process)
                   (< elapsed seconds))
        do (sleep 0.01))
  (not (uiop:process-alive-p process)))

(defmethod mcp-transport-close ((transport mcp-stdio-transport))
  (when (mcp-stdio-transport-closed-p transport)
    (return-from mcp-transport-close nil))
  (setf (mcp-stdio-transport-closed-p transport) t)
  (let ((process (mcp-stdio-transport-process transport))
        (pid (mcp-stdio-transport-pid transport)))
    (cond
      ((null process)
       (mcp-stdio-emit-close transport))
      ((not (uiop:process-alive-p process))
       (ignore-errors
         (close (uiop:process-info-input process)))
       (mcp-stdio-emit-close transport))
      (t
       (ignore-errors
         (close (uiop:process-info-input process)))
       (let* ((timeout (/ (mcp-stdio-transport-close-timeout-ms transport) 1000.0))
              (grace (min 0.5 timeout)))
         (mcp-stdio-wait-dead process grace)
         (when (and pid (uiop:process-alive-p process))
           (mcp-kill-process-group pid sb-posix:sigterm))
         (mcp-stdio-wait-dead process timeout)
         (when (and pid (uiop:process-alive-p process))
           (mcp-kill-process-group pid sb-posix:sigkill)
           (mcp-stdio-wait-dead process 1.0))
         (when pid
           (mcp-kill-process-group pid sb-posix:sigterm)))
       (mcp-stdio-emit-close transport))))
  nil)
