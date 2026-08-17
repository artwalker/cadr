(in-package #:cadr-cli)

(defun directory-entry-name (path)
  (let ((directory
          (uiop:directory-pathname-p path)))
    (if directory
        (format nil "~A/"
                (car (last (pathname-directory path))))
        (file-namestring path))))

(defun list-directory (cwd arguments)
  (let* ((path
           (resolve-tool-path
            cwd (optional-string arguments "path" ".")))
         (limit (optional-integer arguments "limit" 500)))
    (unless (probe-file path)
      (error "Path not found: ~A" (namestring path)))
    (let ((directory (uiop:directory-exists-p path)))
      (unless directory
        (error "Not a directory: ~A" (namestring path)))
    (when (< limit 1)
      (error "limit must be at least 1"))
    (let* ((entries
             (sort
              (append
               (uiop:directory-files directory)
               (uiop:subdirectories directory))
              #'string-lessp
              :key #'directory-entry-name))
           (limit-reached-p (> (length entries) limit))
           (selected
             (subseq entries 0 (min limit (length entries))))
           (raw-output
             (and selected
                  (join-lines
                   (mapcar #'directory-entry-name selected)))))
      (if (null selected)
          (values
           (list
            (cadr-ai:make-text-content
             :text "(empty directory)"))
           nil)
          (multiple-value-bind (output truncation)
              (truncate-head
               raw-output :max-lines most-positive-fixnum)
            (let ((notices nil)
                  (details nil))
              (when limit-reached-p
                (push
                 (format
                  nil
                  "~D entries limit reached. Use limit=~D for more"
                  limit (* 2 limit))
                 notices)
                (setf
                 (getf details :entry-limit-reached)
                 limit))
              (when (getf truncation :truncated)
                (push
                 (format nil "~A limit reached"
                         (format-byte-size
                          +maximum-output-bytes+))
                 notices)
                (setf (getf details :truncation)
                      truncation))
              (when notices
                (setf
                 output
                 (format nil "~A~%~%[~{~A~^. ~}]"
                         output (nreverse notices))))
              (values
               (list
                (cadr-ai:make-text-content :text output))
               details))))))))

(defun make-ls-tool (cwd)
  (cadr-ai:make-tool
   :name "ls"
   :description
   ;; Baseline core/tools/ls.ts:103.
   "List directory contents. Returns entries sorted alphabetically, with '/' suffix for directories. Includes dotfiles. Output is truncated to 500 entries or 50KB (whichever is hit first)."
   :parameters
   (object-schema
    (cadr-ai::json-object
     ;; Baseline core/tools/ls.ts:14-17.
     "path"
     (string-property
      "Directory to list (default: current directory)")
     "limit"
     (number-property "Maximum number of entries to return (default: 500)"))
    nil)
   :execution-mode :parallel
   :executor
   (lambda (call-id arguments)
     (declare (ignore call-id))
     (let ((display-path
             (optional-string arguments "path" ".")))
       (call-with-normalized-file-operation
        :ls display-path
        (lambda () (list-directory cwd arguments)))))))
