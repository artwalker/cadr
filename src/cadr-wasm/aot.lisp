(in-package #:cadr-wasm)

(defvar *quickjs-aot-funcs* nil)
(defvar *quickjs-aot-ready* nil)
(defvar *quickjs-compiled-module* nil)

(defun quickjs-aot-fasl ()
  (vendor-file "quickjs-aot.fasl"))

(defun write-quickjs-aot-source (path)
  "Write the Lisp translated from the pinned quickjs-wasi wasm.
scripts/aot-quickjs-wasm.sh compiles that file on a large heap."
  (let* ((module (parse-module (quickjs-wasm-bytes)))
         (codes (wasm-module-codes module))
         (imports (count :func (wasm-module-imports module) :key #'wasm-import-kind))
         (sigs (collect-sigs module)))
    (validate-module module)
    (with-open-file (out path :direction :output :if-exists :supersede
                              :if-does-not-exist :create)
      (let ((*print-circle* t)
            (*print-gensym* t)
            (*print-length* nil)
            (*print-level* nil)
            (*package* (find-package "CADR-WASM")))
        (format out "(in-package #:cadr-wasm)~%")
        (format out "(setf *quickjs-aot-funcs* (make-array ~D))~%" (length codes))
        (loop for code across codes
              for index from 0
              do (format out "(setf (aref *quickjs-aot-funcs* ~D) " index)
                 (prin1 (translate-function
                         module
                         (aref sigs (+ imports index))
                         (wasm-code-locals code)
                         (wasm-code-body code))
                        out)
                 (format out ")~%")
                 (when (zerop (mod (1+ index) 100))
                   (finish-output out)
                   (format *error-output* "aot-translate ~A/~A~%"
                           (1+ index) (length codes))
                   (finish-output *error-output*)
                   (sb-ext:gc :full t)))
        (format out "(setf *quickjs-aot-ready* t)~%")
        (finish-output out)))
    path))

(defun ensure-quickjs-aot ()
  (unless *quickjs-aot-ready*
    (let ((path (quickjs-aot-fasl)))
      (unless (probe-file path)
        (error "quickjs wasm has no ahead-of-time fasl at ~A" path))
      (load path :verbose nil :print nil)))
  (unless (and *quickjs-aot-ready*
               (vectorp *quickjs-aot-funcs*)
               (= 1698 (length *quickjs-aot-funcs*)))
    (error "quickjs ahead-of-time fasl did not install 1698 functions"))
  (unless *quickjs-compiled-module*
    (setf *quickjs-compiled-module*
          (make-compiled-module
           :module (parse-module (quickjs-wasm-bytes))
           :funcs *quickjs-aot-funcs*)))
  *quickjs-compiled-module*)
