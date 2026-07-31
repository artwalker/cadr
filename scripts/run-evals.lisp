(require "asdf")

(defparameter *cadr-evals-root*
  (uiop:pathname-parent-directory-pathname
   (uiop:pathname-directory-pathname
    (truename *load-truename*))))

(let ((*standard-output* *error-output*)
      (*trace-output* *error-output*)
      (*compile-verbose* nil)
      (*load-verbose* nil))
  (let ((quicklisp-setup
          (or
           (uiop:getenv
            "QUICKLISP_SETUP")
           (namestring
            (merge-pathnames
             "quicklisp/setup.lisp"
             (user-homedir-pathname))))))
    (unless (probe-file quicklisp-setup)
      (error
       "Quicklisp setup not found: ~A"
       quicklisp-setup))
    (load quicklisp-setup))

  (dolist (system
           '("cadr-ai"
             "cadr-agent"
             "cadr-tui"
             "cadr-cli"
             "cadr-evals"))
    (asdf:load-asd
     (truename
      (merge-pathnames
       (format nil "~A.asd" system)
       *cadr-evals-root*))))

  (asdf:load-system "cadr-evals"))
(cadr-evals:eval-main)
