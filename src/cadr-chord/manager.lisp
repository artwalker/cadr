(in-package #:cadr-chord)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-bsd-sockets)
  (require :sb-md5)
  (require :sb-posix))

(defvar *locks* (make-hash-table :test #'equal))

(defun lock-key (name)
  (with-output-to-string (out)
    (map nil (lambda (byte) (format out "~2,'0x" byte))
         (sb-md5:md5sum-string name))))

(defun process-lock (name)
  (let* ((socket (make-instance 'sb-bsd-sockets:local-abstract-socket :type :stream))
         (address (format nil "chord2-~A" (lock-key name))))
    (handler-case
        (progn
          (sb-bsd-sockets:socket-bind socket address)
          (sb-bsd-sockets:socket-listen socket 1)
          (setf (gethash name *locks*) socket)
          (lambda ()
            (remhash name *locks*)
            (ignore-errors (sb-bsd-sockets:socket-close socket))
            nil))
      (sb-bsd-sockets:address-in-use-error ()
        (ignore-errors (sb-bsd-sockets:socket-close socket))
        (signal-chord "unavailable"
                      (format nil "lock ~A is held by another process" name)
                      :reason "locked")))))

(defun current-pid ()
  (sb-posix:getpid))

(defstruct (driver (:conc-name drv-)) spawn)
(defstruct host-instance pid link process send kill-tree (exit nil))
(defstruct (liveness (:conc-name lv-))
  booting active-calls viewers durable-tasks idle-since)
(defstruct (manager (:conc-name mgr-))
  driver status instance live grace keep-alive check-interval on-exit)

(defun child-environment (extra lock)
  (let ((pairs nil))
    (dolist (pair (sb-ext:posix-environ))
      (unless (and (>= (length pair) 12) (string= pair "CHORD2_LOCK=" :end1 12))
        (push pair pairs)))
    (push (format nil "CL_SOURCE_REGISTRY=~A//"
                  (asdf:system-source-directory "cadr-chord"))
          pairs)
    (when lock
      (push (format nil "CHORD2_LOCK=~A" lock) pairs))
    (dolist (pair extra)
      (push (format nil "~A=~A" (car pair) (cdr pair)) pairs))
    pairs))

(defun kill-process-group (pid)
  (ignore-errors
    (uiop:run-program (list "kill" "-KILL" "--" (format nil "-~A" pid))
                      :ignore-error-status t)))

(defun watch-exit (instance)
  (sb-thread:make-thread
   (lambda ()
     (let ((code (uiop:wait-process (host-instance-process instance))))
       (unless (host-instance-exit instance)
         (setf (host-instance-exit instance)
               (json-object "code" (or code 0)
                            "signal" (if (and code (zerop code)) +json-null+ "SIGKILL"))))))
   :name "chord-child-exit"))

(defun child-loader-path ()
  (namestring (merge-pathnames "src/cadr-chord/child-entry.lisp"
                               (asdf:system-source-directory "cadr-chord"))))

(defun fork-driver (&key init lock env)
  (make-driver
   :spawn
   (lambda ()
     (let* ((process (uiop:launch-program
                      (list "sbcl" "--noinform" "--disable-debugger"
                            "--load" (child-loader-path))
                      :input :stream
                      :output :stream
                      :error-output :stream
                      :environment (child-environment env lock)))
            (link (open-pipe-link process))
            (instance (make-host-instance
                       :pid (uiop:process-info-pid process)
                       :process process
                       :link link
                       :kill-tree (lambda () (kill-process-group (uiop:process-info-pid process))))))
       (setf (host-instance-send instance)
             (lambda (message)
               (link-send link (json-object "chord2control" message))))
       (when init
         (funcall (host-instance-send instance)
                  (json-object "type" "init" "value" init)))
       (watch-exit instance)
       instance))))

(defun instance-exited (instance)
  (loop until (host-instance-exit instance) do (sleep 0.02))
  (host-instance-exit instance))

(defun instance-pid (instance) (host-instance-pid instance))
(defun instance-link (instance) (host-instance-link instance))
(defun instance-send (instance message)
  (funcall (host-instance-send instance) message))
(defun instance-on-control (instance listener)
  (link-on-control (host-instance-link instance) listener))

(defun liveness-booting (liveness) (lv-booting liveness))
(defun liveness-active-calls (liveness) (lv-active-calls liveness))
(defun liveness-viewers (liveness) (lv-viewers liveness))
(defun liveness-durable-tasks (liveness) (lv-durable-tasks liveness))
(defun liveness-idle-for (liveness)
  (let ((since (lv-idle-since liveness)))
    (if (or (lv-booting liveness) (null since))
        0
        (round (* 1000 (/ (- (get-internal-real-time) since)
                          internal-time-units-per-second))))))

(defun create-host-manager (&key driver (grace 5) keep-alive check-interval on-exit)
  (make-manager :driver driver
                :status "stopped"
                :grace grace
                :keep-alive keep-alive
                :check-interval (or check-interval 1)
                :on-exit on-exit
                :live (make-liveness :booting nil :active-calls 0 :viewers 0 :durable-tasks 0)))

(defun manager-status (manager) (mgr-status manager))
(defun (setf manager-status) (value manager) (setf (mgr-status manager) value))
(defun manager-instance (manager) (mgr-instance manager))
(defun (setf manager-instance) (value manager) (setf (mgr-instance manager) value))
(defun manager-liveness (manager) (mgr-live manager))

(defun note-status (manager message)
  (let ((live (mgr-live manager))
        (busy (+ (or (json-get message "activeCalls") 0)
                 (or (json-get message "viewers") 0)
                 (or (json-get message "durableTasks") 0))))
    (setf (lv-active-calls live) (or (json-get message "activeCalls") 0)
          (lv-viewers live) (or (json-get message "viewers") 0)
          (lv-durable-tasks live) (or (json-get message "durableTasks") 0))
    (if (plusp busy)
        (setf (lv-idle-since live) nil)
        (unless (lv-idle-since live)
          (setf (lv-idle-since live) (get-internal-real-time))))))

(defun await-ready (manager instance)
  (let ((started nil)
        (failed nil))
    (instance-on-control
     instance
     (lambda (message)
       (cond
         ((string= (json-get message "type") "ready") (setf started t))
         ((string= (json-get message "type") "fatal")
          (setf failed (make-condition 'chord-error
                                       :code "unavailable"
                                       :reason (let ((reason (json-get message "reason")))
                                                 (if (json-null-p reason) nil reason))
                                       :text (format nil "child failed: ~A" (json-get message "message")))))
         ((string= (json-get message "type") "status")
          (note-status manager message)))))
    (loop until (or started failed (host-instance-exit instance))
          do (sleep 0.02))
    (cond
      (failed
       (funcall (host-instance-kill-tree instance))
       (instance-exited instance)
       (error failed))
      ((not started)
       (error 'chord-error :code "unavailable"
              :text (format nil "child exited before ready (~A)"
                            (json-get (host-instance-exit instance) "code"))))
      (t instance))))

(defun manager-start (manager)
  (when (and (mgr-instance manager) (string= (mgr-status manager) "running"))
    (return-from manager-start (mgr-instance manager)))
  (setf (mgr-status manager) "starting"
        (lv-booting (mgr-live manager)) t
        (lv-active-calls (mgr-live manager)) 0
        (lv-idle-since (mgr-live manager)) nil)
  (handler-case
      (let ((instance (funcall (drv-spawn (mgr-driver manager)))))
        (setf (mgr-instance manager) instance)
        (await-ready manager instance)
        (setf (lv-booting (mgr-live manager)) nil
              (mgr-status manager) "running")
        (unless (lv-idle-since (mgr-live manager))
          (setf (lv-idle-since (mgr-live manager)) (get-internal-real-time)))
        (when (mgr-keep-alive manager)
          (sb-thread:make-thread
           (lambda ()
             (loop while (string= (mgr-status manager) "running")
                   do (sleep (mgr-check-interval manager))
                      (when (and (string= (mgr-status manager) "running")
                                 (not (funcall (mgr-keep-alive manager) (mgr-live manager))))
                        (ignore-errors (manager-stop manager)))))
           :name "chord-keepalive"))
        instance)
    (error (condition)
      (setf (mgr-status manager) "stopped"
            (mgr-instance manager) nil
            (lv-booting (mgr-live manager)) nil)
      (error condition))))

(defun manager-stop (manager)
  (let ((instance (mgr-instance manager)))
    (when instance
      (ignore-errors (instance-send instance (json-object "type" "shutdown")))
      (let ((deadline (+ (get-internal-real-time)
                         (ceiling (* (mgr-grace manager) internal-time-units-per-second)))))
        (loop while (and (uiop:process-alive-p (host-instance-process instance))
                         (< (get-internal-real-time) deadline))
              do (sleep 0.02)))
      (when (uiop:process-alive-p (host-instance-process instance))
        (funcall (host-instance-kill-tree instance))
        (unless (host-instance-exit instance)
          (setf (host-instance-exit instance)
                (json-object "code" +json-null+ "signal" "SIGKILL"))))
      (funcall (host-instance-kill-tree instance))
      (let ((exit (instance-exited instance)))
        (when (mgr-on-exit manager)
          (funcall (mgr-on-exit manager) exit))))
    (setf (mgr-instance manager) nil
          (mgr-status manager) "stopped")
    nil))

(defun manager-replace (manager)
  (manager-stop manager)
  (manager-start manager))

(defun write-control (message)
  (write-line (canonical-json (json-object "chord2control" message)) *standard-output*)
  (finish-output *standard-output*))

(defun echo-contract ()
  (remote-contract "t.echo"
                   :version 1
                   :input (schema-object nil)
                   :host (host-named "w1")
                   :variants (variant-table "main" nil
                                            (member-alist "echo" (make-method-spec :args (schema-string)
                                                                                   :result (schema-string))
                                                          "pid" (make-method-spec :result (schema-integer))))))

(defun read-json-line ()
  (let ((line (read-line *standard-input* nil nil)))
    (when (and line (plusp (length (string-trim '(#\Space #\Tab) line))))
      (parse-json line))))

(defun run-child-host ()
  (ignore-errors (sb-posix:setpgid 0 0))
  (let ((mode (or (uiop:getenv "FIXTURE_MODE") "normal")))
    (when (string= mode "fatal")
      (write-control (json-object "type" "fatal" "message" "fixture refuses to start"))
      (uiop:quit 1))
    (let ((lock-name (uiop:getenv "CHORD2_LOCK")))
      (when lock-name
        (handler-case (process-lock lock-name)
          (error (condition)
            (write-control (json-object "type" "fatal"
                                        "message" (princ-to-string condition)
                                        "reason" (if (typep condition 'chord-error)
                                                     (or (chord-error-reason condition) +json-null+)
                                                     +json-null+)))
            (uiop:quit 1)))))
    (let ((host (create-host :name (or (uiop:getenv "HOST_NAME") "worker")))
          (init nil))
      (loop until init
            for frame = (read-json-line)
            while frame
            do (let ((control (json-get frame "chord2control")))
                 (when (and control (string= (json-get control "type") "init"))
                   (setf init (json-get control "value")))))
      (let ((greeting (json-get init "greeting")))
        (host-serve host (echo-contract)
                    (lambda (input principal self)
                      (declare (ignore input principal self))
                      (list (cons "echo"
                                  (lambda (text)
                                    (format nil "~A ~A from ~A" greeting text (current-pid))))
                            (cons "pid" (lambda () (current-pid)))))))
      (let ((link (make-stdio-link)))
        (host-connect host link :principal (json-object "kind" "server"))
        (when (uiop:getenv "GRANDCHILD_FILE")
          (let ((grandchild (uiop:launch-program '("sleep" "60"))))
            (with-open-file (out (uiop:getenv "GRANDCHILD_FILE")
                                 :direction :output :if-exists :supersede)
              (format out "~A" (uiop:process-info-pid grandchild)))))
        (write-control (json-object "type" "ready"))
        (loop for frame = (read-json-line)
              while frame
              do (let ((control (json-get frame "chord2control")))
                   (cond
                     ((and control (string= (json-get control "type") "shutdown"))
                      (unless (string= mode "ignore-shutdown")
                        (host-close host)
                        (uiop:quit 0)))
                     ((not control)
                      (stdio-link-dispatch link frame)))))))))
