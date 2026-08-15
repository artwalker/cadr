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

;;; goal 20, 12F-2: slice-with-width is being rewritten to iterate grapheme
;;; spans without per-cluster subseq allocation and to collect pending ANSI
;;; codes in a list instead of quadratic concatenation.  The reference copy
;;; below is the pre-rewrite implementation, verbatim; the equivalence test
;;; pins the rewrite to it over a corpus that covers ANSI-dense lines, wide
;;; graphemes, combining marks, ZWJ sequences, tabs, and window edges.

(defun slice-with-width-reference (text start-column length &optional strict-p)
  (when (<= length 0)
    (return-from slice-with-width-reference (values "" 0)))
  (let ((end-column (+ start-column length))
        (column 0)
        (width 0)
        (index 0)
        (pending-ansi "")
        (done-p nil))
    (values
     (with-output-to-string (output)
       (loop while (and (< index (length text))
                        (not done-p))
             for ansi-end = (cadr-tui::ansi-sequence-end text index)
             do
             (if ansi-end
                 (let ((code (subseq text index ansi-end)))
                   (cond
                     ((and (>= column start-column)
                           (< column end-column))
                      (write-string code output))
                     ((< column start-column)
                      (setf pending-ansi
                            (concatenate
                             'string pending-ansi code))))
                   (setf index ansi-end))
                 (let* ((next-ansi
                          (or (position #\Escape text
                                        :start index)
                              (length text)))
                        (fragment
                          (subseq text index next-ansi)))
                   (dolist (cluster (cadr-tui::grapheme-clusters fragment))
                     (let* ((cluster-width
                              (cadr-tui::grapheme-width cluster))
                            (in-range-p
                              (and (>= column start-column)
                                   (< column end-column)))
                            (fits-p
                              (or (not strict-p)
                                  (<= (+ column cluster-width)
                                      end-column))))
                       (when (and in-range-p fits-p)
                         (when (plusp (length pending-ansi))
                           (write-string pending-ansi output)
                           (setf pending-ansi ""))
                         (write-string cluster output)
                         (incf width cluster-width))
                       (incf column cluster-width)
                       (when (>= column end-column)
                         (setf done-p t)
                         (return))))
                   (setf index next-ansi)))))
     width)))

(test slice-with-width-matches-reference-on-corpus
  (let ((corpus
          (list
           "plain ascii text"
           (format nil "out 192M~C.pi/skill" #\Tab)
           "让中文与emoji🙂混合的一行文字"
           "é́ 组合字符 a̐́ 测试"
           "🇦🇧🇨 regional indicators"
           "👨‍👩‍👧‍👦 zwj family"
           (format nil "~C[1m~C[38;2;1;2;3mcolored~C[0m tail" #\Escape #\Escape #\Escape)
           (format nil "~C[38;2;1;2;3m~C[1mbold red~C[0m plain ~C[4munder~C[0m"
                   #\Escape #\Escape #\Escape #\Escape #\Escape)
           (format nil "~{~C[3~Dmseg~D~C[0m~}" (loop for i below 8 append (list #\Escape i i #\Escape)))
           (format nil "~C[?2026h~C[2K~C[1G sync~C[?2026l" #\Escape #\Escape #\Escape #\Escape)
           "")))
    (dolist (text corpus)
      (loop for start in '(0 1 3 5 8 13)
            do (loop for length in '(1 4 7 12 40)
                     do (loop for strict in '(nil t)
                              do
                              (multiple-value-bind (rt rw)
                                  (slice-with-width-reference text start length strict)
                                (multiple-value-bind (nt nw)
                                    (cadr-tui:slice-with-width text start length strict)
                                  (is (string= rt nt)
                                      "text mismatch: ~S start=~D length=~D strict=~S"
                                      text start length strict)
                                  (is (= rw nw)
                                      "width mismatch: ~S start=~D length=~D strict=~S"
                                      text start length strict)))))))))
