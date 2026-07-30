(asdf:defsystem "pi-cli"
  :description "Common Lisp coding-agent CLI for Pi"
  :version "0.1.0"
  :license "MIT"
  :depends-on ("cl-ppcre"
               "pi-agent"
               "pi-tui")
  :serial t
  :components ((:module "src/pi-cli"
                :serial t
                :components ((:file "package")
                             (:file "arguments")
                             (:file "config")
                             (:file "truncation")
                             (:module "tools"
                              :serial t
                              :components ((:file "path")
                                           (:file "read")
                                           (:file "write")
                                           (:file "edit")
                                           (:file "bash")
                                           (:file "glob")
                                           (:file "grep")))
                             (:file "system-prompt")
                             (:file "extensions")
                             (:file "repl")
                             (:file "tui")
                             (:file "main")
                             (:file "build-support"))))
  :in-order-to ((test-op (test-op "pi-cli/tests"))))

(asdf:defsystem "pi-cli/tests"
  :description "Tests for pi-cli"
  :depends-on ("fiveam"
               "pi-cli")
  :serial t
  :components ((:module "test/pi-cli"
                :serial t
                :components ((:file "package")
                             (:file "helpers")
                             (:file "file-tools-test")
                             (:file "search-tools-test")
                             (:file "bash-test")
                             (:file "execution-policy-test")
                             (:file "config-auth-test")
                             (:file "repl-test")
                             (:file "session-command-test")
                             (:file "extensions-test")
                             (:file "tui-test")
                             (:file "build-test"))))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (unless (uiop:symbol-call :pi-cli/tests :run-tests)
               (error "pi-cli tests failed"))))
