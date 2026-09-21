(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

;;; Locks packages/coding-agent/test/system-prompt-updates.test.ts
;;; "diffs sections into a patch" and
;;; "keeps the preamble untagged and replaces it like any section"
;;; against baseline v0.86.0 system-prompt.ts.

(defun section-text (sections name)
  (cdr (assoc name sections :test #'string=)))

(test diffs-sections-into-a-patch
  (let ((previous
          (cadr-cli:build-system-prompt-sections
           :cwd "/tmp"
           :sections '(("plan_mode" . "Plan only."))))
        (current
          (cadr-cli:build-system-prompt-sections
           :cwd "/tmp"
           :sections
           '(("plan_mode" . "Implementation allowed.")))))
    (is (equal
         '(("plan_mode"
            . "<plan_mode>
Implementation allowed.
</plan_mode>"))
         (cadr-cli:diff-system-prompt-sections
          previous current)))
    (is (null
         (cadr-cli:diff-system-prompt-sections
          previous previous)))
    (is (equal
         '(("plan_mode" . nil))
         (cadr-cli:diff-system-prompt-sections
          previous
          (cadr-cli:build-system-prompt-sections
           :cwd "/tmp"))))))

(test keeps-the-preamble-untagged-and-replaces-it-like-any-section
  (let ((previous
          (cadr-cli:build-system-prompt-sections
           :custom-prompt "You are A."
           :cwd "/tmp"))
        (current
          (cadr-cli:build-system-prompt-sections
           :custom-prompt "You are B."
           :cwd "/tmp")))
    (is (string= "You are A."
                 (section-text previous "preamble")))
    (is (equal
         '(("preamble" . "You are B."))
         (cadr-cli:diff-system-prompt-sections
          previous current)))
    (is (equal
         '(:content "Exact prompt.")
         (cadr-cli:build-system-prompt-state
          :force-system-prompt "Exact prompt."
          :cwd "/tmp")))
    (let ((state
            (cadr-cli:build-system-prompt-state
             :cwd "/tmp")))
      (is (string= "" (getf state :content)))
      (is (equal
           (cadr-cli:build-system-prompt-sections
            :cwd "/tmp")
           (getf state :sections))))
    (signals error
      (cadr-cli:build-system-prompt-sections
       :cwd "/tmp"
       :sections '(("preamble" . "x"))))))
