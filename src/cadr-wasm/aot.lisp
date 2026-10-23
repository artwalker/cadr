(in-package #:cadr-wasm)

(defvar *quickjs-aot-funcs* nil)
(defvar *quickjs-aot-ready* nil)
(defvar *quickjs-compiled-module* nil)

(defun quickjs-aot-fasl ()
  (vendor-file "quickjs-aot.fasl"))

(defun aot-function-type (sig)
  (with-output-to-string (out)
    (write-string "(function (" out)
    (loop repeat (length (sig-params sig))
          for space = nil then t
          do (when space (write-char #\Space out))
             (format out "~S" '(unsigned-byte 64)))
    (write-string ") (values" out)
    (loop repeat (length (sig-results sig))
          do (format out " ~S" '(unsigned-byte 64)))
    (write-string "))" out)))

(defun write-quickjs-aot-source (path)
  "Write the Lisp translated from the pinned quickjs-wasi wasm.
scripts/aot-quickjs-wasm.sh compiles that file on a large heap.
Module functions call each other by name, so the hot path does not
svref the function vector."
  (let* ((module (parse-module (quickjs-wasm-bytes)))
         (codes (wasm-module-codes module))
         (imports (count :func (wasm-module-imports module) :key #'wasm-import-kind))
         (sigs (collect-sigs module))
         (names (make-array (length sigs) :initial-element nil)))
    (validate-module module)
    (loop for index from imports below (length sigs)
          do (setf (aref names index)
                   (intern (format nil "QJS-AOT-~D" (- index imports))
                           '#:cadr-wasm)))
    (with-open-file (out path :direction :output :if-exists :supersede
                              :if-does-not-exist :create)
      (let ((*print-circle* t)
            (*print-gensym* t)
            (*print-length* nil)
            (*print-level* nil)
            (*package* (find-package "CADR-WASM"))
            (*wasm-call-names* names))
        (format out "(in-package #:cadr-wasm)~%")
        (format out "(declaim~%")
        (loop for index from imports below (length sigs)
              do (format out "(ftype ~A ~A)~%(notinline ~A)~%"
                         (aot-function-type (aref sigs index))
                         (aref names index)
                         (aref names index)))
        (format out ")~%")
        (loop for code across codes
              for index from 0
              for name = (aref names (+ imports index))
              for form = (translate-function module
                                             (aref sigs (+ imports index))
                                             (wasm-code-locals code)
                                             (wasm-code-body code))
              do (prin1 `(defun ,name ,@(cdr form)) out)
                 (terpri out)
                 (when (zerop (mod (1+ index) 100))
                   (finish-output out)
                   (format *error-output* "aot-translate ~A/~A~%"
                           (1+ index) (length codes))
                   (finish-output *error-output*)
                   (sb-ext:gc :full t)))
        (format out "(setf *quickjs-aot-funcs* (vector")
        (loop for index from imports below (length sigs)
              do (format out " #'~A" (aref names index)))
        (format out "))~%(setf *quickjs-aot-ready* t)~%")
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
