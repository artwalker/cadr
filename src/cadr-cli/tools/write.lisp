(in-package #:cadr-cli)

(defun ensure-write-parent-directories (path)
  (let ((parent
          (make-pathname :name nil :type nil :defaults path)))
    (when (and (probe-file parent)
               (not (uiop:directory-exists-p parent)))
      (let ((name (directory-namestring parent)))
        (error "EEXIST: file already exists, mkdir '~A'"
               (if (> (length name) 1)
                   (string-right-trim "/" name)
                   name))))
    (ensure-directories-exist path)))

(defun write-utf8-file (path content)
  (ensure-write-parent-directories path)
  (with-open-file (stream path
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create
                          :external-format :utf-8)
    (write-string content stream))
  path)

(defun make-write-tool (cwd &key context)
  (cadr-ai:make-tool
   :name "write"
   :description
   "Write content to a file. Creates the file if it doesn't exist, overwrites if it does. Automatically creates parent directories."
   :parameters
   (object-schema
    (cadr-ai::json-object
     ;; Baseline core/tools/write.ts.
     "path"
     (string-property "Path to the file to write (relative or absolute)")
     "content"
     (string-property "Content to write to the file"))
    '("path" "content"))
   :constrained-sampling (experimental-tool-sampling)
   :execution-mode :sequential
   :executor
   (lambda (call-id arguments)
     (declare (ignore call-id))
     (let ((display-path
             (required-string arguments "path")))
       (call-with-normalized-file-operation
        :write display-path
        (lambda ()
          (let* ((path
                   (if context
                       (resolve-execution-context-path
                        context cwd display-path)
                       (resolve-tool-path cwd display-path)))
                 (content
                   (required-string arguments "content")))
            (with-file-mutation-queue (path)
               (if context
                   (multiple-value-bind (value operation-error)
                       (cadr-agent:execution-tool-write
                        context path content)
                     (execution-context-value value operation-error))
                   (write-utf8-file path content)))
            (values
             (list
              (cadr-ai:make-text-content
               :text
               (format nil "Successfully wrote ~D bytes to ~A"
                       (utf16-code-unit-length content)
                       display-path)))
             nil))))))))
