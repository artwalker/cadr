(in-package #:cadr-cli/tests)

(in-suite cadr-cli-suite)

(defun goal12-example-manifest ()
  (let ((path
          (merge-pathnames
           "examples/manifest.sexp"
           (asdf:system-source-directory "cadr-cli"))))
    (with-open-file (stream path :direction :input)
      (read stream))))

(defun goal12-source-parity-example-paths ()
  (let* ((path
           (merge-pathnames
            "docs/source-parity.md"
            (asdf:system-source-directory "cadr-cli")))
         (prefix "| `packages/coding-agent/examples/")
         (paths nil))
    (with-open-file (stream path :direction :input
                                 :external-format :utf-8)
      (loop for line = (read-line stream nil nil)
            while line
            when (uiop:string-prefix-p prefix line)
              do
              (let ((end (position #\` line :start (length prefix))))
                (is (not (null end)))
                (push (subseq line 3 end) paths))))
    (sort paths #'string<)))

(defun goal12-read-project-file (relative)
  (uiop:read-file-string
   (merge-pathnames
    relative
    (asdf:system-source-directory "cadr-cli"))))

(defun goal12-count-substring (needle haystack)
  (loop with start = 0
        for position = (search needle haystack :start2 start)
        while position
        count 1
        do (setf start (+ position (length needle)))))

(defun goal12-extension-bundle-registration-count (bundle)
  (+
   (length (cadr-agent::extension-bundle-tools bundle))
   (length (cadr-agent::extension-bundle-commands bundle))
   (length (cadr-agent::extension-bundle-hooks bundle))
   (length (cadr-agent::extension-bundle-templates bundle))
   (length (cadr-agent::extension-bundle-providers bundle))
   (length (cadr-agent::extension-bundle-native-providers bundle))
   (length (cadr-agent::extension-bundle-shortcuts bundle))
   (length (cadr-agent::extension-bundle-flags bundle))
   (length (cadr-agent::extension-bundle-message-renderers bundle))
   (if (cadr-agent::extension-bundle-markdown-transformer bundle) 1 0)
   (length (cadr-agent::extension-bundle-entry-renderers bundle))
   (length (cadr-agent::extension-bundle-tool-renderers bundle))))

(test goal12-example-manifest-covers-every-baseline-source-exactly-once
  (let* ((manifest (goal12-example-manifest))
         (baseline-paths
           (sort (mapcar (lambda (row) (getf row :baseline)) manifest)
                 #'string<))
         (ledger-paths (goal12-source-parity-example-paths)))
    (is (= 99 (length manifest)))
    (is (= 94 (count :ported manifest :key
                     (lambda (row) (getf row :status)))))
    (is (= 5 (count :gap manifest :key
                     (lambda (row) (getf row :status)))))
    (is (= 99 (length (remove-duplicates baseline-paths :test #'string=))))
    (is (equal ledger-paths baseline-paths))
    (dolist (row manifest)
      (is (member (getf row :status) '(:ported :gap)))
      (ecase (getf row :status)
        (:ported
         (let ((target (getf row :lisp)))
           (is (stringp target))
           (is (probe-file
                (merge-pathnames
                 target
                 (asdf:system-source-directory "cadr-cli"))))))
        (:gap
         (is (consp (getf row :gaps))))))))

(test goal12-source-parity-verdicts-follow-the-current-example-manifest
  (let ((ledger (goal12-read-project-file "docs/source-parity.md"))
        (readme (goal12-read-project-file "README.md"))
        (parity-map (goal12-read-project-file "docs/parity-map.md")))
    (is (search "| `coding-agent` | 289 | 257 | 27 | 5 |" ledger))
    (is (search "| **Total** | **595** | **516** | **72** | **7** |" ledger))
    (is (search "Ninety-four" readme))
    (is (search "94 functionally equivalent Lisp ports and 5 explicitly blocked rows"
                parity-map))
    (dolist (row (goal12-example-manifest))
      (let* ((baseline (getf row :baseline))
             (prefix (format nil "| `~A` |" baseline))
             (start (search prefix ledger))
             (end (and start (position #\Newline ledger :start start)))
             (line (and start (subseq ledger start end))))
        (is (stringp line))
        (ecase (getf row :status)
          (:ported
           (is (search "| `已实现` |" line))
           (is (search (format nil "`~A:" (getf row :lisp)) line)))
          (:gap
           (is (search "| `缺失` |" line))
           (is (search "goal-v12-api-scope-amendment-3.md" line))))))))

(test goal12-every-remaining-example-gap-is-covered-by-the-blocked-amendment
  (let* ((proposal
           (goal12-read-project-file
            "docs/proposals/goal-v12-example-api-gaps.md"))
         (amendment
           (goal12-read-project-file
            "docs/proposals/goal-v12-api-scope-amendment-2.md"))
         (mapping-start (search (format nil "~%## 4.") proposal))
         (mapping-end (and mapping-start
                           (search (format nil "~%## 5.")
                                   proposal :start2 mapping-start)))
         (mapping (and mapping-end
                       (subseq proposal mapping-start mapping-end)))
         (mapping-table-end
           (and mapping
                (search (format nil "~%~%机械校验") mapping)))
         (mapping-table
           (and mapping-table-end
                (subseq mapping 0 mapping-table-end)))
         (blocked
           (goal12-read-project-file
            "docs/proposals/goal-v12-api-scope-amendment-3.md"))
         (gap-ids nil))
    (dolist (row (goal12-example-manifest))
      (dolist (gap (getf row :gaps))
        (pushnew gap gap-ids)))
    (is (= 3 (length gap-ids)))
    (is (stringp mapping))
    (is (= 42 (goal12-count-substring "`:" mapping-table)))
    (is (search "19 项能力" proposal))
    (is (search "D/E 已于 2026-08-02 获得用户批准" amendment))
    (dolist (gap gap-ids)
      (is (search (format nil "`:~(~A~)`" gap) blocked)))
    (is (search "状态：**blocked" blocked))))

(test goal12-ported-extension-entrypoints-load-without-diagnostics
  (let ((root (asdf:system-source-directory "cadr-cli")))
    (dolist (row (goal12-example-manifest))
      (when (and (eq :ported (getf row :status))
                 (getf row :entry-p))
        (with-test-directory (temporary)
          (let* ((output (make-string-output-stream))
                 (target
                   (merge-pathnames (getf row :lisp) root))
                 (manager
                   (make-test-extension-manager
                    temporary
                    (merge-pathnames "global/" temporary)
                    output
                    (list target)))
                 (report
                   (cadr-cli::reload-cli-extensions manager))
                 (bundles
                   (cadr-agent::extension-snapshot-bundles
                    (cadr-agent::extension-host-current-snapshot
                     (cadr-cli::cli-extension-manager-host manager))))
                 (target-name (namestring (truename target)))
                 (bundle
                   (find target-name bundles
                         :key (lambda (candidate)
                                (let ((path
                                        (cadr-agent::extension-bundle-path
                                         candidate)))
                                  (namestring (or (probe-file path) path))))
                         :test #'string=)))
            (is (null (getf report :errors)))
            (is (plusp (getf report :loaded)))
            (is (not (null bundle)))
            (is (plusp
                 (goal12-extension-bundle-registration-count bundle)))
            (is (string= "" (get-output-stream-string output)))))))))

(defparameter *goal12-example-registrations*
  '(("packages/coding-agent/examples/extensions/auto-commit-on-exit.ts"
     :hooks (:session-shutdown))
    ("packages/coding-agent/examples/extensions/bash-spawn-hook.ts"
     :tools ("bash"))
    ("packages/coding-agent/examples/extensions/bookmark.ts"
     :commands ("bookmark" "unbookmark"))
    ("packages/coding-agent/examples/extensions/border-status-editor.ts"
     :hooks (:agent-start :agent-end :session-shutdown :session-start))
    ("packages/coding-agent/examples/extensions/built-in-tool-renderer.ts"
     :tools ("read" "bash" "edit" "write"))
    ("packages/coding-agent/examples/extensions/claude-rules.ts"
     :hooks (:session-start :before-agent-start))
    ("packages/coding-agent/examples/extensions/commands.ts"
     :commands ("commands"))
    ("packages/coding-agent/examples/extensions/confirm-destructive.ts"
     :hooks (:session-before-switch :session-before-fork))
    ("packages/coding-agent/examples/extensions/custom-footer.ts"
     :commands ("footer"))
    ("packages/coding-agent/examples/extensions/custom-header.ts"
     :commands ("builtin-header") :hooks (:session-start))
    ("packages/coding-agent/examples/extensions/dirty-repo-guard.ts"
     :hooks (:session-before-switch :session-before-fork))
    ("packages/coding-agent/examples/extensions/dynamic-resources/index.ts"
     :hooks (:resources-discover))
    ("packages/coding-agent/examples/extensions/dynamic-tools.ts"
     :commands ("add-echo-tool") :hooks (:session-start))
    ("packages/coding-agent/examples/extensions/doom-overlay/index.ts"
     :commands ("doom-overlay"))
    ("packages/coding-agent/examples/extensions/entry-renderer.ts"
     :commands ("status-card") :entry-renderers ("status-card"))
    ("packages/coding-agent/examples/extensions/event-bus.ts"
     :commands ("emit") :hooks (:session-start))
    ("packages/coding-agent/examples/extensions/file-trigger.ts"
     :hooks (:session-start))
    ("packages/coding-agent/examples/extensions/git-checkpoint.ts"
     :hooks (:tool-call-after :turn-start :session-before-fork :agent-end))
    ("packages/coding-agent/examples/extensions/git-merge-and-resolve.ts"
     :hooks (:agent-end))
    ("packages/coding-agent/examples/extensions/github-issue-autocomplete.ts"
     :hooks (:session-start))
    ("packages/coding-agent/examples/extensions/gondolin/index.ts"
     :commands ("gondolin")
     :tools ("read" "write" "edit" "bash" "ls" "find" "grep")
     :hooks (:session-start :session-shutdown :user-bash
             :before-agent-start))
    ("packages/coding-agent/examples/extensions/handoff.ts"
     :commands ("handoff"))
    ("packages/coding-agent/examples/extensions/hello.ts"
     :tools ("hello"))
    ("packages/coding-agent/examples/extensions/hidden-thinking-label.ts"
     :commands ("thinking-label") :hooks (:session-start))
    ("packages/coding-agent/examples/extensions/input-transform-streaming.ts"
     :hooks (:input))
    ("packages/coding-agent/examples/extensions/input-transform.ts"
     :hooks (:input))
    ("packages/coding-agent/examples/extensions/inline-bash.ts"
     :hooks (:input))
    ("packages/coding-agent/examples/extensions/interactive-shell.ts"
     :hooks (:user-bash))
    ("packages/coding-agent/examples/extensions/kimi-deferred-tools.ts"
     :tools ("Calculator" "tool_search") :hooks (:session-start))
    ("packages/coding-agent/examples/extensions/mac-system-theme.ts"
     :hooks (:session-start :session-shutdown))
    ("packages/coding-agent/examples/extensions/message-renderer.ts"
     :commands ("status") :message-renderers ("status-update"))
    ("packages/coding-agent/examples/extensions/minimal-mode.ts"
     :tools ("read" "bash" "write" "edit" "find" "grep" "ls"))
    ("packages/coding-agent/examples/extensions/model-status.ts"
     :hooks (:model-select))
    ("packages/coding-agent/examples/extensions/modal-editor.ts"
     :hooks (:session-start))
    ("packages/coding-agent/examples/extensions/notify.ts"
     :hooks (:agent-end))
    ("packages/coding-agent/examples/extensions/overlay-qa-tests.ts"
     :commands
     ("overlay-animation" "overlay-anchors" "overlay-margins"
      "overlay-stack" "overlay-overflow" "overlay-edge"
      "overlay-percent" "overlay-maxheight" "overlay-sidepanel"
      "overlay-toggle" "overlay-passive" "overlay-focus"
      "overlay-streaming"))
    ("packages/coding-agent/examples/extensions/overlay-test.ts"
     :commands ("overlay-test"))
    ("packages/coding-agent/examples/extensions/permission-gate.ts"
     :hooks (:tool-call-before))
    ("packages/coding-agent/examples/extensions/pirate.ts"
     :commands ("pirate") :hooks (:before-agent-start))
    ("packages/coding-agent/examples/extensions/plan-mode/index.ts"
     :commands ("plan" "todos")
     :hooks (:tool-call-before :context :before-agent-start
             :turn-end :agent-end :session-start)
     :flags ("plan") :shortcuts ("ctrl+alt+p"))
    ("packages/coding-agent/examples/extensions/preset.ts"
     :commands ("preset")
     :hooks (:before-agent-start :session-start :turn-start)
     :flags ("preset") :shortcuts ("ctrl+shift+u"))
    ("packages/coding-agent/examples/extensions/project-trust.ts"
     :hooks (:project-trust :session-start))
    ("packages/coding-agent/examples/extensions/protected-paths.ts"
     :hooks (:tool-call-before))
    ("packages/coding-agent/examples/extensions/provider-payload.ts"
     :hooks (:before-provider-request :after-provider-response))
    ("packages/coding-agent/examples/extensions/question.ts"
     :tools ("question"))
    ("packages/coding-agent/examples/extensions/questionnaire.ts"
     :tools ("questionnaire"))
    ("packages/coding-agent/examples/extensions/qna.ts"
     :commands ("qna"))
    ("packages/coding-agent/examples/extensions/rainbow-editor.ts"
     :hooks (:session-start))
    ("packages/coding-agent/examples/extensions/reload-runtime.ts"
     :commands ("reload-runtime") :tools ("reload_runtime"))
    ("packages/coding-agent/examples/extensions/rpc-demo.ts"
     :commands ("rpc-input" "rpc-editor" "rpc-prefill")
     :hooks (:session-start :turn-start :turn-end
             :tool-call-before :session-before-switch))
    ("packages/coding-agent/examples/extensions/sandbox/index.ts"
     :commands ("sandbox") :tools ("bash") :flags ("no-sandbox")
     :hooks (:user-bash :session-start :session-shutdown))
    ("packages/coding-agent/examples/extensions/send-user-message.ts"
     :commands ("ask" "steer" "followup" "askwith"))
    ("packages/coding-agent/examples/extensions/session-name.ts"
     :commands ("session-name"))
    ("packages/coding-agent/examples/extensions/shutdown-command.ts"
     :commands ("quit") :tools ("finish_and_exit" "deploy_and_exit"))
    ("packages/coding-agent/examples/extensions/snake.ts"
     :commands ("snake"))
    ("packages/coding-agent/examples/extensions/space-invaders.ts"
     :commands ("invaders"))
    ("packages/coding-agent/examples/extensions/ssh.ts"
     :tools ("read" "write" "edit" "bash") :flags ("ssh")
     :hooks (:session-start :user-bash :before-agent-start))
    ("packages/coding-agent/examples/extensions/subagent/index.ts"
     :tools ("subagent"))
    ("packages/coding-agent/examples/extensions/summarize.ts"
     :commands ("summarize"))
    ("packages/coding-agent/examples/extensions/system-prompt-header.ts"
     :hooks (:agent-start :session-shutdown))
    ("packages/coding-agent/examples/extensions/tic-tac-toe.ts"
     :commands ("tic-tac-toe")
     :tools ("tic_tac_toe" "tic_tac_toe_see_board")
     :hooks (:session-start :session-tree :before-agent-start)
     :message-renderers
     ("tic-tac-toe-move" "tic-tac-toe-game-over"))
    ("packages/coding-agent/examples/extensions/timed-confirm.ts"
     :commands ("timed" "timed-select" "timed-signal"))
    ("packages/coding-agent/examples/extensions/titlebar-spinner.ts"
     :hooks (:agent-start :agent-end :session-shutdown))
    ("packages/coding-agent/examples/extensions/todo.ts"
     :commands ("todos") :tools ("todo")
     :hooks (:session-start :session-tree))
    ("packages/coding-agent/examples/extensions/tool-override.ts"
     :commands ("read-log") :tools ("read"))
    ("packages/coding-agent/examples/extensions/tools.ts"
     :commands ("tools") :hooks (:session-start :session-tree))
    ("packages/coding-agent/examples/extensions/trigger-compact.ts"
     :commands ("trigger-compact") :hooks (:turn-end))
    ("packages/coding-agent/examples/extensions/truncated-tool.ts"
     :tools ("rg"))
    ("packages/coding-agent/examples/extensions/status-line.ts"
     :hooks (:session-start :turn-start :turn-end))
    ("packages/coding-agent/examples/extensions/structured-output.ts"
     :tools ("structured_output"))
    ("packages/coding-agent/examples/extensions/with-deps/index.ts"
     :tools ("parse_duration"))
    ("packages/coding-agent/examples/extensions/widget-placement.ts"
     :hooks (:session-start))
    ("packages/coding-agent/examples/extensions/working-indicator.ts"
     :commands ("working-indicator") :hooks (:session-start))
    ("packages/coding-agent/examples/extensions/working-message-test.ts"
     :hooks (:session-start))))

(test goal12-ported-extension-registrations-cover-the-baseline-surface
  (let ((root (asdf:system-source-directory "cadr-cli")))
    (dolist (expected *goal12-example-registrations*)
      (let* ((row
               (find (first expected) (goal12-example-manifest)
                     :key (lambda (candidate) (getf candidate :baseline))
                     :test #'string=))
             (output (make-string-output-stream)))
        (with-test-directory (temporary)
          (let* ((manager
                   (make-test-extension-manager
                    temporary (merge-pathnames "global/" temporary)
                    output
                    (list (merge-pathnames (getf row :lisp) root))))
                 (report (cadr-cli::reload-cli-extensions manager))
                 (snapshot
                   (cadr-agent::extension-host-snapshot
                    (cadr-cli::cli-extension-manager-host manager))))
            (is (null (getf report :errors)))
            (dolist (command (getf (rest expected) :commands))
              (is
               (find command
                     (cadr-agent::extension-snapshot-commands snapshot)
                     :key #'cadr-agent::extension-command-definition-name
                     :test #'string=)
               "~A must register command ~A" (first expected) command))
            (dolist (hook (getf (rest expected) :hooks))
              (is (gethash hook
                           (cadr-agent::extension-snapshot-hooks snapshot))
                  "~A must register hook ~A" (first expected) hook))
            (dolist (tool (getf (rest expected) :tools))
              (is
               (find tool
                     (cadr-agent::extension-snapshot-tools snapshot)
                     :key #'cadr-agent::extension-tool-definition-name
                     :test #'string=)
               "~A must register tool ~A" (first expected) tool))
            (dolist (flag (getf (rest expected) :flags))
              (is
               (find flag
                     (cadr-agent::extension-snapshot-flags snapshot)
                     :key #'cadr-agent::extension-flag-definition-name
                     :test #'string=)
               "~A must register flag ~A" (first expected) flag))
            (dolist (shortcut (getf (rest expected) :shortcuts))
              (is
               (find shortcut
                     (cadr-agent::extension-snapshot-shortcuts snapshot)
                     :key #'cadr-agent::extension-shortcut-definition-key
                     :test #'string=)
               "~A must register shortcut ~A" (first expected) shortcut))
            (dolist (provider (getf (rest expected) :native-providers))
              (is
               (find provider
                     (cadr-agent::extension-snapshot-native-providers snapshot)
                     :key
                     (lambda (definition)
                       (cadr-ai:runtime-provider-id
                        (cadr-agent::extension-native-provider-definition-provider
                         definition)))
                     :test #'eq)
               "~A must register native provider ~A"
               (first expected) provider))
            (dolist (custom-type (getf (rest expected) :message-renderers))
              (is
               (find custom-type
                     (cadr-agent::extension-snapshot-message-renderers snapshot)
                     :key #'cadr-agent::extension-renderer-definition-custom-type
                     :test #'string=)
               "~A must register message renderer ~A"
               (first expected) custom-type))
            (dolist (custom-type (getf (rest expected) :entry-renderers))
              (is
               (find custom-type
                     (cadr-agent::extension-snapshot-entry-renderers snapshot)
                     :key #'cadr-agent::extension-renderer-definition-custom-type
                     :test #'string=)
               "~A must register entry renderer ~A"
               (first expected) custom-type))))))))

(defun goal12-load-pure-example (relative)
  (load
   (merge-pathnames relative
                    (asdf:system-source-directory "cadr-cli"))))

(test goal12-pure-example-ports-preserve-edge-case-behavior
  (goal12-load-pure-example "examples/extensions/doom-overlay/doom-keys.lisp")
  (goal12-load-pure-example "examples/extensions/doom-overlay/wad-finder.lisp")
  (goal12-load-pure-example "examples/extensions/plan-mode/utils.lisp")
  (goal12-load-pure-example "examples/extensions/subagent/agents.lisp")
  (let ((map-key (symbol-function 'map-key-to-doom)))
    (is (equal '(173) (funcall map-key (format nil "~C[A" #\Escape))))
    (is (equal '(173 182) (funcall map-key "W")))
    (is (equal '(163) (funcall map-key "F")))
    (is (equal '(121) (funcall map-key "Y")))
    (is (equal '(49) (funcall map-key "1")))
    (is (null (funcall map-key (string (code-char 3))))))
  (is (string=
       "https://distro.ibiblio.org/slitaz/sources/packages/d/doom1.wad"
       (symbol-value '+doom-wad-url+)))
  (is (= (+ #x80 #x58) (symbol-value '+doom-key-f12+)))
  (is (funcall (symbol-function 'plan-mode-safe-command-p)
               "git status"))
  (is (not (funcall (symbol-function 'plan-mode-safe-command-p)
                    "git reset --hard")))
  (let* ((extract
           (symbol-function 'plan-mode-extract-todo-items))
         (items
           (funcall extract
                    (format nil
                            "Plan:~%1. **Use the `read` tool**~%2) Verify tests pass~%3. /skip this"))))
    (is (= 2 (length items)))
    (is (string= "Read tool"
                 (funcall (symbol-function 'plan-mode-todo-item-text)
                          (first items))))
    (is (= 2
           (funcall (symbol-function 'plan-mode-mark-completed-steps)
                    "[DONE:2] [DONE:99]" items)))
    (is
     (funcall (symbol-function 'plan-mode-todo-item-completed-p)
              (second items))))
  (with-test-directory (directory)
    (let ((wad (merge-pathnames "custom.wad" directory)))
      (write-text wad "IWADpayload")
      (is (string=
           (namestring (truename wad))
           (funcall (symbol-function 'find-wad-file) (namestring wad))))))
  (with-test-directory (directory)
    (let* ((wad (merge-pathnames "downloaded.wad" directory))
           (payload
             (make-array 5 :element-type '(unsigned-byte 8)
                           :initial-contents '(0 1 2 3 255)))
           (original-download
             (symbol-function 'doom-download-wad-octets)))
      (unwind-protect
          (progv (list '+doom-bundled-wad-path+) (list wad)
            (setf (symbol-function 'doom-download-wad-octets)
                  (lambda () payload))
            (is (string= (namestring wad)
                         (funcall (symbol-function 'ensure-wad-file))))
            (with-open-file
                (stream wad :direction :input
                            :element-type '(unsigned-byte 8))
              (let ((actual
                      (make-array (file-length stream)
                                  :element-type '(unsigned-byte 8))))
                (read-sequence actual stream)
                (is (equalp payload actual)))))
        (setf (symbol-function 'doom-download-wad-octets)
              original-download))))
  (with-test-directory (directory)
    (let* ((agents-directory (merge-pathnames ".cadr/agents/" directory))
           (nested (merge-pathnames "src/deep/" directory)))
      (ensure-directories-exist (merge-pathnames "anchor" nested))
      (write-text
       (merge-pathnames "reviewer.md" agents-directory)
       (format nil
               "---~%name: 'reviewer'~%description: \"Review changes\"~%tools: read, grep~%model: test-model~%---~%Be strict.~%"))
      (let* ((result
               (funcall (symbol-function 'discover-subagents)
                        nested :project))
             (agent (first (getf result :agents))))
        (is (= 1 (length (getf result :agents))))
        (is (string= "reviewer" (getf agent :name)))
        (is (equal '("read" "grep") (getf agent :tools)))
        (is (string= (format nil "Be strict.~%")
                     (getf agent :system-prompt)))))))
