(asdf:defsystem "cadr-tui"
  :description "Pure Common Lisp terminal UI primitives for cadr"
  :version "0.1.0"
  :license "MIT"
  :depends-on ("sb-posix")
  :serial t
  :components ((:module "src/cadr-tui"
                :serial t
                :components ((:file "package")
                             (:file "unicode")
                             (:file "input")
                             (:file "editor")
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
                             (:file "unicode-test")
                             (:file "input-editor-test")
                             (:file "components-test")
                             (:file "renderer-test")
                             (:file "terminal-test"))))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (unless (uiop:symbol-call :cadr-tui/tests :run-tests)
               (error "cadr-tui tests failed"))))
