(defstruct doom-engine
  process
  input
  output
  error-output
  (frame '("DOOM runtime is starting…") :type list)
  lock
  reader-thread
  error-thread
  (running-p nil :type boolean))

(defun doom-runtime-command ()
  (let ((configured (uiop:getenv "CADR_DOOM_RUNNER")))
    (if configured
        (list configured)
        (list
         (example-program-path "node")
         (namestring
          (merge-pathnames "cadr-doom-runner.mjs" *load-truename*))))))

(defun doom-drain-errors (engine)
  (lambda ()
    (ignore-errors
      (loop for line = (read-line (doom-engine-error-output engine) nil nil)
            while line))))

(defun start-doom-engine (wasm wad request-render)
  (let* ((command (doom-runtime-command))
         (process
           (uiop:launch-program
            (append command
                    (list "--wasm" (namestring wasm)
                          "--wad" (namestring wad) "--fps" "35"
                          "--format" "ansi-lines"))
            :input :stream :output :stream :error-output :stream))
         (engine
           (make-doom-engine
            :process process
            :input (uiop:process-info-input process)
            :output (uiop:process-info-output process)
            :error-output (uiop:process-info-error-output process)
            :lock (sb-thread:make-mutex :name "cadr doom frame")
            :running-p t)))
    (setf
     (doom-engine-error-thread engine)
     (sb-thread:make-thread
      (doom-drain-errors engine)
      :name "cadr doom diagnostic drain"))
    (setf
     (doom-engine-reader-thread engine)
     (sb-thread:make-thread
      (lambda ()
        (unwind-protect
             (loop while (and (doom-engine-running-p engine)
                              (uiop:process-alive-p process))
                   for line = (read-line (doom-engine-output engine) nil nil)
                   while line
                   do
                   (let ((lines (uiop:split-string line :separator '(#\Page))))
                     (sb-thread:with-mutex ((doom-engine-lock engine))
                       (setf (doom-engine-frame engine) lines))
                     (funcall request-render)))
          (setf (doom-engine-running-p engine) nil)))
      :name "cadr doom 35fps frame reader"))
    engine))

(defun doom-engine-current-frame (engine)
  (sb-thread:with-mutex ((doom-engine-lock engine))
    (copy-list (doom-engine-frame engine))))

(defun doom-engine-key (engine key down-p)
  (when (and (doom-engine-running-p engine) key)
    (format (doom-engine-input engine) "KEY ~D ~D~%" key (if down-p 1 0))
    (finish-output (doom-engine-input engine))))

(defun stop-doom-engine (engine)
  (when engine
    (setf (doom-engine-running-p engine) nil)
    (when (and (doom-engine-process engine)
               (uiop:process-alive-p (doom-engine-process engine)))
      (uiop:terminate-process (doom-engine-process engine)))
    (dolist (thread
             (list (doom-engine-reader-thread engine)
                   (doom-engine-error-thread engine)))
      (when (and thread
                 (sb-thread:thread-alive-p thread)
                 (not (eq thread sb-thread:*current-thread*)))
        (ignore-errors (sb-thread:join-thread thread)))))
  nil)
