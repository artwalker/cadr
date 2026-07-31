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
    (setf (cadr-tui:select-list-query list) "a-very")
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
           (format nil "~{~A~%~}" lines)))
    (is (search "Header" joined))
    (is (search "• item" joined))
    (is (search "1. ordered" joined))
    (is (search "│ quote" joined))
    (is (search "bold" joined))
    (is (search "italic" joined))
    (is (search "gone" joined))
    (is (search "code" joined))
    (is (search "https://example.com" joined))
    (is (search "│ A" joined))
    (is (search "(+ 1 2)" joined))
    (is (search "Image: alt (image.png)" joined))
    (is (search "───" joined))
    (is (search (format nil "~C[" #\Escape) joined))
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
