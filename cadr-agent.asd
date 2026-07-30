(asdf:defsystem "cadr-agent"
  :description "Common Lisp agent runtime for cadr"
  :version "0.1.0"
  :license "MIT"
  :depends-on ("cl-ppcre"
               "sqlite"
               "cadr-ai")
  :serial t
  :components ((:module "src/cadr-agent"
                :serial t
                :components ((:file "package")
                             (:file "conditions")
                             (:file "resources")
                             (:file "truncate")
                             (:file "execution-env")
                             (:file "session")
                             (:file "storage")
                             (:file "sqlite-storage")
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
                             (:file "queue-test")
                             (:file "retry-test")
                             (:file "tool-loop-test")
                             (:file "schema-test")
                             (:file "session-test")
                             (:file "session-v2-test")
                             (:file "session-v3-test")
                             (:file "compaction-test")
                             (:file "storage-test")
                             (:file "sqlite-storage-test")
                             (:file "resources-test")
                             (:file "truncate-test")
                             (:file "execution-env-test")
                             (:file "extensions-test")
                             (:file "extensions-wave2-test"))))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (unless (uiop:symbol-call :cadr-agent/tests :run-tests)
               (error "cadr-agent tests failed"))))
