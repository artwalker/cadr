(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(test goal28-branch-summary-prompt-reaches-existing-tree
  (let* ((manager (cadr-cli::make-memory-settings-manager))
         (chooser-calls 0)
         (summarize-p
           (cadr-cli::branch-summary-tree-summarize-p
            manager
            :chooser
            (lambda (title labels)
              (incf chooser-calls)
              (is (string= title "Summarize branch?"))
              (is (equal
                   labels
                   '("No summary"
                     "Summarize"
                     "Summarize with custom prompt")))
              "Summarize"))))
    (is (eq nil
            (cadr-cli::settings-branch-summary-skip-prompt-p
             manager)))
    (is (= 1 chooser-calls))
    (is (eq t summarize-p)))
  (with-test-directory (root)
    (let* ((global (merge-pathnames "settings.json" root))
           (_
             (write-text
              global
              "{\"branchSummary\":{\"reserveTokens\":9,\"skipPrompt\":true}}"))
           (manager
             (cadr-cli::make-settings-manager
              :global-path global))
           (chooser-calls 0)
           (summarize-p
             (cadr-cli::branch-summary-tree-summarize-p
              manager
              :chooser
              (lambda (title labels)
                (declare (ignore title labels))
                (incf chooser-calls)
                "Summarize"))))
      (declare (ignore _))
      (is (eq t
              (cadr-cli::settings-branch-summary-skip-prompt-p
               manager)))
      (is (= 9
             (cadr-cli::settings-branch-summary-reserve-tokens
              manager)))
      (is (= 0 chooser-calls))
      (is (eq nil summarize-p)))))
