(in-package #:pi-cli)

(defun read-tool-file (cwd arguments)
  (let* ((path
           (resolve-tool-path
            cwd (required-string arguments "path")))
         (offset (or (optional-integer arguments "offset" 1) 1))
         (limit (optional-integer arguments "limit"))
         (text (uiop:read-file-string
                path :external-format :utf-8))
         (lines (text-lines text)))
    (when (< offset 1)
      (error "offset must be at least 1"))
    (when (and limit (< limit 1))
      (error "limit must be at least 1"))
    (when (> offset (max 1 (length lines)))
      (error "offset ~D is beyond the end of the file (~D lines)"
             offset (length lines)))
    (let* ((start (min (1- offset) (length lines)))
           (end (if limit
                    (min (length lines) (+ start limit))
                    (length lines)))
           (selected (subseq lines start end)))
      (multiple-value-bind (output details)
          (bounded-lines selected :head)
        (values
         (list (pi-ai:make-text-content :text output))
         details)))))

(defun make-read-tool (cwd)
  (pi-ai:make-tool
   :name "read"
   :description
   "Read a UTF-8 text file with optional 1-based offset and line limit."
   :parameters
   (object-schema
    (pi-ai::json-object
     "path" (string-property)
     "offset" (number-property)
     "limit" (number-property))
    '("path"))
   :execution-mode :parallel
   :executor
   (lambda (call-id arguments)
     (declare (ignore call-id))
     (read-tool-file cwd arguments))))
