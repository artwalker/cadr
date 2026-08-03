(require "asdf")

(defparameter *cadr-server-build-root*
  (uiop:pathname-directory-pathname
   *load-truename*))

(defun server-build-path (name)
  (merge-pathnames
   name *cadr-server-build-root*))

(let ((quicklisp-setup
        (uiop:getenv
         "QUICKLISP_SETUP")))
  (unless
      (and quicklisp-setup
           (probe-file quicklisp-setup))
    (error
     "QUICKLISP_SETUP does not name a readable file"))
  (load quicklisp-setup))

(dolist (system
         '("cadr-core" "cadr-ai" "cadr-server"))
  (asdf:load-asd
   (truename
    (server-build-path
     (format nil
             "~A.asd"
             system)))))

(asdf:load-system "cadr-server")

(unless
    (member
     :sb-core-compression
     *features*)
  (format
   *error-output*
   "cadr-server build: SBCL lacks sb-core-compression; building an uncompressed image.~%")
  (finish-output
   *error-output*))

(apply
 #'sb-ext:save-lisp-and-die
 (namestring
  (server-build-path
   "cadr-server"))
 (append
  (list
   :toplevel
   #'cadr-server:server-executable-main
   :executable t
   :save-runtime-options t)
  (when
      (member
       :sb-core-compression
       *features*)
    (list :compression t))))
