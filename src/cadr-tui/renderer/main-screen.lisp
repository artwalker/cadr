(in-package #:cadr-tui)

(defun clipped-frame-lines (terminal lines)
  (loop for line in lines
        collect
        (multiple-value-bind (prefix width)
            (slice-to-width line
                            (terminal-columns terminal))
          (declare (ignore width))
          (concatenate
           'string prefix
           (format nil "~C[0m" #\Escape)))))

(defun kitty-parameter-integer
    (line parameter)
  (let ((position
          (search parameter line)))
    (when position
      (parse-integer
       line
       :start (+ position
                 (length parameter))
       :junk-allowed t))))

(defun kitty-image-id (line)
  (when (search (format nil "~C_G" #\Escape)
                line)
    (kitty-parameter-integer line "i=")))

(defun kitty-image-rows (line)
  (if (search (format nil "~C_G" #\Escape)
              line)
      (or (kitty-parameter-integer line "r=")
          1)
      1))

(defun frame-image-ids (lines)
  (remove-duplicates
   (remove nil
           (mapcar #'kitty-image-id lines))
   :test #'=))

(defun frame-image-change-p (current previous)
  (loop for row below
        (max (length current)
             (length previous))
        for new =
        (if (< row (length current))
            (nth row current)
            "")
        for old =
        (if (< row (length previous))
            (nth row previous)
            "")
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
    (stream lines row line)
  (ansi-position stream row 0)
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
      (ansi-position stream row 0))
    (write-string line stream)
    (format stream "~C[0m" #\Escape)))

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
  (if (zerop total-lines)
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
        output)))

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
     cursor-row cursor-column)
  (let* ((terminal
           (terminal-renderer-terminal renderer))
         (height
           (max 1 (terminal-rows terminal)))
         (output
           (with-output-to-string (stream)
             (format stream "~C[?2026h"
                     #\Escape)
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
                   (write-string line stream))
             (format stream "~C[?2026l"
                     #\Escape))))
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
  (loop with first = nil
        with last = nil
        for row below
        (max (length current)
             (length previous))
        for new =
        (or (nth row current) "")
        for old =
        (or (nth row previous) "")
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
                      (cursor-column 0))
  (let* ((terminal
           (terminal-renderer-terminal renderer))
         (width
           (max 1 (terminal-columns terminal)))
         (height
           (max 1 (terminal-rows terminal)))
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
              renderer)))))
    (when (null previous)
      (return-from render-main-frame
        (render-main-full-frame
         renderer current nil
         cursor-row cursor-column)))
    (when
        (or
         (terminal-renderer-invalid-p renderer)
         width-changed-p
         height-changed-p
         (< (length current)
            (terminal-renderer-max-lines-rendered
             renderer)))
      (return-from render-main-frame
        (render-main-full-frame
         renderer current t
         cursor-row cursor-column)))
    (multiple-value-bind
          (first-changed last-changed)
        (changed-line-range current previous)
      (unless first-changed
        (return-from render-main-frame
          (main-renderer-position-cursor
           renderer cursor-row cursor-column
           (length current))))
      (let* ((previous-viewport-top
               (terminal-renderer-previous-viewport-top
                renderer))
             (viewport-top previous-viewport-top)
             (hardware-row
               (terminal-renderer-hardware-cursor-row
                renderer)))
        (when (< first-changed
                 previous-viewport-top)
          (return-from render-main-frame
            (render-main-full-frame
             renderer current t
             cursor-row cursor-column)))
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
               (output
                 (with-output-to-string (stream)
                   (format stream "~C[?2026h"
                           #\Escape)
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
                         to
                         (min last-changed
                              (1- (length current)))
                         for line = (nth row current)
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
                         (write-string line stream))
                   (format stream "~C[?2026l"
                           #\Escape))))
          (terminal-write terminal output)
          (let ((final-row
                  (min last-changed
                       (max 0
                            (1-
                             (length current))))))
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
              (- final-row height -1))))
          (let ((cursor-output
                  (main-renderer-position-cursor
                   renderer cursor-row cursor-column
                   (length current))))
            (main-renderer-store-frame
             renderer current width height)
            (concatenate
             'string output cursor-output)))))))
