(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defparameter +goal28-pin-rpc-methods+
  '("abort" "abort_bash" "abort_retry" "bash" "clear_queue"
    "clone" "compact" "cycle_model" "cycle_thinking_level"
    "export_html" "follow_up" "fork" "get_available_models"
    "get_available_thinking_levels" "get_commands" "get_entries"
    "get_fork_messages" "get_last_assistant_text" "get_messages"
    "get_session_stats" "get_state" "get_tree" "new_session"
    "prompt" "set_auto_compaction" "set_auto_retry"
    "set_follow_up_mode" "set_model" "set_session_name"
    "set_steering_mode" "set_thinking_level" "steer"
    "switch_session"))

(defparameter +goal28-pin-theme-tokens+
  '("accent" "bashMode" "border" "borderAccent" "borderMuted"
    "customMessageBg" "customMessageLabel" "customMessageText"
    "dim" "error" "mdCode" "mdCodeBlock" "mdCodeBlockBorder"
    "mdHeading" "mdHr" "mdLink" "mdLinkUrl" "mdListBullet"
    "mdQuote" "mdQuoteBorder" "muted" "scrollbarThumb"
    "scrollbarTrack" "searchMatchBg" "searchMatchText"
    "selectedBg" "success" "syntaxComment" "syntaxFunction"
    "syntaxKeyword" "syntaxNumber" "syntaxOperator"
    "syntaxPunctuation" "syntaxString" "syntaxType"
    "syntaxVariable" "text" "thinkingHigh" "thinkingLow"
    "thinkingMax" "thinkingMedium" "thinkingMinimal"
    "thinkingOff" "thinkingText" "thinkingXhigh" "toolDiffAdded"
    "toolDiffContext" "toolDiffRemoved" "toolErrorBg"
    "toolOutput" "toolPendingBg" "toolSuccessBg" "toolTitle"
    "userMessageBg" "userMessageText" "warning"))

(defun goal28-theme-token-name (keyword)
  (let* ((name (string-downcase (symbol-name keyword)))
         (parts (uiop:split-string name :separator '(#\-))))
    (concatenate
     'string
     (first parts)
     (apply #'concatenate
            'string
            (mapcar #'string-capitalize (rest parts))))))

(defun goal28-keybinding-action-names ()
  (remove-duplicates
   (append
    (mapcar #'car cadr-tui::+tui-keybinding-definitions+)
    (mapcar #'car
            cadr-cli::+models-selector-keybinding-definitions+)
    (mapcar #'car
            cadr-cli::+session-selector-keybinding-definitions+)
    (mapcar #'car
            cadr-cli::+thinking-selector-keybinding-definitions+)
    (mapcar #'car
            cadr-cli::+tree-selector-keybinding-definitions+))
   :test #'string=))

(defun goal28-rpc-command-types-from-source ()
  (let* ((path
           (merge-pathnames
            "src/cadr-cli/modes/rpc/commands.lisp"
            (asdf:system-source-directory "cadr-cli")))
         (text (uiop:read-file-string path))
         (types nil)
         (start 0))
    (loop
      (let ((pos
              (search
               "(string= type"
               text
               :start2 start)))
        (unless pos
          (return))
        (let* ((quote
                 (position
                  #\" text
                  :start (+ pos (length "(string= type"))))
               (end
                 (and quote
                      (position #\" text :start (1+ quote)))))
          (unless (and quote end)
            (return))
          (push (subseq text (1+ quote) end) types)
          (setf start (1+ end)))))
    (remove-duplicates types :test #'string=)))

(test goal28-rpc-methods-reach-existing-dispatch
  (let ((types (goal28-rpc-command-types-from-source)))
    (is (= (length +goal28-pin-rpc-methods+)
           (length types)))
    (dolist (method +goal28-pin-rpc-methods+)
      (is (find method types :test #'string=)))))

(test goal28-theme-tokens-reach-existing-palette
  (let ((names
          (mapcar
           #'goal28-theme-token-name
           (mapcar #'car cadr-tui::+dark-theme-colors+))))
    (dolist (token +goal28-pin-theme-tokens+)
      (is (find token names :test #'string=)))))

(test goal28-keybinding-actions-reach-existing-registries
  (let ((names (goal28-keybinding-action-names))
        (pin
          (remove-duplicates
           (append
            (mapcar #'car cadr-tui::+tui-keybinding-definitions+)
            (mapcar #'car
                    cadr-cli::+models-selector-keybinding-definitions+)
            (mapcar #'car
                    cadr-cli::+session-selector-keybinding-definitions+)
            (mapcar #'car
                    cadr-cli::+thinking-selector-keybinding-definitions+)
            (mapcar #'car
                    cadr-cli::+tree-selector-keybinding-definitions+))
           :test #'string=)))
    (declare (ignore pin))
    (dolist
        (action
         '("app.clear" "app.clipboard.pasteImage" "app.editor.external"
           "app.exit" "app.interrupt" "app.message.copy"
           "app.message.dequeue" "app.message.followUp"
           "app.model.cycleBackward" "app.model.cycleForward"
           "app.model.select" "app.models.clearAll"
           "app.models.enableAll" "app.models.reorderDown"
           "app.models.reorderUp" "app.models.save"
           "app.models.toggleProvider" "app.session.delete"
           "app.session.deleteNoninvasive" "app.session.fork"
           "app.session.new" "app.session.rename" "app.session.resume"
           "app.session.toggleNamedFilter" "app.session.togglePath"
           "app.session.toggleSort" "app.session.tree"
           "app.thinking.cycle" "app.thinking.save"
           "app.thinking.toggle" "app.tools.expand"
           "app.tree.editLabel" "app.tree.filter.all"
           "app.tree.filter.cycleBackward" "app.tree.filter.cycleForward"
           "app.tree.filter.default" "app.tree.filter.labeledOnly"
           "app.tree.filter.noTools" "app.tree.filter.userOnly"
           "app.tree.foldOrUp" "app.tree.toggleLabelTimestamp"
           "app.tree.unfoldOrDown" "app.suspend"
           "tui.altScreen.bottom" "tui.altScreen.halfPageDown"
           "tui.altScreen.halfPageUp" "tui.altScreen.lineDown"
           "tui.altScreen.lineUp" "tui.altScreen.nextPrompt"
           "tui.altScreen.pageDown" "tui.altScreen.pageUp"
           "tui.altScreen.previousPrompt" "tui.altScreen.search"
           "tui.altScreen.searchClose" "tui.altScreen.searchNext"
           "tui.altScreen.searchPrevious" "tui.altScreen.top"
           "tui.editor.cursorDown" "tui.editor.cursorLeft"
           "tui.editor.cursorLineEnd" "tui.editor.cursorLineStart"
           "tui.editor.cursorRight" "tui.editor.cursorUp"
           "tui.editor.cursorWordLeft" "tui.editor.cursorWordRight"
           "tui.editor.deleteCharBackward" "tui.editor.deleteCharForward"
           "tui.editor.deleteToLineEnd" "tui.editor.deleteToLineStart"
           "tui.editor.deleteWordBackward" "tui.editor.deleteWordForward"
           "tui.editor.historyNext" "tui.editor.historyPrevious"
           "tui.editor.jumpBackward" "tui.editor.jumpForward"
           "tui.editor.pageDown" "tui.editor.pageUp"
           "tui.editor.undo" "tui.editor.yank" "tui.editor.yankPop"
           "tui.input.copy" "tui.input.newLine" "tui.input.submit"
           "tui.input.tab" "tui.select.cancel" "tui.select.confirm"
           "tui.select.down" "tui.select.pageDown" "tui.select.pageUp"
           "tui.select.up"))
      (is (find action names :test #'string=)))))

(test goal28-armin-component-reaches-existing-export
  (is (fboundp 'cadr-cli:make-armin-component))
  (is (fboundp 'cadr-cli:armin-component-tick))
  (let* ((ui
           (cadr-tui:make-tui-root
            :render-function
            (lambda (lines)
              (declare (ignore lines))
              nil)))
         (component
           (cadr-cli:make-armin-component
            ui
            :effect :scanline
            :start-p nil)))
    (is (typep component 'cadr-cli:armin-component))
    (cadr-cli:armin-component-tick component)
    (is (typep component 'cadr-cli:armin-component))))
