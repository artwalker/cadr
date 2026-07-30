(defpackage #:cadr-cli/tests
  (:use #:cl #:fiveam)
  (:import-from #:cadr-cli
                #:make-bash-tool
                #:make-edit-tool
                #:make-glob-tool
                #:make-grep-tool
                #:make-read-tool
                #:make-write-tool
                #:run-repl)
  (:export #:run-tests))

(in-package #:cadr-cli/tests)

(def-suite cadr-cli-suite)
(in-suite cadr-cli-suite)

(defun run-tests ()
  (run! 'cadr-cli-suite))
