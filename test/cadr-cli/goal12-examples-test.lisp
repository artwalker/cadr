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
    (is (= 99 (count :ported manifest :key
                     (lambda (row) (getf row :status)))))
    (is (= 0 (count :gap manifest :key
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

(test goal12-all-34-extension-events-have-production-dispatch-evidence
  (let* ((audit
           (goal12-read-project-file
            "docs/acceptance/goal-v12-extension-event-dispatch.md"))
         (events cadr-agent::+extension-hook-events+))
    (is (= 34 (length events)))
    (dolist (event events)
      (let* ((prefix (format nil "| `:~(~A~)` |" (symbol-name event)))
             (start (search prefix audit))
             (end (and start (position #\Newline audit :start start)))
             (row (and start (subseq audit start end)))
             (test-start (and row (search "test/" row)))
             (test-end
               (and test-start
                    (position #\: row :start test-start)))
             (test-path
               (and test-end (subseq row test-start test-end))))
        (is (stringp row) "Missing dispatch audit row for ~A" event)
        (when row
          (is (= 1 (goal12-count-substring prefix audit)))
          (is (search "src/cadr-" row))
          (is (search "test/cadr-" row))
          (is (and test-path
                   (probe-file
                    (merge-pathnames
                     test-path
                     (asdf:system-source-directory "cadr-cli"))))))))
    (is (search "declared-but-disconnected" audit))
    (is (search ":session-before-compact" audit))))

(test goal18-extension-event-set-matches-the-derived-baseline
  ;; Goal 18 I2: the baseline ExtensionEvent union is expanded
  ;; mechanically from types.ts into baseline-interface-inventory.json
  ;; (git-verified at gate time); cadr's set must equal it modulo the
  ;; adjudicated tool_call/tool_result three-phase split.
  (let* ((inventory
          (cadr-ai::parse-json
           (goal12-read-project-file
            "test/fixtures/render-diff/baseline-interface-inventory.json")))
         (baseline
          (coerce
           (cadr-ai::json-get inventory "extensionEvents")
           'list))
         (expected
          (sort
           (append
            (remove-if
             (lambda (name)
               (member name '("tool-call" "tool-result") :test #'string=))
             (mapcar
              (lambda (name)
                (substitute #\- #\_ name))
              baseline))
            '("tool-call-before" "tool-call-after" "tool-call-error"))
           #'string<))
         (actual
          (sort
           (mapcar
            (lambda (event)
              (string-downcase (symbol-name event)))
            cadr-agent::+extension-hook-events+)
           #'string<)))
    (is (= 33 (length baseline)))
    (is (equal expected actual)
        "cadr extension events drifted from the derived baseline set")))

(test goal12-source-parity-verdicts-follow-the-current-example-manifest
  (let ((ledger (goal12-read-project-file "docs/source-parity.md"))
        (readme (goal12-read-project-file "README.md"))
        (parity-map (goal12-read-project-file "docs/parity-map.md"))
        (performance (goal12-read-project-file "docs/performance.md"))
        (manifest-source (goal12-read-project-file "examples/manifest.sexp"))
        (identity
          "GOAL12_LEDGER baseline=74caa2649f10ed71b4378ce69f5d9fbfd2466ca5 source=595/518/77/0 examples=99/99/0"))
    (is (search "| `coding-agent` | 289 | 257 | 32 | 0 |" ledger))
    (is (search "| `tui` | 37 | 36 | 1 | 0 |" ledger))
    (is (search "| **Total** | **595** | **518** | **77** | **0** |" ledger))
    (is (search "实现完成，平台不可实测" ledger))
    (is (search "all 99" readme :test #'char-equal))
    (is (search "99 functionally equivalent Lisp ports and 0 gaps"
                parity-map))
    (is (search
         "| Goal 12 runnable examples | complete | fixed-baseline 99-file extension/SDK example surface |"
         parity-map))
    (is (not (search "94 complete; 5 blocked" parity-map)))
    (is (not (search "94 implemented, 5 missing" parity-map)))
    (is (not (search "C5 explicitly deferred" parity-map)))
    (dolist (source (list ledger parity-map performance manifest-source))
      (is (= 1 (goal12-count-substring identity source))))
    (is (search "docs/parity-map.md" performance))
    (is (search "docs/source-parity.md" performance))
    (is (search "examples/manifest.sexp" performance))
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

(test goal12-approved-amendments-close-every-example-gap
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
    (is (= 0 (length gap-ids)))
    (is (stringp mapping))
    (is (= 42 (goal12-count-substring "`:" mapping-table)))
    (is (search "19 项能力" proposal))
    (is (search "D/E 已于 2026-08-02 获得用户批准" amendment))
    (is (search "状态：**approved and implemented**" blocked))
    (dolist (item '("F" "G" "H"))
      (is (search (format nil "~A：批准" item) blocked)))))

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
    ("packages/coding-agent/examples/extensions/custom-compaction.ts"
     :hooks (:session-before-compact))
    ("packages/coding-agent/examples/extensions/custom-footer.ts"
     :commands ("footer"))
    ("packages/coding-agent/examples/extensions/custom-header.ts"
     :commands ("builtin-header") :hooks (:session-start))
    ("packages/coding-agent/examples/extensions/custom-provider-anthropic/index.ts"
     :native-providers (:custom-anthropic))
    ("packages/coding-agent/examples/extensions/custom-provider-gitlab-duo/index.ts"
     :native-providers (:gitlab-duo))
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
    ("packages/coding-agent/examples/extensions/prompt-customizer.ts"
     :hooks (:before-agent-start))
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

(defun goal12-load-example-native-provider
    (relative provider-id temporary http-function)
  (let* ((root (asdf:system-source-directory "cadr-cli"))
         (manager
           (make-test-extension-manager
            temporary
            (merge-pathnames "global/" temporary)
            (make-string-output-stream)
            (list (merge-pathnames relative root))))
         (report (cadr-cli::reload-cli-extensions manager))
         (host (cadr-cli::cli-extension-manager-host manager))
         (definition
           (find
            provider-id
            (cadr-agent::extension-snapshot-native-providers
             (cadr-agent::extension-host-current-snapshot host))
            :key
            (lambda (entry)
              (cadr-ai:runtime-provider-id
               (cadr-agent::extension-native-provider-definition-provider
                entry)))
            :test #'eq)))
    (is (null (getf report :errors)))
    (is (not (null definition)))
    (setf (cadr-agent::extension-host-http-request-function host)
          http-function)
    (values
     (cadr-agent::extension-native-provider-definition-provider definition)
     host
     (cadr-agent::extension-bundle-package
      (cadr-agent::extension-native-provider-definition-bundle definition)))))

(test goal12-custom-provider-oauth-examples-use-session-http-and-temporary-auth-store
  (dolist
      (spec
       '(("examples/extensions/custom-provider-anthropic/index.lisp"
          :custom-anthropic "auth-code#state-value")
         ("examples/extensions/custom-provider-gitlab-duo/index.lisp"
          :gitlab-duo
          "http://127.0.0.1/callback?code=%E4%B8%AD+code")))
    (destructuring-bind (relative provider-id prompt-value) spec
      (with-test-directory (temporary)
        (let ((requests nil)
              (notifications nil)
              (auth-path (merge-pathnames "auth.json" temporary)))
          (multiple-value-bind (provider host extension-package)
              (goal12-load-example-native-provider
               relative provider-id temporary
               (lambda (url &key method headers body timeout-ms signal)
                 (declare (ignore timeout-ms signal))
                 (push (list url method (copy-tree headers) body) requests)
                 (let ((object
                         (if (search "direct_access" url)
                             (cadr-ai::json-object
                              "token" "short-lived-secret"
                              "headers"
                              (cadr-ai::json-object
                               "X-GitLab-Realm" "saas"))
                             (if (eq provider-id :custom-anthropic)
                                 (cadr-ai::json-object
                                  "access_token" "anthropic-access-secret"
                                  "refresh_token" "anthropic-refresh-secret"
                                  "expires_in" 3600)
                                 (cadr-ai::json-object
                                  "access_token" "gitlab-access-secret"
                                  "refresh_token" "gitlab-refresh-secret"
                                  "expires_in" 3600
                                  "created_at" 2000000000)))))
                   (list
                    :status 200
                    :headers '(("content-type" . "application/json"))
                    :body
                    (sb-ext:string-to-octets
                     (cadr-ai::stringify-json object)
                     :external-format :utf-8)))))
            (declare (ignore host))
            (let* ((storage (cadr-cli:make-file-auth-storage auth-path))
                   (registry
                     (cadr-cli:make-model-registry
                      :path nil :credentials storage))
                   (runtime
                     (cadr-cli::model-registry-native-runtime registry)))
              (cadr-ai:models-runtime-set-provider runtime provider)
              (let ((credential
                      (cadr-cli::model-registry-login-native-provider
                       registry provider-id
                       (cadr-ai:make-runtime-auth-interaction
                        :prompt-function (constantly prompt-value)
                        :notify-function
                        (lambda (event) (push event notifications)))
                       :auth-type :oauth)))
                (is (typep credential 'cadr-ai:oauth-credential))
                (is (eq provider-id
                        (cadr-ai:oauth-credential-provider credential)))
                (is (typep
                     (cadr-cli:auth-storage-read storage provider-id)
                     'cadr-ai:oauth-credential))
                (is (= 1 (length notifications))))
              (let ((login-request (first requests)))
                (is (eq :post (second login-request)))
                (is (find "Content-Type" (third login-request)
                          :key #'car :test #'string-equal))
                (if (eq provider-id :custom-anthropic)
                    (is (search "\"code\":\"auth-code\""
                                (fourth login-request)))
                    (is (search "code=%E4%B8%AD+code"
                                (fourth login-request)))))
              (let* ((stored
                       (cadr-cli:auth-storage-read storage provider-id))
                     (refresh
                       (cadr-ai::runtime-provider-oauth-refresh-function
                        provider))
                     (refreshed (funcall refresh stored))
                     (refresh-request (first requests)))
                (is (typep refreshed 'cadr-ai:oauth-credential))
                (is (eq provider-id
                        (cadr-ai:oauth-credential-provider refreshed)))
                (is (eq :post (second refresh-request)))
                (is (search "refresh_token" (fourth refresh-request))))
              (when (eq provider-id :gitlab-duo)
                (let ((direct-access
                        (symbol-function
                         (or (find-symbol "GITLAB-DUO-DIRECT-ACCESS"
                                          extension-package)
                             (error "Missing GitLab direct access function")))))
                  (let ((result (funcall direct-access "gitlab-access-secret")))
                    (is (string= "short-lived-secret"
                                 (getf result :token)))
                    (is (string= "saas"
                                 (cdr (assoc "X-GitLab-Realm"
                                             (getf result :headers)
                                             :test #'string-equal)))))))
              (let ((login
                      (cadr-ai:runtime-provider-oauth-login-function provider)))
                (handler-case
                    (progn
                      (funcall
                       login
                       (cadr-ai:make-runtime-auth-interaction
                        :prompt-function (constantly nil)
                        :notify-function (constantly nil)))
                      (fail "Expected cancelled extension OAuth login"))
                  (condition (condition)
                    (let ((visible (princ-to-string condition)))
                      (is (search "cancelled" visible
                                  :test #'char-equal))
                      (dolist (secret '("access-secret" "refresh-secret"
                                        "short-lived-secret"))
                        (is (not (search secret visible)))))))))))))))

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
