(in-package #:cadr-cli)

(defparameter +default-coding-tool-names+
  '("read" "bash" "edit" "write"))

(defparameter +builtin-coding-tool-names+
  '("read" "bash" "edit" "write" "grep" "find" "ls"))

(defun make-baseline-coding-tools (cwd &key context)
  (list (make-read-tool cwd :context context)
        (make-bash-tool cwd :context context)
        (make-edit-tool cwd :context context)
        (make-write-tool cwd :context context)))

(defun make-coding-tools (cwd &key context)
  (make-baseline-coding-tools cwd :context context))

(defun make-all-coding-tools (cwd &key context)
  (append
   (make-baseline-coding-tools cwd :context context)
   (list
    (make-grep-tool cwd)
    (make-find-tool cwd)
    (make-ls-tool cwd))))

(defun select-coding-tools
    (tools &key allow exclude no-builtin-p builtin-names)
  (let ((selected
          (if allow
              (remove-if-not
               (lambda (tool)
                 (member (cadr-ai:tool-name tool)
                         allow :test #'string=))
               tools)
              (copy-list tools))))
    (when no-builtin-p
      (setf selected
            (remove-if
             (lambda (tool)
               (member (cadr-ai:tool-name tool)
                       builtin-names :test #'string=))
             selected)))
    (remove-if
     (lambda (tool)
       (member (cadr-ai:tool-name tool)
               exclude :test #'string=))
     selected)))

(defun tool-prompt-snippets (tools)
  (let ((baseline
          '(("read" . "Read file contents")
            ("bash"
             . "Execute bash commands (ls, grep, find, etc.)")
            ("edit"
             . "Make precise file edits with exact text replacement, including multiple disjoint edits in one call")
            ("write" . "Create or overwrite files")
            ("grep"
             . "Search file contents for patterns (respects .gitignore)")
            ("find"
             . "Find files by glob pattern (respects .gitignore)")
            ("ls" . "List directory contents"))))
    (mapcar
     (lambda (tool)
       (let* ((name (cadr-ai:tool-name tool))
              (snippet
                (cdr (assoc name baseline :test #'string=))))
         (cons
          name
          (or snippet
              (cadr-ai:tool-description tool)))))
     tools)))

(defun tool-prompt-guidelines (tools)
  (loop for tool in tools
        append
        (cond
          ((string= "read" (cadr-ai:tool-name tool))
           (list
            "Use read to examine files instead of cat or sed."))
          ((string= "edit" (cadr-ai:tool-name tool))
           (list
            "Use edit for precise changes (edits[].oldText must match exactly)"
            "When changing multiple separate locations in one file, use one edit call with multiple entries in edits[] instead of multiple edit calls"
            "Each edits[].oldText is matched against the original file, not after earlier edits are applied. Do not emit overlapping or nested edits. Merge nearby changes into one edit."
            "Keep edits[].oldText as small as possible while still being unique in the file. Do not pad with large unchanged regions."))
          ((string= "write" (cadr-ai:tool-name tool))
           (list
            "Use write only for new files or complete rewrites."))
          (t nil))))
