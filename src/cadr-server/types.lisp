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
  (multiple-value-bind
        (second minute hour day month year)
      (decode-universal-time
       (get-universal-time) 0)
    (format nil
            "~4,'0D-~2,'0D-~2,'0DT~2,'0D:~2,'0D:~2,'0DZ"
            year month day hour minute second)))
