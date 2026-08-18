(in-package #:cadr-cli/tests)

(in-suite cadr-cli-suite)

(defun goal20-example-source (relative)
  (goal12-read-project-file relative))

(test goal20-example-session-branch-walks-path-entries
  (let ((source (goal20-example-source "examples/extensions/support.lisp")))
    (is (search "session-path-entries" source))
    (is (null (search "(cadr-agent:session-branch" source)))))

(test goal20-snake-source-has-baseline-sgr
  ;; Goal 20 P0: the single snake-ansi helper appended its own "m" to codes
  ;; that already carried one, painting a literal m before every colored
  ;; string. The port now mirrors snake.ts:220-224 - separate dim/bold
  ;; helpers closing with ESC[22m and a color helper taking the bare code.
  (let ((source (goal20-example-source "examples/extensions/snake.lisp")))
    (is (search "(snake-color \"32\"" source))
    (is (search "(snake-color \"31\"" source))
    (is (search "~C[2m~A~C[22m" source))
    (is (search "~C[1m~A~C[22m" source))
    ;; The defect shape: an m-suffixed code handed to a helper that appends
    ;; its own m. Neither the old helper nor any m-suffixed code literal may
    ;; come back.
    (is (null (search "snake-ansi" source)))
    (is (null (search "\"32m\"" source)))
    (is (null (search "\"31m\"" source)))
    (is (null (search "\"1;32m\"" source)))
    (is (search "example-render-diff-harness-p" source))))

(test goal20-tic-tac-toe-source-has-cursor-highlight
  ;; Goal 20 P0-3 removed the always-true "nil)" assertion this test used
  ;; to carry; the remaining greps are the defect-shape locks, and the
  ;; behavior tier lives in
  ;; goal20-ttt-agent-action-repaints-the-live-overlay below.
  (let ((source (goal20-example-source "examples/extensions/tic-tac-toe.lisp")))
    (is (search "32;1m" source))
    (is (search "TIC-TAC-TOE-RENDER-VISUAL-BOARD" source :test #'char-equal))
    (is (search "(tic-tac-toe-reconstruct context)" source))
    (is (search "(arguments theme context)" source))
    (is (search "There is no batched form" source))
    (is (search ":tool-title" source))
    (is (search "---------+---------+---------" source))
    (is (search "<[~D,~D]>" source))
    (is (null (search "-----+-----+-----" source)))))

(test goal20-snake-behavior-render-reflects-state
  ;; Goal 20 P0-3 behavior tier: construct the component, advance the game
  ;; state, and assert the drawn frame changes - not the source text.
  (let ((root (asdf:system-source-directory "cadr-cli")))
    (with-test-directory (temporary)
      (let* ((output (make-string-output-stream))
             (target (merge-pathnames "examples/extensions/snake.lisp" root))
             (manager
               (make-test-extension-manager
                temporary (merge-pathnames "global/" temporary)
                output (list target)))
             (report (cadr-cli::reload-cli-extensions manager)))
        (is (null (getf report :errors)))
        (let* ((bundles
                 (cadr-agent::extension-snapshot-bundles
                  (cadr-agent::extension-host-current-snapshot
                   (cadr-cli::cli-extension-manager-host manager))))
               (bundle
                 (find-if
                  (lambda (candidate)
                    (find "snake"
                          (cadr-agent::extension-bundle-commands candidate)
                          :key #'cadr-agent::extension-command-definition-name
                          :test #'string=))
                  bundles))
               (package (cadr-agent::extension-bundle-package bundle))
               (state
                 (funcall
                  (find-symbol "MAKE-INITIAL-SNAKE-STATE" package)))
               (renders 0)
               (tui
                 (cadr-tui:make-tui-root
                  :render-function
                  (lambda (lines)
                    (declare (ignore lines))
                    (incf renders))))
               (component
                 (make-instance
                  (find-symbol "SNAKE-COMPONENT" package)
                  :state state
                  :tui tui
                  :done (lambda (value) value)
                  :save (lambda (value) value)
                  :paused-p t))
               (before (cadr-tui:component-render component 100)))
          (is (find-if (lambda (line) (search "SNAKE" line)) before))
          (is (find-if (lambda (line) (search "██" line)) before))
          (funcall (find-symbol "SNAKE-COMPONENT-ADVANCE" package)
                   component)
          (is (plusp renders)
              "timer tick did not request a repaint")
          (let ((after (cadr-tui:component-render component 100)))
            (is (not (equal before after))
                "a game tick did not reach the rendered frame")))))))

(test goal20-invaders-behavior-render-reflects-state
  ;; Goal 20 P0-3 behavior tier for space invaders.
  (let ((root (asdf:system-source-directory "cadr-cli")))
    (with-test-directory (temporary)
      (let* ((output (make-string-output-stream))
             (target
               (merge-pathnames "examples/extensions/space-invaders.lisp" root))
             (manager
               (make-test-extension-manager
                temporary (merge-pathnames "global/" temporary)
                output (list target)))
             (report (cadr-cli::reload-cli-extensions manager)))
        (is (null (getf report :errors)))
        (let* ((bundles
                 (cadr-agent::extension-snapshot-bundles
                  (cadr-agent::extension-host-current-snapshot
                   (cadr-cli::cli-extension-manager-host manager))))
               (bundle
                 (find-if
                  (lambda (candidate)
                    (find "invaders"
                          (cadr-agent::extension-bundle-commands candidate)
                          :key #'cadr-agent::extension-command-definition-name
                          :test #'string=))
                  bundles))
               (package (cadr-agent::extension-bundle-package bundle))
               (state
                 (funcall
                  (find-symbol "MAKE-INITIAL-INVADERS-STATE" package)))
               (renders 0)
               (tui
                 (cadr-tui:make-tui-root
                  :render-function
                  (lambda (lines)
                    (declare (ignore lines))
                    (incf renders))))
               (component
                 (make-instance
                  (find-symbol "SPACE-INVADERS-COMPONENT" package)
                  :state state
                  :tui tui
                  :done (lambda (value) value)
                  :save (lambda (value) value)
                  :paused-p t))
               (frame (cadr-tui:component-render component 100)))
          (is (find-if (lambda (line) (search "SPACE INVADERS" line)) frame))
          (is (find-if (lambda (line) (search "Score" line)) frame))
          (funcall (find-symbol "SPACE-INVADERS-ADVANCE" package)
                   component)
          (is (plusp renders)
              "timer tick did not request a repaint"))))))

(test goal20-snake-overlay-reads-live-global
  ;; P.8: after reconstruct/restart the overlay must paint *snake-state*,
  ;; not a slot captured when the component was built.
  (let ((root (asdf:system-source-directory "cadr-cli")))
    (with-test-directory (temporary)
      (let* ((output (make-string-output-stream))
             (target (merge-pathnames "examples/extensions/snake.lisp" root))
             (manager
               (make-test-extension-manager
                temporary (merge-pathnames "global/" temporary)
                output (list target)))
             (report (cadr-cli::reload-cli-extensions manager)))
        (is (null (getf report :errors)))
        (let* ((bundles
                 (cadr-agent::extension-snapshot-bundles
                  (cadr-agent::extension-host-current-snapshot
                   (cadr-cli::cli-extension-manager-host manager))))
               (bundle
                 (find-if
                  (lambda (candidate)
                    (find "snake"
                          (cadr-agent::extension-bundle-commands candidate)
                          :key #'cadr-agent::extension-command-definition-name
                          :test #'string=))
                  bundles))
               (package (cadr-agent::extension-bundle-package bundle))
               (slot-state
                 (funcall (find-symbol "MAKE-INITIAL-SNAKE-STATE" package)))
               (live-state
                 (funcall (find-symbol "MAKE-INITIAL-SNAKE-STATE" package)))
               (tui (cadr-tui:make-tui-root
                     :render-function (lambda (lines)
                                        (declare (ignore lines)))))
               (component
                 (make-instance
                  (find-symbol "SNAKE-COMPONENT" package)
                  :state slot-state
                  :tui tui
                  :done (lambda (value) value)
                  :save (lambda (value) value)
                  :paused-p t)))
          (funcall
           (fdefinition
            (list 'setf (find-symbol "SNAKE-STATE-SCORE" package)))
           999 live-state)
          (setf (symbol-value (find-symbol "*SNAKE-STATE*" package))
                live-state)
          (let ((lines (cadr-tui:component-render component 100)))
            (is (find-if (lambda (line) (search "999" line)) lines)
                "overlay did not read *snake-state*")))))))

(test goal20-invaders-overlay-reads-live-global
  (let ((root (asdf:system-source-directory "cadr-cli")))
    (with-test-directory (temporary)
      (let* ((output (make-string-output-stream))
             (target
               (merge-pathnames "examples/extensions/space-invaders.lisp" root))
             (manager
               (make-test-extension-manager
                temporary (merge-pathnames "global/" temporary)
                output (list target)))
             (report (cadr-cli::reload-cli-extensions manager)))
        (is (null (getf report :errors)))
        (let* ((bundles
                 (cadr-agent::extension-snapshot-bundles
                  (cadr-agent::extension-host-current-snapshot
                   (cadr-cli::cli-extension-manager-host manager))))
               (bundle
                 (find-if
                  (lambda (candidate)
                    (find "invaders"
                          (cadr-agent::extension-bundle-commands candidate)
                          :key #'cadr-agent::extension-command-definition-name
                          :test #'string=))
                  bundles))
               (package (cadr-agent::extension-bundle-package bundle))
               (slot-state
                 (funcall
                  (find-symbol "MAKE-INITIAL-INVADERS-STATE" package)))
               (live-state
                 (funcall
                  (find-symbol "MAKE-INITIAL-INVADERS-STATE" package)))
               (tui (cadr-tui:make-tui-root
                     :render-function (lambda (lines)
                                        (declare (ignore lines)))))
               (component
                 (make-instance
                  (find-symbol "SPACE-INVADERS-COMPONENT" package)
                  :state slot-state
                  :tui tui
                  :done (lambda (value) value)
                  :save (lambda (value) value)
                  :paused-p t)))
          (funcall
           (fdefinition
            (list 'setf (find-symbol "INVADERS-STATE-SCORE" package)))
           777 live-state)
          (setf (symbol-value
                 (find-symbol "*SPACE-INVADERS-STATE*" package))
                live-state)
          (let ((lines (cadr-tui:component-render component 100)))
            (is (find-if (lambda (line) (search "777" line)) lines)
                "overlay did not read *space-invaders-state*")))))))

(test goal20-ttt-agent-action-repaints-the-live-overlay
  ;; Goal 20 P0-2 behavior lock (baseline updateState,
  ;; tic-tac-toe.ts:389-393): the overlay component must carry the tui
  ;; handle, and the agent's tool path - which mutates the shared state on
  ;; an execution path the input loop never repaints - must request a
  ;; render. Construct -> mutate through the registered tool -> assert the
  ;; repaint and the rendered frame, not the source text.
  (let ((root (asdf:system-source-directory "cadr-cli")))
    (with-test-directory (temporary)
      (let* ((output (make-string-output-stream))
             (target
               (merge-pathnames "examples/extensions/tic-tac-toe.lisp" root))
               (manager
               (make-test-extension-manager
                temporary (merge-pathnames "global/" temporary)
                output (list target)))
             (report (cadr-cli::reload-cli-extensions manager)))
        (is (null (getf report :errors)))
        ;; The game's save path calls a host action; the bare test host has
        ;; none. Stub the dispatcher so the test isolates the repaint path.
        (setf (cadr-agent::extension-host-action-function
               (cadr-cli::cli-extension-manager-host manager))
              (lambda (action arguments)
                (declare (ignore action arguments))
                nil))
        (let* ((bundles
                 (cadr-agent::extension-snapshot-bundles
                  (cadr-agent::extension-host-current-snapshot
                   (cadr-cli::cli-extension-manager-host manager))))
               (bundle
                 (find-if
                  (lambda (candidate)
                    (find "tic_tac_toe"
                          (cadr-agent::extension-bundle-tools candidate)
                          :key #'cadr-agent::extension-tool-definition-name
                          :test #'string=))
                  bundles))
               (package (cadr-agent::extension-bundle-package bundle))
               (renders 0)
               (tui
                 (cadr-tui:make-tui-root
                  :render-function
                  (lambda (lines)
                    (declare (ignore lines))
                    (incf renders)))))
          (is (not (null bundle)))
          (let* ((component-class
                   (find-symbol "TIC-TAC-TOE-BOARD-COMPONENT" package))
                 (component-var
                   (find-symbol "*TIC-TAC-TOE-COMPONENT*" package))
                 (state-var (find-symbol "*TIC-TAC-TOE-STATE*" package))
                 (tool
                   (find "tic_tac_toe"
                         (cadr-agent::extension-bundle-tools bundle)
                         :key #'cadr-agent::extension-tool-definition-name
                         :test #'string=))
                 (arguments (make-hash-table :test #'equal)))
            ;; The class must expose the tui slot the factory wires.
            (is (not (null (find-symbol "TIC-TAC-TOE-COMPONENT-TUI" package))))
            (setf (symbol-value component-var)
                  (make-instance component-class
                                 :state (symbol-value state-var)
                                 :tui tui))
            ;; A fresh board is the user's turn; hand the turn to the agent
            ;; the way a user move does before driving the agent tool.
            (funcall
             (fdefinition
              (list 'setf
                    (find-symbol "TIC-TAC-TOE-STATE-CURRENT-TURN" package)))
             #\O (symbol-value state-var))
            (setf (gethash "action" arguments) "play")
            (funcall (cadr-agent::extension-tool-definition-handler tool)
                     "goal20-p0-2-call" arguments nil nil nil)
            (is (plusp renders)
                "agent tool action did not request a repaint")
            ;; Behavior tier for the render itself: the mutated state must
            ;; reach the drawn frame (banner plus an O mark somewhere).
            (let ((lines
                    (cadr-tui:component-render
                     (symbol-value component-var) 60)))
              (is (find-if (lambda (line) (search "Tic-Tac-Toe" line)) lines))
              (is (find-if (lambda (line)
                             (search (string #\LARGE_CIRCLE) line))
                           lines)))))))))

(test goal20-hello-matches-baseline-contract
  (let ((source (goal20-example-source "examples/extensions/hello.lisp")))
    (is (search "A simple greeting tool" source))
    (is (search ":greeted" source))
    (is (search "example-text-result" source))))

(test goal20-event-bus-notifies-payload
  (let ((source (goal20-example-source "examples/extensions/event-bus.lisp")))
    (is (search "event-bus-example" source))
    (is (search "Event from ~A: ~A" source))
    (is (null (search "declare (ignore payload)" source)))))

(test goal20-commands-uses-select-not-dialog
  (let ((source (goal20-example-source "examples/extensions/commands.lisp")))
    (is (search "Available Commands" source))
    (is (search "extension-context-select" source))
    (is (search "View source path?" source))
    (is (null (search "example-show-dialog" source)))))

(test goal20-custom-header-has-mascot-subtitle
  (let ((source (goal20-example-source "examples/extensions/custom-header.lisp")))
    (is (search "shitty coding agent" source))
    (is (search "read-baseline-anchor" source))))

(test goal20-overlay-test-is-not-generic-dialog
  (let ((source (goal20-example-source "examples/extensions/overlay-test.lisp")))
    (is (search "Overlay Test" source))
    (is (search "example-overlay-test-component" source))
    (is (null (search "example-dialog-component" source)))))

(test goal20-send-user-message-ask-usage
  (let ((source (goal20-example-source "examples/extensions/send-user-message.lisp")))
    (is (search "Usage: /~(~A~) <message>" source))
    (is (search "extension-api-send-user-message" source))))

(test goal20-trigger-compact-notify
  (let ((source (goal20-example-source "examples/extensions/trigger-compact.lisp")))
    (is (search "Compaction started" source))
    (is (search "Trigger compaction immediately" source))))

(test goal20-reload-runtime-queues-follow-up
  (let ((source (goal20-example-source "examples/extensions/reload-runtime.lisp")))
    (is (search "Queued /reload-runtime as a follow-up command." source))))

(test goal20-thinking-label-matches-baseline
  ;; Goal 20 P0-3: the "nil))" grep this test carried was always true for
  ;; any Lisp source and asserted nothing; removed.
  (let ((source (goal20-example-source "examples/extensions/hidden-thinking-label.lisp")))
    (is (search "Pondering..." source))
    (is (search "Hidden thinking label set to:" source))))

(test goal20-message-renderer-uses-level-prefix
  (let ((source (goal20-example-source "examples/extensions/message-renderer.lisp")))
    (is (search "[~:@(~A~)]" source))
    (is (search "status-update" source))))

(test goal20-entry-renderer-status-prefix
  (let ((source (goal20-example-source "examples/extensions/entry-renderer.lisp")))
    (is (search "[status]" source))
    (is (search "append-entry" source))))

(test goal20-dynamic-tools-session-start-returns-nil
  ;; Goal 20 P0-3: the "nil))" grep this test carried was always true for
  ;; any Lisp source and asserted nothing; removed. The returns-nil
  ;; behavior itself is exercised by the goal12 registration suite, which
  ;; runs the session-start hook when it loads the entry.
  (let ((source (goal20-example-source "examples/extensions/dynamic-tools.lisp")))
    (is (search "Registered dynamic tool: echo_session" source))))

(test goal20-todo-empty-state-and-add-text
  (let ((source (goal20-example-source "examples/extensions/todo.lisp")))
    (is (search "No todos yet. Ask the agent to add some!" source))
    (is (search "Added todo #" source))))

(test goal20-qna-empty-assistant
  (let ((source (goal20-example-source "examples/extensions/qna.lisp")))
    (is (search "No assistant messages found" source))))

(test goal20-p0-4-ttt-move-renderer-paints-compact-banner
  ;; Goal 20 P0-4: the move customType is registered, but a missing
  ;; renderer falls back to the LLM content (full ASCII board). The
  ;; baseline paints BannerMessageComponent (tic-tac-toe.ts:685-692).
  (let ((root (asdf:system-source-directory "cadr-cli")))
    (with-test-directory (temporary)
      (let* ((output (make-string-output-stream))
             (target
               (merge-pathnames "examples/extensions/tic-tac-toe.lisp" root))
             (manager
               (make-test-extension-manager
                temporary (merge-pathnames "global/" temporary)
                output (list target)))
             (report (cadr-cli::reload-cli-extensions manager)))
        (is (null (getf report :errors)))
        (let* ((host (cadr-cli::cli-extension-manager-host manager))
               (entry
                 (cadr-cli::make-tui-entry
                  :type :custom-message
                  :custom-type "tic-tac-toe-move"
                  :custom-payload
                  (list :custom-type "tic-tac-toe-move"
                        :content
                        "Player X played at (row=0, col=1). It is now Player O's turn."
                        :details (list :current-turn "O")
                        :display-p t)
                  :custom-options '(:expanded-p nil :output-pad 1))))
          (is (not
               (null
                (cadr-agent::find-extension-message-renderer
                 host "tic-tac-toe-move"))))
          (let ((screen
                  (format
                   nil "~{~A~^~%~}"
                   (cadr-cli::render-tui-entry
                    entry 80 :extension-host host))))
            (is (search "Player X played" screen))
            (is (search "next:" screen))
            (is (null (search "played at (row=" screen)))
            (is (null (search "marked with" screen)))
            (is (null (search "-----+-----" screen))))
          (setf (cadr-cli::tui-entry-custom-options entry)
                '(:expanded-p t :output-pad 1)
                (cadr-cli::tui-entry-custom-component entry) nil)
          (let ((screen
                  (format
                   nil "~{~A~^~%~}"
                   (cadr-cli::render-tui-entry
                    entry 80 :extension-host host))))
            (is (search "Player X played" screen))
            (is (search (string #\BOX_DRAWINGS_LIGHT_HORIZONTAL) screen))
            (is (null (search "played at (row=" screen)))
            (is (null (search "marked with" screen)))
            (is (null (search "-----+-----" screen)))))))))

(test goal20-p0-4-trigger-turn-does-not-block-tui-input-thread
  ;; Gate-validity: without the wrap, a 0.3s send-message would hold the
  ;; caller (the TUI input loop) and freeze flush-render. With the wrap
  ;; the caller returns before the turn finishes.
  (let* ((finished-p nil)
         (host (cadr-agent::make-extension-host :mode :tui))
         (worker nil))
    (setf (cadr-agent::extension-host-send-message-function host)
          (lambda (message &key trigger-turn-p deliver-as)
            (declare (ignore deliver-as))
            (when trigger-turn-p
              (sleep 0.25)
              (setf finished-p t))
            message))
    (cadr-cli::wrap-extension-host-tui-turn-dispatch
     host
     (lambda (thunk)
       (setf worker
             (sb-thread:make-thread
              thunk :name "goal20-p0-4-dispatch"))))
    (let ((cadr-cli::*tui-input-thread* sb-thread:*current-thread*)
          (start (get-internal-real-time)))
      (funcall
       (cadr-agent::extension-host-send-message-function host)
       '(:custom-type "x" :content "y" :display-p t)
       :trigger-turn-p t)
      (is (< (/ (- (get-internal-real-time) start)
                internal-time-units-per-second)
             0.1d0)
          "trigger-turn blocked the TUI input thread")
      (is (null finished-p)))
    (when worker
      (sb-thread:join-thread worker))
    (is (not (null finished-p)))))
