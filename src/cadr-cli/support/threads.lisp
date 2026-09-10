(in-package #:cadr-cli)

(defun stop-thread-for-cleanup (thread &rest args)
  (declare (dynamic-extent args))
  (cond
    ((null thread) :absent)
    ((eq thread sb-thread:*current-thread*) :current)
    (t (apply #'cadr-core:stop-thread-for-cleanup thread args))))
