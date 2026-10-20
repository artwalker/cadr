(in-package #:cadr-cli)

(defparameter +default-coding-tool-names+
  '("read" "bash" "edit" "write"))

(defparameter +builtin-coding-tool-names+
  '("read" "bash" "powershell" "edit" "write" "grep" "find" "ls"))

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
    (make-ls-tool cwd))))

(defun tool-modifier-p (entry)
  ;; pi@71023aec1 settings-manager.ts isToolModifier
  (and (stringp entry)
       (plusp (length entry))
       (or (char= (char entry 0) #\+)
           (char= (char entry 0) #\-))))

(defun tool-modifiers (tools)
  ;; pi@71023aec1 sdk.ts: tools?.some(isToolModifier) ? tools : undefined
  (and tools (find-if #'tool-modifier-p tools) tools))

(defun tool-list-error (entries)
  ;; pi@71023aec1 settings-manager.ts getToolListError
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
  ;; pi@71023aec1 settings-manager.ts applyToolModifiers
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
  ;; pi@71023aec1 settings-manager.ts resolveDefaultTools
  (let ((plain (remove-if #'tool-modifier-p entries)))
    (apply-tool-modifiers
     (if (or plain (null entries))
         plain
         +default-coding-tool-names+)
     entries)))

(defun restore-active-tools-from-transcript
    (agent &key (modifiers '()) exclude-tools)
  ;; pi@71023aec1 agent-session.ts _restoreToolsFromTranscript
  (let ((system
          (cadr-ai:get-current-system-message
           (cadr-agent:agent-messages agent))))
    (unless system
      (return-from restore-active-tools-from-transcript nil))
    (let* ((recorded
             (mapcar
              #'cadr-ai:tool-name
              (or (cadr-ai:system-message-tools-added system)
                  '())))
           (names
             (apply-tool-modifiers recorded modifiers))
           (names
             (if exclude-tools
                 (remove-if
                  (lambda (name)
                    (member name exclude-tools
                            :test #'string=))
                  names)
                 names))
           (host
             (cadr-agent::agent-extension-host agent))
           (available
             (mapcar
              #'cadr-ai:tool-name
              (cadr-agent::merged-agent-tools agent)))
           (known
             (remove-if-not
              (lambda (name)
                (member name available :test #'string=))
              names)))
      (if host
          (cadr-agent::extension-host-set-active-tools
           host known)
          (progn
            (setf
             (cadr-agent::agent-tool-filter-function agent)
             (lambda (candidates)
               (remove-if-not
                (lambda (tool)
                  (member
                   (cadr-ai:tool-name tool)
                   known :test #'string=))
                candidates)))
            (cadr-agent::refresh-agent-extension-tools
             agent)))
      known)))

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
