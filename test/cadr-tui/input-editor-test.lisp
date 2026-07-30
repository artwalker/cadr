(in-package #:cadr-tui/tests)
(in-suite cadr-tui-suite)

(defun event-kinds (events)
  (mapcar #'cadr-tui:input-event-kind events))

(test input-decoder-handles-keys-and-fragmented-paste
  (let ((decoder (cadr-tui:make-input-decoder)))
    (is (equal '(:text :left :newline)
               (event-kinds
                (cadr-tui:feed-input decoder
                                   (format nil "中~C[D~C[13;2u"
                                           #\Escape #\Escape)))))
    (is (null
         (cadr-tui:feed-input decoder
                            (format nil "~C[200~~a~%" #\Escape))))
    (let ((events
            (cadr-tui:feed-input decoder
                               (format nil "b~C[201~~" #\Escape))))
      (is (= 1 (length events)))
      (is (eq :paste
              (cadr-tui:input-event-kind (first events))))
      (is (string= (format nil "a~%b")
                   (cadr-tui:input-event-text (first events)))))))

(test multiline-editor-edits-by-grapheme-and-submits
  (let ((editor (cadr-tui:make-multiline-editor)))
    (cadr-tui:editor-handle-event
     editor (cadr-tui:make-input-event :kind :text :text "Aé中"))
    (cadr-tui:editor-handle-event
     editor (cadr-tui:make-input-event :kind :left))
    (cadr-tui:editor-handle-event
     editor (cadr-tui:make-input-event :kind :backspace))
    (is (string= "A中" (cadr-tui:editor-text editor)))
    (cadr-tui:editor-handle-event
     editor (cadr-tui:make-input-event :kind :newline))
    (cadr-tui:editor-handle-event
     editor (cadr-tui:make-input-event :kind :paste
                                     :text (format nil "x~Cy" #\Return)))
    (multiple-value-bind (action value)
        (cadr-tui:editor-handle-event
         editor (cadr-tui:make-input-event :kind :enter))
      (is (eq :submit action))
      (is (string= (format nil "A~%x~%y中") value)))
    (is (string= "" (cadr-tui:editor-text editor)))
    (cadr-tui:editor-handle-event
     editor (cadr-tui:make-input-event :kind :up))
    (is (string= (format nil "A~%x~%y中")
                 (cadr-tui:editor-text editor)))))

(test editor-render-reports-cell-cursor
  (let ((editor (cadr-tui:make-multiline-editor :prompt "› ")))
    (cadr-tui:editor-handle-event
     editor (cadr-tui:make-input-event :kind :text :text "ab中文"))
    (multiple-value-bind (lines row column)
        (cadr-tui:render-editor editor 6)
      (is (equal '("› ab中" "  文") lines))
      (is (= 1 row))
      (is (= 4 column)))))
