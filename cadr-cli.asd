(asdf:defsystem "cadr-cli"
  :description "Common Lisp coding-agent CLI for cadr"
  :version (:read-file-form "version.sexp")
  :license "MIT"
  :depends-on ("cadr-core"
               "cl-ppcre"
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
                             (:module "support"
                              :serial t
                              :components ((:file "threads")
                                           (:file "atomic-write")
                                           (:file "changelog-share")
                                           (:file "bug-report")
                                           (:file "html")
                                           (:file "resume-version-git")
                                           (:file "headers")
                                           (:file "external-editor")
                                           (:file "model-help")
                                           (:file "event-bus")
                                           (:file "timings")
                                           (:file "file-watcher")
                                           (:file "paths")
                                           (:file "shell-process")))
                             (:file "tool-manager")
                             (:file "config")
                             (:module "settings"
                              :serial t
                              :components ((:file "config-values")
                                           (:file "manager")
                                           (:file "trust")))
                             (:module "packages"
                              :serial t
                             :components ((:file "source")
                                          (:file "settings")
                                          (:file "manifest")
                                          (:file "config-selector")
                                          (:file "update-checks")
                                          (:file "commands")))
                             (:file "resource-loader")
                             (:module "models"
                              :serial t
                              :components ((:file "auth-storage")
                                           (:file "store")
                                           (:file "registry")
                                           (:file "matching")
                                           (:file "login-selection")
                                           (:file "credential-print")))
                             (:file "media")
                             (:module "interactive"
                              :serial t
                              :components ((:file "footer")
                                           (:file "theme")
                                           (:file "images")
                                           (:file "clipboard")
                                           (:file "syntax")
                                           (:file "tool-render-session")
                                           (:module "selectors"
                                            :serial t
                                            :components ((:file "common")
                                                         (:file "sessions")
                                                         (:file "tree")
                                                         (:file "settings")
                                                         (:file "auth")
                                                         (:file "login-dialog")
                                                         (:file "models")
                                                         (:file "thinking")
                                                         (:file "trust")
                                                         (:file "fork")))))
                             (:file "truncation")
                             (:file "output-accumulator")
                             (:module "tools"
                              :serial t
                              :components ((:file "path")
                                           (:file "read")
                                           (:file "write")
                                           (:file "edit")
                                           (:file "bash")
                                           (:file "powershell")
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
                                 (:file "ui")
                                 (:file "extension")))))
                             (:module "extensions"
                              :serial t
                              :components ((:file "discovery")
                                           (:file "loader")
                                           (:file "commands")
                                           (:file "installer")))
                             (:module "sdk-services"
                              :pathname "sdk"
                              :serial t
                              :components ((:file "cache-version")
                                           (:file "system-prompt")
                                           (:file "settings-service")
                                           (:file "resource-service")
                                           (:file "model-service")))
                             (:module "modes"
                              :serial t
                              :components
                              ((:file "print")
                               (:module "rpc"
                                :serial t
                                :components
                                ((:file "jsonl")
                                 (:file "ui")
                                 (:file "models")
                                 (:file "prompt-bash")
                                 (:file "sessions")
                                 (:file "commands")
                                 (:file "mode")))))
                             (:file "repl")
                             (:module "interactive-components"
                              :pathname "interactive/components"
                              :serial t
                              :components ((:file "loaders")
                                           (:file "countdown")
                                           (:file "armin")
                                           (:file "daxnuts")
                                           (:file "announcement")))
                             (:module "interactive-controller"
                              :pathname "interactive"
                              :serial t
                              :components ((:file "state")
                                           (:file "entries")
                                           (:file "status")
                                           (:file "extension-ui")
                                           (:file "user-bash")
                                           (:file "transcript")
                                           (:file "tool-rendering")
                                           (:file "pending-messages")
                                           (:file "frame")
                                           (:file "autocomplete")
                                           (:file "themes")
                                           (:file "controller")))
                             (:file "remote-repl")
                             (:module "bootstrap"
                              :serial t
                              :components ((:file "tools")
                                           (:file "sessions")
                                           (:file "settings")
                                           (:file "auth")
                                           (:file "commands")
                                           (:file "main")))
                             (:file "crash")
                             (:module "sdk-facade"
                              :pathname "sdk"
                              :serial t
                              :components ((:file "session-manager")
                                           (:file "agent-session")
                                           (:file "session-runtime")))
                             (:file "build-support"))))
  :in-order-to ((test-op (test-op "cadr-cli/tests"))))

(asdf:defsystem "cadr-cli/tests"
  :description "Tests for cadr-cli"
  :depends-on ("fiveam"
               "cadr-cli"
               "slynk/mrepl"
               "cadr-live-test-support")
  :serial t
  :components ((:module "test/cadr-cli"
                :serial t
                :components ((:file "package")
                             (:file "helpers")
                             (:file "file-tools-test")
                             (:file "part-b-tools-test")
                             (:file "part-b-utilities-test")
                             (:file "part-b-config-test")
                             (:file "goal28-compaction-settings-test")
                             (:file "goal28-branch-summary-settings-test")
                             (:file "goal28-shell-settings-test")
                             (:file "goal28-session-dir-settings-test")
                             (:file "goal28-websocket-timeout-settings-test")
                             (:file "goal28-http-proxy-settings-test")
                             (:file "goal28-thinking-budgets-settings-test")
                             (:file "goal28-themes-settings-test")
                             (:file "goal28-skills-settings-test")
                             (:file "goal28-prompts-settings-test")
                             (:file "goal28-extensions-settings-test")
                             (:file "goal28-markdown-indent-settings-test")
                             (:file "goal28-markdown-indent-live-test")
                             (:file "goal28-last-changelog-version-test")
                             (:file "goal28-external-editor-settings-test")
                             (:file "goal28-external-editor-key-test")
                             (:file "goal28-npm-command-settings-test")
                             (:file "goal28-npm-command-install-test")
                             (:file "goal28-packages-settings-test")
                             (:file "goal28-exit-and-auth-test")
                             (:file "goal28-cli-flags-test")
                             (:file "goal28-slash-commands-test")
                             (:file "goal24-bug-report-test")
                             (:file "goal24-click-collapse-test")
                             (:file "goal28-registries-test")
                             (:file "goal28-events-providers-tools-test")
                             (:file "goal28-remaining-surfaces-test")
                             (:file "goal28-extension-bundle-fields-test")
                             (:file "goal28-public-api-exports-test")
                             (:file "goal28-rpc-bash-settings-test")
                             (:file "goal28-branch-summary-prompt-test")
                             (:file "goal28-provider-retry-settings-test")
                             (:file "goal28-retry-enabled-test")
                             (:file "goal28-import-file-not-found-test")
                             (:file "goal28-import-collision-test")
                             (:file "goal28-missing-session-cwd-test")
                             (:file "goal28-credential-sync-test")
                             (:file "goal28-http-idle-timeout-test")
                             (:file "goal28-image-settings-test")
                             (:file "goal28-terminal-warning-settings-test")
                             (:file "goal28-cli-settings-readers-test")
                             (:file "part-b-models-test")
                             (:file "goal21-thinking-selector-test")
                             (:file "model-registry-cache-test")
                             (:file "part-b-interactive-test")
                             (:file "part-b-sdk-test")
                             (:file "part-b-cli-test")
                             (:file "part-b-package-test")
                             (:file "search-tools-test")
                             (:file "bash-test")
                             (:file "powershell-test")
                             (:file "tool-result-parity-test")
                             (:file "execution-policy-test")
                             (:file "config-auth-test")
                             (:file "modes-test")
                             (:file "rpc-test")
                             (:file "repl-test")
                             (:file "remote-repl-test")
                             (:file "session-command-test")
                             (:file "extensions-test")
                             (:file "llama-extension-test")
                             (:file "goal12-tui-composition-test")
                             (:file "goal12-core-capabilities-test")
                             (:file "goal12-sdk-test")
                             (:file "goal23-in-memory-session-test")
                             (:file "goal12-examples-test")
                             (:file "goal20-example-games-test")
                             (:file "tic-tac-toe-steer-test")
                             (:file "goal20-part-l-test")
                             (:file "goal20-part-i-test")
                             (:file "goal20-part-b-ledger-test")
                             (:file "goal20-selector-cache-test")
                             (:file "goal13-presentation-test")
                             (:file "goal14-a0-test")
                             (:file "goal14-organization-test")
                             (:file "goal15-a0-test")
                             (:file "goal15-part-c-test")
                             (:file "goal17-compaction-test")
                             (:file "goal17-login-dialog-test")
                             (:file "goal18-login-cancel-test")
                             (:file "goal18-migration-test")
                             (:file "goal18-login-forms-test")
                             (:file "goal18-debug-command-test")
                             (:file "goal18-startup-resources-test")
                             (:file "goal18-content-migration-test")
                             (:file "goal18-docs-test")
                             (:file "tui-test")
                             (:file "goal9-b-runtime-parity-test")
                             (:file "goal9-b3-p2-regressions-test")
                             (:file "goal9-b3-overlay-contract-test")
                             (:file "goal9-b3-base-screen-contract-test")
                             (:file "goal18-presentation-numbers-test")
                             (:file "goal9-a2-interactive-test")
                             (:file "goal9-a2-workflows-test")
                             (:file "goal9-a2-process-faux-test")
                             (:file "migration-test")
                             (:file "data-migration-test")
                             (:file "build-test")
                             (:file "live-auth-test")
                             (:file "live-gate-test"))))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (unless (uiop:symbol-call :cadr-cli/tests :run-tests)
               (error "cadr-cli tests failed"))))

(asdf:defsystem "cadr-cli/live-tests"
  :description "Credential-gated live tests for cadr-cli"
  :depends-on ("fiveam"
               "cadr-cli"
               "cadr-live-test-support")
  :serial t
  :components ((:module "test/cadr-cli"
                :serial t
                :components ((:file "live-package")
                             (:file "live-test")))))
