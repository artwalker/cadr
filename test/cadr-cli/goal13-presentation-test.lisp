(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun goal13-start-tool-block (state call)
  (cadr-cli::tui-handle-agent-event
   state
   (cadr-agent::make-agent-event
    :type :tool-execution-start
    :tool-call call))
  (cadr-cli::tui-entry-tool-block
   (car (last (cadr-cli::tui-state-entries state)))))

(defun goal13-finish-tool-block (state call result)
  (cadr-cli::tui-handle-agent-event
   state
   (cadr-agent::make-agent-event
    :type :tool-execution-end
    :tool-call call
    :tool-result result))
  (cadr-cli::tui-entry-tool-block
   (car (last (cadr-cli::tui-state-entries state)))))

(defun goal13-rendered-tool (block &optional (width 100))
  (format nil "~{~A~^~%~}"
          (cadr-tui:render-tool-block
           block width :ansi-theme-p t)))

(test goal13-tool-header-segments-match-baseline-colors-links-and-invalid-copy
  (let ((original-capabilities
          (cadr-tui:get-terminal-capabilities)))
    (unwind-protect
         (progn
           (cadr-tui:set-terminal-capabilities
            (cadr-tui:make-terminal-capabilities
             :images nil :true-color-p t :hyperlinks-p t))
           (let* ((home
                    (string-right-trim
                     "/" (namestring (user-homedir-pathname))))
                  (cwd (format nil "~A/projects/cadr/" home))
                  (find-call
                    (cadr-ai:make-tool-call
                     :id "find-segments" :name "find"
                     :arguments
                     (args "pattern" "*.lisp"
                           "path" cwd "limit" 4)))
                  (find-block
                    (goal13-start-tool-block
                     (cadr-cli::make-tui-state :cwd cwd)
                     find-call))
                  (find-rendered
                    (goal13-rendered-tool find-block))
                  (read-call
                    (cadr-ai:make-tool-call
                     :id "read-link" :name "read"
                     :arguments
                     (args "path" "src/a b.lisp"
                           "offset" 2 "limit" 3)))
                  (read-block
                    (goal13-start-tool-block
                     (cadr-cli::make-tui-state :cwd cwd)
                     read-call))
                  (read-rendered
                    (goal13-rendered-tool read-block)))
             (is
              (search
               (cadr-tui:theme-foreground
                :accent "*.lisp" :enabled-p t)
               find-rendered))
             (is
              (search
               (cadr-tui:theme-foreground
                :tool-output " in "
                :enabled-p t)
               find-rendered))
             (is
              (search
               (cadr-tui:theme-foreground
                :tool-output "~/projects/cadr/"
                :enabled-p t)
               find-rendered))
             (is
              (search
               (cadr-tui:theme-foreground
                :tool-output " (limit 4)"
                :enabled-p t)
               find-rendered))
             (is
              (search
               (format nil "file://~A/projects/cadr/src/a%20b.lisp"
                       home)
               read-rendered))
             (is
              (search
               (cadr-tui:theme-foreground
                :warning ":2-4" :enabled-p t)
               read-rendered))
             (let* ((prefixed
                      (concatenate 'string home "-shadow/file"))
                    (call
                      (cadr-ai:make-tool-call
                       :id "prefix-home" :name "read"
                       :arguments (args "path" prefixed))))
               (is
                (string=
                 (concatenate
                  'string "~" (subseq prefixed (length home)))
                 (cadr-cli::tool-arguments-summary call))))
             (dolist
                 (spec
                  (list
                   (list "read" (args "path" 7))
                   (list "write" (args "path" 7 "content" "x"))
                   (list "edit" (args "path" 7 "edits" #()))
                   (list "find" (args "pattern" 7 "path" 8))
                   (list "grep" (args "pattern" 7 "path" 8))
                   (list "ls" (args "path" 7))))
               (let* ((call
                        (cadr-ai:make-tool-call
                         :id (first spec)
                         :name (first spec)
                         :arguments (second spec)))
                      (block
                        (goal13-start-tool-block
                         (cadr-cli::make-tui-state :cwd cwd)
                         call))
                      (rendered (goal13-rendered-tool block)))
                 (is (search "[invalid arg]" rendered))
                 (is (null (search "[invalid path]" rendered)))
                 (is (null (search "[invalid pattern]" rendered)))
                 (is (null (search "[invalid command]" rendered)))))))
      (cadr-tui:set-terminal-capabilities original-capabilities))))

(test goal13-read-and-write-source-previews-use-baseline-syntax-colors
  (with-test-directory (directory)
    (let* ((source "const answer = 42;")
           (state
             (cadr-cli::make-tui-state
              :cwd (namestring directory)))
           (write-call
             (cadr-ai:make-tool-call
              :id "write-highlight" :name "write"
              :arguments
              (args "path" "answer.ts" "content" source)))
           (write-block
             (goal13-start-tool-block state write-call))
           (write-rendered
             (goal13-rendered-tool write-block)))
      (is
       (search
        (cadr-tui:theme-foreground
         :syntax-keyword "const" :enabled-p t)
        write-rendered))
      (let* ((read-state
               (cadr-cli::make-tui-state
                :cwd (namestring directory)))
             (read-call
               (cadr-ai:make-tool-call
                :id "read-highlight" :name "read"
                :arguments (args "path" "answer.ts")))
             (result
               (cadr-ai:make-tool-result-message
                :tool-call-id "read-highlight"
                :tool-name "read"
                :content
                (list
                 (cadr-ai:make-text-content :text source))
                :is-error nil)))
        (setf (cadr-cli::tui-state-tools-expanded-p read-state) t)
        (goal13-start-tool-block read-state read-call)
        (let* ((block
                 (goal13-finish-tool-block
                  read-state read-call result))
               (rendered (goal13-rendered-tool block)))
          (is
           (search
            (cadr-tui:theme-foreground
             :syntax-keyword "const" :enabled-p t)
            rendered)))))))

(test goal13-tool-results-use-tool-specific-colors-and-detail-warnings
  (let* ((bash-call
           (cadr-ai:make-tool-call
            :id "bash-error-color" :name "bash"
            :arguments (args "command" "exit 7")))
         (bash-state (cadr-cli::make-tui-state))
         (bash-result
           (cadr-ai:make-tool-result-message
            :tool-call-id "bash-error-color"
            :tool-name "bash" :is-error t
            :content
            (list
             (cadr-ai:make-text-content
              :text "Command exited with code 7")))))
    (goal13-start-tool-block bash-state bash-call)
    (let* ((block
             (goal13-finish-tool-block
              bash-state bash-call bash-result))
           (rendered (goal13-rendered-tool block)))
      (is
       (search
        (cadr-tui:theme-foreground
         :tool-output "Command exited with code 7"
         :enabled-p t)
        rendered))
      (is
       (null
        (search
         (cadr-tui:theme-foreground
          :error "Command exited with code 7"
          :enabled-p t)
         rendered))))
    (let* ((write-call
             (cadr-ai:make-tool-call
              :id "write-error-color" :name "write"
              :arguments
              (args "path" "x" "content" "y")))
           (write-state (cadr-cli::make-tui-state))
           (write-result
             (cadr-ai:make-tool-result-message
              :tool-call-id "write-error-color"
              :tool-name "write" :is-error t
              :content
              (list
               (cadr-ai:make-text-content :text "write failed")))))
      (goal13-start-tool-block write-state write-call)
      (is
       (search
        (cadr-tui:theme-foreground
         :error "write failed" :enabled-p t)
        (goal13-rendered-tool
         (goal13-finish-tool-block
          write-state write-call write-result)))))
    (let* ((find-call
             (cadr-ai:make-tool-call
              :id "find-warning" :name "find"
              :arguments (args "pattern" "*")))
           (find-state (cadr-cli::make-tui-state))
           (find-result
             (cadr-ai:make-tool-result-message
              :tool-call-id "find-warning"
              :tool-name "find" :is-error nil
              :content
              (list
               (cadr-ai:make-text-content
                :text
                (format nil
                        "a~%~%[2 results limit reached. Use limit=4 for more, or refine pattern]")))
              :details
              (list
               :result-limit-reached 2
               :truncation
               (list :truncated t :max-bytes (* 50 1024)))))
           (block
             (progn
               (goal13-start-tool-block find-state find-call)
               (goal13-finish-tool-block
                find-state find-call find-result)))
           (rendered (goal13-rendered-tool block)))
      (is
       (search
        (cadr-tui:theme-foreground
         :warning
         "[Truncated: 2 results limit, 50.0KB limit]"
         :enabled-p t)
        rendered)))))

(test goal13-edit-call-renders-preexecution-preview-and-validation-state
  (with-test-directory (directory)
    (write-text
     (merge-pathnames "edit.txt" directory)
     (format nil "alpha~%tail"))
    (let* ((state
             (cadr-cli::make-tui-state
              :cwd (namestring directory)))
           (call
             (cadr-ai:make-tool-call
              :id "edit-preview" :name "edit"
              :arguments
              (args
               "path" "edit.txt"
               "edits"
               (vector
                (args "oldText" "alpha"
                      "newText" "beta")))))
           (block (goal13-start-tool-block state call)))
      (is (search "-1 alpha" (cadr-tui:tool-block-output block)))
      (is (search "+1 beta" (cadr-tui:tool-block-output block)))
      (is (eq :complete
              (cadr-tui::tool-block-preview-status block))))
    (let* ((state
             (cadr-cli::make-tui-state
              :cwd (namestring directory)))
           (call
             (cadr-ai:make-tool-call
              :id "edit-preview-error" :name "edit"
              :arguments
              (args
               "path" "missing.txt"
               "edits"
               (vector
                (args "oldText" "a" "newText" "b")))))
           (block (goal13-start-tool-block state call)))
      (is
       (search "Could not edit file: missing.txt. Error code: ENOENT."
               (cadr-tui:tool-block-output block)))
      (is (eq :error
              (cadr-tui::tool-block-preview-status block))))))

(test goal13-compact-read-titles-match-baseline-classification-and-copy
  (with-test-directory (directory)
    (let* ((skill-directory
             (merge-pathnames "skills/example/" directory))
           (skill-path
             (merge-pathnames "SKILL.md" skill-directory))
           (resource-path
             (merge-pathnames "AGENTS.md" directory)))
      (write-text skill-path "skill")
      (write-text resource-path "resource")
      (dolist
          (case
           (list
            (list
             "skill" (namestring skill-path)
             "[skill] example (ctrl+o to expand)")
            (list
             "resource" (namestring resource-path)
             "read resource AGENTS.md (ctrl+o to expand)")))
        (destructuring-bind (id path expected) case
          (let* ((call
                   (cadr-ai:make-tool-call
                    :id id :name "read"
                    :arguments (args "path" path)))
                 (block
                   (goal13-start-tool-block
                    (cadr-cli::make-tui-state
                     :cwd (namestring directory))
                    call))
                 (plain
                   (cadr-tui:strip-terminal-sequences
                    (goal13-rendered-tool block))))
            (is (search expected plain))))))))

(test goal13-skill-branch-and-compaction-transcripts-match-baseline-components
  (let* ((state (cadr-cli::make-tui-state))
         (skill-message
           (cadr-ai:make-user-message
            :content
            (format nil
                    "<skill name=\"audit\" location=\"/tmp/SKILL.md\">~%Skill body.~%</skill>~%~%Please review.")))
         (branch
           (cadr-agent:make-branch-summary-message
            :summary "Branch **summary** body."))
         (compaction
           (cadr-agent:make-compaction-summary-agent-message
            :summary "Compaction **summary** body."
            :tokens-before 12345)))
    (cadr-cli::seed-tui-message state skill-message)
    (cadr-cli::seed-tui-message state branch)
    (cadr-cli::seed-tui-message state compaction)
    (is
     (equal
      '(:skill-invocation :user :branch-summary :compaction-summary)
      (mapcar #'cadr-cli::tui-entry-type
              (cadr-cli::tui-state-entries state))))
    (is
     (string= "Please review."
              (cadr-cli::tui-entry-text
               (second (cadr-cli::tui-state-entries state)))))
    (let ((collapsed
            (mapcar
             (lambda (entry)
               (mapcar
                #'cadr-tui:strip-terminal-sequences
                (cadr-cli::render-tui-entry entry 72)))
             (cadr-cli::tui-state-entries state))))
      ;; Baseline custom messages are full-width boxes with exactly one line
      ;; of vertical padding; branch/compaction add one internal spacer line.
      (is (= 3 (length (first collapsed))))
      (is (= 5 (length (third collapsed))))
      (is (= 5 (length (fourth collapsed))))
      (is (every
           (lambda (lines)
             (every (lambda (line) (= 72 (length line))) lines))
           (list (first collapsed) (third collapsed)
                 (fourth collapsed))))
      (is (find-if
           (lambda (line)
             (search "[skill] audit (ctrl+o to expand)" line))
           (first collapsed)))
      (is (find-if
           (lambda (line)
             (search "Branch summary (ctrl+o to expand)" line))
           (third collapsed)))
      (is (find-if
           (lambda (line)
             (search "Compacted from 12,345 tokens (ctrl+o to expand)" line))
           (fourth collapsed))))
    (cadr-cli::set-tui-tools-expanded state t)
    (let ((expanded
            (mapcar
             (lambda (entry)
               (format
                nil "~{~A~^~%~}"
                (mapcar
                 #'cadr-tui:strip-terminal-sequences
                 (cadr-cli::render-tui-entry entry 72))))
             (cadr-cli::tui-state-entries state))))
      (is (search "Skill body." (first expanded)))
      (is (search "Branch Summary" (third expanded)))
      (is (search "Branch summary body." (third expanded)))
      (is (search "Compacted from 12,345 tokens" (fourth expanded)))
      (is (search "Compaction summary body." (fourth expanded))))))

(test goal13-streaming-skill-message-uses-the-same-split-transcript-path
  (let* ((state (cadr-cli::make-tui-state))
         (message
           (cadr-ai:make-user-message
            :content
            (format nil
                    "<skill name=\"live\" location=\"/tmp/live/SKILL.md\">~%Live body.~%</skill>~%~%Do it."))))
    (cadr-cli::tui-handle-agent-event
     state
     (cadr-agent::make-agent-event
      :type :message-start :message message))
    (is
     (equal '(:skill-invocation :user)
            (mapcar #'cadr-cli::tui-entry-type
                    (cadr-cli::tui-state-entries state))))
    (is
     (string= "Do it."
              (cadr-cli::tui-entry-text
               (second (cadr-cli::tui-state-entries state)))))))

(test goal13-session-path-and-tree-timestamps-match-baseline-display-rules
  (let* ((home
           (string-right-trim
            "/" (namestring (user-homedir-pathname))))
         (prefix-only
           (concatenate 'string home "land/session.jsonl")))
    ;; Baseline deliberately uses a raw startsWith(home), including this
    ;; prefix-only edge case; presentation parity preserves that exact rule.
    (is (string= "~"
                 (cadr-cli::session-selector-shorten-path home)))
    (is (string= "~land/session.jsonl"
                 (cadr-cli::session-selector-shorten-path prefix-only)))
    (is (string= "/tmp/session.jsonl"
                 (cadr-cli::session-selector-shorten-path
                  "/tmp/session.jsonl"))))
  (let ((now
          (encode-universal-time
           0 0 15 2 8 2026 0)))
    (is (string= "09:07"
                 (cadr-cli::tree-selector-format-label-timestamp
                  "2026-08-02T09:07:11.000Z" now 0)))
    (is (string= "3/28 14:32"
                 (cadr-cli::tree-selector-format-label-timestamp
                  "2026-03-28T14:32:00.000Z" now 0)))
    (is (string= "25/12/31 23:59"
                 (cadr-cli::tree-selector-format-label-timestamp
                  "2025-12-31T23:59:00.000Z" now 0)))
    (is (string= "17:07"
                 (cadr-cli::tree-selector-format-label-timestamp
                  "2026-08-02T09:07:11.000Z" now -8)))
    (is (string= "07:30"
                 (cadr-cli::tree-selector-format-label-timestamp
                  "2026-08-02T10:00:00+02:30" now 0)))
    (is (string= "not-a-date"
                 (cadr-cli::tree-selector-format-label-timestamp
                  "not-a-date" now 0)))))
