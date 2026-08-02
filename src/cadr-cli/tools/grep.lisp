(in-package #:cadr-cli)

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
            cwd (optional-string arguments "path" ".")))
         (filter (cadr-ai::json-get arguments "glob"))
         (filter-scanner (and filter (glob-scanner filter)))
         (literal-p (eq t (cadr-ai::json-get arguments "literal")))
         (ignore-case-p
           (eq t
               (or (cadr-ai::json-get arguments "ignoreCase")
                   (cadr-ai::json-get arguments "ignore_case"))))
         (context-count
           (max 0
                (or (optional-integer arguments "context" 0) 0)))
         (limit (max 1
                     (or (optional-integer arguments "limit" 100)
                         100)))
         (scanner
           (grep-matcher pattern literal-p ignore-case-p))
         (output nil)
         (match-count 0)
         (match-limit-reached-p nil)
         (lines-truncated-p nil))
    (unless (probe-file base)
      (error "Path not found: ~A" (namestring base)))
    (let* ((directory-base
             (uiop:directory-exists-p base))
           (directory-p (not (null directory-base)))
           (files
             (if directory-p
                 (collect-tree-files directory-base)
                 (list base))))
    (block search
      (dolist (file files)
        (let ((relative-base
                (if directory-p
                    (relative-posix-path file directory-base)
                    (file-namestring file))))
          (when (or (null filter-scanner)
                    (cl-ppcre:scan filter-scanner relative-base))
            (handler-case
                (let* ((lines
                         (text-lines
                          (uiop:read-file-string
                           file :external-format :utf-8)))
                       (relative relative-base))
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
                                  (multiple-value-bind
                                        (display-line truncated-p)
                                      (truncate-tool-line
                                       (nth context-index lines))
                                    (when truncated-p
                                      (setf lines-truncated-p t))
                                    (push
                                     (format
                                      nil "~A~C~D~C ~A"
                                      relative marker
                                      (1+ context-index) marker
                                      display-line)
                                     output))))
                          (when (>= match-count limit)
                            (setf match-limit-reached-p t)
                            (return-from search))))
              (error () nil))))))
    (let ((raw-output
            (if output
                (join-lines (nreverse output))
                "No matches found")))
      (when (null output)
        (return-from grep-lines
          (values
           (list
            (cadr-ai:make-text-content :text raw-output))
           nil)))
      (multiple-value-bind (bounded-output bounds)
          (truncate-head
           raw-output :max-lines most-positive-fixnum)
        (let ((notices nil)
              (details nil))
          (when match-limit-reached-p
            (push
             (format
              nil
              "~D matches limit reached. Use limit=~D for more, or refine pattern"
              limit (* 2 limit))
             notices)
            (setf (getf details :match-limit-reached)
                  limit))
          (when (getf bounds :truncated)
            (push
             (format nil "~A limit reached"
                     (format-byte-size
                      +maximum-output-bytes+))
             notices)
            (setf (getf details :truncation) bounds))
          (when lines-truncated-p
            (push
             "Some lines truncated to 500 chars. Use read tool to see full lines"
             notices)
            (setf (getf details :lines-truncated) t))
          (when notices
            (setf
             bounded-output
             (format nil "~A~%~%[~{~A~^. ~}]"
                     bounded-output (nreverse notices))))
          (values
           (list
            (cadr-ai:make-text-content
             :text bounded-output))
           details)))))))

(defun make-grep-tool (cwd)
  (cadr-ai:make-tool
   :name "grep"
   :description
   "Search UTF-8 files using regex or literal text with optional context."
   :parameters
   (object-schema
    (cadr-ai::json-object
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
     (let ((display-path
             (optional-string arguments "path" ".")))
       (call-with-normalized-file-operation
        :grep display-path
        (lambda () (grep-lines cwd arguments)))))))
