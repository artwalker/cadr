;;; Goal 19 Part C: mermaid markdown transformer goldens and semantics.
;;;
;;; Authority is test/fixtures/mermaid-golden/transform-reference.json,
;;; produced by scripts/mermaid-transform-golden.mjs from marked 18.0.5 +
;;; grok-mermaid 0.2.2 using the baseline mermaid.ts transformer (unstyled).
;;; Each byte-exact case also carries an independent assertion derived from
;;; the baseline contract, not from cadr's implementation.
(in-package #:cadr-tui/tests)
(in-suite cadr-tui-suite)

(defun transform-captured (src &key (mode "streaming")
                                    (message-type "assistant")
                                    streaming-p
                                    (available-width 80))
  (handler-case
      (cadr-tui:transform-mermaid-markdown
       src
       :mode mode
       :message-type message-type
       :streaming-p streaming-p
       :available-width available-width
       :theme-p nil)
    (error (e)
      (list :transform-error (princ-to-string e)))))

(test mermaid-transform-golden-23-cases-byte-exact
  (let ((results +mermaid-transform-results+))
    (is (= 23 (length results))
        "transform golden must carry exactly 23 cases, got ~D"
        (length results))
    (is (= 23 (length (remove-duplicates
                       (mapcar (lambda (c) (getf c :id)) results)
                       :test #'string=)))
        "transform case ids must be unique")
    (dolist (case results)
      (let* ((id (getf case :id))
             (got (transform-captured
                   (getf case :src)
                   :mode (getf case :mode)
                   :message-type (getf case :message-type)
                   :streaming-p (getf case :streaming-p)
                   :available-width (getf case :available-width)))
             (expected (getf case :expected)))
        (if (and (consp got) (eq (first got) :transform-error))
            (fail "~A: transformer errored: ~A" id (second got))
            (is (string= expected got)
                "~A: transformer output differs" id))))))

(test mermaid-transform-off-is-identity
  (let ((src (format nil "```mermaid~%flowchart LR~%  A-->B~%```~%")))
    (is (string= src (transform-captured src :mode "off"))
        "mode=off must return the source unchanged")))

(test mermaid-transform-thinking-is-identity
  (let ((src (format nil "```mermaid~%flowchart LR~%  A-->B~%```~%")))
    (is (string= src
                (transform-captured src
                                    :mode "streaming"
                                    :message-type "assistant-thinking"))
        "assistant-thinking must skip mermaid rendering")))

(test mermaid-transform-final-skips-while-streaming
  (let ((src (format nil "```mermaid~%flowchart LR~%  A-->B~%```~%")))
    (is (string= src
                (transform-captured src
                                    :mode "final"
                                    :streaming-p t))
        "mode=final during streaming must return the source unchanged")))

(test mermaid-transform-success-uses-code-spans
  (let* ((src (format nil "```mermaid~%flowchart LR~%  A-->B~%```~%"))
         (out (transform-captured src :mode "streaming")))
    (is (char= (char out 0) (code-char 96))
        "successful render starts with a code-span fence")
    (is (null (search "```mermaid" out))
        "successful render must replace the mermaid fence")
    (is (search "──" out)
        "successful render contains the diagram art")))

(test mermaid-transform-too-wide-falls-back-silently
  (let* ((src (format nil "```mermaid~%flowchart LR~%  A[very long label that should wrap at twenty four columns] --> B~%```~%"))
         (out (transform-captured src :mode "streaming" :available-width 10)))
    (is (string= src out)
        "over-wide art must silently return token.raw")
    (is (null (search "Mermaid diagram not rendered" out))
        "over-wide fallback must not add a warning line")))

(test mermaid-transform-parse-fail-falls-back-silently
  (let* ((src (format nil "```mermaid~%not a diagram~%```~%"))
         (out (transform-captured src)))
    (is (string= src out)
        "parse failure must silently return token.raw")))

(test mermaid-transform-warning-nonstreaming-has-suffix
  (let* ((src (format nil "```mermaid~%flowchart LR~%  A[~%```~%"))
         (out (transform-captured src :mode "final" :streaming-p nil)))
    (is (search "Mermaid diagram not rendered:" out)
        "non-streaming warnings must emit the baseline warning prefix")
    (is (search src (subseq out 0 (min (length src) (length out))))
        "warning path keeps the original fence before the warning line")))

(test mermaid-transform-blockquote-stays-source
  (let ((src (format nil "> ```mermaid~%> flowchart LR~%>   A-->B~%> ```~%")))
    (is (string= src (transform-captured src))
        "blockquote-nested mermaid is not a top-level token")))

(test mermaid-theme-cls-mapping-six-ways
  (let ((border (cadr-tui::mermaid-style-span "x" "border" :theme-p t))
        (text (cadr-tui::mermaid-style-span "x" "text" :theme-p t))
        (edge (cadr-tui::mermaid-style-span "x" "edge" :theme-p t))
        (label (cadr-tui::mermaid-style-span "x" "edgeLabel" :theme-p t))
        (title (cadr-tui::mermaid-style-span "x" "title" :theme-p t))
        (none (cadr-tui::mermaid-style-span "x" "none" :theme-p t)))
    (is (search (cadr-tui:theme-foreground-ansi :border-muted :enabled-p t) border))
    (is (search (cadr-tui:theme-foreground-ansi :text :enabled-p t) text))
    (is (search (cadr-tui:theme-foreground-ansi :accent :enabled-p t) edge))
    (is (search (cadr-tui:theme-foreground-ansi :muted :enabled-p t) label))
    (is (search (cadr-tui:theme-foreground-ansi :accent :enabled-p t) title))
    (is (search (format nil "~C[1m" #\Escape) title)
        "title is accent+bold")
    (is (string= "x" none)
        "none is unstyled")))

(test mermaid-theme-token-count-stays-58
  ;; v0.84.2 added searchMatchBg/searchMatchText; the pin still guards
  ;; against unreviewed growth.
  (is (= 58 (length cadr-tui::+dark-theme-colors+))
      "theme tokens must not grow without review; dark has ~D"
      (length cadr-tui::+dark-theme-colors+)))

(test mermaid-inline-code-spans-keep-single-backtick
  (let ((rendered
          (format nil "~{~A~%~}"
                  (cadr-tui:render-markdown
                   "Use **bold** and `code` now."
                   40))))
    (is (search "Use bold and code now." rendered))
    (is (null (search "`" rendered)))))

(test mermaid-inline-code-spans-accept-double-backtick
  (let* ((src (format nil "``hel`lo``"))
         (rendered
           (format nil "~{~A~%~}"
                   (cadr-tui:render-markdown src 40))))
    (is (search "hel`lo" rendered)
        "marked 18 multi-backtick spans keep an interior backtick")
    (is (null (search "``" rendered)))))

(test mermaid-rendered-markdown-does-not-grow-an-eof-blank
  (let* ((src (format nil "```mermaid~%flowchart LR~%  A-->B~%```~%"))
         (transformed (transform-captured src :mode "streaming"))
         (lines
           (cadr-tui:render-markdown transformed 80 :padding-y 0 :padding-x 0))
         (nonblank
           (remove-if
            (lambda (line)
              (zerop (length (string-trim '(#\Space #\Tab) line))))
            lines)))
    (is (>= (length nonblank) 3)
        "flowchart LR A-->B must render at least the three art rows")
    (is (search "──" (first nonblank)))
    (is (search "A" (second nonblank)))
    (is (or (search "└" (car (last nonblank)))
            (search "┘" (car (last nonblank)))
            (search "─" (car (last nonblank))))
        "last non-blank row is the bottom rule, not an extra pad")
    (is (= (length lines) (length nonblank))
        "EOF newline must not become a blank markdown row; got ~D lines of which ~D nonblank"
        (length lines) (length nonblank))))

(test markdown-keeps-internal-blank-paragraphs
  (let* ((lines
           (cadr-tui:render-markdown
            (format nil "alpha~%~%beta")
            40
            :padding-y 0
            :padding-x 0))
         (trimmed
           (mapcar
            (lambda (line)
              (string-trim '(#\Space #\Tab) line))
            lines)))
    (is (find "alpha" trimmed :test #'search))
    (is (find "beta" trimmed :test #'search))
    (is (find "" trimmed :test #'string=)
        "an internal blank paragraph must survive")))
