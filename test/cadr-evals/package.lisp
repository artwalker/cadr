(defpackage #:cadr-evals/tests
  (:use #:cl #:fiveam)
  (:export #:run-tests))

(in-package #:cadr-evals/tests)

(def-suite cadr-evals-suite)
(in-suite cadr-evals-suite)

(defun run-tests ()
  (run! 'cadr-evals-suite))
