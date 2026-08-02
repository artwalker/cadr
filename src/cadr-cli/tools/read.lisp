(in-package #:cadr-cli)

(defun read-tool-file (cwd arguments &key context)
  (let* ((offset (or (optional-integer arguments "offset" 1) 1))
         (limit (optional-integer arguments "limit"))
         (display-path (required-string arguments "path"))
         (path
           (if context
               (resolve-execution-context-path context cwd display-path)
               (resolve-readable-tool-path cwd display-path)))
         (bytes
           (and context
                (multiple-value-bind (value operation-error)
                    (cadr-agent:execution-tool-read-binary context path)
                  (execution-context-value value operation-error)))))
    (unless (or context (probe-file path))
      (error "File not found: ~A" display-path))
    (multiple-value-bind
          (image-bytes mime-type hints omitted-message)
        (if context
            (process-image-data bytes)
            (call-with-normalized-file-operation
             :read display-path
             (lambda () (process-image-file path))))
      (when mime-type
        (let ((note
                (format
                 nil "Read image file [~A]~@[~%~{~A~^~%~}~]~@[~%~A~]"
                 mime-type hints omitted-message)))
          (return-from read-tool-file
            (values
             (if omitted-message
                 (list
                  (cadr-ai:make-text-content :text note))
                 (list
                  (cadr-ai:make-text-content :text note)
                  (cadr-ai:make-image-content
                   :mime-type mime-type
                   :data
                   (encode-base64-bytes image-bytes))))
             nil)))))
    (let* ((text (if context
                     (cadr-ai::utf8-string bytes)
                     (call-with-normalized-file-operation
                      :read display-path
                      (lambda ()
                        (uiop:read-file-string
                         path :external-format :utf-8)))))
           (lines (split-all-lines text))
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
             (selected (subseq lines start end))
             (selected-content (join-lines selected))
             (start-display (1+ start))
             (user-limited-lines
               (and limit (- end start))))
        (multiple-value-bind (output details)
            (truncate-head selected-content)
          (cond
            ((getf details :first-line-exceeds-limit)
             (setf
              output
              (format
               nil
               "[Line ~D is ~A, exceeds ~A limit. Use bash: sed -n '~Dp' ~A | head -c ~D]"
               start-display
               (format-byte-size
                (utf8-length (nth start lines)))
               (format-byte-size +maximum-output-bytes+)
               start-display
               display-path
               +maximum-output-bytes+)))
            ((getf details :truncated)
             (let* ((output-lines
                      (getf details :output-lines))
                    (end-display
                      (+ start-display output-lines -1))
                    (next-offset (1+ end-display)))
               (setf
                output
                (format
                 nil
                 "~A~%~%[Showing lines ~D-~D of ~D~A. Use offset=~D to continue.]"
                 output start-display end-display
                 (length lines)
                 (if (eq (getf details :truncated-by) :bytes)
                     (format nil " (~A limit)"
                             (format-byte-size
                              +maximum-output-bytes+))
                     "")
                 next-offset))))
            ((and user-limited-lines
                  (< (+ start user-limited-lines)
                     (length lines)))
             (let ((remaining
                     (- (length lines)
                        (+ start user-limited-lines)))
                   (next-offset
                     (+ start user-limited-lines 1)))
               (setf
                output
                (format
                 nil
                 "~A~%~%[~D more lines in file. Use offset=~D to continue.]"
                 output remaining next-offset)))))
          (values
           (list (cadr-ai:make-text-content :text output))
           (and (getf details :truncated) details)))))))

(defun make-read-tool (cwd &key context)
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
     (let ((display-path
             (required-string arguments "path")))
       (call-with-normalized-file-operation
        :read display-path
        (lambda ()
          (read-tool-file
           cwd arguments :context context)))))))
