(in-package #:cadr-cli)

(defun read-tool-file (cwd arguments)
  (let* ((offset (or (optional-integer arguments "offset" 1) 1))
         (limit (optional-integer arguments "limit"))
         (path
           (resolve-readable-tool-path
            cwd (required-string arguments "path"))))
    (multiple-value-bind (image-bytes mime-type hints)
        (process-image-file path)
      (when mime-type
        (let ((note
                (format nil "Read image file [~A]~@[~%~{~A~^~%~}~]"
                        mime-type hints)))
          (return-from read-tool-file
            (values
             (list
              (cadr-ai:make-text-content :text note)
              (cadr-ai:make-image-content
               :mime-type mime-type
               :data (encode-base64-bytes image-bytes)))
             nil)))))
    (let* ((text (uiop:read-file-string
                  path :external-format :utf-8))
           (lines (or (text-lines text) (list "")))
           (start (if (zerop offset)
                      0
                      (max 0 (1- offset)))))
      (when (and limit (< limit 1))
        (error "limit must be at least 1"))
      (when (>= start (length lines))
        (error "Offset ~D is beyond end of file (~D lines total)"
               offset (length lines)))
      (let* ((end (if limit
                      (min (length lines) (+ start limit))
                      (length lines)))
             (selected (subseq lines start end)))
        (multiple-value-bind (output details)
            (bounded-lines selected :head)
          (values
           (list (cadr-ai:make-text-content :text output))
           details))))))

(defun make-read-tool (cwd)
  (cadr-ai:make-tool
   :name "read"
   :description
   "Read the contents of a file. Supports text files and images (jpg, png, gif, webp, bmp). Images are sent as attachments. For text files, output is truncated to 2000 lines or 50KB (whichever is hit first). Use offset/limit for large files. When you need the full file, continue with offset until complete."
   :parameters
   (object-schema
    (cadr-ai::json-object
     "path" (string-property)
     "offset" (number-property)
     "limit" (number-property))
    '("path"))
   :execution-mode :parallel
   :executor
   (lambda (call-id arguments)
     (declare (ignore call-id))
     (read-tool-file cwd arguments))))
