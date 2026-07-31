(asdf:defsystem "cadr-tui"
  :description "Pure Common Lisp terminal UI primitives for cadr"
  :version "0.1.0"
  :license "MIT"
  :depends-on ("cl-ppcre"
               "sb-posix")
  :serial t
  :components ((:module "src/cadr-tui"
                :serial t
                :components ((:file "package")
                             (:file "unicode")
                             (:file "fuzzy")
                             (:file "word-navigation")
                             (:file "keys")
                             (:file "keybindings")
                             (:file "kill-ring")
                             (:file "undo-stack")
                             (:file "input")
                             (:file "stdin-buffer")
                             (:file "terminal-colors")
                             (:file "terminal-image")
                             (:file "theme")
                             (:file "overlay")
                             (:file "autocomplete")
                             (:file "editor")
                             (:file "input-component")
                             (:file "components")
                             (:file "renderer")
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
                             (:file "renderer-test")
                             (:file "alt-screen-test")
                             (:file "terminal-test")
                             (:file "terminal-parity-test")
                             (:file "manual-acceptance-test"))))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (unless (uiop:symbol-call :cadr-tui/tests :run-tests)
               (error "cadr-tui tests failed"))))
