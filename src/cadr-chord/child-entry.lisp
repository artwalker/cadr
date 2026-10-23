;;;; Child process entry. Loaded by fork-driver with stdout reserved for frames.
(require :asdf)
(let ((protocol *standard-output*))
  (let ((*standard-output* *error-output*)
        (*trace-output* *error-output*))
    (load (or (uiop:getenv "QUICKLISP_SETUP") "/root/quicklisp/setup.lisp"))
    (asdf:load-system "cadr-chord"))
  (let ((*standard-output* protocol))
    (funcall (find-symbol "RUN-CHILD-HOST" "CADR-CHORD"))))
