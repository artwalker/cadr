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

(test goal11-visible-width-fast-path-matches-reference-grapheme-semantics
  (labels
      ((reference-width (text)
         (loop for cluster in
               (cadr-tui:grapheme-clusters
                (cadr-tui::strip-ansi text))
               sum (cadr-tui::grapheme-width cluster)))
       (check (text)
         (is (= (reference-width text)
                (cadr-tui:visible-width text))
             "Fast width path diverged for ~S" text)))
    (let* ((escape (string #\Escape))
           (segments
             (list
              "" "plain ASCII 123" "中文" "👩‍💻" "🇨🇳"
              (format nil "e~C" #\Combining_Acute_Accent)
              (format nil "~C" #\Tab)
              "र्क" "ကာ" "ำ"
              (format nil "~A[31mred~A[0m" escape escape)
              (format nil "~A]8;;https://example.test~C链接~A]8;;~C"
                      escape (code-char 7) escape (code-char 7))
              (format nil "~A]133;A~Cprompt" escape (code-char 7)))))
      (dolist (segment segments)
        (check segment))
      (dolist (left segments)
        (dolist (right segments)
          (check (concatenate 'string left right)))))))

(test grapheme-clusters-do-not-split-composed-input
  (let ((clusters
          (cadr-tui:grapheme-clusters
           (format nil "Ae~C👩‍💻🇨🇳" #\Combining_Acute_Accent))))
    (is (= 4 (length clusters)))
    (is (string= "A" (first clusters)))
    (is (= 1 (cadr-tui:visible-width (second clusters))))
    (is (string= "👩‍💻" (third clusters)))
    (is (string= "🇨🇳" (fourth clusters)))))

(test grapheme-clusters-handle-empty-and-dangling-joiner-boundaries
  (is (null (cadr-tui:grapheme-clusters "")))
  (is (zerop (cadr-tui:visible-width "")))
  (let* ((dangling (format nil "👨~C " (code-char #x200d)))
         (clusters (cadr-tui:grapheme-clusters dangling)))
    (is (= 2 (length clusters)))
    (is (string= (format nil "👨~C" (code-char #x200d))
                 (first clusters)))
    (is (string= " " (second clusters)))
    (is (= 3 (cadr-tui:visible-width dangling)))))

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

(test regional-indicator-width-stays-stable-during-streaming
  (loop for codepoint from #x1f1e6 to #x1f1ff
        for indicator = (string (code-char codepoint))
        do (is (= 2 (cadr-tui:visible-width indicator))))
  (dolist (flag '("🇯🇵" "🇺🇸" "🇬🇧" "🇨🇳" "🇩🇪" "🇫🇷"))
    (is (= 2 (cadr-tui:visible-width flag))))
  (dolist (emoji '("👍" "👍🏻" "✅" "⚡" "⚡️" "👨" "👨‍💻" "🏳️‍🌈"))
    (is (= 2 (cadr-tui:visible-width emoji))))
  (let ((wrapped (cadr-tui:wrap-text "      - 🇨" 9)))
    (is (= 2 (length wrapped)))
    (is (= 7 (cadr-tui:visible-width (first wrapped))))
    (is (= 2 (cadr-tui:visible-width (second wrapped))))))

(test terminal-cell-width-covers-indic-and-myanmar-spacing-marks
  (dolist
      (case
       '(("र्क" 2)
         ("नेटवर्क" 5)
         ("सर्वाधिकार सुरक्षित। ऑर्डर पर क्लिक करें" 33)
         ("র্ক" 2)
         ("ર્ક" 2)
         ("ର୍କ" 2)
         ("ర్క" 2)
         ("ര്‍ക" 2)
         ("ကာ" 2)
         ("ကေ" 2)
         ("က်" 2)
         ("ကျ" 2)
         ("ကြ" 2)
         ("ကဳ" 2)
         ("ကဴ" 2)
         ("ကဵ" 2)
         ("ကး" 2)
         ("ကို" 1)
         ("က္" 1)))
    (is (= (second case)
           (cadr-tui:visible-width (first case)))
        "~S must occupy ~D terminal cells"
        (first case)
        (second case))))

(test terminal-cell-width-keeps-ordinary-marks-zero-width
  (dolist
      (case
       `((,(format nil "e~C" #\Combining_Acute_Accent) 1)
         ("čřžůú" 5)
         ("שָׁ" 1)
         ("بّ" 1)
         ("རྐ" 1)
         ("ᜠ᜴" 1)
         ("가〮" 2)
         ("가〯" 2)
         ("网络" 4)
         ("ネットワーク" 12)
         ("が" 2)
         ("が" 2)))
    (is (= (second case)
           (cadr-tui:visible-width (first case)))
        "~S must occupy ~D terminal cells"
        (first case)
        (second case))))
