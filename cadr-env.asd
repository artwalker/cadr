(asdf:defsystem "cadr-env"
  :description "Remote execution environment daemon and its framed client."
  :version (:read-file-form "version.sexp")
  :license "MIT"
  :depends-on ("sb-posix")
  :serial t
  :components ((:module "src/cadr-env"
                :serial t
                :components ((:file "package")
                             (:file "wire")
                             (:file "decode")
                             (:file "fs")
                             (:file "list")
                             (:file "window")
                             (:file "process")
                             (:file "pty")
                             (:file "watch")
                             (:file "daemon")
                             (:file "client"))))
  :in-order-to ((test-op (test-op "cadr-env/tests"))))

(asdf:defsystem "cadr-env/tests"
  :description "Tests for the remote execution environment."
  :depends-on ("fiveam" "cadr-env")
  :serial t
  :components ((:module "test/cadr-env"
                :serial t
                :components ((:file "package")
                             (:file "env-test"))))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (unless (uiop:symbol-call :cadr-env/tests :run-tests)
               (error "cadr-env tests failed"))))
