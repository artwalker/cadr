(in-package #:cadr-cli)

(defvar *glob-scanner-cache*
  (make-hash-table :test #'equal)
  "Pattern string -> cl-ppcre scanner. find-pattern-match-p and
find-files share this so a walk does not rebuild the same regex
per file. fd compiles the pattern once per invocation.")

(defun cached-glob-scanner (pattern)
  (or (gethash pattern *glob-scanner-cache*)
      (setf (gethash pattern *glob-scanner-cache*)
            (glob-scanner pattern))))

(defun star-extension-suffix (pattern)
  "When PATTERN is a basename-only *.EXT with no other glob
metacharacters, return the \".EXT\" suffix. Else NIL."
  (let ((length (length pattern)))
    (when (and (>= length 2)
               (char= (char pattern 0) #\*)
               (char= (char pattern 1) #\.)
               (not (find #\/ pattern))
               (not (find #\? pattern))
               (= 1 (count #\* pattern)))
      (subseq pattern 1))))

(defun find-pattern-match-p (pattern relative)
  (let* ((path-p (find #\/ pattern))
         (target
           (if path-p
               relative
               (file-namestring relative)))
         (suffix
           (and (not path-p)
                (star-extension-suffix pattern))))
    (cond
      (suffix
       (let ((n (length target))
             (m (length suffix)))
         (and (>= n m)
              (string-equal target suffix
                            :start1 (- n m))
              0)))
      (t
       (cl-ppcre:scan
        (cached-glob-scanner pattern)
        target)))))

(defun find-files (cwd arguments)
  (let* ((pattern (required-string arguments "pattern"))
         (base
           (resolve-tool-path
            cwd (optional-string arguments "path" ".")))
         (canonical-base
           (and (uiop:directory-exists-p base)
                (truename (uiop:ensure-directory-pathname base))))
         (limit (optional-integer arguments "limit" 1000)))
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
   ;; Baseline core/tools/find.ts:117.
   "Search for files by glob pattern. Returns matching file paths relative to the search directory. Respects .gitignore. Output is truncated to 1000 results or 50KB (whichever is hit first)."
   :parameters
   (object-schema
    (cadr-ai::json-object
     ;; Baseline core/tools/find.ts:21-26.
     "pattern"
     (string-property
      "Glob pattern to match files, e.g. '*.ts', '**/*.json', or 'src/**/*.spec.ts'")
     "path"
     (string-property
      "Directory to search in (default: current directory)")
     "limit"
     (number-property "Maximum number of results (default: 1000)"))
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
