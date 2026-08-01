(defpackage #:cadr-ai/live-tests
  (:use #:cl #:fiveam))

(in-package #:cadr-ai/live-tests)

(def-suite cadr-ai-live-suite)
(in-suite cadr-ai-live-suite)

(defun first-text (message)
  (let ((block
          (find-if
           (lambda (item)
             (typep item 'cadr-ai:text-content))
           (cadr-ai:assistant-message-content message))))
    (and block
         (cadr-ai:text-content-text block))))
