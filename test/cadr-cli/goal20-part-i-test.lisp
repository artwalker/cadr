(in-package #:cadr-cli/tests)

(in-suite cadr-cli-suite)

(defparameter *goal20-lispification-identity*
  "GOAL20_LISPIFICATION_LEDGER baseline=53fa77ccd8a279eb87e92294ef3687b03ff80112 files=293 lines=121006 assets=5 unevaluated=293 needs-rewrite=0 no-rewrite=0 in-progress=0 done=0")

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
    (is (= 293
           (count-substring "| pending evaluation | — | — |" section-2)))
    (is (= 5
           (count-substring
            "| n/a | Static export asset, a byte-for-byte copy of the baseline, no Lisp source to evaluate | — |"
            section-2)))
    (is (= 12
           (count-substring "src/cadr-tui/mermaid/" section-2)))
    (is (null (search "| evaluated-" section-2)))
    (is (null (search "## Lisp" ledger)))))
