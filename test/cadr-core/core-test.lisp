(in-package #:cadr-core/tests)

(in-suite cadr-core-suite)

(defstruct goal14-redacted-fixture
  secret
  visible)

(cadr-core:define-redacted-print-object
    (goal14-redacted-fixture value stream)
  (format stream ":visible ~A :secret [REDACTED]"
          (goal14-redacted-fixture-visible value)))

(defun goal14-source-files (directory)
  (append
   (uiop:directory-files directory "*.lisp")
   (mapcan #'goal14-source-files
           (uiop:subdirectories directory))))

(defun goal14-count-substring (needle haystack)
  (loop with start = 0
        for position = (search needle haystack :start2 start)
        while position
        count 1
        do (setf start (+ position (length needle)))))

(defmacro with-core-temporary-directory ((directory) &body body)
  `(let* ((base
            (uiop:ensure-directory-pathname
             (uiop:temporary-directory)))
          (,directory
            (merge-pathnames
             (format nil "cadr-core-~36R/"
                     (random most-positive-fixnum))
             base)))
     (ensure-directories-exist
      (merge-pathnames "anchor" ,directory))
     (unwind-protect
          (progn ,@body)
       (uiop:delete-directory-tree
        ,directory
        :validate t
        :if-does-not-exist :ignore))))

(test bounded-cleanup-has-one-owner-and-active-joins-require-a-reason
  (is (eq :absent
          (cadr-core:stop-thread-for-cleanup nil)))
  (is (eq :current
          (cadr-core:stop-thread-for-cleanup
           sb-thread:*current-thread*)))
  (signals error
    (cadr-core:join-active-thread
     (sb-thread:make-thread (lambda () :done))))
  (let ((started (sb-thread:make-semaphore :count 0))
        (release (sb-thread:make-semaphore :count 0)))
    (let ((thread
            (sb-thread:make-thread
             (lambda ()
               (sb-thread:signal-semaphore started)
               (sb-thread:wait-on-semaphore release)
               :done))))
      (is (sb-thread:wait-on-semaphore started :timeout 2))
      (sb-thread:signal-semaphore release)
      (is (eq :done
              (cadr-core:join-active-thread
               thread :reason "test result synchronization")))))
  (let ((started (sb-thread:make-semaphore :count 0))
        (never (sb-thread:make-semaphore :count 0)))
    (let ((thread
            (sb-thread:make-thread
             (lambda ()
               (sb-thread:signal-semaphore started)
               (sb-thread:wait-on-semaphore never)))))
      (is (sb-thread:wait-on-semaphore started :timeout 2))
      (is (eq :terminated
              (cadr-core:stop-thread-for-cleanup
               thread :timeout 0.01d0))))))

(test cancellation-state-is-local-external-waitable-and-thread-safe
  (let* ((external-p nil)
         (state
           (cadr-core:make-cancellation-state
            :aborted-function (lambda () external-p))))
    (is (not (cadr-core:cancellation-aborted-p state)))
    (setf external-p t)
    (is (cadr-core:cancellation-aborted-p state))
    (setf external-p nil)
    (let ((waiting (sb-thread:make-semaphore :count 0))
          (result nil))
      (let ((thread
              (sb-thread:make-thread
               (lambda ()
                 (sb-thread:signal-semaphore waiting)
                 (setf result
                       (cadr-core:wait-for-cancellation
                        state :timeout 2d0))))))
        (is (sb-thread:wait-on-semaphore waiting :timeout 2))
        (cadr-core:abort-cancellation state)
        (is (eq :aborted
                (cadr-core:join-active-thread
                 thread :reason "observe cancellation result")))
        (is (eq :aborted result))))
    (cadr-core:set-cancellation-aborted-p state nil)
    (is (not (cadr-core:cancellation-aborted-p state)))))

(test atomic-replacement-preserves-old-content-on-error-and-private-mode
  (with-core-temporary-directory (directory)
    (let ((path (merge-pathnames "state.json" directory)))
      (cadr-core:atomic-write-string
       path "old" :mode #o600 :durability :flush)
      (is (string= "old" (uiop:read-file-string path)))
      (is (= #o600
             (logand #o777
                     (sb-posix:stat-mode
                      (sb-posix:stat path)))))
      (signals error
        (cadr-core:call-with-atomic-replacement
         path
         (lambda (temporary)
           (with-open-file
               (stream temporary :direction :output
                :if-exists :error :if-does-not-exist :create)
             (write-string "new" stream))
           (error "forced failure"))
         :mode #o600 :durability :flush))
      (is (string= "old" (uiop:read-file-string path)))
      (is (= 1 (length (uiop:directory-files directory))))
      (cadr-core:append-string-to-file
       path "+tail" :mode #o600 :durability :flush)
      (is (string= "old+tail" (uiop:read-file-string path))))))

(test redacted-object-declaration-registers-type-and-never-prints-secret
  (let* ((secret "GOAL14-SECRET-SENTINEL")
         (value
           (make-goal14-redacted-fixture
            :secret secret :visible "safe"))
         (printed (prin1-to-string value)))
    (is (search "safe" printed))
    (is (search "[REDACTED]" printed))
    (is (not (search secret printed)))
    (is (member 'goal14-redacted-fixture
                (cadr-core:redacted-object-types)))))

(test utc-time-primitives-match-fixed-baseline-vectors
  (is (= 0 (cadr-core:iso8601-to-milliseconds
            "1970-01-01T00:00:00.000Z")))
  (is (string=
       "1970-01-01T00:00:00.000Z"
       (cadr-core:milliseconds-to-utc-iso8601 0)))
  (is (string=
       "1970-01-01T00:00:00Z"
       (cadr-core:milliseconds-to-utc-iso8601
        999 :fraction-digits 0)))
  (is (string=
       "2026-08-03T12:34:56.789Z"
       (cadr-core:milliseconds-to-utc-iso8601
        1785760496789))))

(test production-cleanup-joins-cannot-bypass-cadr-core
  (let* ((root (asdf:system-source-directory "cadr-core"))
         (source-root (merge-pathnames "src/" root))
         (owner (truename
                 (merge-pathnames
                  "src/cadr-core/threads.lisp" root)))
         (violations nil))
    (dolist (path (goal14-source-files source-root))
      (unless (equal (truename path) owner)
        (let ((source (uiop:read-file-string path)))
          (when (search "(sb-thread:join-thread" source)
            (push (enough-namestring path root) violations)))))
    (is (null violations)
        "raw production join-thread calls: ~S"
        (nreverse violations))))

(test atomic-replacement-and-secret-printers-have-one-policy-owner
  (let* ((root (asdf:system-source-directory "cadr-core"))
         (source-root (merge-pathnames "src/" root))
         (atomic-owner
           (truename
            (merge-pathnames
             "src/cadr-core/atomic-file.lisp" root)))
         (printer-owner
           (truename
            (merge-pathnames
             "src/cadr-core/redacted-print.lisp" root)))
         (atomic-violations nil)
         (printer-violations nil))
    (dolist (path (goal14-source-files source-root))
      (let ((source (uiop:read-file-string path)))
        (when (and
               (not (equal (truename path) atomic-owner))
               (search "rename-file-overwriting-target" source))
          (push (enough-namestring path root)
                atomic-violations))
        (when (and
               (not (equal (truename path) printer-owner))
               (search "(defmethod print-object" source))
          (push (enough-namestring path root)
                printer-violations))))
    (is (null atomic-violations)
        "handwritten atomic replacements: ~S"
        (nreverse atomic-violations))
    (is (null printer-violations)
        "handwritten secret printers: ~S"
        (nreverse printer-violations))))

(test standalone-tui-harness-loads-cadr-core-before-its-consumer
  (let* ((root (asdf:system-source-directory "cadr-core"))
         (harnesses
           '("scripts/goal5-manual-tui.sh"
             "scripts/goal9-a2-pty-driver.py")))
    (dolist (relative harnesses)
      (let* ((source
               (uiop:read-file-string
                (merge-pathnames relative root)))
             (core (search "cadr-core" source))
             (tui (search "cadr-tui" source)))
        (is (not (null core)) "~A omits cadr-core" relative)
        (is (not (null tui)) "~A omits cadr-tui" relative)
        (is (< core tui) "~A loads cadr-core after cadr-tui" relative)))))
