(in-package #:cadr-cli)

(defparameter +default-coding-tool-names+
  '("read" "bash" "edit" "write"))

(defparameter +builtin-coding-tool-names+
  '("read" "bash" "powershell" "edit" "write" "grep" "find" "ls"
    "tool_search"))

(defun make-baseline-coding-tools
    (cwd &key context command-prefix shell-path)
  (list (make-read-tool cwd :context context)
        (make-bash-tool
         cwd
         :context context
         :command-prefix command-prefix
         :shell-path shell-path)
        (make-edit-tool cwd :context context)
        (make-write-tool cwd :context context)))

(defun make-coding-tools
    (cwd &key context command-prefix shell-path)
  (make-baseline-coding-tools
   cwd
   :context context
   :command-prefix command-prefix
   :shell-path shell-path))

(defun make-all-coding-tools
    (cwd &key context command-prefix shell-path)
  (append
   (make-baseline-coding-tools
    cwd
    :context context
    :command-prefix command-prefix
    :shell-path shell-path)
   (list
    (make-powershell-tool cwd :context context)
    (make-grep-tool cwd)
    (make-find-tool cwd)
    (make-ls-tool cwd)
    (cadr-agent:make-tool-search-tool))))

(defun tool-modifier-p (entry)
  ;; pi@4a080252f settings-manager.ts isToolModifier
  (and (stringp entry)
       (plusp (length entry))
       (or (char= (char entry 0) #\+)
           (char= (char entry 0) #\-))))

(defun tool-modifiers (tools)
  ;; pi@4a080252f sdk.ts: tools?.some(isToolModifier) ? tools : undefined
  (and tools (find-if #'tool-modifier-p tools) tools))

(defun tool-list-error (entries)
  ;; pi@4a080252f settings-manager.ts getToolListError
  (let ((modifiers
          (remove-if-not #'tool-modifier-p entries)))
    (cond
      ((null modifiers) nil)
      ((< (length modifiers) (length entries))
       "tool names cannot be mixed with +name or -name entries")
      ((find-if
        (lambda (entry) (find #\* entry :test #'char=))
        modifiers)
       (format
        nil
        "+name and -name entries take exact tool names, not patterns: ~A"
        (find-if
         (lambda (entry) (find #\* entry :test #'char=))
         modifiers)))
      (t nil))))

(defun apply-tool-modifiers (base entries)
  ;; pi@4a080252f settings-manager.ts applyToolModifiers
  (let ((tools (copy-list base)))
    (dolist (entry entries tools)
      (when (tool-modifier-p entry)
        (let* ((name (subseq entry 1))
               (index (position name tools :test #'string=)))
          (cond
            ((and (char= (char entry 0) #\+)
                  (null index)
                  (plusp (length name)))
             (setf tools (append tools (list name))))
            ((and (char= (char entry 0) #\-)
                  index)
             (setf tools
                   (append
                    (subseq tools 0 index)
                    (subseq tools (1+ index)))))))))))

(defun resolve-default-tools (entries)
  ;; pi@4a080252f settings-manager.ts resolveDefaultTools
  (let ((plain (remove-if #'tool-modifier-p entries)))
    (apply-tool-modifiers
     (if (or plain (null entries))
         plain
         +default-coding-tool-names+)
     entries)))

(defun explicitly-named-tool-names (entries &optional defaults)
  (append
   (remove-if #'tool-modifier-p entries)
   (loop for entry in entries
         when (and (tool-modifier-p entry)
                   (char= (char entry 0) #\+))
         collect (subseq entry 1))
   (copy-list defaults)))

(defun tool-allowlist-filters-mcp-names-p (names present-p)
  ;; pi@4a080252f agent-session.ts: an empty allowlist, or one that
  ;; names an mcp__ tool, stops keeping other MCP tools registered.
  (and present-p
       (or (null names)
           (some
            (lambda (name)
              (and (stringp name)
                   (uiop:string-prefix-p "mcp__" name)))
            names))))

(defun restore-active-tools-from-transcript
    (agent &key (modifiers '()) exclude-tools)
  ;; pi@4a080252f agent-session.ts _restoreToolsFromTranscript
  (cadr-agent::agent-restore-tools-from-transcript
   agent
   :modifiers modifiers
   :modifier-function #'apply-tool-modifiers
   :exclude-tools exclude-tools))

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
            ("powershell" . "Execute PowerShell commands")
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
