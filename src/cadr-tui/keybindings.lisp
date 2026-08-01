(in-package #:cadr-tui)

(defparameter +tui-keybinding-definitions+
  '(("app.interrupt" . ("escape"))
    ("app.clear" . ("ctrl+c"))
    ("app.exit" . ("ctrl+d"))
    ("app.message.followUp" . ("alt+enter"))
    ("app.message.dequeue" . ("alt+up"))
    ("tui.editor.cursorUp" . ("up"))
    ("tui.editor.cursorDown" . ("down"))
    ("tui.editor.cursorLeft" . ("left" "ctrl+b"))
    ("tui.editor.cursorRight" . ("right" "ctrl+f"))
    ("tui.editor.cursorWordLeft"
     . ("alt+left" "ctrl+left" "alt+b"))
    ("tui.editor.cursorWordRight"
     . ("alt+right" "ctrl+right" "alt+f"))
    ("tui.editor.cursorLineStart" . ("home" "ctrl+a"))
    ("tui.editor.cursorLineEnd" . ("end" "ctrl+e"))
    ("tui.editor.jumpForward" . ("ctrl+]"))
    ("tui.editor.jumpBackward" . ("ctrl+alt+]"))
    ("tui.editor.pageUp" . ("pageUp"))
    ("tui.editor.pageDown" . ("pageDown"))
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
    ("tui.altScreen.pageUp" . ("shift+pageUp"))
    ("tui.altScreen.pageDown" . ("shift+pageDown"))
    ("tui.altScreen.top" . ("ctrl+home"))
    ("tui.altScreen.bottom" . ("ctrl+end"))))

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
