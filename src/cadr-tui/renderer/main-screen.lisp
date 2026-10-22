(in-package #:cadr-tui)

(defparameter *tui-environment-function* #'uiop:getenv)

(defun tui-debug-redraw-p ()
  (string=
   (or (funcall *tui-environment-function* "CADR_TUI_DEBUG_REDRAW")
       "")
   "1"))

(defun tui-debug-redraw-log-path ()
  (merge-pathnames
   "cadr-tui-debug.log"
   (cadr-core:coding-agent-directory)))

(defun log-tui-full-redraw (renderer current reason)
  (when (tui-debug-redraw-p)
    (cadr-core:append-string-to-file
     (tui-debug-redraw-log-path)
     (format
      nil
      "[~A] fullRender: ~A (prev=~D, new=~D, height=~D)~%"
      (cadr-core:current-utc-iso8601)
      reason
      (length (terminal-renderer-previous-lines renderer))
      (length current)
      (max 1
           (terminal-rows
            (terminal-renderer-terminal renderer)))))))

(defun clipped-frame-lines (terminal lines)
  ;; Keep the natural document as the renderer's comparison buffer.  Clipping
  ;; every line here made an unchanged large transcript allocate and copy in
  ;; proportion to its complete history on every frame.
  (declare (ignore terminal))
  lines)

(defun write-main-frame-line (stream terminal line)
  (multiple-value-bind (prefix width)
      (slice-to-width line
                      (terminal-columns terminal))
    (declare (ignore width))
    (write-string prefix stream)
    (format stream "~C[0m" #\Escape)))

(defun kitty-image-id (line)
  (when (search +kitty-control-prefix+ line)
    (kitty-line-parameter-integer line "i=")))

(defun kitty-image-rows (line)
  (if (search +kitty-control-prefix+ line)
      (or (kitty-line-parameter-integer line "r=")
          1)
      1))

(defun frame-image-ids (lines)
  (remove-duplicates
   (remove nil
           (mapcar #'kitty-image-id lines))
   :test #'=))

(defun frame-image-change-p (current previous)
  (loop
    with new-tail = current
    with old-tail = previous
    while (or new-tail old-tail)
    for new = (if new-tail (pop new-tail) "")
    for old = (if old-tail (pop old-tail) "")
    thereis
    (and
     (not (string= new old))
     (or (image-line-p new)
         (image-line-p old)))))

(defun write-kitty-deletions (stream ids)
  (dolist (id ids)
    (write-string
     (delete-kitty-image id)
     stream)))

(defun render-frame-line
    (stream lines row line &key (clear-p t))
  (ansi-position stream row 0)
  (when clear-p
    (format stream "~C[2K" #\Escape)
    (let ((reserved
            (min
             (kitty-image-rows line)
             (- (length lines) row))))
      (when (> reserved 1)
        (loop for offset from 1 below reserved
              do
              (ansi-position stream
                             (+ row offset) 0)
              (format stream "~C[2K" #\Escape))
        (ansi-position stream row 0))))
  (write-string line stream)
  (format stream "~C[0m" #\Escape))

(defun clear-frame-row (stream row)
  (ansi-position stream row 0)
  (format stream "~C[2K" #\Escape))

(defun wezterm-session-p
    (&optional (environment nil))
  (flet ((env (name)
           (if environment
               (cdr (assoc name environment
                           :test #'string=))
               (uiop:getenv name))))
    (or (let ((pane (env "WEZTERM_PANE")))
          (and pane (plusp (length pane))))
        (string-equal
         "wezterm"
         (or (env "TERM_PROGRAM") "")))))

(defun wezterm-kitty-clear-before-draw-p
    (renderer current redraw-images-p
     &optional environment)
  (and redraw-images-p
       (eq :kitty
           (terminal-renderer-image-protocol
            renderer))
       (some #'image-line-p current)
       (wezterm-session-p environment)))

(defun ansi-position (stream row column)
  (format stream "~C[~D;~DH"
          #\Escape
          (1+ row)
          (1+ column)))

(defun write-relative-row-move
    (stream difference)
  (cond
    ((plusp difference)
     (format stream "~C[~DB"
             #\Escape difference))
    ((minusp difference)
     (format stream "~C[~DA"
             #\Escape (- difference)))))

(defun main-renderer-position-cursor
    (renderer cursor-row cursor-column
     total-lines)
  (let* ((height
           (max
            1
            (terminal-rows
             (terminal-renderer-terminal renderer))))
         (viewport-top
           (max 0 (- total-lines height)))
         (cursor-visible-p
           (and cursor-row cursor-column
                (>= cursor-row viewport-top)
                (< cursor-row total-lines))))
    (if (or (zerop total-lines)
            (not cursor-visible-p))
      (let ((output
              (format nil "~C[?25l"
                      #\Escape)))
        (terminal-write
         (terminal-renderer-terminal renderer)
         output)
        output)
      (let* ((target-row
               (max
                0
                (min cursor-row
                     (1- total-lines))))
             (target-column
               (max 0 cursor-column))
             (difference
               (- target-row
                  (terminal-renderer-hardware-cursor-row
                   renderer)))
             (output
               (with-output-to-string (stream)
                 (write-relative-row-move
                  stream difference)
                 (format stream "~C[~DG~C[?25~C"
                         #\Escape
                         (1+ target-column)
                         #\Escape
                         (if
                             (terminal-renderer-show-hardware-cursor-p
                              renderer)
                             #\h
                             #\l)))))
        (terminal-write
         (terminal-renderer-terminal renderer)
         output)
        (setf
         (terminal-renderer-hardware-cursor-row
          renderer)
         target-row)
        output))))

(defun main-renderer-store-frame
    (renderer current width height)
  (setf
   (terminal-renderer-previous-lines renderer)
   (copy-list current)
   (terminal-renderer-previous-image-ids
    renderer)
   (frame-image-ids current)
   (terminal-renderer-previous-width renderer)
   width
   (terminal-renderer-previous-height renderer)
   height
   (terminal-renderer-invalid-p renderer)
   nil))

(defun render-main-full-frame
    (renderer current clear-p
     cursor-row cursor-column
     &optional (reason "full"))
  (log-tui-full-redraw renderer current reason)
  (let* ((terminal
           (terminal-renderer-terminal renderer))
         (height
           (max 1 (terminal-rows terminal)))
         (output
           (with-output-to-string (stream)
             (write-string +synchronized-update-begin+ stream)
             (when clear-p
               (write-kitty-deletions
                stream
                (terminal-renderer-previous-image-ids
                 renderer))
               (format stream
                       "~C[2J~C[H~C[3J"
                       #\Escape #\Escape
                       #\Escape))
             (loop for line in current
                   for row from 0
                   do
                   (when (plusp row)
                     (write-char #\Return stream)
                     (write-char #\Newline stream))
                   (write-main-frame-line
                    stream terminal line))
             (write-string +synchronized-update-end+ stream))))
    (terminal-write terminal output)
    (let ((last-row
            (max 0 (1- (length current)))))
      (setf
       (terminal-renderer-cursor-row renderer)
       last-row
       (terminal-renderer-hardware-cursor-row
        renderer)
       last-row
       (terminal-renderer-max-lines-rendered
        renderer)
       (if clear-p
           (length current)
           (max
            (terminal-renderer-max-lines-rendered
             renderer)
            (length current)))
       (terminal-renderer-previous-viewport-top
        renderer)
       (max
        0
        (- (max height (length current))
           height))))
    (let ((cursor-output
            (main-renderer-position-cursor
             renderer cursor-row cursor-column
             (length current))))
      (main-renderer-store-frame
       renderer current
       (terminal-columns terminal)
       height)
      (concatenate
       'string output cursor-output))))

(defun changed-line-range (current previous)
  (loop
    with first = nil
    with last = nil
    with new-tail = current
    with old-tail = previous
    for row from 0
    while (or new-tail old-tail)
    for new = (if new-tail (pop new-tail) "")
    for old = (if old-tail (pop old-tail) "")
    unless (string= new old)
      do
      (unless first
        (setf first row))
      (setf last row)
    finally
    (return (values first last))))

(defun render-main-frame
    (renderer lines &key
                      (cursor-row
                        (max 0 (1- (length lines))))
                      (cursor-column 0)
                      overlay-active-p)
  (let* ((terminal
          (terminal-renderer-terminal renderer))
         (width
           (max 1 (terminal-columns terminal)))
         (height
           (max 1 (terminal-rows terminal)))
         (previous-buffer-length
           (if
               (plusp
                (terminal-renderer-previous-height
                 renderer))
               (+
                (terminal-renderer-previous-viewport-top
                 renderer)
                (terminal-renderer-previous-height
                 renderer))
               height))
         (current
           (clipped-frame-lines terminal lines))
         (previous
           (terminal-renderer-previous-lines
            renderer))
         (width-changed-p
           (and
            (plusp
             (terminal-renderer-previous-width
              renderer))
            (/=
             width
             (terminal-renderer-previous-width
              renderer))))
         (height-changed-p
           (and
            (plusp
             (terminal-renderer-previous-height
              renderer))
            (/=
             height
             (terminal-renderer-previous-height
              renderer))))
         (previous-viewport-top
           (if height-changed-p
               (max 0 (- previous-buffer-length height))
               (terminal-renderer-previous-viewport-top
                renderer))))
    (when (null previous)
      (return-from render-main-frame
        (render-main-full-frame
         renderer current nil
         cursor-row cursor-column
         "first render")))
    (let ((full-reason
            (cond
              ((terminal-renderer-invalid-p renderer)
               "invalid")
              (width-changed-p
               (format
                nil
                "terminal width changed (~A -> ~A)"
                (terminal-renderer-previous-width renderer)
                width))
              ((and height-changed-p
                    (null (uiop:getenv "TERMUX_VERSION")))
               (format
                nil
                "terminal height changed (~A -> ~A)"
                (terminal-renderer-previous-height renderer)
                height))
              ((and
                (terminal-renderer-clear-on-shrink-p
                 renderer)
                (not overlay-active-p)
                (< (length current)
                   (terminal-renderer-max-lines-rendered
                    renderer)))
               (format
                nil
                "clearOnShrink (maxLinesRendered=~A)"
                (terminal-renderer-max-lines-rendered
                 renderer))))))
      (when full-reason
        (return-from render-main-frame
          (render-main-full-frame
           renderer current t
           cursor-row cursor-column
           full-reason))))
    (let ((canonical-repaint-p
            (prog1
                (terminal-renderer-canonical-repaint-p
                 renderer)
              (setf
               (terminal-renderer-canonical-repaint-p
                renderer)
               nil))))
      (multiple-value-bind
            (first-changed last-changed)
          (changed-line-range current previous)
        ;; A canonical repaint (the render-diff harness's work-rendered
        ;; acknowledgement) expands an ordinary diff into a full
        ;; visible-region repaint in place.  When the natural diff would
        ;; take a full-clear branch (change above the viewport, deep
        ;; shrink), the baseline wipes too, so those branches must still
        ;; fire; the expansion only applies to the plain diff path.
        (when (and canonical-repaint-p (null first-changed))
          (setf
           first-changed
           (min
            previous-viewport-top
            (max 0 (1- (length current))))
           last-changed
           (max 0 (1- (length current)))))
        (unless first-changed
        (let ((cursor-output
                (main-renderer-position-cursor
                 renderer cursor-row cursor-column
                 (length current))))
          (setf
           (terminal-renderer-previous-viewport-top renderer)
           previous-viewport-top
           (terminal-renderer-previous-height renderer)
           height)
          (return-from render-main-frame cursor-output)))
      (let* ((viewport-top previous-viewport-top)
             (hardware-row
               (terminal-renderer-hardware-cursor-row
                renderer)))
        (when (>= first-changed (length current))
          (let* ((target-row
                   (max 0 (1- (length current))))
                 (extra-lines
                   (- (length previous)
                      (length current))))
            (when (< target-row previous-viewport-top)
              (return-from render-main-frame
                (render-main-full-frame
                 renderer current t
                 cursor-row cursor-column
                 (format
                  nil
                  "deleted lines moved viewport up (~A < ~A)"
                  target-row previous-viewport-top))))
            (when (> extra-lines height)
              (return-from render-main-frame
                (render-main-full-frame
                 renderer current t
                 cursor-row cursor-column
                 (format
                  nil
                  "extraLines > height (~A > ~A)"
                  extra-lines height))))
            (let ((output
                    (with-output-to-string (stream)
                      (write-string +synchronized-update-begin+ stream)
                      (when
                          (frame-image-change-p
                           current previous)
                        (write-kitty-deletions
                         stream
                         (terminal-renderer-previous-image-ids
                          renderer)))
                      (write-relative-row-move
                       stream
                       (- target-row hardware-row))
                      (write-char #\Return stream)
                      (let ((clear-start-offset
                              (if (zerop (length current)) 0 1)))
                        (when
                            (and (plusp extra-lines)
                                 (plusp clear-start-offset))
                          (format stream "~C[~DB"
                                  #\Escape clear-start-offset))
                        (loop for index below extra-lines
                              do
                                 (format stream "~C[2K"
                                         #\Escape)
                                 (when (< index (1- extra-lines))
                                   (format stream "~C[1B"
                                           #\Escape)))
                        (let ((move-back
                                (max
                                 0
                                 (+ (1- extra-lines)
                                    clear-start-offset))))
                          (when (plusp move-back)
                            (format stream "~C[~DA"
                                    #\Escape move-back))))
                      (write-string +synchronized-update-end+ stream))))
          (terminal-write terminal output)
          (setf
               (terminal-renderer-cursor-row renderer)
               target-row
               (terminal-renderer-hardware-cursor-row renderer)
               target-row
               (terminal-renderer-previous-viewport-top renderer)
               previous-viewport-top)
              (let ((cursor-output
                      (main-renderer-position-cursor
                       renderer cursor-row cursor-column
                       (length current))))
                (main-renderer-store-frame
                 renderer current width height)
                (return-from render-main-frame
                  (concatenate
                   'string output cursor-output))))))
        (when (< first-changed
                 previous-viewport-top)
          (return-from render-main-frame
            (render-main-full-frame
             renderer current t
             cursor-row cursor-column
             (format
              nil
              "firstChanged < viewportTop (~A < ~A)"
              first-changed previous-viewport-top))))
        ;; Canonical repaint (harness work-rendered acknowledgement):
        ;; the natural diff survived every full-clear check, so expand
        ;; it to the whole visible region in place.
        (when canonical-repaint-p
          (setf
           first-changed
           (min
            previous-viewport-top
            (max 0 (1- (length current))))
           last-changed
           (max 0 (1- (length current))))
          (when *canonical-repaint-hook*
            (funcall *canonical-repaint-hook* renderer)))
        (let* ((appended-p
                 (> (length current)
                    (length previous)))
               (append-start-p
                 (and
                  appended-p
                  (= first-changed
                     (length previous))
                  (plusp first-changed)))
               (move-target
                 (if append-start-p
                     (1- first-changed)
                     first-changed))
               (viewport-bottom
                 (+ previous-viewport-top
                    height -1))
               (render-end
                 (min last-changed
                      (1- (length current))))
               (final-row render-end)
               (output
                 (with-output-to-string (stream)
                   (write-string +synchronized-update-begin+ stream)
                   (when
                       (frame-image-change-p
                        current previous)
                     (write-kitty-deletions
                      stream
                      (terminal-renderer-previous-image-ids
                       renderer)))
                   (when (> move-target
                            viewport-bottom)
                     (let* ((screen-row
                              (max
                               0
                               (min
                                (1- height)
                                (-
                                 hardware-row
                                 previous-viewport-top))))
                            (move-to-bottom
                              (- (1- height)
                                 screen-row))
                            (scroll
                              (- move-target
                                 viewport-bottom)))
                       (when (plusp move-to-bottom)
                         (format stream "~C[~DB"
                                 #\Escape
                                 move-to-bottom))
                       (loop repeat scroll
                             do
                         (write-char #\Return stream)
                         (write-char #\Newline stream))
                       (incf previous-viewport-top
                             scroll)
                       (incf viewport-top scroll)
                       (setf hardware-row
                             move-target)))
                   (let* ((current-screen-row
                            (- hardware-row
                               previous-viewport-top))
                          (target-screen-row
                            (- move-target
                               viewport-top)))
                     (write-relative-row-move
                      stream
                      (- target-screen-row
                         current-screen-row)))
                   (if append-start-p
                       (progn
                         (write-char #\Return stream)
                         (write-char #\Newline stream))
                       (write-char #\Return stream))
                   (loop for row from first-changed
                         to render-end
                         for line in
                         (nthcdr first-changed current)
                         do
                         (when (> row first-changed)
                           (write-char #\Return stream)
                           (write-char #\Newline stream))
                         (format stream "~C[2K"
                                 #\Escape)
                         (let ((reserved
                                 (min
                                  (kitty-image-rows
                                   line)
                                  (-
                                   (length current)
                                   row))))
                           (when (> reserved 1)
                             (loop for offset from 1
                                   below reserved
                                   do
                                   (write-char #\Return
                                               stream)
                                   (write-char #\Newline
                                               stream)
                                   (format stream "~C[2K"
                                           #\Escape))
                             (format stream "~C[~DA"
                                     #\Escape
                                     (1- reserved))))
                         (write-main-frame-line
                          stream terminal line))
                   (when (> (length previous)
                            (length current))
                     (let ((extra-lines
                             (- (length previous)
                                (length current))))
                       (when (< render-end
                                (1- (length current)))
                         (let ((move-down
                                 (- (1- (length current))
                                    render-end)))
                           (format stream "~C[~DB"
                                   #\Escape move-down)
                           (setf final-row
                                 (1- (length current)))))
                       (loop repeat extra-lines
                             do
                                (write-char #\Return stream)
                                (write-char #\Newline stream)
                                (format stream "~C[2K"
                                        #\Escape))
                       (when (plusp extra-lines)
                         (format stream "~C[~DA"
                                 #\Escape extra-lines))))
                   (write-string +synchronized-update-end+ stream))))
          (terminal-write terminal output)
          (setf
           (terminal-renderer-cursor-row renderer)
           (max 0 (1- (length current)))
           (terminal-renderer-hardware-cursor-row
            renderer)
           final-row
           (terminal-renderer-max-lines-rendered
            renderer)
           (max
            (terminal-renderer-max-lines-rendered
             renderer)
            (length current))
           (terminal-renderer-previous-viewport-top
            renderer)
           (max
            previous-viewport-top
            (- final-row height -1)))
          (let ((cursor-output
                  (main-renderer-position-cursor
                   renderer cursor-row cursor-column
                   (length current))))
            (main-renderer-store-frame
             renderer current width height)
            (concatenate
             'string output cursor-output))))))))
