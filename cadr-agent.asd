(asdf:defsystem "cadr-agent"
  :description "Common Lisp agent runtime for cadr"
  :version (:read-file-form "version.sexp")
  :license "MIT"
  :depends-on ("cadr-core"
               "cl-ppcre"
               "sqlite"
               "cadr-ai")
  :serial t
  :components ((:module "src/cadr-agent"
                :serial t
                :components ((:file "package")
                             (:file "conditions")
                             (:file "resources")
                             (:file "truncate")
                             (:file "file-mutation-queue")
                             (:file "execution-env")
                             (:module "session"
                              :serial t
                              :components
                              ((:file "codec")
                               (:file "journal")
                               (:file "migration")
                               (:file "discovery")
                               (:file "export-html")))
                             (:module "export-html"
                              :components
                              ((:static-file "template.html")
                               (:static-file "template.css")
                               (:static-file "template.js")
                               (:module "vendor"
                                :components
                                ((:static-file "marked.min.js")
                                 (:static-file "highlight.min.js")))))
                             (:file "messages")
                             (:module "storage"
                              :serial t
                              :components
                              ((:file "protocol")
                               (:file "memory")
                               (:file "harness")
                               (:file "jsonl")))
                             (:file "sqlite-storage")
                             (:file "runtime")
                             (:file "schema")
                             (:module "extensions"
                              :serial t
                              :components
                              ((:file "context")
                               (:file "api")
                               (:file "registration")
                               (:file "snapshot")
                               (:file "rendering")
                               (:file "providers")
                               (:file "commands")
                               (:file "lifecycle")))
                             (:file "tool")
                             (:file "summarization")
                             (:file "compaction")
                             (:file "branch-summarization")
                             (:file "proxy")
                             (:module "loop"
                              :serial t
                              :components
                              ((:file "events")
                               (:file "tool-execution")
                               (:file "turns")
                               (:file "agent-loop"))))))
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
                             (:file "goal12-core-capabilities-test")
                             (:file "storage-test")
                             (:file "sqlite-storage-test")
                             (:file "resources-test")
                             (:file "truncate-test")
                             (:file "execution-env-test")
                             (:file "extensions-test")
                             (:file "extensions-wave2-test")
                             (:file "extensions-wave3-test")
                             (:file "goal12-extension-api-test")
                             (:file "shutdown-test"))))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (unless (uiop:symbol-call :cadr-agent/tests :run-tests)
               (error "cadr-agent tests failed"))))
