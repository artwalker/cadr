(in-package #:cadr-tui)

(defparameter +unix-keybinding-definitions+
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
    ;; pi@4a080252f tui/keybindings.ts:68-75 — prompt history
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
    ;; pi@4a080252f keybindings.ts #10314 — unmodified Home/End stay
    ;; with the editor. Ctrl+Home/Ctrl+End scroll the fullscreen
    ;; transcript, so they are not also line-start/line-end.
    ("tui.editor.cursorLineStart"
     . ("home" "ctrl+a"))
    ("tui.editor.cursorLineEnd"
     . ("end" "ctrl+e"))
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
    ;; pi@4a080252f tui/keybindings.ts:154-178 — the alt-screen
    ;; viewport keys moved off the shift/ctrl modifiers and gained
    ;; half-page and prompt-jump actions.
    ("tui.altScreen.pageUp" . ("pageUp"))
    ("tui.altScreen.pageDown" . ("pageDown"))
    ("tui.altScreen.halfPageUp" . nil)
    ("tui.altScreen.halfPageDown" . nil)
    ;; v1.4.0: one-line scrolling and transcript search actions.
    ("tui.altScreen.lineUp" . nil)
    ("tui.altScreen.lineDown" . nil)
    ;; pi@4a080252f keybindings.ts — Unix keeps both chords.
    ("tui.altScreen.previousPrompt" . ("ctrl+shift+up" "ctrl+up"))
    ("tui.altScreen.nextPrompt" . ("ctrl+shift+down" "ctrl+down"))
    ("tui.altScreen.search" . ("ctrl+shift+f"))
    ("tui.altScreen.searchNext" . ("enter" "ctrl+g"))
    ("tui.altScreen.searchPrevious" . ("shift+enter" "ctrl+shift+g"))
    ("tui.altScreen.searchClose" . ("escape"))
    ("tui.altScreen.top" . ("ctrl+home"))
    ("tui.altScreen.bottom" . ("ctrl+end"))))

;; pi@4a080252f keybindings.ts useWindowsKeybindings and the
;; platform branches of KEYBINDINGS. :windows applies to native
;; win32 and to WSL. Undo and suspend split win32 from WSL.
;; A missing entry inherits the Unix row. nil is an empty default.
(defparameter +keybinding-platform-deltas+
  '(("app.suspend" :win32 nil)
    ("app.model.cycleBackward" :windows ("alt+p"))
    ("app.message.followUp" :windows ("ctrl+q"))
    ("app.message.dequeue" :windows ("alt+q"))
    ("app.clipboard.pasteImage" :windows ("alt+v"))
    ("tui.editor.undo" :win32 ("ctrl+z") :wsl ("alt+z"))
    ("tui.altScreen.previousPrompt" :windows ("ctrl+up"))
    ("tui.altScreen.nextPrompt" :windows ("ctrl+down"))
    ("tui.altScreen.search" :windows ("ctrl+f"))))

(defun keybinding-host-platform ()
  (cond
    ((uiop:os-windows-p) "win32")
    ((uiop:os-macosx-p) "darwin")
    (t "linux")))

(defun keybinding-environment-present-p (environment name)
  (let ((value
          (if (eq environment :process)
              (uiop:getenv name)
              (cdr (assoc name environment :test #'string=)))))
    (and (stringp value) (plusp (length value)) t)))

(defun use-windows-keybindings
    (&key
       (platform (keybinding-host-platform))
       (environment :process))
  (or (string= platform "win32")
      (and (string= platform "linux")
           (or (keybinding-environment-present-p
                environment "WSL_DISTRO_NAME")
               (keybinding-environment-present-p
                environment "WSL_INTEROP"))
           t)))

(defun keybinding-platform-class (platform environment)
  (cond
    ((string= platform "win32") :win32)
    ((use-windows-keybindings
      :platform platform
      :environment environment)
     :wsl)
    (t :unix)))

(defun keybinding-plist-entry (plist key)
  (loop for rest on plist by #'cddr
        when (eq (car rest) key)
          return (values (cadr rest) t)
        finally (return (values nil nil))))

(defun platform-delta-keys (name class)
  (let ((entry
          (assoc name +keybinding-platform-deltas+
                 :test #'string=)))
    (unless entry
      (return-from platform-delta-keys :inherit))
    (let ((plist (cdr entry)))
      (multiple-value-bind (value present)
          (keybinding-plist-entry plist class)
        (when present
          (return-from platform-delta-keys value)))
      (when (member class '(:win32 :wsl))
        (multiple-value-bind (value present)
            (keybinding-plist-entry plist :windows)
          (when present
            (return-from platform-delta-keys value)))))
    :inherit))

(defun default-keybinding-definitions
    (&key
       (platform (keybinding-host-platform))
       (environment :process))
  (let ((class
          (keybinding-platform-class platform environment)))
    (loop for pair in +unix-keybinding-definitions+
          for replacement = (platform-delta-keys (car pair) class)
          collect (if (eq replacement :inherit)
                      pair
                      (cons (car pair) replacement)))))

(defun tree-branch-default-keys (platform)
  ;; pi@4a080252f keybindings.ts app.tree.foldOrUp / unfoldOrDown.
  (if (string= platform "darwin")
      (values '("alt+left" "ctrl+left")
              '("alt+right" "ctrl+right"))
      (values '("ctrl+left" "alt+left")
              '("ctrl+right" "alt+right"))))

(defparameter +tui-keybinding-definitions+
  (default-keybinding-definitions))

(defparameter +logical-key-events+
  '(("app.interrupt" . :interrupt)
    ("app.clear" . :clear)
    ("app.exit" . :eof)
    ("app.debug" . :debug)
    ("app.message.followUp" . :follow-up)
    ("app.message.dequeue" . :dequeue)
    ("app.message.copy" . :copy)
    ("app.clipboard.pasteImage" . :paste-image)
    ("app.editor.external" . :external-editor)
    ("app.session.new" . :session-new)
    ("app.session.tree" . :session-tree)
    ("app.session.fork" . :session-fork)
    ("app.session.resume" . :session-resume)
    ("app.model.cycleForward" . :model-cycle-forward)
    ("app.model.cycleBackward" . :model-cycle-backward)
    ("tui.editor.cursorUp" . :up)
    ("tui.editor.cursorDown" . :down)
    ("tui.editor.historyPrevious" . :history-previous)
    ("tui.editor.historyNext" . :history-next)
    ("tui.editor.cursorLeft" . :left)
    ("tui.editor.cursorRight" . :right)
    ("tui.editor.cursorWordLeft" . :word-left)
    ("tui.editor.cursorWordRight" . :word-right)
    ("tui.editor.cursorLineStart" . :line-start)
    ("tui.editor.cursorLineEnd" . :line-end)
    ("tui.editor.jumpForward" . :jump-forward)
    ("tui.editor.jumpBackward" . :jump-backward)
    ("tui.editor.pageUp" . :page-up)
    ("tui.editor.pageDown" . :page-down)
    ("tui.editor.deleteCharBackward" . :backspace)
    ("tui.editor.deleteCharForward" . :delete)
    ("tui.editor.deleteWordBackward"
     . :delete-word-backward)
    ("tui.editor.deleteWordForward"
     . :delete-word-forward)
    ("tui.editor.deleteToLineStart"
     . :delete-line-start)
    ("tui.editor.deleteToLineEnd"
     . :delete-line-end)
    ("tui.editor.yank" . :yank)
    ("tui.editor.yankPop" . :yank-pop)
    ("tui.editor.undo" . :undo)
    ("tui.input.newLine" . :newline)
    ("tui.input.submit" . :enter)
    ("tui.input.tab" . :tab)))

(defstruct (keybindings-manager
            (:constructor %make-keybindings-manager))
  definitions
  user-bindings
  resolved
  conflicts
  ;; Flattened (key-id . kind) built at rebuild.  event-kind-for-raw-key
  ;; parse-key's once and walks this instead of rescanning
  ;; +logical-key-events+ through matches-key (input.ts key table).
  event-kinds)

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
    (let ((resolved-final (nreverse resolved))
          (conflicts-final (nreverse conflicts)))
      (setf
       (keybindings-manager-resolved manager)
       resolved-final
       (keybindings-manager-conflicts manager)
       conflicts-final
       (keybindings-manager-event-kinds manager)
       (logical-event-kind-entries resolved-final))))
  manager)

(defun logical-event-kind-entries (resolved)
  ;; First name in +logical-key-events+ that owns a key wins, matching
  ;; the old loop order.
  (let ((entries nil))
    (dolist (pair +logical-key-events+)
      (let* ((name (car pair))
             (kind (cdr pair))
             (keys (cdr (assoc name resolved :test #'string=))))
        (dolist (key keys)
          (push (cons key kind) entries))))
    (nreverse entries)))

(defun logical-key-id-matches-data-p (key-id data parsed)
  ;; Same specials as matches-key, but parse-key is supplied by the
  ;; caller so the dispatch table does not recompile scanners.
  (multiple-value-bind (key mask)
      (split-key-id key-id)
    (when (and (= (length data) 1)
               (string= key "h")
               (= mask +key-modifier-control+)
               (= (codepoint (char data 0)) 8))
      (return-from logical-key-id-matches-data-p t))
    (let ((control
            (and (= mask +key-modifier-control+)
                 (raw-control-codepoint-for-key key))))
      (when (and control
                 (= (length data) 1)
                 (= (codepoint (char data 0)) control))
        (return-from logical-key-id-matches-data-p t))))
  (or (legacy-alt-printable-matches-p data key-id)
      (and parsed
           (string= (canonical-key-id parsed)
                    (canonical-key-id key-id)))))

(defun make-keybindings-manager
    (&key
       (definitions +tui-keybinding-definitions+)
       user-bindings)
  (rebuild-keybindings-manager
   (%make-keybindings-manager
    :definitions
    (if (eq definitions +tui-keybinding-definitions+)
        definitions
        (copy-tree definitions))
    :user-bindings
    (copy-tree user-bindings))))

(defun keybinding-keys (manager name)
  (cdr
   (assoc name
          (keybindings-manager-resolved manager)
          :test #'string=)))

(defun keybinding-matches-p
    (manager data name)
  (some
   (lambda (key)
     (matches-key data key))
   (keybinding-keys manager name)))

(defun keybinding-conflicts (manager)
  (keybindings-manager-conflicts manager))

(defvar *global-keybindings* nil)

(defun set-keybindings (manager)
  (setf *global-keybindings* manager))

(defun get-keybindings ()
  (or *global-keybindings*
      (setf *global-keybindings*
            (make-keybindings-manager))))
