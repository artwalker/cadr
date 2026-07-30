(in-package #:pi-cli)

(defun grep-matcher (pattern literal-p ignore-case-p)
  (cl-ppcre:create-scanner
   (if literal-p
       (cl-ppcre:quote-meta-chars pattern)
       pattern)
   :case-insensitive-mode ignore-case-p))

(defun grep-lines (cwd arguments)
  (let* ((pattern (required-string arguments "pattern"))
         (base
           (resolve-tool-path
            cwd (or (pi-ai::json-get arguments "path") ".")))
         (filter (pi-ai::json-get arguments "glob"))
         (filter-scanner (and filter (glob-scanner filter)))
         (literal-p (eq t (pi-ai::json-get arguments "literal")))
         (ignore-case-p
           (eq t (pi-ai::json-get arguments "ignore_case")))
         (context-count
           (or (optional-integer arguments "context" 0) 0))
         (limit (or (optional-integer arguments "limit" 1000)
                    1000))
         (scanner
           (grep-matcher pattern literal-p ignore-case-p))
         (output nil)
         (match-count 0)
         (truncated nil))
    (when (or (< context-count 0) (< limit 1))
      (error "context must be nonnegative and limit must be positive"))
    (block search
      (dolist (file (collect-tree-files base))
        (let ((relative-base (relative-posix-path file base)))
          (when (or (null filter-scanner)
                    (cl-ppcre:scan filter-scanner relative-base))
            (handler-case
                (let* ((lines
                         (text-lines
                          (uiop:read-file-string
                           file :external-format :utf-8)))
                       (relative (relative-posix-path file cwd)))
                  (loop for line in lines
                        for index from 0
                        when (cl-ppcre:scan scanner line)
                          do
                          (incf match-count)
                          (let ((start
                                  (max 0 (- index context-count)))
                                (end
                                  (min (length lines)
                                       (+ index context-count 1))))
                            (loop for context-index
                                    from start below end
                                  for marker =
                                    (if (= context-index index)
                                        #\:
                                        #\-)
                                  do
                                  (push
                                   (format
                                    nil "~A~C~D~C~A"
                                    relative marker
                                    (1+ context-index) marker
                                    (let ((text
                                            (nth context-index
                                                 lines)))
                                      (if (> (length text) 10000)
                                          (subseq text 0 10000)
                                          text)))
                                   output)))
                          (when (>= match-count limit)
                            (setf truncated t)
                            (return-from search))))
              (error () nil))))))
    (let ((raw-output
            (if output
                (join-lines (nreverse output))
                "No matches found")))
      (multiple-value-bind (bounded-output bounds)
          (truncate-head raw-output)
        (values
         (list
          (pi-ai:make-text-content
           :text bounded-output))
         (list
          :truncated
          (or truncated (getf bounds :truncated))
          :matches match-count))))))

(defun make-grep-tool (cwd)
  (pi-ai:make-tool
   :name "grep"
   :description
   "Search UTF-8 files using regex or literal text with optional context."
   :parameters
   (object-schema
    (pi-ai::json-object
     "pattern" (string-property)
     "path" (string-property)
     "glob" (string-property)
     "literal" (boolean-property)
     "ignore_case" (boolean-property)
     "context" (number-property)
     "limit" (number-property))
    '("pattern"))
   :execution-mode :parallel
   :executor
   (lambda (call-id arguments)
     (declare (ignore call-id))
     (grep-lines cwd arguments))))
