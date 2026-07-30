(in-package #:cadr-tui/tests)
(in-suite cadr-tui-suite)

(test differential-renderer-updates-only-changed-lines
  (let* ((terminal (cadr-tui:make-virtual-terminal :columns 12 :rows 4))
         (renderer (cadr-tui:make-terminal-renderer terminal)))
    (cadr-tui:render-frame renderer '("one" "two") :cursor-row 1 :cursor-column 3)
    (is (equal '("one" "two" "" "")
               (cadr-tui:virtual-terminal-snapshot terminal)))
    (let ((output
            (cadr-tui:render-frame
             renderer '("one" "TWO")
             :cursor-row 1 :cursor-column 3)))
      (is (null (search (format nil "~C[1;1H" #\Escape) output)))
      (is (search (format nil "~C[2;1H" #\Escape) output)))
    (is (equal '("one" "TWO" "" "")
               (cadr-tui:virtual-terminal-snapshot terminal)))))

(test renderer-clears-shrunk-content-and-redraws-on-resize
  (let* ((terminal (cadr-tui:make-virtual-terminal :columns 10 :rows 4))
         (renderer (cadr-tui:make-terminal-renderer terminal)))
    (cadr-tui:render-frame renderer '("a" "b" "c"))
    (cadr-tui:render-frame renderer '("a"))
    (is (equal '("a" "" "" "")
               (cadr-tui:virtual-terminal-snapshot terminal)))
    (setf (cadr-tui:terminal-columns terminal) 8)
    (let ((output (cadr-tui:render-frame renderer '("z"))))
      (is (search (format nil "~C[2J" #\Escape) output)))
    (is (equal '("z" "" "" "")
               (cadr-tui:virtual-terminal-snapshot terminal)))))

(test renderer-isolates-line-styles
  (let* ((terminal
           (cadr-tui:make-virtual-terminal
            :columns 20 :rows 3))
         (renderer
           (cadr-tui:make-terminal-renderer terminal))
         (styled
           (format nil "~C[3mitalic" #\Escape))
         (output
           (cadr-tui:render-frame
            renderer (list styled "plain"))))
    (is (search
         (format nil "~C[3mitalic~C[0m"
                 #\Escape #\Escape)
         output))
    (is (search
         (format nil "plain~C[0m" #\Escape)
         output))))

(test renderer-deletes-changed-kitty-images-before-redraw
  (let* ((terminal
           (cadr-tui:make-virtual-terminal
            :columns 40 :rows 6))
         (renderer
           (cadr-tui:make-terminal-renderer terminal))
         (old
           (cadr-tui:encode-kitty-image
            "AAAA" :columns 2 :rows 2
            :image-id 42 :move-cursor-p nil))
         (new
           (cadr-tui:encode-kitty-image
            "BBBB" :columns 2 :rows 1
            :image-id 42 :move-cursor-p nil)))
    (cadr-tui:render-frame renderer (list "top" old ""))
    (let* ((output
             (cadr-tui:render-frame
              renderer (list new "")))
           (delete
             (cadr-tui:delete-kitty-image 42))
           (delete-position (search delete output))
           (draw-position (search new output)))
      (is (integerp delete-position))
      (is (integerp draw-position))
      (is (< delete-position draw-position)))
    (cadr-tui:render-frame renderer (list old ""))
    (cadr-tui:invalidate-renderer renderer)
    (let* ((output
             (cadr-tui:render-frame
              renderer '("plain")))
           (delete-position
             (search
              (cadr-tui:delete-kitty-image 42)
              output))
           (clear-position
             (search (format nil "~C[2J" #\Escape)
                     output)))
      (is (integerp delete-position))
      (is (integerp clear-position))
      (is (< delete-position clear-position)))))

(test renderer-preclears-kitty-reserved-rows
  (let* ((terminal
           (cadr-tui:make-virtual-terminal
            :columns 40 :rows 6))
         (renderer
           (cadr-tui:make-terminal-renderer terminal))
         (image
           (cadr-tui:encode-kitty-image
            "AAAA" :columns 2 :rows 3
            :image-id 77 :move-cursor-p nil)))
    (cadr-tui:render-frame renderer '("before"))
    (let ((output
            (cadr-tui:render-frame
             renderer
             (list "before" image "" "" "after"))))
      (is (search
           (format nil "~C[2K~C[3;1H~C[2K~C[4;1H~C[2K"
                   #\Escape #\Escape #\Escape
                   #\Escape #\Escape)
           output)))))
