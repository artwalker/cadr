(asdf:defsystem "cadr-storage"
  :description "Standalone SQLite session storage package for cadr"
  :version "0.1.0"
  :license "MIT"
  :depends-on ("cadr-agent")
  :serial t
  :components ((:module "src/cadr-storage"
                :serial t
                :components ((:file "package")
                             (:file "sqlite"))))
  :in-order-to ((test-op (test-op "cadr-storage/tests"))))

(asdf:defsystem "cadr-storage/tests"
  :description "Tests for cadr-storage"
  :depends-on ("fiveam"
               "cadr-storage")
  :serial t
  :components ((:module "test/cadr-storage"
                :serial t
                :components ((:file "package")
                             (:file "storage-test"))))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (unless (uiop:symbol-call
                      :cadr-storage/tests
                      :run-tests)
               (error "cadr-storage tests failed"))))
