(in-package #:pi-cli/tests)

(defmacro with-test-directory ((directory) &body body)
  `(uiop:with-temporary-file
       (:pathname marker :keep t)
     (delete-file marker)
     (let ((,directory
             (uiop:ensure-directory-pathname
              (pathname (format nil "~A-dir/"
                                (namestring marker))))))
       (ensure-directories-exist
        (merge-pathnames "anchor" ,directory))
       (unwind-protect
            (progn ,@body)
         (when (probe-file ,directory)
           (uiop:delete-directory-tree
            ,directory :validate t :if-does-not-exist :ignore))))))

(defun write-text (path text)
  (ensure-directories-exist path)
  (with-open-file (stream path
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create
                          :external-format :utf-8)
    (write-string text stream)))

(defun read-text (path)
  (uiop:read-file-string path :external-format :utf-8))

(defun args (&rest pairs)
  (apply #'pi-ai::json-object pairs))

(defun invoke-tool (tool arguments)
  (funcall (pi-ai:tool-executor tool) "test-call" arguments))

(defun result-text (content)
  (pi-ai:text-content-text (first content)))

(defun count-substring (needle haystack)
  (loop with start = 0
        for position = (search needle haystack :start2 start)
        while position
        count position
        do (setf start (+ position (length needle)))))
