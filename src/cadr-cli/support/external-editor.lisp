(in-package #:cadr-cli)

(defun edit-in-external-editor (content runner)
  (uiop:with-temporary-file
      (:pathname path
       :stream stream
       :direction :output
       :external-format :utf-8
       :keep t)
    (write-string content stream)
    (finish-output stream)
    (close stream)
    (sb-posix:chmod path #o600)
    (unwind-protect
         (if (zerop (funcall runner path))
             (uiop:read-file-string
              path :external-format :utf-8)
             content)
      (when (probe-file path)
        (delete-file path)))))
