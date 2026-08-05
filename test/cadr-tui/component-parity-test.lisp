(in-package #:cadr-tui/tests)

(in-suite cadr-tui-suite)

(test truncated-text-pads-clips-first-line-and-isolates-style
  (let* ((escape (string #\Escape))
         (lines
           (cadr-tui:render-truncated-text
            (format nil "~A[31mabcdefghij~A[0m~%ignored"
                    escape escape)
            10 :padding-x 1 :padding-y 1)))
    (is (= 3 (length lines)))
    (is (every (lambda (line)
                 (= 10 (cadr-tui:visible-width line)))
               lines))
    (is (string= (make-string 10
                              :initial-element #\Space)
                 (first lines)))
    (is (search "abcde" (second lines)))
    (is (search "..." (second lines)))
    (is (not (search "ignored" (second lines))))
    (is (search (format nil "~A[0m" escape)
                (second lines)))))

(test select-list-aligns-single-line-descriptions-and-layout-bounds
  (let* ((items
           (list
            (cadr-tui:make-select-item
             :label "short"
             :value :short
             :description
             (format nil "first line~%second line"))
            (cadr-tui:make-select-item
             :label "a-very-long-command-name"
             :value :long
             :description "description")))
         (list
           (cadr-tui:make-select-list
            :items items :height 5
            :show-filter-p nil
            :min-primary-column-width 12
            :max-primary-column-width 16))
         (lines (cadr-tui:render-select-list list 60)))
    (is (= 2 (length lines)))
    (is (search "first line second line"
                (first lines)))
    (is (search "description" (second lines)))
    (is (=
         (cadr-tui:visible-width
          (subseq (first lines) 0
                  (search "first line"
                          (first lines))))
         (cadr-tui:visible-width
          (subseq (second lines) 0
                  (search "description"
                          (second lines))))))
    (is (<= (cadr-tui:visible-width
             (first lines))
            60))
    (setf (cadr-tui:select-list-query list) "long")
    (is (= 1
           (length
            (cadr-tui:select-list-filtered-items list))))))

(test markdown-covers-streaming-structures-links-tables-and-ansi-theme
  (let* ((caps
           (cadr-tui:make-terminal-capabilities
            :images nil
            :true-color-p t
            :hyperlinks-p t))
         (text
           (format nil
                   "# Header~%~%- item~%1. ordered~%> quote~%~%**bold** *italic* ~~~~gone~~~~ `code` [link](https://example.com)~%~%| A | B |~%|---|---|~%| 1 | 2 |~%~%```lisp~%(+ 1 2)~%```~%~%![alt](image.png)~%---"))
         (lines
           (cadr-tui:render-markdown
            text 48 :ansi-theme-p t
            :capabilities caps))
         (joined
           (cadr-tui:strip-terminal-sequences
            (format nil "~{~A~%~}" lines))))
    (is (search "Header" joined))
    (is (search "- item" joined))
    (is (search "1. ordered" joined))
    (is (search "│ quote" joined))
    (is (search "bold" joined))
    (is (search "italic" joined))
    (is (search "gone" joined))
    (is (search "code" joined))
    (is
     (search
      "https://example.com"
      (format nil "~{~A~%~}" lines)))
    (is (search "│ A" joined))
    (is (search "(+ 1 2)" joined))
    (is (search "Image: alt (image.png)" joined))
    (is (search "───" joined))
    (is
     (search
      (format nil "~C[" #\Escape)
      (format nil "~{~A~%~}" lines)))
    (is (every (lambda (line)
                 (<= (cadr-tui:visible-width line)
                     48))
               lines))
    (let ((streaming
            (cadr-tui:render-markdown
             "streaming **open" 30)))
      (is (= 1 (length streaming)))
      (is (= 30
             (cadr-tui:visible-width
              (first streaming))))
      (is (string=
           "streaming **open"
           (string-right-trim
            " " (first streaming)))))))

(test image-component-reserves-rows-and-falls-back-within-width
  (let* ((kitty
           (cadr-tui:make-terminal-capabilities
            :images :kitty :true-color-p t
            :hyperlinks-p t))
         (lines
           (cadr-tui:render-image-component
            "YWJj" "image/png" 30
            :dimensions '(100 100)
            :capabilities kitty
            :max-width-cells 20
            :max-height-cells 4
            :image-id 9))
         (plain
           (cadr-tui:make-terminal-capabilities
            :images nil :true-color-p nil
            :hyperlinks-p nil))
         (fallback
           (cadr-tui:render-image-component
            "YWJj" "image/png" 20
            :dimensions '(640 480)
            :capabilities plain
            :filename "/root/a-very-long-picture-name.png")))
    (is (= 4 (length lines)))
    (is (cadr-tui:image-line-p (first lines)))
    (is (every (lambda (line)
                 (string= "" line))
               (rest lines)))
    (is (= 1 (length fallback)))
    (is (<= (cadr-tui:visible-width
             (first fallback))
            20))))

(defun markdown-parity-plain-lines (text width &rest options)
  (mapcar
   (lambda (line)
     (string-right-trim
      " "
      (cadr-tui:strip-terminal-sequences line)))
   (apply #'cadr-tui:render-markdown
          text width options)))

(test goal9-md03-renders-nested-and-bare-blockquotes
  (let ((lines
          (markdown-parity-plain-lines
           (format nil "> outer~%> > nested~%>~%after")
           40)))
    (is (find "│ outer" lines :test #'string=))
    (is (find "│ │ nested" lines :test #'string=))
    (is (find "│" lines :test #'string=))
    (is (equal '("│" "" "after")
               (last lines 3)))))

(test goal9-md04-preserves-source-list-continuations-and-nesting
  (let* ((lines
          (markdown-parity-plain-lines
           (format nil
                   "* parent~%  continuation words that wrap~%    7) child~%       nested continuation words")
           18 :preserve-list-markers-p t))
         (nested-index
           (position "    7) child" lines
                     :test #'string=)))
    (is (string= "* parent" (first lines)))
    (is (find "  continuation" lines
              :test #'uiop:string-prefix-p))
    (is (find "  words that wrap" lines
              :test #'string=))
    (is (find "    7) child" lines :test #'string=))
    (is (find "       nested" lines
              :test #'uiop:string-prefix-p))
    (is (every
         (lambda (line)
           (uiop:string-prefix-p "       " line))
         (nthcdr (1+ nested-index) lines)))))

(test goal9-md05-mailto-link-comparison-omits-redundant-url
  (let* ((caps
           (cadr-tui:make-terminal-capabilities
            :images nil :true-color-p t
            :hyperlinks-p nil))
         (rendered
           (format nil "~{~A~^~%~}"
                   (cadr-tui:render-markdown
                    "[person@example.com](mailto:person@example.com)"
                    80 :capabilities caps))))
    (is (search "person@example.com" rendered))
    (is (null (search "(mailto:" rendered)))))

(test goal9-md06-wraps-table-cells-and-separates-body-rows
  (let* ((lines
           (markdown-parity-plain-lines
            (format nil
                    "| Name | Description |~%| --- | --- |~%| alpha | first body cell wraps across lines |~%| beta | second row |")
            28))
         (alpha-index
           (position-if
            (lambda (line) (search "alpha" line))
            lines))
         (beta-index
           (position-if
            (lambda (line) (search "beta" line))
            lines)))
    (is (not (null alpha-index)))
    (is (not (null beta-index)))
    (is (> beta-index (+ alpha-index 1)))
    (is (find-if
         (lambda (line)
           (and (plusp (length line))
                (char= #\├ (char line 0))))
         (subseq lines (1+ alpha-index) beta-index)))
    (is (find-if
         (lambda (line)
           (and (uiop:string-prefix-p "│ " line)
                (search "wraps" line)))
         lines))))

(test goal9-md07-restores-default-message-style-after-inline-reset
  (let* ((escape (string #\Escape))
         (user-prefix
           (format nil "~A[38;5;111m" escape))
         (thinking-prefix
           (format nil "~A[38;5;244m~A[3m"
                   escape escape))
         (user
           (format nil "~{~A~^~%~}"
                   (cadr-tui:render-markdown
                    "before `code` after" 80
                    :ansi-theme-p t
                    :default-style-function
                    (lambda (text)
                      (format nil "~A~A~A[39m"
                              user-prefix text escape)))))
         (thinking
           (format nil "~{~A~^~%~}"
                   (cadr-tui:render-markdown
                    "before **bold** after" 80
                    :ansi-theme-p t
                    :default-style-function
                    (lambda (text)
                      (format nil "~A~A~A[23m~A[39m"
                              thinking-prefix text
                              escape escape))))))
    (is (>= (count-substring user-prefix user) 2))
    (is (>= (count-substring thinking-prefix thinking) 2))))

(test goal9-markdown-blocks-space-following-content-like-baseline
  (let ((cases
          (list
           (format nil "```txt~%code~%```~%after-code")
           (format nil "> quote~%after-quote")
           (format nil "---~%after-rule")
           (format nil
                   "| A | B |~%|---|---|~%| 1 | 2 |~%after-table"))))
    (dolist (source cases)
      (let* ((lines
               (markdown-parity-plain-lines source 40))
             (after-index
               (position-if
                (lambda (line)
                  (search "after-" line))
                lines)))
        (is (not (null after-index)))
        (is (plusp after-index))
        (is (string= "" (nth (1- after-index) lines)))))))

(test goal9-footer-extension-status-preserves-its-own-style
  (let ((caps
          (cadr-tui:make-terminal-capabilities
           :images nil :true-color-p t
           :hyperlinks-p nil)))
    (cadr-tui:set-current-theme :dark :capabilities caps)
    (unwind-protect
         (let* ((escape (string #\Escape))
                (error-prefix
                  (format nil "~A[38;2;204;102;102m"
                          escape))
                (dim-prefix
                  (format nil "~A[38;2;128;128;128m"
                          escape))
                (status
                  (cadr-tui:theme-foreground
                   :error
                   (format nil "extension~% status")
                   :enabled-p t))
                (line
                  (third
                   (cadr-tui:render-footer
                    14 :model "m"
                    :statuses (list (cons "x" status))
                    :ansi-theme-p t))))
           (is (uiop:string-prefix-p error-prefix line))
           (is (not (uiop:string-prefix-p dim-prefix line)))
           (is (search "extension" line))
           (is (null (search (string #\Newline) line)))
           (is (<= (cadr-tui:visible-width line) 14)))
      (cadr-tui:reset-current-theme))))

(test goal9-footer-token-count-rounding-matches-js-math-round
  (dolist
      (entry
       '((999 "999")
         (1000 "1.0k")
         (9999 "10.0k")
         (10000 "10k")
         (10499 "10k")
         (10500 "11k")
         (12500 "13k")
         (999999 "1000k")
         (1000000 "1.0M")
         (9999999 "10.0M")
         (10000000 "10M")
         (10499999 "10M")
         (10500000 "11M")
         (12500000 "13M")))
    (destructuring-bind (count expected) entry
      (is (string=
           expected
           (cadr-tui::format-footer-tokens count))))))

(test goal17-narrow-footer-truncation-keeps-the-baseline-dim-ellipsis
  ;; footer.ts:229 passes a dim-styled ellipsis to truncateToWidth.  Keeping
  ;; the ellipsis in the same style run matters after terminal replay.
  (let ((caps
          (cadr-tui:make-terminal-capabilities
           :images nil :true-color-p t
           :hyperlinks-p nil)))
    (cadr-tui:set-current-theme :dark :capabilities caps)
    (unwind-protect
         (let* ((ellipsis
                  (cadr-tui:theme-foreground
                   :dim "..." :enabled-p t))
                (line
                  (first
                   (cadr-tui:render-footer
                    8 :cwd "/long/path"
                    :model "model"
                    :ansi-theme-p t))))
           (is (= 8 (cadr-tui:visible-width line)))
           (is (search ellipsis line)))
      (cadr-tui:reset-current-theme))))
