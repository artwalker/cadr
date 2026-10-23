(defpackage #:cadr-env/tests
  (:use #:cl #:fiveam #:cadr-env)
  (:export #:run-tests))

(in-package #:cadr-env/tests)

(def-suite cadr-env-suite)
(in-suite cadr-env-suite)

(defun run-tests ()
  (let ((result (run 'cadr-env-suite)))
    (explain! result)
    (results-status result)))
