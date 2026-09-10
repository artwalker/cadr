(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun goal28-markdown-plain-lines (lines)
  (mapcar
   (lambda (line)
     (string-right-trim
      " "
      (cadr-tui:strip-terminal-sequences line)))
   lines))

(test goal28-markdown-indent-settings-reach-existing-renderer
  (let* ((source (format nil "```ts~%const x = 1;~%```"))
         (manager (cadr-cli::make-memory-settings-manager))
         (absent-indent
           (cadr-cli::settings-markdown-code-block-indent
            manager))
         (absent-lines
           (goal28-markdown-plain-lines
            (cadr-tui:render-markdown
             source 80
             :code-block-indent absent-indent))))
    (is (string= "  " absent-indent))
    (is (equal
         '("```ts" "  const x = 1;" "```")
         absent-lines))
    (is (eq t (cadr-cli::settings-boolean-value
               manager "compaction" t "enabled")))
    (is (= 20000
           (cadr-cli::settings-compaction-keep-recent-tokens
            manager)))
    (is (= 16384
           (cadr-cli::settings-compaction-reserve-tokens
            manager)))
    (is (= 16384
           (cadr-cli::settings-branch-summary-reserve-tokens
            manager)))
    (is (eq nil
            (cadr-cli::settings-branch-summary-skip-prompt-p
             manager)))
    (is (null (cadr-cli::settings-shell-path manager)))
    (is (null
         (cadr-cli::settings-shell-command-prefix manager)))
    (is (null (cadr-cli::settings-session-dir manager)))
    (is (null
         (cadr-cli::settings-websocket-connect-timeout-ms
          manager)))
    (is (null (cadr-cli::settings-http-proxy manager)))
    (is (null (cadr-cli::settings-thinking-budgets manager)))
    (is (null (cadr-cli::settings-theme-paths manager)))
    (is (null (cadr-cli::settings-skill-paths manager)))
    (is (null (cadr-cli::settings-prompt-paths manager)))
    (is (null (cadr-cli::settings-extension-paths manager))))
  (with-test-directory (root)
    (let* ((global (merge-pathnames "settings.json" root))
           (_
             (write-text
              global
              "{\"markdown\":{\"codeBlockIndent\":\">>>>\"}}"))
           (manager
             (cadr-cli::make-settings-manager
              :global-path global))
           (present-indent
             (cadr-cli::settings-markdown-code-block-indent
              manager))
           (present-lines
             (goal28-markdown-plain-lines
              (cadr-tui:render-markdown
               (format nil "```ts~%const x = 1;~%```")
               80
               :code-block-indent present-indent))))
      (declare (ignore _))
      (is (string= ">>>>" present-indent))
      (is (equal
           '("```ts" ">>>>const x = 1;" "```")
           present-lines))))
  (with-test-directory (root)
    (let* ((global (merge-pathnames "settings.json" root))
           (_
             (write-text
              global
              "{\"markdown\":{\"codeBlockIndent\":4}}"))
           (manager
             (cadr-cli::make-settings-manager
              :global-path global))
           (non-string-indent
             (cadr-cli::settings-markdown-code-block-indent
              manager))
           (non-string-lines
             (goal28-markdown-plain-lines
              (cadr-tui:render-markdown
               (format nil "```ts~%const x = 1;~%```")
               80
               :code-block-indent non-string-indent))))
      (declare (ignore _))
      (is (string= "  " non-string-indent))
      (is (equal
           '("```ts" "  const x = 1;" "```")
           non-string-lines)))))
