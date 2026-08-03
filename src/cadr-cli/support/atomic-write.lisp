(in-package #:cadr-cli)

(defun atomic-write-utf8 (path content)
  (cadr-core:atomic-write-string
   path content :durability :flush))
