(in-package #:cadr-tui/tests)
(in-suite cadr-tui-suite)

(test kitty-and-modify-other-keys-parse-to-logical-bindings
  (cadr-tui:set-kitty-protocol-active t)
  (dolist
      (case
       `(("\e[1089::99;5u" "ctrl+c")
         ("\e[1079::112;6u" "shift+ctrl+p")
         ("\e[107;9u" "super+k")
         ("\e[13;9u" "super+enter")
         ("\e[107;13u" "ctrl+super+k")
         ("\e[107;14u" "shift+ctrl+super+k")
         ("\e[49u" "1")
         ("\e[49;5u" "ctrl+1")
         ("\e[57400u" "1")
         ("\e[57417u" "left")
         ("\e[57426u" "delete")
         ("\e[99:67:99;2u" "shift+c")
         ("\e[1089:1057:99;6:2u" "shift+ctrl+c")
         ("\e[107::118;5u" "ctrl+k")
         ("\e[47::91;5u" "ctrl+/")))
    (destructuring-bind (source expected) case
      (let ((data
              (substitute
               #\Escape #\e source
               :start 0 :end 1)))
        (is (string= expected
                     (cadr-tui:parse-key data)))
        (is (cadr-tui:matches-key data expected)))))
  (is (null
       (cadr-tui:parse-key
        (format nil "~C[99;17u" #\Escape))))
  (cadr-tui:set-kitty-protocol-active nil)
  (dolist
      (case
       `((,(format nil "~C[27;5;99~~" #\Escape) "ctrl+c")
         (,(format nil "~C[27;2;13~~" #\Escape) "shift+enter")
         (,(format nil "~C[27;3;9~~" #\Escape) "alt+tab")
         (,(format nil "~C[27;5;127~~" #\Escape)
          "ctrl+backspace")
         (,(format nil "~C[27;1;32~~" #\Escape) "space")
         (,(format nil "~C[27;7;104~~" #\Escape)
          "ctrl+alt+h")
         (,(format nil "~C[104;7u" #\Escape)
          "ctrl+alt+h")))
    (destructuring-bind (data expected) case
      (is (string= expected (cadr-tui:parse-key data)))
      (is (cadr-tui:matches-key data expected)))))

(test modified-csi-arrows-and-alt-enter-match-real-terminal-sequences
  (cadr-tui:set-kitty-protocol-active nil)
  (dolist
      (case
       `((,(format nil "~C[1;3A" #\Escape) "alt+up")
         (,(format nil "~C[1;3B" #\Escape) "alt+down")
         (,(format nil "~C[1;3C" #\Escape) "alt+right")
         (,(format nil "~C[1;3D" #\Escape) "alt+left")
         (,(format nil "~C[1;3:2A" #\Escape) "alt+up")
         (,(format nil "~C[3;3~~" #\Escape) "alt+delete")
         (,(format nil "~C[1;3H" #\Escape) "alt+home")
         (,(format nil "~C[27;3;13~~" #\Escape)
          "alt+enter")
         (,(format nil "~C[13;3u" #\Escape)
          "alt+enter")
         (,(format nil "~C~C" #\Escape #\Return)
          "alt+enter")))
    (destructuring-bind (data expected) case
      (is (string= expected (cadr-tui:parse-key data)))
      (is (cadr-tui:matches-key data expected))))
  (cadr-tui:set-kitty-protocol-active t)
  (is (string=
       "shift+enter"
       (cadr-tui:parse-key
        (format nil "~C~C" #\Escape #\Return))))
  (cadr-tui:set-kitty-protocol-active nil))

(test legacy-key-parsing-covers-controls-navigation-and-functions
  (cadr-tui:set-kitty-protocol-active nil)
  (dolist
      (case
       `((,(string (code-char 3)) "ctrl+c")
         (,(string (code-char 4)) "ctrl+d")
         (,(string #\Escape) "escape")
         (,(string #\Newline) "enter")
         (,(string (code-char 0)) "ctrl+space")
         (,(string (code-char 28)) "ctrl+\\")
         (,(string (code-char 29)) "ctrl+]")
         (,(string (code-char 31)) "ctrl+-")
         (,(format nil "~C~C" #\Escape (code-char 29))
          "ctrl+alt+]")
         (,(format nil "~C[A" #\Escape) "up")
         (,(format nil "~COA" #\Escape) "up")
         (,(format nil "~C[2^" #\Escape) "ctrl+insert")
         (,(format nil "~C[7$" #\Escape) "shift+home")
         (,(format nil "~COP" #\Escape) "f1")
         (,(format nil "~C[24~~" #\Escape) "f12")
         (,(format nil "~C[E" #\Escape) "clear")
         (,(format nil "~Cp" #\Escape) "alt+up")
         (,(format nil "~C[[5~~" #\Escape) "pageUp")))
    (destructuring-bind (data expected) case
      (is (string= expected (cadr-tui:parse-key data)))
      (is (cadr-tui:matches-key data expected))))
  (is (cadr-tui:matches-key
       (string (code-char 8)) "ctrl+h"))
  (is (cadr-tui:matches-key
       (string #\Return) "enter"))
  (is (string= "shift+l" (cadr-tui:parse-key "L")))
  (is (cadr-tui:matches-key "L" "shift+l"))
  (is (not
       (cadr-tui:matches-key
        (string #\Return) "ctrl+-")))
  (is (cadr-tui:matches-key
       (string (code-char 31)) "ctrl+-"))
  (is (cadr-tui:matches-key
       (string (code-char 31)) "ctrl+_"))
  (is (string=
       "alt+y"
       (cadr-tui:parse-key
        (format nil "~Cy" #\Escape))))
  (cadr-tui:set-kitty-protocol-active t)
  (is (null
       (cadr-tui:parse-key
        (format nil "~Cy" #\Escape))))
  (is (string=
       "shift+enter"
       (cadr-tui:parse-key (string #\Newline))))
  (cadr-tui:set-kitty-protocol-active nil))

(test printable-key-decoding-and-event-kinds
  (is (string=
       "1"
       (cadr-tui:decode-kitty-printable
        (format nil "~C[57400u" #\Escape))))
  (is (null
       (cadr-tui:decode-kitty-printable
        (format nil "~C[57417u" #\Escape))))
  (is (string=
       "E"
       (cadr-tui:decode-printable-key
        (format nil "~C[27;2;69~~" #\Escape))))
  (is (null
       (cadr-tui:decode-printable-key
        (format nil "~C[27;6;69~~" #\Escape))))
  (is (cadr-tui:key-release-p
       (format nil "~C[99;5:3u" #\Escape)))
  (is (cadr-tui:key-repeat-p
       (format nil "~C[99;5:2u" #\Escape)))
  (is (not
       (cadr-tui:key-release-p
        (format nil "~C[200~~90:62:3F:A5~C[201~~"
                #\Escape #\Escape)))))

(test shift-tab-vt-sequence-is-not-tab
  ;; pi@4a080252f keys.ts parseKey returns "shift+tab" for ESC [ Z,
  ;; the sequence ENABLE_VIRTUAL_TERMINAL_INPUT makes Windows send.
  ;; keys.test.ts locks modifyOtherKeys shift+tab as ESC [ 27 ; 2 ; 9 ~.
  ;; A plain tab stays "tab". Kitty on or off does not change ESC [ Z.
  (unwind-protect
       (let ((shift-tab (format nil "~C[Z" #\Escape))
             (modify-other (format nil "~C[27;2;9~~" #\Escape))
             (kitty (format nil "~C[9;2u" #\Escape))
             (tab (string #\Tab)))
         (dolist (active '(nil t))
           (cadr-tui:set-kitty-protocol-active active)
           (is (string= "shift+tab" (cadr-tui:parse-key shift-tab)))
           (is (cadr-tui:matches-key shift-tab "shift+tab"))
           (is (not (cadr-tui:matches-key shift-tab "tab"))))
         (cadr-tui:set-kitty-protocol-active nil)
         (is (string= "shift+tab" (cadr-tui:parse-key modify-other)))
         (is (cadr-tui:matches-key modify-other "shift+tab"))
         (is (string= "shift+tab" (cadr-tui:parse-key kitty)))
         (is (cadr-tui:matches-key kitty "shift+tab"))
         (is (string= "tab" (cadr-tui:parse-key tab)))
         (is (cadr-tui:matches-key tab "tab"))
         (is (not (cadr-tui:matches-key tab "shift+tab")))
         (let ((manager (cadr-tui:make-keybindings-manager)))
           (is (cadr-tui:keybinding-matches-p
                manager shift-tab "app.thinking.cycle"))
           (is (not (cadr-tui:keybinding-matches-p
                     manager tab "app.thinking.cycle")))
           (is (cadr-tui:keybinding-matches-p
                manager tab "tui.input.tab"))
           (is (not (cadr-tui:keybinding-matches-p
                     manager shift-tab "tui.input.tab")))))
    (cadr-tui:set-kitty-protocol-active nil)))

(test keys-scanners-are-compiled
  (is (not (null cadr-tui::+kitty-scanner+)))
  (is (not (null cadr-tui::+modified-arrow-scanner+)))
  (cadr-tui:set-kitty-protocol-active t)
  (is (string=
       "left"
       (cadr-tui:parse-key
        (format nil "~C[57417u" #\Escape))))
  (cadr-tui:set-kitty-protocol-active nil))

(defun set-test-env (name value)
  (if (null value)
      (sb-posix:unsetenv name)
      (setf (uiop:getenv name) value)))

(defun call-with-restored-env (pairs function)
  (let ((saved
          (loop for (name) in pairs
                collect (cons name (uiop:getenv name)))))
    (unwind-protect
         (progn
           (dolist (pair pairs)
             (set-test-env (car pair) (cdr pair)))
           (funcall function))
      (dolist (pair saved)
        (set-test-env (car pair) (cdr pair))))))

(test raw-backspace-follows-local-windows-terminal
  ;; pi@4a080252f keys.test.ts. Byte 0x08 is ctrl+backspace only in a
  ;; local Windows Terminal. Empty WT_SESSION is absent. Empty SSH_*
  ;; does not suppress WT_SESSION. Byte 0x7f stays backspace.
  (cadr-tui:set-kitty-protocol-active nil)
  (let ((bs (string (code-char 8)))
        (del (string (code-char 127))))
    (call-with-restored-env
     '(("WT_SESSION" . nil)
       ("SSH_CONNECTION" . nil)
       ("SSH_CLIENT" . nil)
       ("SSH_TTY" . nil))
     (lambda ()
       (is (cadr-tui:matches-key bs "backspace"))
       (is (not (cadr-tui:matches-key bs "ctrl+backspace")))
       (is (string= "backspace" (cadr-tui:parse-key bs)))
       (is (cadr-tui:matches-key bs "ctrl+h"))
       (is (string= "backspace" (cadr-tui:parse-key del)))))
    (call-with-restored-env
     '(("WT_SESSION" . "test-session")
       ("SSH_CONNECTION" . nil)
       ("SSH_CLIENT" . nil)
       ("SSH_TTY" . nil))
     (lambda ()
       (is (cadr-tui:matches-key bs "ctrl+backspace"))
       (is (not (cadr-tui:matches-key bs "backspace")))
       (is (string= "ctrl+backspace" (cadr-tui:parse-key bs)))
       (is (cadr-tui:matches-key bs "ctrl+h"))))
    (call-with-restored-env
     '(("WT_SESSION" . "")
       ("SSH_CONNECTION" . nil)
       ("SSH_CLIENT" . nil)
       ("SSH_TTY" . nil))
     (lambda ()
       (is (string= "backspace" (cadr-tui:parse-key bs)))))
    (call-with-restored-env
     '(("WT_SESSION" . "test-session")
       ("SSH_CONNECTION" . "")
       ("SSH_CLIENT" . nil)
       ("SSH_TTY" . nil))
     (lambda ()
       (is (string= "ctrl+backspace" (cadr-tui:parse-key bs)))))
    (call-with-restored-env
     '(("WT_SESSION" . "test-session")
       ("SSH_CONNECTION" . "1 2 3 4")
       ("SSH_CLIENT" . "1 2 3")
       ("SSH_TTY" . "/dev/pts/1"))
     (lambda ()
       (is (not (cadr-tui:matches-key bs "ctrl+backspace")))
       (is (cadr-tui:matches-key bs "backspace"))
       (is (string= "backspace" (cadr-tui:parse-key bs)))
       (is (cadr-tui:matches-key bs "ctrl+h"))))))
