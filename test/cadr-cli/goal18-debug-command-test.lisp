(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

;;; Goal 18 Part D: /debug and shift+ctrl+d dump the full rendered document
;;; plus session messages to the agent debug log, and confirm with the
;;; baseline accent check line + muted path block.

(test goal18-debug-command-writes-the-debug-log-and-confirms
  (let* ((terminal-cell (list nil))
         (confirmed nil)
         (terminal
           (make-instance
            'goal17-scripted-terminal
            :columns 80 :rows 16
            :inputs
            (list
             (format nil "/debug~C" #\Return)
             (lambda ()
               (and (goal18-screen-has-p
                     (first terminal-cell) "Debug log written")
                    (prog1 (format nil "/quit~C" #\Return)
                      (setf confirmed t))))))))
    (setf (first terminal-cell) terminal)
    (let ((debug-path (cadr-core:agent-debug-log-path)))
      (ignore-errors (delete-file debug-path))
      (cadr-cli::run-tui
       (lambda (line) (declare (ignore line)))
       :debug-messages-function
       (lambda () "{\"role\":\"user\",\"content\":\"seed\"}")
       :model "faux"
       :terminal terminal)
      (is-true confirmed "the confirmation block never rendered")
      (is (probe-file debug-path) "the debug log was not written")
      (let ((content (uiop:read-file-string debug-path)))
        (is (search "Debug output at " content))
        (is (search "Terminal: 80x16" content))
        (is (search "Total lines: " content))
        (is (search "=== All rendered lines with visible widths ===" content))
        (is (search "[0] (w=" content))
        (is (search "=== Agent messages (JSONL) ===" content))
        (is (search "{\"role\":\"user\",\"content\":\"seed\"}" content)
            "the session messages must appear as JSONL")
        (is (not (search "oauth-access-secret" content))
            "the dump must not contain credential material")))))

(test goal18-shift-ctrl-d-triggers-the-debug-dump
  (let* ((terminal-cell (list nil))
         (confirmed nil)
         (terminal
           (make-instance
            'goal17-scripted-terminal
            :columns 80 :rows 16
            :inputs
            (list
             ;; Kitty CSI-u: d (100) with shift+ctrl (modifier 6).
             (format nil "~C[100;6u" #\Escape)
             (lambda ()
               (and (goal18-screen-has-p
                     (first terminal-cell) "Debug log written")
                    (prog1 (format nil "/quit~C" #\Return)
                      (setf confirmed t))))))))
    (setf (first terminal-cell) terminal)
    (let ((debug-path (cadr-core:agent-debug-log-path)))
      (ignore-errors (delete-file debug-path))
      (cadr-cli::run-tui
       (lambda (line) (declare (ignore line)))
       :model "faux"
       :terminal terminal)
      (is-true confirmed "shift+ctrl+d did not produce the confirmation")
      (is (probe-file debug-path)
          "shift+ctrl+d must write the debug log"))))

(test goal18-user-bound-session-action-dispatches
  ;; Goal 18 I7: a settings.json binding for a session action must drive
  ;; the same handler as its slash command (baseline
  ;; interactive-mode.ts:2646-2649 editor actions).
  (let* ((terminal-cell (list nil))
         (opened nil)
         (dismissed nil)
         (previous (cadr-tui:get-keybindings))
         (terminal
           (make-instance
            'goal17-scripted-terminal
            :columns 80 :rows 16
            :inputs
            (list
             ;; Kitty CSI-u: t (116) with ctrl+alt (modifier 7), bound to
             ;; app.session.tree below.
             (format nil "~C[116;7u" #\Escape)
             (lambda ()
               (and (goal18-screen-has-p
                     (first terminal-cell) "Session Tree")
                     (not dismissed)
                     (prog1 (format nil "~C" #\Escape)
                       (setf opened t dismissed t))))
             (lambda ()
               (and dismissed
                    (not (goal18-screen-has-p
                          (first terminal-cell) "Session Tree"))
                    (format nil "/quit~C" #\Return)))))))
    (setf (first terminal-cell) terminal)
    (cadr-tui:set-keybindings
     (cadr-tui:make-keybindings-manager
      :user-bindings '(("app.session.tree" . ("ctrl+alt+t")))))
    (unwind-protect
         (cadr-cli::run-tui
          (lambda (line) (declare (ignore line)))
          :model "faux"
          :terminal terminal)
      (cadr-tui:set-keybindings previous))
    (is-true opened
             "the bound app.session.tree key did not open the tree selector")))
