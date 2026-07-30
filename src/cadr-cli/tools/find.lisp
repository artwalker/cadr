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
            cwd (or (cadr-ai::json-get arguments "path") ".")))
         (canonical-base
           (and (uiop:directory-exists-p base)
                (truename (uiop:ensure-directory-pathname base))))
         (limit (or (optional-integer arguments "limit" 1000) 1000)))
    (unless canonical-base
      (error "Path not found: ~A" (namestring base)))
    (when (< limit 1)
      (error "limit must be at least 1"))
    (let* ((matches
             (loop for file in (collect-tree-files canonical-base)
                   for relative = (relative-posix-path
                                   file canonical-base)
                   when (find-pattern-match-p pattern relative)
                     collect relative))
           (truncated (> (length matches) limit))
           (selected
             (subseq matches 0 (min limit (length matches))))
           (text
             (if selected
                 (join-lines selected)
                 "No files found matching pattern")))
      (values
       (list (cadr-ai:make-text-content :text text))
       (and truncated
            (list :result-limit-reached limit))))))

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
     (find-files cwd arguments))))
