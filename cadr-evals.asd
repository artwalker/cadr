(asdf:defsystem "cadr-evals"
  :description "Behavioral evaluation harness for cadr"
  :version "0.1.0"
  :license "MIT"
  :depends-on ("cadr-cli")
  :serial t
  :components ((:module "src/cadr-evals"
                :serial t
                :components ((:file "package")
                             (:file "harness")
                             (:file "suites")
                             (:file "main"))))
  :in-order-to ((test-op (test-op "cadr-evals/tests"))))

(asdf:defsystem "cadr-evals/tests"
  :description "Tests for cadr-evals"
  :depends-on ("fiveam"
               "cadr-evals")
  :serial t
  :components ((:module "test/cadr-evals"
                :serial t
                :components ((:file "package")
                             (:file "evals-test")
                             (:file "live-evals-test"))))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (unless (uiop:symbol-call
                      :cadr-evals/tests
                      :run-tests)
               (error "cadr-evals tests failed"))))
