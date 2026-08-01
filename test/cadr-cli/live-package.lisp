(defpackage #:cadr-cli/live-tests
  (:use #:cl #:fiveam))

(in-package #:cadr-cli/live-tests)

(def-suite cadr-cli-live-suite)
(in-suite cadr-cli-live-suite)

(defmacro with-test-directory ((directory) &body body)
  `(uiop:with-temporary-file
       (:pathname marker :keep t)
     (delete-file marker)
     (let ((,directory
             (uiop:ensure-directory-pathname
              (pathname
               (format nil "~A-dir/"
                       (namestring marker))))))
       (ensure-directories-exist
        (merge-pathnames "anchor" ,directory))
       (unwind-protect
            (progn ,@body)
         (when (probe-file ,directory)
           (uiop:delete-directory-tree
            ,directory
            :validate t
            :if-does-not-exist :ignore))))))
