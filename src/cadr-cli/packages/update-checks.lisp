(in-package #:cadr-cli)

;;; Background package update checks: process-group isolation, git
;;; runner plumbing, and the candidate scan.  Split from
;;; packages/commands.lisp to keep both under the organization gate's
;;; reviewed size band; ownership unchanged (same package).

(defun package-update-check-group-path ()
  (merge-pathnames
   (format nil "cadr-package-update-~D-~D.pgid"
           (get-universal-time)
           (random most-positive-fixnum))
   (uiop:temporary-directory)))

(defun package-update-check-process-argv
    (argv group-path)
  (if (or (uiop:os-windows-p)
          (not (probe-file "/usr/bin/setsid")))
      argv
      (append
       (list
        "/usr/bin/setsid" "--fork" "--wait"
        "/bin/sh" "-c"
        "group_path=$1; shift; printf '%s' \"$$\" > \"$group_path\"; exec \"$@\""
        "cadr-package-update-check"
        (namestring group-path))
       argv)))

(defun package-update-check-environment ()
  (let ((prompt-prefix "GIT_TERMINAL_PROMPT="))
    (cons
     "GIT_TERMINAL_PROMPT=0"
     (remove-if
      (lambda (entry)
        (uiop:string-prefix-p prompt-prefix entry))
      #+sbcl (sb-ext:posix-environ)
      #-sbcl nil))))

(defun stop-package-update-check-process
    (process group-path)
  (when process
    (let* ((group-id
             (and group-path
                  (probe-file group-path)
                  (ignore-errors
                    (parse-integer
                     (uiop:read-file-string group-path)
                     :junk-allowed t))))
           (pid
             (ignore-errors
               (uiop:process-info-pid process))))
      (if pid
          (kill-process-tree (or group-id pid))
          (ignore-errors
            (uiop:terminate-process process :urgent t))))
    (ignore-errors
      (uiop:wait-process process)))
  nil)

(defun default-package-update-check-runner
    (argv
     &key
       (timeout-seconds 10)
       (clock #'get-internal-real-time))
  (let* ((group-path
           (and (not (uiop:os-windows-p))
                (probe-file "/usr/bin/setsid")
                (package-update-check-group-path)))
         (process
           (uiop:launch-program
            (package-update-check-process-argv
             argv group-path)
            :environment
            (package-update-check-environment)
            :output :stream
            ;; UIOP defines NIL as the platform null device. Keep git and
            ;; transport diagnostics out of every user-visible stream.
            :error-output nil))
         (output-stream
           (uiop:process-info-output process))
         (deadline
           (+ (funcall clock)
              (* timeout-seconds
                 internal-time-units-per-second)))
         (completed-p nil))
    (unwind-protect
         (progn
           (loop while (uiop:process-alive-p process)
                 do
                 (when (>= (funcall clock)
                           deadline)
                   (stop-package-update-check-process
                    process group-path)
                   (error "Package update check timed out"))
                 (sleep 0.01d0))
           (let ((output
                   (with-output-to-string (stream)
                     (loop for line =
                             (read-line output-stream nil nil)
                           while line
                           do (write-line line stream))))
                 (status (uiop:wait-process process)))
             (setf completed-p t)
             (unless (zerop (or status 1))
               (error "Package update check command failed"))
             output))
      (when (and (not completed-p)
                 (ignore-errors
                   (uiop:process-alive-p process)))
        (stop-package-update-check-process
         process group-path))
      (when output-stream
        (ignore-errors
          (close output-stream)))
      (when (and group-path
                 (probe-file group-path))
        (ignore-errors
          (delete-file group-path))))))

(defun package-update-git-output
    (runner path &rest arguments)
  (funcall
   runner
   (append
    (list "git" "-C" (namestring path))
    arguments)))

(defun package-update-remote-ref (runner path)
  (let ((upstream
          (ignore-errors
            (string-trim
             '(#\Space #\Tab #\Newline #\Return)
             (package-update-git-output
              runner path
              "rev-parse" "--abbrev-ref"
              "@{upstream}")))))
    (if (and upstream
             (uiop:string-prefix-p
              "origin/" upstream)
             (> (length upstream)
                (length "origin/")))
        (format nil "refs/heads/~A"
                (subseq upstream
                        (length "origin/")))
        nil)))

(defun package-update-git-object-id (output)
  (let* ((trimmed
           (string-trim
            '(#\Space #\Tab #\Newline #\Return)
            output))
         (end
           (or (position-if
                (lambda (character)
                  (member character
                          '(#\Space #\Tab #\Newline #\Return)))
                trimmed)
               (length trimmed)))
         (object-id (subseq trimmed 0 end)))
    (and (= 40 (length object-id))
         (every
          (lambda (character)
            (digit-char-p character 16))
          object-id)
         (string-downcase object-id))))

(defun package-git-update-available-p
    (record runner)
  (let* ((path (getf record :path))
         (local
           (package-update-git-object-id
            (package-update-git-output
             runner path "rev-parse" "HEAD")))
         (remote-ref
           (package-update-remote-ref runner path))
         (remote
           (or
            (and
             remote-ref
             (package-update-git-object-id
              (package-update-git-output
               runner path
               "ls-remote" "origin" remote-ref)))
            ;; Match Pi's Git update contract: an unavailable, empty, or
            ;; malformed upstream ref falls back to the remote default branch.
            (package-update-git-object-id
             (package-update-git-output
              runner path
              "ls-remote" "origin" "HEAD")))))
    (and local remote
         (not (string= local remote)))))

(defun package-update-records-project-first (records)
  (append
   (remove-if-not
    (lambda (record)
      (eq :project (getf record :scope)))
    records)
   (remove-if
    (lambda (record)
      (eq :project (getf record :scope)))
    records)))

(defun package-update-candidate-record-p (record)
  (let ((source (getf record :parsed))
        (path (getf record :path)))
    (and
     (typep source 'package-source)
     (eq :git (package-source-type source))
     (not (package-source-pinned-p source))
     path
     (probe-file path))))

(defun package-update-record-result (record runner)
  (handler-case
      (when (package-git-update-available-p
             record runner)
        (let ((source (getf record :parsed)))
          (format nil "~A/~A"
                  (package-source-host source)
                  (package-source-path source))))
    (condition () nil)))

(defun run-package-update-checks
    (records runner max-concurrency)
  (let* ((items (coerce records 'vector))
         (count (length items)))
    (when (zerop count)
      (return-from run-package-update-checks nil))
    (let ((results (make-array count :initial-element nil))
          (next-index 0)
          (lock
            (sb-thread:make-mutex
             :name "cadr package update scheduler")))
      (labels
          ((claim-index ()
             (sb-thread:with-mutex (lock)
               (when (< next-index count)
                 (prog1 next-index
                   (incf next-index)))))
           (worker ()
             (loop for index = (claim-index)
                   while index
                   do
                   (setf
                    (aref results index)
                    (package-update-record-result
                     (aref items index) runner)))))
        (let ((threads nil)
              (completed-p nil))
          (unwind-protect
               (progn
                 (setf
                  threads
                  (loop
                    repeat
                    (min count
                         (max 1 max-concurrency))
                    collect
                    (sb-thread:make-thread
                     #'worker
                     :name "cadr package update check")))
                 (dolist (thread threads)
                   (cadr-core:join-active-thread
                    thread
                    :reason
                    "Package update results require every bounded worker to finish"))
                 (setf completed-p t)
                 (loop for result across results
                       when result collect result))
            ;; The TUI owns only the outer update-check thread.  If cleanup
            ;; terminates that owner, unwind its lexically owned workers too;
            ;; otherwise their git subprocesses can outlive the session.
            (unless completed-p
              (dolist (thread threads)
                (cadr-core:stop-thread-for-cleanup
                 thread)))))))))

(defun check-for-available-package-updates
    (records
     &key
       (runner #'default-package-update-check-runner)
       (offline-p (offline-mode-p))
       (max-concurrency 4))
  (when offline-p
    (return-from
        check-for-available-package-updates nil))
  (run-package-update-checks
   (remove-if-not
    #'package-update-candidate-record-p
    (package-update-records-project-first records))
   runner max-concurrency))

