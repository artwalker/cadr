(in-package #:cadr-tui/tests)

(in-suite cadr-tui-suite)

(test goal20-fuzzy-match-reuses-normalized-text
  (let ((text "GPT-5.2-Codex"))
    (multiple-value-bind (direct-p direct-score)
        (cadr-tui:fuzzy-match "codex" text)
      (multiple-value-bind (cached-p cached-score)
          (cadr-tui::fuzzy-match-against-normalized-text
           "codex" (string-downcase text))
        (is (eq direct-p cached-p))
        (is (= direct-score cached-score)))))
  (is
   (equal
    '("Banana")
    (cadr-tui:fuzzy-filter
     '("Apple" "Banana" "Cherry")
     "AN"
     #'identity))))
