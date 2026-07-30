(in-package #:cadr-cli)

(defun regex-special-p (character)
  (find character ".^$+()[]{}|\\"))

(defun glob-regex-source (pattern)
  (with-output-to-string (output)
    (write-char #\^ output)
    (loop with index = 0
          while (< index (length pattern))
          for character = (char pattern index)
          do
          (cond
            ((char= character #\*)
             (if (and (< (1+ index) (length pattern))
                      (char= #\* (char pattern (1+ index))))
                 (progn
                   (incf index)
                   (if (and (< (1+ index) (length pattern))
                            (char= #\/
                                   (char pattern (1+ index))))
                       (progn
                         (incf index)
                         (write-string "(?:.*/)?" output))
                       (write-string ".*" output)))
                 (write-string "[^/]*" output)))
            ((char= character #\?)
             (write-string "[^/]" output))
            ((regex-special-p character)
             (write-char #\\ output)
             (write-char character output))
            (t
             (write-char character output)))
          (incf index))
    (write-char #\$ output)))

(defun glob-scanner (pattern)
  (cl-ppcre:create-scanner (glob-regex-source pattern)))

(defstruct gitignore-rule
  base
  scanner
  negated-p)

(defun glob-regex-body (pattern)
  (let ((source (glob-regex-source pattern)))
    (subseq source 1 (1- (length source)))))

(defun gitignore-regex-source (pattern anchored-p directory-only-p)
  (let ((body (glob-regex-body pattern)))
    (cond
      (anchored-p
       (format nil "^~A~A"
               body
               (if directory-only-p "/" "(?:$|/)")))
      (directory-only-p
       (format nil "(?:^|/)~A/" body))
      (t
       (format nil "(?:^|/)~A(?:$|/)" body)))))

(defun parse-gitignore-line (line base)
  (let ((text (string-right-trim '(#\Return #\Space #\Tab) line)))
    (cond
      ((or (zerop (length text))
           (char= #\# (char text 0)))
       nil)
      (t
       (let* ((escaped-marker-p
                (and (> (length text) 1)
                     (char= #\\ (char text 0))
                     (find (char text 1) "#!")))
              (negated-p
                (and (not escaped-marker-p)
                     (char= #\! (char text 0))))
              (raw
                (cond
                  (escaped-marker-p (subseq text 1))
                  (negated-p (subseq text 1))
                  (t text)))
              (directory-only-p
                (and (plusp (length raw))
                     (char= #\/
                            (char raw (1- (length raw))))))
              (without-trailing
                (if directory-only-p
                    (subseq raw 0 (1- (length raw)))
                    raw))
              (leading-slash-p
                (and (plusp (length without-trailing))
                     (char= #\/ (char without-trailing 0))))
              (pattern
                (if leading-slash-p
                    (subseq without-trailing 1)
                    without-trailing))
              (anchored-p
                (or leading-slash-p
                    (find #\/ pattern))))
         (when (plusp (length pattern))
           (make-gitignore-rule
            :base base
            :scanner
            (cl-ppcre:create-scanner
             (gitignore-regex-source
              pattern anchored-p directory-only-p))
            :negated-p negated-p)))))))

(defun directory-gitignore-rules (directory)
  (let ((path (merge-pathnames
               ".gitignore"
               (uiop:ensure-directory-pathname directory))))
    (when (probe-file path)
      (remove
       nil
       (mapcar
        (lambda (line)
          (parse-gitignore-line line directory))
        (uiop:read-file-lines path
                              :external-format :utf-8))))))

(defun gitignored-p (path rules)
  (let ((ignored-p nil))
    (dolist (rule rules ignored-p)
      (when (uiop:subpathp path (gitignore-rule-base rule))
        (let ((relative
                (relative-posix-path
                 path (gitignore-rule-base rule))))
          (when (cl-ppcre:scan
                 (gitignore-rule-scanner rule) relative)
            (setf ignored-p
                  (not (gitignore-rule-negated-p rule)))))))))

(defun ignored-directory-p (directory)
  (member
   (car (last (pathname-directory
               (uiop:ensure-directory-pathname directory))))
   '(".git" "node_modules")
   :test #'string=))

(defun collect-tree-files (root)
  (let ((files nil)
        (canonical-root
          (truename (uiop:ensure-directory-pathname root))))
    (labels ((walk (directory inherited-rules)
               (let ((rules
                       (append
                        inherited-rules
                        (directory-gitignore-rules directory))))
               (dolist (file (uiop:directory-files directory))
                   (unless (gitignored-p file rules)
                     (push file files)))
               (dolist (child (uiop:subdirectories directory))
                 (unless (ignored-directory-p child)
                     ;; Git can re-include a descendant with a later negation,
                     ;; so ignored directories are traversed but their files
                     ;; remain filtered.
                     (walk child rules))))))
      (walk canonical-root nil))
    (sort files #'string<
          :key (lambda (path)
                 (relative-posix-path path canonical-root)))))

(defun glob-files (cwd arguments)
  (let* ((pattern (required-string arguments "pattern"))
         (base
           (resolve-tool-path
            cwd (or (cadr-ai::json-get arguments "path") ".")))
         (limit (or (optional-integer arguments "limit" 1000)
                    1000))
         (scanner (glob-scanner pattern))
         (matches
           (loop for file in (collect-tree-files base)
                 for relative-base =
                   (relative-posix-path file base)
                 when (cl-ppcre:scan scanner relative-base)
                   collect (relative-posix-path file cwd))))
    (when (< limit 1)
      (error "limit must be at least 1"))
    (let* ((truncated (> (length matches) limit))
           (selected (subseq matches 0 (min limit (length matches))))
           (text
             (if selected
                 (join-lines selected)
                 "No files found")))
      (values
       (list (cadr-ai:make-text-content :text text))
       (list :truncated truncated
             :matches (length matches))))))

(defun make-glob-tool (cwd)
  (cadr-ai:make-tool
   :name "glob"
   :description
   "Find files recursively with a glob pattern; follows .gitignore and ignores .git and node_modules."
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
     (glob-files cwd arguments))))
