(asdf:defsystem "pi-agent"
  :description "Common Lisp agent runtime for Pi"
  :version "0.1.0"
  :license "MIT"
  :depends-on ("cl-ppcre"
               "pi-ai")
  :serial t
  :components ((:module "src/pi-agent"
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
  :in-order-to ((test-op (test-op "pi-agent/tests"))))

(asdf:defsystem "pi-agent/tests"
  :description "Tests for pi-agent"
  :depends-on ("fiveam"
               "pi-agent")
  :serial t
  :components ((:module "test/pi-agent"
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
             (unless (uiop:symbol-call :pi-agent/tests :run-tests)
               (error "pi-agent tests failed"))))
