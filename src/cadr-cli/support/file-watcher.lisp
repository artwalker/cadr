(in-package #:cadr-cli)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-posix))

(defparameter +fs-watch-retry-delay-milliseconds+ 5000)

(defstruct (file-watcher (:constructor %make-file-watcher))
  path listener on-error signature thread
  (closed-p nil :type boolean)
  (poll-interval 0.1d0 :type real)
  (lock (sb-thread:make-mutex :name "cadr-file-watcher"))
  (waitqueue (sb-thread:make-waitqueue :name "cadr-file-watcher")))

(defun watched-path-signature (path)
  (handler-case
      (let ((st (sb-posix:stat (namestring path))))
        (list (sb-posix:stat-mtime st) (sb-posix:stat-size st)))
    (sb-posix:syscall-error ()
      nil)))

(defun close-watcher (watcher)
  (when watcher
    (sb-thread:with-mutex ((file-watcher-lock watcher))
      (setf (file-watcher-closed-p watcher) t)
      (sb-thread:condition-broadcast (file-watcher-waitqueue watcher)))
    (let ((thread (file-watcher-thread watcher)))
      (when (and thread
                 (not (eq thread sb-thread:*current-thread*)))
        (stop-thread-for-cleanup thread))))
  nil)

(defun poll-file-watcher-once (watcher)
  (handler-case
      (let ((next (watched-path-signature (file-watcher-path watcher))))
        (unless (equal next (file-watcher-signature watcher))
          (setf (file-watcher-signature watcher) next)
          (funcall (file-watcher-listener watcher)
                   :change (file-watcher-path watcher))
          t))
    (error ()
      (funcall (file-watcher-on-error watcher))
      nil)))

(defun watch-with-error-handler (path listener on-error &key (poll-interval 0.1d0))
  (handler-case
      (let* ((watcher
               (%make-file-watcher
                :path path :listener listener :on-error on-error
                :signature (watched-path-signature path)
                :poll-interval poll-interval))
             (thread
               (sb-thread:make-thread
                (lambda ()
                  (loop
                    (sb-thread:with-mutex ((file-watcher-lock watcher))
                      (when (file-watcher-closed-p watcher)
                        (return))
                      (sb-thread:condition-wait
                       (file-watcher-waitqueue watcher)
                       (file-watcher-lock watcher)
                       :timeout (file-watcher-poll-interval watcher)))
                    (when (file-watcher-closed-p watcher)
                      (return))
                    (poll-file-watcher-once watcher)))
                :name "cadr-file-watcher")))
        (setf (file-watcher-thread watcher) thread)
        watcher)
    (error ()
      (funcall on-error)
      nil)))
