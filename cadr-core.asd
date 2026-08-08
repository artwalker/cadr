(asdf:defsystem "cadr-core"
  :description "Internal failure-safety and persistence primitives for cadr"
  :version (:read-file-form "version.sexp")
  :license "MIT"
  :depends-on ("sb-posix")
  :serial t
  :components ((:module "src/cadr-core"
                :serial t
                :components ((:file "package")
                             (:file "threads")
                             (:file "cancellation")
                             (:file "atomic-file")
                             (:file "redacted-print")
                             (:file "time")
                             (:file "paths"))))
  :in-order-to ((test-op (test-op "cadr-core/tests"))))

(asdf:defsystem "cadr-core/tests"
  :description "Tests for internal cadr-core primitives"
  :depends-on ("fiveam" "cadr-core")
  :serial t
  :components ((:module "test/cadr-core"
                :serial t
                :components ((:file "package")
                             (:file "core-test"))))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (unless (uiop:symbol-call :cadr-core/tests :run-tests)
               (error "cadr-core tests failed"))))
