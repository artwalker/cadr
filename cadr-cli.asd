(asdf:defsystem "cadr-cli"
  :description "Common Lisp coding-agent CLI for cadr"
  :version "0.1.0"
  :license "MIT"
  :depends-on ("cl-ppcre"
               "cl-jpeg"
               "png-read"
               "cadr-agent"
               "cadr-tui")
  :serial t
  :components ((:module "src/cadr-cli"
                :serial t
                :components ((:file "package")
                             (:file "arguments")
                             (:file "migration")
                             (:file "utilities")
                             (:file "config")
                             (:file "settings")
                             (:file "package-manager")
                             (:file "resource-loader")
                             (:file "model-services")
                             (:file "media")
                             (:file "interactive-services")
                             (:file "sdk-services")
                             (:file "truncation")
                             (:module "tools"
                              :serial t
                              :components ((:file "path")
                                           (:file "read")
                                           (:file "write")
                                           (:file "edit")
                                           (:file "bash")
                                           (:file "glob")
                                           (:file "grep")
                                           (:file "find")
                                           (:file "ls")))
                             (:file "system-prompt")
                             (:module "bundled-extensions"
                              :pathname "extensions"
                              :serial t
                              :components
                              ((:module "llama"
                                :serial t
                                :components
                                ((:file "client")
                                 (:file "huggingface")
                                 (:file "provider")
                                 (:file "extension")))))
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
                             (:file "part-b-tools-test")
                             (:file "part-b-utilities-test")
                             (:file "part-b-config-test")
                             (:file "part-b-models-test")
                             (:file "part-b-interactive-test")
                             (:file "part-b-sdk-test")
                             (:file "part-b-cli-test")
                             (:file "part-b-package-test")
                             (:file "search-tools-test")
                             (:file "bash-test")
                             (:file "tool-result-parity-test")
                             (:file "execution-policy-test")
                             (:file "config-auth-test")
                             (:file "modes-test")
                             (:file "rpc-test")
                             (:file "repl-test")
                             (:file "session-command-test")
                             (:file "extensions-test")
                             (:file "llama-extension-test")
                             (:file "tui-test")
                             (:file "goal9-b-runtime-parity-test")
                             (:file "goal9-b3-p2-regressions-test")
                             (:file "goal9-b3-overlay-contract-test")
                             (:file "goal9-a2-interactive-test")
                             (:file "goal9-a2-workflows-test")
                             (:file "migration-test")
                             (:file "data-migration-test")
                             (:file "build-test")
                             (:file "live-test"))))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (unless (uiop:symbol-call :cadr-cli/tests :run-tests)
               (error "cadr-cli tests failed"))))
