(in-package #:cadr-tui/tests)
(in-suite cadr-tui-suite)

(defun pi140-markdown-plain-lines (source)
  (mapcar (lambda (line)
            (string-right-trim '(#\Space) line))
          (cadr-tui:render-markdown
           source 80 :ansi-theme-p nil :padding-x 0 :padding-y 0)))

(defparameter +pi140-sample-table+
  '("| A | B |" "|---|---|" "| 1 | 2 |"))

(defparameter +pi140-rendered-table+
  '("┌───┬───┐" "│ A │ B │" "├───┼───┤" "│ 1 │ 2 │" "└───┴───┘"))

(defun pi140-join-lines (lines)
  (format nil "~{~A~^~%~}" lines))

(test pi140-unclosed-display-math-does-not-swallow-tables
  ;; Locked to packages/tui/test/markdown.test.ts
  ;; "unclosed display math before tables (#11159)" at v1.4.0.
  (is (equal (append '("Intro" "" "$$" "")
                     +pi140-rendered-table+
                     '("" "After"))
             (pi140-markdown-plain-lines
              (pi140-join-lines
               (append '("Intro" "" "$$" "")
                       +pi140-sample-table+
                       '("" "After"))))))
  (is (equal (append '("$$" "x = 1" "")
                     +pi140-rendered-table+)
             (pi140-markdown-plain-lines
              (pi140-join-lines
               (append '("$$" "x = 1" "")
                       +pi140-sample-table+)))))
  (is (equal (append '("Intro" "" "$$" "x = 1" "")
                     +pi140-rendered-table+
                     '("" "y²"))
             (pi140-markdown-plain-lines
              (pi140-join-lines
               (append '("Intro" "" "$$" "x = 1" "")
                       +pi140-sample-table+
                       '("" "$$" "y^2" "$$"))))))
  (is (equal '("$$" "" "┌───┐" "│ A │" "├───┤" "│ 1 │" "└───┘")
             (pi140-markdown-plain-lines
              (format nil "$$~%~%| A |~%:---:~%| 1 |"))))
  (is (equal (append '("" "\\[" "x^2" "")
                     +pi140-rendered-table+)
             (pi140-markdown-plain-lines
              (pi140-join-lines
               (append '("\\\\[" "x^2" "")
                       +pi140-sample-table+)))))
  (is (equal (append '("" "\\[" "x = 1" "")
                     +pi140-rendered-table+
                     '("" "\\" "" "\\[" "y^2" "\\\\]"))
             (pi140-markdown-plain-lines
              (pi140-join-lines
               (append '("\\\\[" "x = 1" "")
                       +pi140-sample-table+
                       '("" "\\\\[" "y^2" "\\\\]"))))))
  (is (equal '("$$" "x^2" ""
               "┌───────┐" "│ Value │" "├───────┤" "│ 1     │" "└───────┘")
             (pi140-markdown-plain-lines
              (format nil "$$~%x^2~%~%Value~%| --- |~%1"))))
  (is (equal (append '("a + b" "") +pi140-rendered-table+)
             (pi140-markdown-plain-lines
              (pi140-join-lines
               (append '("$$" "a" "+ b" "$$" "")
                       +pi140-sample-table+))))))

(defun pi140-emphasis-line (text)
  (cadr-tui::render-inline-markdown
   text t (cadr-tui:get-terminal-capabilities)))

(defun pi140-styled (kind text)
  (if (eq kind :bold)
      (cadr-tui:theme-bold text :enabled-p t)
      (cadr-tui:theme-italic text :enabled-p t)))

(test pi140-cjk-emphasis-beside-punctuation
  ;; Locked to packages/tui/test/markdown.test.ts "CJK emphasis" at v1.4.0.
  (is (string= (concatenate 'string
                            (pi140-styled :bold "这是测试。")
                            "后面")
               (pi140-emphasis-line "**这是测试。**后面")))
  (is (string= (concatenate 'string
                            (pi140-styled :bold "一句话说清：")
                            "一台机器")
               (pi140-emphasis-line "**一句话说清：**一台机器")))
  (is (string= (concatenate 'string
                            (pi140-styled :bold "要点到此为止。")
                            "20 小时")
               (pi140-emphasis-line "**要点到此为止。**20 小时")))
  (is (string= (concatenate 'string
                            "字"
                            (pi140-styled :bold "「引用」")
                            "字")
               (pi140-emphasis-line "字**「引用」**字")))
  (is (string= (concatenate 'string
                            (pi140-styled :italic "斜体。")
                            "后面")
               (pi140-emphasis-line "*斜体。*后面")))
  (is (string= "**end.**Then next"
               (pi140-emphasis-line "**end.**Then next")))
  (is (string= "a_b_c" (pi140-emphasis-line "a_b_c")))
  (is (string= "snake_case" (pi140-emphasis-line "snake_case"))))
