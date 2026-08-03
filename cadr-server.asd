(asdf:defsystem "cadr-server"
  :description "Unix socket supervisor for cadr RPC instances"
  :version (:read-file-form "version.sexp")
  :license "MIT"
  :depends-on ("cadr-core"
               "cadr-ai"
               "sb-bsd-sockets"
               "sb-posix")
  :serial t
  :components ((:module "src/cadr-server"
                :serial t
                :components ((:file "package")
                             (:file "types")
                             (:file "config")
                             (:file "protocol")
                             (:file "storage")
                             (:file "radius")
                             (:file "rpc-process")
                             (:file "supervisor")
                             (:file "handler")
                             (:file "ipc")
                             (:file "main"))))
  :in-order-to ((test-op (test-op "cadr-server/tests"))))

(asdf:defsystem "cadr-server/tests"
  :description "Tests for cadr-server"
  :depends-on ("fiveam"
               "cadr-server")
  :serial t
  :components ((:module "test/cadr-server"
                :serial t
                :components ((:file "package")
                             (:file "server-test"))))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (unless (uiop:symbol-call
                      :cadr-server/tests
                      :run-tests)
               (error "cadr-server tests failed"))))
