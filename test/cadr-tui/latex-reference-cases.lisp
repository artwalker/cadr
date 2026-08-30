;; Generated from pi@b79e4cc83 packages/tui/src/latex.ts renderLatex
;; output for each (source display) pair; NIL rendered means the
;; baseline rejected the expression as unsupported or malformed.
(in-package #:cadr-tui/tests)

(defparameter +latex-reference-cases+
  (list
   (list "E = mc^2" nil "E = mc²")
   (list "\\frac{1}{2}" nil "1/2")
   (list "\\frac{1}{2}" t "1
─
2")
   (list "\\frac{x+1}{y-2}" t "x+1
───
y-2")
   (list "\\sqrt{x}" nil "√x")
   (list "\\sqrt[3]{x}" nil "∛x")
   (list "\\sqrt[5]{x+1}" nil "⁵√(x+1)")
   (list "\\sum_{i=1}^{n} x_i" t " n
 ∑  xᵢ
i=1")
   (list "\\sum_{i=1}^{n} x_i" nil "∑ᵢ₌₁ⁿ xᵢ")
   (list "\\int_0^1 f(x) dx" t "1
∫ f(x) dx
0")
   (list "\\lim_{x \\to 0} \\frac{\\sin x}{x}" t "     sin x
lim  ─────
x→0    x")
   (list "x_{i+1}^2" nil "xᵢ₊₁²")
   (list "\\alpha + \\beta \\times \\gamma" nil "α + β × γ")
   (list "a \\leq b \\neq c \\approx d" nil "a ≤ b ≠ c ≈ d")
   (list "\\mathbb{R}^n" nil "ℝⁿ")
   (list "\\hat{x} + \\vec{v}" nil "x̂ + v⃗")
   (list "x \\not= y" nil "x ≠ y")
   (list "\\binom{n}{k}" nil "(n choose k)")
   (list "f \\pmod{3}" nil "f (mod 3)")
   (list "\\operatorname{argmax}_{x} f(x)" t "argmax[x] f(x)")
   (list "\\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix}" t "⎛ a │ b ⎞
⎝ c │ d ⎠")
   (list "\\begin{cases} x & if x > 0 \\\\ -x & otherwise \\end{cases}" t "⎧ x if x > 0
⎩ -x otherwise")
   (list "\\begin{aligned} x &= 1 \\\\ y &= 2 \\end{aligned}" t "x = 1
y = 2")
   (list "\\boxed{x+y}" nil "[x+y]")
   (list "\\overset{*}{X}" nil "X^*")
   (list "\\underset{n}{\\max}" nil "maxₙ")
   (list "A \\xrightarrow{f} B" nil nil)
   (list "\\text{hello world}" nil "hello world")
   (list "\\not\\in" nil "∉")
   (list "$not latex" nil "$not latex")
   (list "\\unknowncmd{x}" nil nil)
   (list "\\frac{1}{2" nil nil)
   (list "\\displaystyle\\sum_{k=0}^\\infty \\frac{1}{k!}" t " ∞   1
 ∑   ──
k=0  k!")
   (list "x \\quad y \\; z" nil "x y z")
   (list "e^{i\\pi} + 1 = 0" nil "e^(iπ) + 1 = 0")
   ))
