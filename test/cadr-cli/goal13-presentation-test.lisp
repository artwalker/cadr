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

(defparameter +goal13-semantic-theme-keys+
  '(:accent :border :border-accent :border-muted
    :success :error :warning :muted :dim :text
    :thinking-text
    :selected-bg :user-message-bg :user-message-text
    :custom-message-bg :custom-message-text
    :custom-message-label
    :tool-pending-bg :tool-success-bg :tool-error-bg
    :tool-title :tool-output
    :md-heading :md-link :md-link-url :md-code
    :md-code-block :md-code-block-border :md-quote
    :md-quote-border :md-hr :md-list-bullet
    :tool-diff-added :tool-diff-removed :tool-diff-context
    :syntax-comment :syntax-keyword :syntax-function
    :syntax-variable :syntax-string :syntax-number
    :syntax-type :syntax-operator :syntax-punctuation
    :thinking-off :thinking-minimal :thinking-low
    :thinking-medium :thinking-high :thinking-xhigh
    :thinking-max :bash-mode
    :page-bg :card-bg :info-bg))

(defun goal13-semantic-sentinel (index)
  (format nil "#~2,'0X~2,'0X~2,'0X"
          index (+ 80 index) (- 240 index)))

(defun goal13-semantic-overrides ()
  (loop for key in +goal13-semantic-theme-keys+
        for index from 1
        collect (cons key (goal13-semantic-sentinel index))))

(defun goal13-semantic-sentinel-for (key overrides)
  (cdr (assoc key overrides :test #'eq)))

(defun goal13-rendered-lines (lines)
  (format nil "~{~A~^~%~}" lines))

(defun goal13-semantic-span-present-p
    (key rendered marker &key background-p)
  (let* ((ansi
           (if background-p
               (cadr-tui:theme-background-ansi
                key :enabled-p t)
               (cadr-tui:theme-foreground-ansi
                key :enabled-p t)))
         (reset
           (format nil "~C[~Dm" #\Escape
                   (if background-p 49 39))))
    (loop with cursor = 0
          for ansi-position =
            (search ansi rendered :start2 cursor)
          while ansi-position
          for content-start = (+ ansi-position (length ansi))
          for reset-position =
            (or (search reset rendered :start2 content-start)
                (length rendered))
          for marker-position =
            (search marker rendered :start2 content-start
                                    :end2 reset-position)
          when marker-position return t
          do (setf cursor content-start)
          finally (return nil))))

(defun goal13-note-semantic-probe
    (seen key rendered marker &key background-p)
  ;; Requiring the marker to occur inside this token's ANSI span proves the
  ;; semantic key reached the intended production surface, not merely that a
  ;; renderer happened to use the color elsewhere in the same frame.
  (is
   (goal13-semantic-span-present-p
    key rendered marker :background-p background-p)
   "Semantic token ~S did not style marker ~S" key marker)
  (setf (gethash key seen) t))

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

(test goal13-all-semantic-theme-keys-drive-production-renderers
  (let* ((original-theme (cadr-tui:current-theme))
         (original-capabilities
           (cadr-tui:get-terminal-capabilities))
         (overrides (goal13-semantic-overrides))
         (seen (make-hash-table :test #'eq))
         (capabilities
           (cadr-tui:make-terminal-capabilities
            :images nil :true-color-p t :hyperlinks-p nil)))
    (unwind-protect
         (progn
           (cadr-tui:set-terminal-capabilities capabilities)
           (cadr-tui:set-current-theme
            :dark :overrides overrides
            :capabilities capabilities)
           ;; Frame, selector, and tree projections exercise the shared TUI
           ;; composition paths rather than directly formatting theme values.
           (let* ((frame
                    (goal13-rendered-lines
                     (cadr-cli::render-framed-select-state
                      (cadr-cli::make-framed-select-state
                       "Semantic frame" '("Semantic choice") '(:choice))
                      48)))
                  (session-selector
                    (goal13-rendered-lines
                     (cadr-cli::render-session-selector
                      (cadr-cli::make-session-selector-state
                       :current-sessions
                       (list
                        (cadr-cli::make-session-search-record
                         :id "semantic-session"
                         :path "/tmp/semantic-session.jsonl"
                         :cwd "/tmp"
                         :first-message "Semantic selected session"
                         :message-count 1
                         :modified 0
                         :all-messages-text
                         "Semantic selected session"))
                       :all-loaded-p t)
                      72)))
                  (fork-selector
                    (goal13-rendered-lines
                     (cadr-cli::render-user-message-selector
                      (cadr-cli::make-user-message-selector-state
                       :items
                       (list
                        (cadr-tui:make-select-item
                         :label "Semantic fork message"
                         :value "semantic-fork")))
                      48)))
                  (oauth
                    (goal13-rendered-lines
                     (cadr-cli::render-oauth-selector
                      (cadr-cli::make-oauth-selector-state
                       :options
                       (list
                        (cadr-cli::make-oauth-selector-option
                         :id :selected
                         :name "Semantic selected provider"
                         :auth-type :oauth)
                        (cadr-cli::make-oauth-selector-option
                         :id :unselected
                         :name "Semantic unselected provider"
                         :auth-type :api-key)))
                      72))))
             (goal13-note-semantic-probe
              seen :border frame (make-string 48 :initial-element #\─))
             (goal13-note-semantic-probe
              seen :accent frame "Semantic frame")
             (goal13-note-semantic-probe
              seen :border-muted fork-selector
              (make-string 48 :initial-element #\─))
             (goal13-note-semantic-probe
              seen :selected-bg session-selector
              "Semantic selected session"
              :background-p t)
             (goal13-note-semantic-probe
              seen :text oauth "Semantic unselected provider")
             (dolist
                 (probe
                  (list
                   (list
                    :success
                    (cadr-cli::tree-selector-entry-display-text
                     '(:type :message :role :assistant
                       :text "Semantic assistant")
                     nil)
                    "assistant: ")
                   (list
                    :muted
                    (cadr-cli::tree-selector-entry-display-text
                     '(:type :message :role :assistant :text "")
                     nil)
                    "(no content)")
                   (list
                    :dim
                    (cadr-cli::tree-selector-entry-display-text
                     '(:type :message :role :bash-execution
                       :text "Semantic shell")
                     nil)
                    "[bash]: Semantic shell")
                   (list
                    :warning
                    (cadr-cli::tree-selector-entry-display-text
                     '(:type :branch-summary
                       :text "Semantic branch")
                     nil)
                    "[branch summary]: ")
                   (list
                    :border-accent
                    (cadr-cli::tree-selector-entry-display-text
                     '(:type :compaction
                       :text "Semantic compaction")
                     nil)
                    "[compaction]: Semantic compaction")))
               (goal13-note-semantic-probe
                seen (first probe) (second probe) (third probe))))
           (let* ((error-rendered
                    (goal13-rendered-lines
                     (cadr-cli::render-tui-entry
                      (cadr-cli::make-tui-entry
                       :type :error :text "Semantic transport")
                      72)))
                  (thinking-rendered
                    (goal13-rendered-lines
                     (cadr-cli::render-tui-entry
                      (cadr-cli::make-tui-entry
                       :type :assistant
                       :content-blocks
                       (list
                        (cons :assistant-thinking
                              "Semantic thought")))
                      72)))
                  (user-rendered
                    (goal13-rendered-lines
                     (cadr-cli::render-tui-entry
                      (cadr-cli::make-tui-entry
                       :type :user :text "Semantic user body")
                      72)))
                  (custom-rendered
                    (goal13-rendered-lines
                     (cadr-cli::render-tui-entry
                      (cadr-cli::make-tui-entry
                       :type :skill-invocation
                       :label "Semantic skill label"
                       :text "Semantic skill body")
                      72))))
             (goal13-note-semantic-probe
              seen :error error-rendered
              "Error: Semantic transport")
             (goal13-note-semantic-probe
              seen :thinking-text thinking-rendered
              "Semantic thought")
             (goal13-note-semantic-probe
              seen :user-message-text user-rendered
              "Semantic user body")
             (goal13-note-semantic-probe
              seen :user-message-bg user-rendered
              "Semantic user body" :background-p t)
             (goal13-note-semantic-probe
              seen :custom-message-label custom-rendered "[skill]")
             (goal13-note-semantic-probe
              seen :custom-message-text custom-rendered
              "Semantic skill label")
             (goal13-note-semantic-probe
              seen :custom-message-bg custom-rendered
              "Semantic skill label" :background-p t))
           ;; Tool blocks cover all runtime states and the complete diff/output
           ;; surfaces through the same renderer used by the transcript.
           (let* ((pending
                    (goal13-rendered-tool
                     (cadr-tui:make-tool-block
                      :name "bash"
                      :summary "Semantic pending command"
                      :output "Semantic tool output"
                      :status :running :collapsed-p nil)))
                  (success
                    (goal13-rendered-tool
                     (cadr-tui:make-tool-block
                      :name "write"
                      :summary "Semantic success path"
                      :status :complete :collapsed-p nil)))
                  (failure
                    (goal13-rendered-tool
                     (cadr-tui:make-tool-block
                      :name "edit"
                      :summary "Semantic failure path"
                      :status :error :collapsed-p nil)))
                  (diff
                    (goal13-rendered-tool
                     (cadr-tui:make-tool-block
                      :name "edit" :summary "semantic.diff"
                      :output
                      (format nil
                              "-1 old semantic~%+1 new semantic~% 2 context semantic")
                      :status :complete :collapsed-p nil))))
             (goal13-note-semantic-probe
              seen :tool-pending-bg pending
              "Semantic pending command" :background-p t)
             (goal13-note-semantic-probe
              seen :tool-title pending
              "Semantic pending command")
             (goal13-note-semantic-probe
              seen :tool-output pending "Semantic tool output")
             (goal13-note-semantic-probe
              seen :tool-success-bg success
              "Semantic success path" :background-p t)
             (goal13-note-semantic-probe
              seen :tool-error-bg failure
              "Semantic failure path" :background-p t)
             (goal13-note-semantic-probe
              seen :tool-diff-removed diff "-1 ")
             (goal13-note-semantic-probe
              seen :tool-diff-added diff "+1 ")
             (goal13-note-semantic-probe
              seen :tool-diff-context diff " 2 context semantic"))
           ;; Each Markdown construct is rendered separately so a sentinel can
           ;; only be credited to the production surface named by the probe.
           (let ((heading
                   (goal13-rendered-lines
                    (cadr-tui:render-markdown
                     "# Semantic heading" 72
                     :ansi-theme-p t
                     :capabilities capabilities)))
                 (link
                   (goal13-rendered-lines
                    (cadr-tui:render-markdown
                     "[Semantic link](https://semantic.invalid)"
                     72 :ansi-theme-p t
                     :capabilities capabilities)))
                 (inline-code
                   (goal13-rendered-lines
                    (cadr-tui:render-markdown
                     "`semantic-inline`" 72
                     :ansi-theme-p t
                     :capabilities capabilities)))
                 (code-block
                   (goal13-rendered-lines
                    (cadr-tui:render-markdown
                     (format nil
                             "```text~%semantic-block~%```")
                     72 :ansi-theme-p t
                     :capabilities capabilities)))
                 (quote
                   (goal13-rendered-lines
                    (cadr-tui:render-markdown
                     "> semantic quote" 72
                     :ansi-theme-p t
                     :capabilities capabilities)))
                 (horizontal-rule
                   (goal13-rendered-lines
                    (cadr-tui:render-markdown
                     "---" 24 :ansi-theme-p t
                     :capabilities capabilities)))
                 (list-item
                   (goal13-rendered-lines
                    (cadr-tui:render-markdown
                     "- semantic list" 72
                     :ansi-theme-p t
                     :capabilities capabilities))))
             (goal13-note-semantic-probe
              seen :md-heading heading "Semantic heading")
             (goal13-note-semantic-probe
              seen :md-link link "Semantic link")
             (goal13-note-semantic-probe
              seen :md-link-url link "https://semantic.invalid")
             (goal13-note-semantic-probe
              seen :md-code inline-code "semantic-inline")
             (goal13-note-semantic-probe
              seen :md-code-block code-block "semantic-block")
             (goal13-note-semantic-probe
              seen :md-code-block-border code-block "```text")
             (goal13-note-semantic-probe
              seen :md-quote quote "semantic quote")
             (goal13-note-semantic-probe
              seen :md-quote-border quote "│")
             (goal13-note-semantic-probe
              seen :md-hr horizontal-rule
              (make-string 24 :initial-element #\─))
             (goal13-note-semantic-probe
              seen :md-list-bullet list-item "-"))
           ;; The CLI syntax highlighter is the production formatter passed to
           ;; read/write previews and fenced Markdown blocks.
           (let ((typescript
                   (cadr-cli::simple-syntax-highlight
                    (format nil
                            "// semantic-comment~%class SemanticType {~%  semanticFunction(semanticVariable: string) { return ~S + 42; }~%}"
                            "semantic-string")
                    "typescript"))
                 (sql
                   (cadr-cli::simple-syntax-highlight
                    "SELECT semantic_column FROM semantic_table WHERE semantic_column >= 42"
                    "sql"))
                 (html
                   (cadr-cli::simple-syntax-highlight
                    "<semantic-tag semantic-attr=\"semantic-value\">"
                    "html")))
             (goal13-note-semantic-probe
              seen :syntax-comment typescript "// semantic-comment")
             (goal13-note-semantic-probe
              seen :syntax-keyword typescript "class")
             (goal13-note-semantic-probe
              seen :syntax-function typescript "semanticFunction")
             (goal13-note-semantic-probe
              seen :syntax-variable typescript "semanticVariable")
             (goal13-note-semantic-probe
              seen :syntax-string typescript "\"semantic-string\"")
             (goal13-note-semantic-probe
              seen :syntax-number typescript "42")
             (goal13-note-semantic-probe
              seen :syntax-type typescript "string")
             (goal13-note-semantic-probe
              seen :syntax-operator sql ">=")
             (goal13-note-semantic-probe
              seen :syntax-punctuation html "<"))
           ;; Editor borders are the observable thinking-level and bash-mode
           ;; surfaces. Every level must select its own semantic token.
           (let ((editor
                   (cadr-tui:make-multiline-editor
                    :text "semantic editor" :prompt "")))
             (dolist
                 (entry
                  '((:off :thinking-off)
                    (:minimal :thinking-minimal)
                    (:low :thinking-low)
                    (:medium :thinking-medium)
                    (:high :thinking-high)
                    (:xhigh :thinking-xhigh)
                    (:max :thinking-max)))
               (cadr-tui:editor-set-border-mode
                editor :thinking (first entry))
               (multiple-value-bind (lines row column)
                   (cadr-tui:render-editor editor 40)
                 (declare (ignore row column))
                 (goal13-note-semantic-probe
                  seen (second entry)
                  (goal13-rendered-lines lines)
                  (make-string 40 :initial-element #\─))))
             (cadr-tui:editor-set-border-mode editor :bash)
             (multiple-value-bind (lines row column)
                 (cadr-tui:render-editor editor 40)
               (declare (ignore row column))
               (goal13-note-semantic-probe
                seen :bash-mode
                (goal13-rendered-lines lines)
                (make-string 40 :initial-element #\─))))
           ;; Export colors are non-ANSI production semantics. Verify both the
           ;; public export variables and the CSS locations that consume them.
           (with-test-directory (root)
             (let* ((sessions (merge-pathnames "sessions/" root))
                    (session
                      (cadr-agent:create-session
                       :directory sessions :cwd root
                       :id "goal13-semantic-theme"))
                    (path (merge-pathnames "theme.html" root))
                    (page
                      (goal13-semantic-sentinel-for
                       :page-bg overrides))
                    (card
                      (goal13-semantic-sentinel-for
                       :card-bg overrides))
                    (info
                      (goal13-semantic-sentinel-for
                       :info-bg overrides))
                    (theme
                      (args
                       "export"
                       (args "pageBg" page
                             "cardBg" card
                             "infoBg" info))))
               (cadr-agent:export-session-html
                session path :theme-name "goal13-sentinel"
                :theme-object theme)
               (let ((html (read-text path)))
                 (dolist
                     (probe
                      (list
                       (list :page-bg page
                             "--exportPageBg" "--body-bg")
                       (list :card-bg card
                             "--exportCardBg" "--container-bg")
                       (list :info-bg info
                             "--exportInfoBg" "--info-bg")))
                   (destructuring-bind
                         (key value public-name css-name) probe
                     (is
                      (search
                       (format nil "~A: ~A;" public-name value)
                       html))
                     (is
                      (search
                       (format nil "~A: ~A;" css-name value)
                       html))
                     (setf (gethash key seen) t))))))
           ;; The test-owned baseline list makes new, removed, or unprobed
           ;; semantic keys fail loudly instead of silently shrinking scope.
           (is
            (equal
             +goal13-semantic-theme-keys+
             (cadr-tui:terminal-theme-color-keys
              (cadr-tui:current-theme))))
           (is (= 55 (length +goal13-semantic-theme-keys+)))
           (is (= 55 (hash-table-count seen)))
           (is
            (null
             (set-difference
              +goal13-semantic-theme-keys+
              (loop for key being the hash-keys of seen
                    collect key)
              :test #'eq))))
      (cadr-tui:set-current-theme original-theme)
      (cadr-tui:set-terminal-capabilities original-capabilities))))

(defun goal13-ledger-section (text heading next-heading)
  (let ((start (search heading text))
        (end (and next-heading
                  (search next-heading text))))
    (unless (and start (or (null next-heading) end))
      (error "Missing presentation ledger section ~A" heading))
    (subseq text start end)))

(defun goal13-count-ledger-rows (text pattern)
  (count-if
   (lambda (line)
     (cl-ppcre:scan pattern line))
   (uiop:split-string text :separator '(#\Newline))))

(defun goal13-ledger-row-lines (text pattern)
  (remove-if-not
   (lambda (line)
     (cl-ppcre:scan pattern line))
   (uiop:split-string text :separator '(#\Newline))))

(defun goal13-ledger-row-cells (line)
  (mapcar
   (lambda (cell)
     (string-trim '(#\Space #\Tab) cell))
   (uiop:split-string line :separator '(#\|))))

(defun goal13-ledger-evidence-cell-p (cell)
  (cl-ppcre:scan
   "[A-Za-z0-9_./*+-]+[.](ts|lisp|css|html):[0-9]+"
   cell))

(defun goal13-production-lisp-files (directory)
  (labels ((collect-files (current)
             (append
              (uiop:directory-files current "*.lisp")
              (mapcan #'collect-files
                      (uiop:subdirectories current)))))
    (collect-files (uiop:ensure-directory-pathname directory))))

(test goal13-four-ledgers-and-presentation-denominators-stay-in-sync
  (let* ((root (asdf:system-source-directory "cadr-cli"))
         (readme
           (uiop:read-file-string
            (merge-pathnames "README.md" root)))
         (architecture
           (uiop:read-file-string
            (merge-pathnames "docs/architecture.md" root)))
         (docs-index
           (uiop:read-file-string
            (merge-pathnames "docs/README.md" root)))
         (performance
           (uiop:read-file-string
            (merge-pathnames "docs/performance.md" root)))
         (presentation
           (uiop:read-file-string
            (merge-pathnames
             "docs/presentation-parity.md" root))))
    (dolist (document
              (list readme architecture docs-index performance))
      (dolist (ledger
                '("parity-map.md"
                  "source-parity.md"
                  "performance.md"
                  "presentation-parity.md"))
        (is (search ledger document)
            "Four-ledger document is missing ~A" ledger)))
    (dolist (obsolete
              '("three independent ledgers"
                "three ledgers"
                "三本账"))
      (dolist (document
                (list readme architecture docs-index performance))
        (is (null (search obsolete document
                          :test #'char-equal))
            "Obsolete ledger count remains: ~A" obsolete)))
    (is
     (search
      "GOAL13_PRESENTATION_LEDGER baseline=74caa2649f10ed71b4378ce69f5d9fbfd2466ca5 b1=55 b2=52 b3=10 b4=6 total=123 aligned=119 pending=0 intentional=4"
      presentation))
    (is
     (search
      "GOAL13_OUTPUT_CHANNELS total=18 covered=18 pending=0"
      presentation))
    (let ((channels
            (goal13-ledger-section
             presentation
             "## Output-channel completeness gate"
             "## B1.")))
      (is (= 18
             (goal13-count-ledger-rows
              channels "^\\| C-[0-9]+ \\|")))
      (is (= 18
             (goal13-count-ledger-rows
              channels "^\\| C-[0-9]+ .*\\| 已覆盖 \\|$")))
      (is (= 18
             (goal13-count-ledger-rows
              channels "^\\| A-[0-9]+ \\|")))
      (dolist
          (required
           '("TUI screen"
             "stdout/stderr before TUI"
             "stdout after TUI teardown"
             "`--print`"
             "`--mode json`"
             "`--mode rpc`"
             "session JSONL"
             "exported session files"
             "`auth.json`"
             "settings, trust and installed-package"
             "SQLite"
             "outbound provider"
             "OAuth loopback"
             "Unix-socket"
             "process exit status"
             "server control-process"
             "eval runner"
             "runtime output during abnormal termination"))
        (is (search required channels)
            "Missing observable output channel: ~A"
            required))
      (dolist (channel
                '("C-01" "C-02" "C-03" "C-04" "C-05" "C-06"
                  "C-07" "C-08" "C-09" "C-10" "C-11" "C-12"
                  "C-13" "C-14" "C-15" "C-16" "C-17" "C-18"))
        (is (search channel
                    (goal13-ledger-section
                     channels
                     "### Exceptional-path closure"
                     nil))
            "Exceptional-path audit is missing ~A" channel)))
    (let ((b1 (goal13-ledger-section
               presentation "## B1." "## B2."))
          (b2 (goal13-ledger-section
               presentation "## B2." "## B3."))
          (b3 (goal13-ledger-section
               presentation "## B3." "## B4."))
          (b4 (goal13-ledger-section
               presentation "## B4." nil)))
      (is (= 55
             (goal13-count-ledger-rows
              b1 "^\\| `[^`]+` \\|")))
      (is (= 52
             (goal13-count-ledger-rows
              b2 "^\\| [A-Z]+-[0-9]+ \\|")))
      (is (= 10
             (goal13-count-ledger-rows
              b3 "^\\| [A-Z]+-[0-9]+ \\|")))
      (is (= 6
             (goal13-count-ledger-rows
              b4 "^\\| [A-Z]+-[0-9]+ \\|"))))))

(test goal13-presentation-ledger-recomputes-every-disposition-and-row-evidence
  (let* ((root (asdf:system-source-directory "cadr-cli"))
         (presentation
           (uiop:read-file-string
            (merge-pathnames
             "docs/presentation-parity.md" root)))
         (sections
           (list
            (list
             :b1
             (goal13-ledger-section
              presentation "## B1." "## B2.")
             "^\\| `[^`]+` \\|" 55 55 0 0)
            (list
             :b2
             (goal13-ledger-section
              presentation "## B2." "## B3.")
             "^\\| [A-Z]+-[0-9]+ \\|" 52 50 0 2)
            (list
             :b3
             (goal13-ledger-section
              presentation "## B3." "## B4.")
             "^\\| [A-Z]+-[0-9]+ \\|" 10 10 0 0)
            (list
             :b4
             (goal13-ledger-section
              presentation "## B4." nil)
             "^\\| [A-Z]+-[0-9]+ \\|" 6 4 0 2)))
         (total 0)
         (aligned 0)
         (pending 0)
         (intentional 0))
    (dolist (section sections)
      (destructuring-bind
            (name text pattern expected-total expected-aligned
                  expected-pending expected-intentional)
          section
        (let ((section-total 0)
              (section-aligned 0)
              (section-pending 0)
              (section-intentional 0))
          (dolist (line (goal13-ledger-row-lines text pattern))
            (let* ((cells (goal13-ledger-row-cells line))
                   (baseline-index (if (eq name :b1) 2 3))
                   (baseline (nth baseline-index cells))
                   (cadr (nth (1+ baseline-index) cells))
                   (status (nth (+ 2 baseline-index) cells)))
              (incf section-total)
              (is (goal13-ledger-evidence-cell-p baseline)
                  "~A baseline evidence lacks file:line: ~A"
                  name line)
              (is (goal13-ledger-evidence-cell-p cadr)
                  "~A Cadr evidence lacks file:line: ~A"
                  name line)
              (cond
                ((or (string= status "一致")
                     (search "不一致（已改齐）" status))
                 (incf section-aligned))
                ((search "有意差异" status)
                 (incf section-intentional))
                ((search "不一致" status)
                 (incf section-pending))
                (t
                 (fail "~A has an unknown disposition: ~A"
                       name line)))))
          (is (= expected-total section-total))
          (is (= expected-aligned section-aligned))
          (is (= expected-pending section-pending))
          (is (= expected-intentional section-intentional))
          (incf total section-total)
          (incf aligned section-aligned)
          (incf pending section-pending)
          (incf intentional section-intentional))))
    (is (= 123 total))
    (is (= 119 aligned))
    (is (= 0 pending))
    (is (= 4 intentional))))

(test goal13-lisp-idiom-audit-covers-the-current-production-file-set
  (let* ((root (asdf:system-source-directory "cadr-cli"))
         (audit
           (uiop:read-file-string
            (merge-pathnames "docs/lisp-idiom-audit.md" root)))
         (systems
           '(("cadr-core" 6)
             ("cadr-ai" 28)
             ("cadr-agent" 35)
             ("cadr-cli" 108)
             ("cadr-tui" 36)
             ("cadr-storage" 2)
             ("cadr-server" 11)
             ("cadr-protocol" 5)
             ("cadr-evals" 8)))
         (total 0))
    (is
     (search
      "GOAL13_LISP_IDIOM_AUDIT files=239 systems=9 axes=6 rewrite=1 keep=8"
      audit))
    (dolist (spec systems)
      (destructuring-bind (system expected) spec
        (let* ((directory
                 (merge-pathnames
                  (format nil "src/~A/" system) root))
               (actual
                 (length
                  (goal13-production-lisp-files directory))))
          (incf total actual)
          (is (= expected actual)
              "~A source-file count drifted" system)
          (is
           (search
            (format nil "| `~A` | ~D |" system expected)
            audit)
           "~A has no current module-audit row" system))))
    (is (= 239 total))
    (dolist
        (heading
         '("### 1. Manually maintained invariants"
           "### 2. Repeated dispatch logic"
           "### 3. Repeated boilerplate"
           "### 4. Error handling"
           "### 5. `defstruct` versus `defclass`"
           "### 6. Repeated bug classes"))
      (is (search heading audit)
          "Missing Lisp-idiom audit axis: ~A" heading))
    (dolist
        (path
         '("src/cadr-ai/crash.lisp"
           "src/cadr-cli/crash.lisp"
           "src/cadr-cli/interactive/{transcript,status,footer,theme,images,clipboard,syntax,tool-render-session}.lisp"
           "src/cadr-cli/interactive/selectors/{common,sessions,tree,settings,auth,models,trust,fork}.lisp"
           "src/cadr-cli/{support,settings,models,packages,extensions,sdk}/*.lisp"
           "src/cadr-cli/bootstrap/{tools,sessions,settings,auth,commands,main}.lisp"
           "src/cadr-cli/modes/rpc/{models,prompt-bash,sessions,commands,mode}.lisp"
           "src/cadr-tui/components/{markdown,image,tool-block,status,select-list}.lisp"
           "src/cadr-tui/composition/{protocol,text-box,rich-content,settings-list,loaders,root}.lisp"
           "src/cadr-tui/renderer/{terminal-protocol,virtual-terminal,lifecycle-input,main-screen,alt-screen}.lisp"
           "src/cadr-agent/{session,storage,loop}/*.lisp"
           "src/cadr-agent/extensions/*.lisp"
           "src/cadr-tui/threads.lisp"
           "src/cadr-core/{package,threads,cancellation,atomic-file,redacted-print,time}.lisp"))
      (is (search path audit)
          "Post-audit source addition has no disposition: ~A"
          path))))
