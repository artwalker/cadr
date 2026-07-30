(defpackage #:cadr-tui/tests
  (:use #:cl #:fiveam)
  (:export #:run-tests))

(in-package #:cadr-tui/tests)

(def-suite cadr-tui-suite)
(in-suite cadr-tui-suite)

(defun run-tests ()
  (run! 'cadr-tui-suite))
