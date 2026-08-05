(in-package #:cadr-cli)

(defun find-pattern-match-p (pattern relative)
  (if (find #\/ pattern)
      (cl-ppcre:scan (glob-scanner pattern) relative)
      (cl-ppcre:scan
       (glob-scanner pattern)
       (file-namestring relative))))

(defun find-files (cwd arguments)
  (let* ((pattern (required-string arguments "pattern"))
         (base
           (resolve-tool-path
            cwd (optional-string arguments "path" ".")))
         (canonical-base
           (and (uiop:directory-exists-p base)
                (truename (uiop:ensure-directory-pathname base))))
         (limit (or (optional-integer arguments "limit" 1000) 1000)))
    (unless canonical-base
      (error "[fd error]: Search path '~A' is not a directory.~%[fd error]: No valid search paths given."
             (namestring base)))
    (when (< limit 1)
      (error "limit must be at least 1"))
    (let* ((matches
             (loop for file in (collect-tree-files canonical-base)
                   for relative = (relative-posix-path
                                   file canonical-base)
                   when (find-pattern-match-p pattern relative)
                     collect relative))
           (limit-reached-p (>= (length matches) limit))
           (selected
             (subseq matches 0 (min limit (length matches))))
           (raw-output
             (and selected (join-lines selected))))
      (if (null selected)
          (values
           (list
            (cadr-ai:make-text-content
             :text "No files found matching pattern"))
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
                  "~D results limit reached. Use limit=~D for more, or refine pattern"
                  limit (* 2 limit))
                 notices)
                (setf
                 (getf details :result-limit-reached)
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
               details)))))))

(defun make-find-tool (cwd)
  (cadr-ai:make-tool
   :name "find"
   :description
   "Search for files by glob pattern, respecting .gitignore."
   :parameters
   (object-schema
    (cadr-ai::json-object
     "pattern" (string-property)
     "path" (string-property)
     "limit" (number-property))
    '("pattern"))
   :execution-mode :parallel
   :executor
   (lambda (call-id arguments)
     (declare (ignore call-id))
     (let ((display-path
             (optional-string arguments "path" ".")))
       (call-with-normalized-file-operation
        :find display-path
        (lambda () (find-files cwd arguments)))))))
