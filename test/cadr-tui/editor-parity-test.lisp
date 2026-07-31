(in-package #:cadr-tui/tests)
(in-suite cadr-tui-suite)

(defun editor-event (editor kind &optional text)
  (cadr-tui:editor-handle-event
   editor
   (cadr-tui:make-input-event :kind kind :text text)))

(defun editor-type (editor text)
  (loop for cluster in (cadr-tui:grapheme-clusters text)
        do (editor-event editor :text cluster))
  editor)

(defun editor-cursor-values (editor)
  (multiple-value-list (cadr-tui:editor-cursor editor)))

(defun editor-render-plain-lines (lines)
  (mapcar #'cadr-tui:strip-terminal-sequences lines))

(test editor-history-state-and-normalization-match-reference
  (let ((editor (cadr-tui:make-multiline-editor)))
    (cadr-tui:editor-add-history editor "first")
    (cadr-tui:editor-add-history editor "second")
    (cadr-tui:editor-add-history editor "second")
    (editor-event editor :up)
    (is (string= "second" (cadr-tui:editor-text editor)))
    (is (equal '(0 0) (editor-cursor-values editor)))
    (editor-event editor :up)
    (is (string= "first" (cadr-tui:editor-text editor)))
    (editor-event editor :down)
    (is (string= "second" (cadr-tui:editor-text editor)))
    (is (equal '(0 6) (editor-cursor-values editor)))
    (editor-event editor :down)
    (is (string= "" (cadr-tui:editor-text editor)))
    (cadr-tui:editor-set-text
     editor
     (format nil "A~CB~CC~CD" #\Return #\Newline #\Tab))
    (is (string= (format nil "A~%B~%C    D")
                 (cadr-tui:editor-text editor)))
    (let ((lines (cadr-tui:editor-lines editor)))
      (setf (first lines) "mutated")
      (is (string= "A"
                   (first (cadr-tui:editor-lines editor)))))))

(test editor-backslash-enter-and-programmatic-insert
  (let ((editor (cadr-tui:make-multiline-editor)))
    (editor-type editor "\\")
    (multiple-value-bind (action value)
        (editor-event editor :enter)
      (is (null action))
      (is (null value)))
    (is (string= (string #\Newline)
                 (cadr-tui:editor-text editor)))
    (cadr-tui:editor-insert-text-at-cursor
     editor
     (format nil "a~Cb~Cc~Cd" #\Return #\Newline #\Tab))
    (is (string= (format nil "~%a~%b~%c    d")
                 (cadr-tui:editor-text editor)))
    (editor-event editor :undo)
    (is (string= (string #\Newline)
                 (cadr-tui:editor-text editor)))))

(test editor-kill-ring-yank-pop-and-undo
  (let ((editor
          (cadr-tui:make-multiline-editor
           :text "one two three")))
    (editor-event editor :delete-word-backward)
    (editor-event editor :delete-word-backward)
    (editor-event editor :delete-word-backward)
    (is (string= "" (cadr-tui:editor-text editor)))
    (editor-event editor :yank)
    (is (string= "one two three"
                 (cadr-tui:editor-text editor)))
    (editor-event editor :undo)
    (is (string= "" (cadr-tui:editor-text editor)))
    (cadr-tui:editor-set-text editor "alpha")
    (editor-event editor :delete-word-backward)
    (cadr-tui:editor-set-text editor "")
    (editor-event editor :yank)
    (is (string= "alpha" (cadr-tui:editor-text editor)))
    (editor-event editor :yank-pop)
    (is (string= "one two three"
                 (cadr-tui:editor-text editor)))))

(test editor-word-navigation-cjk-punctuation-and-multiline-kills
  (let ((editor
          (cadr-tui:make-multiline-editor
           :text (format nil "foo.bar~%你好，世界"))))
    (editor-event editor :word-left)
    (is (equal '(1 3) (editor-cursor-values editor)))
    (editor-event editor :delete-word-backward)
    (is (string= (format nil "foo.bar~%你好世界")
                 (cadr-tui:editor-text editor)))
    (editor-event editor :line-start)
    (editor-event editor :delete-word-backward)
    (is (string= "foo.bar你好世界"
                 (cadr-tui:editor-text editor)))
    (editor-event editor :line-start)
    (editor-event editor :delete-word-forward)
    (is (string= ".bar你好世界"
                 (cadr-tui:editor-text editor)))))

(test editor-paste-is-atomic-and-large-pastes-expand-literally
  (let ((editor
          (cadr-tui:make-multiline-editor :text "before after")))
    (loop repeat 5 do (editor-event editor :left))
    (editor-event editor :paste
                  (format nil "one~C~Ctwo~Cthree"
                          #\Return #\Newline #\Tab))
    (is (string= (format nil "before one~%two    threeafter")
                 (cadr-tui:editor-text editor)))
    (editor-event editor :undo)
    (is (string= "before after"
                 (cadr-tui:editor-text editor))))
  (let* ((editor (cadr-tui:make-multiline-editor))
         (payload (make-string 1001 :initial-element #\x)))
    (editor-event editor :paste payload)
    (is (search "[paste #1 1001 chars]"
                (cadr-tui:editor-text editor)))
    (is (string= payload
                 (cadr-tui:editor-expanded-text editor)))
    (editor-event editor :left)
    (editor-event editor :delete)
    (is (string= "" (cadr-tui:editor-text editor)))
    (editor-event editor :undo)
    (is (string= payload
                 (cadr-tui:editor-expanded-text editor)))))

(test editor-renumbers-multiple-paste-markers-and-undo-restores-registry
  (let* ((editor (cadr-tui:make-multiline-editor))
         (first (make-string 1001 :initial-element #\a))
         (second (make-string 1001 :initial-element #\b)))
    (editor-event editor :paste first)
    (editor-event editor :text " ")
    (editor-event editor :paste second)
    (is (search "[paste #1 1001 chars]"
                (cadr-tui:editor-text editor)))
    (is (search "[paste #2 1001 chars]"
                (cadr-tui:editor-text editor)))
    (editor-event editor :line-start)
    (editor-event editor :delete)
    (is (not (search "[paste #2"
                     (cadr-tui:editor-text editor))))
    (is (search "[paste #1 1001 chars]"
                (cadr-tui:editor-text editor)))
    (is (string=
         (concatenate 'string " " second)
         (cadr-tui:editor-expanded-text editor)))
    (editor-event editor :undo)
    (is (string=
         (concatenate 'string first " " second)
         (cadr-tui:editor-expanded-text editor)))))

(test editor-character-jump-and-sticky-column
  (let ((editor
          (cadr-tui:make-multiline-editor
           :text (format nil "abcdef~%x~%abcdef"))))
    (editor-event editor :up)
    (is (equal '(1 1) (editor-cursor-values editor)))
    (editor-event editor :up)
    (is (equal '(0 6) (editor-cursor-values editor)))
    (editor-event editor :down)
    (editor-event editor :left)
    (editor-event editor :up)
    (is (equal '(0 0) (editor-cursor-values editor)))
    (editor-event editor :jump-forward)
    (editor-event editor :text "f")
    (is (equal '(0 5) (editor-cursor-values editor)))
    (editor-event editor :jump-forward)
    (editor-event editor :text "f")
    (is (equal '(2 5) (editor-cursor-values editor)))
    (editor-event editor :jump-backward)
    (editor-event editor :text "x")
    (is (equal '(1 0) (editor-cursor-values editor)))))

(test editor-sticky-column-navigates-wrapped-visual-lines
  (let ((editor
          (cadr-tui:make-multiline-editor
           :text "abcdefghijk" :prompt "")))
    (cadr-tui:render-editor editor 5)
    (editor-event editor :up)
    (is (equal '(0 7) (editor-cursor-values editor)))
    (editor-event editor :up)
    (is (equal '(0 3) (editor-cursor-values editor)))
    (editor-event editor :down)
    (is (equal '(0 7) (editor-cursor-values editor)))))

(test editor-autocomplete-popup-selection-and-undo
  (let* ((provider
           (cadr-tui:make-autocomplete-provider
            :commands
            (list
             (cadr-tui:make-autocomplete-command
              :name "help" :description "show help")
             (cadr-tui:make-autocomplete-command
              :name "history" :description "show history"))))
         (editor (cadr-tui:make-multiline-editor)))
    (cadr-tui:editor-set-autocomplete-provider editor provider)
    (editor-event editor :text "/")
    (is (cadr-tui:editor-autocomplete-visible-p editor))
    (is (= 2 (length
              (cadr-tui:editor-autocomplete-items editor))))
    (multiple-value-bind (lines row column)
        (cadr-tui:render-editor editor 20)
      (declare (ignore row column))
      (is (some
           (lambda (line)
             (search "history" line))
           lines)))
    (editor-event editor :down)
    (editor-event editor :tab)
    (is (string= "/history "
                 (cadr-tui:editor-text editor)))
    (is (not (cadr-tui:editor-autocomplete-visible-p editor)))
    (editor-event editor :undo)
    (is (string= "/" (cadr-tui:editor-text editor)))
    (multiple-value-bind (lines row column)
        (cadr-tui:render-editor editor 20)
      (declare (ignore row column))
      (is (every (lambda (line)
                   (<= (cadr-tui:visible-width line) 20))
                 lines)))))

(test editor-enter-applies-and-submits-slash-completion
  (let* ((provider
           (cadr-tui:make-autocomplete-provider
            :commands
            (list
             (cadr-tui:make-autocomplete-command
              :name "help"))))
         (editor (cadr-tui:make-multiline-editor)))
    (cadr-tui:editor-set-autocomplete-provider editor provider)
    (editor-event editor :text "/")
    (multiple-value-bind (action value)
        (editor-event editor :enter)
      (is (eq :submit action))
      (is (string= "/help" value)))
    (is (string= "" (cadr-tui:editor-text editor)))))

(test editor-word-wrap-keeps-boundaries-and-wide-cells
  (let ((editor
          (cadr-tui:make-multiline-editor
           :text "alpha beta中文"
           :prompt "")))
    (multiple-value-bind (lines row column)
        (cadr-tui:render-editor editor 7)
      (declare (ignore row column))
      (let ((plain
              (editor-render-plain-lines lines)))
        (is (string= "───────"
                     (first plain)))
        (is (equal '("alpha" "beta中" "文")
                   (mapcar
                    (lambda (line)
                      (string-right-trim '(#\Space) line))
                    (subseq plain 1 (1- (length plain))))))
        (is (string= "───────"
                     (car (last plain)))))
      (is (every (lambda (line)
                   (<= (cadr-tui:visible-width line) 7))
                 lines)))))

(test editor-renders-horizontal-borders-and-thirty-percent-viewport
  (let ((editor
          (cadr-tui:make-multiline-editor
           :text
           (format nil
                   "zero~%one~%two~%three~%four~%five~%six~%seven"))))
    (multiple-value-bind (lines row column)
        (cadr-tui:render-editor
         editor 16 :terminal-rows 10)
      (let ((plain (editor-render-plain-lines lines)))
        (is (= 7 (length plain)))
        (is (search "↑ 3 more" (first plain)))
        (is (equal '("three" "four" "five" "six" "seven")
                   (mapcar
                    (lambda (line)
                      (string-right-trim '(#\Space) line))
                    (subseq plain 1 6))))
        (is (string=
             (make-string 16 :initial-element #\─)
             (car (last plain))))
        (is (string=
             (cadr-tui:theme-foreground
              :border
              (make-string 16 :initial-element #\─))
             (car (last lines))))
        (is (= 5 row))
        (is (= 5 column))
        (is (every
             (lambda (line)
               (= 16 (cadr-tui:visible-width line)))
             lines))))))

(test editor-fake-cursor-covers-whole-grapheme-and-keeps-ime-position
  (let ((editor
          (cadr-tui:make-multiline-editor
           :text "A你🙂" :prompt "")))
    (editor-event editor :left)
    (multiple-value-bind (lines row column)
        (cadr-tui:render-editor
         editor 12 :terminal-rows 24 :focused-p t)
      (is (= 1 row))
      (is (= 3 column))
      (is (search
           (format nil "~C[7m🙂~C[27m"
                   #\Escape #\Escape)
           (second lines)))
      (is (= 12 (cadr-tui:visible-width (second lines)))))
    (editor-event editor :left)
    (multiple-value-bind (lines row column)
        (cadr-tui:render-editor
         editor 12 :terminal-rows 24 :focused-p t)
      (is (= 1 row))
      (is (= 1 column))
      (is (search
           (format nil "~C[7m你~C[27m"
                   #\Escape #\Escape)
           (second lines))))
    (cadr-tui:editor-set-text editor "行尾")
    (multiple-value-bind (lines row column)
        (cadr-tui:render-editor
         editor 12 :terminal-rows 24 :focused-p t)
      (is (= 1 row))
      (is (= 4 column))
      (is (search
           (format nil "~C[7m ~C[27m"
                   #\Escape #\Escape)
           (second lines))))))

(test editor-unfocused-overlay-state-keeps-logical-cursor-without-fake-cursor
  (let ((editor
          (cadr-tui:make-multiline-editor
           :text "你🙂" :prompt "")))
    (editor-event editor :left)
    (multiple-value-bind (lines row column)
        (cadr-tui:render-editor
         editor 10 :terminal-rows 24 :focused-p nil)
      (is (= 1 row))
      (is (= 2 column))
      (is (null
           (search (format nil "~C[7m" #\Escape)
                   (second lines)))))))

(test editor-autocomplete-centers-selection-after-bottom-border
  (let* ((commands
           (loop for index below 8
                 collect
                 (cadr-tui:make-autocomplete-command
                  :name (format nil "command-~D" index)
                  :description
                  (format nil "description ~D" index))))
         (provider
           (cadr-tui:make-autocomplete-provider
            :commands commands))
         (editor
           (cadr-tui:make-multiline-editor :prompt "")))
    (cadr-tui:editor-set-autocomplete-provider editor provider)
    (editor-event editor :text "/")
    (loop repeat 5 do (editor-event editor :down))
    (multiple-value-bind (lines row column)
        (cadr-tui:render-editor
         editor 60 :terminal-rows 24)
      (declare (ignore column))
      (let* ((plain (editor-render-plain-lines lines))
             (bottom-border-position
               (position
                (make-string 60 :initial-element #\─)
                plain :test #'string=
                :from-end t))
             (popup
               (subseq plain (1+ bottom-border-position)))
             (styled-popup
               (subseq lines (1+ bottom-border-position)))
             (selected-position
               (position-if
                (lambda (line)
                  (search "→ command-5" line))
                popup)))
        (is (= 1 row))
        (is (= 6 (length popup)))
        (is (some
             (lambda (line)
               (and (search "→ command-5" line)
                    (search "description 5" line)))
             popup))
        (is (search
             (cadr-tui:theme-foreground-ansi :accent)
             (nth selected-position styled-popup)))
        (is (some
             (lambda (line)
               (search "(6/8)" line))
             popup))
        (is (every
             (lambda (line)
               (= 60 (cadr-tui:visible-width line)))
             lines))))))
