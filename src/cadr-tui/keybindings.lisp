(in-package #:cadr-tui)

(defparameter +tui-keybinding-definitions+
  '(("app.interrupt" . ("escape"))
    ("app.clear" . ("ctrl+c"))
    ("app.exit" . ("ctrl+d"))
    ("app.suspend" . ("ctrl+z"))
    ("app.debug" . ("shift+ctrl+d"))
    ("app.thinking.cycle" . ("shift+tab"))
    ("app.message.followUp" . ("alt+enter"))
    ("app.message.dequeue" . ("alt+up"))
    ("app.editor.external" . ("ctrl+g"))
    ("app.model.cycleForward" . ("ctrl+p"))
    ("app.model.cycleBackward" . ("shift+ctrl+p"))
    ("app.model.select" . ("ctrl+l"))
    ("app.tools.expand" . ("ctrl+o"))
    ("app.thinking.toggle" . ("ctrl+t"))
    ("app.message.copy" . ("ctrl+x"))
    ("app.clipboard.pasteImage" . ("ctrl+v"))
    ;; Session actions exist in the baseline registry with empty default
    ;; keys (keybindings.ts:115-118): bindable through settings.json and
    ;; listed there, but unbound by default.
    ("app.session.new" . nil)
    ("app.session.tree" . nil)
    ("app.session.fork" . nil)
    ("app.session.resume" . nil)
    ("tui.editor.cursorUp" . ("up"))
    ("tui.editor.cursorDown" . ("down"))
    ;; pi@914cf1472 tui/keybindings.ts:68-75 — prompt history
    ;; navigation is registered with empty defaults (bindable through
    ;; keybindings.json, unbound by default).
    ("tui.editor.historyPrevious" . nil)
    ("tui.editor.historyNext" . nil)
    ("tui.editor.cursorLeft" . ("left" "ctrl+b"))
    ("tui.editor.cursorRight" . ("right" "ctrl+f"))
    ("tui.editor.cursorWordLeft"
     . ("alt+left" "ctrl+left" "alt+b"))
    ("tui.editor.cursorWordRight"
     . ("alt+right" "ctrl+right" "alt+f"))
    ("tui.editor.cursorLineStart"
     . ("home" "ctrl+home" "ctrl+a"))
    ("tui.editor.cursorLineEnd"
     . ("end" "ctrl+end" "ctrl+e"))
    ("tui.editor.jumpForward" . ("ctrl+]"))
    ("tui.editor.jumpBackward" . ("ctrl+alt+]"))
    ("tui.editor.pageUp" . ("pageUp" "ctrl+pageUp"))
    ("tui.editor.pageDown" . ("pageDown" "ctrl+pageDown"))
    ("tui.editor.deleteCharBackward" . ("backspace"))
    ("tui.editor.deleteCharForward" . ("delete" "ctrl+d"))
    ("tui.editor.deleteWordBackward"
     . ("ctrl+w" "alt+backspace"))
    ("tui.editor.deleteWordForward"
     . ("alt+d" "alt+delete"))
    ("tui.editor.deleteToLineStart" . ("ctrl+u"))
    ("tui.editor.deleteToLineEnd" . ("ctrl+k"))
    ("tui.editor.yank" . ("ctrl+y"))
    ("tui.editor.yankPop" . ("alt+y"))
    ("tui.editor.undo" . ("ctrl+-"))
    ("tui.input.newLine" . ("shift+enter" "ctrl+j"))
    ("tui.input.submit" . ("enter"))
    ("tui.input.tab" . ("tab"))
    ("tui.input.copy" . ("ctrl+c"))
    ("tui.select.up" . ("up"))
    ("tui.select.down" . ("down"))
    ("tui.select.pageUp" . ("pageUp"))
    ("tui.select.pageDown" . ("pageDown"))
    ("tui.select.confirm" . ("enter"))
    ("tui.select.cancel" . ("escape" "ctrl+c"))
    ;; pi@914cf1472 tui/keybindings.ts:154-178 — the alt-screen
    ;; viewport keys moved off the shift/ctrl modifiers and gained
    ;; half-page and prompt-jump actions.
    ("tui.altScreen.pageUp" . ("pageUp"))
    ("tui.altScreen.pageDown" . ("pageDown"))
    ("tui.altScreen.halfPageUp" . nil)
    ("tui.altScreen.halfPageDown" . nil)
    ;; v0.84.2: one-line scrolling and transcript search actions.
    ("tui.altScreen.lineUp" . nil)
    ("tui.altScreen.lineDown" . nil)
    ("tui.altScreen.previousPrompt" . ("ctrl+shift+up"))
    ("tui.altScreen.nextPrompt" . ("ctrl+shift+down"))
    ("tui.altScreen.search" . ("ctrl+shift+f"))
    ("tui.altScreen.searchNext" . ("enter" "ctrl+g"))
    ("tui.altScreen.searchPrevious" . ("shift+enter" "ctrl+shift+g"))
    ("tui.altScreen.searchClose" . ("escape"))
    ("tui.altScreen.top" . ("home"))
    ("tui.altScreen.bottom" . ("end"))))

(defstruct (keybindings-manager
            (:constructor %make-keybindings-manager))
  definitions
  user-bindings
  resolved
  conflicts)

(defun normalized-binding-keys (value)
  (let ((keys
          (cond
            ((null value) nil)
            ((stringp value) (list value))
            (t (copy-list value)))))
    (remove-duplicates keys :test #'string=)))

(defun rebuild-keybindings-manager (manager)
  (let ((resolved nil)
        (claims nil)
        (conflicts nil))
    (dolist (definition
             (keybindings-manager-definitions manager))
      (let* ((name (car definition))
             (user
               (assoc
                name
                (keybindings-manager-user-bindings manager)
                :test #'string=))
             (keys
               (normalized-binding-keys
                (if user (cdr user) (cdr definition)))))
        (push (cons name keys) resolved)))
    (dolist (binding
             (keybindings-manager-user-bindings manager))
      (when (assoc
             (car binding)
             (keybindings-manager-definitions manager)
             :test #'string=)
        (dolist (key
                 (normalized-binding-keys (cdr binding)))
          (let ((claim
                  (assoc key claims :test #'string=)))
            (if claim
                (setf (cdr claim)
                      (append (cdr claim)
                              (list (car binding))))
                (push
                 (list key (car binding))
                 claims))))))
    (dolist (claim (nreverse claims))
      (when (> (length (cdr claim)) 1)
        (push claim conflicts)))
    (setf
     (keybindings-manager-resolved manager)
     (nreverse resolved)
     (keybindings-manager-conflicts manager)
     (nreverse conflicts)))
  manager)

(defun make-keybindings-manager
    (&key
       (definitions +tui-keybinding-definitions+)
       user-bindings)
  (rebuild-keybindings-manager
   (%make-keybindings-manager
    :definitions
    (copy-tree definitions)
    :user-bindings
    (copy-tree user-bindings))))

(defun keybinding-keys (manager name)
  (copy-list
   (cdr
    (assoc name
           (keybindings-manager-resolved manager)
           :test #'string=))))

(defun keybinding-matches-p
    (manager data name)
  (some
   (lambda (key)
     (matches-key data key))
   (keybinding-keys manager name)))

(defun keybinding-conflicts (manager)
  (copy-tree
   (keybindings-manager-conflicts manager)))

(defvar *global-keybindings* nil)

(defun set-keybindings (manager)
  (setf *global-keybindings* manager))

(defun get-keybindings ()
  (or *global-keybindings*
      (setf *global-keybindings*
            (make-keybindings-manager))))
