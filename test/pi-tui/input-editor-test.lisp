(in-package #:pi-tui/tests)
(in-suite pi-tui-suite)

(defun event-kinds (events)
  (mapcar #'pi-tui:input-event-kind events))

(test input-decoder-handles-keys-and-fragmented-paste
  (let ((decoder (pi-tui:make-input-decoder)))
    (is (equal '(:text :left :newline)
               (event-kinds
                (pi-tui:feed-input decoder
                                   (format nil "中~C[D~C[13;2u"
                                           #\Escape #\Escape)))))
    (is (null
         (pi-tui:feed-input decoder
                            (format nil "~C[200~~a~%" #\Escape))))
    (let ((events
            (pi-tui:feed-input decoder
                               (format nil "b~C[201~~" #\Escape))))
      (is (= 1 (length events)))
      (is (eq :paste
              (pi-tui:input-event-kind (first events))))
      (is (string= (format nil "a~%b")
                   (pi-tui:input-event-text (first events)))))))

(test multiline-editor-edits-by-grapheme-and-submits
  (let ((editor (pi-tui:make-multiline-editor)))
    (pi-tui:editor-handle-event
     editor (pi-tui:make-input-event :kind :text :text "Aé中"))
    (pi-tui:editor-handle-event
     editor (pi-tui:make-input-event :kind :left))
    (pi-tui:editor-handle-event
     editor (pi-tui:make-input-event :kind :backspace))
    (is (string= "A中" (pi-tui:editor-text editor)))
    (pi-tui:editor-handle-event
     editor (pi-tui:make-input-event :kind :newline))
    (pi-tui:editor-handle-event
     editor (pi-tui:make-input-event :kind :paste
                                     :text (format nil "x~Cy" #\Return)))
    (multiple-value-bind (action value)
        (pi-tui:editor-handle-event
         editor (pi-tui:make-input-event :kind :enter))
      (is (eq :submit action))
      (is (string= (format nil "A~%x~%y中") value)))
    (is (string= "" (pi-tui:editor-text editor)))
    (pi-tui:editor-handle-event
     editor (pi-tui:make-input-event :kind :up))
    (is (string= (format nil "A~%x~%y中")
                 (pi-tui:editor-text editor)))))

(test editor-render-reports-cell-cursor
  (let ((editor (pi-tui:make-multiline-editor :prompt "› ")))
    (pi-tui:editor-handle-event
     editor (pi-tui:make-input-event :kind :text :text "ab中文"))
    (multiple-value-bind (lines row column)
        (pi-tui:render-editor editor 6)
      (is (equal '("› ab中" "  文") lines))
      (is (= 1 row))
      (is (= 4 column)))))
