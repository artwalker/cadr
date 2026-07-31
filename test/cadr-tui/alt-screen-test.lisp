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
      (format nil "~C[5$" #\Escape)))
    (alt-render renderer lines)
    (is (= 1
           (cadr-tui:renderer-viewport-top
            renderer)))
    (is
     (cadr-tui:renderer-handle-input
      renderer
      (format nil "~C[1;5F" #\Escape)))
    (alt-render renderer lines)
    (is (= 4
           (cadr-tui:renderer-viewport-top
            renderer)))))

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
