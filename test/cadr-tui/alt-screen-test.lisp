(in-package #:cadr-tui/tests)
(in-suite cadr-tui-suite)

(defclass alt-recording-terminal
    (cadr-tui:virtual-terminal)
  ((events :initform nil
           :accessor alt-recording-events)))

(defun record-alt-event (terminal type &optional data)
  (setf
   (alt-recording-events terminal)
   (append
    (alt-recording-events terminal)
    (list (list :type type :data data)))))

(defmethod cadr-tui:terminal-start
    ((terminal alt-recording-terminal))
  (record-alt-event terminal :start))

(defmethod cadr-tui:terminal-stop
    ((terminal alt-recording-terminal))
  (record-alt-event terminal :stop))

(defmethod cadr-tui:terminal-write :around
    ((terminal alt-recording-terminal) text)
  (record-alt-event terminal :write text)
  (call-next-method))

(defun make-alt-recording-terminal
    (&key (columns 20) (rows 4))
  (make-instance
   'alt-recording-terminal
   :columns columns
   :rows rows))

(defun alt-event-index (terminal type &optional needle)
  (position-if
   (lambda (event)
     (and
      (eq type (getf event :type))
      (or
       (null needle)
       (and
        (stringp (getf event :data))
        (search needle (getf event :data))))))
   (alt-recording-events terminal)))

(defun alt-write-containing-p (terminal needle)
  (find-if
   (lambda (event)
     (and
      (eq :write (getf event :type))
      (search needle (getf event :data))))
   (alt-recording-events terminal)))

(defun alt-write-containing-count
    (terminal needle)
  (count-if
   (lambda (event)
     (and
      (eq :write (getf event :type))
      (search needle (getf event :data))))
   (alt-recording-events terminal)))

(defun alt-render
    (renderer lines &key
                      (cursor-row
                        (max 0 (1- (length lines))))
                      (cursor-column 0))
  (cadr-tui:render-frame
   renderer lines
   :cursor-row cursor-row
   :cursor-column cursor-column))

(test alt-screen-renders-viewport-and-preserves-manual-scroll
  (let* ((terminal
           (make-alt-recording-terminal :rows 4))
         (renderer
           (cadr-tui:make-terminal-renderer
            terminal :alt-p t))
         (ten
           (loop for index from 1 to 10
                 collect
                 (format nil "line ~D" index))))
    (cadr-tui:renderer-start renderer)
    (alt-render renderer ten)
    (is (equal
         '("line 7" "line 8" "line 9" "line 10")
         (mapcar
          (lambda (line)
            (string-right-trim " " line))
          (cadr-tui:virtual-terminal-snapshot
           terminal))))
    (is (cadr-tui:renderer-following-output-p
         renderer))
    (is
     (cadr-tui:renderer-handle-input
      renderer
      (format nil "~C[<64;1;1M" #\Escape)))
    (alt-render renderer ten)
    (is (= 3
           (cadr-tui:renderer-viewport-top
            renderer)))
    (is (not
         (cadr-tui:renderer-following-output-p
          renderer)))
    (alt-render
     renderer
     (loop for index from 1 to 12
           collect (format nil "line ~D" index)))
    (is (= 3
           (cadr-tui:renderer-viewport-top
            renderer)))))

(test goal11-alt-input-reuses-baseline-differential-redraw
  (let* ((terminal
           (make-alt-recording-terminal :rows 4))
         (renderer
           (cadr-tui:make-terminal-renderer
            terminal :alt-p t))
         (lines
           (loop for index from 1 to 20
                 collect (format nil "line ~D" index)))
         (clear-screen
           (format nil "~C[2J" #\Escape)))
    (cadr-tui:renderer-start renderer)
    (alt-render renderer lines)
    (setf (alt-recording-events terminal) nil)
    (cadr-tui:renderer-handle-input
     renderer
     (format nil "~C[<64;1;1M" #\Escape))
    (alt-render renderer lines)
    (is (not (alt-write-containing-p
              terminal clear-screen)))
    (setf (alt-recording-events terminal) nil)
    (cadr-tui:renderer-handle-input
     renderer
     (format nil "~C[<0;2;2M" #\Escape))
    (cadr-tui:renderer-handle-input
     renderer
     (format nil "~C[<32;5;3M" #\Escape))
    (alt-render renderer lines)
    (is (not (alt-write-containing-p
              terminal clear-screen)))))

(test goal13-alt-screen-reuses-only-the-unchanged-prepared-prefix
  (let* ((terminal
           (make-alt-recording-terminal
            :columns 12 :rows 3))
         (renderer
           (cadr-tui:make-terminal-renderer
            terminal :alt-p t))
         (prefix
           (list
            "stable one"
            (format nil "~C]133;B~Cstable two"
                    #\Escape (code-char 7))
            "stable three"))
         (first-lines
           (append prefix
                   (list "old suffix that clips")))
         (second-lines
           (append prefix
                   (list "new suffix that clips"))))
    (cadr-tui:renderer-start renderer)
    (alt-render renderer first-lines)
    (let ((first-document
            (copy-seq
             (cadr-tui::terminal-renderer-last-document
              renderer))))
      (alt-render renderer second-lines)
      (let ((second-document
              (cadr-tui::terminal-renderer-last-document
               renderer)))
        (is (= 3
               (cadr-tui::terminal-renderer-prepared-prefix-reused
                renderer)))
        (is (every #'eq
                   (subseq first-document 0 3)
                   (subseq second-document 0 3)))
        (is (not (eq (elt first-document 3)
                     (elt second-document 3))))
        (is (equalp
             (coerce
              (cadr-tui::prepare-alt-document
               second-lines 12)
              'vector)
             second-document)))
      (setf (cadr-tui:terminal-columns terminal) 10)
      (alt-render renderer second-lines)
      (is (= 0
             (cadr-tui::terminal-renderer-prepared-prefix-reused
              renderer)))
      (is (equalp
           (coerce
            (cadr-tui::prepare-alt-document
             second-lines 10)
            'vector)
           (cadr-tui::terminal-renderer-last-document
            renderer))))))

(test goal13-alt-screen-prepared-cache-keeps-the-full-document-contract
  (let* ((terminal
           (make-alt-recording-terminal :rows 2))
         (renderer
           (cadr-tui:make-terminal-renderer
            terminal :alt-p t))
         (prefix (list "first" "second" "third"))
         (initial (append prefix (list "old tail")))
         (updated (append prefix (list "new tail"))))
    (cadr-tui:renderer-start renderer)
    (cadr-tui:terminal-start terminal)
    (alt-render renderer initial)
    (alt-render renderer updated)
    (is (equalp
         (coerce updated 'vector)
         (cadr-tui::terminal-renderer-last-document
          renderer)))
    (cadr-tui:renderer-before-stop renderer)
    (cadr-tui:terminal-stop terminal)
    (cadr-tui:renderer-after-stop renderer)
    (let* ((exit
             (alt-event-index
              terminal :write
              (format nil "~C[?1049l" #\Escape)))
           (restore
             (getf
              (nth exit (alt-recording-events terminal))
              :data)))
      (is (search "first" restore))
      (is (search "new tail" restore))
      (is (null (search "old tail" restore))))))

(test alt-screen-supports-configurable-keyboard-navigation
  (let* ((terminal
           (make-alt-recording-terminal :rows 4))
         (renderer
           (cadr-tui:make-terminal-renderer
            terminal :alt-p t))
         (lines
           (loop for index from 1 to 8
                 collect
                 (format nil "line ~D" index))))
    (cadr-tui:renderer-start renderer)
    (alt-render renderer lines)
    (is
     (cadr-tui:renderer-handle-input
      renderer
      (format nil "~C[5~~" #\Escape)))
    (alt-render renderer lines)
    (is (= 1
           (cadr-tui:renderer-viewport-top
            renderer)))
    (is
     (cadr-tui:renderer-handle-input
      renderer
      (format nil "~C[F" #\Escape)))
    (alt-render renderer lines)
    (is (= 4
           (cadr-tui:renderer-viewport-top
            renderer)))))

(test alt-screen-half-page-and-prompt-jump-follow-the-baseline-rules
  ;; pi@ecac0a9c4 tui-alt-screen.ts:435-449 — half-page scrolls by
  ;; floor(viewport/2); prompt jumps land on the next OSC 133;A row.
  (let ((previous (cadr-tui:get-keybindings)))
    (unwind-protect
         (progn
          (cadr-tui:set-keybindings
           (cadr-tui:make-keybindings-manager
            :user-bindings
            '(("tui.altScreen.halfPageUp" . ("shift+up"))
              ("tui.altScreen.halfPageDown" . ("shift+down")))))
          (let* ((terminal
                   (make-alt-recording-terminal :rows 4))
                 (renderer
                   (cadr-tui:make-terminal-renderer
                    terminal :alt-p t))
                 (prompt
                   (format nil "~C]133;A~C" #\Escape (code-char 7)))
                 (lines
                   (list "intro"
                         (concatenate 'string prompt "first")
                         "body 1" "body 2"
                         (concatenate 'string prompt "second")
                         "body 3" "body 4" "body 5")))
            (cadr-tui:renderer-start renderer)
            (alt-render renderer lines)
            ;; half-page up from the bottom moves floor(4/2) = 2 rows.
            (is
             (cadr-tui:renderer-handle-input
              renderer (format nil "~C[a" #\Escape)))
            (alt-render renderer lines)
            (is (= 2 (cadr-tui:renderer-viewport-top renderer)))
            ;; half-page down returns to the bottom.
            (is
             (cadr-tui:renderer-handle-input
              renderer (format nil "~C[b" #\Escape)))
            (alt-render renderer lines)
            (is (= 4 (cadr-tui:renderer-viewport-top renderer)))
            ;; ctrl+shift+up scans upward from one past the top edge,
            ;; landing on the first prompt row (index 1).
            (is
             (cadr-tui:renderer-handle-input
              renderer (format nil "~C[1;6A" #\Escape)))
            (alt-render renderer lines)
            (is (= 1 (cadr-tui:renderer-viewport-top renderer)))
            ;; no earlier prompt row exists; the viewport stays.
            (is
             (cadr-tui:renderer-handle-input
              renderer (format nil "~C[1;6A" #\Escape)))
            (alt-render renderer lines)
            (is (= 1 (cadr-tui:renderer-viewport-top renderer)))
            ;; ctrl+shift+down jumps forward to the second prompt.
            (is
             (cadr-tui:renderer-handle-input
              renderer (format nil "~C[1;6B" #\Escape)))
            (alt-render renderer lines)
            (is (= 4 (cadr-tui:renderer-viewport-top renderer)))))
      (cadr-tui:set-keybindings previous))))

(test alt-screen-scrollbar-follows-the-baseline-geometry-and-visibility
  ;; pi@ecac0a9c4 layout.ts:268-303 + components/scroll-view.ts:62-70:
  ;; auto mode paints the thumb only after real scroll activity while
  ;; the content overflows; thumb height is track²/content clamped to
  ;; [min(2, track), track]; the offset maps scrollTop onto the free
  ;; track.  8 lines in a 4x20 viewport: thumb height 2, and at
  ;; scroll-top 0 the thumb covers rows 0-1 of the last column.
  (let* ((terminal
           (make-alt-recording-terminal :columns 20 :rows 4))
         (renderer
           (cadr-tui:make-terminal-renderer
            terminal :alt-p t))
         (thumb-bg
           (cadr-tui:theme-background-ansi
            :scrollbar-thumb :enabled-p t))
         (lines
           (loop for index from 1 to 8
                 collect
                 (format nil "line ~D" index))))
    (cadr-tui:renderer-start renderer)
    (alt-render renderer lines)
    ;; No scroll activity yet: the auto scrollbar stays hidden.
    (is (null (alt-write-containing-p terminal thumb-bg)))
    ;; scroll-to-top from the bottom is a real position change.
    (cadr-tui:renderer-scroll-to-top renderer)
    (alt-render renderer lines)
    (is (alt-write-containing-p terminal thumb-bg))
    ;; A no-op repeat marks no new activity: scroll-to-top at the top
    ;; leaves the timestamp alone, so the hide window is not extended.
    (let ((at
            (cadr-tui::terminal-renderer-scrollbar-activity-at
             renderer)))
      (cadr-tui:renderer-scroll-to-top renderer)
      (is (eql at
               (cadr-tui::terminal-renderer-scrollbar-activity-at
                renderer))))))

(test alt-screen-disables-iterm-images-and-strips-osc133
  (cadr-tui:set-terminal-capabilities
   (cadr-tui:make-terminal-capabilities
    :images :iterm2
    :true-color-p t
    :hyperlinks-p t))
  (unwind-protect
       (let* ((terminal
                (make-alt-recording-terminal
                 :rows 3))
              (renderer
                (cadr-tui:make-terminal-renderer
                 terminal :alt-p t))
              (line
                (format
                 nil "~C]133;B~C~C]133;C~Ccontent"
                 #\Escape (code-char 7)
                 #\Escape (code-char 7))))
         (cadr-tui:renderer-start renderer)
         (is (null
              (cadr-tui:terminal-capabilities-images
               (cadr-tui:get-terminal-capabilities))))
         (alt-render
          renderer
          (list line "[Image: example.png]"))
         (cadr-tui:renderer-before-stop renderer)
         (cadr-tui:renderer-after-stop renderer)
         (is (not
              (alt-write-containing-p
               terminal
               (format nil "~C]133;" #\Escape))))
         (is (alt-write-containing-p
              terminal "[Image: example.png]"))
         (is (eq
              :iterm2
              (cadr-tui:terminal-capabilities-images
               (cadr-tui:get-terminal-capabilities)))))
    (cadr-tui:reset-terminal-capabilities)))

(test alt-screen-clears-stale-iterm-image-placements
  (cadr-tui:set-terminal-capabilities
   (cadr-tui:make-terminal-capabilities
    :images :iterm2
    :true-color-p t
    :hyperlinks-p t))
  (unwind-protect
       (let* ((terminal
                (make-alt-recording-terminal
                 :rows 3))
              (renderer
                (cadr-tui:make-terminal-renderer
                 terminal :alt-p t))
              (image
                (format
                 nil
                 "~C]1337;File=inline=1;width=2;height=auto:AAAA~C"
                 #\Escape (code-char 7)))
              (lines
                (list image "" "" "after" "more"
                      "end")))
         (cadr-tui:renderer-start renderer)
         (alt-render renderer lines)
         (cadr-tui:renderer-scroll-to-top
          renderer)
         (alt-render renderer lines)
         (setf (alt-recording-events terminal)
               nil)
         (cadr-tui:renderer-scroll-by renderer 1)
         (alt-render renderer lines)
         (is
          (alt-write-containing-p
           terminal
           (format nil "~C[2J" #\Escape))))
    (cadr-tui:reset-terminal-capabilities)))

(test alt-screen-crops-kitty-image-above-viewport
  (let* ((terminal
           (make-alt-recording-terminal :rows 3))
         (renderer
           (cadr-tui:make-terminal-renderer
            terminal :alt-p t))
         (image
           (cadr-tui:encode-kitty-image
            "AAAA"
            :columns 2 :rows 3
            :image-id 123
            :move-cursor-p nil)))
    (cadr-tui:register-kitty-image-metadata
     :image-id 123 :columns 2 :rows 3
     :width-px 100 :height-px 100)
    (cadr-tui:renderer-start renderer)
    (alt-render
     renderer
     (list "before" image "" "" "after" "end"))
    (is (= 3
           (cadr-tui:renderer-viewport-top
            renderer)))
    (is (alt-write-containing-p terminal "i=123"))
    (is (alt-write-containing-p
         terminal "y=66,h=34,r=1"))))

(test alt-screen-opens-osc8-link-on-click-not-drag
  (let* ((opened nil)
         (terminal
           (make-alt-recording-terminal :rows 3))
         (renderer
           (cadr-tui:make-terminal-renderer
            terminal :alt-p t
            :open-url-function
            (lambda (url)
              (push url opened))))
         (url "https://example.com/path?q=1")
         (bel-url "https://example.com/bel")
         (emoji-url "https://example.com/emoji")
         (line
           (cadr-tui:terminal-hyperlink
            "link" url))
         (bel-line
           (format
            nil "~C]8;;~A~Clink~C]8;;~C"
            #\Escape bel-url (code-char 7)
            #\Escape (code-char 7)))
         (emoji-line
           (cadr-tui:terminal-hyperlink
            "🙂" emoji-url)))
    (cadr-tui:renderer-start renderer)
    (alt-render
     renderer
     (list line bel-line emoji-line))
    (cadr-tui:renderer-handle-input
     renderer
     (format nil "~C[<0;2;1M" #\Escape))
    (cadr-tui:renderer-handle-input
     renderer
     (format nil "~C[<0;2;1m" #\Escape))
    (is (equal (list url) opened))
    (cadr-tui:renderer-handle-input
     renderer
     (format nil "~C[<0;2;2M" #\Escape))
    (cadr-tui:renderer-handle-input
     renderer
     (format nil "~C[<0;2;2m" #\Escape))
    (is (equal (list bel-url url) opened))
    (cadr-tui:renderer-handle-input
     renderer
     (format nil "~C[<0;2;3M" #\Escape))
    (cadr-tui:renderer-handle-input
     renderer
     (format nil "~C[<0;2;3m" #\Escape))
    (is (equal
         (list emoji-url bel-url url)
         opened))
    (cadr-tui:renderer-handle-input
     renderer
     (format nil "~C[<0;2;1M" #\Escape))
    (cadr-tui:renderer-handle-input
     renderer
     (format nil "~C[<32;4;1M" #\Escape))
    (cadr-tui:renderer-handle-input
     renderer
     (format nil "~C[<0;4;1m" #\Escape))
    (is (equal
         (list emoji-url bel-url url)
         opened))))

(test alt-screen-copies-mouse-selection-with-osc52
  (let* ((terminal
           (make-alt-recording-terminal :rows 4))
         (renderer
           (cadr-tui:make-terminal-renderer
            terminal :alt-p t)))
    (cadr-tui:renderer-start renderer)
    (alt-render renderer
                '("alpha" "beta" "gamma" "delta"))
    (cadr-tui:renderer-handle-input
     renderer
     (format nil "~C[<0;1;1M" #\Escape))
    (cadr-tui:renderer-handle-input
     renderer
     (format nil "~C[<32;4;2M" #\Escape))
    (cadr-tui:renderer-handle-input
     renderer
     (format nil "~C[<0;4;2m" #\Escape))
    (alt-render renderer
                '("alpha" "beta" "gamma" "delta"))
    (is
     (alt-write-containing-p
      terminal
      (format nil "~C]52;c;YWxwaGEKYmV0YQ==~C"
              #\Escape (code-char 7))))
    (is
     (alt-write-containing-p
      terminal
      (format nil "~C[7m" #\Escape)))))

(test alt-screen-selection-snaps-to-graphemes
  (let* ((terminal
           (make-alt-recording-terminal :rows 2))
         (renderer
           (cadr-tui:make-terminal-renderer
            terminal :alt-p t))
         (line "A界🙂éZ"))
    (cadr-tui:renderer-start renderer)
    (alt-render renderer (list line))
    (cadr-tui:renderer-handle-input
     renderer
     (format nil "~C[<0;3;1M" #\Escape))
    (cadr-tui:renderer-handle-input
     renderer
     (format nil "~C[<32;4;1M" #\Escape))
    (cadr-tui:renderer-handle-input
     renderer
     (format nil "~C[<0;4;1m" #\Escape))
    (let ((wide
            (format
             nil "~C]52;c;55WM8J+Zgg==~C"
             #\Escape (code-char 7))))
      (is (= 1
             (alt-write-containing-count
              terminal wide)))
      (cadr-tui:renderer-handle-input
       renderer
       (format nil "~C[<0;5;1M" #\Escape))
      (cadr-tui:renderer-handle-input
       renderer
       (format nil "~C[<32;2;1M" #\Escape))
      (cadr-tui:renderer-handle-input
       renderer
       (format nil "~C[<0;2;1m" #\Escape))
      (is (= 2
             (alt-write-containing-count
              terminal wide))))
    (cadr-tui:renderer-handle-input
     renderer
     (format nil "~C[<0;6;1M" #\Escape))
    (cadr-tui:renderer-handle-input
     renderer
     (format nil "~C[<32;7;1M" #\Escape))
    (cadr-tui:renderer-handle-input
     renderer
     (format nil "~C[<0;7;1m" #\Escape))
    (is
     (alt-write-containing-p
      terminal
      (format nil "~C]52;c;ZcyBWg==~C"
              #\Escape (code-char 7))))))

(test alt-screen-ignores-horizontal-wheel
  (let* ((terminal
           (make-alt-recording-terminal :rows 4))
         (renderer
           (cadr-tui:make-terminal-renderer
            terminal :alt-p t))
         (lines
           (loop for index from 1 to 8
                 collect
                 (format nil "line ~D" index))))
    (cadr-tui:renderer-start renderer)
    (alt-render renderer lines)
    (cadr-tui:renderer-handle-input
     renderer
     (format nil "~C[<66;1;1M" #\Escape))
    (cadr-tui:renderer-handle-input
     renderer
     (format nil "~C[<67;1;1M" #\Escape))
    (is (= 4
           (cadr-tui:renderer-viewport-top
            renderer)))))

(test alt-screen-alt-wheel-scrolls-five-times-faster
  ;; pi@ecac0a9c4 tui-alt-screen.ts:75,968-970 — SGR bit 3 (8) is Alt.
  (let* ((terminal
           (make-alt-recording-terminal :rows 4))
         (renderer
           (cadr-tui:make-terminal-renderer
            terminal :alt-p t :wheel-scroll-lines 3))
         (lines
           (loop for index from 1 to 40
                 collect
                 (format nil "line ~D" index))))
    (cadr-tui:renderer-start renderer)
    (alt-render renderer lines)
    (cadr-tui:renderer-scroll-to-top renderer)
    (is (= 0 (cadr-tui:renderer-viewport-top renderer)))
    ;; Plain wheel down (button 65 = 64|1): +3 lines.
    (cadr-tui:renderer-handle-input
     renderer
     (format nil "~C[<65;1;1M" #\Escape))
    (is (= 3 (cadr-tui:renderer-viewport-top renderer)))
    ;; Alt+wheel down (button 73 = 64|8|1): +15 lines.
    (cadr-tui:renderer-handle-input
     renderer
     (format nil "~C[<73;1;1M" #\Escape))
    (is (= 18 (cadr-tui:renderer-viewport-top renderer)))))

(test alt-screen-jump-to-latest-indicator-when-scrolled-up
  ;; pi@ecac0a9c4 tui-alt-screen.ts:1618-1635
  (let* ((terminal
           (make-alt-recording-terminal :rows 4 :columns 48))
         (renderer
           (cadr-tui:make-terminal-renderer
            terminal
            :alt-p t
            :scroll-to-end-indicator-function
            (lambda ()
              " ↓ Jump to latest message · End ")))
         (lines
           (loop for index from 1 to 20
                 collect
                 (format nil "line ~D" index))))
    (cadr-tui:renderer-start renderer)
    (alt-render renderer lines)
    (cadr-tui:renderer-scroll-to-top renderer)
    (alt-render renderer lines)
    (is
     (alt-write-containing-p
      terminal "Jump to latest message"))
    (let ((rect
            (cadr-tui::terminal-renderer-scroll-to-end-indicator-rect
             renderer)))
      (is (not (null rect)))
      (cadr-tui:renderer-handle-input
       renderer
       (format
        nil "~C[<0;~D;~DM"
        #\Escape
        (1+ (getf rect :column))
        (1+ (getf rect :row))))
      (is (cadr-tui:renderer-following-output-p renderer)))))

(test alt-screen-restores-terminal-before-exit-and-prints-document
  (let* ((terminal
           (make-alt-recording-terminal :rows 3))
         (renderer
           (cadr-tui:make-terminal-renderer
            terminal :alt-p t))
         (document
           '("first" "second" "third"
             "fourth" "fifth" "sixth")))
    (cadr-tui:renderer-start renderer)
    (cadr-tui:terminal-start terminal)
    (alt-render renderer document)
    (cadr-tui:renderer-before-stop renderer)
    (cadr-tui:terminal-stop terminal)
    (cadr-tui:renderer-after-stop renderer)
    (let ((enter
            (alt-event-index
             terminal :write
             (format nil "~C[?1049h" #\Escape)))
          (start
            (alt-event-index terminal :start))
          (disable
            (alt-event-index
             terminal :write
             (format nil "~C[?1006l" #\Escape)))
          (stop
            (alt-event-index terminal :stop))
          (exit
            (alt-event-index
             terminal :write
             (format nil "~C[?1049l" #\Escape))))
      (is (and enter start (< enter start)))
      (is (and disable stop (< disable stop)))
      (is (and exit stop (> exit stop)))
      (let ((restore
              (getf
               (nth exit
                    (alt-recording-events
                     terminal))
               :data)))
        (dolist (line document)
          (is (search line restore)))
        (is (< (search "first" restore)
               (search "sixth" restore)))))))

(test renderer-live-mode-switch-round-trips-main-screen-state
  ;; pi@ecac0a9c4 interactive-mode.ts:788-832 — a live tuiMode switch
  ;; preserves the main-screen render state across the fullscreen
  ;; round-trip and emits the preserveScreen exit sequence.
  (let* ((terminal (make-alt-recording-terminal))
         (renderer
           (cadr-tui:make-terminal-renderer terminal :alt-p nil)))
    ;; Seed a main-screen differential state.
    (setf
     (cadr-tui::terminal-renderer-previous-lines renderer)
     (list "alpha" "beta")
     (cadr-tui::terminal-renderer-previous-width renderer) 20
     (cadr-tui::terminal-renderer-previous-height renderer) 4
     (cadr-tui::terminal-renderer-hardware-cursor-row renderer) 1
     (cadr-tui::terminal-renderer-max-lines-rendered renderer) 2
     (cadr-tui::terminal-renderer-previous-viewport-top renderer) 0)
    (cadr-tui:renderer-enter-alt-screen-live renderer)
    (is (cadr-tui::terminal-renderer-alt-screen-p renderer))
    (is (cadr-tui::terminal-renderer-alt-screen-active-p renderer))
    (is (null (cadr-tui::terminal-renderer-previous-lines renderer)))
    (is (alt-write-containing-p terminal (format nil "~C[?1049h" #\Escape)))
    (cadr-tui:renderer-exit-alt-screen-live renderer)
    (is (not (cadr-tui::terminal-renderer-alt-screen-p renderer)))
    (is (not (cadr-tui::terminal-renderer-alt-screen-active-p renderer)))
    ;; preserveScreen exit: 1049l and show-cursor, no document replay.
    (is (alt-write-containing-p terminal (format nil "~C[?1049l" #\Escape)))
    (is (alt-write-containing-p terminal (format nil "~C[?25h" #\Escape)))
    ;; The stashed main-screen state is restored.
    (is (equal (list "alpha" "beta")
               (cadr-tui::terminal-renderer-previous-lines renderer)))
    (is (= 20 (cadr-tui::terminal-renderer-previous-width renderer)))
    (is (= 1 (cadr-tui::terminal-renderer-hardware-cursor-row renderer)))
    (is (cadr-tui::terminal-renderer-invalid-p renderer))))

(test renderer-multi-click-selects-word-then-line
  ;; pi@ecac0a9c4 tui-alt-screen.ts:644-713 — double click selects the
  ;; word under the cursor, triple click the line, and the streak
  ;; cycles back to a character selection on the fourth click.
  (let ((renderer
          (cadr-tui:make-terminal-renderer
           (make-alt-recording-terminal) :alt-p t)))
    (setf
     (cadr-tui::terminal-renderer-last-document renderer)
     (list "hello world, lisp"))
    (labels ((press (row col)
               (cadr-tui::renderer-note-click
                renderer row
                (cadr-tui::selection-word-range
                 (cadr-tui::renderer-selection-source-line
                  renderer row)
                 col))))
      ;; segmentation: word run, space run, punctuation run, word run
      (is (equal '(0 . 5)
                 (cadr-tui::selection-word-range
                  "hello world, lisp" 2)))
      (is (equal '(5 . 6)
                 (cadr-tui::selection-word-range
                  "hello world, lisp" 5)))
      (is (equal '(11 . 12)
                 (cadr-tui::selection-word-range
                  "hello world, lisp" 11)))
      (is (null
           (cadr-tui::selection-word-range "hello" 5)))
      ;; streak: same word inside the window cycles 1 2 3 1
      (is (= 1 (press 0 2)))
      (is (= 2 (press 0 2)))
      (is (= 3 (press 0 2)))
      (is (= 1 (press 0 2)))
      ;; a click on a different word restarts the streak
      (is (= 1 (press 0 7)))
      ;; a click outside any word resets
      (is (= 1 (press 0 5))))))

(test renderer-word-and-line-ranges-feed-selection
  (let ((renderer
          (cadr-tui:make-terminal-renderer
           (make-alt-recording-terminal) :alt-p t)))
    (setf
     (cadr-tui::terminal-renderer-last-document renderer)
     (list "hello world"))
    (is (equal (cons 0 11)
               (cdr
                (cadr-tui::renderer-line-selection-range
                 renderer 0))))
    (is (equal (cons 0 0)
               (car
                (cadr-tui::renderer-line-selection-range
                 renderer 0))))))

(test renderer-flash-composites-and-expires
  ;; pi@ecac0a9c4 components/alt-screen-flash.ts — flashes render as
  ;; reverse-video padded messages and expire after their duration.
  (let ((renderer
          (cadr-tui:make-terminal-renderer
           (make-alt-recording-terminal) :alt-p t)))
    (cadr-tui:renderer-flash renderer "Copied!")
    (let ((lines
            (cadr-tui::renderer-live-flash-lines renderer 40)))
      (is (= 1 (length lines)))
      (is (search " Copied! " (first lines)))
      (is (search (format nil "~C[7m" #\Escape) (first lines))))
    ;; force expiry by backdating the deadline
    (setf
     (third
      (first
       (cadr-tui::terminal-renderer-flash-entries renderer)))
     0.0d0)
    (is (null
         (cadr-tui::renderer-live-flash-lines renderer 40)))))

(test alt-screen-search-overlay-literals-match-baseline
  ;; Baseline packages/tui/src/alt-screen-search.ts:143-149
  ;; (pi@ecac0a9c4). AltScreenSearchComponent.render composes the
  ;; overlay title at runtime, so the extractor never sees these
  ;; literals. Expected strings are copied from the TypeScript, not
  ;; from cadr.
  (let* ((empty (cadr-tui::render-search-bar "" 40 0 0))
         (miss (cadr-tui::render-search-bar "q" 40 0 0))
         (hit (cadr-tui::render-search-bar "q" 40 0 3))
         (empty-title
           (cadr-tui::strip-terminal-sequences (first empty)))
         (miss-title
           (cadr-tui::strip-terminal-sequences (first miss)))
         (hit-title
           (cadr-tui::strip-terminal-sequences (first hit))))
    (is (= 2 (length empty)))
    (is (eql 0 (search " Find transcript" empty-title)))
    (is (not (search "No matches " empty-title)))
    (is (eql 0 (search " Find transcript" miss-title)))
    (is (search "No matches " miss-title))
    (is (eql 0 (search " Find transcript" hit-title)))
    (is (search "1/3 " hit-title))
    (is (not (search "No matches " hit-title)))))

(test selection-word-range-treats-hyphen-and-slash-as-joiners
  (is (equal '(0 . 7)
             (cadr-tui::selection-word-range "foo-bar" 3)))
  (is (equal '(0 . 3)
             (cadr-tui::selection-word-range "a/b" 0))))
