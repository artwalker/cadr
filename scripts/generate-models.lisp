#!/usr/bin/env -S sbcl --script

;; The hydrated provider snapshot is the deterministic source of truth. The
;; materializer validates every shard and its manifest before replacing the
;; compiled Lisp catalog.
(require :asdf)

(let ((status
        (uiop:wait-process
         (uiop:launch-program
          (list
           (or (uiop:getenv "SBCL") "sbcl")
           "--script"
           (namestring
            (truename
             (merge-pathnames
              "refresh-model-catalog.lisp"
              (uiop:pathname-directory-pathname
               (truename *load-truename*))))))
          :output *standard-output*
          :error-output *error-output*))))
  (unless (zerop status)
    (uiop:quit status)))
