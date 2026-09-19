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
  ;; pi@d981de122 components/scroll-view.ts:62-70 — :auto shows the
  ;; thumb transiently after scroll activity, :always reserves a
  ;; column, :hidden never paints.
  (scrollbar-mode :auto :type symbol)
  ;; v0.85.1 fullscreenExitOutput: :transcript replays the document on
  ;; exit (the baseline default); :resume-hint leaves the screen and
  ;; prints only the resume hint.
  (exit-output-mode :transcript :type symbol)
  (scrollbar-activity-at nil :type (or null double-float))
  open-url-function
  ;; P.12.3: per-row selection/copy indexes this; a vector
  ;; keeps AREF O(1). Tests may still SETF a list.
  (last-document nil :type (or null vector list))
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
  ;; pi@d981de122 tui-alt-screen.ts:147-149 — multi-click selection
  ;; state: double click selects the word, triple click the line, and
  ;; drags extend by the same granularity.
  (selection-granularity :character :type symbol)
  selection-initial-range
  (last-click-at nil :type (or null double-float))
  (last-click-count 0 :type (integer 0 *))
  (last-click-row -1 :type integer)
  (last-click-word-start -1 :type integer)
  (last-click-word-end -1 :type integer)
  ;; pi@d981de122 components/alt-screen-flash.ts — transient
  ;; reverse-video messages composited top-right in fullscreen mode.
  (flash-entries nil :type list)
  (flash-next-id 0 :type integer)
  ;; v0.85.1: the transcript search session, while the find bar is open.
  (alt-search-state nil)
  ;; v0.85.1 tui-alt-screen.ts copySelection: a host clipboard function
  ;; with a verified success path; nil falls back to an OSC 52 write.
  (copy-selection-function nil)
  ;; v0.85.1 tui-alt-screen.ts copyOnSelect: default true; when false
  ;; mouse release leaves the highlight and Ctrl+X copies it.
  (copy-on-select-p t :type boolean)
  component-mouse-function
  component-mouse-press
  (component-mouse-moved-p nil :type boolean)
  ;; pi@d981de122 tui-alt-screen.ts scrollToEndIndicator — when the
  ;; transcript is scrolled up, paint a centered label on the last
  ;; viewport row. Nil disables the overlay.
  (scroll-to-end-indicator-function nil)
  (scroll-to-end-indicator-rect nil)
  image-protocol
  saved-capabilities
  ;; Stashed main-screen render state for live TUI-mode round-trips
  ;; (pi@d981de122 interactive-mode.ts:788-832 switchTuiMode).
  saved-main-screen-state
  (previous-lines nil :type list)
  (previous-image-ids nil :type list)
  (previous-width 0 :type (integer 0 *))
  (previous-height 0 :type (integer 0 *))
  (cursor-row 0 :type (integer 0 *))
  (hardware-cursor-row 0 :type (integer 0 *))
  (max-lines-rendered 0 :type (integer 0 *))
  (previous-viewport-top 0
                         :type (integer 0 *))
  (invalid-p t :type boolean)
  (canonical-repaint-p nil :type boolean))

(defun make-terminal-renderer
    (terminal
     &key alt-p
       (wheel-scroll-lines 3)
       (mouse-p t)
       (show-hardware-cursor-p nil)
       (clear-on-shrink-p nil)
       (scrollbar-mode :auto)
       (exit-output-mode :transcript)
       copy-selection-function
       (copy-on-select-p t)
       open-url-function
       scroll-to-end-indicator-function)
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
   :scrollbar-mode
   (if (member scrollbar-mode '(:auto :always :hidden))
       scrollbar-mode
       :auto)
   :exit-output-mode
   (if (member exit-output-mode '(:transcript :resume-hint))
       exit-output-mode
       :transcript)
   :copy-selection-function copy-selection-function
   :copy-on-select-p (not (null copy-on-select-p))
   :open-url-function open-url-function
   :scroll-to-end-indicator-function
   scroll-to-end-indicator-function))

(defun renderer-open-search (renderer)
  ;; Baseline tui-alt-screen.ts openSearch: focus the existing bar or
  ;; open one anchored at the current viewport top.
  (unless (terminal-renderer-alt-search-state renderer)
    (setf (terminal-renderer-alt-search-state renderer)
          (make-alt-search-state
           (terminal-renderer-scroll-top renderer)))))

(defun renderer-close-search (renderer)
  (setf (terminal-renderer-alt-search-state renderer) nil))

(defun renderer-flash (renderer message &optional (duration-ms 1000))
  ;; pi@d981de122 components/alt-screen-flash.ts:20-38 — transient
  ;; message, expiring DURATION-MS after it is shown.
  (incf (terminal-renderer-flash-next-id renderer))
  (push
   (list
    (terminal-renderer-flash-next-id renderer)
    message
    (+ (/ (get-internal-real-time)
          (coerce internal-time-units-per-second 'double-float))
       (/ (max 0 duration-ms) 1000.0d0)))
   (terminal-renderer-flash-entries renderer))
  renderer)

(defun renderer-live-flash-lines (renderer width)
  ;; Expire elapsed entries and return the surviving flash lines,
  ;; oldest first: reverse-video, space-padded, truncated to WIDTH.
  (let ((now
          (/ (get-internal-real-time)
             (coerce internal-time-units-per-second 'double-float))))
    (setf
     (terminal-renderer-flash-entries renderer)
     (remove-if
      (lambda (entry) (<= (third entry) now))
      (terminal-renderer-flash-entries renderer)))
    (mapcar
     (lambda (entry)
       (let ((message
               (truncate-to-width
                (format nil " ~A " (second entry))
                width "")))
         (format nil "~C[7m~A~C[27m"
                 #\Escape message #\Escape)))
     ;; entries accumulate newest-first; render oldest first
     (reverse (terminal-renderer-flash-entries renderer)))))

(defun renderer-note-scrollbar-activity (renderer)
  (setf
   (terminal-renderer-scrollbar-activity-at renderer)
   (/ (get-internal-real-time)
      (coerce internal-time-units-per-second 'double-float)))
  renderer)

(defun renderer-set-clear-on-shrink
    (renderer enabled-p)
  (setf
   (terminal-renderer-clear-on-shrink-p renderer)
   (not (null enabled-p)))
  renderer)

(defun invalidate-renderer (renderer)
  (setf (terminal-renderer-invalid-p renderer) t)
  renderer)

(defun renderer-request-canonical-repaint (renderer)
  ;; Ask the next frame to repaint the full visible region in place,
  ;; without the scrollback-wiping clear that INVALIDATE-RENDERER would
  ;; produce.  The render-diff harness uses this for its work-rendered
  ;; acknowledgement: the checkpoint screen becomes a canonical redraw
  ;; while the terminal's scroll history and viewport stay intact
  ;; (baseline TuiMainScreen never clears on work completion).
  (setf
   (terminal-renderer-canonical-repaint-p renderer)
   t)
  renderer)

(defvar *canonical-repaint-hook* nil
  "Test seam: when non-nil, called with the renderer after a canonical
in-place repaint executes.  Production leaves this NIL; the harness
 acknowledgement tests bind it to count repaints.")

(defparameter +alt-screen-enter+
  (format nil "~C[?1049h" #\Escape))
(defparameter +alt-screen-exit+
  (format nil "~C[?1049l" #\Escape))
(defparameter +autowrap-disable+
  (format nil "~C[?7l" #\Escape))
(defparameter +autowrap-enable+
  (format nil "~C[?7h" #\Escape))
(defun multiplexer-mouse-environment-p ()
  ;; pi@d981de122 tui-alt-screen.ts:236-247 — multiplexers lag when
  ;; every pointer movement is forwarded, so they get button-motion
  ;; tracking (1002) while other terminals get all-motion (1003).
  (let ((term
          (string-downcase (or (uiop:getenv "TERM") ""))))
    (or (uiop:getenv "TMUX")
        (uiop:getenv "ZELLIJ")
        (uiop:getenv "STY")
        (uiop:string-prefix-p "tmux" term)
        (uiop:string-prefix-p "screen" term))))

(defun mouse-enable-sequence ()
  (if (multiplexer-mouse-environment-p)
      (format nil "~C[?1000h~C[?1002h~C[?1004h~C[?1006h"
              #\Escape #\Escape #\Escape #\Escape)
      (format nil "~C[?1000h~C[?1002h~C[?1003h~C[?1004h~C[?1006h"
              #\Escape #\Escape #\Escape #\Escape #\Escape)))

(defparameter +mouse-disable+
  (format nil "~C[?1006l~C[?1004l~C[?1003l~C[?1002l~C[?1000l"
          #\Escape #\Escape #\Escape #\Escape #\Escape))

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
     (terminal-renderer-selection-granularity
      renderer)
     :character
     (terminal-renderer-selection-initial-range
      renderer)
     nil
     (terminal-renderer-last-click-at renderer)
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
                 (mouse-enable-sequence)
                 "")
             #\Escape #\Escape #\Escape)))
  renderer)

(defun renderer-before-stop (renderer)
  (renderer-close-search renderer)
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
    (setf
     (terminal-renderer-flash-entries renderer)
     nil)
    (terminal-write
     (terminal-renderer-terminal renderer)
     (format
      nil "~A~A~A~A~A"
      +synchronized-update-begin+
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
      +synchronized-update-end+)))
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
       (format stream "~A~A~A"
               +synchronized-update-begin+
               +alt-screen-exit+
               +autowrap-disable+)
       ;; v0.85.1 fullscreenExitOutput: resume-hint skips the transcript
       ;; replay; the session's resume hint prints instead.
       (unless
           (eq :resume-hint
               (terminal-renderer-exit-output-mode
                renderer))
         (loop for line across
               (coerce
                (or (terminal-renderer-last-document
                     renderer)
                    #())
                'vector)
               for row from 0
               do
               (when (plusp row)
                 (write-string
                  (format nil "~C~C"
                          #\Return #\Newline)
                  stream))
               (format stream "~C~C[2K~A~C[0m"
                       #\Return #\Escape line #\Escape)))
       (format stream
               "~C[0m~A~C~C~C[?25h~A"
               #\Escape +autowrap-enable+
               #\Return #\Newline
               #\Escape
               +synchronized-update-end+)))
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

(defun renderer-enter-alt-screen-live (renderer)
  "Switch RENDERER from regular to fullscreen mode while running.
Stashes the main-screen render state, flips ALT-SCREEN-P, and emits
the alternate-screen entry sequence.  Callers switch the controlling
mode flag and force a full repaint afterwards."
  (setf
   (terminal-renderer-saved-main-screen-state renderer)
   (list
    :previous-lines
    (terminal-renderer-previous-lines renderer)
    :previous-width
    (terminal-renderer-previous-width renderer)
    :previous-height
    (terminal-renderer-previous-height renderer)
    :cursor-row
    (terminal-renderer-cursor-row renderer)
    :hardware-cursor-row
    (terminal-renderer-hardware-cursor-row renderer)
    :max-lines-rendered
    (terminal-renderer-max-lines-rendered renderer)
    :previous-viewport-top
    (terminal-renderer-previous-viewport-top renderer)))
  (setf
   (terminal-renderer-alt-screen-p renderer) t)
  (renderer-start renderer)
  renderer)

(defun renderer-exit-alt-screen-live (renderer)
  "Switch RENDERER from fullscreen back to regular mode while running.
Emits the alternate-screen exit sequence without replaying the
document (the baseline's preserveScreen stop), restores the stashed
main-screen render state, and clears ALT-SCREEN-P.  Callers switch the
controlling mode flag and repaint afterwards."
  (when
      (terminal-renderer-alt-screen-active-p renderer)
    (terminal-write
     (terminal-renderer-terminal renderer)
     (format
      nil "~A~A~A~A~A"
      +synchronized-update-begin+
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
      +synchronized-update-end+))
    (terminal-write
     (terminal-renderer-terminal renderer)
     (format
      nil "~A~A~C[?25h~A"
      +synchronized-update-begin+
      +alt-screen-exit+
      #\Escape
      +synchronized-update-end+))
    (setf
     (terminal-renderer-alt-screen-active-p renderer)
     nil))
  (when
      (and
       (terminal-renderer-saved-capabilities renderer)
       (not
        (consp
         (terminal-renderer-saved-capabilities renderer))))
    (set-terminal-capabilities
     (terminal-renderer-saved-capabilities renderer))
    (setf
     (terminal-renderer-saved-capabilities renderer)
     nil))
  (setf
   (terminal-renderer-alt-screen-p renderer) nil)
  (let ((main-state
          (terminal-renderer-saved-main-screen-state renderer)))
    (when main-state
      (setf
       (terminal-renderer-previous-lines renderer)
       (getf main-state :previous-lines)
       (terminal-renderer-previous-width renderer)
       (getf main-state :previous-width)
       (terminal-renderer-previous-height renderer)
       (getf main-state :previous-height)
       (terminal-renderer-cursor-row renderer)
       (getf main-state :cursor-row)
       (terminal-renderer-hardware-cursor-row renderer)
       (getf main-state :hardware-cursor-row)
       (terminal-renderer-max-lines-rendered renderer)
       (getf main-state :max-lines-rendered)
       (terminal-renderer-previous-viewport-top renderer)
       (getf main-state :previous-viewport-top))))
  (setf
   (terminal-renderer-saved-main-screen-state renderer)
   nil)
  (setf
   (terminal-renderer-invalid-p renderer) t)
  renderer)

(defun renderer-scroll-by (renderer lines)
  (when (zerop lines)
    (return-from renderer-scroll-by
      renderer))
  (renderer-note-scrollbar-activity renderer)
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
  ;; pi@d981de122 components/scroll-view.ts:140-150 — scroll activity
  ;; is marked only when the position or the follow-end state actually
  ;; changes.
  (let* ((new-sticky-p
           (<=
            (terminal-renderer-content-line-count
             renderer)
            (terminal-rows
             (terminal-renderer-terminal renderer))))
         (changed-p
           (or (plusp (terminal-renderer-scroll-top renderer))
               (not
                (eq new-sticky-p
                    (terminal-renderer-stick-to-bottom-p
                     renderer))))))
    (setf
     (terminal-renderer-scroll-top renderer) 0
     (terminal-renderer-stick-to-bottom-p
      renderer)
     new-sticky-p)
    (when changed-p
      (renderer-note-scrollbar-activity renderer)))
  renderer)

(defun renderer-scroll-to-bottom (renderer)
  (let ((terminal
          (terminal-renderer-terminal renderer)))
    (let ((next
            (max
             0
             (- (terminal-renderer-content-line-count
                 renderer)
                (terminal-rows terminal))))
          (was-sticky-p
            (terminal-renderer-stick-to-bottom-p renderer)))
      (when (or (not was-sticky-p)
                (/= (terminal-renderer-scroll-top renderer) next))
        (renderer-note-scrollbar-activity renderer))
      (setf
       (terminal-renderer-stick-to-bottom-p renderer) t
       (terminal-renderer-scroll-top renderer) next)))
  renderer)

(defun osc133-prompt-start-line-p (line)
  ;; pi@d981de122 tui-alt-screen.ts:56 — /^\x1b\]133;A(?:\x07|\x1b\\)/.
  (and (>= (length line) 8)
       (char= (char line 0) #\Escape)
       (string= "]133;A" line :start2 1 :end2 7)
       (let ((terminator (char line 7)))
         (or (char= terminator (code-char 7))
             (and (char= terminator #\Escape)
                  (>= (length line) 9)
                  (char= (char line 8) #\\))))))

(defun renderer-scroll-to-prompt (renderer direction)
  ;; pi@d981de122 tui-alt-screen.ts:366-378 — scan the scroll content
  ;; from the current viewport edge for the next OSC 133 prompt-start
  ;; marker and land the viewport on it.
  (let* ((terminal
           (terminal-renderer-terminal renderer))
         (height
           (max 1 (terminal-rows terminal)))
         (count
           (terminal-renderer-content-line-count renderer))
         (maximum
           (max 0 (- count height)))
         (current
           (if (terminal-renderer-stick-to-bottom-p renderer)
               maximum
               (terminal-renderer-scroll-top renderer)))
         (lines
           (coerce
            (or (terminal-renderer-prepared-source-lines renderer)
                (terminal-renderer-last-document renderer)
                '())
            'vector))
         (line-count (length lines)))
    (loop for row = (+ current direction) then (+ row direction)
          while (and (<= 0 row) (< row (min count line-count)))
          when (osc133-prompt-start-line-p (aref lines row))
            do (when (/= row current)
                 (setf
                  (terminal-renderer-scroll-top renderer) row
                  (terminal-renderer-stick-to-bottom-p renderer)
                  (= row maximum))
                 (renderer-note-scrollbar-activity renderer))
               (return-from renderer-scroll-to-prompt renderer)))
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

(defun renderer-wheel-scroll-lines (renderer button)
  ;; pi@d981de122 tui-alt-screen.ts:968-970 — SGR bit 3 (value 8) is Alt.
  (let ((lines
          (terminal-renderer-wheel-scroll-lines renderer)))
    (if (zerop (logand button 8))
        lines
        (* lines 5))))

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

(defun selection-columns (line row bounds
                          &key boundary-end-p)
  ;; pi@d981de122 tui-alt-screen.ts:855-869 — a boundary end (word or
  ;; line range edge) is used as-is; a character-drag end extends to
  ;; the grapheme covering it.
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
               (if boundary-end-p
                   (min (cdr end-point) line-width)
                   (let ((range
                           (grapheme-cell-range
                            line (cdr end-point))))
                     (if range
                         (cdr range)
                         (min
                          (1+ (cdr end-point))
                          line-width))))
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

(defun selection-word-character-class (character)
  (cond
    ((navigation-whitespace-p character) :space)
    ((navigation-cjk-p character) :cjk)
    ((or (char= character #\-) (char= character #\/)) :joiner)
    ((navigation-punctuation-p character) :punct)
    (t :word)))

(defun selection-word-joinable-p (class)
  ;; pi@d981de122 tui-alt-screen.ts TERMINAL_WORD_SELECTION_JOINERS:
  ;; keep paths and kebab-case tokens whole under fullscreen selection.
  (member class '(:word :joiner)))

(defun selection-word-range (line column)
  "The (start . end) cell range of the word segment covering COLUMN in
LINE, or NIL when no segment covers it.  Segments follow cadr's
word-navigation character classes, then join word runs across '-' and
'/' (pi@d981de122 tui-alt-screen.ts:835-868)."
  (let ((segments nil)
        (start 0)
        (class nil))
    (loop with cells = 0
          for character across line
          for width = (visible-width (string character))
          for next = (selection-word-character-class character)
          do (when (or (null class)
                       (not (eq next class))
                       (eq next :cjk)
                       (eq class :cjk)
                       (eq next :joiner)
                       (eq class :joiner))
               (when class
                 (push (list start cells class) segments))
               (setf start cells
                     class next))
             (incf cells width)
          finally
             (when class
               (push (list start cells class) segments)))
    (let ((ordered (nreverse segments))
          (merged nil))
      (dolist (segment ordered)
        (let ((previous (first merged)))
          (if (and previous
                   (selection-word-joinable-p (third previous))
                   (selection-word-joinable-p (third segment)))
              (setf (second previous) (second segment)
                    (third previous)
                    (if (or (eq (third previous) :joiner)
                            (eq (third segment) :joiner))
                        :joiner
                        :word))
              (push segment merged))))
      (let ((covering
              (find-if
               (lambda (segment)
                 (and (>= column (first segment))
                      (< column (second segment))))
               (nreverse merged))))
        (and covering
             (cons (first covering) (second covering)))))))

(defun renderer-note-click (renderer row word)
  ;; pi@d981de122 tui-alt-screen.ts:687-713 getClickCount: the count
  ;; advances only for clicks on the same word of the same row within
  ;; 500ms, cycling 1-2-3; a click outside any word resets the streak.
  (let* ((now
           (/ (get-internal-real-time)
              (coerce internal-time-units-per-second 'double-float)))
         (previous-at
           (terminal-renderer-last-click-at renderer))
         (count
           (if (and word previous-at
                    (<= (- now previous-at) 0.5d0)
                    (eql row
                         (terminal-renderer-last-click-row renderer))
                    (eql (car word)
                         (terminal-renderer-last-click-word-start
                          renderer))
                    (eql (cdr word)
                         (terminal-renderer-last-click-word-end
                          renderer)))
               (1+ (mod
                    (terminal-renderer-last-click-count renderer)
                    3))
               1)))
    (if word
        (setf
         (terminal-renderer-last-click-at renderer) now
         (terminal-renderer-last-click-count renderer) count
         (terminal-renderer-last-click-row renderer) row
         (terminal-renderer-last-click-word-start renderer)
         (car word)
         (terminal-renderer-last-click-word-end renderer)
         (cdr word))
        (setf
         (terminal-renderer-last-click-at renderer) nil))
    count))

(defun renderer-document-line (document row)
  ;; last-document is a vector after render-alt-frame. NTH past
  ;; the end is NIL; AREF is not. Tests still SETF a list.
  (cond
    ((or (not (integerp row)) (minusp row))
     "")
    ((vectorp document)
     (if (< row (length document))
         (aref document row)
         ""))
    (t
     (or (nth row document) ""))))

(defun renderer-selection-source-line (renderer row)
  (strip-ansi
   (renderer-document-line
    (terminal-renderer-last-document renderer)
    row)))

(defun renderer-line-selection-range (renderer row)
  (cons (cons row 0)
        (cons row
              (visible-width
               (renderer-selection-source-line renderer row)))))

(defun selection-point-before-p (left right)
  (or (< (car left) (car right))
      (and (= (car left) (car right))
           (< (cdr left) (cdr right)))))

(defun renderer-active-selection-text (renderer)
  (let ((bounds
          (renderer-selection-bounds
           renderer)))
    (unless bounds
      (return-from renderer-active-selection-text
        nil))
    (let ((lines nil))
      (loop for row from
            (car (car bounds))
            to (car (cdr bounds))
            for line =
            (renderer-document-line
             (terminal-renderer-last-document
              renderer)
             row)
            for columns =
            (selection-columns
             line row bounds
             :boundary-end-p
             (member
              (terminal-renderer-selection-granularity
               renderer)
              '(:word :line)))
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
        (and (plusp (length text)) text)))))

(defun renderer-has-active-selection-p (renderer)
  (not (null (renderer-active-selection-text renderer))))

(defun renderer-copy-selection (renderer)
  (let ((text (renderer-active-selection-text renderer)))
    (unless text
      (return-from renderer-copy-selection nil))
    (let ((copier
            (terminal-renderer-copy-selection-function
             renderer)))
      (if copier
          ;; v0.85.1: the host clipboard path reports success; a
          ;; bare OSC 52 write can flash "Copied!" without
          ;; reaching the system clipboard.
          (renderer-flash
           renderer
           (if (funcall copier text) "Copied!" "Copy failed"))
          (progn
            ;; pi@d981de122 tui-alt-screen.ts:896 — the fullscreen
            ;; copy confirmation is a flash, not a status.
            (renderer-flash renderer "Copied!")
            (terminal-write
             (terminal-renderer-terminal
              renderer)
             (format nil "~C]52;c;~A~C"
                     #\Escape
                     (utf8-base64 text)
                     (code-char 7))))))
    t))

(defun renderer-copy-active-selection (renderer)
  (renderer-copy-selection renderer))

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
           (viewport-column
             (max
              0
              (min
               (1- (terminal-columns terminal))
               (getf event :x))))
           (point
             (cons
              (+ (terminal-renderer-scroll-top
                  renderer)
                 viewport-row)
              viewport-column))
           (jump-rect
             (terminal-renderer-scroll-to-end-indicator-rect
              renderer)))
      ;; pi@d981de122 handleScrollToEndIndicatorMouseEvent
      (when
          (and jump-rect
               (not (getf event :release-p))
               (zerop (logand button 32))
               (= viewport-row (getf jump-rect :row))
               (<= (getf jump-rect :column) viewport-column)
               (< viewport-column
                  (+ (getf jump-rect :column)
                     (getf jump-rect :width))))
        (renderer-scroll-to-bottom renderer)
        (return-from renderer-handle-mouse t))
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
                 (when (terminal-renderer-copy-on-select-p
                        renderer)
                   (renderer-copy-selection
                    renderer))))))
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
            ;; A drag breaks the click streak (baseline motion resets
            ;; lastClick).
            (terminal-renderer-last-click-at renderer)
            nil)
           ;; pi@d981de122 tui-alt-screen.ts:665-684
           ;; updateSelectionFocus: word/line drags extend from the
           ;; initial range by whole segments.
           (let ((granularity
                   (terminal-renderer-selection-granularity
                    renderer))
                 (initial
                   (terminal-renderer-selection-initial-range
                    renderer)))
             (if (or (eq granularity :character)
                     (null initial))
                 (setf
                  (terminal-renderer-selection-focus renderer)
                  point)
                 (let ((range
                         (if (eq granularity :word)
                             (let ((word
                                     (selection-word-range
                                      (renderer-selection-source-line
                                       renderer (car point))
                                      (cdr point))))
                               (and word
                                    (cons
                                     (cons (car point) (car word))
                                     (cons (car point) (cdr word)))))
                             (renderer-line-selection-range
                              renderer (car point)))))
                   (when range
                     (if (selection-point-before-p
                          (car range) (car initial))
                         (setf
                          (terminal-renderer-selection-anchor
                           renderer)
                          (cdr initial)
                          (terminal-renderer-selection-focus
                           renderer)
                          (car range))
                         (setf
                          (terminal-renderer-selection-anchor
                           renderer)
                          (car initial)
                          (terminal-renderer-selection-focus
                           renderer)
                          (cdr range)))))))))
        (t
         ;; pi@d981de122 tui-alt-screen.ts:813-833 — word/line ranges
         ;; on double/triple click, character selection otherwise;
         ;; range presses never arm URL activation.
         (let* ((word
                  (selection-word-range
                   (renderer-selection-source-line
                    renderer (car point))
                   (cdr point)))
                (click-count
                  (renderer-note-click renderer (car point) word))
                (range
                  (cond
                    ((= click-count 2)
                     (and word
                          (cons
                           (cons (car point) (car word))
                           (cons (car point) (cdr word)))))
                    ((= click-count 3)
                     (renderer-line-selection-range
                      renderer (car point)))
                    (t nil))))
           (setf
            (terminal-renderer-selection-granularity
             renderer)
            (cond
              ((= click-count 2) :word)
              ((= click-count 3) :line)
              (t :character))
            (terminal-renderer-selection-initial-range
             renderer)
            range
            (terminal-renderer-selection-anchor
             renderer)
            (or (car range) point)
            (terminal-renderer-selection-focus
             renderer)
            (or (cdr range) point)
            (terminal-renderer-selection-dragged-p
             renderer)
            nil
            (terminal-renderer-pressed-url
             renderer)
            (and
             (null range)
             (osc8-link-at-column
              (or
               (nth
                viewport-row
                (terminal-renderer-previous-lines
                 renderer))
               "")
              (cdr point)))))))
    t)))

(defun renderer-deliver-component-mouse (renderer mouse)
  (let ((handler (terminal-renderer-component-mouse-function renderer)))
    (unless handler
      (return-from renderer-deliver-component-mouse nil))
    (let* ((button (getf mouse :button))
           (x (getf mouse :x))
           (y (getf mouse :y))
           (wheel-p (not (zerop (logand button 64))))
           (motion-p (not (zerop (logand button 32))))
           (release-p (getf mouse :release-p))
           (decoded
             (case (logand button 3)
               (0 :left)
               (1 :middle)
               (2 :right)
               (t :none)))
           (press (terminal-renderer-component-mouse-press renderer)))
      (when (and press
                 (or (/= x (car press)) (/= y (cdr press))))
        (setf (terminal-renderer-component-mouse-moved-p renderer) t))
      (labels ((gesture (type button-name wheel-delta)
                 (list :type type
                       :button button-name
                       :x x
                       :y y
                       :wheel-delta wheel-delta))
               (deliver (plist)
                 (not (null (funcall handler plist)))))
        (cond
          (wheel-p
           (let ((direction (logand button 3)))
             (when (member direction '(0 1))
               (deliver
                (gesture :wheel :none
                         (if (zerop direction) -1 1))))))
          (release-p
             (let ((clicked
                     (and press
                          (not (terminal-renderer-component-mouse-moved-p
                                renderer))
                          (= x (car press))
                          (= y (cdr press))
                          (deliver (gesture :click decoded nil)))))
               (when clicked
                 (setf (terminal-renderer-selection-anchor renderer) nil
                       (terminal-renderer-selection-focus renderer) nil
                       (terminal-renderer-selection-dragged-p renderer) nil))
               (setf (terminal-renderer-component-mouse-press renderer) nil
                     (terminal-renderer-component-mouse-moved-p renderer) nil)
               clicked))
          (motion-p
           (deliver
            (gesture (if (eq decoded :none) :move :drag) decoded nil)))
          (t
           (setf (terminal-renderer-component-mouse-press renderer)
                 (cons x y)
                 (terminal-renderer-component-mouse-moved-p renderer) nil)
           (deliver (gesture :press decoded nil))))))))

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
      (when (renderer-deliver-component-mouse renderer mouse)
        (return-from renderer-handle-input t))
      (let ((button (getf mouse :button)))
        (when
            (not
             (zerop (logand button 64)))
          (case (logand button 3)
            (0
             (renderer-scroll-by
              renderer
              (- (renderer-wheel-scroll-lines
                  renderer button))))
            (1
             (renderer-scroll-by
              renderer
              (renderer-wheel-scroll-lines
               renderer button)))))
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
    ;; v0.85.1: while the find bar is open it consumes keyboard input;
    ;; only the four search actions stay live.
    (when (keybinding-matches-p
           keybindings data
           "tui.altScreen.search")
      (renderer-open-search renderer)
      (return-from renderer-handle-input t))
    (let ((search (terminal-renderer-alt-search-state renderer)))
      (when search
        (cond
          ((keybinding-matches-p
            keybindings data
            "tui.altScreen.searchNext")
           (setf (alt-search-state-selection-mode search) :next))
          ((keybinding-matches-p
            keybindings data
            "tui.altScreen.searchPrevious")
           (setf (alt-search-state-selection-mode search) :previous))
          ((keybinding-matches-p
            keybindings data
            "tui.altScreen.searchClose")
           (renderer-close-search renderer))
          ((member data (list (string #\Rubout) (string #\Backspace))
                   :test #'string=)
           (let ((query (alt-search-state-query search)))
             (when (plusp (length query))
               ;; Drop the trailing grapheme, not the trailing codepoint.
               (let ((clusters (grapheme-clusters query)))
                 (setf (alt-search-state-query search)
                       (apply #'concatenate 'string
                              (butlast clusters)))))))
          ((and (plusp (length data))
                (every (lambda (character)
                         (and (graphic-char-p character)
                              (not (char= character #\Rubout))))
                       data))
           (setf (alt-search-state-query search)
                 (concatenate 'string
                              (alt-search-state-query search) data))))
        (return-from renderer-handle-input t)))
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
        "tui.altScreen.halfPageUp")
       ;; pi@d981de122 tui-alt-screen.ts:435-441
       (renderer-scroll-by
        renderer (- (max 1 (floor height 2))))
       t)
      ((keybinding-matches-p
        keybindings data
        "tui.altScreen.halfPageDown")
       (renderer-scroll-by
        renderer (max 1 (floor height 2)))
       t)
      ;; v0.85.1: one-line viewport scrolling.
      ((keybinding-matches-p
        keybindings data
        "tui.altScreen.lineUp")
       (renderer-scroll-by renderer -1)
       t)
      ((keybinding-matches-p
        keybindings data
        "tui.altScreen.lineDown")
       (renderer-scroll-by renderer 1)
       t)
      ((keybinding-matches-p
        keybindings data
        "tui.altScreen.previousPrompt")
       (renderer-scroll-to-prompt renderer -1)
       t)
      ((keybinding-matches-p
        keybindings data
        "tui.altScreen.nextPrompt")
       (renderer-scroll-to-prompt renderer 1)
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
                            line row bounds
                            :boundary-end-p
                            (member
                             (terminal-renderer-selection-granularity
                              renderer)
                             '(:word :line))))
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
