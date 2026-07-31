(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defparameter +goal9-baseline-tool-descriptions+
  '(("read"
     . "Read the contents of a file. Supports text files and images (jpg, png, gif, webp, bmp). Images are sent as attachments. For text files, output is truncated to 2000 lines or 50KB (whichever is hit first). Use offset/limit for large files. When you need the full file, continue with offset until complete.")
    ("bash"
     . "Execute a bash command in the current working directory. Returns stdout and stderr. Output is truncated to last 2000 lines or 50KB (whichever is hit first). If truncated, full output is saved to a temp file. Optionally provide a timeout in seconds.")
    ("edit"
     . "Edit a single file using exact text replacement. Every edits[].oldText must match a unique, non-overlapping region of the original file. If two changes affect the same block or nearby lines, merge them into one edit instead of emitting overlapping edits. Do not include large unchanged regions just to connect distant changes.")
    ("write"
     . "Write content to a file. Creates the file if it doesn't exist, overwrites if it does. Automatically creates parent directories.")))

(defparameter +goal9-baseline-tool-snippets+
  '(("read" . "Read file contents")
    ("bash" . "Execute bash commands (ls, grep, find, etc.)")
    ("edit"
     . "Make precise file edits with exact text replacement, including multiple disjoint edits in one call")
    ("write" . "Create or overwrite files")))

(defparameter +goal9-baseline-tool-guidelines+
  '("Use read to examine files instead of cat or sed."
    "Use edit for precise changes (edits[].oldText must match exactly)"
    "When changing multiple separate locations in one file, use one edit call with multiple entries in edits[] instead of multiple edit calls"
    "Each edits[].oldText is matched against the original file, not after earlier edits are applied. Do not emit overlapping or nested edits. Merge nearby changes into one edit."
    "Keep edits[].oldText as small as possible while still being unique in the file. Do not pad with large unchanged regions."
    "Use write only for new files or complete rewrites."))

(defun goal9-tool-named (name tools)
  (find name tools :key #'cadr-ai:tool-name :test #'string=))

(defun goal9-rendered-line-present-p (text lines)
  (find
   text lines
   :test
   (lambda (expected rendered)
     (string=
      expected
      (string-trim '(#\Space #\Tab) rendered)))))

(test goal9-default-tool-and-prompt-contract-matches-audit-baseline
  (with-test-directory (directory)
    (let* ((default-tools
             (cadr-cli:make-coding-tools directory))
           (all-tools
             (cadr-cli::make-all-coding-tools directory)))
      (is (equal
           '("read" "bash" "edit" "write")
           (mapcar #'cadr-ai:tool-name default-tools)))
      (is (equal
           '("read" "bash" "edit" "write"
             "grep" "find" "ls")
           (mapcar #'cadr-ai:tool-name all-tools)))
      (dolist (expected +goal9-baseline-tool-descriptions+)
        (let ((tool
                (goal9-tool-named
                 (car expected) all-tools)))
          (is (not (null tool)))
          (is (string=
               (cdr expected)
               (cadr-ai:tool-description tool)))))
      (is (equal
           +goal9-baseline-tool-snippets+
           (cadr-cli::tool-prompt-snippets default-tools)))
      (is (equal
           +goal9-baseline-tool-guidelines+
           (cadr-cli::tool-prompt-guidelines default-tools)))
      (let ((prompt
              (cadr-cli:build-system-prompt
               :selected-tools
               (mapcar #'cadr-ai:tool-name default-tools)
               :tool-snippets
               (cadr-cli::tool-prompt-snippets default-tools)
               :prompt-guidelines
               (cadr-cli::tool-prompt-guidelines default-tools)
               :cwd (namestring directory))))
        (is (search
             "You are an expert coding assistant operating inside cadr, a coding agent harness."
             prompt))
        (is (search "- read: Read file contents" prompt))
        (is (search
             "- bash: Execute bash commands (ls, grep, find, etc.)"
             prompt))
        (is (search
             "- edit: Make precise file edits with exact text replacement, including multiple disjoint edits in one call"
             prompt))
        (is (search "- write: Create or overwrite files" prompt))
        (is (not (search "- grep:" prompt)))
        (is (not (search "- find:" prompt)))
        (is (not (search "- ls:" prompt)))
        (is (search
             "In addition to the tools above, you may have access to other custom tools depending on the project."
             prompt))
        (is (search "- Be concise in your responses" prompt))
        (is (search
             "- Show file paths clearly when working with files"
             prompt))
        (dolist (guideline +goal9-baseline-tool-guidelines+)
          (is (search (format nil "- ~A" guideline) prompt)))
        (is (search
             (format nil "Current working directory: ~A"
                     (namestring directory))
             prompt))))))

(test goal9-streamed-multiline-assistant-output-stays-line-oriented-every-frame
  (let* ((width 32)
         (rows 12)
         (state
           (cadr-cli::make-tui-state
            :model "faux" :session "stream-lines"))
         (editor (cadr-tui:make-multiline-editor))
         (terminal
           (cadr-tui:make-virtual-terminal
            :columns width :rows rows))
         (renderer
           (cadr-tui:make-terminal-renderer terminal :alt-p t))
         (message
           (cadr-ai:make-assistant-message
            :api :faux :provider :faux :model "faux"
            :stop-reason :stop))
         (expected ""))
    (cadr-cli::tui-handle-agent-event
     state
     (cadr-agent::make-agent-event
      :type :message-start :message message))
    (loop for line-number from 1 to 120
          for text = (format nil "~D" line-number)
          for delta = (if (= line-number 1)
                          text
                          (format nil "~%~A" text))
          do
          (setf expected
                (concatenate 'string expected delta))
          (cadr-cli::tui-handle-agent-event
           state
           (cadr-agent::make-agent-event
            :type :message-update
            :message message
            :stream-event
            (cadr-ai:make-stream-event
             :type :text-delta :delta delta)))
          (is (string=
               expected
               (cadr-cli::tui-entry-text
                (cadr-cli::tui-state-current-assistant state))))
          (multiple-value-bind (document row column)
              (cadr-cli::render-tui-state
               state editor width rows :full-document-p t)
            (let ((plain-document
                    (mapcar #'cadr-tui:strip-terminal-sequences
                            document)))
              (is (goal9-rendered-line-present-p
                   text plain-document))
              (when (> line-number 1)
                (is (goal9-rendered-line-present-p
                     (format nil "~D" (1- line-number))
                     plain-document))))
            (cadr-tui:render-frame
             renderer document
             :cursor-row row :cursor-column column)
            (let ((snapshot
                    (mapcar #'cadr-tui:strip-terminal-sequences
                            (cadr-tui:virtual-terminal-snapshot
                             terminal))))
              (is (goal9-rendered-line-present-p
                   text snapshot)))))
    (is (= 119
           (count
            #\Newline
            (cadr-cli::tui-entry-text
             (cadr-cli::tui-state-current-assistant state))))
        "The final event stream must retain every explicit line boundary.")))

(test goal9-streamed-markdown-fence-is-exact-through-the-full-tui-chain
  (let* ((width 32)
         (rows 12)
         (state
           (cadr-cli::make-tui-state
            :model "faux" :session "stream-fence"))
         (editor (cadr-tui:make-multiline-editor))
         (terminal
           (cadr-tui:make-virtual-terminal
            :columns width :rows rows))
         (renderer
           (cadr-tui:make-terminal-renderer terminal :alt-p t))
         (message
           (cadr-ai:make-assistant-message
            :api :faux :provider :faux :model "faux"
            :stop-reason :stop))
         (expected "")
         (deltas
           (list "```te" (format nil "xt~%alpha")
                 (format nil "~%``") "`")))
    (cadr-cli::tui-handle-agent-event
     state
     (cadr-agent::make-agent-event
      :type :message-start :message message))
    (dolist (delta deltas)
      (setf expected
            (concatenate 'string expected delta))
      (cadr-cli::tui-handle-agent-event
       state
       (cadr-agent::make-agent-event
        :type :message-update
        :message message
        :stream-event
        (cadr-ai:make-stream-event
         :type :text-delta :delta delta)))
      (is
       (string=
        expected
        (cadr-cli::tui-entry-text
         (cadr-cli::tui-state-current-assistant state))))
      (multiple-value-bind (document row column)
          (cadr-cli::render-tui-state
           state editor width rows :full-document-p t)
        (cadr-tui:render-frame
         renderer document :cursor-row row :cursor-column column)))
    (cadr-cli::tui-handle-agent-event
     state
     (cadr-agent::make-agent-event
      :type :message-end :message message))
    (let ((plain-screen
            (mapcar
             (lambda (line)
               (string-right-trim
                " "
                (cadr-tui:strip-terminal-sequences line)))
             (cadr-tui:virtual-terminal-snapshot terminal))))
      (is (find " ```text" plain-screen :test #'string=))
      (is (find "   alpha" plain-screen :test #'string=))
      (is (find " ```" plain-screen :test #'string=)))))
