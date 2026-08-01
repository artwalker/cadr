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

(test input-decoder-emits-configurable-editor-actions
  (let ((decoder (cadr-tui:make-input-decoder)))
    (is (equal
         '(:enter)
         (event-kinds
          (cadr-tui:feed-input
           decoder (string #\Return)))))
    (is
     (equal
      '(:line-start :line-end
        :delete-line-end :delete-word-backward
        :yank :undo :word-left :word-right
        :delete-word-forward :yank-pop
        :jump-forward :jump-backward)
      (event-kinds
       (cadr-tui:feed-input
        decoder
        (format nil
                "~C~C~C~C~C~C~C[1;5D~C[1;5C~Cd~Cy~C~C~C"
                (code-char 1)
                (code-char 5)
                (code-char 11)
                (code-char 23)
                (code-char 25)
                (code-char 31)
                #\Escape
                #\Escape
                #\Escape
                #\Escape
                (code-char 29)
                #\Escape
                (code-char 29))))))
    (let ((events
            (cadr-tui:feed-input
             decoder
             (format nil "~C[97u~C[45;5u"
                     #\Escape #\Escape))))
      (is (equal '(:text :undo)
                 (event-kinds events)))
      (is (string=
           "a"
           (cadr-tui:input-event-text
           (first events)))))))

(test input-decoder-preserves-configurable-alt-key-actions
  (let ((previous (cadr-tui:get-keybindings)))
    (unwind-protect
         (progn
           (cadr-tui:set-keybindings
            (cadr-tui:make-keybindings-manager))
           (let ((events
                   (cadr-tui:feed-input
                    (cadr-tui:make-input-decoder)
                    (format nil "~Cp" #\Escape))))
             (is (equal '(:dequeue) (event-kinds events)))))
      (cadr-tui:set-keybindings previous))))

(test input-decoder-handles-real-xterm-and-windows-alt-sequences
  (let ((previous (cadr-tui:get-keybindings)))
    (unwind-protect
         (progn
           (cadr-tui:set-keybindings
            (cadr-tui:make-keybindings-manager))
           (dolist
               (case
                `((,(format nil "~C[1;3A" #\Escape)
                   :dequeue)
                  (,(format nil "~C[27;3;13~~" #\Escape)
                   :follow-up)
                  (,(format nil "~C[13;3u" #\Escape)
                   :follow-up)
                  (,(format nil "~C~C" #\Escape #\Return)
                   :follow-up)))
             (destructuring-bind (data expected) case
               (is
                (equal
                 (list expected)
                 (event-kinds
                  (cadr-tui:feed-input
                   (cadr-tui:make-input-decoder)
                   data))))))
           (dolist
               (data
                (list
                 (format nil "~C[1;99A" #\Escape)
                 (format nil "~C[999~~" #\Escape)
                 (format nil "~Cx" #\Escape)))
             (let ((events
                     (cadr-tui:feed-input
                      (cadr-tui:make-input-decoder)
                      data)))
               (is
                (null
                 (find :text events
                       :key #'cadr-tui:input-event-kind)))))
           (dolist
               (data
                (list
                 (format nil "~C[999~~ok" #\Escape)
                 (format nil "~COZok" #\Escape)
                 (format nil "~C]999;private~Cok"
                         #\Escape (code-char 7))
                 (format nil "~CPprivate~C\\ok"
                         #\Escape #\Escape)
                 (format nil "~C_private~C\\ok"
                         #\Escape #\Escape)
                 (format nil "~Cxok" #\Escape)))
             (let ((events
                     (cadr-tui:feed-input
                      (cadr-tui:make-input-decoder)
                      data)))
               (is (= 1 (length events)))
               (is (eq :text
                       (cadr-tui:input-event-kind
                        (first events))))
               (is (string= "ok"
                            (cadr-tui:input-event-text
                             (first events)))))))
      (cadr-tui:set-keybindings previous))))

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
      (is
       (equal
        '("──────" "› ab  " "  中  "
          "  文  " "──────")
        (mapcar
         #'cadr-tui:strip-terminal-sequences
         lines)))
      (is (= 3 row))
      (is (= 4 column)))))
