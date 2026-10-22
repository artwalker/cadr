(in-package #:cadr-tui/tests)
(in-suite cadr-tui-suite)

(defclass lifecycle-terminal (cadr-tui:terminal)
  ((starts :initform 0 :accessor lifecycle-starts)
   (stops :initform 0 :accessor lifecycle-stops)))

(defmethod cadr-tui:terminal-start ((terminal lifecycle-terminal))
  (incf (lifecycle-starts terminal)))

(defmethod cadr-tui:terminal-stop ((terminal lifecycle-terminal))
  (incf (lifecycle-stops terminal)))

(test terminal-lifecycle-restores-after-condition
  (let ((terminal (make-instance 'lifecycle-terminal)))
    (signals simple-error
      (cadr-tui:call-with-terminal
       terminal
       (lambda ()
         (error "boom"))))
    (is (= 1 (lifecycle-starts terminal)))
    (is (= 1 (lifecycle-stops terminal)))))

(defclass failing-start-terminal (lifecycle-terminal) ())

(defmethod cadr-tui:terminal-start ((terminal failing-start-terminal))
  (incf (lifecycle-starts terminal))
  (error "start failed after partial setup"))

(test terminal-lifecycle-cleans-up-partial-start
  (let ((terminal (make-instance 'failing-start-terminal)))
    (signals simple-error
      (cadr-tui:call-with-terminal
       terminal
       (lambda () nil)))
    (is (= 1 (lifecycle-starts terminal)))
    (is (= 1 (lifecycle-stops terminal)))))

(test escape-timeout-follows-cadr-tui-esc-timeout-and-ssh
  ;; pi@4a080252f packages/tui/test/terminal.test.ts resolveEscapeTimeoutMs.
  ;; SSH_CLIENT does not lengthen the timeout. An empty SSH variable is
  ;; unset for this check (JS truthiness).
  (flet ((timeout (pairs)
           (cadr-tui::resolve-escape-timeout-milliseconds
            :environment pairs)))
    (is (= 80 (timeout '(("CADR_TUI_ESC_TIMEOUT" . "80")))))
    (is (= 80
           (timeout '(("CADR_TUI_ESC_TIMEOUT" . "80")
                      ("SSH_TTY" . "/dev/pts/1")))))
    (is (= 80.5
           (timeout '(("CADR_TUI_ESC_TIMEOUT" . "80.5")))))
    (is (= 100 (timeout '(("CADR_TUI_ESC_TIMEOUT" . "1e2")))))
    (is (= 80 (timeout '(("CADR_TUI_ESC_TIMEOUT" . " 80 ")))))
    (is (= 10 (timeout '(("CADR_TUI_ESC_TIMEOUT" . "abc")))))
    (is (= 10 (timeout '(("CADR_TUI_ESC_TIMEOUT" . "0")))))
    (is (= 10 (timeout '(("CADR_TUI_ESC_TIMEOUT" . "-5")))))
    (is (= 10 (timeout '(("CADR_TUI_ESC_TIMEOUT" . "")))))
    (is (= 10 (timeout '(("CADR_TUI_ESC_TIMEOUT" . "Infinity")))))
    (is (= 100 (timeout '(("SSH_CONNECTION" . "10.0.0.1 22")))))
    (is (= 100 (timeout '(("SSH_TTY" . "/dev/pts/1")))))
    (is (= 100
           (timeout '(("CADR_TUI_ESC_TIMEOUT" . "0")
                      ("SSH_CONNECTION" . "10.0.0.1 22")))))
    (is (= 10 (timeout '(("SSH_CLIENT" . "10.0.0.1 22 24")))))
    (is (= 10 (timeout '(("SSH_CONNECTION" . "")))))
    (is (= 10 (timeout '())))))

(test multiplexer-mouse-tracking-drops-all-motion
  ;; pi@4a080252f tui-alt-screen.test.ts "uses button-motion tracking
  ;; inside terminal multiplexers".
  (let ((button (format nil "~C[?1002h" #\Escape))
        (all (format nil "~C[?1003h" #\Escape))
        (sgr (format nil "~C[?1006h" #\Escape)))
    (flet ((sequence (pairs)
             (cadr-tui::mouse-enable-sequence :environment pairs)))
      (let ((direct
              (sequence '(("TERM" . "xterm-256color")))))
        (is (search all direct))
        (is (search sgr direct)))
      (dolist (pairs '((("TMUX" . "/tmp/tmux/default,1,0"))
                       (("TERM" . "tmux-256color"))
                       (("ZELLIJ" . "0"))
                       (("ZELLIJ" . ""))
                       (("STY" . "123.session"))
                       (("TERM" . "screen-256color"))))
        (let ((writes (sequence pairs)))
          (is (search button writes) pairs)
          (is (not (search all writes)) pairs)
          (is (search sgr writes) pairs))))))
