(in-package #:cadr-cli)

(defun ripgrep-match-event (line)
  (handler-case
      (let ((event (cadr-ai::parse-json line)))
        (when (string= "match" (or (cadr-ai::json-get event "type") ""))
          (let* ((data (cadr-ai::json-get event "data"))
                 (path (and data (cadr-ai::json-get data "path")))
                 (lines (and data (cadr-ai::json-get data "lines")))
                 (path-text (and path (cadr-ai::json-get path "text")))
                 (line-text (and lines (cadr-ai::json-get lines "text")))
                 (line-number
                   (and data (cadr-ai::json-get data "line_number"))))
            (when (and (stringp path-text) (integerp line-number))
              (list :path path-text
                    :line-number line-number
                    :line-text line-text)))))
    (condition () nil)))

(defun ripgrep-line-text (text)
  (let ((without-returns
          (remove #\Return text)))
    (if (and (plusp (length without-returns))
             (char= #\Newline
                    (char without-returns
                          (1- (length without-returns)))))
        (subseq without-returns 0 (1- (length without-returns)))
        without-returns)))

(defun call-ripgrep-stream (arguments line-function)
  (let* ((process
           (handler-case
               (uiop:launch-program
                arguments
                :input nil
                :output :stream
                :error-output :stream
                :wait nil)
             (condition (condition)
               (error "Failed to run ripgrep: ~A" condition))))
         (stdout (uiop:process-info-output process))
         (stderr (uiop:process-info-error-output process))
         (stderr-capture (make-string-output-stream))
         (stderr-error nil)
         (stderr-reader
           (sb-thread:make-thread
            (lambda ()
              (handler-case
                  (loop for character = (read-char stderr nil :eof)
                        until (eq character :eof)
                        do (write-char character stderr-capture))
                (condition (condition)
                  (setf stderr-error condition))))
            :name "cadr-ripgrep-stderr-reader"))
         (stopped-p nil)
         (aborted-p nil)
         (status nil))
    (unwind-protect
         (progn
           (loop for line = (read-line stdout nil nil)
                 while line
                 do
                 (when (cadr-agent::current-tool-aborted-p)
                   (setf aborted-p t)
                   (uiop:terminate-process process)
                   (return))
                 (unless (funcall line-function line)
                   (setf stopped-p t)
                   (uiop:terminate-process process)
                   (return)))
           (setf status (or (uiop:wait-process process) 128))
           (cadr-core:stop-thread-for-cleanup
            stderr-reader :timeout 1.0d0)
           (when stderr-error
             (error stderr-error))
           (when aborted-p
             (error "Operation aborted"))
           (values
            (get-output-stream-string stderr-capture)
            status
            stopped-p))
      (when (uiop:process-alive-p process)
        (uiop:terminate-process process :urgent t)
        (ignore-errors (uiop:wait-process process)))
      (ignore-errors (close stdout))
      (ignore-errors (close stderr))
      (when (sb-thread:thread-alive-p stderr-reader)
        (cadr-core:stop-thread-for-cleanup
         stderr-reader :timeout 1.0d0)))))

(defun ripgrep-file-lines (file cache)
  (or (gethash file cache)
      (setf (gethash file cache)
            (make-text-line-table
             (uiop:read-file-string
              file :external-format :utf-8)))))

(defun ripgrep-context-block
    (file line-number context-count relative &optional cache)
  (handler-case
      (let* ((table
               (if cache
                   (ripgrep-file-lines file cache)
                   (make-text-line-table
                    (uiop:read-file-string
                     file :external-format :utf-8))))
             (source (first table))
             (starts (second table))
             (n (third table))
             (index (1- line-number))
             (start (max 0 (- index context-count)))
             (end (min n (+ index context-count 1)))
             (output nil)
             (truncated-p nil))
        (if (zerop n)
            (values
             (list
              (format nil "~A:~D: (unable to read file)"
                      relative line-number))
             nil)
            (progn
              (loop for context-index from start below end
                    for line = (text-line-ref source starts context-index)
                    for marker = (if (= context-index index) #\: #\-)
                    do
                    (multiple-value-bind (display-line line-truncated-p)
                        (truncate-tool-line line)
                      (when line-truncated-p
                        (setf truncated-p t))
                      (push
                       (format nil "~A~C~D~C ~A"
                               relative marker (1+ context-index)
                               marker display-line)
                       output)))
              (values (nreverse output) truncated-p))))
    (condition ()
      (when cache
        (remhash file cache))
      (values
       (list
        (format nil "~A:~D: (unable to read file)"
                relative line-number))
       nil))))

(defun grep-lines (cwd arguments)
  (let* ((pattern (required-string arguments "pattern"))
         (base
           (resolve-tool-path
            cwd (optional-string arguments "path" ".")))
         (filter (cadr-ai::json-get arguments "glob"))
         (literal-p (eq t (cadr-ai::json-get arguments "literal")))
         (ignore-case-p
           (eq t
               (or (cadr-ai::json-get arguments "ignoreCase")
                   (cadr-ai::json-get arguments "ignore_case"))))
         (context-count
           (max 0 (optional-integer arguments "context" 0)))
         (limit (max 1 (optional-integer arguments "limit" 100)))
         (output nil)
         (match-count 0)
         (match-limit-reached-p nil)
         (lines-truncated-p nil)
         (file-cache (make-hash-table :test #'equal)))
    (unless (probe-file base)
      (error "Path not found: ~A" (namestring base)))
    (let* ((directory-base (uiop:directory-exists-p base))
           (directory-p (not (null directory-base)))
           (rg (ensure-tool :rg :silent-p t)))
      (unless rg
        (error "ripgrep (rg) is not available and could not be downloaded"))
      (let ((command
              (append
               (list rg "--json" "--line-number" "--color=never" "--hidden")
               (when ignore-case-p (list "--ignore-case"))
               (when literal-p (list "--fixed-strings"))
               (when filter (list "--glob" filter))
               (list "--" pattern (namestring base)))))
        (multiple-value-bind (stderr status stopped-p)
            (call-ripgrep-stream
             command
             (lambda (line)
               (let ((match (ripgrep-match-event line)))
                 (if (null match)
                     t
                     (progn
                       (incf match-count)
                       (let* ((file
                                (or
                                 (ignore-errors
                                   (truename
                                    (pathname (getf match :path))))
                                 (pathname (getf match :path))))
                              (line-number
                                (getf match :line-number))
                              (line-text
                                (getf match :line-text))
                              (relative
                                (if directory-p
                                    (relative-posix-path
                                     file directory-base)
                                    (file-namestring file))))
                         (if (and (zerop context-count)
                                  (stringp line-text))
                             (multiple-value-bind
                                   (display-line truncated-p)
                                 (truncate-tool-line
                                  (ripgrep-line-text line-text))
                               (when truncated-p
                                 (setf lines-truncated-p t))
                               (push
                                (format nil "~A:~D: ~A"
                                        relative line-number display-line)
                                output))
                             (multiple-value-bind (block truncated-p)
                                 (ripgrep-context-block
                                  file line-number context-count relative
                                  file-cache)
                               (when truncated-p
                                 (setf lines-truncated-p t))
                               (dolist (entry block)
                                 (push entry output)))))
                       (if (>= match-count limit)
                           (progn
                             (setf match-limit-reached-p t)
                             nil)
                           t))))))
          (unless (or stopped-p (member status '(0 1)))
            (let ((message
                    (string-trim
                     '(#\Space #\Tab #\Newline #\Return)
                     stderr)))
              (error "~A"
                     (if (plusp (length message))
                         message
                         (format nil "ripgrep exited with code ~D" status))))))))
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
           details))))))

(defun make-grep-tool (cwd)
  (cadr-ai:make-tool
   :name "grep"
   :description
   ;; Baseline core/tools/grep.ts:131.
   "Search file contents for a pattern. Returns matching lines with file paths and line numbers. Respects .gitignore. Output is truncated to 100 matches or 50KB (whichever is hit first). Long lines are truncated to 500 chars."
   :parameters
   (object-schema
    (cadr-ai::json-object
     ;; Baseline core/tools/grep.ts:24-36 — camelCase ignoreCase, each
     ;; property with its baseline description.
     "pattern"
     (string-property "Search pattern (regex or literal string)")
     "path"
     (string-property
      "Directory or file to search (default: current directory)")
     "glob"
     (string-property
      "Filter files by glob pattern, e.g. '*.ts' or '**/*.spec.ts'")
     "ignoreCase"
     (boolean-property "Case-insensitive search (default: false)")
     "literal"
     (boolean-property
      "Treat pattern as literal string instead of regex (default: false)")
     "context"
     (number-property
      "Number of lines to show before and after each match (default: 0)")
     "limit"
     (number-property "Maximum number of matches to return (default: 100)"))
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
