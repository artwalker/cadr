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
          (cadr-tui:make-keybindings-manager
           :definitions
           (cadr-tui:default-keybinding-definitions
            :platform "linux" :environment nil))))
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

(test fullscreen-home-and-end-stay-on-the-editor
  ;; pi@4a080252f keybindings.ts #10314.
  (let ((manager (cadr-tui:make-keybindings-manager))
        (home (format nil "~COH" #\Escape))
        (end (format nil "~C[F" #\Escape))
        (ctrl-home (format nil "~C[1;5H" #\Escape))
        (ctrl-end (format nil "~C[1;5F" #\Escape))
        (legacy-ctrl-home (format nil "~C[7^" #\Escape))
        (legacy-ctrl-end (format nil "~C[8^" #\Escape))
        (kitty-ctrl-home (format nil "~C[57423;5u" #\Escape)))
    (is (equal
         '("home" "ctrl+a")
         (cadr-tui:keybinding-keys
          manager "tui.editor.cursorLineStart")))
    (is (equal
         '("end" "ctrl+e")
         (cadr-tui:keybinding-keys
          manager "tui.editor.cursorLineEnd")))
    (is (equal
         '("ctrl+home")
         (cadr-tui:keybinding-keys
          manager "tui.altScreen.top")))
    (is (equal
         '("ctrl+end")
         (cadr-tui:keybinding-keys
          manager "tui.altScreen.bottom")))
    (is (not
         (cadr-tui:keybinding-matches-p
          manager home "tui.altScreen.top")))
    (is (not
         (cadr-tui:keybinding-matches-p
          manager end "tui.altScreen.bottom")))
    (is (eq t
            (cadr-tui:keybinding-matches-p
             manager ctrl-home "tui.altScreen.top")))
    (is (eq t
            (cadr-tui:keybinding-matches-p
             manager legacy-ctrl-home "tui.altScreen.top")))
    (is (eq t
            (cadr-tui:keybinding-matches-p
             manager kitty-ctrl-home "tui.altScreen.top")))
    (is (eq t
            (cadr-tui:keybinding-matches-p
             manager ctrl-end "tui.altScreen.bottom")))
    (is (eq t
            (cadr-tui:keybinding-matches-p
             manager legacy-ctrl-end "tui.altScreen.bottom")))
    (is (eq :line-start
            (cadr-tui::event-kind-for-raw-key home)))
    (is (eq :line-end
            (cadr-tui::event-kind-for-raw-key end)))
    (is (null
         (cadr-tui::event-kind-for-raw-key ctrl-home)))
    (is (null
         (cadr-tui::event-kind-for-raw-key ctrl-end)))))

(defun windows-key-defaults-manager (platform environment)
  (cadr-tui:make-keybindings-manager
   :definitions
   (cadr-tui:default-keybinding-definitions
    :platform platform :environment environment)))

(defun windows-key-defaults-keys (platform environment name)
  (cadr-tui:keybinding-keys
   (windows-key-defaults-manager platform environment)
   name))

(test windows-and-wsl-key-defaults-match-v140
  ;; pi@4a080252f keybindings.ts useWindowsKeybindings and
  ;; packages/coding-agent/test/keybindings.test.ts.
  (is (eq t
          (cadr-tui:use-windows-keybindings
           :platform "win32" :environment nil)))
  (is (eq t
          (cadr-tui:use-windows-keybindings
           :platform "linux"
           :environment '(("WSL_DISTRO_NAME" . "Ubuntu")))))
  (is (eq t
          (cadr-tui:use-windows-keybindings
           :platform "linux"
           :environment
           '(("WSL_INTEROP" . "/run/WSL/123_interop")))))
  (is (eq nil
          (cadr-tui:use-windows-keybindings
           :platform "linux"
           :environment '(("WT_SESSION" . "session")))))
  (is (eq nil
          (cadr-tui:use-windows-keybindings
           :platform "linux"
           :environment
           '(("WSL_DISTRO_NAME" . "")
             ("WSL_INTEROP" . "")))))
  (is (eq nil
          (cadr-tui:use-windows-keybindings
           :platform "linux" :environment nil)))
  (is (eq nil
          (cadr-tui:use-windows-keybindings
           :platform "darwin" :environment nil)))
  (is (eq nil
          (cadr-tui:use-windows-keybindings
           :platform "darwin"
           :environment '(("WSL_DISTRO_NAME" . "Ubuntu")))))
  (dolist (case
           '((:win32 nil
              ("alt+v") ("ctrl+f") ("ctrl+q") ("alt+p")
              ("ctrl+z") ("ctrl+up") ("ctrl+down") ("alt+q")
              nil)
             (:wsl (("WSL_DISTRO_NAME" . "Ubuntu"))
              ("alt+v") ("ctrl+f") ("ctrl+q") ("alt+p")
              ("alt+z") ("ctrl+up") ("ctrl+down") ("alt+q")
              ("ctrl+z"))
             (:unix nil
              ("ctrl+v") ("ctrl+shift+f") ("alt+enter")
              ("shift+ctrl+p") ("ctrl+-")
              ("ctrl+shift+up" "ctrl+up")
              ("ctrl+shift+down" "ctrl+down")
              ("alt+up") ("ctrl+z"))))
    (destructuring-bind
        (class environment paste search follow-up backward
         undo previous next dequeue suspend)
        case
      (let ((platform (if (eq class :win32) "win32" "linux")))
        (is (equal paste
                   (windows-key-defaults-keys
                    platform environment
                    "app.clipboard.pasteImage")))
        (is (equal search
                   (windows-key-defaults-keys
                    platform environment
                    "tui.altScreen.search")))
        (is (equal follow-up
                   (windows-key-defaults-keys
                    platform environment
                    "app.message.followUp")))
        (is (equal backward
                   (windows-key-defaults-keys
                    platform environment
                    "app.model.cycleBackward")))
        (is (equal undo
                   (windows-key-defaults-keys
                    platform environment
                    "tui.editor.undo")))
        (is (equal previous
                   (windows-key-defaults-keys
                    platform environment
                    "tui.altScreen.previousPrompt")))
        (is (equal next
                   (windows-key-defaults-keys
                    platform environment
                    "tui.altScreen.nextPrompt")))
        (is (equal dequeue
                   (windows-key-defaults-keys
                    platform environment
                    "app.message.dequeue")))
        (is (equal suspend
                   (windows-key-defaults-keys
                    platform environment
                    "app.suspend")))
        (is (equal '("right" "ctrl+f")
                   (windows-key-defaults-keys
                    platform environment
                    "tui.editor.cursorRight"))))))
  (dolist (platform '("linux" "win32" "darwin"))
    (multiple-value-bind (fold unfold)
        (cadr-tui:tree-branch-default-keys platform)
      (if (string= platform "darwin")
          (progn
            (is (equal '("alt+left" "ctrl+left") fold))
            (is (equal '("alt+right" "ctrl+right") unfold)))
          (progn
            (is (equal '("ctrl+left" "alt+left") fold))
            (is (equal '("ctrl+right" "alt+right") unfold))))))
  (let* ((windows (cadr-tui:use-windows-keybindings))
         (native (uiop:os-windows-p))
         (defs cadr-tui::+tui-keybinding-definitions+))
    (is (equal
         (if windows '("alt+p") '("shift+ctrl+p"))
         (cdr (assoc "app.model.cycleBackward" defs
                     :test #'string=))))
    (is (equal
         (cond (native '("ctrl+z"))
               (windows '("alt+z"))
               (t '("ctrl+-")))
         (cdr (assoc "tui.editor.undo" defs :test #'string=)))))
  (let ((previous (cadr-tui:get-keybindings))
        (windows
          (windows-key-defaults-manager
           "linux" '(("WSL_DISTRO_NAME" . "Ubuntu")))))
    (unwind-protect
         (progn
           (cadr-tui:set-keybindings windows)
           (is (eq :model-cycle-backward
                   (cadr-tui::event-kind-for-raw-key
                    (format nil "~Cp" #\Escape))))
           (is (eq :dequeue
                   (cadr-tui::event-kind-for-raw-key
                    (format nil "~Cq" #\Escape))))
           (is (eq :follow-up
                   (cadr-tui::event-kind-for-raw-key
                    (string (code-char 17)))))
           (is (eq :undo
                   (cadr-tui::event-kind-for-raw-key
                    (format nil "~Cz" #\Escape))))
           (is (null
                (cadr-tui::event-kind-for-raw-key
                 (string (code-char 31))))))
      (cadr-tui:set-keybindings previous)))
  (let ((previous (cadr-tui:get-keybindings))
        (native
          (windows-key-defaults-manager "win32" nil)))
    (unwind-protect
         (progn
           (cadr-tui:set-keybindings native)
           (is (eq :undo
                   (cadr-tui::event-kind-for-raw-key
                    (string (code-char 26)))))
           (is (not
                (cadr-tui:keybinding-matches-p
                 native
                 (string (code-char 26))
                 "app.suspend"))))
      (cadr-tui:set-keybindings previous))))
