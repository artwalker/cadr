(defpackage #:cadr-protocol/tests
  (:use #:cl #:fiveam)
  (:export #:run-tests))

(in-package #:cadr-protocol/tests)

(def-suite cadr-protocol-suite)
(in-suite cadr-protocol-suite)

(defun run-tests ()
  (run! 'cadr-protocol-suite))
