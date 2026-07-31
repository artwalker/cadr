(in-package #:cadr-storage)

(defun open-sqlite-database (path)
  (cadr-agent::open-sqlite-session-database
   (pathname path)))

(defun close-sqlite-database (database)
  (sqlite:disconnect database)
  nil)

(defun apply-sqlite-migrations (database)
  (apply-sqlite-session-migrations database))
