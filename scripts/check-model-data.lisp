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
       (directory
         (merge-pathnames "test/fixtures/catalogs/provider-data/" root)))
  (asdf:load-asd (truename (merge-pathnames "cadr-ai.asd" root)))
  (asdf:load-system "cadr-ai")
  (handler-case
      (progn
        (uiop:symbol-call
         :cadr-ai :validate-model-data-directory
         (uiop:symbol-call :cadr-ai :read-model-data-structure directory)
         directory)
        (format t "Generated model data is valid.~%"))
    (error (cause)
      (format *error-output* "~A~%" cause)
      (format *error-output*
              "~%Model data is missing or stale. Run scripts/generate-models.lisp.~%")
      (uiop:quit 1))))
