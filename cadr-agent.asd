(asdf:defsystem "cadr-agent"
  :description "Common Lisp agent runtime for cadr"
  :version "0.1.0"
  :license "MIT"
  :depends-on ("cl-ppcre"
               "cadr-ai")
  :serial t
  :components ((:module "src/cadr-agent"
                :serial t
                :components ((:file "package")
                             (:file "conditions")
                             (:file "session")
                             (:file "runtime")
                             (:file "schema")
                             (:file "extensions")
                             (:file "tool")
                             (:file "compaction")
                             (:file "loop"))))
  :in-order-to ((test-op (test-op "cadr-agent/tests"))))

(asdf:defsystem "cadr-agent/tests"
  :description "Tests for cadr-agent"
  :depends-on ("fiveam"
               "cadr-agent")
  :serial t
  :components ((:module "test/cadr-agent"
                :serial t
                :components ((:file "package")
                             (:file "helpers")
                             (:file "loop-test")
                             (:file "tool-loop-test")
                             (:file "schema-test")
                             (:file "session-test")
                             (:file "session-v2-test")
                             (:file "compaction-test")
                             (:file "extensions-test"))))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (unless (uiop:symbol-call :cadr-agent/tests :run-tests)
               (error "cadr-agent tests failed"))))
