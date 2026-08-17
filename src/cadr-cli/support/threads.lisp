(in-package #:cadr-cli)

(defun stop-thread-for-cleanup (thread &rest args)
  ;; cadr-core:stop-thread-for-cleanup owns 0.5d0/t
  ;; (src/cadr-core/threads.lisp:4). This is the package entry, not a
  ;; second policy.
  (apply #'cadr-core:stop-thread-for-cleanup thread args))
