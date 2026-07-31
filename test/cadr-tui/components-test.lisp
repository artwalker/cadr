(in-package #:cadr-tui/tests)
(in-suite cadr-tui-suite)

(test goal9-markdown-transform-receives-exact-available-width
  (let ((seen nil))
    (let ((rendered
            (cadr-tui:render-markdown
             "answer" 58
             :transform-function
             (lambda (markdown available-width)
               (push available-width seen)
               (format nil "~A (~D)"
                       markdown available-width)))))
      (is (search "answer (58)"
                  (format nil "~{~A~^~%~}" rendered)))
      (is (equal '(58) seen)))))

(test goal9-markdown-padding-reduces-transform-width
  (let ((calls nil))
    (let ((lines
            (cadr-tui:render-markdown
             "source" 80
             :padding-x 2
             :transform-function
             (lambda (source available-width)
               (push
                (list source available-width)
                calls)
               (format nil "~A ~D"
                       source available-width)))))
      (is (equal
           '(("source" 76))
           calls))
      (is (= 80
             (cadr-tui:visible-width
              (first lines))))
      (is (search "source 76"
                  (first lines))))))

(test markdown-renders-incomplete-stream
  (let ((lines
          (cadr-tui:render-markdown
           (format nil "# 标题~%~%- one~%> quote~%```lisp~%(+ 1 2)")
           20)))
    (is (search "标题" (first lines)))
    (is (find-if (lambda (line) (search "• one" line)) lines))
    (is (find-if (lambda (line) (search "│ quote" line)) lines))
    (is (find-if (lambda (line) (search "(+ 1 2)" line)) lines))))

(test markdown-consumes-inline-delimiters
  (let ((rendered
          (format nil "~{~A~%~}"
                  (cadr-tui:render-markdown
                   "Use **bold** and `code` now."
                   40))))
    (is (search "Use bold and code now." rendered))
    (is (null (search "**" rendered)))
    (is (null (search "`" rendered)))))

(test tool-block-is-collapsible
  (let ((block
          (cadr-tui:make-tool-block
           :name "read"
           :summary "{\"path\":\"README.md\"}"
         :output (format nil "line one~%line two")
           :status :complete)))
    (is (= 4 (length
              (cadr-tui:render-tool-block block 40))))
    (cadr-tui:toggle-tool-block block)
    (is (> (length (cadr-tui:render-tool-block block 40)) 1))
    (is (search "line one"
                (format nil "~{~A~%~}"
                        (cadr-tui:render-tool-block block 40))))))

(test tool-block-recomputes-width-on-every-render
  (let ((block
          (cadr-tui:make-tool-block
           :name "bash"
           :summary
           (make-string 200
                        :initial-element #\x)
           :output
           (make-string 200
                        :initial-element #\y)
           :status :complete)))
    (dolist (width '(200 80 60))
      (dolist
          (line
           (cadr-tui:render-tool-block
            block width))
        (is
         (<=
          (cadr-tui:visible-width line)
          width))))))

(test status-bar-and-select-list
  (is (search "↑12"
              (cadr-tui:render-status-bar
               80 :model "gemini-3.6-flash"
               :input 12 :output 4 :cache 2
               :cost nil :session "abc")))
  (let ((list
          (cadr-tui:make-select-list
           :items (list
                   (cadr-tui:make-select-item :label "OpenAI / gpt" :value :gpt)
                   (cadr-tui:make-select-item :label "Google / gemini" :value :gemini))
           :height 3)))
    (cadr-tui:select-list-handle-event
     list (cadr-tui:make-input-event :kind :text :text "gem"))
    (is (= 1 (length (cadr-tui:select-list-filtered-items list))))
    (multiple-value-bind (action value)
        (cadr-tui:select-list-handle-event
         list (cadr-tui:make-input-event :kind :enter))
      (is (eq :select action))
      (is (eq :gemini value)))
    (cadr-tui:select-list-handle-event
     list (cadr-tui:make-input-event :kind :escape))
    (is (string= "gem" (cadr-tui:select-list-query list)))))

(test goal9-markdown-block-layout-matches-baseline
  (let* ((text
           (format nil
                   "# H1~%## H2~%### H3~%~%> quote~%~%- item~%~%---"))
         (lines
           (cadr-tui:render-markdown text 12))
         (plain
           (mapcar #'cadr-tui:strip-terminal-sequences
                   lines)))
    (is (string= "H1"
                 (string-right-trim " " (first plain))))
    (is (string= "H2"
                 (string-right-trim " " (second plain))))
    (is (string= "### H3"
                 (string-right-trim " " (third plain))))
    (is (find "│ quote" plain
              :test
              (lambda (expected line)
                (string=
                 expected
                 (string-right-trim " " line)))))
    (is (find "• item" plain
              :test
              (lambda (expected line)
                (string=
                 expected
                 (string-right-trim " " line)))))
    (is (find (make-string 12
                           :initial-element #\─)
              plain :test #'string=))))

(test goal9-markdown-table-uses-complete-box-and-bold-header
  (let* ((text
           (format nil
                   "| Name | Value |~%| --- | --- |~%| alpha | 1 |~%| beta | 2 |"))
         (lines
           (cadr-tui:render-markdown text 30
                                     :ansi-theme-p t))
         (plain
           (mapcar
            (lambda (line)
              (string-right-trim
               " "
               (cadr-tui:strip-terminal-sequences line)))
            lines))
         (joined (format nil "~{~A~^~%~}" plain)))
    (is (char= #\┌ (char (first plain) 0)))
    (is (find-if
         (lambda (line)
           (and (plusp (length line))
                (char= #\├ (char line 0))))
         plain))
    (is (char= #\└
               (char (car (last plain)) 0)))
    (is (search "│ Name" joined))
    (is (search "│ alpha" joined))
    (is (search
         (format nil "~C[1m" #\Escape)
         (format nil "~{~A~^~%~}" lines)))))

(test goal9-markdown-theme-uses-semantic-colors-and-local-resets
  (let* ((caps
           (cadr-tui:make-terminal-capabilities
            :images nil
            :true-color-p t
            :hyperlinks-p nil)))
    (cadr-tui:set-current-theme
     :dark :capabilities caps)
    (unwind-protect
         (let ((rendered
                 (format
                  nil "~{~A~^~%~}"
                  (cadr-tui:render-markdown
                   (format nil "# heading~%> quote~%`code` [link](https://example.com)")
                   80 :ansi-theme-p t
                   :capabilities caps))))
           (is (search
                (format nil "~C[38;2;240;198;116m"
                        #\Escape)
                rendered))
           (is (search
                (format nil "~C[38;2;128;128;128m"
                        #\Escape)
                rendered))
           (is (search
                (format nil "~C[38;2;138;190;183m"
                        #\Escape)
                rendered))
           (is (search
                (format nil "~C[39m" #\Escape)
                rendered)))
      (cadr-tui:reset-current-theme))))

(test goal9-tool-block-has-baseline-shell-padding-and-status-background
  (let* ((caps
           (cadr-tui:make-terminal-capabilities
            :images nil :true-color-p t
            :hyperlinks-p nil))
         (block
           (cadr-tui:make-tool-block
            :name "bash"
            :summary "printf ok"
            :output (format nil "one~%two")
            :status :running
            :collapsed-p nil)))
    (cadr-tui:set-current-theme
     :dark :capabilities caps)
    (unwind-protect
         (let* ((lines
                  (cadr-tui:render-tool-block
                   block 28 :ansi-theme-p t))
                (plain
                  (mapcar
                   #'cadr-tui:strip-terminal-sequences
                   lines))
                (joined
                  (format nil "~{~A~^~%~}" lines)))
           (is (string= "" (first plain)))
           (is (string=
                (make-string 28
                             :initial-element #\Space)
                (second plain)))
           (is (search "bash" (third plain)))
           (is (search "one" joined))
           (is (search
                (format nil "~C[48;2;40;40;50m"
                        #\Escape)
                joined))
           (is (every
                (lambda (line)
                  (or (string= line "")
                      (= 28
                         (cadr-tui:visible-width line))))
                lines)))
      (cadr-tui:reset-current-theme))))

(test goal9-select-list-centers-window-and-themes-selection
  (let* ((items
           (loop for index below 9
                 collect
                 (cadr-tui:make-select-item
                  :label (format nil "item-~D" index)
                  :value index
                  :description "description")))
         (selector
           (cadr-tui:make-select-list
            :items items :height 5
            :show-filter-p nil)))
    (loop repeat 6
          do
          (cadr-tui:select-list-handle-event
           selector
           (cadr-tui:make-input-event
            :kind :down)))
    (let* ((lines
             (cadr-tui:render-select-list
              selector 50 :ansi-theme-p t))
           (plain
             (mapcar
              #'cadr-tui:strip-terminal-sequences
              lines))
           (joined (format nil "~{~A~^~%~}" plain)))
      (is (= 6
             (cadr-tui::select-list-selected
              selector)))
      (is (search "→ item-6" joined))
      (is (search "item-4" joined))
      (is (search "item-8" joined))
      (is (search
           (format nil "~C[" #\Escape)
           (format nil "~{~A~^~%~}" lines))))))
