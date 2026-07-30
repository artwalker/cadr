(in-package #:cadr-tui/tests)
(in-suite cadr-tui-suite)

(test truncate-to-width-is-ansi-and-grapheme-safe
  (let* ((reset (csi "0m"))
         (red (csi "31m"))
         (huge
           (with-output-to-string (output)
             (loop repeat 10000
                   do (write-string "🙂界" output))))
         (truncated
           (cadr-tui:truncate-to-width huge 40 "…")))
    (is (<= (cadr-tui:visible-width truncated) 40))
    (is (uiop:string-suffix-p
         truncated
         (concatenate 'string "…" reset)))
    (let ((styled
            (cadr-tui:truncate-to-width
             (format nil "~A~A~A"
                     red
                     (make-string 100 :initial-element #\h)
                     reset)
             20 "…")))
      (is (search red styled))
      (is (uiop:string-suffix-p
           styled
           (format nil "~A…~A" reset reset)))))
  (is
   (string=
    ""
    (cadr-tui:truncate-to-width "abcdef" 1 "🙂")))
  (is
   (string=
    (format nil "~A🙂~A" (csi "0m") (csi "0m"))
    (cadr-tui:truncate-to-width "abcdef" 2 "🙂")))
  (is (string= "a"
               (cadr-tui:truncate-to-width "a" 2 "🙂")))
  (is (= 8
         (cadr-tui:visible-width
          (cadr-tui:truncate-to-width
           "🙂界🙂界🙂界" 8 "…" t))))
  (is
   (uiop:string-suffix-p
    (cadr-tui:truncate-to-width
     (format nil "~A~A"
             (csi "31m")
             (make-string 100 :initial-element #\h))
     10 "")
    (csi "0m")))
  (is
   (string=
    (format nil "🙂~C~A…~A "
            #\Tab (csi "0m") (csi "0m"))
    (cadr-tui:truncate-to-width
     (format nil "🙂~C界 ~C_abc~C"
             #\Tab #\Escape (code-char 7))
     7 "…" t))))

(test terminal-output-normalization-preserves-control-sequences
  (is (= 1 (cadr-tui:visible-width "ำ")))
  (is (= 1 (cadr-tui:visible-width "ຳ")))
  (is (= 2 (cadr-tui:visible-width "กำ")))
  (is (= 2 (cadr-tui:visible-width "ກຳ")))
  (is (string= "ํา"
               (cadr-tui:normalize-terminal-output "ำ")))
  (is (string= "ໍາ"
               (cadr-tui:normalize-terminal-output "ຳ")))
  (dolist
      (control
       (list
        (osc-bel (format nil "8;;https://example.test/a~Cb"
                         #\Tab))
        (osc-st (format nil "0;window~Ctitle" #\Tab))
        (format nil "~C_payload~Cdata~C\\"
                #\Escape #\Tab #\Escape)))
    (is
     (string=
      (format nil "~Alabel   text" control)
      (cadr-tui:normalize-terminal-output
       (format nil "~Alabel~Ctext" control #\Tab))))))

(test column-slicing-never-splits-wide-graphemes
  (multiple-value-bind (text width)
      (cadr-tui:slice-with-width
       (format nil "out 192M~C.pi/skill-tests/results-ha" #\Tab)
       0 10 t)
    (is (string= "out 192M" text))
    (is (= 8 width))
    (is (= width (cadr-tui:visible-width text))))
  (multiple-value-bind
        (before before-width after after-width)
      (cadr-tui:extract-segments "abcd让EFGH" 5 9 11 t)
    (is (string= "abcd" before))
    (is (= 4 before-width))
    (is (string= "H" after))
    (is (= 1 after-width))))
