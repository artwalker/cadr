(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun goal15-a0-start-tool (state call)
  (cadr-cli::tui-handle-agent-event
   state
   (cadr-agent::make-agent-event
    :type :tool-execution-start
    :tool-call call)
   :clock-function (lambda () 10d0))
  (cadr-cli::tui-entry-tool-block
   (car (last (cadr-cli::tui-state-entries state)))))

(defun goal15-a0-finish-tool (state call text)
  (cadr-cli::tui-handle-agent-event
   state
   (cadr-agent::make-agent-event
    :type :tool-execution-end
    :tool-call call
    :tool-result
    (cadr-ai:make-tool-result-message
     :tool-call-id (cadr-ai:tool-call-id call)
     :tool-name (cadr-ai:tool-call-name call)
     :content (list (cadr-ai:make-text-content :text text))
     :is-error nil))
   :clock-function (lambda () 10.1d0))
  (cadr-cli::tui-entry-tool-block
   (car (last (cadr-cli::tui-state-entries state)))))

(defun goal15-a0-plain-lines (lines)
  (mapcar
   (lambda (line)
     (string-right-trim
      " " (cadr-tui:strip-terminal-sequences line)))
   lines))

(defun goal15-a0-line-containing (needle lines)
  (position-if
   (lambda (line) (search needle line)) lines))

(test goal15-a0-multiline-bash-header-uses-real-renderer-lines
  (let* ((command
           (format nil
                   "python - <<'PY'~%print('alpha')~%~%print('omega')~%PY"))
         (state (cadr-cli::make-tui-state))
         (call
           (cadr-ai:make-tool-call
            :id "multiline-bash" :name "bash"
            :arguments
            (args "command" command "timeout" 10)))
         (block (goal15-a0-start-tool state call))
         (lines
           (goal15-a0-plain-lines
            (cadr-tui:render-tool-block block 80))))
    ;; Baseline Text renders each embedded newline as a real component line.
    (is (every
         (lambda (line)
           (and (null (position #\Newline line))
                (null (position #\Return line))))
         lines))
    (let ((start (goal15-a0-line-containing "$ python - <<'PY'" lines))
          (alpha (goal15-a0-line-containing "print('alpha')" lines))
          (omega (goal15-a0-line-containing "print('omega')" lines))
          (end (goal15-a0-line-containing "PY (timeout 10s)" lines)))
      (is (and start alpha omega end))
      (is (= (1+ start) alpha))
      ;; The empty logical command line must consume exactly one renderer row.
      (is (= (+ alpha 2) omega))
      (is (= (1+ omega) end)))))

(test goal15-a0-long-bash-header-wraps-without-embedded-control-lines
  (let* ((state (cadr-cli::make-tui-state))
         (call
           (cadr-ai:make-tool-call
            :id "long-bash" :name "bash"
            :arguments
            (args "command"
                  "printf abcdefghijklmnopqrstuvwxyz0123456789")))
         (block (goal15-a0-start-tool state call))
         (lines (cadr-tui:render-tool-block block 18)))
    (is (> (length lines) 5))
    (dolist (line lines)
      (is (<= (cadr-tui:visible-width line) 18)))
    (is (every
         (lambda (line)
           (and (null (position #\Newline line))
                (null (position #\Return line))))
         lines))))

(test goal15-a0-multiline-tool-header-preserves-following-output-and-thinking
  (let* ((state (cadr-cli::make-tui-state))
         (call
           (cadr-ai:make-tool-call
            :id "ordered-bash" :name "bash"
            :arguments
            (args "command" (format nil "printf first~%printf second"))))
         (block (goal15-a0-start-tool state call)))
    (setf (cadr-tui:tool-block-collapsed-p block) nil)
    (goal15-a0-finish-tool state call "tool-output-after-header")
    (cadr-cli::append-tui-entry
     state
     (cadr-cli::make-tui-entry
      :type :assistant
      :content-blocks
      (list
       (cons :assistant-thinking "thinking-after-tool")
       (cons :assistant "answer-after-tool"))))
    (let* ((lines
             (goal15-a0-plain-lines
              (cadr-cli::render-tui-entries
               (cadr-cli::tui-state-entries state) 60 :now 10.1d0)))
           (first-command
             (goal15-a0-line-containing "$ printf first" lines))
           (second-command
             (goal15-a0-line-containing "printf second" lines))
           (output
             (goal15-a0-line-containing "tool-output-after-header" lines))
           (thinking
             (goal15-a0-line-containing "thinking-after-tool" lines))
           (answer
             (goal15-a0-line-containing "answer-after-tool" lines)))
      (is (every
           (lambda (line)
             (and (null (position #\Newline line))
                  (null (position #\Return line))))
           lines))
      (is (and first-command second-command output thinking answer))
      (is (< first-command second-command output thinking answer)))))

(test goal15-a0-file-tool-path-newlines-use-the-same-real-line-contract
  ;; Read/edit/write all route path text through the shared tool header block.
  ;; Keep the baseline Text newline contract at that common ownership point.
  (dolist (name '("read" "edit" "write"))
    (let* ((state (cadr-cli::make-tui-state))
           (call
             (cadr-ai:make-tool-call
              :id name :name name
              :arguments
              (args "path" (format nil "first~%second")
                    "content" "body"
                    "edits" #())))
           (block (goal15-a0-start-tool state call))
           (lines
             (goal15-a0-plain-lines
              (cadr-tui:render-tool-block block 60)))
           (first-line
             (goal15-a0-line-containing
              (format nil "~A first" name) lines))
           (second-line
             (goal15-a0-line-containing "second" lines)))
      (is (and first-line second-line))
      (is (= (1+ first-line) second-line))
      (is (every
           (lambda (line)
             (and (null (position #\Newline line))
                  (null (position #\Return line))))
           lines)))))
