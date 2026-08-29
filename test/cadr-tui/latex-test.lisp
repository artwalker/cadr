(in-package #:cadr-tui/tests)
(in-suite cadr-tui-suite)

(test latex-render-matches-baseline-reference-cases
  ;; Every case in +latex-reference-cases+ is the baseline renderLatex
  ;; output captured from pi@b79e4cc83 packages/tui/src/latex.ts.
  (dolist (case +latex-reference-cases+)
    (destructuring-bind (source display expected) case
      (is
       (equal expected
              (cadr-tui:render-latex source :display-p display))
       "render-latex ~S display=~A should be ~S"
       source display expected))))

(test markdown-inline-latex-renders-and-guards-currency
  (is
   (string=
    "the energy E = mc² holds"
    (cadr-tui::render-inline-markdown
     "the energy $E = mc^2$ holds" nil
     (cadr-tui:get-terminal-capabilities))))
  (is
   (string=
    "costs $5 and $10 today"
    (cadr-tui::render-inline-markdown
     "costs $5 and $10 today" nil
     (cadr-tui:get-terminal-capabilities)))))

(test markdown-block-latex-stacks-display-fractions
  (let ((text
          (format nil "~{~A~^~%~}"
                  (cadr-tui::render-markdown
                   (format nil "$$\\frac{1}{2}$$")
                   40 :ansi-theme-p nil))))
    (let ((trimmed
            (remove ""
                    (mapcar
                     (lambda (line)
                       (string-trim
                        '(#\Space) line))
                     (cadr-tui::split-lines-preserving-empty
                      text))
                    :test #'string=)))
      (is (equal '("1" "─" "2") trimmed)))))
