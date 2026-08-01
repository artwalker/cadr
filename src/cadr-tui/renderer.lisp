(in-package #:cadr-tui)

(defclass terminal ()
  ((columns
    :initarg :columns
    :initform 80
    :accessor terminal-columns)
   (rows
    :initarg :rows
    :initform 24
    :accessor terminal-rows)))

(defgeneric terminal-start (terminal))
(defgeneric terminal-stop (terminal))
(defgeneric terminal-write (terminal text))
(defgeneric terminal-read-input (terminal))
(defgeneric terminal-resized-p (terminal))
(defgeneric terminal-query-background-color
    (terminal &key timeout-seconds))
(defgeneric terminal-query-color-scheme
    (terminal &key timeout-seconds))
(defgeneric terminal-set-color-scheme-notifications
    (terminal enabled))
(defgeneric terminal-color-scheme-change (terminal))
(defgeneric terminal-set-progress (terminal active))
(defgeneric terminal-poll-progress (terminal))

(defmethod terminal-start ((terminal terminal))
  (declare (ignore terminal))
  nil)

(defmethod terminal-stop ((terminal terminal))
  (declare (ignore terminal))
  nil)

(defmethod terminal-write ((terminal terminal) text)
  (declare (ignore terminal text))
  nil)

(defmethod terminal-read-input ((terminal terminal))
  (declare (ignore terminal))
  "")

(defmethod terminal-resized-p ((terminal terminal))
  (declare (ignore terminal))
  nil)

(defmethod terminal-query-background-color
    ((terminal terminal) &key (timeout-seconds 0.1d0))
  (declare (ignore terminal timeout-seconds))
  nil)

(defmethod terminal-query-color-scheme
    ((terminal terminal) &key (timeout-seconds 0.1d0))
  (declare (ignore terminal timeout-seconds))
  nil)

(defmethod terminal-set-color-scheme-notifications
    ((terminal terminal) enabled)
  (declare (ignore terminal))
  (not (null enabled)))

(defmethod terminal-color-scheme-change ((terminal terminal))
  (declare (ignore terminal))
  nil)

(defmethod terminal-set-progress ((terminal terminal) active)
  (declare (ignore terminal))
  (not (null active)))

(defmethod terminal-poll-progress ((terminal terminal))
  (declare (ignore terminal))
  nil)

(defclass virtual-terminal (terminal)
  ((screen :accessor virtual-terminal-screen)
   (cursor-row :initform 0 :accessor virtual-cursor-row)
   (cursor-column :initform 0 :accessor virtual-cursor-column)
   (writes :initform nil :accessor virtual-writes)))

(defmethod initialize-instance :after ((terminal virtual-terminal) &key)
  (setf
   (virtual-terminal-screen terminal)
   (make-array
    (terminal-rows terminal)
    :initial-element "")))

(defun make-virtual-terminal (&key (columns 80) (rows 24))
  (make-instance
   'virtual-terminal
   :columns columns
   :rows rows))

(defun ensure-virtual-screen (terminal)
  (when
      (/= (length (virtual-terminal-screen terminal))
          (terminal-rows terminal))
    (let ((screen
            (make-array
             (terminal-rows terminal)
             :initial-element "")))
      (loop for index below
            (min
             (length screen)
             (length
              (virtual-terminal-screen terminal)))
            do
            (setf
             (aref screen index)
             (aref
              (virtual-terminal-screen terminal)
              index)))
      (setf (virtual-terminal-screen terminal) screen))))

(defun csi-end-position (text start)
  (loop for index from (+ start 2) below (length text)
        for value = (codepoint (char text index))
        when (between-p value #x40 #x7e)
          do (return index)))

(defun parse-csi-numbers (parameters)
  (if (zerop (length parameters))
      nil
      (mapcar
       (lambda (part)
         (or (parse-integer part :junk-allowed t) 0))
       (uiop:split-string
        (string-left-trim '(#\?) parameters)
        :separator '(#\;)))))

(defun virtual-erase-line (terminal)
  (let ((row (virtual-cursor-row terminal)))
    (when (< row (length
                  (virtual-terminal-screen terminal)))
      (setf
       (aref
        (virtual-terminal-screen terminal)
        row)
       ""))))

(defun virtual-clear (terminal)
  (fill (virtual-terminal-screen terminal) "")
  (setf
   (virtual-cursor-row terminal) 0
   (virtual-cursor-column terminal) 0))

(defun virtual-write-character (terminal character)
  (let ((row (virtual-cursor-row terminal)))
    (when (< row (length
                  (virtual-terminal-screen terminal)))
      (setf
       (aref
        (virtual-terminal-screen terminal)
        row)
       (concatenate
        'string
        (aref
         (virtual-terminal-screen terminal)
         row)
        (string character)))
      (incf
       (virtual-cursor-column terminal)
       (visible-width (string character))))))

(defun apply-virtual-output (terminal text)
  (ensure-virtual-screen terminal)
  (loop with index = 0
        while (< index (length text))
        for character = (char text index)
        do
        (cond
          ((and (char= character #\Escape)
                (< (1+ index) (length text))
                (char= (char text (1+ index)) #\[))
           (let ((end (csi-end-position text index)))
             (unless end
               (return))
             (let* ((command (char text end))
                    (parameters
                      (subseq text (+ index 2) end))
                    (numbers
                      (parse-csi-numbers parameters)))
               (case command
                 (#\H
                  (setf
                   (virtual-cursor-row terminal)
                   (max 0 (1-
                           (or (first numbers) 1)))
                   (virtual-cursor-column terminal)
                   (max 0 (1-
                           (or (second numbers) 1)))))
                 (#\J
                  (when (= (or (first numbers) 0) 2)
                    (virtual-clear terminal)))
                 (#\K
                  (virtual-erase-line terminal))
                 (#\A
                  (decf
                   (virtual-cursor-row terminal)
                   (or (first numbers) 1))
                  (setf
                   (virtual-cursor-row terminal)
                   (max 0
                        (virtual-cursor-row
                         terminal))))
                 (#\B
                  (incf
                   (virtual-cursor-row terminal)
                   (or (first numbers) 1)))
                 (#\G
                  (setf
                   (virtual-cursor-column terminal)
                   (max
                    0
                    (1-
                     (or (first numbers)
                         1)))))))
             (setf index (1+ end))))
          ((char= character #\Newline)
           (incf (virtual-cursor-row terminal))
           (setf (virtual-cursor-column terminal) 0)
           (incf index))
          ((char= character #\Return)
           (setf (virtual-cursor-column terminal) 0)
           (incf index))
          (t
           (virtual-write-character terminal character)
           (incf index)))))

(defmethod terminal-write ((terminal virtual-terminal) text)
  (push text (virtual-writes terminal))
  (apply-virtual-output terminal text)
  text)

(defun virtual-terminal-snapshot (terminal)
  (ensure-virtual-screen terminal)
  (coerce
   (virtual-terminal-screen terminal)
   'list))

(defstruct (terminal-renderer
            (:constructor %make-terminal-renderer))
  terminal
  (alt-screen-p nil :type boolean)
  (alt-screen-active-p nil :type boolean)
  (wheel-scroll-lines 3 :type (integer 1 *))
  (mouse-p t :type boolean)
  (show-hardware-cursor-p nil :type boolean)
  open-url-function
  (last-document nil :type list)
  (scroll-top 0 :type (integer 0 *))
  (content-line-count 0 :type (integer 0 *))
  (stick-to-bottom-p t :type boolean)
  selection-anchor
  selection-focus
  pressed-url
  (selection-dragged-p nil :type boolean)
  image-protocol
  saved-capabilities
  (previous-lines nil :type list)
  (previous-image-ids nil :type list)
  (previous-width 0 :type (integer 0 *))
  (previous-height 0 :type (integer 0 *))
  (cursor-row 0 :type (integer 0 *))
  (hardware-cursor-row 0 :type (integer 0 *))
  (max-lines-rendered 0 :type (integer 0 *))
  (previous-viewport-top 0
                         :type (integer 0 *))
  (invalid-p t :type boolean))

(defun make-terminal-renderer
    (terminal
     &key alt-p
       (wheel-scroll-lines 3)
       (mouse-p t)
       (show-hardware-cursor-p nil)
       open-url-function)
  (%make-terminal-renderer
   :terminal terminal
   :alt-screen-p (not (null alt-p))
   :wheel-scroll-lines
   (max 1 (floor wheel-scroll-lines))
   :mouse-p (not (null mouse-p))
   :show-hardware-cursor-p
   (not (null show-hardware-cursor-p))
   :open-url-function open-url-function))

(defun invalidate-renderer (renderer)
  (setf (terminal-renderer-invalid-p renderer) t)
  renderer)

(defparameter +alt-screen-enter+
  (format nil "~C[?1049h" #\Escape))
(defparameter +alt-screen-exit+
  (format nil "~C[?1049l" #\Escape))
(defparameter +autowrap-disable+
  (format nil "~C[?7l" #\Escape))
(defparameter +autowrap-enable+
  (format nil "~C[?7h" #\Escape))
(defparameter +mouse-enable+
  (format nil "~C[?1000h~C[?1002h~C[?1006h"
          #\Escape #\Escape #\Escape))
(defparameter +mouse-disable+
  (format nil "~C[?1006l~C[?1002l~C[?1000l"
          #\Escape #\Escape #\Escape))

(defun alt-screen-renderer-p (renderer)
  (terminal-renderer-alt-screen-p renderer))

(defun renderer-viewport-top (renderer)
  (terminal-renderer-scroll-top renderer))

(defun renderer-following-output-p (renderer)
  (terminal-renderer-stick-to-bottom-p renderer))

(defun renderer-start (renderer)
  (unless (terminal-renderer-alt-screen-p
           renderer)
    (return-from renderer-start renderer))
  (let* ((terminal
           (terminal-renderer-terminal renderer))
         (capabilities
           (get-terminal-capabilities)))
    (setf
     (terminal-renderer-alt-screen-active-p
      renderer)
     t
     (terminal-renderer-image-protocol
      renderer)
     (terminal-capabilities-images
      capabilities)
     (terminal-renderer-last-document renderer)
     nil
     (terminal-renderer-selection-anchor
      renderer)
     nil
     (terminal-renderer-selection-focus
      renderer)
     nil
     (terminal-renderer-pressed-url renderer)
     nil
     (terminal-renderer-selection-dragged-p
      renderer)
     nil
     (terminal-renderer-previous-lines renderer)
     nil
     (terminal-renderer-previous-width renderer)
     0
     (terminal-renderer-previous-height renderer)
     0
     (terminal-renderer-invalid-p renderer)
     t)
    (when
        (eq :iterm2
            (terminal-capabilities-images
             capabilities))
      (setf
       (terminal-renderer-saved-capabilities
        renderer)
       capabilities)
      (set-terminal-capabilities
       (make-terminal-capabilities
        :images nil
        :true-color-p
        (terminal-capabilities-true-color-p
         capabilities)
        :hyperlinks-p
        (terminal-capabilities-hyperlinks-p
         capabilities))))
    (terminal-write
     terminal
     (format nil "~A~A~A~C[2J~C[H~C[?25l"
             +alt-screen-enter+
             +autowrap-disable+
             (if
                 (terminal-renderer-mouse-p
                  renderer)
                 +mouse-enable+
                 "")
             #\Escape #\Escape #\Escape)))
  renderer)

(defun renderer-before-stop (renderer)
  (when
      (and
       (not
        (terminal-renderer-alt-screen-p
         renderer))
       (terminal-renderer-previous-lines
        renderer))
    (let* ((target-row
             (length
              (terminal-renderer-previous-lines
               renderer)))
           (difference
             (- target-row
                (terminal-renderer-hardware-cursor-row
                 renderer))))
      (terminal-write
       (terminal-renderer-terminal renderer)
       (with-output-to-string (stream)
         (write-char #\Space stream)
         (cond
           ((plusp difference)
            (format stream "~C[~DB"
                    #\Escape difference))
           ((minusp difference)
            (format stream "~C[~DA"
                    #\Escape (- difference))))
         (write-char #\Return stream)
         (write-char #\Newline stream)))))
  (when
      (and
       (terminal-renderer-alt-screen-p
        renderer)
       (terminal-renderer-alt-screen-active-p
        renderer))
    (terminal-write
     (terminal-renderer-terminal renderer)
     (format
      nil "~C[?2026h~A~A~A~C[?2026l"
      #\Escape
      (if
          (eq :kitty
              (terminal-renderer-image-protocol
               renderer))
          (delete-all-kitty-images)
          "")
      (if
          (terminal-renderer-mouse-p renderer)
          +mouse-disable+
          "")
      +autowrap-enable+
      #\Escape)))
  renderer)

(defun renderer-after-stop (renderer)
  (when
      (and
       (terminal-renderer-alt-screen-p
        renderer)
       (terminal-renderer-alt-screen-active-p
        renderer))
    (setf
     (terminal-renderer-alt-screen-active-p
      renderer)
     nil)
    (terminal-write
     (terminal-renderer-terminal renderer)
     (with-output-to-string (stream)
       (format stream "~C[?2026h~A~A"
               #\Escape
               +alt-screen-exit+
               +autowrap-disable+)
       (loop for line in
             (terminal-renderer-last-document
              renderer)
             for row from 0
             do
             (when (plusp row)
               (write-string
                (format nil "~C~C"
                        #\Return #\Newline)
                stream))
             (format stream "~C~C[2K~A~C[0m"
                     #\Return #\Escape line #\Escape))
       (format stream
               "~C[0m~A~C~C~C[?25h~C[?2026l"
               #\Escape +autowrap-enable+
               #\Return #\Newline
               #\Escape #\Escape)))
    (when
        (terminal-renderer-saved-capabilities
         renderer)
      (set-terminal-capabilities
       (terminal-renderer-saved-capabilities
        renderer))
      (setf
       (terminal-renderer-saved-capabilities
        renderer)
       nil)))
  renderer)

(defun renderer-scroll-by (renderer lines)
  (when (zerop lines)
    (return-from renderer-scroll-by
      renderer))
  (let* ((terminal
           (terminal-renderer-terminal renderer))
         (height
           (max 1 (terminal-rows terminal)))
         (maximum
           (max
            0
            (- (terminal-renderer-content-line-count
                renderer)
               height)))
         (current
           (if
               (terminal-renderer-stick-to-bottom-p
                renderer)
               maximum
               (terminal-renderer-scroll-top
                renderer)))
         (next
           (max
            0
            (min maximum
                 (+ current lines)))))
    (setf
     (terminal-renderer-scroll-top renderer)
     next
     (terminal-renderer-stick-to-bottom-p
      renderer)
     (= next maximum)))
  renderer)

(defun renderer-scroll-to-top (renderer)
  (setf
   (terminal-renderer-scroll-top renderer) 0
   (terminal-renderer-stick-to-bottom-p
    renderer)
   (<=
    (terminal-renderer-content-line-count
     renderer)
    (terminal-rows
     (terminal-renderer-terminal renderer))))
  renderer)

(defun renderer-scroll-to-bottom (renderer)
  (let ((terminal
          (terminal-renderer-terminal renderer)))
    (setf
     (terminal-renderer-stick-to-bottom-p
      renderer)
     t
     (terminal-renderer-scroll-top renderer)
     (max
      0
      (- (terminal-renderer-content-line-count
          renderer)
         (terminal-rows terminal)))))
  renderer)

(defun strip-osc133-zone-prefix (line)
  (loop with index = 0
        while
        (and
         (< index (length line))
         (= (char-code (char line index))
            27)
         (< (+ index 6) (length line))
         (string=
          "]133;"
          line
          :start2 (1+ index)
          :end2 (+ index 6))
         (find
          (char line (+ index 6))
          "ABC"))
        for end = (ansi-sequence-end
                   line index)
        while end
        do (setf index end)
        finally
        (return
          (if (zerop index)
              line
              (subseq line index)))))

(defun sgr-mouse-event (data)
  (multiple-value-bind
        (start end starts ends)
      (cl-ppcre:scan
       (format
        nil "^~C\\[<(\\d+);(\\d+);(\\d+)([Mm])$"
        #\Escape)
       data)
    (declare (ignore end))
    (when start
      (list
       :button
       (parse-integer
        (subseq data
                (aref starts 0)
                (aref ends 0)))
       :x
       (1-
        (parse-integer
         (subseq data
                 (aref starts 1)
                 (aref ends 1))))
       :y
       (1-
        (parse-integer
         (subseq data
                 (aref starts 2)
                 (aref ends 2))))
       :release-p
       (char= #\m
              (char data
                    (aref starts 3)))))))

(defun renderer-selection-bounds (renderer)
  (let ((anchor
          (terminal-renderer-selection-anchor
           renderer))
        (focus
          (terminal-renderer-selection-focus
           renderer)))
    (when
        (and anchor focus
             (not (equal anchor focus)))
      (if
          (or
           (< (car anchor) (car focus))
           (and
            (= (car anchor) (car focus))
            (< (cdr anchor) (cdr focus))))
          (cons anchor focus)
          (cons focus anchor)))))

(defun selection-columns (line row bounds)
  (let* ((start-point (car bounds))
         (end-point (cdr bounds))
         (line-width (visible-width line))
         (start
           (if (= row (car start-point))
               (let ((range
                       (grapheme-cell-range
                        line (cdr start-point))))
                 (if range
                     (car range)
                     (min
                      (cdr start-point)
                      line-width)))
               0))
         (end
           (if (= row (car end-point))
               (let ((range
                       (grapheme-cell-range
                        line (cdr end-point))))
                 (if range
                     (cdr range)
                     (min
                      (1+ (cdr end-point))
                      line-width)))
               line-width)))
    (cons start end)))

(defun utf8-base64 (text)
  (let ((bytes
          #+sbcl
          (sb-ext:string-to-octets
           text :external-format :utf-8)
          #-sbcl
          (map 'vector #'char-code text)))
    (with-output-to-string (output)
      (loop for position from 0
            below (length bytes) by 3
            for remaining =
            (- (length bytes) position)
            for first = (aref bytes position)
            for second =
            (if (> remaining 1)
                (aref bytes (1+ position))
                0)
            for third =
            (if (> remaining 2)
                (aref bytes (+ position 2))
                0)
            for value =
            (logior
             (ash first 16)
             (ash second 8)
             third)
            do
            (write-char
             (char +base64-alphabet+
                   (ldb (byte 6 18) value))
             output)
            (write-char
             (char +base64-alphabet+
                   (ldb (byte 6 12) value))
             output)
            (write-char
             (if (> remaining 1)
                 (char
                  +base64-alphabet+
                  (ldb (byte 6 6) value))
                 #\=)
             output)
            (write-char
             (if (> remaining 2)
                 (char
                  +base64-alphabet+
                  (ldb (byte 6 0) value))
                 #\=)
             output)))))

(defun renderer-copy-selection (renderer)
  (let ((bounds
          (renderer-selection-bounds
           renderer)))
    (unless bounds
      (return-from renderer-copy-selection
        nil))
    (let ((lines nil))
      (loop for row from
            (car (car bounds))
            to (car (cdr bounds))
            for line =
            (or
             (nth
              row
              (terminal-renderer-last-document
               renderer))
             "")
            for columns =
            (selection-columns
             line row bounds)
            do
            (push
             (string-right-trim
              '(#\Space #\Tab)
              (strip-terminal-sequences
               (slice-by-column
                line
                (car columns)
                (max
                 0
                 (- (cdr columns)
                    (car columns)))
                t)))
             lines))
      (let ((text
              (format
               nil "~{~A~^~%~}"
               (nreverse lines))))
        (when (plusp (length text))
          (terminal-write
           (terminal-renderer-terminal
            renderer)
           (format nil "~C]52;c;~A~C"
                   #\Escape
                   (utf8-base64 text)
                   (code-char 7)))
          t)))))

(defun renderer-handle-mouse
    (renderer event)
  (let ((button (getf event :button)))
    (unless (= 0 (logand button 3))
      (return-from renderer-handle-mouse
        nil))
    (let* ((terminal
             (terminal-renderer-terminal
              renderer))
           (viewport-row
             (max
              0
              (min
               (1- (terminal-rows terminal))
               (getf event :y))))
           (point
             (cons
              (+ (terminal-renderer-scroll-top
                  renderer)
                 viewport-row)
              (max
               0
               (min
                (1- (terminal-columns terminal))
                (getf event :x))))))
      (cond
        ((getf event :release-p)
         (when
             (terminal-renderer-selection-anchor
              renderer)
           (setf
            (terminal-renderer-selection-focus
             renderer)
            point)
           (let ((url
                   (and
                    (not
                     (terminal-renderer-selection-dragged-p
                      renderer))
                    (equal
                     point
                     (terminal-renderer-selection-anchor
                      renderer))
                    (terminal-renderer-pressed-url
                     renderer))))
             (setf
              (terminal-renderer-pressed-url
               renderer)
              nil)
             (if
                 (and
                  url
                  (terminal-renderer-open-url-function
                   renderer))
                 (progn
                   (setf
                    (terminal-renderer-selection-anchor
                     renderer)
                    nil
                    (terminal-renderer-selection-focus
                     renderer)
                    nil)
                   (ignore-errors
                     (funcall
                      (terminal-renderer-open-url-function
                       renderer)
                      url)))
                 (renderer-copy-selection
                  renderer)))))
        ((not
          (zerop (logand button 32)))
         (when
             (terminal-renderer-selection-anchor
              renderer)
           (setf
            (terminal-renderer-selection-dragged-p
             renderer)
            t
            (terminal-renderer-pressed-url
             renderer)
            nil
            (terminal-renderer-selection-focus
             renderer)
            point)))
        (t
         (setf
          (terminal-renderer-selection-anchor
           renderer)
          point
          (terminal-renderer-selection-focus
           renderer)
          point
          (terminal-renderer-selection-dragged-p
           renderer)
          nil
          (terminal-renderer-pressed-url
           renderer)
          (osc8-link-at-column
           (or
            (nth
             viewport-row
             (terminal-renderer-previous-lines
              renderer))
            "")
           (cdr point))))))
    t))

(defun renderer-handle-input (renderer data)
  (unless
      (and
       (terminal-renderer-alt-screen-p
        renderer)
       (plusp (length data)))
    (return-from renderer-handle-input
      nil))
  (let ((mouse (sgr-mouse-event data)))
    (when mouse
      (let ((button (getf mouse :button)))
        (when
            (not
             (zerop (logand button 64)))
          (case (logand button 3)
            (0
             (renderer-scroll-by
              renderer
              (-
               (terminal-renderer-wheel-scroll-lines
                renderer))))
            (1
             (renderer-scroll-by
              renderer
              (terminal-renderer-wheel-scroll-lines
               renderer)))))
        (unless
            (not
             (zerop (logand button 64)))
          (renderer-handle-mouse
           renderer mouse)))
      (return-from renderer-handle-input
        t)))
  (let ((keybindings (get-keybindings))
        (height
          (terminal-rows
           (terminal-renderer-terminal
            renderer))))
    (cond
      ((keybinding-matches-p
        keybindings data
        "tui.altScreen.pageUp")
       (renderer-scroll-by
        renderer (- (max 1 (1- height))))
       t)
      ((keybinding-matches-p
        keybindings data
        "tui.altScreen.pageDown")
       (renderer-scroll-by
        renderer (max 1 (1- height)))
       t)
      ((keybinding-matches-p
        keybindings data
        "tui.altScreen.top")
       (renderer-scroll-to-top renderer)
       t)
      ((keybinding-matches-p
        keybindings data
        "tui.altScreen.bottom")
       (renderer-scroll-to-bottom renderer)
       t)
      (t nil))))

(defun apply-renderer-selection
    (renderer screen)
  (let ((bounds
          (renderer-selection-bounds
           renderer)))
    (if (null bounds)
        screen
        (loop for line in screen
              for viewport-row from 0
              for row =
              (+ (terminal-renderer-scroll-top
                  renderer)
                 viewport-row)
              collect
              (if
                  (or
                   (< row (car (car bounds)))
                   (> row (car (cdr bounds)))
                   (image-line-p line))
                  line
                  (let* ((columns
                           (selection-columns
                            line row bounds))
                         (start (car columns))
                         (end (cdr columns))
                         (width
                           (visible-width line)))
                    (if (<= end start)
                        line
                        (concatenate
                         'string
                         (slice-by-column
                          line 0 start t)
                         (format nil "~C[7m"
                                 #\Escape)
                         (slice-by-column
                          line start
                          (- end start) t)
                         (format nil "~C[27m"
                                 #\Escape)
                         (slice-by-column
                          line end
                          (max 0 (- width end))
                          t)))))))))

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

(defun prepare-alt-document (lines width)
  (loop for source in lines
        for line =
        (strip-osc133-zone-prefix source)
        collect
        (if
            (or (image-line-p line)
                (<= (visible-width line) width))
            line
            (slice-by-column
             line 0 width t))))

(defun cropped-image-at-viewport-top
    (document top height)
  (when (plusp top)
    (loop for image-row downfrom (1- top) to 0
          for image-line = (nth image-row document)
          for metadata =
          (get-kitty-image-metadata image-line)
          when metadata
            do
            (let ((hidden-rows (- top image-row)))
              (return
                (and
                 (< hidden-rows
                    (getf metadata :rows))
                 (crop-kitty-image-line
                  image-line
                  hidden-rows
                  (min
                   height
                   (-
                    (getf metadata :rows)
                    hidden-rows))))))
          when
          (plusp
           (length
            (strip-terminal-sequences
             image-line)))
            do (return nil))))

(defun alt-viewport-lines
    (renderer document height)
  (let* ((top
           (terminal-renderer-scroll-top
            renderer))
         (screen
           (subseq
            document
            (min top (length document))
            (min
             (length document)
             (+ top height))))
         (cropped
           (cropped-image-at-viewport-top
            document top height)))
    (when cropped
      (if screen
          (setf (first screen) cropped)
          (setf screen (list cropped))))
    (nconc
     screen
     (make-list
      (max 0 (- height (length screen)))
      :initial-element ""))))

(defun render-alt-frame
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
         (document
           (prepare-alt-document
            lines width))
         (maximum-top
           (max 0 (- (length document) height))))
    (setf
     (terminal-renderer-content-line-count
      renderer)
     (length document)
     (terminal-renderer-last-document renderer)
     document)
    (if
        (terminal-renderer-stick-to-bottom-p
         renderer)
        (setf
         (terminal-renderer-scroll-top renderer)
         maximum-top)
        (progn
          (setf
           (terminal-renderer-scroll-top renderer)
           (max
            0
            (min
             (terminal-renderer-scroll-top
              renderer)
             maximum-top)))
          (when
              (=
               (terminal-renderer-scroll-top
                renderer)
               maximum-top)
            (setf
             (terminal-renderer-stick-to-bottom-p
              renderer)
             t))))
    (let* ((selected
             (apply-renderer-selection
              renderer
              (alt-viewport-lines
               renderer document height)))
           (current
             (loop for line in selected
                   collect
                   (if
                       (or
                        (image-line-p line)
                        (<= (visible-width line)
                            width))
                       line
                       (slice-by-column
                        line 0 width t))))
           (previous
             (terminal-renderer-previous-lines
              renderer))
           (full-p
             (or
              (terminal-renderer-invalid-p
               renderer)
              (null previous)
              (/=
               width
               (terminal-renderer-previous-width
                renderer))
              (/=
               height
               (terminal-renderer-previous-height
                renderer))))
           (image-change-p
             (frame-image-change-p
              current previous))
           (visible-cursor-row
             (- cursor-row
                (terminal-renderer-scroll-top
                 renderer)))
           (cursor-visible-p
             (and
              (>= visible-cursor-row 0)
              (< visible-cursor-row height)))
           (output
             (with-output-to-string (stream)
               (format stream "~C[?2026h"
                       #\Escape)
               (cond
                 (full-p
                  (when
                      (eq
                       :kitty
                       (terminal-renderer-image-protocol
                        renderer))
                    (write-string
                     (delete-all-kitty-images)
                     stream))
                  (format stream "~C[2J"
                          #\Escape))
                 (image-change-p
                  (if
                      (eq
                       :iterm2
                       (terminal-renderer-image-protocol
                        renderer))
                      (format stream "~C[2J"
                              #\Escape)
                      (when
                          (eq
                           :kitty
                           (terminal-renderer-image-protocol
                            renderer))
                        (write-string
                         (delete-all-kitty-images)
                         stream)))))
               (loop for row below height
                     for new =
                     (or (nth row current) "")
                     for old =
                     (nth row previous)
                     when
                     (or
                      full-p
                      image-change-p
                      (null old)
                      (not (string= new old)))
                       do
                       (render-frame-line
                        stream current row new))
               (if cursor-visible-p
                   (progn
                     (ansi-position
                      stream
                      visible-cursor-row
                      (min
                       (max 0 cursor-column)
                       (1- width)))
                     (format stream "~C[?25~C"
                             #\Escape
                             (if
                                 (terminal-renderer-show-hardware-cursor-p
                                  renderer)
                                 #\h
                                 #\l)))
                   (format stream "~C[?25l"
                           #\Escape))
               (format stream "~C[?2026l"
                       #\Escape))))
      (terminal-write terminal output)
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
       nil)
      output)))

(defun render-frame
    (renderer lines &key
                      (cursor-row
                        (max 0 (1- (length lines))))
                      (cursor-column 0))
  (if (terminal-renderer-alt-screen-p renderer)
      (render-alt-frame
       renderer lines
       :cursor-row cursor-row
       :cursor-column cursor-column)
      (render-main-frame
       renderer lines
       :cursor-row cursor-row
       :cursor-column cursor-column)))
