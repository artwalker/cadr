(in-package #:cadr-cli/tests)

(in-suite cadr-cli-suite)

;;; Goal 18 I7 tail: the baseline content migrations
;;; (packages/coding-agent/src/migrations.ts), the models.json error
;;; envelope, the --list-models table, prompt-file and @file read
;;; failures, and the extension shortcut conflict resolution — each
;;; locked to the baseline wording.

(defun goal18-with-agent-dir (directory thunk)
  (let ((agent
          (uiop:ensure-directory-pathname
           (merge-pathnames "agent/" directory))))
    (ensure-directories-exist agent)
    (let ((cadr-core::*path-environment-function*
            (lambda (name)
              (and (string= name "CADR_CODING_AGENT_DIR")
                   (namestring agent)))))
      (funcall thunk agent))))

(test goal18-oauth-json-and-settings-api-keys-migrate-into-auth-json
  (with-test-directory (directory)
    (goal18-with-agent-dir
     directory
     (lambda (agent)
       (write-text
        (merge-pathnames "oauth.json" agent)
        "{\"anthropic\": {\"access\": \"tok\", \"refresh\": \"ref\", \"expires\": 1}}")
       (write-text
        (merge-pathnames "settings.json" agent)
        "{\"theme\": \"dark\", \"apiKeys\": {\"deepseek\": \"sk-test-key\"}}")
       (let ((providers (cadr-cli::migrate-auth-to-auth-json)))
         (is (equal '("anthropic" "deepseek")
                    (sort (copy-list providers) #'string<)))
         (is (null (probe-file (merge-pathnames "oauth.json" agent))))
         (is (not (null
                   (probe-file
                    (merge-pathnames "oauth.json.migrated" agent)))))
         (let ((auth
                 (cadr-ai::parse-json
                  (uiop:read-file-string
                   (merge-pathnames "auth.json" agent)))))
           (is (string= "oauth"
                        (cadr-ai::json-get
                         (cadr-ai::json-get auth "anthropic") "type")))
           (is (string= "tok"
                        (cadr-ai::json-get
                         (cadr-ai::json-get auth "anthropic") "access")))
           (is (string= "api_key"
                        (cadr-ai::json-get
                         (cadr-ai::json-get auth "deepseek") "type")))
           (is (string= "sk-test-key"
                        (cadr-ai::json-get
                         (cadr-ai::json-get auth "deepseek") "key")))
           (is (= #o600
                  (logand #o777
                          (sb-posix:stat-mode
                           (sb-posix:stat
                            (merge-pathnames "auth.json" agent)))))))
         (let ((settings
                 (cadr-ai::parse-json
                  (uiop:read-file-string
                   (merge-pathnames "settings.json" agent)))))
           (is (null (cadr-ai::json-get settings "apiKeys")))
           (is (string= "dark"
                        (cadr-ai::json-get settings "theme"))))
         ;; An existing auth.json skips the whole migration.
         (is (null (cadr-cli::migrate-auth-to-auth-json))))))))

(test goal18-agent-root-sessions-move-into-the-sessions-directory
  (with-test-directory (directory)
    (goal18-with-agent-dir
     directory
     (lambda (agent)
       (write-text
        (merge-pathnames "stray.jsonl" agent)
        (format nil
                "{\"type\":\"session\",\"version\":3,\"id\":\"stray\",\"cwd\":\"/tmp/x\"}~%"))
       (write-text
        (merge-pathnames "notes.jsonl" agent)
        (format nil "{\"type\":\"other\"}~%"))
       (cadr-cli::migrate-sessions-from-agent-root)
       (is (null (probe-file (merge-pathnames "stray.jsonl" agent))))
       (is (not (null
                 (probe-file
                  (merge-pathnames "sessions/stray.jsonl" agent)))))
       ;; Not a session file: untouched.
       (is (not (null
                 (probe-file
                  (merge-pathnames "notes.jsonl" agent)))))))))

(test goal18-managed-binaries-move-from-tools-to-bin
  (with-test-directory (directory)
    (goal18-with-agent-dir
     directory
     (lambda (agent)
       (write-text (merge-pathnames "tools/fd" agent) "binary")
       (write-text (merge-pathnames "tools/rg" agent) "binary")
       (let ((output (make-string-output-stream)))
         (cadr-cli::migrate-tools-to-bin :output output)
         (is (string=
              (format nil "Migrated managed binaries tools/ → bin/~%")
              (get-output-stream-string output))))
       (is (not (null
                 (probe-file (merge-pathnames "bin/fd" agent)))))
       (is (not (null
                 (probe-file (merge-pathnames "bin/rg" agent)))))
       ;; Nothing left to move: silent.
       (let ((output (make-string-output-stream)))
         (cadr-cli::migrate-tools-to-bin :output output)
         (is (string= "" (get-output-stream-string output))))))))

(test goal18-commands-directories-migrate-to-prompts
  (with-test-directory (directory)
    (let ((base (uiop:ensure-directory-pathname
                 (merge-pathnames "base/" directory))))
      (write-text (merge-pathnames "commands/review.md" base) "body")
      (let ((output (make-string-output-stream)))
        (is (cadr-cli::migrate-commands-to-prompts
             base "Global" :output output))
        (is (string=
             (format nil "Migrated Global commands/ → prompts/~%")
             (get-output-stream-string output))))
      (is (null (uiop:directory-exists-p
                 (merge-pathnames "commands/" base))))
      (is (not (null
                (probe-file
                 (merge-pathnames "prompts/review.md" base)))))
      ;; Failure arm (baseline migrations.ts:148): the rename failure is
      ;; a yellow warning, never a raw condition.
      (write-text (merge-pathnames "commands/review2.md" base) "body")
      (delete-file (merge-pathnames "prompts/review.md" base))
      (uiop:delete-directory-tree
       (merge-pathnames "prompts/" base)
       :validate t :if-does-not-exist :ignore)
      (let ((output (make-string-output-stream))
            (cadr-cli::*migration-rename-function*
              (lambda (old new)
                (declare (ignore old new))
                (error "EACCES: permission denied (test drive)"))))
        (is (null
             (cadr-cli::migrate-commands-to-prompts
              base "Global" :output output)))
        (is (uiop:string-prefix-p
             "Warning: Could not migrate Global commands/ to prompts/: "
             (get-output-stream-string output)))))))

(test goal18-deprecated-extension-directories-warn
  (with-test-directory (directory)
    (let ((base (uiop:ensure-directory-pathname
                 (merge-pathnames "base/" directory))))
      (ensure-directories-exist (merge-pathnames "hooks/" base))
      (write-text (merge-pathnames "tools/custom-tool" base) "x")
      (write-text (merge-pathnames "tools/fd" base) "x")
      (let ((warnings
              (cadr-cli::check-deprecated-extension-dirs base "Global")))
        (is (equal
             '("Global hooks/ directory found. Hooks have been renamed to extensions."
               "Global tools/ directory contains custom tools. Custom tools have been merged into extensions.")
             warnings)))
      ;; Only managed binaries and dotfiles: no warning.
      (delete-file (merge-pathnames "tools/custom-tool" base))
      (uiop:delete-directory-tree
       (merge-pathnames "hooks/" base)
       :validate t :if-does-not-exist :ignore)
      (is (null
           (cadr-cli::check-deprecated-extension-dirs base "Global"))))))

(test goal18-deprecation-warnings-match-the-baseline-text
  (let ((output (make-string-output-stream)))
    (cadr-cli::show-deprecation-warnings
     '("Global hooks/ directory found. Hooks have been renamed to extensions.")
     :output output
     :input (make-string-input-stream "x"))
    (is (string=
         (format nil
                 "Warning: Global hooks/ directory found. Hooks have been renamed to extensions.~%~
                  ~%Move your extensions to the extensions/ directory.~%~
                  Migration guide: ~A~%~
                  Documentation: ~A~%~
                  ~%Press any key to continue...~%~%"
                 cadr-cli::+migration-guide-url+
                 cadr-cli::+extensions-doc-url+)
         (get-output-stream-string output)))))

(test list-models-token-count-writer-matches-baseline-strings
  ;; Shipped writer must keep formatTokenCount bytes without FORMAT.
  (dolist (pair '((0 . "0")
                  (1 . "1")
                  (999 . "999")
                  (1000 . "1K")
                  (1500 . "1.5K")
                  (384000 . "384K")
                  (1000000 . "1M")
                  (1500000 . "1.5M")))
    (is (string=
         (cdr pair)
         (with-output-to-string (stream)
           (cadr-cli::write-list-models-token-count
            stream (car pair)))))))

(test goal18-list-models-prints-the-baseline-table
  (with-test-directory (directory)
    (goal18-with-agent-dir
     directory
     (lambda (agent)
       (write-text
        (merge-pathnames "models.json" agent)
        "{\"providers\": {\"deepseek\": {\"apiKey\": \"sk-test-key\"}}}")
       (let ((output (make-string-output-stream)))
         (cadr-cli::print-cli-models nil output)
         (is (string=
              (format nil
                      "provider  model              context  max-out  thinking  images~%~
                       deepseek  deepseek-v4-flash  1M       384K     yes       no    ~%~
                       deepseek  deepseek-v4-pro    1M       384K     yes       no    ~%")
              (get-output-stream-string output))))
       ;; Fuzzy filter on "provider id"; no match keeps the baseline line.
       (let ((output (make-string-output-stream)))
         (cadr-cli::print-cli-models "flash" output)
         (is (string=
              (format nil
                      "provider  model              context  max-out  thinking  images~%~
                       deepseek  deepseek-v4-flash  1M       384K     yes       no    ~%")
              (get-output-stream-string output))))
       (let ((output (make-string-output-stream)))
         (cadr-cli::print-cli-models "nomatch" output)
         (is (string= (format nil "No models matching \"nomatch\"~%")
                      (get-output-stream-string output))))))))

(test goal18-list-models-warns-on-corrupt-models-json
  (with-test-directory (directory)
    (goal18-with-agent-dir
     directory
     (lambda (agent)
       (write-text
        (merge-pathnames "models.json" agent)
        "{ not valid json ")
       (let ((output (make-string-output-stream))
             (error-output (make-string-output-stream)))
         (let ((*error-output* error-output))
           (cadr-cli::print-cli-models nil output))
         (let ((warning (get-output-stream-string error-output)))
           (is (uiop:string-prefix-p
                (format nil
                        "Warning: errors loading models.json:~%Failed to parse models.json: ")
                warning))
           (is (search
                (format nil "~%~%File: ~A~%"
                        (namestring
                         (merge-pathnames "models.json" agent)))
                warning)))
         (is (uiop:string-prefix-p
              "No models available. "
              (get-output-stream-string output))))))))

(test goal18-system-prompt-directory-falls-back-with-a-warning
  (with-test-directory (directory)
    (let ((error-output (make-string-output-stream))
          (dir (namestring
                (uiop:ensure-directory-pathname directory))))
      (let* ((*error-output* error-output)
             (value (cadr-cli::resolve-system-prompt dir)))
        ;; Baseline resolvePromptInput: unreadable prompt files degrade
        ;; to the literal input.
        (is (string= dir value))
        (is (string=
             (format nil
                     "Warning: Could not read system prompt file ~A: Error: EISDIR: illegal operation on a directory, read~%"
                     dir)
             (get-output-stream-string error-output)))))))

(test goal18-file-argument-directory-is-a-normalized-error
  (with-test-directory (directory)
    (signals cadr-ai:configuration-error
      (cadr-cli::process-cli-file-arguments
       (list (namestring directory))))
    (handler-case
        (cadr-cli::process-cli-file-arguments
         (list (namestring directory)))
      (cadr-ai:configuration-error (condition)
        (is (uiop:string-prefix-p
             "Error: Could not read file "
             (cadr-ai:cadr-error-message condition)))
        (is (search
             "EISDIR: illegal operation on a directory, read"
             (cadr-ai:cadr-error-message condition))))))

(test goal18-extension-shortcut-conflicts-follow-the-baseline
  (with-test-directory (directory)
    (let* ((bundle-one
             (cadr-agent::make-extension-bundle
              :id "one" :path "/tmp/ext-one"))
           (bundle-two
             (cadr-agent::make-extension-bundle
              :id "two" :path "/tmp/ext-two"))
           (host (cadr-agent::make-extension-host :cwd directory)))
      (cadr-agent::call-with-extension-registration
       bundle-one
       (lambda ()
         (cadr-agent::register-extension-shortcut
          "ctrl+x" :description "one" :handler (lambda ()))
         (cadr-agent::register-extension-shortcut
          "ctrl+shift+d" :description "two" :handler (lambda ()))
         (cadr-agent::register-extension-shortcut
          "ctrl+shift+z" :description "three" :handler (lambda ()))))
      (cadr-agent::call-with-extension-registration
       bundle-two
       (lambda ()
         (cadr-agent::register-extension-shortcut
          "ctrl+shift+z" :description "four" :handler (lambda ()))))
      (cadr-agent::replace-extension-bundles
       host (list bundle-one bundle-two))
      (let ((keybindings
              (cadr-tui:make-keybindings-manager
               :user-bindings
               '(("app.interrupt" . "ctrl+x")
                 ("app.session.delete" . "ctrl+shift+d")))))
        (multiple-value-bind (shortcuts diagnostics)
            (cadr-cli::resolve-extension-shortcuts host keybindings)
          ;; Reserved built-in key: skipped with the baseline text.
          (is (null
               (find "ctrl+x" shortcuts
                     :key #'cadr-agent::extension-shortcut-definition-key
                     :test #'string=)))
          ;; Non-reserved built-in collision: extension wins.
          (is (not (null
                    (find "ctrl+shift+d" shortcuts
                          :key
                          #'cadr-agent::extension-shortcut-definition-key
                          :test #'string=))))
          ;; Extension-extension collision: later registration wins.
          (is (equal '("/tmp/ext-two")
                     (mapcar #'cadr-cli::extension-shortcut-path
                             (remove-if-not
                             (lambda (definition)
                                (string=
                                 "ctrl+shift+z"
                                 (cadr-agent::extension-shortcut-definition-key
                                  definition)))
                              shortcuts)))))
          (let ((messages
                  (mapcar (lambda (issue) (getf issue :message))
                          diagnostics)))
            (is (equal
                 "Extension shortcut 'ctrl+x' from /tmp/ext-one conflicts with built-in shortcut. Skipping."
                 (first messages)))
            (is (equal
                 "Extension shortcut conflict: 'ctrl+shift+d' is built-in shortcut for app.session.delete and /tmp/ext-one. Using /tmp/ext-one."
                 (second messages)))
            (is (equal
                 "Extension shortcut conflict: 'ctrl+shift+z' registered by both /tmp/ext-one and /tmp/ext-two. Using /tmp/ext-two."
                 (third messages)))))))))

(test goal18-keybinding-legacy-names-migrate
  (let ((migrated
          (cadr-cli::migrate-keybindings
           (cadr-ai::json-object
            "cursorLeft" "ctrl+b"
            "selectCancel" (vector "ctrl+w")
            "fork" "ctrl+shift+f"
            "tui.editor.undo" "ctrl+u"
            "undo" "ctrl+z"))))
    ;; Legacy names map onto the baseline targets.
    (is (string= "ctrl+b"
                 (cadr-ai::json-get migrated "tui.editor.cursorLeft")))
    (is (equal '("ctrl+w")
               (coerce
                (cadr-ai::json-get migrated "tui.select.cancel")
                'list)))
    (is (string= "ctrl+shift+f"
                 (cadr-ai::json-get migrated "app.session.fork")))
    ;; A legacy name never overrides an explicit modern binding.
    (is (string= "ctrl+u"
                 (cadr-ai::json-get migrated "tui.editor.undo")))
    (is (null (cadr-ai::json-get migrated "undo")))
    (is (null (cadr-ai::json-get migrated "cursorLeft")))))

(test goal18-startup-issue-report-composes-the-baseline-load-failure
  (let ((manager
          (cadr-cli::make-cli-extension-manager
           :output (make-broadcast-stream))))
    (setf (cadr-cli::cli-extension-manager-startup-issues manager)
          (list
           (list :type :error
                 :path "/tmp/ext-broken/extension.lisp"
                 :message "Failed to load extension: render-drive-broken")
           (list :type :warning
                 :message "some discovery warning")))
    (let ((output (make-string-output-stream)))
      (multiple-value-bind (any-error-p load-failure-p)
          (cadr-cli::report-startup-extension-issues manager output)
        (is (and any-error-p load-failure-p))
        (is (string=
             (format nil
                     "Error: Failed to load extension \"/tmp/ext-broken/extension.lisp\": Failed to load extension: render-drive-broken~%~
                      Warning: some discovery warning~%")
             (get-output-stream-string output)))))))
