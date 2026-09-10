(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(test goal28-branch-summary-settings-reach-navigate-path
  (let* ((manager (cadr-cli::make-memory-settings-manager)))
    (is (= 16384
           (cadr-cli::settings-branch-summary-reserve-tokens
            manager)))
    (is (eq nil
             (cadr-cli::settings-branch-summary-skip-prompt-p
              manager)))
    (is (eq t
            (cadr-cli::branch-summary-tree-summarize-p
             manager
             :chooser (lambda (title labels)
                        (declare (ignore title labels))
                        "Summarize"))))
    (is (eq nil
            (cadr-cli::branch-summary-tree-summarize-p
             manager)))
    (is (= 16384
           (cadr-cli:sdk-settings-branch-summary-reserve-tokens
            (cadr-cli::make-memory-sdk-settings-manager))))
    (is (eq nil
            (cadr-cli:sdk-settings-branch-summary-skip-prompt-p
             (cadr-cli::make-memory-sdk-settings-manager)))))
  (with-test-directory (root)
    (let* ((global
             (merge-pathnames "settings.json" root))
           (_
             (write-text
              global
              "{\"branchSummary\":{\"reserveTokens\":9,\"skipPrompt\":true}}"))
           (manager
             (cadr-cli::make-settings-manager
              :global-path global)))
      (declare (ignore _))
      (is (= 9
             (cadr-cli::settings-branch-summary-reserve-tokens
              manager)))
      (is (eq t
              (cadr-cli::settings-branch-summary-skip-prompt-p
               manager)))
      (is (eq nil
              (cadr-cli::branch-summary-tree-summarize-p
               manager
               :chooser (lambda (title labels)
                          (declare (ignore title labels))
                          "Summarize"))))))
  (let ((settings
          (cadr-cli::make-memory-sdk-settings-manager
           (args
            "branchSummary"
            (args "reserveTokens" 111
                  "skipPrompt" t)))))
    (is (= 111
           (cadr-cli:sdk-settings-branch-summary-reserve-tokens
            settings)))
    (is (eq t
            (cadr-cli:sdk-settings-branch-summary-skip-prompt-p
             settings))))
  (let* ((manager (cadr-cli::make-memory-settings-manager))
         (agent (cadr-agent:make-agent :provider nil :model nil)))
    (cadr-cli::sync-agent-settings-from-manager
     agent manager)
    (is (eq t (cadr-agent::agent-auto-compact-p agent)))
    (is (= 20000
           (cadr-agent::agent-compaction-keep-recent-tokens
            agent)))
    (is (= 16384
           (cadr-agent::agent-compaction-reserve-tokens
            agent)))))
