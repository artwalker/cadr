(in-package #:cadr-tui/tests)
(in-suite cadr-tui-suite)

(defun count-substring (needle haystack)
  (loop with start = 0
        for position =
          (search needle haystack :start2 start)
        while position
        count 1
        do (setf start
                 (+ position (length needle)))))

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
    (is (find-if (lambda (line) (search "- one" line)) lines))
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
    (is (null
         (search "line two"
                 (format nil "~{~A~%~}"
                         (cadr-tui:render-tool-block block 40)))))
    (cadr-tui:toggle-tool-block block)
    (is (> (length (cadr-tui:render-tool-block block 40)) 1))
    (is (search "line one"
                (format nil "~{~A~%~}"
                        (cadr-tui:render-tool-block block 40))))
    (is (search "line two"
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

(test goal9-b-bash-tool-runtime-renders-elapsed-and-took-lines
  (let ((block
          (cadr-tui:make-tool-block
           :name "bash"
           :summary "printf ok"
           :status :running
           :started-at 10d0)))
    (let ((running
            (cadr-tui:strip-terminal-sequences
             (format
              nil "~{~A~%~}"
              (cadr-tui:render-tool-block
               block 60 :now 11.26d0)))))
      (is (search "Elapsed 1.3s" running)))
    (setf
     (cadr-tui:tool-block-status block) :error
     (cadr-tui:tool-block-ended-at block) 10.04d0)
    (let ((finished
            (cadr-tui:strip-terminal-sequences
             (format
              nil "~{~A~%~}"
              (cadr-tui:render-tool-block
               block 60 :now 99d0)))))
      (is (search "Took 0.0s" finished)))))

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

(test goal9-select-list-empty-and-first-item-navigation-never-writes-negative-index
  (let ((list
          (cadr-tui:make-select-list
           :items
           (list
            (cadr-tui:make-select-item
             :label "first" :value :first)
            (cadr-tui:make-select-item
             :label "last" :value :last)))))
    (finishes
      (cadr-tui:select-list-handle-event
       list (cadr-tui:make-input-event :kind :up)))
    (is (= 1 (cadr-tui::select-list-selected list)))
    (cadr-tui:select-list-handle-event
     list (cadr-tui:make-input-event :kind :down))
    (is (zerop (cadr-tui::select-list-selected list)))
    (cadr-tui:select-list-handle-event
     list (cadr-tui:make-input-event :kind :page-up))
    (is (= 1 (cadr-tui::select-list-selected list)))
    (cadr-tui:select-list-handle-event
     list (cadr-tui:make-input-event :kind :page-down))
    (is (zerop (cadr-tui::select-list-selected list)))
    (cadr-tui:select-list-handle-event
     list (cadr-tui:make-input-event :kind :up))
    (multiple-value-bind (action value)
        (cadr-tui:select-list-handle-event
         list (cadr-tui:make-input-event :kind :enter))
      (is (eq :select action))
      (is (eq :last value))))
  (dolist (items
           (list
            nil
            (list
             (cadr-tui:make-select-item
              :label "candidate" :value :candidate))))
    (let ((list
            (cadr-tui:make-select-list
             :items items :height 3)))
      (when items
        (setf (cadr-tui::select-list-selected list) 99)
        (setf (cadr-tui:select-list-query list)
              "no-match"))
      (dolist (kind '(:up :down :page-up :page-down))
        (finishes
          (cadr-tui:select-list-handle-event
           list (cadr-tui:make-input-event :kind kind)))
        (is (zerop (cadr-tui::select-list-selected list))))
      (multiple-value-bind (action value)
          (cadr-tui:select-list-handle-event
           list (cadr-tui:make-input-event :kind :enter))
        (is (null action))
        (is (null value)))
      (is (find-if
           (lambda (line)
             (search "No matching commands" line))
           (cadr-tui:render-select-list list 40))))))

(test goal9-select-list-navigation-wraps-at-both-boundaries
  (let ((list
          (cadr-tui:make-select-list
           :items
           (loop for value in '(:first :middle :last)
                 collect
                 (cadr-tui:make-select-item
                  :label (string-downcase
                          (symbol-name value))
                  :value value)))))
    (cadr-tui:select-list-handle-event
     list (cadr-tui:make-input-event :kind :up))
    (multiple-value-bind (action value)
        (cadr-tui:select-list-handle-event
         list (cadr-tui:make-input-event :kind :enter))
      (is (eq :select action))
      (is (eq :last value)))
    (cadr-tui:select-list-handle-event
     list (cadr-tui:make-input-event :kind :down))
    (multiple-value-bind (action value)
        (cadr-tui:select-list-handle-event
         list (cadr-tui:make-input-event :kind :enter))
      (is (eq :select action))
      (is (eq :first value)))))

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
    (is (string= ""
                 (string-right-trim
                  " " (second plain))))
    (is (string= "H2"
                 (string-right-trim " " (third plain))))
    (is (string= ""
                 (string-right-trim
                  " " (fourth plain))))
    (is (string= "### H3"
                 (string-right-trim " " (fifth plain))))
    (is (find "│ quote" plain
              :test
              (lambda (expected line)
                (string=
                 expected
                 (string-right-trim " " line)))))
    (is (find "- item" plain
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
         (format nil "~{~A~^~%~}" lines)))
    ;; pi@ecac0a9c4 packages/tui/src/components/markdown.ts:807-851
    ;; emits table borders as literal box glyphs.  Only inline cell content
    ;; and the header receive theme styling.
    (is (char= #\┌ (char (first lines) 0)))
    (is
     (every
      (lambda (line)
        (let ((plain-line
                (cadr-tui:strip-terminal-sequences line)))
          (or (zerop (length plain-line))
              (not (find (char plain-line 0)
                         '(#\┌ #\│ #\├ #\└)))
              (char= (char line 0) (char plain-line 0)))))
      lines))))

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
                   (lambda (line)
                     (string-right-trim
                      " "
                      (cadr-tui:strip-terminal-sequences
                       line)))
                   lines))
                (joined
                  (format nil "~{~A~^~%~}" lines)))
           (is (string= "" (first plain)))
           (is (string= "" (second plain)))
           (is (search "$ printf ok"
                       (third plain)))
           (is (null (search "bash"
                             (third plain))))
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

(test goal9-tool-collapsed-previews-match-baseline-budgets
  (labels
      ((output (count)
         (format nil "~{~A~^~%~}"
                 (loop for index from 1 to count
                       collect
                       (format nil "line-~2,'0D" index))))
       (plain-lines (name count &key expanded-p)
         (let ((block
                 (cadr-tui:make-tool-block
                  :name name
                  :summary "args"
                  :output (output count)
                  :status :complete
                  :collapsed-p (not expanded-p))))
           (mapcar
            #'cadr-tui:strip-terminal-sequences
            (cadr-tui:render-tool-block block 72)))))
    (let ((bash (plain-lines "bash" 12)))
      (is (find-if
           (lambda (line)
             (search "7 earlier lines" line))
           bash))
      (is (null (find-if
                 (lambda (line) (search "line-07" line))
                 bash)))
      (is (find-if
           (lambda (line) (search "line-08" line))
           bash))
      (is (find-if
           (lambda (line) (search "line-12" line))
           bash)))
    (let ((collapsed-read (plain-lines "read" 12)))
      (is
       (equal
        (list
         ""
         (make-string 72 :initial-element #\Space)
         (concatenate
          'string " read args"
          (make-string 62 :initial-element #\Space))
         (make-string 72 :initial-element #\Space))
        collapsed-read))
      (is (null
           (find-if
            (lambda (line) (search "line-" line))
            collapsed-read)))
      (is (null
           (find-if
            (lambda (line) (search "more lines" line))
            collapsed-read))))
    (dolist (entry '(("write" 10)
                     ("grep" 15)
                     ("find" 20)
                     ("ls" 20)))
      (destructuring-bind (name budget) entry
        (let ((lines (plain-lines name (+ budget 2))))
          (is (find-if
               (lambda (line)
                 (search
                  (format nil "line-~2,'0D" budget)
                  line))
               lines))
          (is (null
               (find-if
                (lambda (line)
                  (search
                   (format nil "line-~2,'0D" (1+ budget))
                   line))
                lines)))
          (is (find-if
               (lambda (line)
                 (search "2 more lines" line))
               lines)))))
    (let ((expanded (plain-lines "read" 12 :expanded-p t)))
      (is (find-if
           (lambda (line) (search "line-12" line))
           expanded)))
    (let* ((block
             (cadr-tui:make-tool-block
              :name "read" :summary "missing.txt"
              :output "Offset 99 is beyond end of file"
              :status :error :collapsed-p t))
           (collapsed-error
             (mapcar
              #'cadr-tui:strip-terminal-sequences
              (cadr-tui:render-tool-block block 72))))
      (is (find-if
           (lambda (line)
             (search "Offset 99 is beyond end of file" line))
           collapsed-error)))
    (let ((caps
            (cadr-tui:make-terminal-capabilities
             :images nil :true-color-p t
             :hyperlinks-p nil)))
      (cadr-tui:set-current-theme :dark :capabilities caps)
      (unwind-protect
           (let* ((block
                    (cadr-tui:make-tool-block
                     :name "bash" :summary "args"
                     :output (output 6)
                     :status :complete
                     :collapsed-p t))
                  (rendered
                    (format nil "~{~A~^~%~}"
                            (cadr-tui:render-tool-block
                             block 72 :ansi-theme-p t))))
             (is (search
                  (format nil
                          "~C[38;2;128;128;128m... (1 earlier lines"
                          #\Escape)
                  rendered)))
        (cadr-tui:reset-current-theme)))))

(test goal10-tool-block-internal-spacers-match-baseline
  (labels
      ((plain-lines (block)
         (mapcar
          #'cadr-tui:strip-terminal-sequences
          (cadr-tui:render-tool-block block 72)))
       (blank-p (line)
         (every
          (lambda (character) (char= character #\Space))
          line)))
    (dolist (name '("read" "write" "grep" "find" "ls" "edit"))
      (let ((lines
              (plain-lines
               (cadr-tui:make-tool-block
                :name name :summary "args"
                :output "result"
                :status :complete
                :collapsed-p nil))))
        (is (blank-p (nth 3 lines))
            "~A must keep the baseline header/result spacer" name)
        (is (search "result" (nth 4 lines)))))
    (let ((lines
            (plain-lines
             (cadr-tui:make-tool-block
              :name "bash" :summary "printf result"
              :output "result"
              :status :complete
              :started-at 1d0 :ended-at 1.1d0
              :collapsed-p nil))))
      (is (blank-p (nth 3 lines)))
      (is (search "result" (nth 4 lines)))
      (is (blank-p (nth 5 lines)))
      (is (search "Took 0.1s" (nth 6 lines))))))

(test goal9-tool-preview-is-tab-normalized-and-ansi-width-safe
  (let* ((escape (string #\Escape))
         (block
           (cadr-tui:make-tool-block
            :name "bash"
            :summary "宽参数"
            :output
            (format nil
                    "~A[31m甲乙丙丁戊己庚辛~A[39m~%one~Ctwo~%three~%four~%five~%six"
                    escape escape #\Tab)
            :status :complete
            :collapsed-p t))
         (lines
           (cadr-tui:render-tool-block
            block 18 :ansi-theme-p t))
         (plain
           (mapcar #'cadr-tui:strip-terminal-sequences
                   lines)))
    (is (every
         (lambda (line)
           (or (string= line "")
               (= 18 (cadr-tui:visible-width line))))
         lines))
    (is (find-if
         (lambda (line) (search "one   two" line))
         plain))
    (is (search (format nil "~C[" #\Escape)
                (format nil "~{~A~^~%~}" lines)))))

(test goal9-tool-diff-uses-semantic-lines-and-word-inverse
  (let* ((caps
           (cadr-tui:make-terminal-capabilities
            :images nil :true-color-p t
            :hyperlinks-p nil))
         (block
           (cadr-tui:make-tool-block
            :name "edit"
            :summary "src/example.lisp"
            :output
            (format nil
                    "-12 hello brave world~%+12 hello bold world~% 13 same~Ccontext"
                    #\Tab)
            :status :complete
            :collapsed-p nil)))
    (cadr-tui:set-current-theme :dark :capabilities caps)
    (unwind-protect
         (let ((rendered
                 (format nil "~{~A~^~%~}"
                         (cadr-tui:render-tool-block
                          block 80 :ansi-theme-p t))))
           (is (search
                (format nil "~C[38;2;204;102;102m"
                        #\Escape)
                rendered))
           (is (search
                (format nil "~C[38;2;181;189;104m"
                        #\Escape)
                rendered))
           (is (search
                (format nil "~C[38;2;128;128;128m"
                        #\Escape)
                rendered))
           (is (search
                (format nil "~C[7mbrave~C[27m"
                        #\Escape #\Escape)
                rendered))
           (is (search
                (format nil "~C[7mbold~C[27m"
                        #\Escape #\Escape)
                rendered))
           (is (search "same   context"
                       (cadr-tui:strip-terminal-sequences
                        rendered))))
      (cadr-tui:reset-current-theme))))

(test goal13-tool-output-colors-are-tool-specific-while-status-backgrounds-remain
  (let* ((caps
           (cadr-tui:make-terminal-capabilities
            :images nil :true-color-p t
            :hyperlinks-p nil))
         (error-block
           (cadr-tui:make-tool-block
            :name "bash" :summary "false"
            :output "command failed" :status :error
            :collapsed-p nil))
         (warning-block
           (cadr-tui:make-tool-block
            :name "read" :summary "large.log"
            :output "[Truncated: line limit reached]"
            :status :complete :collapsed-p nil)))
    (cadr-tui:set-current-theme :dark :capabilities caps)
    (unwind-protect
         (let ((error-rendered
                 (format nil "~{~A~^~%~}"
                         (cadr-tui:render-tool-block
                          error-block 50 :ansi-theme-p t)))
               (warning-rendered
                 (format nil "~{~A~^~%~}"
                         (cadr-tui:render-tool-block
                          warning-block 50 :ansi-theme-p t))))
           (is (search
                (format nil "~C[48;2;60;40;40m"
                        #\Escape)
                error-rendered))
           (is (search
                (format nil "~C[38;2;128;128;128m"
                        #\Escape)
                error-rendered))
           (is (null
                (search
                 (format nil "~C[38;2;204;102;102m"
                         #\Escape)
                 error-rendered)))
           (is (search
                (format nil "~C[48;2;40;50;40m"
                        #\Escape)
                warning-rendered))
           (is (search
                (format nil "~C[38;2;128;128;128m"
                        #\Escape)
                warning-rendered))
           (is (null
                (search
                 (format nil "~C[38;2;255;255;0m"
                         #\Escape)
                 warning-rendered))))
      (cadr-tui:reset-current-theme))))

(test goal9-tool-output-strips-terminal-control-sequences
  (let* ((escape (string #\Escape))
         (bell (string (code-char 7)))
         (block
           (cadr-tui:make-tool-block
            :name "bash" :summary "untrusted"
            :output
            (format nil
                    "~A[2Jvisible~A]0;owned~Atext~A]52;c;c2VjcmV0~A~A[31mred~A[0m"
                    escape escape bell escape bell
                    escape escape)
            :status :complete
            :collapsed-p nil))
         (rendered
           (format nil "~{~A~^~%~}"
                   (cadr-tui:render-tool-block
                    block 80))))
    (is (search "visibletextred" rendered))
    (is (null (search "[2J" rendered)))
    (is (null (search "]0;owned" rendered)))
    (is (null (search "c2VjcmV0" rendered)))))

(test goal9-word-diff-is-bounded-for-long-minified-lines
  (let* ((old
           (format nil "~{old~D~^_~}"
                   (loop for index below 400
                         collect index)))
         (new
           (format nil "~{new~D~^_~}"
                   (loop for index below 400
                         collect index)))
         (block
           (cadr-tui:make-tool-block
            :name "edit" :summary "minified"
            :output
            (format nil "-1 ~A~%+1 ~A" old new)
            :status :complete
            :collapsed-p nil))
         (plain
           (cadr-tui:strip-terminal-sequences
            (format nil "~{~A~^~%~}"
                    (cadr-tui:render-tool-block
                     block 120
                     :ansi-theme-p t))))
         (rendered
           (format nil "~{~A~^~%~}"
                   (cadr-tui:render-tool-block
                    block 120
                    :ansi-theme-p t))))
    (is (search "old0_old1_old2" plain))
    (is (search "new0_new1_new2" plain))
    (is (null
         (search
          (format nil "~C[7m" #\Escape)
          rendered)))))

(test goal9-markdown-nested-task-and-ordered-list-markers
  (let ((caps
          (cadr-tui:make-terminal-capabilities
           :images nil :true-color-p t
           :hyperlinks-p nil)))
    (cadr-tui:set-current-theme :dark :capabilities caps)
    (unwind-protect
         (let* ((lines
                  (cadr-tui:render-markdown
                   (format nil
                           "- outer~%  - inner~%      3. ordered~%- [x] done~%- [ ] todo")
                   40 :ansi-theme-p t))
                (plain
                  (mapcar
                   (lambda (line)
                     (string-right-trim
                      " "
                      (cadr-tui:strip-terminal-sequences
                       line)))
                   lines))
                (rendered
                  (format nil "~{~A~^~%~}" lines)))
           (is (find "- outer" plain :test #'string=))
           (is (find "    - inner" plain :test #'string=))
           (is (find "        3. ordered" plain
                     :test #'string=))
           (is (find "- [x] done" plain :test #'string=))
           (is (find "- [ ] todo" plain :test #'string=))
           (is (search
                (format nil
                        "~C[38;2;138;190;183m3. ~C[39m"
                        #\Escape #\Escape)
                rendered))
           (is (search
                (format nil
                        "~C[38;2;138;190;183m- [x] ~C[39m"
                        #\Escape #\Escape)
                rendered)))
      (cadr-tui:reset-current-theme))))

(test goal9-markdown-streaming-partial-closing-fence-does-not-flicker
  (let ((without-partial
          (cadr-tui:render-markdown
           (format nil "```lisp~%(+ 1 2)") 40))
        (with-partial
          (cadr-tui:render-markdown
           (format nil "```lisp~%(+ 1 2)~%``") 40)))
    (is (equal without-partial with-partial))
    (is (null
         (search "  ``"
                 (format nil "~{~A~^~%~}"
                         with-partial))))))

(test goal9-markdown-streaming-fences-match-baseline-exactly
  (dolist
      (case
       (list
        (list
         (format nil "```ts~%const x = 1;~%``")
         '("```ts" "  const x = 1;" "```"))
        (list
         (format nil "```md~%not a closing fence:~%``~%```")
         '("```md" "  not a closing fence:" "  ``" "```"))
        (list
         (format nil "```ts~%``")
         '("```ts" "" "```"))
        (list
         (format nil "````~%```")
         '("```" "" "```"))
        (list
         (format nil "~A~%~A" "~~~~~" "~~~~")
         '("```" "" "```"))
        (list
         (format nil
                 "```md~%not a closing fence:~%``~%```~%~%after")
         '("```md" "  not a closing fence:" "  ``" "```"
           "" "after"))))
    (destructuring-bind (source expected) case
      (is (equal
           expected
           (mapcar
            (lambda (line)
              (string-right-trim
               " "
               (cadr-tui:strip-terminal-sequences line)))
            (cadr-tui:render-markdown source 80)))))))

(test goal9-markdown-narrow-table-falls-back-to-source
  (let* ((source
           (format nil
                   "| A | B | C |~%|---|---|---|~%| 1 | 2 | 3 |"))
         (lines (cadr-tui:render-markdown source 8))
         (plain
           (format nil "~{~A~^~%~}"
                   (mapcar
                    #'cadr-tui:strip-terminal-sequences
                    lines))))
    (is (search "| A |" plain))
    (is (search "|---|" plain))
    (is (null (search "┌" plain)))
    (is (every
         (lambda (line)
           (<= (cadr-tui:visible-width line) 8))
         lines))))

(test goal9-markdown-syntax-highlight-hook-is-theme-neutral
  (let ((calls nil)
        (escape (string #\Escape))
        (caps
          (cadr-tui:make-terminal-capabilities
           :images nil :true-color-p t
           :hyperlinks-p nil)))
    (cadr-tui:set-current-theme :dark :capabilities caps)
    (unwind-protect
         (progn
           (let ((rendered
                   (format
                    nil "~{~A~^~%~}"
                    (cadr-tui:render-markdown
                     (format nil "```lisp~%(+ 1 2)~%```") 40
                     :ansi-theme-p t
                     :syntax-highlight-function
                     (lambda (language source)
                       (push (list language source) calls)
                       (format nil "~A[35m~A~A[39m"
                               escape source escape))))))
             (is (equal '(("lisp" "(+ 1 2)")) calls))
             (is (search
                  (format nil "~C[35m(+ 1 2)~C[39m"
                          #\Escape #\Escape)
                  rendered)))
           (let ((fallback
                   (format
                    nil "~{~A~^~%~}"
                    (cadr-tui:render-markdown
                     (format nil "```unknown~%text~%```") 40
                     :ansi-theme-p t
                     :syntax-highlight-function
                     (lambda (language source)
                       (declare (ignore language source))
                       nil)))))
             (is (search
                  (format nil
                          "~C[38;2;181;189;104mtext~C[39m"
                          #\Escape #\Escape)
                  fallback))))
      (cadr-tui:reset-current-theme))))

(test goal9-markdown-headings-space-following-blocks-and-restore-style
  (let ((caps
          (cadr-tui:make-terminal-capabilities
           :images nil :true-color-p t
           :hyperlinks-p nil)))
    (cadr-tui:set-current-theme :dark :capabilities caps)
    (unwind-protect
         (let* ((lines
                  (cadr-tui:render-markdown
                   (format nil
                           "### Head `code` tail~%paragraph")
                   80 :ansi-theme-p t
                   :capabilities caps))
                (plain
                  (mapcar
                   (lambda (line)
                     (string-right-trim
                      " "
                      (cadr-tui:strip-terminal-sequences
                       line)))
                   lines))
                (rendered
                  (format nil "~{~A~^~%~}" lines))
                (heading-prefix
                  (format nil
                          "~C[38;2;240;198;116m~C[1m"
                          #\Escape #\Escape)))
           (is (string= "### Head code tail"
                        (first plain)))
           (is (string= "" (second plain)))
           (is (string= "paragraph"
                        (third plain)))
           (is (>=
                (count-substring
                 heading-prefix rendered)
                2)))
      (cadr-tui:reset-current-theme))))

(test goal9-markdown-list-markers-and-continuations-match-baseline
  (let* ((source
           (format nil
                   "* alpha beta gamma delta epsilon~%  7) ordered item"))
         (lines
           (cadr-tui:render-markdown
            source 18
            :preserve-list-markers-p t))
         (plain
           (mapcar
            (lambda (line)
              (string-right-trim
               " "
               (cadr-tui:strip-terminal-sequences
                line)))
            lines)))
    (is (uiop:string-prefix-p "* " (first plain)))
    (is (uiop:string-prefix-p "  "
                              (second plain)))
    (is (not
         (uiop:string-prefix-p "* "
                               (second plain))))
    (is (find-if
         (lambda (line)
           (uiop:string-prefix-p "    7) " line))
         plain)))
  (let ((caps
          (cadr-tui:make-terminal-capabilities
           :images nil :true-color-p t
           :hyperlinks-p nil)))
    (cadr-tui:set-current-theme :dark :capabilities caps)
    (unwind-protect
         (let ((rendered
                 (first
                  (cadr-tui:render-markdown
                   "- alpha" 18
                   :ansi-theme-p t
                   :capabilities caps))))
           (is
            (search
             (cadr-tui:theme-foreground
              :md-list-bullet "- " :enabled-p t)
             rendered)))
      (cadr-tui:reset-current-theme))))

(test goal9-markdown-quote-restores-outer-style-after-inline-reset
  (let ((caps
          (cadr-tui:make-terminal-capabilities
           :images nil :true-color-p t
           :hyperlinks-p nil)))
    (cadr-tui:set-current-theme :dark :capabilities caps)
    (unwind-protect
         (let* ((rendered
                  (format
                   nil "~{~A~^~%~}"
                   (cadr-tui:render-markdown
                    "> before `code` after"
                    80 :ansi-theme-p t
                    :capabilities caps)))
                (quote-prefix
                  (format nil
                          "~C[38;2;128;128;128m~C[3m"
                          #\Escape #\Escape)))
           (is (>=
                (count-substring
                 quote-prefix rendered)
                2))
           (is (search
                "│ before code after"
                (cadr-tui:strip-terminal-sequences
                 rendered))))
      (cadr-tui:reset-current-theme))))

(test goal17-footer-low-context-keeps-the-baseline-single-dim-run
  ;; footer.ts:210-215 dims statsLeft as one span when context usage is below
  ;; the warning threshold; it does not restyle the context substring alone.
  (let ((caps
          (cadr-tui:make-terminal-capabilities
           :images nil :true-color-p t :hyperlinks-p nil)))
    (cadr-tui:set-current-theme :dark :capabilities caps)
    (unwind-protect
         (let* ((line
                  (second
                   (cadr-tui:render-footer
                    72 :model "faux-1" :input 3 :output 4
                    :context-percent 2d0 :context-window 128000
                    :auto-compact-p t :ansi-theme-p t)))
                (whole
                  (cadr-tui:theme-foreground
                   :dim "↑3 ↓4 2.0%/128k (auto)" :enabled-p t))
                (context-only
                  (cadr-tui:theme-foreground
                   :dim "2.0%/128k (auto)" :enabled-p t)))
           (is (search whole line))
           (is (null (search context-only line))))
      (cadr-tui:reset-current-theme))))

(test goal17-autocomplete-unselected-description-owns-the-column-gap
  ;; Fixed pi@ecac0a9c4 select-list.ts:139-171 keeps the unselected prefix
  ;; and primary label plain, then starts the dim description span at the
  ;; entire inter-column gap.  This locks the span boundary independently of
  ;; a terminal screen diff.
  (let ((caps
          (cadr-tui:make-terminal-capabilities
           :images nil :true-color-p t :hyperlinks-p nil)))
    (cadr-tui:set-current-theme :dark :capabilities caps)
    (unwind-protect
         (let* ((width 64)
                (label "model")
                (description "Select model")
                (primary-width 16)
                (gap (make-string 11 :initial-element #\Space))
                (line
                  (cadr-tui::render-editor-autocomplete-item
                   (cadr-tui:make-autocomplete-item
                    :value "model" :label label
                    :description description)
                   nil width primary-width))
                (expected-prefix
                  (concatenate
                   'string "  " label
                   (cadr-tui:theme-foreground
                    :muted
                    (concatenate 'string gap description)
                    :enabled-p t)))
                (wrong-boundary
                  (concatenate
                   'string "  " label gap
                   (cadr-tui:theme-foreground
                    :muted description :enabled-p t))))
           (is (zerop (or (search expected-prefix line) -1)))
           (is (null (search wrong-boundary line)))
           (is (= width (cadr-tui:visible-width line))))
      (cadr-tui:reset-current-theme))))

(test list-hover-does-not-move-the-centered-selection
  (dolist (row '(0 4))
    (let ((list
            (cadr-tui:make-select-list
             :height 5
             :items
             (loop for index below 12
                   collect
                   (cadr-tui:make-select-item
                    :label (format nil "Item ~D" index)
                    :value (format nil "item-~D" index))))))
      (setf (cadr-tui::select-list-selected list) 5)
      (is (eq :scroll
              (cadr-tui:select-list-handle-mouse
               list :type :wheel :wheel-delta 1 :y row)))
      (is (= 6 (cadr-tui::select-list-selected list)))
      (let ((before (cadr-tui:render-select-list list 80)))
        (dolist (y '(0 1 2 3 4))
          (is (null
               (cadr-tui:select-list-handle-mouse
                list :type :move :button :none :y y)))
          (is (equal before (cadr-tui:render-select-list list 80))))
        (is (= 6 (cadr-tui::select-list-selected list)))
        (is (eq :press
                (cadr-tui:select-list-handle-mouse
                 list :type :press :button :left :y row)))
        (multiple-value-bind (action value)
            (cadr-tui:select-list-handle-mouse
             list :type :click :button :left :y row)
          (is (eq :select action))
          (is (string= (format nil "item-~D" (+ 4 row)) value)))))))
