(require "asdf")
(defparameter *aot-root*
  (uiop:pathname-parent-directory-pathname
   (uiop:pathname-directory-pathname *load-truename*)))
(asdf:load-asd (merge-pathnames "cadr-wasm.asd" *aot-root*))
(asdf:load-system "cadr-wasm")

(let ((source (merge-pathnames "quickjs-aot.lisp" (uiop:temporary-directory))))
  (cadr-wasm::write-quickjs-aot-source source)
  (let ((fasl
          (handler-bind ((style-warning #'muffle-warning)
                         (sb-ext:compiler-note #'muffle-warning))
            (compile-file source :verbose nil :print nil))))
    (uiop:copy-file fasl (cadr-wasm::quickjs-aot-fasl))
    (format t "aot-fasl ~A bytes ~A~%"
            (cadr-wasm::quickjs-aot-fasl)
            (with-open-file (stream (cadr-wasm::quickjs-aot-fasl)
                                    :element-type '(unsigned-byte 8))
              (file-length stream)))))
(sb-ext:exit :code 0)
