(in-package #:cadr-server)

(defstruct machine-record
  id
  created-at
  last-seen-at
  label)

(defstruct instance-record
  id
  status
  cwd
  created-at
  last-seen-at
  label
  session-id
  session-file
  radius-pi-id)

(defun clone-instance-record (record)
  (copy-instance-record record))

(defun current-iso8601 ()
  (cadr-core:current-utc-iso8601 :fraction-digits 0))
