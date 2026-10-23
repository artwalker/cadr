(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

;;; Locked to v1.4.0 thinking-selector.ts and select-list.ts renderItem.
;;; thinking-selector.test.ts keeps the check on the current level while
;;; the arrow moves. keyDisplayText capitalizes app.thinking.cycle
;;; ("shift+tab" -> "Shift+Tab"). The description column uses a 2-cell
;;; safety margin, so width 48 cuts the long descriptions.

(defun goal27-thinking-plain-lines (state width)
  (mapcar #'cadr-tui:strip-terminal-sequences
          (cadr-cli::render-thinking-selector state width)))

(defun goal27-thinking-level-line (lines needle)
  (find-if (lambda (line) (search needle line)) lines))

(test goal27-thinking-selector-marks-the-current-level-in-front
  (let* ((state
           (cadr-cli::make-thinking-selector-state
            :levels '(:medium :high)
            :current-level :medium))
         (lines (goal27-thinking-plain-lines state 80))
         (medium (goal27-thinking-level-line lines "medium"))
         (high (goal27-thinking-level-line lines "high")))
    (is (string= "→ ✓ medium    Moderate reasoning (~8k tokens)"
                 medium))
    (is (string= "    high      Deep reasoning (~16k tokens)"
                 high))
    (cadr-cli::thinking-selector-handle-event
     state (cadr-tui:make-input-event :kind :down))
    (let* ((moved (goal27-thinking-plain-lines state 80))
           (medium (goal27-thinking-level-line moved "medium"))
           (high (goal27-thinking-level-line moved "high")))
      (is (string= "  ✓ medium    Moderate reasoning (~8k tokens)"
                   medium))
      (is (string= "→   high      Deep reasoning (~16k tokens)"
                   high)))))

(test goal27-thinking-selector-cycle-hint-uses-key-display-text
  (let* ((state
           (cadr-cli::make-thinking-selector-state
            :levels '(:off)
            :current-level :off
            :default-level :medium))
         (lines (goal27-thinking-plain-lines state 100)))
    (is (find "Shift+Tab cycles thinking levels in-session"
              lines
              :key (lambda (line)
                     (string-right-trim '(#\Space #\Tab) line))
              :test #'string=))
    (is (null (find-if
               (lambda (line)
                 (search "shift+tab" line))
               lines)))
    (is (string= "→ ✓ off       No reasoning"
                 (goal27-thinking-level-line lines "off")))
    (is (null (find "No reasoning" lines :test #'string=)))))

(test goal27-thinking-selector-description-column-matches-v140
  (let* ((state
           (cadr-cli::make-thinking-selector-state
            :levels '(:off :minimal :low :medium :high :xhigh :max)
            :current-level :medium
            :default-level :medium))
         (wide (goal27-thinking-plain-lines state 100))
         (narrow (goal27-thinking-plain-lines state 48)))
    (is (string= "    off       No reasoning"
                 (goal27-thinking-level-line wide "off")))
    (is (string= "→ ✓ medium    Moderate reasoning (~8k tokens) · default"
                 (goal27-thinking-level-line wide "medium")))
    (is (string= "    minimal   Very brief reasoning (~1k tokens"
                 (goal27-thinking-level-line narrow "minimal")))
    (is (string= "→ ✓ medium    Moderate reasoning (~8k tokens) "
                 (goal27-thinking-level-line narrow "medium")))
    (is (string= "    xhigh     Extra-high reasoning (~32k token"
                 (goal27-thinking-level-line narrow "xhigh")))
    (is (string= "    max       Maximum reasoning"
                 (goal27-thinking-level-line narrow "max")))))

(test goal27-thinking-selector-cycle-hint-follows-the-binding
  (let* ((keybindings
           (cadr-cli::make-thinking-selector-keybindings
            '(("app.thinking.cycle" . ("ctrl+y")))))
         (state
           (cadr-cli::make-thinking-selector-state
            :levels '(:off)
            :current-level :off
            :keybindings keybindings))
         (lines (goal27-thinking-plain-lines state 80)))
    (is (find "Ctrl+Y cycles thinking levels in-session"
              lines
              :key (lambda (line)
                     (string-right-trim '(#\Space #\Tab) line))
              :test #'string=))))

(test goal27-thinking-selector-unselected-description-is-muted
  (let* ((state
           (cadr-cli::make-thinking-selector-state
            :levels '(:medium :high)
            :current-level :medium))
         (raw (cadr-cli::render-thinking-selector state 80))
         (high (find-if
                (lambda (line)
                  (search "high" (cadr-tui:strip-terminal-sequences line)))
                raw))
         (medium (find-if
                  (lambda (line)
                    (search "medium"
                            (cadr-tui:strip-terminal-sequences line)))
                  raw))
         (muted (cadr-tui:theme-foreground-ansi :muted :enabled-p t))
         (accent (cadr-tui:theme-foreground-ansi :accent :enabled-p t))
         (plain (cadr-tui:strip-terminal-sequences high)))
    (is (and (>= (length medium) (length accent))
             (string= accent
                      (subseq medium 0 (length accent)))))
    (is (= (length "    high")
           (or (search muted high) -1)))
    (is (string= (subseq plain 0 (length "    high"))
                 "    high"))))
