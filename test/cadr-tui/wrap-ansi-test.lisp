(in-package #:cadr-tui/tests)
(in-suite cadr-tui-suite)

(test wrap-ansi-preserves-styles-and-word-boundaries
  (let* ((underline (csi "4m"))
         (underline-off (csi "24m"))
         (background (csi "44m"))
         (reset (csi "0m"))
         (url "https://example.com/very/long/path/that/will/wrap")
         (underlined
           (format nil "read this thread ~A~A~A"
                   underline url underline-off))
         (wrapped (cadr-tui:wrap-text underlined 40)))
    (is (string= "read this thread" (first wrapped)))
    (is (uiop:string-prefix-p underline (second wrapped)))
    (dolist (line (butlast (rest wrapped)))
      (is (uiop:string-suffix-p line underline-off)))
    (let ((background-lines
            (cadr-tui:wrap-text
             (format nil "~Ahello world this is blue background text~A"
                     background reset)
             15)))
      (is (every
           (lambda (line) (search background line))
           background-lines))
      (is (every
           (lambda (line)
             (not (uiop:string-suffix-p line reset)))
           (butlast background-lines)))))
  (is
   (equal
    '("first" "second" "third" "fourth")
    (cadr-tui:wrap-text
     (format nil "first~%second~C~%third~Cfourth"
             #\Return #\Return)
     80)))
  (let ((lines
          (cadr-tui:wrap-text
           "This is an example 中文汉字测试段落内容中文汉字测试段落内容."
           40)))
    (is
     (equal
      '("This is an example 中文汉字测试段落内容"
        "中文汉字测试段落内容.")
      lines))
    (is (every
         (lambda (line)
           (<= (cadr-tui:visible-width line) 40))
         lines)))
  (is
   (every
    (lambda (line)
      (<= (cadr-tui:visible-width line) 1))
    (cadr-tui:wrap-text "  " 1))))

(test wrap-ansi-preserves-osc-eight-hyperlinks
  (let* ((url "https://example.com")
         (open-st (osc-st (format nil "8;;~A" url)))
         (close-st (osc-st "8;;"))
         (lines
           (cadr-tui:wrap-text
            (format nil "~A0123456789~A" open-st close-st)
            6)))
    (is (= 2 (length lines)))
    (dolist (line lines)
      (is (search open-st line)))
    (is (uiop:string-suffix-p (first lines) close-st)))
  (let* ((url
           (concatenate
            'string "https://example.com/oauth/"
            (make-string 32 :initial-element #\a)))
         (open-bel (osc-bel (format nil "8;;~A" url)))
         (close-bel (osc-bel "8;;"))
         (lines
           (cadr-tui:wrap-text
            (format nil "~A~A~A" open-bel url close-bel)
            20)))
    (is (> (length lines) 1))
    (dolist (line lines)
      (is (search open-bel line))
      (is (not (search
                (osc-st (format nil "8;;~A" url))
                line))))
    (dolist (line (butlast lines))
      (is (uiop:string-suffix-p line close-bel)))))

(test wrap-ansi-ignores-osc-markers-and-stabilizes-flags
  (is
   (= 5
      (cadr-tui:visible-width
       (format nil "~Ahello~A"
               (osc-bel "133;A")
               (osc-bel "133;B")))))
  (is
   (= 5
      (cadr-tui:visible-width
       (format nil "~Ahello~A"
               (osc-st "133;A")
               (osc-st "133;B")))))
  (is (= 2 (cadr-tui:visible-width "🇨")))
  (is (= 2 (cadr-tui:visible-width "🇨🇳")))
  (let ((lines (cadr-tui:wrap-text "      - 🇨" 9)))
    (is (equal '("      -" "🇨") lines))))
