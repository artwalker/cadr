(in-package #:cadr-tui/tests)
(in-suite cadr-tui-suite)

(defun single-input-event (input kind &optional text)
  (cadr-tui:single-line-input-handle-event
   input
   (cadr-tui:make-input-event :kind kind :text text)))

(test single-line-input-scrolls-wide-text-with-visible-cursor
  (let ((input
          (cadr-tui:make-single-line-input
           :value "가나다라마바사아자차카타파하")))
    (single-input-event input :line-start)
    (loop repeat 5 do (single-input-event input :right))
    (multiple-value-bind (lines row column)
        (cadr-tui:render-single-line-input input 20)
      (is (= 1 (length lines)))
      (is (= 0 row))
      (is (< column 20))
      (is (<= (cadr-tui:visible-width (first lines)) 20)))))

(test single-line-input-renders-baseline-software-cursor-at-end-and-over-text
  (let ((input
          (cadr-tui:make-single-line-input
           :value "ab")))
    (multiple-value-bind (lines row column)
        (cadr-tui:render-single-line-input input 12)
      (is (= 0 row))
      (is (= 4 column))
      (is
       (search
        (format nil "ab~C[7m ~C[27m"
                #\Escape #\Escape)
        (first lines))))
    (single-input-event input :left)
    (multiple-value-bind (lines row column)
        (cadr-tui:render-single-line-input input 12)
      (declare (ignore row))
      (is (= 3 column))
      (is
       (search
        (format nil "a~C[7mb~C[27m"
                #\Escape #\Escape)
        (first lines))))))

(test single-line-input-cursor-preserves-graphemes-and-narrow-widths
  (let ((input
          (cadr-tui:make-single-line-input
           :value "你🙂a")))
    (single-input-event input :line-start)
    (multiple-value-bind (lines row column)
        (cadr-tui:render-single-line-input input 10)
      (declare (ignore row))
      (is (= 2 column))
      (is
       (search
        (format nil "~C[7m你~C[27m"
                #\Escape #\Escape)
        (first lines))))
    (single-input-event input :right)
    (multiple-value-bind (lines row column)
        (cadr-tui:render-single-line-input input 10)
      (declare (ignore row))
      (is (= 4 column))
      (is
       (search
        (format nil "~C[7m🙂~C[27m"
                #\Escape #\Escape)
        (first lines))))
    (single-input-event input :line-start)
    (multiple-value-bind (lines row column)
        (cadr-tui:render-single-line-input input 3)
      (declare (ignore row column))
      (is (= 3 (cadr-tui:visible-width (first lines))))
      (is (null (search "你" (first lines))))
      (is
       (search
        (format nil "~C[7m ~C[27m"
                #\Escape #\Escape)
        (first lines))))))

(test single-line-input-kill-yank-pop-and-word-boundaries
  (let ((input
          (cadr-tui:make-single-line-input
           :value "foo.bar 你好，世界")))
    (single-input-event input :delete-word-backward)
    (is (string= "foo.bar 你好，"
                 (cadr-tui:single-line-input-value input)))
    (single-input-event input :delete-word-backward)
    (single-input-event input :delete-word-backward)
    (single-input-event input :yank)
    (is (string= "foo.bar 你好，世界"
                 (cadr-tui:single-line-input-value input)))
    (cadr-tui:single-line-input-set-value input "other")
    (single-input-event input :delete-word-backward)
    (single-input-event input :yank)
    (is (string= "other"
                 (cadr-tui:single-line-input-value input)))
    (single-input-event input :yank-pop)
    (is (string= "你好，世界"
                 (cadr-tui:single-line-input-value input)))))

(test single-line-input-undo-coalesces-words-and-paste-is-atomic
  (let ((input (cadr-tui:make-single-line-input)))
    (loop for character across "hello world"
          do (single-input-event
              input :text (string character)))
    (single-input-event input :undo)
    (is (string= "hello"
                 (cadr-tui:single-line-input-value input)))
    (single-input-event input :undo)
    (is (string= ""
                 (cadr-tui:single-line-input-value input)))
    (single-input-event
     input :paste
     (format nil "a~%b~Cc" #\Tab))
    (is (string= "ab    c"
                 (cadr-tui:single-line-input-value input)))
    (single-input-event input :undo)
    (is (string= ""
                 (cadr-tui:single-line-input-value input)))))

(test single-line-input-submit-preserves-backslash
  (let ((input
          (cadr-tui:make-single-line-input
           :value "path\\")))
    (multiple-value-bind (action value)
        (single-input-event input :enter)
      (is (eq :submit action))
      (is (string= "path\\" value)))
    (is (string= "path\\"
                 (cadr-tui:single-line-input-value input)))))

(test single-line-input-press-positions-the-cursor
  (let ((input
          (cadr-tui:make-single-line-input :value "hello")))
    (cadr-tui:render-single-line-input input 20)
    (is (cadr-tui:single-line-input-handle-mouse
         input :type :press :button :left :x 4 :y 0))
    (single-input-event input :text "X")
    (is (string= "heXllo"
                 (cadr-tui:single-line-input-value input)))
    (is (null
         (cadr-tui:single-line-input-handle-mouse
          input :type :click :button :left :x 4 :y 0)))
    (is (string= "heXllo"
                 (cadr-tui:single-line-input-value input)))))
