(defpackage #:cadr-server/tests
  (:use #:cl #:fiveam)
  (:export #:run-tests))

(in-package #:cadr-server/tests)

(def-suite cadr-server-suite)
(in-suite cadr-server-suite)

(defun run-tests ()
  (run! 'cadr-server-suite))
