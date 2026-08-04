(in-package #:cadr-tui)

(defstruct (terminal-renderer
            (:constructor %make-terminal-renderer))
  terminal
  (alt-screen-p nil :type boolean)
  (alt-screen-active-p nil :type boolean)
  (wheel-scroll-lines 3 :type (integer 1 *))
  (mouse-p t :type boolean)
  (show-hardware-cursor-p nil :type boolean)
  (clear-on-shrink-p nil :type boolean)
  open-url-function
  (last-document nil :type list)
  (prepared-source-lines nil :type list)
  (prepared-document nil :type list)
  (prepared-width 0 :type (integer 0 *))
  (prepared-prefix-reused 0 :type (integer 0 *))
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
       (clear-on-shrink-p nil)
       open-url-function)
  (%make-terminal-renderer
   :terminal terminal
   :alt-screen-p (not (null alt-p))
   :wheel-scroll-lines
   (max 1 (floor wheel-scroll-lines))
   :mouse-p (not (null mouse-p))
   :show-hardware-cursor-p
   (not (null show-hardware-cursor-p))
   :clear-on-shrink-p
   (not (null clear-on-shrink-p))
   :open-url-function open-url-function))

(defun renderer-set-clear-on-shrink
    (renderer enabled-p)
  (setf
   (terminal-renderer-clear-on-shrink-p renderer)
   (not (null enabled-p)))
  renderer)

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
     (terminal-renderer-prepared-source-lines renderer)
     nil
     (terminal-renderer-prepared-document renderer)
     nil
     (terminal-renderer-prepared-width renderer)
     0
     (terminal-renderer-prepared-prefix-reused renderer)
     0
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
