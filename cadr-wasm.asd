(asdf:defsystem "cadr-wasm"
  :description "Pure Lisp WebAssembly runtime for the quickjs-wasi module"
  :version (:read-file-form "version.sexp")
  :license "MIT"
  :serial t
  :components ((:module "src/cadr-wasm"
                :serial t
                :components ((:file "package")
                             (:file "module")
                             (:file "value")
                             (:file "binary")
                             (:file "text")
                             (:file "validate")
                             (:file "compile")
                             (:file "instance")
                             (:file "wasi")
                             (:file "cache")
                             (:file "aot"))))
  :in-order-to ((test-op (test-op "cadr-wasm/tests"))))

(asdf:defsystem "cadr-wasm/tests"
  :description "Tests for the pure Lisp WebAssembly runtime"
  :depends-on ("fiveam" "cadr-wasm")
  :serial t
  :components ((:module "test/cadr-wasm"
                :serial t
                :components ((:file "package")
                             (:file "runtime-test")
                             (:file "spec"))))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (unless (uiop:symbol-call :cadr-wasm/tests :run-tests)
               (error "cadr-wasm tests failed"))))
