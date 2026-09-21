(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defclass goal17-scripted-terminal
    (cadr-tui::virtual-terminal)
  ((inputs :initarg :inputs
           :accessor goal17-scripted-terminal-inputs)))

(defmethod cadr-tui:terminal-read-input
    ((terminal goal17-scripted-terminal))
  (let* ((inputs (goal17-scripted-terminal-inputs terminal))
         (input (first inputs)))
    (if (functionp input)
        (let ((value (funcall input)))
          ;; Keep a deferred input at the head of the script until its
          ;; synchronization predicate says the raw bytes are ready.  This
          ;; leaves the TUI loop free to consume agent events meanwhile.
          (when value
            (pop (goal17-scripted-terminal-inputs terminal)))
          (or value ""))
        (progn
          (pop (goal17-scripted-terminal-inputs terminal))
          (or input "")))))

(defclass goal17-live-bash-terminal
    (cadr-tui::virtual-terminal)
  ((inputs :initarg :inputs
           :accessor goal17-live-bash-terminal-inputs)
   (running-rendered
    :initform (sb-thread:make-semaphore :count 0)
    :reader goal17-live-bash-terminal-running-rendered)
   (complete-rendered
    :initform (sb-thread:make-semaphore :count 0)
    :reader goal17-live-bash-terminal-complete-rendered)
   (completion-marker
    :initarg :completion-marker
    :reader goal17-live-bash-terminal-completion-marker)))

(defun goal17-live-bash-terminal-screen (terminal)
  (format
   nil "~{~A~^~%~}"
   (mapcar
    #'cadr-tui:strip-terminal-sequences
    (cadr-tui:virtual-terminal-snapshot terminal))))

(defmethod cadr-tui:terminal-read-input
    ((terminal goal17-live-bash-terminal))
  (let* ((inputs (goal17-live-bash-terminal-inputs terminal))
         (input (first inputs)))
    (if (functionp input)
        (let ((value (funcall input terminal)))
          (when value
            (pop (goal17-live-bash-terminal-inputs terminal)))
          (or value ""))
        (progn
          (pop (goal17-live-bash-terminal-inputs terminal))
          (or input "")))))

(defmethod cadr-tui:terminal-write :after
    ((terminal goal17-live-bash-terminal) text)
  (declare (ignore text))
  (let ((screen (goal17-live-bash-terminal-screen terminal)))
    (when (and (search "Running... (escape/ctrl+c to cancel)" screen)
               (search "chunk-arrived" screen))
      (sb-thread:signal-semaphore
       (goal17-live-bash-terminal-running-rendered terminal)))
    (when (search
           (goal17-live-bash-terminal-completion-marker terminal)
           screen)
      (sb-thread:signal-semaphore
      (goal17-live-bash-terminal-complete-rendered terminal)))))

(test goal17-work-render-ack-fires-after-worker-cleanup-terminal-write
  (let ((work-rendered
          (sb-thread:make-semaphore :count 0))
        (prompt-line nil)
        (settled-screen nil)
        (settled-scrollback-wipes 0)
        (settled-canonical-repaints 0))
    (let ((terminal
            (make-instance
             'goal17-scripted-terminal
             :columns 80 :rows 16
             :inputs
             (list
              (format nil "event~C" #\Return)
              (let ((attempts 0))
                (lambda ()
                  (cond
                    ((sb-thread:try-semaphore work-rendered)
                     (format nil "/quit~C" #\Return))
                    ((> (incf attempts) 5000)
                     (error "Work render acknowledgement was never emitted"))
                    (t nil))))))))
      (let ((cadr-tui:*canonical-repaint-hook*
              (lambda (renderer)
                (declare (ignore renderer))
                (incf settled-canonical-repaints))))
        (cadr-cli::run-tui
         (lambda (line)
           (setf prompt-line line))
         :work-rendered-function
         (lambda ()
         (setf
          settled-screen
         (format
           nil "~{~A~^~%~}"
           (cadr-tui:virtual-terminal-snapshot terminal)))
         (setf
          ;; Goal 18 I05: the acknowledgement repaint is a canonical
          ;; in-place redraw of the visible region, never the
          ;; scrollback-wiping 2J/H/3J full clear.
          settled-scrollback-wipes
          (count-if
           (lambda (write)
             (search
              (format nil "~C[2J~C[H~C[3J"
                      #\Escape #\Escape #\Escape)
              write))
         (cadr-tui::virtual-writes terminal)))
        (sb-thread:signal-semaphore work-rendered))
        :model "faux"
        :terminal terminal)))
    (is (string= "event" prompt-line))
    (is-true settled-screen)
    (is (= 0 settled-scrollback-wipes))
    (is (= 1 settled-canonical-repaints))
    (is (null (search "Working..." settled-screen)))))

(test goal17-work-render-ack-does-not-redraw-local-commands
  (let ((work-render-count 0)
        (command-lines nil))
    (cadr-cli::run-tui
     (constantly nil)
     :command-function
     (lambda (line)
       (push line command-lines)
       (values t "local done"))
     :work-rendered-function
     (lambda ()
       (incf work-render-count))
     :model "faux"
     :terminal
     (make-instance
      'goal17-scripted-terminal
      :columns 80 :rows 16
      :inputs
      (list
       (format nil "/local~C" #\Return)
       (format nil "/quit~C" #\Return))))
    (is (equal '("/local") command-lines))
    (is (= 0 work-render-count))))

(test goal17-user-bash-result-is-rendered-through-the-tui
  (let ((terminal
          (make-instance
           'goal17-scripted-terminal
           :columns 80 :rows 16
           :inputs
           (list
            (format nil "!render~C" #\Return)
            (format nil "/quit~C" #\Return)))))
    (cadr-cli::run-tui
     (constantly nil)
     :bash-function
     (lambda (command exclude-p)
       (declare (ignore command exclude-p))
       "Output truncated. Full output: /tmp/fixed.log")
     :model "faux"
     :terminal terminal)
    (is
     (search
      "Output truncated. Full output: /tmp/fixed.log"
      (format nil "~{~A~^~%~}"
              (cadr-tui:virtual-terminal-snapshot terminal))))))

(test goal17-direct-bash-renders-running-output-and-completes-the-same-entry
  ;; pi@13cbf77df interactive-mode.ts:6052-6075 creates the
  ;; BashExecutionComponent before executeBash and appends every onChunk
  ;; delta to that same component.  The semaphores freeze the command after
  ;; its first chunk so this assertion observes the live state, not a final
  ;; result reconstructed after execution.
  (let* ((release-command (sb-thread:make-semaphore :count 0))
         (running-screen nil)
         (complete-screen nil)
         (result
           (cadr-cli::make-user-bash-result
            :command "blocked-command"
            :output "chunk-arrived"
            :exit-code 7))
         (terminal
           (make-instance
            'goal17-live-bash-terminal
            :columns 80 :rows 18
            :completion-marker "(exit 7)"
            :inputs
            (list
             (format nil "!blocked-command~C" #\Return)
             (let ((attempts 0))
               (lambda (current)
                 (cond
                   ((sb-thread:try-semaphore
                     (goal17-live-bash-terminal-running-rendered current))
                    (setf running-screen
                          (goal17-live-bash-terminal-screen current))
                    (sb-thread:signal-semaphore release-command)
                    "")
                   ((> (incf attempts) 5000)
                    (sb-thread:signal-semaphore release-command)
                    (error "Running bash frame was never rendered"))
                   (t nil))))
             (let ((attempts 0))
               (lambda (current)
                 (cond
                   ((sb-thread:try-semaphore
                     (goal17-live-bash-terminal-complete-rendered current))
                    (setf complete-screen
                          (goal17-live-bash-terminal-screen current))
                    (format nil "/quit~C" #\Return))
                   ((> (incf attempts) 5000)
                    (error "Completed bash frame was never rendered"))
                   (t nil))))))))
    (cadr-cli::run-tui
     (constantly nil)
     :bash-function
     (lambda (command exclude-p)
       (declare (ignore command exclude-p))
       (when cadr-cli::*bash-live-output*
         (write-string "chunk-arrived" cadr-cli::*bash-live-output*)
         (finish-output cadr-cli::*bash-live-output*))
       (sb-thread:wait-on-semaphore release-command)
       result)
     :model "faux"
     :terminal terminal)
    (is (search "Running... (escape/ctrl+c to cancel)" running-screen))
    (is (search "chunk-arrived" running-screen))
    (is (= 1 (count-substring "$ blocked-command" complete-screen)))
    (is (search "chunk-arrived" complete-screen))
    (is (search "(exit 7)" complete-screen))
    (is (null (search "Running..." complete-screen)))
    ;; Rendering completion must not rewrite the result that the bootstrap
    ;; records in agent/session history.
    (is (string= "chunk-arrived"
                 (cadr-cli::user-bash-result-output result)))
    (is (= 7 (cadr-cli::user-bash-result-exit-code result)))))

(test goal17-direct-bash-cancellation-updates-the-running-entry-in-place
  (let* ((cancel-command (sb-thread:make-semaphore :count 0))
         (complete-screen nil)
         (terminal
           (make-instance
            'goal17-live-bash-terminal
            :columns 80 :rows 18
            :completion-marker "(cancelled)"
            :inputs
            (list
             (format nil "!blocked-cancel~C" #\Return)
             (let ((attempts 0))
               (lambda (current)
                 (cond
                   ((sb-thread:try-semaphore
                     (goal17-live-bash-terminal-running-rendered current))
                    (string #\Escape))
                   ((> (incf attempts) 5000)
                    (sb-thread:signal-semaphore cancel-command)
                    (error "Running cancellable bash frame was never rendered"))
                   (t nil))))
             (let ((attempts 0))
               (lambda (current)
                 (cond
                   ((sb-thread:try-semaphore
                     (goal17-live-bash-terminal-complete-rendered current))
                    (setf complete-screen
                          (goal17-live-bash-terminal-screen current))
                    (format nil "/quit~C" #\Return))
                   ((> (incf attempts) 5000)
                    (error "Cancelled bash frame was never rendered"))
                   (t nil))))))))
    (cadr-cli::run-tui
     (constantly nil)
     :bash-function
     (lambda (command exclude-p)
       (declare (ignore command exclude-p))
       (when cadr-cli::*bash-live-output*
         (write-string "chunk-arrived" cadr-cli::*bash-live-output*)
         (finish-output cadr-cli::*bash-live-output*))
       (sb-thread:wait-on-semaphore cancel-command)
       (cadr-cli::make-user-bash-result
        :command "blocked-cancel"
        :output "chunk-arrived"
        :cancelled-p t))
     :abort-function
     (lambda ()
       (sb-thread:signal-semaphore cancel-command))
     :model "faux"
     :terminal terminal)
    (is (= 1 (count-substring "$ blocked-cancel" complete-screen)))
    (is (search "chunk-arrived" complete-screen))
    (is (search "(cancelled)" complete-screen))
    (is (null (search "Running..." complete-screen)))))

(test goal17-bootstrap-tui-bash-projection-preserves-live-chunk-stream
  ;; The real CLI bootstrap reprojects frontend output by mode before calling
  ;; EXECUTE-USER-BASH-FOR-TUI.  TUI must preserve the controller-installed
  ;; stream; REPL and machine-readable modes retain their existing targets.
  (with-test-directory (directory)
    (let* ((chunks nil)
           (stream
             (cadr-cli::make-notification-output-stream
              (lambda (chunk) (push chunk chunks))))
           (text "bootstrap-live-chunk"))
      (let ((cadr-cli::*bash-live-output* stream))
        (is (eq stream
                (cadr-cli::bash-live-output-for-mode :tui nil)))
        (let ((cadr-cli::*bash-live-output*
                (cadr-cli::bash-live-output-for-mode :tui nil)))
          (let ((result
                  (cadr-cli::execute-user-bash-for-tui
                   nil directory
                   (format nil "printf '~A'" text))))
            (is (string= text
                         (cadr-cli::user-bash-result-output result)))
            (is (= 0 (cadr-cli::user-bash-result-exit-code result))))))
      (setf chunks (nreverse chunks))
      (is (string= text (apply #'concatenate 'string chunks)))
      (is (some (lambda (chunk) (> (length chunk) 1)) chunks))
      (is (< (length chunks) (length text)))
      (let ((frontend (make-string-output-stream))
            (sentinel (make-string-output-stream)))
        (let ((cadr-cli::*bash-live-output* sentinel))
          (is (eq frontend
                  (cadr-cli::bash-live-output-for-mode :repl frontend)))
          (is (eq *error-output*
                  (cadr-cli::bash-live-output-for-mode :json frontend))))))))

(defun goal17-render-user-bash-state
    (&key
       (command "printf lines")
       (output "")
       (exit-code 0)
       cancelled-p
       truncated-p
       full-output-path
       expanded-p
       running-p
       (now 0d0)
       (strip-terminal-p t)
       (width 72))
  (let ((lines
          (cadr-cli::render-tui-entry
           (cadr-cli::make-tui-entry
            :type :bash-execution
            :label command
            :text output
            :expanded-p expanded-p
            :custom-options
            (list
             :running-p running-p
             :exit-code exit-code
             :cancelled-p cancelled-p
             :truncated-p truncated-p
             :full-output-path full-output-path))
           width :now now)))
    (if strip-terminal-p
        (mapcar #'cadr-tui:strip-terminal-sequences lines)
        lines)))

(test goal17-direct-user-bash-component-matches-fixed-baseline-final-states
  ;; pi@13cbf77df bash-execution.ts:100-204 owns a framed component distinct
  ;; from notices and agent tool blocks.  Its collapsed budget is 20 logical
  ;; lines, expansion preserves the context-truncated output, and completion
  ;; states have component-local copy rather than generic Error/status text.
  (let* ((output
           (format nil "~{line-~2,'0D~^~%~}"
                   (loop for index from 1 to 25 collect index)))
         (collapsed
           (goal17-render-user-bash-state
            :output output
            :truncated-p t
            :full-output-path "/tmp/fixed.log"))
         (expanded
           (goal17-render-user-bash-state
            :output output
            :truncated-p t
            :full-output-path "/tmp/fixed.log"
            :expanded-p t))
         (styled-collapsed
           (goal17-render-user-bash-state
            :output output
            :truncated-p t
            :full-output-path "/tmp/fixed.log"
            :strip-terminal-p nil))
         (styled-expanded
           (goal17-render-user-bash-state
            :output output
            :truncated-p t
            :full-output-path "/tmp/fixed.log"
            :expanded-p t
            :strip-terminal-p nil)))
    (is (string= "" (first collapsed)))
    (is (= 72 (length (second collapsed))))
    (is (every (lambda (character) (char= character #\─))
               (second collapsed)))
    (is (string= " $ printf lines"
                 (string-right-trim " " (third collapsed))))
    (is (search "line-06" (fourth collapsed)))
    (is (null (find "line-05" collapsed :test #'search)))
    (is (find "line-06" collapsed :test #'search))
    (is (find "line-25" collapsed :test #'search))
    (is
     (find
      "... 5 more lines (ctrl+o to expand)"
      collapsed :test #'search))
    (let ((hint-line
            (find "... 5 more lines" styled-collapsed :test #'search)))
      (is
       (search
        (cadr-tui:theme-foreground
         :muted "... 5 more lines (" :enabled-p t)
        hint-line))
      (is
       (search
        (cadr-cli:key-hint "app.tools.expand" "to expand")
        hint-line)))
    (is
     (find
      "Output truncated. Full output: /tmp/fixed.log"
      collapsed :test #'search))
    (is (find "line-01" expanded :test #'search))
    (is
     (find "(ctrl+o to collapse)" expanded :test #'search))
    (let ((hint-line
            (find "to collapse" styled-expanded :test #'search)))
      (is
       (search
        (cadr-cli:key-hint "app.tools.expand" "to collapse")
        hint-line)))
    (is (null (find "more lines" expanded :test #'search))))
  (let ((nonzero
          (goal17-render-user-bash-state
           :command "exit 7"
           :output (format nil "before exit~%")
           :exit-code 7))
        (cancelled
          (goal17-render-user-bash-state
           :command "sleep 5" :cancelled-p t :exit-code nil)))
    (is (find "before exit" nonzero :test #'search))
    (is (find "(exit 7)" nonzero :test #'search))
    (is (null (find "Process exited with code" nonzero :test #'search)))
    (is (find "$ sleep 5" cancelled :test #'search))
    (is (find "(cancelled)" cancelled :test #'search))
    (is (null (find "Error:" cancelled :test #'search)))
    (is (null (find "Command aborted" cancelled :test #'search)))
    ;; pi@13cbf77df bash-execution.ts:112-173 preserves the trailing empty
    ;; stdout line, then the status Text contributes its own leading newline.
    ;; The result is exactly two blank rows between output and `(exit 7)`.
    (let ((output-position
            (position-if
             (lambda (line) (search "before exit" line))
             nonzero))
          (status-position
            (position-if
             (lambda (line) (search "(exit 7)" line))
             nonzero)))
      (is (= 3 (- status-position output-position))))))

(test goal17-direct-user-bash-running-spacer-matches-fixed-baseline
  ;; pi@13cbf77df bash-execution.ts:140-147 adds Loader after the command;
  ;; Loader renders a zero-cell spacer row followed by the spinner row.
  (let ((running
          (goal17-render-user-bash-state
           :command "sleep 5" :running-p t :now 0d0)))
    (is (string= "" (fourth running)))
    (is (search "Running... (escape/ctrl+c to cancel)"
                (fifth running)))))

(test goal17-direct-user-bash-enters-agent-session-and-context
  ;; pi@13cbf77df agent-session.ts:2803-2824 records every direct bash result
  ;; before the footer asks getContextUsage().  This is observable even before
  ;; the next provider turn: a 50 KiB tail must move the 128k footer to 10.0%.
  (with-test-directory (root)
    (let* ((sessions (merge-pathnames "sessions/" root))
           (cwd (merge-pathnames "cwd/" root))
           (session nil)
           (agent nil)
           (result
             (cadr-cli::make-user-bash-result
              :command "produce"
              :output (make-string (* 50 1024) :initial-element #\x)
              :exit-code 0
              :truncated-p t
              :full-output-path "/tmp/fixed.log")))
      (ensure-directories-exist sessions)
      (ensure-directories-exist cwd)
      (setf
       session
       (cadr-agent:create-session
        :directory sessions :cwd cwd :id "goal17-user-bash")
       agent
       (cadr-agent:make-agent :session session))
      (cadr-cli::record-user-bash-result agent result)
      (let* ((message (first (cadr-agent:agent-messages agent)))
             (entry (first (cadr-agent:session-entries session)))
             (encoded (cadr-agent::message-to-json message))
             (decoded (cadr-agent::message-from-json encoded))
             (estimate
               (cadr-ai:estimate-context-tokens
                (cadr-agent:convert-agent-messages-to-llm
                 (cadr-agent:agent-messages agent))))
             (percent
               (* 100d0
                  (/ (cadr-ai:context-usage-estimate-tokens estimate)
                     128000))))
        (is (typep message 'cadr-agent:bash-execution-message))
        (is (eq message (cadr-agent:session-entry-message entry)))
        (is (string= "bashExecution"
                     (cadr-ai::json-get encoded "role")))
        (is (typep decoded 'cadr-agent:bash-execution-message))
        (is (string= "produce"
                     (cadr-agent:bash-execution-message-command decoded)))
        (is (< 9.9d0 percent 10.1d0))))))

(test goal17-direct-user-bash-result-contract-preserves-render-metadata
  (let ((result
          (cadr-cli::make-user-bash-result
           :command "produce"
           :output "tail"
           :exit-code 0
           :truncated-p t
           :full-output-path "/tmp/fixed.log"
           :exclude-from-context-p t)))
    (is (string= "produce"
                 (cadr-cli::user-bash-result-command result)))
    (is (string= "tail"
                 (cadr-cli::user-bash-result-output result)))
    (is (= 0 (cadr-cli::user-bash-result-exit-code result)))
    (is (cadr-cli::user-bash-result-truncated-p result))
    (is (string= "/tmp/fixed.log"
                 (cadr-cli::user-bash-result-full-output-path result)))
    (is (cadr-cli::user-bash-result-exclude-from-context-p result))))

(test goal17-persisted-direct-bash-is-seeded-back-into-the-transcript
  ;; pi@13cbf77df interactive-mode.ts:3308-3322 reconstructs the dedicated
  ;; BashExecutionComponent when a persisted session is displayed again.
  (let* ((state (cadr-cli::make-tui-state :messages nil))
         (message
           (cadr-agent:make-bash-execution-message
            :command "printf restored"
            :output "restored-output"
            :exit-code 7
            :timestamp 1700000000000)))
    (cadr-cli::seed-tui-message state message)
    (let ((entry (first (cadr-cli::tui-state-entries state))))
      (is (not (null entry)))
      (is (eq :bash-execution (cadr-cli::tui-entry-type entry)))
      (is (string= "printf restored"
                   (cadr-cli::tui-entry-label entry)))
      (is (string= "restored-output"
                   (cadr-cli::tui-entry-text entry)))
      (is (= 7 (getf (cadr-cli::tui-entry-custom-options entry)
                     :exit-code))))))

(test goal17-cancelled-truncated-direct-bash-preserves-full-output-metadata
  ;; pi@13cbf77df bash-executor.ts:112-137 returns the truncation fields even
  ;; when cancellation interrupts execution after the output limit is crossed.
  (with-test-directory (root)
    (let* ((ready (merge-pathnames "bash-output-ready" root))
           (command
             (format nil
                     "head -c 60000 /dev/zero | tr '\\0' x; touch ~S; sleep 30"
                     (namestring ready)))
           (result
             (cadr-cli::execute-user-bash-for-tui
              nil root command
              :abort-p (lambda () (not (null (probe-file ready)))))))
      (unwind-protect
           (progn
             (is (cadr-cli::user-bash-result-cancelled-p result))
             (is (cadr-cli::user-bash-result-truncated-p result))
             (is (stringp
                  (cadr-cli::user-bash-result-full-output-path result)))
             (is (probe-file
                  (cadr-cli::user-bash-result-full-output-path result)))
             (is (plusp
                  (length (cadr-cli::user-bash-result-output result)))))
        (let ((path
                (cadr-cli::user-bash-result-full-output-path result)))
          (when (and path (probe-file path))
            (delete-file path)))))))

(test goal17-session-tree-classifies-persisted-direct-bash
  ;; pi@13cbf77df tree-selector.ts:568-578 indexes bashExecution by role and
  ;; command, and its display branch renders the bash-specific label.
  (with-test-directory (root)
    (let* ((session
             (cadr-agent:create-session
              :directory root :cwd root :id "goal17-tree-bash"))
           (agent (cadr-agent:make-agent :session session)))
      (cadr-cli::record-user-bash-result
       agent
       (cadr-cli::make-user-bash-result
        :command "printf tree-visible"
        :output "tree-output"
        :exit-code 0))
      (multiple-value-bind (entries leaf-id)
          (cadr-cli::session-tree-selector-data session)
        (declare (ignore leaf-id))
        (let ((entry (first entries)))
          (is (eq :bash-execution (getf entry :role)))
          (is (search "printf tree-visible" (getf entry :text)))
          (is (search
               "[bash]: printf tree-visible"
               (cadr-tui:strip-terminal-sequences
                (cadr-cli::tree-selector-entry-display-text entry nil)))))))))

(test goal17-agent-bash-header-and-expand-hint-match-fixed-baseline-spans
  ;; pi@13cbf77df tool-execution renders "$ <command>" as one bold
  ;; toolTitle span.  The collapsed preview styles the configurable expand
  ;; key separately from the surrounding muted copy.
  (let ((caps
          (cadr-tui:make-terminal-capabilities
           :images nil :true-color-p t :hyperlinks-p nil)))
    (cadr-tui:set-current-theme :dark :capabilities caps)
    (unwind-protect
         (let* ((block
                  (cadr-tui:make-tool-block
                   :name "bash" :summary "printf ok"
                   :output
                   (format nil "~{line-~D~^~%~}"
                           (loop for index from 1 to 7 collect index))
                   :status :complete :collapsed-p t))
                (lines
                  (cadr-tui:render-tool-block
                   block 72 :ansi-theme-p t))
                (header
                  (find-if
                   (lambda (line)
                     (search
                      "$ printf ok"
                      (cadr-tui:strip-terminal-sequences line)))
                   lines))
                (preview
                  (find-if
                   (lambda (line)
                     (search
                      "earlier lines"
                      (cadr-tui:strip-terminal-sequences line)))
                   lines)))
           (is (not (null header)))
           (is
            (search
             (cadr-tui:theme-foreground
              :tool-title
              (cadr-tui:theme-bold
               "$ printf ok" :enabled-p t)
              :enabled-p t)
             header))
           (is (not (null preview)))
           (is
            (search
             (cadr-tui:theme-foreground
              :dim "ctrl+o" :enabled-p t)
             preview)))
      (cadr-tui:reset-current-theme))))

(test goal17-agent-tool-supplemental-warning-wraps-as-text-component
  ;; Fixed baseline supplemental status is a Text component: long warnings
  ;; wrap inside the tool shell and retain every byte instead of relying on
  ;; terminal autowrap to clip the tail.
  (let* ((warning
           "[Full output: /tmp/fixed.log. Truncated: 253 lines shown (50.0KB limit)]")
         (block
           (cadr-tui:make-tool-block
            :name "bash" :summary "produce"
            :output "tail" :status :complete :collapsed-p t
            :supplemental-lines (list warning)))
         (lines
           (cadr-tui:render-tool-block block 40))
         (plain
           (mapcar #'cadr-tui:strip-terminal-sequences lines))
         (joined (format nil "~{~A~^~%~}" plain)))
    (is (every
         (lambda (line)
           (or (string= line "")
               (= 40 (cadr-tui:visible-width line))))
         lines))
    (is (search "Full output: /tmp/fixed.log" joined))
    (is (search "Truncated: 253 lines shown" joined))
    (is (search "limit)]" joined))))

(test goal17-bash-output-path-matches-fixed-baseline-random-id-shape
  ;; Fixed bash-executor.ts uses randomBytes(8).toString("hex").  Besides
  ;; collision resistance, the bounded 16-character id keeps the one-line
  ;; truncation warning geometry stable at the fixed wide viewport.
  (let ((first (file-namestring (cadr-cli::bash-output-path)))
        (second (file-namestring (cadr-cli::bash-output-path))))
    (is (cl-ppcre:scan "^cadr-bash-[0-9a-f]{16}\\.log$" first))
    (is (cl-ppcre:scan "^cadr-bash-[0-9a-f]{16}\\.log$" second))
    (is (not (string= first second)))))

(test goal17-edit-preview-preserves-unchanged-line-on-pure-insertion
  ;; pi@13cbf77df edit-diff.ts:478-490 emits a leading ellipsis whenever the
  ;; unchanged prefix exceeds four context lines.  It also preserves the
  ;; unchanged line that a pure insertion follows instead of synthesizing a
  ;; red/green remove-add pair for identical text.
  (with-test-directory (directory)
    (write-text
     (merge-pathnames "diff.txt" directory)
     (format nil "head~%new-a~%new-b~%new-c~%tail~%"))
    (multiple-value-bind (diff status)
        (cadr-cli::preview-edit-call
         directory
         (args
          "path" "diff.txt"
          "edits"
          (vector
           (args "oldText" "tail"
                 "newText" (format nil "tail~%inserted")))))
      (is (eq :complete status))
      (is
       (string=
        (format nil
                "   ...~% 2 new-a~% 3 new-b~% 4 new-c~% 5 tail~%+6 inserted")
        diff)))))

(test goal17-session-display-and-tree-projections-match-fixed-baseline
  ;; pi@13cbf77df session-manager.ts:383-407 and
  ;; interactive-mode.ts:3471-3528 keep display messages typed, report every
  ;; historical compaction, and never expose the provider-facing <summary>
  ;; wrapper in the transcript.
  (with-test-directory (root)
    (let* ((session
             (cadr-agent:create-session
              :directory root :cwd root :id "goal17-tree-display"))
           (root-id
             (cadr-agent:session-append-message
              session
              (cadr-ai:make-user-message :content "root")))
           (assistant-id
             (cadr-agent:session-append-message
              session
              (cadr-ai:make-assistant-message
               :content (list (cadr-ai:make-text-content :text "answer"))
               :api :faux :provider :faux :model "faux-1"
               :usage (cadr-ai:make-usage) :stop-reason :stop))))
      (cadr-agent:session-append-compaction
       session "seed compaction summary" (list root-id)
       root-id 42000)
      (cadr-agent:session-branch session root-id)
      (cadr-agent::session-append-branch-summary
       session assistant-id "seed branch summary")
      (cadr-agent::session-set-label
       session root-id "seed label")
      (let* ((messages
               (cadr-cli::session-display-messages session))
             (provider-text
               (format nil "~{~A~^ ~}"
                       (mapcar #'princ-to-string messages))))
        (is (= 2 (length messages)))
        (is (typep (first messages) 'cadr-ai:user-message))
        (is (typep (second messages)
                   'cadr-agent:branch-summary-message))
        (is
         (string=
          "seed branch summary"
          (cadr-agent::branch-summary-message-summary
           (second messages))))
        (is (null (search "<summary>" provider-text)))
        (is
         (string=
          "Session compacted 1 time"
          (cadr-cli::session-compaction-status session))))
      (multiple-value-bind (tree-entries _leaf-id)
          (cadr-cli::session-tree-selector-data session)
        (declare (ignore _leaf-id))
        (let ((label-entry
                (find :label tree-entries
                      :key (lambda (entry) (getf entry :type)))))
          (is (string= "seed label"
                       (getf label-entry :entry-label)))
          (is (null (getf label-entry :label))))))))

(test goal17-agent-context-estimation-uses-message-order-for-compaction
  ;; pi@13cbf77df coding-agent/core/compaction/compaction.ts:190-222 has a
  ;; deliberately different contract from packages/ai: coding-agent context
  ;; usage follows session message order even when imported timestamps differ.
  (let ((messages
          (list
           (cadr-ai:make-user-message :content "summary" :timestamp 200)
           (cadr-ai:make-assistant-message
            :content (list (cadr-ai:make-text-content :text "kept"))
            :usage (cadr-ai:make-usage :input 9500)
            :stop-reason :stop :timestamp 100)
           (cadr-ai:make-user-message
            :content (make-string 4000 :initial-element #\x)
            :timestamp 300))))
    (is (= 10500
           (cadr-agent::context-estimated-tokens messages)))))

(test goal17-compaction-end-rebuilds-only-the-active-context-once
  ;; pi@13cbf77df interactive-mode.ts:3155-3177,3599-3602 rebuilds the
  ;; transcript from SessionManager.buildContextEntries after compaction.
  ;; Pre-boundary messages must not reappear and the typed summary is seeded
  ;; exactly once by the normal transcript projection.
  (with-test-directory (root)
    (let* ((session
             (cadr-agent:create-session
              :directory root :cwd root :id "goal17-compaction-display"))
           (old-user-id
             (cadr-agent:session-append-message
              session
              (cadr-ai:make-user-message :content "old-user")))
           (old-assistant-id
             (cadr-agent:session-append-message
              session
              (cadr-ai:make-assistant-message
               :content
               (list (cadr-ai:make-text-content :text "old-assistant"))
               :api :faux :provider :faux :model "faux-1"
               :usage (cadr-ai:make-usage) :stop-reason :stop)))
           (kept-id
             (cadr-agent:session-append-message
              session
              (cadr-ai:make-user-message :content "kept-user")))
           (state (cadr-cli::make-tui-state)))
      (cadr-agent:session-append-compaction
       session "compact-once" (list old-user-id old-assistant-id)
       kept-id 42000)
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-assistant-message
        :content (list (cadr-ai:make-text-content :text "post-compact"))
        :api :faux :provider :faux :model "faux-1"
        :usage (cadr-ai:make-usage) :stop-reason :stop))
      (cadr-cli::seed-tui-message
       state (cadr-ai:make-user-message :content "stale-transcript"))
      (multiple-value-bind
            (display-messages summary tokens-before)
          (cadr-cli::session-compaction-display-state session)
        (cadr-cli::tui-handle-agent-event
         state
         (cadr-agent::make-agent-event :type :compaction-end)
         :display-messages display-messages
         :compaction-summary summary
         :compaction-tokens-before tokens-before))
      (let ((entries (cadr-cli::tui-state-entries state)))
        (is (= 3 (length entries)))
        (is
         (equal
          '(:compaction-summary :user :assistant)
          (mapcar #'cadr-cli::tui-entry-type entries)))
        (is (= 1 (count :compaction-summary entries
                        :key #'cadr-cli::tui-entry-type)))
        (is (string= "compact-once"
                     (cadr-cli::tui-entry-text (first entries))))
        (is (= 42000
               (cadr-cli::tui-entry-tokens-before (first entries))))
        (is (string= "kept-user"
                     (cadr-cli::tui-entry-text (second entries))))
        (is (string= "post-compact"
                     (cadr-cli::tui-entry-text (third entries))))
        (is (null (find "old-user" entries
                        :key #'cadr-cli::tui-entry-text :test #'string=)))
        (is (null (find "old-assistant" entries
                        :key #'cadr-cli::tui-entry-text :test #'string=)))
        (is (null (find "stale-transcript" entries
                        :key #'cadr-cli::tui-entry-text :test #'string=)))))))

(test goal17-summary-components-retain-baseline-leading-spacer
  ;; pi@13cbf77df interactive-mode.ts:3398-3412 inserts Spacer(1) before
  ;; branch and compaction components.  The summary component's own box
  ;; padding is separate and cannot substitute for this transcript gap.
  (let* ((state (cadr-cli::make-tui-state))
         (_
           (progn
             (cadr-cli::seed-tui-message
              state
              (cadr-ai:make-user-message :content "root"))
             (cadr-cli::seed-tui-message
              state
              (cadr-agent:make-branch-summary-message
               :summary "branch"))))
         (lines
           (mapcar
            #'cadr-tui:strip-terminal-sequences
            (cadr-cli::render-tui-entries
             (cadr-cli::tui-state-entries state) 72)))
         (user-position
           (position-if
            (lambda (line) (search "root" line)) lines))
         (branch-position
           (position-if
            (lambda (line) (search "[branch]" line)) lines)))
    (declare (ignore _))
    (is (= 4 (- branch-position user-position)))))

(test goal17-tree-filter-and-error-copy-match-fixed-baseline
  ;; pi@13cbf77df tree-selector.ts:343-359,768-851 hides every non-current
  ;; assistant entry that has neither text nor an error/abort stop reason.
  ;; Error and aborted entries remain distinct and compactions show token count.
  (let* ((entries
           (list
            '(:id "stop" :type :message :role :assistant
              :text "" :stop-reason :stop)
            '(:id "tool" :type :message :role :assistant
              :text "" :stop-reason :tool-use :tool-call-only-p t)
            '(:id "error" :type :message :role :assistant
              :text "" :stop-reason :error
              :error-message "seed provider error")
            '(:id "abort" :type :message :role :assistant
              :text "" :stop-reason :aborted)
            '(:id "leaf" :type :message :role :assistant
              :text "" :stop-reason :stop)))
         (visible
           (remove-if-not
            (lambda (entry)
              (cadr-cli::tree-selector-entry-filtered-p
               entry :all "leaf"))
            entries)))
    (is (equal '("error" "abort" "leaf")
               (mapcar (lambda (entry) (getf entry :id)) visible)))
    (is
     (string=
      "assistant: seed provider error"
      (cadr-tui:strip-terminal-sequences
       (cadr-cli::tree-selector-entry-display-text
        (third entries) nil))))
    (is
     (string=
      "assistant: (aborted)"
      (cadr-tui:strip-terminal-sequences
       (cadr-cli::tree-selector-entry-display-text
        (fourth entries) nil))))
    (is
     (string=
      "[compaction: 42k tokens]"
      (cadr-tui:strip-terminal-sequences
       (cadr-cli::tree-selector-entry-display-text
        '(:type :compaction :tokens-before 42000)
        nil))))
    (is
     (string=
      "[label: seed label]"
      (cadr-tui:strip-terminal-sequences
       (cadr-cli::tree-selector-entry-display-text
        '(:type :label :entry-label "seed label")
        nil))))))

(test goal17-bash-collapsed-preview-uses-the-configured-expand-key
  (let* ((block
           (cadr-tui:make-tool-block
            :name "bash" :summary "printf lines"
            :output
            (format nil "~{line-~D~^~%~}"
                    (loop for index from 1 to 8 collect index))
            :status :complete :collapsed-p t
            :expand-key-text "ctrl+x"))
         (text
           (format nil "~{~A~^~%~}"
                   (mapcar
                    #'cadr-tui:strip-terminal-sequences
                    (cadr-tui:render-tool-block block 72)))))
    (is (search "... (3 earlier lines, ctrl+x to expand)" text))
    (is (null (search "earlier lines, to expand" text)))))

(test goal17-compaction-status-distinguishes-reason-and-configured-interrupt-key
  (let ((previous (cadr-tui:get-keybindings)))
    (unwind-protect
         (progn
           (cadr-tui:set-keybindings
            (cadr-tui:make-keybindings-manager
             :user-bindings
             '(("app.interrupt" . ("ctrl+x")))))
           (dolist
               (case
                '((:manual
                   "Compacting context... (ctrl+x to cancel)")
                  (:threshold
                   "Auto-compacting... (ctrl+x to cancel)")
                  (:overflow
                   "Context overflow detected, Auto-compacting... (ctrl+x to cancel)")))
             (destructuring-bind (reason expected) case
               (let ((state (cadr-cli::make-tui-state)))
                 (cadr-cli::tui-handle-agent-event
                  state
                  (cadr-agent::make-agent-event
                   :type :compaction-start
                   :reason reason))
                 (is
                  (string=
                   expected
                   (cadr-cli::tui-state-status-message state)))))))
      (cadr-tui:set-keybindings previous))))

(test goal17-overflow-status-uses-baseline-loader-wrapping-at-narrow-width
  ;; pi@13cbf77df status-indicator.ts:78-88 passes one message to Loader;
  ;; Loader inherits Text paddingX=1, so Text.render wraps at width - 2
  ;; instead of truncating the message to the first physical line.
  (is
   (equal
    (list
     ""
     (goal9-b3-full-width-line
      " ⠋ Context overflow detected," 48)
     (goal9-b3-full-width-line
      " Auto-compacting... (escape to cancel)" 48))
    (mapcar
     #'cadr-tui:strip-terminal-sequences
     (cadr-cli::render-tui-status-indicator
      "Context overflow detected, Auto-compacting... (escape to cancel)"
      48 :spinner-frame "⠋")))))

(test goal17-summarization-retry-status-restores-the-originating-indicator
  (let ((state (cadr-cli::make-tui-state)))
    (cadr-cli::tui-handle-agent-event
     state
     (cadr-agent::make-agent-event
      :type :summarization-retry-scheduled
      :attempt 1 :max-attempts 3 :delay-ms 2000
      :error-message "terminated"))
    (is
     (string=
      "Retrying (1/3) in 2s..."
      (cadr-cli::tui-state-status-message state)))
    (cadr-cli::tui-handle-agent-event
     state
     (cadr-agent::make-agent-event
      :type :summarization-retry-attempt-start
      :source :compaction
      :reason :overflow))
    (is
     (string=
      "Context overflow detected, Auto-compacting... (escape to cancel)"
      (cadr-cli::tui-state-status-message state)))))

(test goal17-threshold-compaction-failure-copy-is-not-reprefixed
  (let ((state (cadr-cli::make-tui-state)))
    (cadr-cli::tui-handle-agent-event
     state
     (cadr-agent::make-agent-event
      :type :compaction-end
      :reason :threshold
      :error-message
      "Auto-compaction failed: Summarization failed: invalid request"))
    (is
     (string=
      "Auto-compaction failed: Summarization failed: invalid request"
      (cadr-cli::tui-entry-text
       (car (last (cadr-cli::tui-state-entries state))))))))

(test goal17-custom-interrupt-raw-input-cancels-active-summary-and-preserves-session
  (with-test-directory (root)
    (let* ((session-directory (merge-pathnames "sessions/" root))
           (cwd (merge-pathnames "cwd/" root))
           (summary-started (sb-thread:make-semaphore :count 0))
           (release-summary (sb-thread:make-semaphore :count 0))
           (worker-done (sb-thread:make-semaphore :count 0))
           (events nil)
           (observed-abort-p nil)
           (release-observed-p nil)
           (prompt-line nil)
           (abort-count 0)
           (session nil)
           (agent nil)
           (before-entry-ids nil)
           (before-messages nil)
           (previous-keybindings (cadr-tui:get-keybindings)))
      (ensure-directories-exist session-directory)
      (ensure-directories-exist cwd)
      (setf session
            (cadr-agent:create-session
             :directory session-directory :cwd cwd
             :id "goal17-tui-summary-interrupt"))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-user-message
        :content (format nil "old context ~120@{x~}")))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-assistant-message
        :api :faux :provider :faux :model "faux-1"
        :content (list (cadr-ai:make-text-content :text "old answer"))
        :usage (cadr-ai:make-usage) :stop-reason :stop))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-user-message
        :content "current context remains after cancellation"))
      (setf
       before-entry-ids
       (mapcar #'cadr-agent:session-entry-id
               (cadr-agent:session-entries session))
       before-messages
       (copy-list (cadr-agent:session-messages session))
       agent
       (cadr-agent:make-agent
        :provider :faux
        :model
        (cadr-ai:make-model
         :id "faux-1" :name "Faux Model"
         :provider :faux :api :faux
         :base-url "http://localhost:0"
         :context-window 128000 :max-tokens 16384)
        :session session
        :compaction-keep-recent-tokens 4
        :stream-function
        (lambda (provider model context on-event
                 &key max-tokens abort-p cache-retention session-id)
          (declare
           (ignore provider model context on-event max-tokens
                   cache-retention session-id))
          (sb-thread:signal-semaphore summary-started)
          (setf
           release-observed-p
           (sb-thread:wait-on-semaphore
            release-summary :timeout 5d0)
           observed-abort-p
           (funcall abort-p))
          (cadr-ai:make-assistant-message
           :api :faux :provider :faux :model "faux-1"
           :content nil :usage (cadr-ai:make-usage)
           :stop-reason :aborted))
        :on-event (lambda (event) (push event events))))
      (unwind-protect
           (progn
             (cadr-tui:set-keybindings
              (cadr-tui:make-keybindings-manager
               :user-bindings
               '(("app.interrupt" . ("ctrl+q")))))
             (is-true
              (cadr-tui:keybinding-matches-p
               (cadr-tui:get-keybindings)
               (string (code-char 17))
               "app.interrupt"))
             (let ((terminal
                     (make-instance
                      'goal17-scripted-terminal
                      :columns 80 :rows 16
                      :inputs
                      (list
                       (format nil "summarize~C" #\Return)
                       (lambda ()
                         (is-true
                          (sb-thread:wait-on-semaphore
                           summary-started :timeout 2d0))
                         (string (code-char 17)))
                       (lambda ()
                         (is-true
                          (sb-thread:wait-on-semaphore
                           worker-done :timeout 2d0))
                         (format nil "/quit~C" #\Return))))))
               (cadr-cli::run-tui
                (lambda (line)
                  ;; FiveAM assertions are deliberately kept on the test
                  ;; thread: its result accumulator is dynamically bound and
                  ;; is not a cross-thread synchronization primitive.
                  (setf prompt-line line)
                  (unwind-protect
                       (cadr-agent:compact-agent
                        agent :force-p t :reason :manual)
                    (sb-thread:signal-semaphore worker-done)))
                :abort-function
                (lambda ()
                  (incf abort-count)
                  (cadr-agent:agent-abort agent)
                  (sb-thread:signal-semaphore release-summary))
                :model "faux-1"
                :session session
                :messages before-messages
                :terminal terminal)))
             (is (string= "summarize" prompt-line))
             (is-true release-observed-p)
             (is (= 1 abort-count))
             (is-true observed-abort-p)
             (is (equal
                  before-entry-ids
                  (mapcar #'cadr-agent:session-entry-id
                          (cadr-agent:session-entries session))))
             (is (equal before-messages
                        (cadr-agent:session-messages session)))
             (is (zerop
                  (count :compaction
                         (cadr-agent:session-entries session)
                         :key #'cadr-agent:session-entry-type)))
             (let ((ended
                     (find :compaction-end events
                           :key #'cadr-agent:agent-event-type)))
               (is (not (null ended)))
               (is-true (cadr-agent:agent-event-aborted ended))
               (is-false (cadr-agent:agent-event-result ended))))
        (cadr-tui:set-keybindings previous-keybindings)
        (when (and agent
                   (not (cadr-agent::agent-shutdown-p agent)))
          (cadr-agent:agent-shutdown agent)))))

(test goal17-package-command-help-preserves-baseline-contract
  ;; Fixed pi@13cbf77df package-manager-cli.ts:66-155 owns the complete
  ;; foreground help contract.  Cadr changes product identity only; the
  ;; examples match the baseline verbatim (npm:@foo/bar included — the
  ;; npm install capability gap is reported separately).
  (flet ((help (command)
           (with-output-to-string (stream)
             (cadr-cli::print-package-command-help command stream))))
    (let ((install (help :install))
          (remove (help :remove))
          (update (help :update))
          (list (help :list))
          (config (help :config)))
      (dolist (fragment
               '("Install a package and add it to settings."
                 "-l, --local       Install project-locally (.cadr/settings.json)"
                 "-a, --approve     Trust project-local files for this command"
                 "-na, --no-approve Ignore project-local files for this command"
                 "cadr install npm:@foo/bar"
                 "cadr install git:github.com/user/repo"
                 "cadr install ./local/path"))
        (is (search fragment install)))
      (dolist (fragment
               '("Remove a package and its source from settings."
                 "Alias: cadr uninstall <source> [-l]"
                 "cadr remove npm:@foo/bar"
                 "cadr uninstall npm:@foo/bar"))
        (is (search fragment remove)))
      (dolist (fragment
               '("cadr update [source|self|cadr]"
                 "Update cadr, installed packages, or model catalogs."
                 "--extensions            Update installed packages only"
                 "--models                Refresh model catalogs only"
                 "--extension <source>    Update one package only"
                 "--force                 Reinstall cadr even if the current version is latest"
                 "cadr update cadr           Update cadr only (self works as alias to cadr)"))
        (is (search fragment update)))
      (dolist (fragment
               '("List installed packages from user and project settings."
                 "-a, --approve      Trust project-local files for this command"
                 "-na, --no-approve  Ignore project-local files for this command"))
        (is (search fragment list)))
      (dolist (fragment
               '("Open the resource configuration TUI to enable or disable package resources."
                 "Without -l, starts in global settings (~/.cadr/agent/settings.json)."
                 "Press Tab in the TUI to switch between global and project-local modes."
                 "-l, --local       Edit project overrides (.cadr/settings.json)"))
        (is (search fragment config))))))

(test goal17-update-cadr-and-self-select-the-product-update-target
  ;; The fixed baseline reserves both `self` and the product slug as aliases
  ;; for the self-update target.  Product identity changes pi -> cadr only.
  (dolist (source '("self" "cadr"))
    (let ((options
            (cadr-cli::parse-package-command
             (list "update" source))))
      (is (equal '(:self)
                 (cadr-cli::package-command-options-update-target options)))
      ;; Baseline keeps the alias in options.source; only the resolved
      ;; update-target distinguishes it (package-manager-cli.ts:357-360).
      (is (string= source
                   (cadr-cli::package-command-options-source options))))))
