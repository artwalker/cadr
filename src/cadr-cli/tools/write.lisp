(in-package #:cadr-cli)

(defun write-utf8-file (path content)
  (ensure-directories-exist path)
  (with-open-file (stream path
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create
                          :external-format :utf-8)
    (write-string content stream))
  path)

(defun make-write-tool (cwd)
  (cadr-ai:make-tool
   :name "write"
   :description "Create or completely overwrite a UTF-8 text file."
   :parameters
   (object-schema
    (cadr-ai::json-object
     "path" (string-property)
     "content" (string-property))
    '("path" "content"))
   :execution-mode :sequential
   :executor
   (lambda (call-id arguments)
     (declare (ignore call-id))
     (let* ((path
              (resolve-tool-path
               cwd (required-string arguments "path")))
            (content (required-string arguments "content")))
       (with-file-mutation-queue
        path
        (lambda ()
          (write-utf8-file path content)))
       (values
        (list
         (cadr-ai:make-text-content
          :text
          (format nil "Wrote ~D UTF-8 bytes to ~A"
                  (utf8-length content)
                  (namestring path))))
        (list :path (namestring path)
              :bytes (utf8-length content)))))))
