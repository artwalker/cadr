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

(test goal28-branch-summary-custom-prompt-keeps-the-instructions
  (let* ((manager (cadr-cli::make-memory-settings-manager))
         (chooser-calls 0)
         (editor-calls 0))
    (multiple-value-bind (summarize-p cancelled instructions)
        (cadr-cli::branch-summary-tree-summarize-p
         manager
         :chooser
         (lambda (title labels)
           (declare (ignore title labels))
           (incf chooser-calls)
           "Summarize with custom prompt")
         :editor
         (lambda ()
           (incf editor-calls)
           "keep the API names"))
      (is (eq t summarize-p))
      (is (eq nil cancelled))
      (is (string= "keep the API names" instructions))
      (is (= 1 chooser-calls))
      (is (= 1 editor-calls))))
  (let* ((manager (cadr-cli::make-memory-settings-manager))
         (chooser-calls 0))
    (multiple-value-bind (summarize-p cancelled instructions)
        (cadr-cli::branch-summary-tree-summarize-p
         manager
         :chooser
         (lambda (title labels)
           (declare (ignore title labels))
           (incf chooser-calls)
           (if (= chooser-calls 1)
               "Summarize with custom prompt"
               "No summary"))
         :editor
         (lambda () nil))
      (is (eq nil summarize-p))
      (is (eq nil cancelled))
      (is (null instructions))
      (is (= 2 chooser-calls)))))
