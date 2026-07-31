(defpackage #:cadr-storage/tests
  (:use #:cl #:fiveam)
  (:export #:run-tests))

(in-package #:cadr-storage/tests)

(def-suite cadr-storage-suite)
(in-suite cadr-storage-suite)

(defun run-tests ()
  (run! 'cadr-storage-suite))
