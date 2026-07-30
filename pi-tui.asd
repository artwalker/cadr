(asdf:defsystem "pi-tui"
  :description "Pure Common Lisp terminal UI primitives for Pi"
  :version "0.1.0"
  :license "MIT"
  :depends-on ("sb-posix")
  :serial t
  :components ((:module "src/pi-tui"
                :serial t
                :components ((:file "package")
                             (:file "unicode")
                             (:file "input")
                             (:file "editor")
                             (:file "components")
                             (:file "renderer")
                             (:file "terminal"))))
  :in-order-to ((test-op (test-op "pi-tui/tests"))))

(asdf:defsystem "pi-tui/tests"
  :description "Tests for pi-tui"
  :depends-on ("fiveam"
               "pi-tui")
  :serial t
  :components ((:module "test/pi-tui"
                :serial t
                :components ((:file "package")
                             (:file "unicode-test")
                             (:file "input-editor-test")
                             (:file "components-test")
                             (:file "renderer-test")
                             (:file "terminal-test"))))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (unless (uiop:symbol-call :pi-tui/tests :run-tests)
               (error "pi-tui tests failed"))))
