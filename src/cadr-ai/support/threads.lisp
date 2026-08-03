(in-package #:cadr-ai)

(defun stop-thread-for-cleanup
    (thread &key (timeout 0.5d0) (terminate-p t))
  (cadr-core:stop-thread-for-cleanup
   thread :timeout timeout :terminate-p terminate-p))
