(in-package #:cadr-cli)

(defun atomic-write-utf8 (path content)
  ;; cadr-core:atomic-write-string already defaults :durability :flush
  ;; (src/cadr-core/atomic-file.lisp:67). Restating it was a zero-decision
  ;; alias.
  (cadr-core:atomic-write-string path content))
