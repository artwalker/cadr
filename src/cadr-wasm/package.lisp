(defpackage #:cadr-wasm
  (:use #:cl)
  (:export
   #:parse-module
   #:parse-module-text
   #:validate-module
   #:compile-module
   #:instantiate
   #:invoke
   #:get-export
   #:ensure-compiled
   #:last-compile-seconds
   #:last-compile-cached-p
   #:clear-compile-cache
   #:make-wasi-imports
   #:quickjs-wasm-bytes
   #:quickjs-wasm-sha256
   #:ensure-quickjs-aot
   #:module-opcode-histogram
   #:module-import-list
   #:wasm-message
   #:wasm-malformed
   #:wasm-invalid
   #:wasm-unlinkable
   #:wasm-trap
   #:wasm-exhaustion))
