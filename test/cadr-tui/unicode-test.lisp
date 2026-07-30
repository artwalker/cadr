(in-package #:cadr-tui/tests)
(in-suite cadr-tui-suite)

(test visible-width-covers-terminal-graphemes
  (is (= 3 (cadr-tui:visible-width "abc")))
  (is (= 4 (cadr-tui:visible-width "中文")))
  (is (= 1 (cadr-tui:visible-width (format nil "e~C" #\Combining_Acute_Accent))))
  (is (= 2 (cadr-tui:visible-width "👩‍💻")))
  (is (= 2 (cadr-tui:visible-width "🇨🇳")))
  (is (= 3 (cadr-tui:visible-width (format nil "~C[31m红~C[0mA"
                                         #\Escape #\Escape))))
  (is (= 5 (cadr-tui:visible-width (format nil "a~Cb" #\Tab)))))

(test grapheme-clusters-do-not-split-composed-input
  (let ((clusters
          (cadr-tui:grapheme-clusters
           (format nil "Ae~C👩‍💻🇨🇳" #\Combining_Acute_Accent))))
    (is (= 4 (length clusters)))
    (is (string= "A" (first clusters)))
    (is (= 1 (cadr-tui:visible-width (second clusters))))
    (is (string= "👩‍💻" (third clusters)))
    (is (string= "🇨🇳" (fourth clusters)))))

(test width-aware-slicing-and-wrapping
  (multiple-value-bind (prefix width)
      (cadr-tui:slice-to-width "ab中cd" 4)
    (is (string= "ab中" prefix))
    (is (= 4 width)))
  (multiple-value-bind (prefix width)
      (cadr-tui:slice-to-width
       (format nil "~C[31m红色~C[0m"
               #\Escape #\Escape)
       2)
    (is (= 2 width))
    (is (= 2 (cadr-tui:visible-width prefix))))
  (is (equal '("ab中" "cd")
             (cadr-tui:wrap-text "ab中cd" 4)))
  (is (equal '("" "") (cadr-tui:wrap-text (format nil "~%") 8))))
