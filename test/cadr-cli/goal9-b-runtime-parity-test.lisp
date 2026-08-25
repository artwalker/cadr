(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

;;; Goal 18 Part K: the model-visible tool contract is locked against
;;; test/fixtures/render-diff/baseline-tool-definitions.json, which the
;;; render-diff gate regenerates from the fixed baseline at capture time
;;; (check_baseline_tool_definitions) — no hand-maintained expectation
;;; table remains between cadr and the baseline tool definitions.

(defun goal9-baseline-tool-definitions ()
  (coerce
   (cadr-ai::json-get
    (cadr-ai::parse-json
     (uiop:read-file-string
      (merge-pathnames
       "test/fixtures/render-diff/baseline-tool-definitions.json"
       (asdf:system-source-directory "cadr-cli"))
      :external-format :utf-8))
    "tools")
   'list))

(defun goal9-baseline-tool-entry (name)
  (find name (goal9-baseline-tool-definitions)
        :key (lambda (entry) (cadr-ai::json-get entry "name"))
        :test #'string=))

(defun goal9-baseline-tool-descriptions ()
  (mapcar
   (lambda (entry)
     (cons (cadr-ai::json-get entry "name")
           (cadr-ai::json-get entry "description")))
   (goal9-baseline-tool-definitions)))

(defun goal9-baseline-tool-snippets ()
  (mapcar
   (lambda (entry)
     (cons (cadr-ai::json-get entry "name")
           (cadr-ai::json-get entry "promptSnippet")))
   (goal9-baseline-tool-definitions)))

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

(defun goal9-json-deep-equal (left right)
  (cond
    ((and (hash-table-p left) (hash-table-p right))
     (and (= (hash-table-count left) (hash-table-count right))
          (loop for key being the hash-keys of left
                  using (hash-value value)
                always (and (nth-value 1 (gethash key right))
                            (goal9-json-deep-equal
                             value (gethash key right))))))
    ((and (vectorp left) (vectorp right))
     (and (= (length left) (length right))
          (loop for index below (length left)
                always (goal9-json-deep-equal
                        (aref left index) (aref right index)))))
    (t (equal left right))))

(defun goal9-strip-cadr-schema-normalization (node)
  "cadr's wire serializer emits \"additionalProperties\": false on every
object schema and sorts keys; both are the established wire
normalization shared by all seven tools.  Strip exactly that key —
asserting it is false — so the remaining structure must equal the
baseline byte content."
  (if (hash-table-p node)
      (let ((result (cadr-ai::json-object)))
        (maphash
         (lambda (key value)
           (if (string= key "additionalProperties")
               (assert (member value '(nil :false)) (value)
                       "additionalProperties must be false, got ~S" value)
               (setf (gethash key result)
                     (goal9-strip-cadr-schema-normalization value))))
         node)
        result)
      (if (vectorp node)
          (map 'vector #'goal9-strip-cadr-schema-normalization node)
          node)))

(defun goal9-assert-tool-schema-matches (tool baseline-entry)
  (let* ((actual
           (goal9-strip-cadr-schema-normalization
            (cadr-ai::parse-json
             (cadr-ai::stringify-json
              (cadr-ai:tool-parameters tool)))))
         (expected
           (cadr-ai::json-get baseline-entry "parameters")))
    (is (goal9-json-deep-equal expected actual)
        "tool ~A parameter schema drifted from the baseline: ~S vs ~S"
        (cadr-ai:tool-name tool) actual expected)))

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
           '("read" "bash" "edit" "write" "powershell" "grep" "find" "ls")
           (mapcar #'cadr-ai:tool-name all-tools)))
      ;; Part K: every one of the seven tools, not just the default
      ;; four — description, parameter schema, and prompt snippet all
      ;; come from the gate-verified baseline fixture.
      (dolist (expected (goal9-baseline-tool-definitions))
        (let ((tool
                (goal9-tool-named
                 (cadr-ai::json-get expected "name") all-tools)))
          (is (not (null tool)))
          (is (string=
               (cadr-ai::json-get expected "description")
               (cadr-ai:tool-description tool)))
          (goal9-assert-tool-schema-matches tool expected)))
      (is (equal
           (goal9-baseline-tool-snippets)
           (cadr-cli::tool-prompt-snippets all-tools)))
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
