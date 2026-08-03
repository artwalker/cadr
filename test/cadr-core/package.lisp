(defpackage #:cadr-core/tests
  (:use #:cl #:fiveam)
  (:export #:run-tests))

(in-package #:cadr-core/tests)

(def-suite cadr-core-suite)
(in-suite cadr-core-suite)

(defun run-tests ()
  (let ((result (run 'cadr-core-suite)))
    (explain! result)
    (results-status result)))
