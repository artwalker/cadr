(require "asdf")

(defparameter *cadr-build-root*
  (uiop:pathname-directory-pathname *load-truename*))

(defun build-path (name)
  (merge-pathnames name *cadr-build-root*))

(let ((quicklisp-setup
        (uiop:getenv "QUICKLISP_SETUP")))
  (unless (and quicklisp-setup
               (probe-file quicklisp-setup))
    (error "QUICKLISP_SETUP does not name a readable file"))
  (load quicklisp-setup))

(dolist (system '("cadr-ai" "cadr-agent" "cadr-tui" "cadr-cli"))
  (asdf:load-asd
   (truename
    (build-path (format nil "~A.asd" system)))))

(let ((*debug-io* (make-broadcast-stream)))
  (asdf:load-system "slynk/mrepl"))
(asdf:load-system "cadr-cli")

(unless (member :sb-core-compression *features*)
  (format *error-output*
          "cadr build: SBCL lacks sb-core-compression; building an uncompressed image.~%")
  (finish-output *error-output*))

(apply
 #'sb-ext:save-lisp-and-die
 (namestring (build-path "cadr"))
 (cadr-cli:native-image-save-arguments *features*))
