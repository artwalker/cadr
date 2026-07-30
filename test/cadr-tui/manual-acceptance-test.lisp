(in-package #:cadr-tui/tests)

(in-suite cadr-tui-suite)

(defparameter +goal5-manual-image+
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl2n0sAAAAASUVORK5CYII=")

(defun goal5-manual-base-lines (width height target)
  (loop for row below height
        collect
        (cadr-tui:truncate-to-width
         (cond
           ((zerop row)
            (format nil
                    "Goal 5 manual TUI acceptance · input target: ~A"
                    target))
           ((= row 1)
            "f: toggle capturing overlay  i: image/fallback  q: quit")
           ((= row 2)
            "甲乙丙丁让ABCDEFGHI 中文边界 background")
           (t
            (format nil
                    "background row ~2D · 中文 · resize me"
                    row)))
         width)))

(defun goal5-manual-overlay-lines (target)
  (list
   "┌─ capturing overlay ───────┐"
   "│ 中文边界应完整，无半个汉字 │"
   (format nil "│ input target: ~A"
           target)
   "└───────────────────────────┘"))

(defun goal5-manual-help-lines ()
  (list
   "non-capturing help"
   "f keeps this visible"))

(defun goal5-manual-frame
    (width height capabilities
     &key (picker-visible-p t)
       (target :picker)
       force-fallback-p)
  (let* ((safe-width (max 20 width))
         (safe-height (max 10 height))
         (picker
           (cadr-tui:make-overlay-placement
            :lines (goal5-manual-overlay-lines target)
            :width 32
            :row 2
            :col 9
            :hidden-p (not picker-visible-p)))
         (help
           (cadr-tui:make-overlay-placement
            :lines (goal5-manual-help-lines)
            :width 24
            :anchor :top-right
            :margin '(:top 1 :right 1
                      :bottom 0 :left 0)))
         (frame
           (cadr-tui:composite-overlay-frame
            (goal5-manual-base-lines
             safe-width safe-height target)
            (list help picker)
            safe-width safe-height))
         (active-capabilities
           (if force-fallback-p
               (cadr-tui:make-terminal-capabilities
                :images nil
                :true-color-p
                (cadr-tui:terminal-capabilities-true-color-p
                 capabilities)
                :hyperlinks-p
                (cadr-tui:terminal-capabilities-hyperlinks-p
                 capabilities))
               capabilities))
         (image-lines
           (cadr-tui:render-image-component
            +goal5-manual-image+
            "image/png"
            safe-width
            :dimensions '(64 64)
            :filename "goal5-pixel.png"
            :capabilities active-capabilities
            :max-width-cells
            (max 4 (min 18 (- safe-width 2)))
            :max-height-cells
            (max 2 (min 6 (- safe-height 7)))
            :image-id 505))
         (image-start
           (max 6
                (- safe-height
                   (length image-lines)
                   1))))
    (when (< (1- image-start) (length frame))
      (setf
       (nth (1- image-start) frame)
       (format nil
               "image protocol: ~A~:[~; (forced fallback)~]"
               (or
                (cadr-tui:terminal-capabilities-images
                 active-capabilities)
                :fallback)
               force-fallback-p)))
    (loop for line in image-lines
          for row from image-start
          while (< row (length frame))
          do (setf (nth row frame) line))
    frame))

(test goal5-manual-frame-exercises-real-overlay-and-image-paths
  (let* ((kitty
           (cadr-tui:make-terminal-capabilities
            :images :kitty
            :true-color-p t
            :hyperlinks-p t))
         (frame
           (goal5-manual-frame
            60 20 kitty
            :picker-visible-p t
            :target :picker))
         (fallback
           (goal5-manual-frame
            60 20 kitty
            :picker-visible-p nil
            :target :editor
            :force-fallback-p t)))
    (is (= 20 (length frame)))
    (is (every
         (lambda (line)
           (<= (cadr-tui:visible-width line) 60))
         frame))
    (is (not
         (null
          (some #'cadr-tui:image-line-p frame))))
    (is (not
         (null
          (some
           (lambda (line)
             (search "input target: PICKER" line))
           frame))))
    (is (not (search "让" (nth 2 frame))))
    (is (not
         (null
          (some
           (lambda (line)
             (search "goal5-pixel.png" line))
           fallback))))
    (is (not
         (null
          (some
           (lambda (line)
             (search "input target: EDITOR" line))
           fallback))))))

(defun goal5-manual-key-present-p (input character)
  (find character input
        :test #'char-equal))

(defun run-goal5-manual-acceptance ()
  (unless
      (and
       (cadr-tui:terminal-stream-p
        *standard-input* :input)
       (cadr-tui:terminal-stream-p
        *standard-output* :output))
    (error "Goal 5 manual acceptance requires an interactive terminal"))
  (let* ((terminal
           (cadr-tui:make-process-terminal))
         (renderer
           (cadr-tui:make-terminal-renderer terminal))
         (capabilities
           (cadr-tui:get-terminal-capabilities))
         (stack
           (cadr-tui:make-overlay-stack
            :focused-component :editor))
         (help
           (cadr-tui:overlay-stack-show
            stack :help
            (goal5-manual-help-lines)
            :non-capturing-p t))
         (picker
           (cadr-tui:overlay-stack-show
            stack :picker
            (goal5-manual-overlay-lines :picker)))
         (picker-visible-p t)
         (force-fallback-p nil)
         (done-p nil))
    (declare (ignore help))
    (cadr-tui:call-with-terminal
     terminal
     (lambda ()
       (unwind-protect
            (loop until done-p
                  do
                  (when
                      (cadr-tui:terminal-resized-p
                       terminal)
                    (cadr-tui:invalidate-renderer
                     renderer))
                  (let* ((target
                           (cadr-tui:overlay-stack-input-target
                            stack))
                         (frame
                           (goal5-manual-frame
                            (cadr-tui:terminal-columns terminal)
                            (cadr-tui:terminal-rows terminal)
                            capabilities
                            :picker-visible-p
                            picker-visible-p
                            :target target
                            :force-fallback-p
                            force-fallback-p)))
                    (cadr-tui:render-frame
                     renderer frame
                     :cursor-row
                     (1-
                      (cadr-tui:terminal-rows terminal))
                     :cursor-column 0))
                  (let ((input
                          (cadr-tui:terminal-read-input
                           terminal)))
                    (when
                        (or
                         (goal5-manual-key-present-p
                          input #\q)
                         (find (code-char 3) input))
                      (setf done-p t))
                    (when
                        (goal5-manual-key-present-p
                         input #\i)
                      (setf force-fallback-p
                            (not force-fallback-p))
                      (cadr-tui:invalidate-renderer
                       renderer))
                    (when
                        (goal5-manual-key-present-p
                         input #\f)
                      (setf picker-visible-p
                            (not picker-visible-p))
                      (cadr-tui:overlay-handle-set-hidden
                       picker
                       (not picker-visible-p))
                      (when picker-visible-p
                        (cadr-tui:overlay-handle-focus
                         picker))
                      (cadr-tui:invalidate-renderer
                       renderer)))
                  (sleep 0.02d0))
         (when
             (eq
              :kitty
              (cadr-tui:terminal-capabilities-images
               capabilities))
           (cadr-tui:terminal-write
            terminal
            (cadr-tui:delete-all-kitty-images)))))))
  t)
