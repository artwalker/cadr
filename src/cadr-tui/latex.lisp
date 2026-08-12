(in-package #:cadr-tui)

;;; pi@53fa77ccd packages/tui/src/latex.ts — terminal-friendly Unicode
;;; rendering of basic LaTeX math.  Data tables are transcribed
;;; verbatim; the parser is a direct port of LatexParser.

;; generated from pi@53fa77ccd packages/tui/src/latex.ts data tables
(defparameter +latex-symbols+
  (list
   (cons "alpha" "α")
   (cons "beta" "β")
   (cons "gamma" "γ")
   (cons "delta" "δ")
   (cons "epsilon" "ϵ")
   (cons "varepsilon" "ε")
   (cons "zeta" "ζ")
   (cons "eta" "η")
   (cons "theta" "θ")
   (cons "vartheta" "ϑ")
   (cons "iota" "ι")
   (cons "kappa" "κ")
   (cons "varkappa" "ϰ")
   (cons "lambda" "λ")
   (cons "mu" "μ")
   (cons "nu" "ν")
   (cons "xi" "ξ")
   (cons "pi" "π")
   (cons "varpi" "ϖ")
   (cons "rho" "ρ")
   (cons "varrho" "ϱ")
   (cons "sigma" "σ")
   (cons "varsigma" "ς")
   (cons "tau" "τ")
   (cons "upsilon" "υ")
   (cons "phi" "ϕ")
   (cons "varphi" "φ")
   (cons "chi" "χ")
   (cons "psi" "ψ")
   (cons "omega" "ω")
   (cons "Gamma" "Γ")
   (cons "Delta" "Δ")
   (cons "Theta" "Θ")
   (cons "Lambda" "Λ")
   (cons "Xi" "Ξ")
   (cons "Pi" "Π")
   (cons "Sigma" "Σ")
   (cons "Upsilon" "Υ")
   (cons "Phi" "Φ")
   (cons "Psi" "Ψ")
   (cons "Omega" "Ω")
   (cons "pm" "±")
   (cons "mp" "∓")
   (cons "times" "×")
   (cons "div" "÷")
   (cons "cdot" "·")
   (cons "ast" "∗")
   (cons "star" "⋆")
   (cons "circ" "∘")
   (cons "bullet" "•")
   (cons "oplus" "⊕")
   (cons "ominus" "⊖")
   (cons "otimes" "⊗")
   (cons "oslash" "⊘")
   (cons "odot" "⊙")
   (cons "bigcirc" "○")
   (cons "dagger" "†")
   (cons "ddagger" "‡")
   (cons "amalg" "⨿")
   (cons "uplus" "⊎")
   (cons "sqcap" "⊓")
   (cons "sqcup" "⊔")
   (cons "triangleleft" "◁")
   (cons "triangleright" "▷")
   (cons "wr" "≀")
   (cons "cap" "∩")
   (cons "cup" "∪")
   (cons "bigcap" "⋂")
   (cons "bigcup" "⋃")
   (cons "bigwedge" "⋀")
   (cons "bigvee" "⋁")
   (cons "bigsqcup" "⨆")
   (cons "biguplus" "⨄")
   (cons "bigoplus" "⨁")
   (cons "bigotimes" "⨂")
   (cons "bigodot" "⨀")
   (cons "setminus" "∖")
   (cons "in" "∈")
   (cons "notin" "∉")
   (cons "ni" "∋")
   (cons "subset" "⊂")
   (cons "supset" "⊃")
   (cons "subseteq" "⊆")
   (cons "supseteq" "⊇")
   (cons "sqsubset" "⊏")
   (cons "sqsupset" "⊐")
   (cons "sqsubseteq" "⊑")
   (cons "sqsupseteq" "⊒")
   (cons "prec" "≺")
   (cons "preceq" "≼")
   (cons "succ" "≻")
   (cons "succeq" "≽")
   (cons "ll" "≪")
   (cons "gg" "≫")
   (cons "le" "≤")
   (cons "leq" "≤")
   (cons "leqslant" "≤")
   (cons "ge" "≥")
   (cons "geq" "≥")
   (cons "geqslant" "≥")
   (cons "ne" "≠")
   (cons "neq" "≠")
   (cons "equiv" "≡")
   (cons "approx" "≈")
   (cons "sim" "∼")
   (cons "simeq" "≃")
   (cons "cong" "≅")
   (cons "asymp" "≍")
   (cons "doteq" "≐")
   (cons "propto" "∝")
   (cons "parallel" "∥")
   (cons "perp" "⊥")
   (cons "mid" "∣")
   (cons "vdash" "⊢")
   (cons "dashv" "⊣")
   (cons "models" "⊨")
   (cons "Vdash" "⊩")
   (cons "Vvdash" "⊪")
   (cons "nvdash" "⊬")
   (cons "nvDash" "⊭")
   (cons "forall" "∀")
   (cons "exists" "∃")
   (cons "nexists" "∄")
   (cons "neg" "¬")
   (cons "land" "∧")
   (cons "wedge" "∧")
   (cons "lor" "∨")
   (cons "vee" "∨")
   (cons "to" "→")
   (cons "rightarrow" "→")
   (cons "longrightarrow" "→")
   (cons "leftarrow" "←")
   (cons "longleftarrow" "←")
   (cons "gets" "←")
   (cons "leftrightarrow" "↔")
   (cons "longleftrightarrow" "↔")
   (cons "hookleftarrow" "↩")
   (cons "hookrightarrow" "↪")
   (cons "twoheadleftarrow" "↞")
   (cons "twoheadrightarrow" "↠")
   (cons "leftharpoonup" "↼")
   (cons "leftharpoondown" "↽")
   (cons "rightharpoonup" "⇀")
   (cons "rightharpoondown" "⇁")
   (cons "rightleftharpoons" "⇌")
   (cons "leftrightharpoons" "⇋")
   (cons "nearrow" "↗")
   (cons "searrow" "↘")
   (cons "swarrow" "↙")
   (cons "nwarrow" "↖")
   (cons "rightsquigarrow" "⇝")
   (cons "leadsto" "⇝")
   (cons "Rightarrow" "⇒")
   (cons "Longrightarrow" "⇒")
   (cons "Leftarrow" "⇐")
   (cons "Longleftarrow" "⇐")
   (cons "Leftrightarrow" "⇔")
   (cons "Longleftrightarrow" "⇔")
   (cons "implies" "⇒")
   (cons "iff" "⇔")
   (cons "mapsto" "↦")
   (cons "longmapsto" "↦")
   (cons "uparrow" "↑")
   (cons "downarrow" "↓")
   (cons "partial" "∂")
   (cons "nabla" "∇")
   (cons "int" "∫")
   (cons "iint" "∬")
   (cons "iiint" "∭")
   (cons "oint" "∮")
   (cons "sum" "∑")
   (cons "prod" "∏")
   (cons "coprod" "∐")
   (cons "infty" "∞")
   (cons "emptyset" "∅")
   (cons "varnothing" "∅")
   (cons "angle" "∠")
   (cons "therefore" "∴")
   (cons "because" "∵")
   (cons "aleph" "ℵ")
   (cons "beth" "ℶ")
   (cons "gimel" "ℷ")
   (cons "daleth" "ℸ")
   (cons "top" "⊤")
   (cons "bot" "⊥")
   (cons "triangle" "△")
   (cons "square" "□")
   (cons "lozenge" "◊")
   (cons "checkmark" "✓")
   (cons "complement" "∁")
   (cons "wp" "℘")
   (cons "prime" "′")
   (cons "ldots" "…")
   (cons "dots" "…")
   (cons "cdots" "⋯")
   (cons "vdots" "⋮")
   (cons "ddots" "⋱")
   (cons "ell" "ℓ")
   (cons "hbar" "ℏ")
   (cons "Im" "ℑ")
   (cons "Re" "ℜ")
   (cons "langle" "⟨")
   (cons "rangle" "⟩")
   (cons "vert" "|")
   (cons "lvert" "|")
   (cons "rvert" "|")
   (cons "Vert" "‖")
   (cons "lVert" "‖")
   (cons "rVert" "‖")
   (cons "lbrace" "{")
   (cons "rbrace" "}")
   (cons "backslash" "\\")
   (cons "lfloor" "⌊")
   (cons "rfloor" "⌋")
   (cons "lceil" "⌈")
   (cons "rceil" "⌉")
   (cons "colon" ":")
   ))
(defparameter +latex-negated-symbols+
  (list
   (cons "<" "≮")
   (cons ">" "≯")
   (cons "=" "≠")
   (cons "∈" "∉")
   (cons "∋" "∌")
   (cons "∣" "∤")
   (cons "∥" "∦")
   (cons "∼" "≁")
   (cons "≃" "≄")
   (cons "≅" "≇")
   (cons "≈" "≉")
   (cons "≡" "≢")
   (cons "≤" "≰")
   (cons "≥" "≱")
   (cons "≺" "⊀")
   (cons "≻" "⊁")
   (cons "⊂" "⊄")
   (cons "⊃" "⊅")
   (cons "⊆" "⊈")
   (cons "⊇" "⊉")
   (cons "⊢" "⊬")
   (cons "⊨" "⊭")
   (cons "↔" "↮")
   (cons "←" "↚")
   (cons "→" "↛")
   (cons "⇒" "⇏")
   (cons "⇐" "⇍")
   (cons "⇔" "⇎")
   (cons "≼" "⋠")
   (cons "≽" "⋡")
   ))
(defparameter +latex-blackboard+
  (list
   (cons "C" "ℂ")
   (cons "H" "ℍ")
   (cons "N" "ℕ")
   (cons "P" "ℙ")
   (cons "Q" "ℚ")
   (cons "R" "ℝ")
   (cons "Z" "ℤ")
   ))
(defparameter +latex-superscripts+
  (list
   (cons "0" "⁰")
   (cons "1" "¹")
   (cons "2" "²")
   (cons "3" "³")
   (cons "4" "⁴")
   (cons "5" "⁵")
   (cons "6" "⁶")
   (cons "7" "⁷")
   (cons "8" "⁸")
   (cons "9" "⁹")
   (cons "+" "⁺")
   (cons "-" "⁻")
   (cons "=" "⁼")
   (cons "(" "⁽")
   (cons ")" "⁾")
   (cons "a" "ᵃ")
   (cons "b" "ᵇ")
   (cons "c" "ᶜ")
   (cons "d" "ᵈ")
   (cons "e" "ᵉ")
   (cons "f" "ᶠ")
   (cons "g" "ᵍ")
   (cons "h" "ʰ")
   (cons "i" "ⁱ")
   (cons "j" "ʲ")
   (cons "k" "ᵏ")
   (cons "l" "ˡ")
   (cons "m" "ᵐ")
   (cons "n" "ⁿ")
   (cons "o" "ᵒ")
   (cons "p" "ᵖ")
   (cons "r" "ʳ")
   (cons "s" "ˢ")
   (cons "t" "ᵗ")
   (cons "u" "ᵘ")
   (cons "v" "ᵛ")
   (cons "w" "ʷ")
   (cons "x" "ˣ")
   (cons "y" "ʸ")
   (cons "z" "ᶻ")
   ))
(defparameter +latex-subscripts+
  (list
   (cons "0" "₀")
   (cons "1" "₁")
   (cons "2" "₂")
   (cons "3" "₃")
   (cons "4" "₄")
   (cons "5" "₅")
   (cons "6" "₆")
   (cons "7" "₇")
   (cons "8" "₈")
   (cons "9" "₉")
   (cons "+" "₊")
   (cons "-" "₋")
   (cons "=" "₌")
   (cons "(" "₍")
   (cons ")" "₎")
   (cons "a" "ₐ")
   (cons "e" "ₑ")
   (cons "h" "ₕ")
   (cons "i" "ᵢ")
   (cons "j" "ⱼ")
   (cons "k" "ₖ")
   (cons "l" "ₗ")
   (cons "m" "ₘ")
   (cons "n" "ₙ")
   (cons "o" "ₒ")
   (cons "p" "ₚ")
   (cons "r" "ᵣ")
   (cons "s" "ₛ")
   (cons "t" "ₜ")
   (cons "u" "ᵤ")
   (cons "v" "ᵥ")
   (cons "x" "ₓ")
   ))
(defparameter +latex-accents+
  (list
   (cons "acute" "́")
   (cons "bar" "̅")
   (cons "breve" "̆")
   (cons "check" "̌")
   (cons "ddot" "̈")
   (cons "dot" "̇")
   (cons "grave" "̀")
   (cons "hat" "̂")
   (cons "mathring" "̊")
   (cons "overleftarrow" "⃖")
   (cons "overleftrightarrow" "⃡")
   (cons "overline" "̅")
   (cons "overrightarrow" "⃗")
   (cons "tilde" "̃")
   (cons "underline" "̲")
   (cons "vec" "⃗")
   (cons "widehat" "̂")
   (cons "widetilde" "̃")
   ))
(defparameter +latex-named-operators+
  (list
   "arccos"
   "arcsin"
   "arctan"
   "arg"
   "cos"
   "cosh"
   "cot"
   "coth"
   "csc"
   "deg"
   "det"
   "dim"
   "exp"
   "gcd"
   "hom"
   "inf"
   "ker"
   "lg"
   "lim"
   "liminf"
   "limsup"
   "ln"
   "log"
   "max"
   "min"
   "Pr"
   "sec"
   "sin"
   "sinh"
   "sup"
   "tan"
   "tanh"
   ))
(defparameter +latex-limit-operators+
  (list
   "argmax"
   "argmin"
   "inf"
   "injlim"
   "lim"
   "liminf"
   "limsup"
   "max"
   "min"
   "projlim"
   "sup"
   ))
(defparameter +latex-display-limit-symbols+
  (list
   "bigcap"
   "bigcup"
   "bigodot"
   "bigoplus"
   "bigotimes"
   "bigsqcup"
   "biguplus"
   "bigvee"
   "bigwedge"
   "coprod"
   "int"
   "iint"
   "iiint"
   "oint"
   "prod"
   "sum"
   ))
(defparameter +latex-relation-commands+
  (list
   "Leftarrow"
   "Leftrightarrow"
   "Longleftarrow"
   "Longleftrightarrow"
   "Longrightarrow"
   "Rightarrow"
   "Vdash"
   "Vvdash"
   "approx"
   "asymp"
   "cong"
   "dashv"
   "doteq"
   "downarrow"
   "equiv"
   "ge"
   "geq"
   "geqslant"
   "gets"
   "gg"
   "hookleftarrow"
   "hookrightarrow"
   "iff"
   "implies"
   "in"
   "leadsto"
   "le"
   "leftarrow"
   "leftharpoondown"
   "leftharpoonup"
   "leftrightarrow"
   "leftrightharpoons"
   "leq"
   "leqslant"
   "ll"
   "longleftarrow"
   "longleftrightarrow"
   "longmapsto"
   "longrightarrow"
   "mapsto"
   "mid"
   "models"
   "ne"
   "nearrow"
   "neq"
   "ni"
   "notin"
   "nvdash"
   "nvDash"
   "nwarrow"
   "parallel"
   "perp"
   "prec"
   "preceq"
   "propto"
   "rightharpoondown"
   "rightharpoonup"
   "rightleftharpoons"
   "rightarrow"
   "rightsquigarrow"
   "searrow"
   "sim"
   "simeq"
   "sqsubset"
   "sqsubseteq"
   "sqsupset"
   "sqsupseteq"
   "subset"
   "subseteq"
   "succ"
   "succeq"
   "supset"
   "supseteq"
   "swarrow"
   "to"
   "triangleleft"
   "triangleright"
   "twoheadleftarrow"
   "twoheadrightarrow"
   "uparrow"
   "vdash"
   ))
(defparameter +latex-spacing-commands+
  (list
   ""
   ""
   ":"
   ";"
   " "
   ">"
   "enspace"
   "enskip"
   "medspace"
   "quad"
   "qquad"
   "thickspace"
   "thinspace"
   ))
(defparameter +latex-negative-spacing-commands+
  (list
   "!"
   "negmedspace"
   "negthickspace"
   "negthinspace"
   ))
(defparameter +latex-ignored-commands+
  (list
   "displaystyle"
   "limits"
   "nolimits"
   "scriptstyle"
   "scriptscriptstyle"
   "textstyle"
   ))
(defparameter +latex-size-commands+
  (list
   "big"
   "Big"
   "bigg"
   "Bigg"
   "bigl"
   "Bigl"
   "biggl"
   "Biggl"
   "bigr"
   "Bigr"
   "biggr"
   "Biggr"
   ))
(defparameter +latex-plain-wrappers+
  (list
   "emph"
   "mathcal"
   "mathbf"
   "mathfrak"
   "mathit"
   "mathrm"
   "mathnormal"
   "mathscr"
   "mathsf"
   "mathtt"
   "mathup"
   "mbox"
   "overbrace"
   "pmb"
   "smash"
   "substack"
   "text"
   "textbf"
   "textit"
   "textmd"
   "textnormal"
   "textrm"
   "textsc"
   "textsf"
   "textsl"
   "texttt"
   "textup"
   "underbrace"
   "bm"
   "boldsymbol"
   ))

(defun latex-letter-p (character)
  ;; \p{L}: SBCL's alphanumericp is Unicode-aware; digits excluded.
  (and (alphanumericp character)
       (not (digit-char-p character))))

(defun latex-number-p (character)
  ;; \p{N}: ASCII digits plus the common Nd blocks.
  (or (digit-char-p character)
      (let ((value (codepoint character)))
        (or (between-p value #x0660 #x0669)
            (between-p value #x06f0 #x06f9)
            (between-p value #x0966 #x096f)
            (between-p value #x09e6 #x09ef)
            (between-p value #x0b66 #x0b6f)
            (between-p value #x0be6 #x0bef)
            (between-p value #x0c66 #x0c6f)
            (between-p value #x0d66 #x0d6f)
            (between-p value #x0e50 #x0e59)
            (between-p value #x0ed0 #x0ed9)
            (between-p value #xff10 #xff19)))))

(defun latex-letter-or-number-p (character)
  (or (latex-letter-p character)
      (latex-number-p character)))

(defun js-whitespace-p (character)
  ;; JavaScript \s: tab, LF, VT, FF, CR, space, NBSP, and the Unicode
  ;; space separators.
  (or (find character
            '(#\Tab #\Newline #\Page #\Return #\Space)
            :test #'char=)
      (let ((value (codepoint character)))
        (or (= value #x0b) (= value #x0c) (= value #xa0)
            (= value #x1680) (between-p value #x2000 #x200a)
            (= value #x2028) (= value #x2029) (= value #x202f)
            (= value #x205f) (= value #x3000) (= value #xfeff)))))

(defun latex-trim (value)
  (string-trim
   '(#\Tab #\Newline #\Page #\Return #\Space)
   value))

(defun latex-trim-end (value)
  (string-right-trim
   '(#\Tab #\Newline #\Page #\Return #\Space)
   value))

(defun latex-trim-start (value)
  (string-left-trim
   '(#\Tab #\Newline #\Page #\Return #\Space)
   value))

(defparameter +latex-negative-space+ (string (code-char 0)))
(defparameter +latex-operator-start+ (string (code-char #xf004)))
(defparameter +latex-operator-end+ (string (code-char #xf005)))
(defparameter +latex-layout-marker-start+ (string (code-char #xf000)))
(defparameter +latex-layout-marker-end+ (string (code-char #xf001)))
(defparameter +latex-protected-space+ (string (code-char #xf002)))

(defun latex-table-lookup (table key)
  (cdr (assoc key table :test #'string=)))

(defun latex-replace-characters (value table)
  (let ((result (make-string-output-stream)))
    (loop for character across value
          for replacement =
            (latex-table-lookup table (string character))
          do (unless replacement
               (return-from latex-replace-characters nil))
             (write-string replacement result))
    (get-output-stream-string result)))

(defun latex-format-script (value kind)
  (setf value (latex-trim value))
  (let ((unicode
          (latex-replace-characters
           (cl-ppcre:regex-replace-all
            "\\s*([=+-])\\s*" value "\\1")
           (if (eq kind :sub)
               +latex-subscripts+
               +latex-superscripts+))))
    (when unicode
      (return-from latex-format-script unicode)))
  (let ((prefix (if (eq kind :sub) "_" "^")))
    (if (or (= (length value) 1)
            (and (eq kind :sub)
                 (every (lambda (c)
                          (or (and (char>= c #\a) (char<= c #\z))
                              (and (char>= c #\A) (char<= c #\Z))))
                        value)))
        (format nil "~A~A" prefix value)
        (format nil "~A(~A)" prefix value))))

(defun latex-simple-word-p (value)
  ;; /^[\p{L}\p{N}.]+$/u
  (and (plusp (length value))
       (every (lambda (c)
                (or (char= c #\.)
                    (latex-letter-or-number-p c)))
              value)))

(defun latex-format-fraction (numerator denominator)
  (setf numerator (latex-trim numerator)
        denominator (latex-trim denominator))
  (format nil "~A/~A"
          (if (latex-simple-word-p numerator)
              numerator
              (format nil "(~A)" numerator))
          (if (or (and (plusp (length denominator))
                       (every (lambda (c)
                                (or (char= c #\.)
                                    (latex-number-p c)))
                              denominator))
                  (= (length denominator) 1))
              denominator
              (format nil "(~A)" denominator))))

(defun latex-format-root (value &optional (symbol "√"))
  (setf value (latex-trim value))
  (if (latex-simple-word-p value)
      (format nil "~A~A" symbol value)
      (format nil "~A(~A)" symbol value)))

(defun latex-ends-with-p (value suffix)
  (and (>= (length value) (length suffix))
       (string= suffix value
                :start2 (- (length value) (length suffix)))))

(defun latex-normalize-output (value)
  ;; The baseline's lookaround regexes reduce to single-character
  ;; marker handling: a start marker becomes a space after
  ;; [letter/number/)/]/}/layout-end] and is removed otherwise; an end
  ;; marker becomes a space before [letter/number/root/layout-start].
  (let* ((start-marker (code-char #xf004))
         (end-marker (code-char #xf005))
         (layout-start (code-char #xf000))
         (layout-end (code-char #xf001))
         (pass1
           (with-output-to-string (stream)
             (loop for index from 0 below (length value)
                   for character = (char value index)
                   do (if (char= character start-marker)
                          (let ((previous
                                  (and (plusp index)
                                       (char value (1- index)))))
                            (when (and previous
                                       (or (latex-letter-or-number-p
                                            previous)
                                           (find previous ")]}"
                                                 :test #'char=)
                                           (char= previous
                                                  layout-end)))
                              (write-char #\Space stream)))
                          (write-char character stream)))))
         (pass2
           (with-output-to-string (stream)
             (loop for index from 0 below (length pass1)
                   for character = (char pass1 index)
                   do (if (char= character end-marker)
                          (let ((next
                                  (and (< (1+ index) (length pass1))
                                       (char pass1 (1+ index)))))
                            (when (and next
                                       (or (latex-letter-or-number-p
                                            next)
                                           (char= next #\√)
                                           (char= next
                                                  layout-start)))
                              (write-char #\Space stream)))
                          (write-char character stream)))))
         (clean
           (literal-string-replace-all
            pass2 +latex-operator-end+ ""))
         (lines
           (loop for line in
                   (cl-ppcre:split "\\n" clean)
                 collect
                 (latex-trim
                  (cl-ppcre:regex-replace-all
                   "[ \\t]+" line " ")))))
    (latex-trim
     (format nil "~{~A~^~%~}"
             (loop for line in lines
                   for index from 0
                   when (or (plusp (length line))
                            (and (plusp index)
                                 (< index (1- (length lines)))))
                   collect line)))))

(defstruct (latex-fraction-node
            (:constructor make-latex-fraction-node))
  numerator denominator)

(defstruct (latex-operator-node
            (:constructor make-latex-operator-node))
  operator lower upper)

(defstruct (latex-matrix-node
            (:constructor make-latex-matrix-node))
  (lines nil :type list)
  (baseline 0 :type integer))

(defstruct (latex-layout
            (:constructor make-latex-layout))
  (lines nil :type list)
  (width 0 :type integer)
  (baseline 0 :type integer))

(defun latex-pad-layout-line (line width &optional centered)
  (let ((padding
          (max 0 (- width (visible-width line)))))
    (if centered
        (let ((left (floor padding 2)))
          (format nil "~VA~A~VA"
                  left "" line
                  (max 0 (- padding left)) ""))
        (format nil "~A~VA" line padding ""))))

(defun latex-join-layouts (layouts)
  (when (null layouts)
    (return-from latex-join-layouts
      (make-latex-layout :lines (list ""))))
  (let* ((baseline
           (reduce #'max layouts
                   :key #'latex-layout-baseline))
         (below
           (reduce #'max layouts
                   :key (lambda (layout)
                          (- (length (latex-layout-lines layout))
                             (latex-layout-baseline layout)
                             1))))
         (lines nil))
    (loop for row from 0 to (+ baseline below)
          do (let ((line
                     (with-output-to-string (stream)
                       (dolist (layout layouts)
                         (let ((source-row
                                 (+ (- row baseline)
                                    (latex-layout-baseline layout))))
                           (write-string
                            (if (and (>= source-row 0)
                                     (< source-row
                                        (length
                                         (latex-layout-lines layout))))
                                (latex-pad-layout-line
                                 (nth source-row
                                      (latex-layout-lines layout))
                                 (latex-layout-width layout))
                                (format nil "~VA"
                                        (latex-layout-width layout)
                                        ""))
                            stream))))))
               (push (latex-trim-end line) lines)))
    (make-latex-layout
     :lines (nreverse lines)
     :width (reduce #'+ layouts :key #'latex-layout-width)
     :baseline baseline)))

(defun latex-render-layout (source nodes)
  (let ((rendered-lines nil)
        (first-baseline 0))
    (dolist (source-line (cl-ppcre:split "\\n" source))
      (let ((layouts nil)
            (position 0)
            (previous-node nil))
        (cl-ppcre:do-register-groups
            (index-string)
            ((format nil "~C([0-9]+)~C"
                     (code-char #xf000) (code-char #xf001))
             source-line)
          (let* ((marker
                   (format nil "~C~A~C"
                           (code-char #xf000) index-string
                           (code-char #xf001)))
                 (index
                   (cl-ppcre:scan
                    (format nil "~C[0-9]+~C"
                            (code-char #xf000) (code-char #xf001))
                    source-line))
                 ;; do-register-groups does not expose match offsets;
                 ;; find this marker from the current position.
                 (at
                   (search marker source-line :start2 position))
                 (node
                   (nth (parse-integer index-string) nodes)))
            (declare (ignore index))
            (when (and at node)
              (when (> at position)
                (let* ((sliced
                         (subseq source-line position at))
                       (trimmed
                         (latex-trim-end
                          (if previous-node
                              (latex-trim-start sliced)
                              sliced)))
                       (preserve-leading
                         (and (typep previous-node
                                     'latex-matrix-node)
                              (plusp (length sliced))
                              (js-whitespace-p
                               (char sliced 0))))
                       (preserve-trailing
                         (and (typep node 'latex-matrix-node)
                              (plusp (length sliced))
                              (js-whitespace-p
                               (char sliced
                                     (1- (length sliced))))))
                       (text
                         (cond
                           ((plusp (length trimmed))
                            (format nil "~A~A~A"
                                    (if preserve-leading " " "")
                                    trimmed
                                    (if preserve-trailing " " "")))
                           ((or preserve-leading
                                preserve-trailing)
                            " ")
                           (t ""))))
                  (push (make-latex-layout
                         :lines (list text)
                         :width (visible-width text))
                        layouts)))
              (cond
                ((typep node 'latex-fraction-node)
                 (let* ((numerator
                          (latex-render-layout
                           (latex-fraction-node-numerator node)
                           nodes))
                        (denominator
                          (latex-render-layout
                           (latex-fraction-node-denominator node)
                           nodes))
                        (content-width
                          (max (latex-layout-width numerator)
                               (latex-layout-width denominator)
                               1))
                        (width (+ content-width 2)))
                   (push
                    (make-latex-layout
                     :lines
                     (append
                      (mapcar
                       (lambda (line)
                         (latex-pad-layout-line
                          line width t))
                       (latex-layout-lines numerator))
                      (list
                       (format nil " ~A "
                               (make-string
                                content-width
                                :initial-element #\─)))
                      (mapcar
                       (lambda (line)
                         (latex-pad-layout-line
                          line width t))
                       (latex-layout-lines denominator)))
                     :width width
                     :baseline
                     (length (latex-layout-lines numerator)))
                    layouts)))
                ((typep node 'latex-operator-node)
                 (let ((content-width
                         (max
                          (visible-width
                           (latex-operator-node-operator node))
                          (if (latex-operator-node-lower node)
                              (visible-width
                               (latex-operator-node-lower node))
                              0)
                          (if (latex-operator-node-upper node)
                              (visible-width
                               (latex-operator-node-upper node))
                              0))))
                   (push
                    (make-latex-layout
                     :lines
                     (append
                      (when (latex-operator-node-upper node)
                        (list
                         (format nil "~A "
                                 (latex-pad-layout-line
                                  (latex-operator-node-upper node)
                                  content-width t))))
                      (list
                       (format nil "~A "
                               (latex-pad-layout-line
                                (latex-operator-node-operator node)
                                content-width t)))
                      (when (latex-operator-node-lower node)
                        (list
                         (format nil "~A "
                                 (latex-pad-layout-line
                                  (latex-operator-node-lower node)
                                  content-width t)))))
                     :width (1+ content-width)
                     :baseline
                     (if (latex-operator-node-upper node) 1 0))
                    layouts)))
                (t
                 (let ((width
                         (max 0
                              (reduce #'max
                                      (mapcar #'visible-width
                                              (latex-matrix-node-lines
                                               node))
                                      :initial-value 0))))
                   (push
                    (make-latex-layout
                     :lines
                     (mapcar
                      (lambda (line)
                        (latex-pad-layout-line line width))
                      (latex-matrix-node-lines node))
                     :width width
                     :baseline (latex-matrix-node-baseline node))
                    layouts))))
              (setf position (+ at (length marker))
                    previous-node node))))
        (when (< position (length source-line))
          (let* ((sliced (subseq source-line position))
                 (trimmed
                   (if previous-node
                       (latex-trim-start sliced)
                       sliced))
                 (text
                   (if (and (typep previous-node
                                   'latex-matrix-node)
                            (plusp (length sliced))
                            (js-whitespace-p (char sliced 0)))
                       (format nil " ~A" trimmed)
                       trimmed)))
            (push (make-latex-layout
                   :lines (list text)
                   :width (visible-width text))
                  layouts)))
        (let ((line-layout
                (latex-join-layouts (nreverse layouts))))
          (when (null rendered-lines)
            (setf first-baseline
                  (latex-layout-baseline line-layout)))
          (setf rendered-lines
                (nconc rendered-lines
                       (latex-layout-lines line-layout))))))
    (make-latex-layout
     :lines rendered-lines
     :width
     (max 0
          (reduce #'max
                  (mapcar #'visible-width rendered-lines)
                  :initial-value 0))
     :baseline first-baseline)))

(defstruct (latex-parser
            (:constructor %make-latex-parser))
  (source "" :type string)
  (layout-nodes nil :type list)
  (display-p nil :type boolean)
  (position 0 :type integer)
  (supported-p t :type boolean)
  (stack-fractions-p t :type boolean))

(defun make-latex-parser (source layout-nodes display-p)
  (%make-latex-parser
   :source source :layout-nodes layout-nodes
   :display-p display-p))

(defun latex-parser-done-p (parser)
  (>= (latex-parser-position parser)
      (length (latex-parser-source parser))))

(defun latex-parser-peek (parser &optional (offset 0))
  (let ((index (+ (latex-parser-position parser) offset)))
    (and (< index (length (latex-parser-source parser)))
         (char (latex-parser-source parser) index))))

(defun latex-parser-render (parser)
  (let ((rendered (latex-parse-sequence parser nil)))
    (if (or (not (latex-parser-supported-p parser))
            (/= (latex-parser-position parser)
                (length (latex-parser-source parser))))
        nil
        (latex-normalize-output rendered))))

(defun latex-trailing-layout-matrix-node (parser value)
  ;; The layout node referenced by a trailing <start>digits<end>
  ;; marker, or NIL.
  (when (latex-ends-with-p value +latex-layout-marker-end+)
    (let ((start
            (search +latex-layout-marker-start+
                    value :from-end t)))
      (when start
        (let ((digits
                (subseq value (1+ start)
                        (1- (length value)))))
          (and (plusp (length digits))
               (every #'digit-char-p digits)
               (nth (parse-integer digits)
                    (latex-parser-layout-nodes parser))))))))

(defun latex-parse-sequence (parser end-character)
  (let ((result (make-string-output-stream)))
    (loop
      (when (latex-parser-done-p parser)
        (when end-character
          (setf (latex-parser-supported-p parser) nil))
        (return))
      (let ((character (latex-parser-peek parser)))
        (when (and end-character
                   (char= character end-character))
          (incf (latex-parser-position parser))
          (return))
        (cond
          ((char= character #\})
           (setf (latex-parser-supported-p parser) nil)
           (return))
          ((char= character #\{)
           (incf (latex-parser-position parser))
           (write-string
            (latex-parse-sequence parser #\})
            result))
          ((char= character #\Backslash)
           (let ((command (latex-parse-command parser)))
             (if (string= command +latex-negative-space+)
                 (let ((trimmed
                         (latex-trim-end
                          (get-output-stream-string result))))
                   (when (latex-ends-with-p
                          trimmed +latex-operator-end+)
                     (setf trimmed
                           (subseq trimmed 0
                                   (- (length trimmed)
                                      (length
                                       +latex-operator-end+)))))
                   (write-string trimmed result))
                 (write-string command result))))
          ((or (char= character #\^) (char= character #\_))
           (incf (latex-parser-position parser))
           (let* ((current
                    (latex-trim-end
                     (get-output-stream-string result)))
                  (script
                    (latex-format-script
                     (latex-parse-required-argument parser nil)
                     (if (char= character #\_) :sub :sup))))
             (if (latex-ends-with-p
                  current +latex-operator-end+)
                 (write-string
                  (format nil "~A~A~A"
                          (subseq current 0
                                  (- (length current)
                                     (length
                                      +latex-operator-end+)))
                          script +latex-operator-end+)
                  result)
                 (write-string
                  (format nil "~A~A" current script)
                  result))))
          ((js-whitespace-p character)
           (write-string (latex-parse-whitespace parser) result))
          ((member character '(#\= #\< #\>) :test #'char=)
           (write-string
            (format nil "~A ~C "
                    (latex-trim-end
                     (get-output-stream-string result))
                    character)
            result)
           (incf (latex-parser-position parser)))
          ((char= character #\&)
           (incf (latex-parser-position parser)))
          ((char= character #\~)
           (incf (latex-parser-position parser))
           (write-char #\Space result))
          (t
           (let ((current
                   (get-output-stream-string result)))
             (if (char= character #\.)
                 ;; A period directly after a matrix marker joins the
                 ;; matrix's last line.
                 (let ((node
                         (latex-trailing-layout-matrix-node
                          parser current)))
                   (if (typep node 'latex-matrix-node)
                       (let ((last
                               (1- (length
                                    (latex-matrix-node-lines
                                     node)))))
                         (setf
                          (nth last
                               (latex-matrix-node-lines node))
                          (format nil "~A~C"
                                  (nth last
                                       (latex-matrix-node-lines
                                        node))
                                  character))
                         (write-string current result)
                         (incf
                          (latex-parser-position parser)))
                       (progn
                         (write-string current result)
                         (write-char character result)
                         (incf
                          (latex-parser-position parser)))))
                 (progn
                   (write-string current result)
                   (write-char character result)
                   (incf
                    (latex-parser-position parser)))))))))
    (get-output-stream-string result)))

(defun latex-parse-whitespace (parser)
  (loop while (and (not (latex-parser-done-p parser))
                   (js-whitespace-p
                    (latex-parser-peek parser)))
        do (incf (latex-parser-position parser)))
  " ")

(defun latex-parse-command (parser)
  (incf (latex-parser-position parser))
  (when (latex-parser-done-p parser)
    (setf (latex-parser-supported-p parser) nil)
    (return-from latex-parse-command ""))
  (let ((command nil)
        (first (latex-parser-peek parser)))
    (if (and first
             (or (and (char>= first #\a) (char<= first #\z))
                 (and (char>= first #\A) (char<= first #\Z))))
        (let ((start (latex-parser-position parser)))
          (loop while (and (not (latex-parser-done-p parser))
                           (let ((c (latex-parser-peek parser)))
                             (or (and (char>= c #\a)
                                      (char<= c #\z))
                                 (and (char>= c #\A)
                                      (char<= c #\Z)))))
                do (incf (latex-parser-position parser)))
          (setf command
                (subseq (latex-parser-source parser)
                        start
                        (latex-parser-position parser))))
        (progn
          (setf command (string first))
          (incf (latex-parser-position parser))))
    (cond
      ((string= command "\\")
       (format nil "~%"))
      ((member command +latex-spacing-commands+ :test #'string=)
       " ")
      ((member command +latex-negative-spacing-commands+
               :test #'string=)
       +latex-negative-space+)
      ((member command +latex-ignored-commands+ :test #'string=)
       "")
      ((member command '("{" "}" "$" "%" "#" "_" "&")
               :test #'string=)
       command)
      ((string= command "|")
       "‖")
      ((string= command "not")
       (let* ((value
                (latex-trim
                 (latex-parse-required-argument parser nil)))
              (negated
                (latex-table-lookup +latex-negated-symbols+ value)))
         (cond
           (negated (format nil " ~A " negated))
           ((zerop (length value))
            (setf (latex-parser-supported-p parser) nil)
            "")
           (t
            (format nil " ~C̸~A "
                    (char value 0)
                    (subseq value 1))))))
      ((member command +latex-limit-operators+ :test #'string=)
       (latex-parse-operator parser command :bracket t t))
      ((latex-table-lookup +latex-symbols+ command)
       (let ((symbol
               (latex-table-lookup +latex-symbols+ command)))
         (if (member command +latex-display-limit-symbols+
                     :test #'string=)
             (latex-parse-operator parser symbol :script t)
             (if (or (string= command "cdot")
                     (string= command "times")
                     (member command +latex-relation-commands+
                             :test #'string=))
                 (format nil " ~A " symbol)
                 symbol))))
      ((member command +latex-named-operators+ :test #'string=)
       (format nil "~A~A~A"
               +latex-operator-start+ command
               +latex-operator-end+))
      ((member command +latex-size-commands+ :test #'string=)
       "")
      ((member command '("left" "middle" "right") :test #'string=)
       (when (and (latex-parser-peek parser)
                  (char= (latex-parser-peek parser) #\.))
         (incf (latex-parser-position parser)))
       "")
      ((member command '("frac" "dfrac" "tfrac") :test #'string=)
       (let ((should-stack
               (and (latex-parser-display-p parser)
                    (latex-parser-stack-fractions-p parser)
                    (not (string= command "tfrac")))))
         (let ((numerator
                 (latex-parse-required-argument
                  parser (not should-stack)))
               (denominator
                 (latex-parse-required-argument
                  parser (not should-stack))))
           (if should-stack
               (let ((index
                       (length
                        (latex-parser-layout-nodes parser))))
                 (setf
                  (latex-parser-layout-nodes parser)
                  (append
                   (latex-parser-layout-nodes parser)
                   (list
                    (make-latex-fraction-node
                     :numerator
                     (latex-normalize-output numerator)
                     :denominator
                     (latex-normalize-output denominator)))))
                 (format nil "~C~D~C"
                         (code-char #xf000) index
                         (code-char #xf001)))
               (latex-format-fraction numerator denominator)))))
      ((string= command "sqrt")
       (let ((degree
               (let ((optional
                       (latex-parse-optional-argument parser)))
                 (and optional (latex-trim optional))))
             (value
               (latex-parse-required-argument parser)))
         (cond
           ((or (null degree) (string= degree "2"))
            (latex-format-root value))
           ((string= degree "3")
            (latex-format-root value "∛"))
           ((string= degree "4")
            (latex-format-root value "∜"))
           (t
            (format nil "~A~A"
                    (latex-format-script degree :sup)
                    (latex-format-root value))))))
      ((member command '("boxed" "fbox") :test #'string=)
       (format nil "[~A]"
               (latex-trim
                (latex-parse-required-argument parser))))
      ((member command '("binom" "dbinom" "tbinom") :test #'string=)
       (format nil "(~A choose ~A)"
               (latex-parse-required-argument parser)
               (latex-parse-required-argument parser)))
      ((latex-table-lookup +latex-accents+ command)
       (let ((accent
               (latex-table-lookup +latex-accents+ command))
             (value
               (latex-parse-required-argument parser)))
         (if (= (length value) 1)
             (format nil "~A~A" value accent)
             (format nil "~A(~A)" command value))))
      ((string= command "mathbb")
       (let ((value
               (latex-parse-required-argument parser)))
         (with-output-to-string (stream)
           (loop for character across value
                 do (write-string
                     (or
                      (latex-table-lookup
                       +latex-blackboard+ (string character))
                      (string character))
                     stream)))))
      ((string= command "operatorname")
       (let ((starred
               (and (latex-parser-peek parser)
                    (char= (latex-parser-peek parser) #\*))))
         (when starred
           (incf (latex-parser-position parser)))
         (let ((operator
                 (latex-trim
                  (latex-normalize-output
                   (latex-parse-required-argument parser)))))
           (latex-parse-operator
            parser operator :bracket starred t))))
      ((member command '("mod" "bmod") :test #'string=)
       " mod ")
      ((member command '("pmod" "pod") :test #'string=)
       (let ((value
               (latex-trim
                (latex-parse-required-argument parser))))
         (if (string= command "pmod")
             (format nil " (mod ~A)" value)
             (format nil " (~A)" value))))
      ((member command '("overset" "stackrel") :test #'string=)
       (let ((upper
               (latex-parse-required-argument parser))
             (value
               (latex-trim
                (latex-parse-required-argument parser))))
         (format nil "~A~A"
                 value
                 (latex-format-script upper :sup))))
      ((string= command "underset")
       (let ((lower
               (latex-parse-required-argument parser))
             (value
               (latex-trim
                (latex-parse-required-argument parser))))
         (format nil "~A~A"
                 value
                 (latex-format-script lower :sub))))
      ((member command +latex-plain-wrappers+ :test #'string=)
       (let ((value
               (latex-parse-required-argument parser)))
         (if (or (and (>= (length command) 4)
                      (string= "text" command :end2 4))
                 (string= command "mbox"))
             value
             (latex-trim value))))
      ((string= command "begin")
       (latex-parse-environment parser))
      ((string= command "end")
       (setf (latex-parser-supported-p parser) nil)
       "")
      (t
       (setf (latex-parser-supported-p parser) nil)
       (format nil "\\~A" command)))))

(defun latex-parse-operator
    (parser operator inline-lower-style display-limits
     &optional (spaced nil))
  (let ((use-display-limits display-limits)
        (modifier-position (latex-parser-position parser)))
    (loop while (and (< modifier-position
                        (length (latex-parser-source parser)))
                     (member (char (latex-parser-source parser)
                                   modifier-position)
                             '(#\Space #\Tab) :test #'char=))
          do (incf modifier-position))
    ;; /\\(limits|nolimits)(?![A-Za-z])/ — matched manually because
    ;; cl-ppcre has no negative lookahead.
    (let* ((source (latex-parser-source parser))
           (limit-pos
             (and (< (1+ modifier-position) (length source))
                  (char= (char source modifier-position)
                         #\Backslash)
                  (cond
                    ((string= "limits" source
                              :start2 (1+ modifier-position)
                              :end2 (min (length source)
                                         (+ modifier-position 7)))
                     (+ modifier-position 7))
                    ((string= "nolimits" source
                              :start2 (1+ modifier-position)
                              :end2 (min (length source)
                                         (+ modifier-position 9)))
                     (+ modifier-position 9))
                    (t nil)))))
      (when (and limit-pos
                 (or (>= limit-pos (length source))
                     (not
                      (let ((c (char source limit-pos)))
                        (or (and (char>= c #\a) (char<= c #\z))
                            (and (char>= c #\A) (char<= c #\Z)))))))
        (setf use-display-limits
              (= limit-pos (+ modifier-position 7)))
        (setf (latex-parser-position parser) limit-pos)))
    (let ((lower nil)
          (upper nil))
      (loop
        (let ((script-position (latex-parser-position parser)))
          (loop while (and (< script-position
                              (length
                               (latex-parser-source parser)))
                           (member
                            (char (latex-parser-source parser)
                                  script-position)
                            '(#\Space #\Tab) :test #'char=))
                do (incf script-position))
          (let ((kind
                  (and (< script-position
                          (length (latex-parser-source parser)))
                       (char (latex-parser-source parser)
                             script-position))))
            (when (or (null kind)
                      (and (not (char= kind #\_))
                           (not (char= kind #\^))))
              (return))
            (setf (latex-parser-position parser)
                  (1+ script-position))
            (let ((value
                    (literal-string-replace-all
                     (latex-normalize-output
                      (latex-parse-required-argument parser nil))
                     " " "")))
              (if (char= kind #\_)
                  (progn
                    (when lower
                      (setf (latex-parser-supported-p parser)
                            nil))
                    (setf lower value))
                  (progn
                    (when upper
                      (setf (latex-parser-supported-p parser)
                            nil))
                    (setf upper value)))))))
      (if (and (latex-parser-display-p parser)
               use-display-limits
               (or lower upper))
          (let ((index
                  (length
                   (latex-parser-layout-nodes parser))))
            (setf
             (latex-parser-layout-nodes parser)
             (append
              (latex-parser-layout-nodes parser)
              (list
               (make-latex-operator-node
                :operator operator :lower lower
                :upper upper))))
            (format nil "~C~D~C"
                    (code-char #xf000) index
                    (code-char #xf001)))
          (let ((rendered operator))
            (when lower
              (setf rendered
                    (format nil "~A~A" rendered
                            (if (eq inline-lower-style :bracket)
                                (format nil "[~A]" lower)
                                (latex-format-script
                                 lower :sub)))))
            (when upper
              (setf rendered
                    (format nil "~A~A" rendered
                            (latex-format-script upper :sup))))
            (if spaced
                (format nil " ~A " rendered)
                rendered))))))

(defun latex-parse-required-argument
    (parser &optional (stack-fractions t))
  (let ((previous
          (latex-parser-stack-fractions-p parser)))
    (setf (latex-parser-stack-fractions-p parser)
          (and previous stack-fractions))
    (unwind-protect
         (latex-parse-required-argument-value parser)
      (setf (latex-parser-stack-fractions-p parser)
            previous))))

(defun latex-parse-required-argument-value (parser)
  (loop while (and (not (latex-parser-done-p parser))
                   (member (latex-parser-peek parser)
                           '(#\Space #\Tab) :test #'char=))
        do (incf (latex-parser-position parser)))
  (when (latex-parser-done-p parser)
    (setf (latex-parser-supported-p parser) nil)
    (return-from latex-parse-required-argument-value ""))
  (let ((character (latex-parser-peek parser)))
    (cond
      ((char= character #\{)
       (incf (latex-parser-position parser))
       (latex-parse-sequence parser #\}))
      ((char= character #\Backslash)
       (latex-parse-command parser))
      (t
       (incf (latex-parser-position parser))
       (string character)))))

(defun latex-parse-optional-argument (parser)
  (loop while (and (not (latex-parser-done-p parser))
                   (member (latex-parser-peek parser)
                           '(#\Space #\Tab) :test #'char=))
        do (incf (latex-parser-position parser)))
  (when (or (latex-parser-done-p parser)
            (not (char= (latex-parser-peek parser) #\[)))
    (return-from latex-parse-optional-argument nil))
  (let ((end
          (position #\] (latex-parser-source parser)
                    :start (1+ (latex-parser-position parser)))))
    (unless end
      (setf (latex-parser-supported-p parser) nil)
      (return-from latex-parse-optional-argument nil))
    (let ((value
            (subseq (latex-parser-source parser)
                    (1+ (latex-parser-position parser))
                    end)))
      (setf (latex-parser-position parser) (1+ end))
      (latex-render-nested parser value))))

(defun latex-read-raw-group (parser)
  (loop while (and (not (latex-parser-done-p parser))
                   (member (latex-parser-peek parser)
                           '(#\Space #\Tab) :test #'char=))
        do (incf (latex-parser-position parser)))
  (when (or (latex-parser-done-p parser)
            (not (char= (latex-parser-peek parser) #\{)))
    (setf (latex-parser-supported-p parser) nil)
    (return-from latex-read-raw-group nil))
  (incf (latex-parser-position parser))
  (let ((start (latex-parser-position parser))
        (depth 1))
    (loop while (not (latex-parser-done-p parser))
          do (let ((character (latex-parser-peek parser)))
               (cond
                 ((char= character #\Backslash)
                  (incf (latex-parser-position parser) 2))
                 (t
                  (when (char= character #\{)
                    (incf depth))
                  (when (char= character #\})
                    (decf depth))
                  (when (zerop depth)
                    (let ((value
                            (subseq
                             (latex-parser-source parser)
                             start
                             (latex-parser-position parser))))
                      (incf (latex-parser-position parser))
                      (return-from latex-read-raw-group
                        value)))
                  (incf (latex-parser-position parser))))))
    (setf (latex-parser-supported-p parser) nil)
    nil))

(defun latex-split-environment-rows (body)
  (cl-ppcre:split
   "\\\\\\\\(?:\\[[^\\]\\n]*\\])?"
   body))

(defun latex-parse-environment (parser)
  (let ((environment (latex-read-raw-group parser)))
    (when (null environment)
      (return-from latex-parse-environment ""))
    (let* ((end-marker
             (format nil "\\end{~A}" environment))
           (end
             (search end-marker
                     (latex-parser-source parser)
                     :start2 (latex-parser-position parser))))
      (unless end
        (setf (latex-parser-supported-p parser) nil)
        (return-from latex-parse-environment ""))
      (let ((body
              (subseq (latex-parser-source parser)
                      (latex-parser-position parser)
                      end)))
        (setf (latex-parser-position parser)
              (+ end (length end-marker)))
        (cond
          ((member environment
                   '("equation" "equation*" "displaymath")
                   :test #'string=)
           (latex-trim
            (latex-render-nested parser body)))
          ((member environment
                   '("aligned" "align" "align*" "alignedat"
                     "alignat" "alignat*" "gather" "gathered"
                     "multline" "multline*" "split")
                   :test #'string=)
           (let* ((aligned-at-p
                    (member environment
                            '("alignedat" "alignat" "alignat*")
                            :test #'string=))
                  (aligned-body
                    (if aligned-at-p
                        (cl-ppcre:regex-replace
                          "^\\s*\\{[^}]*\\}" body "")
                        body)))
             (format nil "~{~A~^~%~}"
                     (remove-if
                      (lambda (row) (zerop (length row)))
                      (mapcar
                       (lambda (row)
                         (let* ((cells
                                  (cl-ppcre:split "&" row))
                                (source
                                  (if aligned-at-p
                                      (format nil "~{~A~^ ~}"
                                              (loop for index
                                                    from 0
                                                    below
                                                    (ceiling
                                                     (length cells)
                                                     2)
                                                    collect
                                                    (format
                                                     nil "~{~A~}"
                                                     (subseq
                                                      cells
                                                      (* index 2)
                                                      (min
                                                       (length
                                                        cells)
                                                       (+ (* index 2)
                                                          2))))))
                                      (format nil "~{~A~}"
                                              cells))))
                           (latex-trim
                            (latex-render-nested
                             parser source))))
                       (latex-split-environment-rows
                        aligned-body))))))
          ((member environment '("cases" "cases*") :test #'string=)
           (let ((rows
                   (remove-if-not
                    (lambda (row) (some #'plusp (mapcar #'length row)))
                    (mapcar
                     (lambda (row)
                       (mapcar
                        (lambda (cell)
                          (latex-trim
                           (latex-render-nested
                            parser cell nil)))
                        (cl-ppcre:split "&" row)))
                     (latex-split-environment-rows body)))))
             (format nil "~{~A~^~%~}"
                     (loop for row in rows
                           for index from 0
                           for value =
                             (cl-ppcre:regex-replace
                               ",\\s*$" (or (first row) "") "")
                           for condition = (or (second row) "")
                           for delimiter =
                             (cond
                               ((zerop index) "⎧")
                               ((= index (1- (length rows))) "⎩")
                               (t "⎨"))
                           collect
                           (format nil "~A ~A~A"
                                   delimiter value
                                   (if (plusp (length condition))
                                       (format nil "~A~A"
                                               (if (cl-ppcre:scan
                                                     "(?i)^(if|when|for|otherwise)\\b"
                                                    condition)
                                                   " "
                                                   " if ")
                                               condition)
                                       ""))))))
          ((member environment
                   '("array" "matrix" "smallmatrix" "pmatrix"
                     "bmatrix" "Bmatrix" "vmatrix" "Vmatrix")
                   :test #'string=)
           (let ((matrix-body
                   (if (string= environment "array")
                       (cl-ppcre:regex-replace
                         "^\\s*\\{[^}]*\\}" body "")
                       body)))
             (latex-render-matrix
              parser environment matrix-body)))
          (t
           (setf (latex-parser-supported-p parser) nil)
           body))))))

(defun latex-render-matrix (parser environment body)
  (let* ((matrix
           (remove-if-not
            (lambda (row) (some #'plusp (mapcar #'length row)))
            (mapcar
             (lambda (row)
               (mapcar
                (lambda (cell)
                  (latex-trim
                   (latex-render-nested parser cell nil)))
                (cl-ppcre:split "&" row)))
             (latex-split-environment-rows body))))
         (column-count
           (max 0
                (reduce #'max
                        (mapcar #'length matrix)
                        :initial-value 0)))
         (column-widths
           (loop for column from 0 below column-count
                 collect
                 (max 0
                      (reduce #'max
                              (mapcar
                               (lambda (row)
                                 (visible-width
                                  (or (nth column row) "")))
                               matrix)
                              :initial-value 0))))
         (rows
           (mapcar
            (lambda (row)
              (format nil "~{~A~^ │ ~}"
                      (loop for column from 0 below column-count
                            for cell = (or (nth column row) "")
                            collect
                            (format nil "~A~A"
                                    cell
                                    (make-string
                                     (max 0
                                          (- (nth column
                                                  column-widths)
                                             (visible-width cell)))
                                     :initial-element
                                     (code-char #xf002))))))
            matrix))
         (lines
           (if (member environment
                       '("array" "matrix" "smallmatrix")
                       :test #'string=)
               rows
               (let ((delimiters
                       (cdr
                        (assoc environment
                               '(("pmatrix" "⎛" "⎞" "⎜" "⎟" "⎝" "⎠")
                                 ("bmatrix" "⎡" "⎤" "⎢" "⎥" "⎣" "⎦")
                                 ("Bmatrix" "⎧" "⎫" "⎨" "⎬" "⎩" "⎭")
                                 ("vmatrix" "│" "│" "│" "│" "│" "│")
                                 ("Vmatrix" "║" "║" "║" "║" "║" "║"))
                               :test #'string=))))
                 (unless delimiters
                   (setf (latex-parser-supported-p parser) nil)
                   (return-from latex-render-matrix
                     (format nil "~{~A~^~%~}" rows)))
                 (loop for row in rows
                       for index from 0
                       for left =
                         (cond
                           ((zerop index) (first delimiters))
                           ((= index (1- (length rows)))
                            (fifth delimiters))
                           (t (third delimiters)))
                       for right =
                         (cond
                           ((zerop index) (second delimiters))
                           ((= index (1- (length rows)))
                            (sixth delimiters))
                           (t (fourth delimiters)))
                       collect
                       (format nil "~A ~A ~A"
                               left row right))))))
    (if (<= (length lines) 1)
        (or (first lines) "")
        (let ((index
                (length
                 (latex-parser-layout-nodes parser))))
          (setf
           (latex-parser-layout-nodes parser)
           (append
            (latex-parser-layout-nodes parser)
            (list
             (make-latex-matrix-node
              :lines lines :baseline 0))))
          (format nil "~C~D~C"
                  (code-char #xf000) index
                  (code-char #xf001))))))

(defun latex-render-nested
    (parser source &optional (stack-fractions t))
  (let* ((nested
           (make-latex-parser
            source
            (latex-parser-layout-nodes parser)
            (and (latex-parser-display-p parser)
                 stack-fractions)))
         (rendered (latex-parser-render nested)))
    (setf (latex-parser-layout-nodes parser)
          (latex-parser-layout-nodes nested))
    (if rendered
        rendered
        (progn
          (setf (latex-parser-supported-p parser) nil)
          source))))

(defun render-latex (source &key display-p)
  "Render a basic LaTeX math expression as terminal-friendly Unicode
text; NIL when the expression contains unsupported or malformed
syntax.  DISPLAY-P stacks fractions and operator limits vertically."
  (let* ((nodes nil)
         (parser
           (make-latex-parser source nil display-p))
         (rendered (latex-parser-render parser)))
    (setf nodes (latex-parser-layout-nodes parser))
    (when (null rendered)
      (return-from render-latex nil))
    (when (null nodes)
      (return-from render-latex
        (literal-string-replace-all
         rendered +latex-protected-space+ " ")))
    (let* ((lines
             (latex-layout-lines
              (latex-render-layout rendered nodes)))
           (indentation
             (let ((non-empty
                     (remove-if
                      (lambda (line)
                        (zerop
                         (length (latex-trim line))))
                      lines)))
               (if non-empty
                   (reduce #'min
                           (mapcar
                            (lambda (line)
                              (- (length line)
                                 (length
                                  (latex-trim-start line))))
                            non-empty))
                   0))))
      (latex-trim-end
       (literal-string-replace-all
        (format nil "~{~A~^~%~}"
                (mapcar
                 (lambda (line)
                   (latex-trim-end
                    (subseq line
                            (min indentation
                                 (length line)))))
                 lines))
        +latex-protected-space+ " ")))))
