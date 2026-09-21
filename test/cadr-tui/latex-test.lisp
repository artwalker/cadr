(in-package #:cadr-tui/tests)
(in-suite cadr-tui-suite)

(test latex-render-matches-baseline-reference-cases
  ;; Every case in +latex-reference-cases+ is the baseline renderLatex
  ;; output captured from pi@13cbf77df packages/tui/src/latex.ts.
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

(test goal24-latex-legacy-font-switches
  (is
   (string=
    "diag(-1/2,1,1), F_intrinsic(λ)"
    (cadr-tui:render-latex
     "\\mathrm{diag}(-1/2,1,1),\\quad F_{\\rm intrinsic}(\\lambda)")))
  (is
   (string=
    "hello+world+x+roman+bold+italic+sans+mono+calligraphic+slanted"
    (cadr-tui:render-latex
     "\\textnormal{hello}+\\mbox{world}+\\boldsymbol{x}+{\\rm roman}+{\\bf bold}+{\\it italic}+{\\sf sans}+{\\tt mono}+{\\cal calligraphic}+{\\sl slanted}"))))

(test goal24-latex-centered-cases
  (is
   (string=
    (format nil "       ⎧ a if x < 0~%f(x) = ⎨ b if x = 0~%       ⎩ c otherwise")
    (cadr-tui:render-latex
     "f(x)=\\begin{cases}a & x<0 \\\\ b & \\text{if }x=0 \\\\ c & \\text{otherwise}\\end{cases}")))
  (is
   (string=
    (format nil "       ⎧ x² if x ≥ 0~%f(x) = ⎨~%       ⎩ -x if x < 0")
    (cadr-tui:render-latex
     "f(x) = \\begin{cases} x^{2} & x \\geq 0 \\\\ -x & x < 0 \\end{cases}"))))

(test goal24-latex-nested-display-scripts
  (is
   (string=
    (format nil "                            2~%                    -A-1   n~%∂ₜU₂(t,0) = Aj (1-t)    . x  +x~%              *                i~%                                j")
    (cadr-tui:render-latex
     "\\partial_tU_2(t,0)=Aj_*(1-t)^{-A-1}.\\qquad x^{n^2}+x_{i_j}"
     :display-p t)))
  (is
   (string=
    "e^(1/2)+1/2"
    (cadr-tui:render-latex
     "e^{\\frac{1}{2}}+\\tfrac{1}{2}"
     :display-p t))))
