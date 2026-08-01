(in-package #:cadr-cli/tests)

(in-suite cadr-cli-suite)

(test goal12-coding-agent-keybinding-hints-and-dynamic-border-match-baseline
  (let ((manager
          (cadr-tui:make-keybindings-manager
           :user-bindings
           '(("tui.select.cancel" . ("ctrl+c"))))))
    (cadr-tui:set-keybindings manager)
    (unwind-protect
         (progn
           (is (string= "alt+enter/ctrl+j"
                        (cadr-cli:format-key-text
                         "alt+enter/ctrl+j")))
           (is (string= "Ctrl+C"
                        (cadr-cli:key-display-text
                         "tui.select.cancel")))
           (is (search "ctrl+c cancel"
                       (cadr-tui:strip-terminal-sequences
                        (cadr-cli:key-hint
                         "tui.select.cancel" "cancel"))))
           (is (search "alt+x action"
                       (cadr-tui:strip-terminal-sequences
                        (cadr-cli:raw-key-hint
                         "alt+x" "action")))))
      (cadr-tui:set-keybindings
       (cadr-tui:make-keybindings-manager))))
  (let ((border
          (cadr-cli:make-dynamic-border-component
           :color-function #'string-upcase)))
    (is (equal (list (make-string 5 :initial-element #\─))
               (cadr-tui:component-render border 5)))))

(test goal12-coding-agent-bordered-loader-reuses-composition-and-cancels
  (let* ((ui (cadr-tui:make-tui-root))
         (loader
           (cadr-cli:make-bordered-loader-component
            ui "Working" :cancellable-p t :start-p nil))
         (aborted 0))
    (cadr-cli:bordered-loader-set-on-abort
     loader (lambda () (incf aborted)))
    (let ((plain
            (mapcar #'cadr-tui:strip-terminal-sequences
                    (cadr-tui:component-render loader 30))))
      (is (char= #\─ (char (first plain) 0)))
      (is (find-if (lambda (line) (search "Working" line)) plain))
      (is (find-if (lambda (line) (search "cancel" line)) plain))
      (is (char= #\─ (char (car (last plain)) 0))))
    (cadr-tui:component-handle-event
     loader (cadr-tui:make-input-event :kind :escape))
    (is (cadr-tui:cancellation-token-aborted-p
         (cadr-cli:bordered-loader-signal loader)))
    (is (= 1 aborted))
    (cadr-tui:component-dispose loader)))

(test goal12-coding-agent-countdown-has-explicit-deterministic-ticks
  (let* ((ticks nil)
        (expired 0)
        (timer
          (cadr-cli:make-countdown-timer
           2100 nil
           (lambda (seconds) (push seconds ticks))
           (lambda () (incf expired))
           :start-p nil)))
    (is (equal '(3) ticks))
    (cadr-cli:countdown-timer-tick timer)
    (cadr-cli:countdown-timer-tick timer)
    (cadr-cli:countdown-timer-tick timer)
    (is (equal '(0 1 2 3) ticks))
    (is (= 1 expired))
    (cadr-tui:component-dispose timer)))

(test goal12-coding-agent-armin-and-daxnuts-animation-components-are-driven-without-sleeps
  (let* ((renders 0)
         (ui (cadr-tui:make-tui-root
              :render-function
              (lambda (lines)
                (declare (ignore lines))
                (incf renders))))
         (armin
           (cadr-cli:make-armin-component
            ui :effect :scanline :start-p nil))
         (dax
           (cadr-cli:make-daxnuts-component
            ui :start-p nil)))
    (is (= 19 (length (cadr-tui:component-render armin 40))))
    (is (search "ARMIN SAYS HI"
                (car (last
                      (cadr-tui:component-render armin 40)))))
    (cadr-cli:armin-component-tick armin)
    (is (plusp renders))
    (is (= 24 (length (cadr-tui:component-render dax 50))))
    (cadr-cli:daxnuts-component-tick dax)
    (is (>= renders 2))
    (cadr-tui:component-dispose armin)
    (cadr-tui:component-dispose dax)))

(test goal12-coding-agent-earendil-announcement-and-component-barrel-are-complete
  (let* ((announcement
           (cadr-cli:make-earendil-announcement-component))
         (plain
           (mapcar #'cadr-tui:strip-terminal-sequences
                   (cadr-tui:component-render announcement 60)))
         (joined (format nil "~{~A~^~%~}" plain)))
    (is (search "pi has joined Earendil" joined))
    (is (search "https://mariozechner.at/posts/2026-04-08-ive-sold-out/"
                joined))
    (is (char= #\─ (char (first plain) 0)))
    (is (char= #\─ (char (car (last plain)) 0))))
  (dolist (name '("MAKE-ARMIN-COMPONENT"
                  "MAKE-BORDERED-LOADER-COMPONENT"
                  "MAKE-COUNTDOWN-TIMER"
                  "MAKE-DAXNUTS-COMPONENT"
                  "MAKE-DYNAMIC-BORDER-COMPONENT"
                  "MAKE-EARENDIL-ANNOUNCEMENT-COMPONENT"
                  "FORMAT-KEY-TEXT"
                  "KEY-HINT"))
    (multiple-value-bind (symbol status)
        (find-symbol name :cadr-cli)
      (is (not (null symbol)))
      (is (eq :external status)))))
