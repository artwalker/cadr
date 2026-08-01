(in-package #:cadr-tui)

(defstruct input-event
  kind
  text)

(defstruct (input-decoder
            (:constructor make-input-decoder ()))
  (buffer "" :type string)
  (paste-p nil :type boolean)
  (paste-buffer "" :type string))

(defparameter +paste-start+ (format nil "~C[200~~" #\Escape))
(defparameter +paste-end+ (format nil "~C[201~~" #\Escape))

(defparameter +escape-inputs+
  (list
   (cons (format nil "~C[A" #\Escape) :up)
   (cons (format nil "~C[B" #\Escape) :down)
   (cons (format nil "~C[C" #\Escape) :right)
   (cons (format nil "~C[D" #\Escape) :left)
   (cons (format nil "~C[H" #\Escape) :home)
   (cons (format nil "~C[F" #\Escape) :end)
   (cons (format nil "~C[1~~" #\Escape) :home)
   (cons (format nil "~C[4~~" #\Escape) :end)
   (cons (format nil "~C[3~~" #\Escape) :delete)
   (cons (format nil "~C[5~~" #\Escape) :page-up)
   (cons (format nil "~C[6~~" #\Escape) :page-down)
   (cons (format nil "~C[13;2u" #\Escape) :newline)
   (cons (format nil "~C[1;5D" #\Escape) :word-left)
   (cons (format nil "~C[1;5C" #\Escape) :word-right)
   (cons (format nil "~C[1;3D" #\Escape) :word-left)
   (cons (format nil "~C[1;3C" #\Escape) :word-right)
   (cons (format nil "~Cb" #\Escape) :word-left)
   (cons (format nil "~Cf" #\Escape) :word-right)
   (cons (format nil "~Cd" #\Escape) :delete-word-forward)
   (cons (format nil "~Cy" #\Escape) :yank-pop)
   (cons (format nil "~C~C" #\Escape
                 (code-char 127))
         :delete-word-backward)
   (cons (format nil "~C~C" #\Escape
                 (code-char 29))
         :jump-backward)))

(defun string-prefix-p (prefix string)
  (and (<= (length prefix) (length string))
       (string= prefix string :end2 (length prefix))))

(defun escape-prefix-p (buffer)
  (or (string-prefix-p buffer +paste-start+)
      (some (lambda (entry)
              (string-prefix-p buffer (car entry)))
            +escape-inputs+)))

(defun normalize-paste (text)
  (with-output-to-string (output)
    (loop with index = 0
          while (< index (length text))
          for character = (char text index)
          do
          (if (char= character #\Return)
              (progn
                (write-char #\Newline output)
                (when (and (< (1+ index) (length text))
                           (char= (char text (1+ index)) #\Newline))
                  (incf index)))
              (write-char character output))
          (incf index))))

(defun consume-buffer-prefix (decoder count)
  (setf (input-decoder-buffer decoder)
        (subseq (input-decoder-buffer decoder) count)))

(defun decode-control-character (character)
  (case (codepoint character)
    (3 :clear)
    (4 :eof)
    (1 :line-start)
    (2 :left)
    (8 :backspace)
    (9 :tab)
    (10 :newline)
    (11 :delete-line-end)
    (13 :enter)
    (15 :toggle-tools)
    (21 :delete-line-start)
    (23 :delete-word-backward)
    (25 :yank)
    (29 :jump-forward)
    (31 :undo)
    (127 :backspace)
    (otherwise nil)))

(defparameter +logical-key-events+
  '(("app.interrupt" . :interrupt)
    ("app.clear" . :clear)
    ("app.exit" . :eof)
    ("app.message.followUp" . :follow-up)
    ("app.message.dequeue" . :dequeue)
    ("tui.editor.cursorUp" . :up)
    ("tui.editor.cursorDown" . :down)
    ("tui.editor.cursorLeft" . :left)
    ("tui.editor.cursorRight" . :right)
    ("tui.editor.cursorWordLeft" . :word-left)
    ("tui.editor.cursorWordRight" . :word-right)
    ("tui.editor.cursorLineStart" . :line-start)
    ("tui.editor.cursorLineEnd" . :line-end)
    ("tui.editor.jumpForward" . :jump-forward)
    ("tui.editor.jumpBackward" . :jump-backward)
    ("tui.editor.pageUp" . :page-up)
    ("tui.editor.pageDown" . :page-down)
    ("tui.editor.deleteCharBackward" . :backspace)
    ("tui.editor.deleteCharForward" . :delete)
    ("tui.editor.deleteWordBackward"
     . :delete-word-backward)
    ("tui.editor.deleteWordForward"
     . :delete-word-forward)
    ("tui.editor.deleteToLineStart"
     . :delete-line-start)
    ("tui.editor.deleteToLineEnd"
     . :delete-line-end)
    ("tui.editor.yank" . :yank)
    ("tui.editor.yankPop" . :yank-pop)
    ("tui.editor.undo" . :undo)
    ("tui.input.newLine" . :newline)
    ("tui.input.submit" . :enter)
    ("tui.input.tab" . :tab)))

(defun event-kind-for-raw-key (data)
  (let ((manager (get-keybindings)))
    (loop for (name . kind)
          in +logical-key-events+
          when (keybinding-matches-p
                manager data name)
            do (return kind))))

(defun input-csi-end-position (text)
  (when
      (and (> (length text) 1)
           (char= (char text 0) #\Escape)
           (char= (char text 1) #\[))
    (loop for index from 2 below (length text)
          for value = (codepoint (char text index))
          when (between-p value #x40 #x7e)
            do (return index))))

(defun decode-complete-escape-event (data)
  (when (key-release-p data)
    (return-from decode-complete-escape-event
      (values t nil)))
  (let ((printable
          (decode-printable-key data)))
    (when printable
      (return-from decode-complete-escape-event
        (values
         t
         (make-input-event
          :kind :text :text printable)))))
  (let ((kind
          (event-kind-for-raw-key data)))
    (when kind
      (return-from decode-complete-escape-event
        (values
         t
         (make-input-event :kind kind)))))
  (values nil nil))

(defun feed-input (decoder text)
  (setf (input-decoder-buffer decoder)
        (concatenate 'string
                     (input-decoder-buffer decoder)
                     text))
  (let ((events nil))
    (labels
        ((decode-next ()
           (when (input-decoder-paste-p decoder)
             (let ((end
                     (search
                      +paste-end+
                      (input-decoder-buffer decoder))))
               (unless end
                 (setf
                  (input-decoder-paste-buffer decoder)
                  (concatenate
                   'string
                   (input-decoder-paste-buffer decoder)
                   (input-decoder-buffer decoder))
                  (input-decoder-buffer decoder) "")
                 (return-from decode-next nil))
               (setf
                (input-decoder-paste-buffer decoder)
                (concatenate
                 'string
                 (input-decoder-paste-buffer decoder)
                 (subseq
                  (input-decoder-buffer decoder)
                  0 end)))
               (push
                (make-input-event
                 :kind :paste
                 :text
                 (normalize-paste
                  (input-decoder-paste-buffer decoder)))
                events)
               (setf
                (input-decoder-buffer decoder)
                (subseq
                 (input-decoder-buffer decoder)
                 (+ end (length +paste-end+)))
                (input-decoder-paste-buffer decoder) ""
                (input-decoder-paste-p decoder) nil)))
           (when
               (zerop
                (length (input-decoder-buffer decoder)))
             (return-from decode-next nil))
           (when
               (string-prefix-p
                +paste-start+
                (input-decoder-buffer decoder))
             (consume-buffer-prefix
              decoder (length +paste-start+))
             (setf (input-decoder-paste-p decoder) t)
             (return-from decode-next (decode-next)))
           (let ((escape
                   (find-if
                    (lambda (entry)
                      (string-prefix-p
                       (car entry)
                       (input-decoder-buffer decoder)))
                    +escape-inputs+)))
             (when escape
               (consume-buffer-prefix
                decoder (length (car escape)))
               (push
                (make-input-event :kind (cdr escape))
                events)
               (return-from decode-next (decode-next))))
           (when
               (and
                (> (length
                    (input-decoder-buffer decoder))
                   1)
                (char=
                 (char
                  (input-decoder-buffer decoder)
                  0)
                 #\Escape)
                (char=
                 (char
                  (input-decoder-buffer decoder)
                  1)
                 #\[))
             (let ((end
                     (input-csi-end-position
                      (input-decoder-buffer decoder))))
               (unless end
                 (return-from decode-next nil))
               (let ((data
                       (subseq
                        (input-decoder-buffer decoder)
                        0 (1+ end))))
                 (multiple-value-bind
                       (recognized-p event)
                     (decode-complete-escape-event data)
                   (when recognized-p
                     (consume-buffer-prefix
                      decoder (length data))
                     (when event (push event events))
                     (return-from decode-next
                       (decode-next)))))))
           (when
               (and
                (> (length
                    (input-decoder-buffer decoder))
                   1)
                (char=
                 (char
                  (input-decoder-buffer decoder)
                  0)
                 #\Escape)
                (not
                 (char=
                  (char
                   (input-decoder-buffer decoder)
                   1)
                  #\[)))
             (let ((data
                     (subseq
                      (input-decoder-buffer decoder)
                      0 2)))
               (multiple-value-bind
                     (recognized-p event)
                   (decode-complete-escape-event data)
                 (when recognized-p
                   (consume-buffer-prefix decoder 2)
                   (when event (push event events))
                   (return-from decode-next
                     (decode-next))))))
           (when
               (and
                (char=
                 (char
                  (input-decoder-buffer decoder)
                  0)
                 #\Escape)
                (escape-prefix-p
                 (input-decoder-buffer decoder)))
             (return-from decode-next nil))
           (let* ((character
                    (char
                     (input-decoder-buffer decoder)
                     0))
                  (raw
                    (string character))
                  (bound
                    (event-kind-for-raw-key raw))
                  (control
                    (or bound
                        (decode-control-character
                         character))))
             (cond
               (control
                (consume-buffer-prefix decoder 1)
                (push
                 (make-input-event :kind control)
                 events))
               ((char= character #\Escape)
                (consume-buffer-prefix decoder 1)
                (push
                 (make-input-event :kind :escape)
                 events))
               (t
                (let ((end
                        (or
                         (position-if
                          (lambda (candidate)
                            (or
                             (char= candidate #\Escape)
                             (decode-control-character
                              candidate)))
                          (input-decoder-buffer decoder)
                          :start 1)
                         (length
                          (input-decoder-buffer
                           decoder)))))
                  (push
                   (make-input-event
                    :kind :text
                    :text
                    (subseq
                     (input-decoder-buffer decoder)
                     0 end))
                   events)
                  (consume-buffer-prefix decoder end))))
             (decode-next))))
      (decode-next))
    (nreverse events)))

(defun flush-input (decoder)
  (if (string= (input-decoder-buffer decoder)
               (string #\Escape))
      (progn
        (setf (input-decoder-buffer decoder) "")
        (list (make-input-event :kind :escape)))
      nil))
