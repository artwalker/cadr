(in-package #:cadr-env)

(defconstant +write-chunk+ (* 512 1024))
(defconstant +read-chunk+ (* 256 1024))
(defconstant +start-timeout-seconds+ 60)
(defconstant +silence-limit-seconds+ 30)

(define-condition remote-error (error)
  ((code :initarg :code :reader remote-error-code)
   (message :initarg :message :reader remote-error-message)
   (path :initarg :path :initform nil :reader remote-error-path)
   (lost :initarg :lost :initform nil :reader remote-error-lost))
  (:report (lambda (condition stream) (write-string (remote-error-message condition) stream))))

(defun remote-lost (message)
  (error 'remote-error :code "unknown" :message message :lost t))

(defstruct spawn-session
  id
  process
  input
  output
  token
  (live t)
  reader
  stderr-reader
  ping
  (buffer (make-array 0 :element-type '(unsigned-byte 8) :adjustable t :fill-pointer 0))
  (start 0)
  (synced nil)
  (last-seen (get-internal-real-time))
  (pending (make-hash-table :test #'eql))
  (lock (sb-thread:make-mutex :name "env-spawn-session"))
  (write-lock (sb-thread:make-mutex :name "env-spawn-write"))
  info)

(defstruct spawn-connection
  command
  on-log
  (session nil)
  (sessions 0)
  (next-id 0)
  (closed nil)
  (starting nil)
  (lock (sb-thread:make-mutex :name "env-spawn"))
  (wait (sb-thread:make-waitqueue :name "env-spawn")))

(defun make-env-abort ()
  (list nil))

(defun env-abort (cell)
  (when cell (setf (car cell) t))
  cell)

(defun env-abort-p (cell)
  (and cell (car cell)))

(defun spawn-binary-stream (stream direction)
  (let ((fd (sb-posix:dup (sb-sys:fd-stream-fd stream))))
    (close stream)
    (sb-sys:make-fd-stream fd direction t
                           :element-type '(unsigned-byte 8)
                           :buffering :none
                           :auto-close t)))

(defun spawn-write-frame (session frame)
  (when (spawn-session-live session)
    (sb-thread:with-mutex ((spawn-session-write-lock session))
      (when (spawn-session-live session)
        (handler-case
            (write-frame (spawn-session-input session) frame)
          (error ()
            (setf (spawn-session-live session) nil)))))))

(defun spawn-teardown (connection session condition)
  (unless (spawn-session-live session)
    (return-from spawn-teardown nil))
  (setf (spawn-session-live session) nil)
  (sb-thread:with-mutex ((spawn-connection-lock connection))
    (when (eq (spawn-connection-session connection) session)
      (setf (spawn-connection-session connection) nil))
    (sb-thread:condition-broadcast (spawn-connection-wait connection)))
  (ignore-errors (close (spawn-session-input session)))
  (let ((process (spawn-session-process session)))
    (when (and process (sb-ext:process-alive-p process))
      (ignore-errors (sb-ext:process-kill process 9))))
  (let ((pending nil))
    (sb-thread:with-mutex ((spawn-session-lock session))
      (maphash (lambda (id box)
                 (declare (ignore id))
                 (push box pending))
               (spawn-session-pending session))
      (clrhash (spawn-session-pending session)))
    (dolist (box pending)
      (sb-thread:with-mutex ((mailbox-lock box))
        (setf (mailbox-failure box) condition
              (mailbox-done box) t)
        (sb-thread:condition-broadcast (mailbox-wait box)))))
  (when (spawn-session-ping session)
    (cadr-core:stop-thread-for-cleanup (spawn-session-ping session) :timeout 1d0))
  (when (and (spawn-session-reader session)
             (not (eq (spawn-session-reader session) sb-thread:*current-thread*)))
    (cadr-core:stop-thread-for-cleanup (spawn-session-reader session) :timeout 1d0))
  (when (spawn-session-stderr-reader session)
    (cadr-core:stop-thread-for-cleanup (spawn-session-stderr-reader session) :timeout 1d0)))

(defun spawn-note-log (connection text)
  (let ((hook (spawn-connection-on-log connection)))
    (when (and hook (plusp (length text)))
      (funcall hook text))))

(defun buffer-compact (session)
  (let ((start (spawn-session-start session))
        (buffer (spawn-session-buffer session)))
    (when (> start 0)
      (replace buffer buffer :start2 start :end2 (fill-pointer buffer))
      (decf (fill-pointer buffer) start)
      (setf (spawn-session-start session) 0))))

(defun buffer-find (session marker)
  (search marker (spawn-session-buffer session) :start2 (spawn-session-start session)))

(defun spawn-consume (session end)
  (setf (spawn-session-start session) end)
  (when (> (spawn-session-start session) (* 1024 1024))
    (buffer-compact session)))

(defun spawn-dispatch (connection session kind id json payload)
  (declare (ignore connection))
  (let ((box (sb-thread:with-mutex ((spawn-session-lock session))
               (gethash id (spawn-session-pending session)))))
    (unless box
      (return-from spawn-dispatch nil))
    (cond
      ((= kind +event+)
       (let ((hook (mailbox-events box)))
         (when hook (funcall hook json payload))))
      ((or (= kind +result+) (= kind +error+))
       (sb-thread:with-mutex ((spawn-session-lock session))
         (remhash id (spawn-session-pending session)))
       (sb-thread:with-mutex ((mailbox-lock box))
         (if (= kind +result+)
             (setf (mailbox-result box) (cons json payload))
             (setf (mailbox-failure box)
                   (make-condition 'remote-error
                                   :code (let ((code (json-get json "code")))
                                           (if (stringp code) code "unknown"))
                                   :message (let ((message (json-get json "message")))
                                              (if (stringp message) message "Remote operation failed"))
                                   :path (let ((path (json-get json "path")))
                                           (when (stringp path) path)))))
         (setf (mailbox-done box) t)
         (sb-thread:condition-broadcast (mailbox-wait box)))))))

(defun spawn-drain (connection session)
  (let ((marker (utf8-bytes (concatenate 'string (wire-literal :banner)
                                         (spawn-session-token session)
                                         (string #\Newline)))))
    (unless (spawn-session-synced session)
      (let ((index (buffer-find session marker)))
        (cond
          (index
           (let* ((buffer (spawn-session-buffer session))
                  (start (spawn-session-start session))
                  (noise (utf8-string buffer :start start :end index)))
             (spawn-note-log connection (string-trim '(#\Space #\Newline #\Return #\Tab) noise)))
           (spawn-consume session (+ index (length marker)))
           (setf (spawn-session-synced session) t))
          ((> (- (fill-pointer (spawn-session-buffer session)) (spawn-session-start session))
              (+ (* 1024 1024) (length marker)))
           (spawn-consume session (- (fill-pointer (spawn-session-buffer session)) (length marker)))))))
    (loop while (and (spawn-session-live session) (spawn-session-synced session))
          do (let* ((buffer (spawn-session-buffer session))
                    (start (spawn-session-start session))
                    (available (- (fill-pointer buffer) start)))
               (unless (>= available 4)
                 (return))
               (let ((length (be-u32 buffer start)))
                 (unless (<= 9 length +max-frame+)
                   (spawn-teardown connection session
                                   (make-condition 'remote-error
                                                   :code "unknown"
                                                   :message "Corrupt frame from pi-env"
                                                   :lost t))
                   (return))
                 (unless (>= available (+ 4 length))
                   (return))
                 (let* ((body-start (+ start 4))
                        (kind (aref buffer body-start))
                        (id (be-u32 buffer (+ body-start 1)))
                        (json-length (be-u32 buffer (+ body-start 5))))
                   (unless (<= (+ 9 json-length) length)
                     (spawn-teardown connection session
                                     (make-condition 'remote-error
                                                     :code "unknown"
                                                     :message "Corrupt frame from pi-env"
                                                     :lost t))
                     (return))
                   (let ((json (if (zerop json-length)
                                   (empty-json)
                                   (handler-case
                                       (parse-json-or-null
                                        (subseq buffer (+ body-start 9)
                                                (+ body-start 9 json-length)))
                                     (error () :corrupt))))
                         (payload (subseq buffer (+ body-start 9 json-length)
                                          (+ start 4 length))))
                     (spawn-consume session (+ start 4 length))
                     (if (eq json :corrupt)
                         (progn
                           (spawn-teardown connection session
                                           (make-condition 'remote-error
                                                           :code "unknown"
                                                           :message "Corrupt frame from pi-env"
                                                           :lost t))
                           (return))
                         (spawn-dispatch connection session kind id json payload)))))))))

(defun read-available (stream chunk)
  "One read of whatever bytes are already buffered.
`read-sequence` waits for the whole vector, and `sb-sys:read-n-bytes` from a
thread other than the one that created the stream does not return a short read."
  (multiple-value-bind (count errno)
      (sb-unix:unix-read (sb-sys:fd-stream-fd stream) (sb-sys:vector-sap chunk) (length chunk))
    (declare (ignore errno))
    (or count 0)))

(defun spawn-read-loop (connection session)
  (let ((chunk (make-array 65536 :element-type '(unsigned-byte 8))))
    (loop while (spawn-session-live session)
          for count = (handler-case
                          (read-available (spawn-session-output session) chunk)
                        (error () 0))
          while (plusp count)
          do (setf (spawn-session-last-seen session) (get-internal-real-time))
             (sb-thread:with-mutex ((spawn-session-lock session))
               (loop for index below count
                     do (vector-push-extend (aref chunk index) (spawn-session-buffer session))))
             (spawn-drain connection session)))
  (spawn-teardown connection session
                  (make-condition 'remote-error
                                  :code "unknown"
                                  :message "pi-env connection lost"
                                  :lost t)))

(defun spawn-stderr-loop (connection stream)
  (loop for line = (handler-case (read-line stream nil nil) (error () nil))
        while line
        do (spawn-note-log connection (concatenate 'string line (string #\Newline)))))

(defun spawn-ping-loop (connection session)
  (loop while (spawn-session-live session)
        do (sleep +ping-seconds+)
           (when (spawn-session-live session)
             (spawn-write-frame session (make-frame +ping+ 0 (empty-json)))
             (when (> (- (get-internal-real-time) (spawn-session-last-seen session))
                      (* +silence-limit-seconds+ internal-time-units-per-second))
               (spawn-teardown connection session
                               (make-condition 'remote-error
                                               :code "unknown"
                                               :message "pi-env connection timed out"
                                               :lost t))))))

(defun spawn-random-token ()
  (with-output-to-string (out)
    (dotimes (i 16)
      (format out "~(~2,'0x~)" (random 256)))))

(defun spawn-command-list (connection)
  (let ((command (spawn-connection-command connection)))
    (if (functionp command)
        (funcall command)
        command)))

(defun spawn-start (connection)
  (when (spawn-connection-closed connection)
    (remote-lost "Connection closed"))
  (let (argv)
    (handler-case
        (setf argv (spawn-command-list connection))
      (remote-error (condition) (error condition))
      (error (condition)
        (error 'remote-error :code "spawn_error"
               :message (princ-to-string condition)
               :lost t)))
    (unless (and (consp argv) (stringp (first argv)))
      (error 'remote-error :code "spawn_error" :message "No daemon command" :lost t))
    (let* ((token (spawn-random-token))
           (program (first argv))
           (args (append (rest argv) (list "serve" "--token" token)))
           (process (handler-case
                        (sb-ext:run-program program args
                                            :wait nil
                                            :search t
                                            :input :stream
                                            :output :stream
                                            :error :stream)
                      (error (condition)
                        (error 'remote-error :code "spawn_error"
                               :message (princ-to-string condition)
                               :lost t))))
           (session (make-spawn-session
                     :id (incf (spawn-connection-sessions connection))
                     :process process
                     :input (spawn-binary-stream (sb-ext:process-input process) :output)
                     :output (spawn-binary-stream (sb-ext:process-output process) :input)
                     :token token)))
      (setf (spawn-connection-session connection) session)
      (setf (spawn-session-stderr-reader session)
            (sb-thread:make-thread
             (lambda () (spawn-stderr-loop connection (sb-ext:process-error process)))
             :name "env-spawn-stderr"))
      (setf (spawn-session-reader session)
            (sb-thread:make-thread
             (lambda () (spawn-read-loop connection session))
             :name "env-spawn-reader"))
      (setf (spawn-session-ping session)
            (sb-thread:make-thread
             (lambda () (spawn-ping-loop connection session))
             :name "env-spawn-ping"))
      session)))

(defun spawn-connect (connection)
  (let (start)
    (sb-thread:with-mutex ((spawn-connection-lock connection))
      (loop
        (when (spawn-connection-closed connection)
          (remote-lost "Connection closed"))
        (let ((session (spawn-connection-session connection)))
          (when (and session (spawn-session-live session))
            (return-from spawn-connect session)))
        (cond
          ((spawn-connection-starting connection)
           (sb-thread:condition-wait (spawn-connection-wait connection)
                                     (spawn-connection-lock connection)))
          (t
           (setf (spawn-connection-starting connection) t
                 start t)
           (return)))))
    (when start
      (handler-case
          (let ((session (spawn-start connection)))
            (let ((hello (spawn-request-on-session
                          connection session "hello"
                          (json-object "protocol" +protocol-version+)
                          :timeout +start-timeout-seconds+)))
              (unless (eql (json-get hello "protocol") +protocol-version+)
                (remote-lost (format nil "Unsupported protocol ~A" (json-get hello "protocol"))))
              (setf (spawn-session-info session) hello))
            (sb-thread:with-mutex ((spawn-connection-lock connection))
              (setf (spawn-connection-starting connection) nil)
              (sb-thread:condition-broadcast (spawn-connection-wait connection)))
            session)
        (error (condition)
          (let ((session (spawn-connection-session connection)))
            (when session
              (spawn-teardown connection session condition)))
          (sb-thread:with-mutex ((spawn-connection-lock connection))
            (setf (spawn-connection-starting connection) nil
                  (spawn-connection-session connection) nil)
            (sb-thread:condition-broadcast (spawn-connection-wait connection)))
          (error condition))))))

(defun spawn-kill (connection id session-id)
  (let ((current (spawn-connection-session connection)))
    (when (and current (spawn-session-live current)
               (eql (spawn-session-id current) session-id))
      (spawn-write-frame current (make-frame +cancel+ id (json-object "mode" "kill"))))))

(defun spawn-request-on-session (connection session op json &key payload on-event abort timeout on-start)
  (unless (spawn-session-live session)
    (remote-lost "pi-env connection lost"))
  (let ((box (make-mailbox))
        (id (incf (spawn-connection-next-id connection)))
        (body (json-object))
        (deadline (when timeout
                   (+ (get-internal-real-time)
                      (* timeout internal-time-units-per-second))))
        (cancel-sent (env-abort-p abort)))
    (maphash (lambda (key value) (json-put body key value)) json)
    (json-put body "op" op)
    (setf (mailbox-events box) on-event)
    (sb-thread:with-mutex ((spawn-session-lock session))
      (setf (gethash id (spawn-session-pending session)) box))
    (spawn-write-frame session (make-frame +request+ id body (or payload #())))
    (when on-start
      (funcall on-start id (spawn-session-id session)))
    (when cancel-sent
      (spawn-write-frame session (make-frame +cancel+ id (empty-json))))
    (loop
      (let ((done (sb-thread:with-mutex ((mailbox-lock box)) (mailbox-done box))))
        (when done (return)))
      (when (and (env-abort-p abort) (not cancel-sent))
        (setf cancel-sent t)
        (spawn-write-frame session (make-frame +cancel+ id (empty-json))))
      (when (and deadline (> (get-internal-real-time) deadline))
        (spawn-teardown connection session
                        (make-condition 'remote-error
                                        :code "unknown"
                                        :message (format nil "pi-env did not answer within ~A s" timeout)
                                        :lost t)))
      (sb-thread:with-mutex ((mailbox-lock box))
        (unless (mailbox-done box)
          (sb-thread:condition-wait (mailbox-wait box) (mailbox-lock box) :timeout 0.05))))
    (when (mailbox-failure box)
      (error (mailbox-failure box)))
    (values (car (mailbox-result box)) (cdr (mailbox-result box)))))

(defun spawn-request (connection op json &key payload on-event abort session on-start)
  (if session
      (let ((current (spawn-connection-session connection)))
        (unless (and current (spawn-session-live current)
                     (eql (spawn-session-id current) session))
          (remote-lost "pi-env connection lost"))
        (spawn-request-on-session connection current op json
                                  :payload payload :on-event on-event :abort abort
                                  :on-start on-start))
      (let ((current (spawn-connect connection)))
        (spawn-request-on-session connection current op json
                                  :payload payload :on-event on-event :abort abort
                                  :on-start on-start))))

(defun spawn-info (connection)
  (spawn-session-info (spawn-connect connection)))

(defun spawn-close (connection)
  (setf (spawn-connection-closed connection) t)
  (let ((session (spawn-connection-session connection)))
    (when session
      (spawn-teardown connection session
                      (make-condition 'remote-error
                                      :code "unknown"
                                      :message "Connection closed")))))

(defun spawn-session-id-of (connection)
  (let ((session (spawn-connection-session connection)))
    (when session (spawn-session-id session))))
