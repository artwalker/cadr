(in-package #:cadr-tui/tests)
(in-suite cadr-tui-suite)

(test goal18-session-actions-registered-unbound-bindable-and-decoding
  ;; Goal 18 I7: the baseline keybindings.ts:115-118 registry carries
  ;; app.session.{new,tree,fork,resume} with empty defaultKeys; cadr
  ;; must register them unbound, resolve user settings.json bindings for
  ;; them, and decode those keys to dispatch keywords.
  (dolist (action
           '("app.session.new" "app.session.tree" "app.session.fork"
             "app.session.resume"))
    (let ((definition
            (assoc
             action
             cadr-tui::+tui-keybinding-definitions+
             :test #'string=)))
      (is (not (null definition)) "~A is missing from the registry" action)
      (is (null (cdr definition))
          "~A must default to no keys (baseline defaultKeys: [])"
          action))
    (is
     (not
      (null
       (assoc
        action
        cadr-tui::+logical-key-events+
        :test #'string=)))
     "~A has no dispatch keyword" action))
  (let ((manager
          (cadr-tui:make-keybindings-manager
           :user-bindings '(("app.session.tree" . ("ctrl+alt+t"))))))
    (is
     (equal
      '("ctrl+alt+t")
      (cadr-tui:keybinding-keys manager "app.session.tree"))
     "a settings.json binding for app.session.tree must resolve"))
  (let ((previous (cadr-tui:get-keybindings)))
    (unwind-protect
         (progn
           (cadr-tui:set-keybindings
            (cadr-tui:make-keybindings-manager
             :user-bindings '(("app.session.tree" . ("ctrl+alt+t")))))
           (is
            (eq
             :session-tree
             (cadr-tui::event-kind-for-raw-key
              ;; Kitty CSI-u: t (116) with ctrl+alt (modifier 7).
              (format nil "~C[116;7u" #\Escape)))
            "ctrl+alt+t must decode to :session-tree"))
      (cadr-tui:set-keybindings previous))))

(test keybindings-defaults-overrides-and-conflicts
  (let ((manager
          (cadr-tui:make-keybindings-manager)))
    (is
     (equal
      '("ctrl+p")
      (cadr-tui:keybinding-keys
       manager "app.model.cycleForward")))
    (is
     (equal
      '("shift+ctrl+p")
      (cadr-tui:keybinding-keys
       manager "app.model.cycleBackward")))
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

(test model-cycle-keybindings-can-be-remapped-or-disabled
  (let ((remapped
          (cadr-tui:make-keybindings-manager
           :user-bindings
           '(("app.model.cycleForward" . ("ctrl+g"))
             ("app.model.cycleBackward" . ("ctrl+shift+g")))))
        (disabled
          (cadr-tui:make-keybindings-manager
           :user-bindings
           '(("app.model.cycleForward" . nil)
             ("app.model.cycleBackward" . nil)))))
    (is
     (equal
      '("ctrl+g")
      (cadr-tui:keybinding-keys
       remapped "app.model.cycleForward")))
    (is
     (equal
      '("ctrl+shift+g")
      (cadr-tui:keybinding-keys
       remapped "app.model.cycleBackward")))
    (is
     (null
      (cadr-tui:keybinding-keys
       disabled "app.model.cycleForward")))
    (is
     (null
      (cadr-tui:keybinding-keys
       disabled "app.model.cycleBackward")))))
