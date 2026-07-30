(asdf:defsystem "cadr-cli"
  :description "Common Lisp coding-agent CLI for cadr"
  :version "0.1.0"
  :license "MIT"
  :depends-on ("cl-ppcre"
               "cadr-agent"
               "cadr-tui")
  :serial t
  :components ((:module "src/cadr-cli"
                :serial t
                :components ((:file "package")
                             (:file "arguments")
                             (:file "migration")
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
                             (:module "modes"
                              :serial t
                              :components
                              ((:file "print")
                               (:module "rpc"
                                :serial t
                                :components
                                ((:file "jsonl")
                                 (:file "ui")
                                 (:file "mode")))))
                             (:file "repl")
                             (:file "tui")
                             (:file "main")
                             (:file "build-support"))))
  :in-order-to ((test-op (test-op "cadr-cli/tests"))))

(asdf:defsystem "cadr-cli/tests"
  :description "Tests for cadr-cli"
  :depends-on ("fiveam"
               "cadr-cli")
  :serial t
  :components ((:module "test/cadr-cli"
                :serial t
                :components ((:file "package")
                             (:file "helpers")
                             (:file "file-tools-test")
                             (:file "search-tools-test")
                             (:file "bash-test")
                             (:file "execution-policy-test")
                             (:file "config-auth-test")
                             (:file "modes-test")
                             (:file "rpc-test")
                             (:file "repl-test")
                             (:file "session-command-test")
                             (:file "extensions-test")
                             (:file "tui-test")
                             (:file "migration-test")
                             (:file "data-migration-test")
                             (:file "build-test"))))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (unless (uiop:symbol-call :cadr-cli/tests :run-tests)
               (error "cadr-cli tests failed"))))
