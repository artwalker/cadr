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
  (let ((source (goal20-example-source "examples/extensions/tic-tac-toe.lisp")))
    (is (search "32;1m" source))
    (is (search "TIC-TAC-TOE-RENDER-VISUAL-BOARD" source :test #'char-equal))
    (is (search "(tic-tac-toe-reconstruct context)" source))
    (is (search "nil)" source))))

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
  (let ((source (goal20-example-source "examples/extensions/hidden-thinking-label.lisp")))
    (is (search "Pondering..." source))
    (is (search "Hidden thinking label set to:" source))
    (is (search "nil))" source))))

(test goal20-message-renderer-uses-level-prefix
  (let ((source (goal20-example-source "examples/extensions/message-renderer.lisp")))
    (is (search "[~:@(~A~)]" source))
    (is (search "status-update" source))))

(test goal20-entry-renderer-status-prefix
  (let ((source (goal20-example-source "examples/extensions/entry-renderer.lisp")))
    (is (search "[status]" source))
    (is (search "append-entry" source))))

(test goal20-dynamic-tools-session-start-returns-nil
  (let ((source (goal20-example-source "examples/extensions/dynamic-tools.lisp")))
    (is (search "Registered dynamic tool: echo_session" source))
    (is (search "nil))" source))))

(test goal20-todo-empty-state-and-add-text
  (let ((source (goal20-example-source "examples/extensions/todo.lisp")))
    (is (search "No todos yet. Ask the agent to add some!" source))
    (is (search "Added todo #" source))))

(test goal20-qna-empty-assistant
  (let ((source (goal20-example-source "examples/extensions/qna.lisp")))
    (is (search "No assistant messages found" source))))
