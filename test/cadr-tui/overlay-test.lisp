(in-package #:cadr-tui/tests)

(in-suite cadr-tui-suite)

(test overlay-layout-covers-anchors-percentages-margins-and-clamping
  (flet ((layout (&rest options)
           (apply #'cadr-tui:resolve-overlay-layout
                  100 30 20 options)))
    (is (equal '(40 5 30 nil)
               (multiple-value-list
                (layout :width 40 :anchor :center))))
    (is (equal '(20 0 0 nil)
               (multiple-value-list
                (layout :width "20%"
                        :anchor :top-left))))
    (is (equal '(30 10 70 nil)
               (multiple-value-list
                (layout :width 30
                        :anchor :bottom-right))))
    (is (equal '(40 3 45 nil)
               (multiple-value-list
                (layout :width 40 :row "30%"
                        :col "75%"))))
    (is (equal '(88 5 6 26)
               (multiple-value-list
                (layout :width 95 :min-width 99
                        :max-height "90%"
                        :margin
                        '(:top 2 :right 6
                          :bottom 2 :left 6)))))
    (is (equal '(20 9 15 8)
               (multiple-value-list
                (layout :width 20 :max-height 8
                        :row 7 :col 13
                        :offset-x 2 :offset-y 2))))))

(test overlay-compositing-is-cell-safe-and-style-isolated
  (let* ((reset
           (format nil "~C[0m~C]8;;~C"
                   #\Escape #\Escape
                   (code-char 7)))
         (inside
           (cadr-tui:composite-overlay-line
            "abcd让EFGH" "│XX│" 5 4 20))
         (boundary
           (cadr-tui:composite-overlay-line
            "abcd让EFGH" "│XX│" 4 4 20))
         (styled
           (cadr-tui:composite-overlay-line
            (format nil "~C[31mabcdefghij~C[0m"
                    #\Escape #\Escape)
            "XX" 3 2 10)))
    (is (not (search "让" inside)))
    (is (= 20 (cadr-tui:visible-width inside)))
    (is (search "│XX│"
                (cadr-tui:slice-by-column
                 inside 5 4 t)))
    (is (not (search "让" boundary)))
    (is (= 20 (cadr-tui:visible-width boundary)))
    (is (search reset styled))
    (is (= 10 (cadr-tui:visible-width styled)))))

(test overlay-frame-snapshot-handles-short-content-cjk-and-stacking
  (let* ((first
           (cadr-tui:make-overlay-placement
            :lines '("TOP" "MID" "BOT")
            :width 10
            :anchor :center))
         (second
           (cadr-tui:make-overlay-placement
            :lines '("中文")
            :width 6
            :row 1 :col 2))
         (frame
           (cadr-tui:composite-overlay-frame
            '("Line 1" "Line 2" "Line 3")
            (list first second)
            20 8)))
    (is (= 8 (length frame)))
    (is (search "TOP" (nth 2 frame)))
    (is (search "MID" (nth 3 frame)))
    (is (search "BOT" (nth 4 frame)))
    (is (search "中文" (nth 1 frame)))
    (is (every (lambda (line)
                 (= 20 (cadr-tui:visible-width line)))
               frame))))

(test overlay-focus-stack-matches-capturing-and-non-capturing-semantics
  (let ((stack
          (cadr-tui:make-overlay-stack
           :focused-component :editor)))
    (let ((help
            (cadr-tui:overlay-stack-show
             stack :help '("help")
             :non-capturing-p t))
          (picker
            (cadr-tui:overlay-stack-show
             stack :picker '("pick"))))
      (is (eq :picker
              (cadr-tui:overlay-stack-input-target stack)))
      (is (cadr-tui:overlay-handle-focused-p picker))
      (is (not
           (cadr-tui:overlay-handle-focused-p help)))
      (cadr-tui:overlay-handle-set-hidden picker t)
      (is (eq :editor
              (cadr-tui:overlay-stack-input-target stack)))
      (is (cadr-tui:overlay-stack-visible-p stack))
      (cadr-tui:overlay-handle-set-hidden picker nil)
      (is (eq :picker
              (cadr-tui:overlay-stack-input-target stack)))
      (cadr-tui:overlay-handle-unfocus
       picker :target :editor)
      (is (eq :editor
              (cadr-tui:overlay-stack-input-target stack)))
      (cadr-tui:overlay-handle-focus picker)
      (is (eq :picker
              (cadr-tui:overlay-stack-input-target stack)))
      (cadr-tui:overlay-handle-hide picker)
      (is (eq :editor
              (cadr-tui:overlay-stack-input-target stack)))
      (cadr-tui:overlay-handle-hide help)
      (is (not
           (cadr-tui:overlay-stack-visible-p stack))))))
