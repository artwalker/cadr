(in-package #:cadr-cli)

(defun native-image-save-arguments (features)
  (append
   (list :toplevel #'executable-main
         :executable t
         :save-runtime-options t)
   (when (member :sb-core-compression features)
     (list :compression t))))

(defun executable-main ()
  (call-with-fatal-condition-boundary
   (lambda ()
     (uiop:quit (or (main) 0)))))
