(in-package #:cadr-tui/tests)
(in-suite cadr-tui-suite)

(test keybindings-defaults-overrides-and-conflicts
  (let ((manager
          (cadr-tui:make-keybindings-manager)))
    (is
     (equal
      '("shift+enter" "ctrl+j")
      (cadr-tui:keybinding-keys
       manager "tui.input.newLine")))
    (is
     (cadr-tui:keybinding-matches-p
      manager (string #\Newline)
      "tui.input.newLine")))
  (let ((manager
          (cadr-tui:make-keybindings-manager
           :user-bindings
           '(("tui.input.submit"
              . ("enter" "ctrl+enter"))
             ("tui.select.up"
              . ("up" "ctrl+p"))))))
    (is
     (equal
      '("enter" "ctrl+enter")
      (cadr-tui:keybinding-keys
       manager "tui.input.submit")))
    (is
     (equal
      '("enter")
      (cadr-tui:keybinding-keys
       manager "tui.select.confirm")))
    (is
     (equal
      '("up")
      (cadr-tui:keybinding-keys
       manager "tui.editor.cursorUp"))))
  (let ((manager
          (cadr-tui:make-keybindings-manager
           :user-bindings
           '(("tui.input.submit" . "ctrl+x")
             ("tui.select.confirm" . "ctrl+x")))))
    (is
     (equal
      '(("ctrl+x"
         "tui.input.submit"
         "tui.select.confirm"))
      (cadr-tui:keybinding-conflicts manager)))
    (is
     (equal
      '("left" "ctrl+b")
      (cadr-tui:keybinding-keys
       manager "tui.editor.cursorLeft")))))
