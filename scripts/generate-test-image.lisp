#!/usr/bin/env -S sbcl --script

(require :asdf)

(let ((setup
        (or (uiop:getenv "QUICKLISP_SETUP")
            (namestring
             (merge-pathnames "quicklisp/setup.lisp"
                              (user-homedir-pathname))))))
  (unless (probe-file setup)
    (error "Quicklisp setup not found: ~A" setup))
  (load setup))

(let* ((root
         (uiop:pathname-parent-directory-pathname
          (uiop:pathname-directory-pathname
           (truename *load-truename*))))
       (path (merge-pathnames "test/data/red-circle.png" root)))
  (asdf:load-asd (truename (merge-pathnames "cadr-ai.asd" root)))
  (asdf:load-system "cadr-ai")
  (uiop:symbol-call
   :cadr-ai :write-red-circle-test-png path :width 200 :height 200)
  (format t "Generated test image at: ~A~%" path))
