(asdf:defsystem "cadr-evals"
  :description "Behavioral evaluation harness for cadr"
  :version (:read-file-form "version.sexp")
  :license "MIT"
  :depends-on ("cadr-core"
               "cadr-cli")
  :serial t
  :components ((:module "src/cadr-evals"
                :serial t
                :components ((:file "package")
                             (:file "harness")
                             (:file "artifacts")
                             (:file "harness-table")
                             (:file "summary")
                             (:file "reporter")
                             (:file "suites")
                             (:file "main"))))
  :in-order-to ((test-op (test-op "cadr-evals/tests"))))

(asdf:defsystem "cadr-evals/tests"
  :description "Tests for cadr-evals"
  :depends-on ("fiveam"
               "cadr-evals"
               "cadr-live-test-support")
  :serial t
  :components ((:module "test/cadr-evals"
                :serial t
                :components ((:file "package")
                             (:file "evals-test")
                             (:file "pi-harness-test")
                             (:file "artifacts-test")
                             (:file "harness-table-test")
                             (:file "summary-test")
                             (:file "reporter-test")
                             (:file "extension-authoring-test"))))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (unless (uiop:symbol-call
                      :cadr-evals/tests
                      :run-tests)
               (error "cadr-evals tests failed"))))

(asdf:defsystem "cadr-evals/live-tests"
  :description "Credential-gated live tests for cadr-evals"
  :depends-on ("fiveam"
               "cadr-evals"
               "cadr-live-test-support")
  :serial t
  :components ((:module "test/cadr-evals"
                :serial t
                :components ((:file "live-package")
                             (:file "live-evals-test")))))
