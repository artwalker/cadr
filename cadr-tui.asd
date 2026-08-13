(asdf:defsystem "cadr-tui"
  :description "Pure Common Lisp terminal UI primitives for cadr"
  :version (:read-file-form "version.sexp")
  :license "MIT"
  :depends-on ("cadr-core"
               "cl-ppcre"
               "sb-posix")
  :serial t
  :components ((:module "src/cadr-tui"
                :serial t
                :components ((:file "package")
                             (:file "threads")
                             (:file "unicode")
                             (:file "fuzzy")
                             (:file "word-navigation")
                             (:file "latex")
                             (:file "keys")
                             (:file "keybindings")
                             (:file "kill-ring")
                             (:file "undo-stack")
                             (:file "input")
                             (:file "stdin-buffer")
                             (:file "native-modifiers")
                             (:file "terminal-colors")
                             (:file "terminal-image")
                             (:file "theme")
                             (:file "overlay")
                             (:file "autocomplete")
                             (:file "editor")
                             (:file "input-component")
                             (:module "mermaid"
                              :serial t
                              :components ((:file "canvas")
                                           (:file "width-data")
                                           (:file "width")
                                           (:file "labels")
                                           (:file "graph")
                                           (:file "parse")
                                           (:file "layout")
                                           (:file "layout-seq")
                                           (:file "ansi")
                                           (:file "source-box")
                                           (:file "index")
                                           (:file "transform")))
                             (:module "components"
                              :serial t
                              :components ((:file "markdown")
                                           (:file "image")
                                           (:file "tool-block")
                                           (:file "status")
                                           (:file "select-list")))
                             (:module "renderer"
                              :serial t
                              :components ((:file "terminal-protocol")
                                           (:file "virtual-terminal")
                                           (:file "lifecycle-input")
                                           (:file "main-screen")
                                           (:file "alt-screen")))
                             (:module "composition"
                              :serial t
                              :components ((:file "protocol")
                                           (:file "text-box")
                                           (:file "rich-content")
                                           (:file "settings-list")
                                           (:file "loaders")
                                           (:file "root")))
                             (:file "terminal"))))
  :in-order-to ((test-op (test-op "cadr-tui/tests"))))

(asdf:defsystem "cadr-tui/tests"
  :description "Tests for cadr-tui"
  :depends-on ("fiveam"
               "cadr-tui")
  :serial t
  :components ((:module "test/cadr-tui"
                :serial t
                :components ((:file "package")
                             (:file "helpers")
                             (:file "unicode-test")
                             (:file "wrap-ansi-test")
                             (:file "truncate-to-width-test")
                             (:file "fuzzy-test")
                             (:file "word-navigation-test")
                             (:file "keys-test")
                             (:file "keybindings-test")
                             (:file "stdin-buffer-test")
                             (:file "terminal-colors-test")
                             (:file "theme-test")
                             (:file "terminal-image-test")
                             (:file "overlay-test")
                             (:file "autocomplete-test")
                             (:file "input-editor-test")
                             (:file "editor-parity-test")
                             (:file "input-component-test")
                             (:file "components-test")
                             (:file "component-parity-test")
                             (:file "composition-test")
                             (:file "renderer-test")
                             (:file "alt-screen-test")
                             (:file "latex-reference-cases")
                             (:file "latex-test")
                             (:file "mermaid-reference-cases")
                             (:file "mermaid-golden-data")
                             (:file "mermaid-golden-test")
                             (:file "mermaid-transform-data")
                             (:file "mermaid-transform-test")
                             (:file "terminal-test")
                             (:file "terminal-parity-test")
                             (:file "manual-acceptance-test"))))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (unless (uiop:symbol-call :cadr-tui/tests :run-tests)
               (error "cadr-tui tests failed"))))
