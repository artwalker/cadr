(in-package #:cadr-cli/tests)

(in-suite cadr-cli-suite)

(defparameter *goal20-lispification-identity*
  "GOAL20_LISPIFICATION_LEDGER baseline=16787ad5b2dc748047f314ca1bfe7708f30f54f3 files=301 lines=129068 assets=5 unevaluated=0 needs-rewrite=0 no-rewrite=147 in-progress=0 done=154")

(defun goal20-part-i-ledger ()
  (uiop:read-file-string
   (merge-pathnames
    "docs/code-organization.md"
    (asdf:system-source-directory "cadr-cli"))))

(defun goal20-part-i-identity (content)
  (let* ((start (search "GOAL20_LISPIFICATION_LEDGER" content))
         (end (and start (position #\Newline content :start start)))
         (line (and start end (subseq content start end)))
         (comment-end (and line (search " -->" line))))
    (and line
         (string-right-trim
          '(#\Space #\Tab)
          (subseq line 0 (or comment-end (length line)))))))

(defun goal20-part-i-section-2 (content)
  (let* ((start (search "## 2. Per-file ledger" content))
         (end (and start (search "## 3. " content :start2 start))))
    (and start end (subseq content start end))))

(test goal20-part-i-locks-lispification-identity-and-initial-states
  (let* ((ledger (goal20-part-i-ledger))
         (section-2 (goal20-part-i-section-2 ledger)))
    (is (string= *goal20-lispification-identity*
                 (goal20-part-i-identity ledger)))
    (is (not (null section-2)))
    (is (= 0
           (count-substring "| pending evaluation | — | — |" section-2)))
    (is (= 147
           (count-substring "| no-rewrite |" section-2)))
    (is (= 0
           (count-substring "| needs-rewrite |" section-2)))
    (is (= 154
           (count-substring "| done |" section-2)))
    (is (= 5
           (count-substring
            "| n/a | Static export asset, a byte-for-byte copy of the baseline, no Lisp source to evaluate | — |"
            section-2)))
    (is (= 12
           (count-substring "src/cadr-tui/mermaid/" section-2)))
    (is (null (search "| evaluated-" section-2)))
    (is (null (search "## Lisp" ledger)))))
