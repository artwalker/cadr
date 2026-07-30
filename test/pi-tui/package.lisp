(defpackage #:pi-tui/tests
  (:use #:cl #:fiveam)
  (:export #:run-tests))

(in-package #:pi-tui/tests)

(def-suite pi-tui-suite)
(in-suite pi-tui-suite)

(defun run-tests ()
  (run! 'pi-tui-suite))
