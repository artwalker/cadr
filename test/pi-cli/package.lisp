(defpackage #:pi-cli/tests
  (:use #:cl #:fiveam)
  (:import-from #:pi-cli
                #:make-bash-tool
                #:make-edit-tool
                #:make-glob-tool
                #:make-grep-tool
                #:make-read-tool
                #:make-write-tool
                #:run-repl)
  (:export #:run-tests))

(in-package #:pi-cli/tests)

(def-suite pi-cli-suite)
(in-suite pi-cli-suite)

(defun run-tests ()
  (run! 'pi-cli-suite))
