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
