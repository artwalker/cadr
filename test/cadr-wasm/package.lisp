(defpackage #:cadr-wasm/tests
  (:use #:cl #:fiveam #:cadr-wasm)
  (:import-from #:cadr-wasm
    #:make-wasm-extern
    #:make-wasm-gcell
    #:make-wasm-table-type
    #:make-wasm-memory-type
    #:make-table
    #:make-memory
    #:wasi-sig
    #:f32-to-bits
    #:f64-to-bits
    #:global-value
    #:null-ref-p
    #:wasm-error
    #:wasm-module-exports
    #:wasm-instance-module
    #:wasm-export-name
    #:decode-base64
    #:load-le
    #:wasm-instance-memories
    #:type-at
    #:sig-params
    #:sig-results
    #:wasm-import-type
    #:wasm-module-imports
    #:wasm-memory-bytes)
  (:export #:run-tests))

(in-package #:cadr-wasm/tests)

(def-suite cadr-wasm-suite)
(in-suite cadr-wasm-suite)

(defun run-tests ()
  (let ((result (run 'cadr-wasm-suite)))
    (explain! result)
    (results-status result)))
