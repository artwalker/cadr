(in-package #:pi-tui/tests)
(in-suite pi-tui-suite)

(test differential-renderer-updates-only-changed-lines
  (let* ((terminal (pi-tui:make-virtual-terminal :columns 12 :rows 4))
         (renderer (pi-tui:make-terminal-renderer terminal)))
    (pi-tui:render-frame renderer '("one" "two") :cursor-row 1 :cursor-column 3)
    (is (equal '("one" "two" "" "")
               (pi-tui:virtual-terminal-snapshot terminal)))
    (let ((output
            (pi-tui:render-frame
             renderer '("one" "TWO")
             :cursor-row 1 :cursor-column 3)))
      (is (null (search (format nil "~C[1;1H" #\Escape) output)))
      (is (search (format nil "~C[2;1H" #\Escape) output)))
    (is (equal '("one" "TWO" "" "")
               (pi-tui:virtual-terminal-snapshot terminal)))))

(test renderer-clears-shrunk-content-and-redraws-on-resize
  (let* ((terminal (pi-tui:make-virtual-terminal :columns 10 :rows 4))
         (renderer (pi-tui:make-terminal-renderer terminal)))
    (pi-tui:render-frame renderer '("a" "b" "c"))
    (pi-tui:render-frame renderer '("a"))
    (is (equal '("a" "" "" "")
               (pi-tui:virtual-terminal-snapshot terminal)))
    (setf (pi-tui:terminal-columns terminal) 8)
    (let ((output (pi-tui:render-frame renderer '("z"))))
      (is (search (format nil "~C[2J" #\Escape) output)))
    (is (equal '("z" "" "" "")
               (pi-tui:virtual-terminal-snapshot terminal)))))
