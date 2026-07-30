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
