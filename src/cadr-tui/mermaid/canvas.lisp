;;; grok-mermaid@0.2.2 dist/canvas.js:1-365 - direct port.
;;;
;;; Copyright 2023-2026 SpaceXAI
;;; Copyright 2026 Alexey Zaytsev
;;; Licensed under the Apache License, Version 2.0.
;;; This file is a Common Lisp port by the cadr authors; it is a
;;; modified version of the original work.  License text:
;;; docs/third-party/grok-mermaid-LICENSE.txt
;;;
;;; The edge-mask grid.  Edges accumulate direction bits rather than glyphs so
;;; that crossings and junctions resolve correctly whatever order they are
;;; drawn in; gm-canvas-finalize-mask turns the accumulated bits into
;;; characters at the end.  `occupied` marks cells claimed by a box, which
;;; edge bits must not overwrite.

(in-package #:cadr-tui)

;;; Sentinel occupying the trailing column of a wide glyph.  Never emitted:
;;; the line builder skips it so a CJK character claims two cells of layout
;;; but contributes one character of output.
(defparameter +gm-cont+ (make-string 1 :initial-element #\Null))

;;; Connection direction bits, combined into a box-drawing glyph by
;;; gm-mask-char.
(defconstant +gm-u+ 1)
(defconstant +gm-d+ 2)
(defconstant +gm-l+ 4)
(defconstant +gm-r+ 8)

;;; Line styles, tracked per cell so crossing edges keep their own stroke.
(defconstant +gm-sty-dot+ 1)
(defconstant +gm-sty-thick+ 2)
(defconstant +gm-sty-solid+ 4)

(defstruct (gm-canvas (:constructor gm-make-canvas (w h)))
  (w w :type fixnum)
  (h h :type fixnum)
  (ch (make-array (* w h) :initial-element " "))
  (cls (make-array (* w h) :initial-element "none"))
  (mask (make-array (* w h) :element-type '(unsigned-byte 8) :initial-element 0))
  (style (make-array (* w h) :element-type '(unsigned-byte 8) :initial-element 0))
  (occupied (make-array (* w h) :element-type '(unsigned-byte 8) :initial-element 0))
  (cur-style +gm-sty-solid+ :type (unsigned-byte 8)))

(defun gm-canvas-idx (canvas x y)
  (+ (* y (gm-canvas-w canvas)) x))

(defun gm-canvas-set (canvas x y c cls)
  (when (or (minusp x) (minusp y)
            (>= x (gm-canvas-w canvas)) (>= y (gm-canvas-h canvas)))
    (return-from gm-canvas-set nil))
  (let ((i (gm-canvas-idx canvas x y)))
    (setf (aref (gm-canvas-ch canvas) i) c)
    (setf (aref (gm-canvas-cls canvas) i) cls)))

;;; Accumulate direction bits on a free cell.  `cls` is the class to claim the
;;; cell for; `border` cells are never reclassified, so a connector meeting a
;;; box keeps the box's styling.
(defun gm-canvas-add-bits (canvas x y bits &optional (cls "edge"))
  (when (or (minusp x) (minusp y)
            (>= x (gm-canvas-w canvas)) (>= y (gm-canvas-h canvas)))
    (return-from gm-canvas-add-bits nil))
  (let ((i (gm-canvas-idx canvas x y)))
    (when (plusp (aref (gm-canvas-occupied canvas) i))
      (return-from gm-canvas-add-bits nil))
    (setf (aref (gm-canvas-mask canvas) i)
          (logior (aref (gm-canvas-mask canvas) i) bits))
    (setf (aref (gm-canvas-style canvas) i)
          (logior (aref (gm-canvas-style canvas) i)
                  (gm-canvas-cur-style canvas)))
    (unless (string= (aref (gm-canvas-cls canvas) i) "border")
      (setf (aref (gm-canvas-cls canvas) i) cls))))

;;; Stamp a finished sub-canvas (a subgraph frame's contents) at an offset.
(defun gm-canvas-blit (canvas sub ox oy)
  (let ((w (gm-canvas-w canvas)) (h (gm-canvas-h canvas)))
    (loop for sy from 0 below (gm-canvas-h sub)
          do (loop for sx from 0 below (gm-canvas-w sub)
                   do (let ((x (+ ox sx)) (y (+ oy sy)))
                        (unless (or (< x 0) (< y 0) (>= x w) (>= y h))
                          (let* ((si (gm-canvas-idx sub sx sy))
                                 (di (gm-canvas-idx canvas x y)))
                            (setf (aref (gm-canvas-ch canvas) di) (aref (gm-canvas-ch sub) si))
                            (setf (aref (gm-canvas-cls canvas) di) (aref (gm-canvas-cls sub) si))
                            (setf (aref (gm-canvas-style canvas) di) (aref (gm-canvas-style sub) si))
                            (setf (aref (gm-canvas-occupied canvas) di) 1))))))))

;;; Add direction bits even to an occupied cell, so an edge can meet a border.
(defun gm-canvas-junction (canvas x y bits)
  (when (or (minusp x) (minusp y)
            (>= x (gm-canvas-w canvas)) (>= y (gm-canvas-h canvas)))
    (return-from gm-canvas-junction nil))
  (let ((i (gm-canvas-idx canvas x y)))
    (setf (aref (gm-canvas-mask canvas) i)
          (logior (aref (gm-canvas-mask canvas) i) bits))
    (unless (string= (aref (gm-canvas-cls canvas) i) "border")
      (setf (aref (gm-canvas-cls canvas) i) "edge"))))

(defun gm-canvas-seg-v (canvas x y0 y1)
  (let ((a (min y0 y1)) (b (max y0 y1)))
    (loop for y from a to b
          do (let ((bits 0))
               (when (> y a) (setf bits (logior bits +gm-u+)))
               (when (< y b) (setf bits (logior bits +gm-d+)))
               (gm-canvas-add-bits canvas x y bits)))))

(defun gm-canvas-seg-h (canvas y x0 x1)
  (let ((a (min x0 x1)) (b (max x0 x1)))
    (loop for x from a to b
          do (let ((bits 0))
               (when (> x a) (setf bits (logior bits +gm-l+)))
               (when (< x b) (setf bits (logior bits +gm-r+)))
               (gm-canvas-add-bits canvas x y bits)))))

;;; Box-drawing glyph transforms: dotted/thick stroke variants and the
;;; vertical/horizontal mirror tables used by the flip routines below.
(defparameter +gm-dotted-map+
  (list (cons #\─ #\╌) (cons #\│ #\╎)))

(defparameter +gm-thick-map+
  (list (cons #\─ #\━) (cons #\│ #\┃)
        (cons #\┌ #\┏) (cons #\┐ #\┓)
        (cons #\└ #\┗) (cons #\┘ #\┛)
        (cons #\├ #\┣) (cons #\┤ #\┫)
        (cons #\┬ #\┳) (cons #\┴ #\┻)
        (cons #\┼ #\╋)))

(defparameter +gm-flip-v-map+
  (list (cons #\┌ #\└) (cons #\└ #\┌)
        (cons #\┐ #\┘) (cons #\┘ #\┐)
        (cons #\┏ #\┗) (cons #\┗ #\┏)
        (cons #\┓ #\┛) (cons #\┛ #\┓)
        (cons #\╭ #\╰) (cons #\╰ #\╭)
        (cons #\╮ #\╯) (cons #\╯ #\╮)
        (cons #\┬ #\┴) (cons #\┴ #\┬)
        (cons #\┳ #\┻) (cons #\┻ #\┳)
        (cons #\▼ #\▲) (cons #\▲ #\▼)
        (cons #\▽ #\△) (cons #\△ #\▽)))

(defparameter +gm-flip-h-map+
  (list (cons #\┌ #\┐) (cons #\┐ #\┌)
        (cons #\└ #\┘) (cons #\┘ #\└)
        (cons #\┏ #\┓) (cons #\┓ #\┏)
        (cons #\┗ #\┛) (cons #\┛ #\┗)
        (cons #\╭ #\╮) (cons #\╮ #\╭)
        (cons #\╰ #\╯) (cons #\╯ #\╰)
        (cons #\├ #\┤) (cons #\┤ #\├)
        (cons #\┣ #\┫) (cons #\┫ #\┣)
        (cons #\▶ #\◄) (cons #\◄ #\▶)
        (cons #\▷ #\◁) (cons #\◁ #\▷)))

(defun gm-map-char (map c)
  (let ((entry (assoc c map)))
    (if entry (cdr entry) c)))

(defun gm-dotted-char (c) (gm-map-char +gm-dotted-map+ c))
(defun gm-thick-char (c) (gm-map-char +gm-thick-map+ c))

;;; Canvas cells hold grapheme-cluster strings, so the flip tables apply to
;;; single-char cells and leave multi-char clusters (CJK/ZWJ) untouched.
(defun gm-flip-glyph-v (s)
  (if (= 1 (length s))
      (string (gm-map-char +gm-flip-v-map+ (char s 0)))
      s))

(defun gm-flip-glyph-h (s)
  (if (= 1 (length s))
      (string (gm-map-char +gm-flip-h-map+ (char s 0)))
      s))

;;; Turn accumulated direction bits into a box-drawing glyph.
(defun gm-mask-char (mask)
  (case mask
    (0 #\Space)
    ((1 2 3) #\│)
    ((4 8 12) #\─)
    (10 #\┌)
    (6 #\┐)
    (9 #\└)
    (5 #\┘)
    (11 #\├)
    (7 #\┤)
    (14 #\┬)
    (13 #\┴)
    (t #\┼)))

;;; Resolve accumulated direction bits into glyphs, honouring line style.
(defun gm-canvas-finalize-mask (canvas)
  (let ((chv (gm-canvas-ch canvas)))
    (dotimes (i (length chv))
      (when (and (plusp (aref (gm-canvas-mask canvas) i))
                 (string= (aref chv i) " "))
        (let ((c (gm-mask-char (aref (gm-canvas-mask canvas) i)))
              (style (aref (gm-canvas-style canvas) i)))
          (setf (aref chv i)
                (string (cond ((= style +gm-sty-dot+) (gm-dotted-char c))
                              ((= style +gm-sty-thick+) (gm-thick-char c))
                              (t c)))))))))

;;; Mirror top-to-bottom for BT.  Rows reorder but within-row text does not,
;;; so labels stay readable; box-drawing glyphs flip to match.
(defun gm-canvas-flip-vertical (canvas)
  (let ((chv (gm-canvas-ch canvas)) (clsv (gm-canvas-cls canvas)))
    (dotimes (y (floor (gm-canvas-h canvas) 2))
      (let ((y2 (1- (- (gm-canvas-h canvas) y))))
        (dotimes (x (gm-canvas-w canvas))
          (let ((i (gm-canvas-idx canvas x y))
                (j (gm-canvas-idx canvas x y2)))
            (rotatef (aref chv i) (aref chv j))
            (rotatef (aref clsv i) (aref clsv j))))))
    (dotimes (i (length chv))
      (setf (aref chv i) (gm-flip-glyph-v (aref chv i))))))

;;; Mirror left-to-right for RL.  Mirroring reverses each row, so after
;;; flipping glyphs each text/label run is reversed back to reading order.
(defun gm-reverse-array-range (arr start end)
  (loop for i from start
        for j from (1- end) downto start
        while (< i j)
        do (rotatef (aref arr i) (aref arr j))))

(defun gm-canvas-flip-horizontal (canvas)
  (let ((chv (gm-canvas-ch canvas)) (clsv (gm-canvas-cls canvas)))
    (dotimes (y (gm-canvas-h canvas))
      (dotimes (x (floor (gm-canvas-w canvas) 2))
        (let* ((x2 (1- (- (gm-canvas-w canvas) x)))
              (i (gm-canvas-idx canvas x y))
              (j (gm-canvas-idx canvas x2 y)))
          (rotatef (aref chv i) (aref chv j))
          (rotatef (aref clsv i) (aref clsv j)))))
    (dotimes (i (length chv))
      (setf (aref chv i) (gm-flip-glyph-h (aref chv i))))
    (dotimes (y (gm-canvas-h canvas))
      (let ((x 0))
        (loop while (< x (gm-canvas-w canvas))
              do (let ((cls (aref clsv (gm-canvas-idx canvas x y))))
                   (if (or (string= cls "text") (string= cls "edgeLabel"))
                       (let ((start (gm-canvas-idx canvas x y)))
                         (loop while (and (< x (gm-canvas-w canvas))
                                          (string= (aref clsv (gm-canvas-idx canvas x y)) cls))
                               do (incf x))
                         (let ((end (gm-canvas-idx canvas x y)))
                           (gm-reverse-array-range chv start end)))
                       (incf x))))))))

(defun gm-rstrip-ascii-spaces (s)
  (let ((end (length s)))
    (loop while (and (plusp end) (char= (char s (1- end)) #\Space))
          do (decf end))
    (subseq s 0 end)))

;;; Group each row into runs of one class, dropping wide-glyph continuations.
;;; Returns (values plain styled width): plain rows as strings with trailing
;;; ASCII spaces trimmed, styled rows as lists of (text class) pairs, and the
;;; widest painted column.
(defun gm-canvas-to-lines (canvas)
  (let ((chv (gm-canvas-ch canvas)) (clsv (gm-canvas-cls canvas))
        (plain nil) (styled nil) (width 0))
    (dotimes (y (gm-canvas-h canvas))
      ;; A trailing CONT counts as painted: it is the second cell of a wide
      ;; glyph, so the row really does reach that column.
      (let ((last 0))
        (loop for x from (1- (gm-canvas-w canvas)) downto 0
              do (unless (string= (aref chv (gm-canvas-idx canvas x y)) " ")
                   (setf last (1+ x))
                   (return)))
        (setf width (max width last))
        (let ((cells nil)
              (row-plain (make-string-output-stream)))
          (loop for x from 0 below last
                do (let* ((i (gm-canvas-idx canvas x y))
                          (c (aref chv i)))
                     (unless (string= c +gm-cont+)
                       (push (cons c (aref clsv i)) cells))))
          (setf cells (nreverse cells))
          (let ((spans nil)
                (run (make-string-output-stream))
                (run-cls "none")
                (run-n 0))
            (dolist (cell cells)
              (let ((c (car cell)) (cls (cdr cell)))
                (write-string c row-plain)
                (unless (string= cls run-cls)
                  (when (plusp run-n)
                    (push (list (get-output-stream-string run) run-cls) spans)
                    (setf run-n 0))
                  (setf run-cls cls))
                (write-string c run)
                (incf run-n)))
            (when (plusp run-n)
              (push (list (get-output-stream-string run) run-cls) spans))
            (push (nreverse spans) styled))
          (push (gm-rstrip-ascii-spaces (get-output-stream-string row-plain)) plain))))
    (setf plain (nreverse plain))
    (setf styled (nreverse styled))
    (let ((first 0) (end (length plain)))
      (loop while (and (< first end) (string= (nth first plain) ""))
            do (incf first))
      (loop while (and (> end first) (string= (nth (1- end) plain) ""))
            do (decf end))
      (values (subseq plain first end)
              (subseq styled first end)
              width))))

;;; Paint text at x, y, one grapheme cluster per cell.  A wide cluster claims
;;; a second cell marked with +gm-cont+ so the line builder emits one
;;; character for it rather than a stray space.
(defun gm-draw-text (canvas text x y cls)
  (let ((cur x))
    (dolist (pair (gm-measured text))
      (let ((cluster (car pair)) (cw (cdr pair)))
        (when (plusp cw)
          (gm-canvas-set canvas cur y cluster cls)
          (loop for k from 1 below cw
                do (gm-canvas-set canvas (+ cur k) y +gm-cont+ cls))
          (incf cur cw))))))

;;; Paint text at x, y, clearing any edge bits underneath first.  Used where
;;; text sits on top of a drawn line (sequence messages, dividers,
;;; compartment rows) and must win over it.
(defun gm-draw-text-over-edges (canvas text x y cls)
  (let ((cur x))
    (dolist (pair (gm-measured text))
      (let ((cluster (car pair)) (cw (cdr pair)))
        (when (plusp cw)
          (loop for k from 0 below cw
                do (let ((cx (+ cur k)))
                     (when (and (< cx (gm-canvas-w canvas))
                                (< y (gm-canvas-h canvas)))
                       (setf (aref (gm-canvas-mask canvas)
                                   (gm-canvas-idx canvas cx y))
                             0))
                     (gm-canvas-set canvas cx y
                                    (if (zerop k) cluster +gm-cont+)
                                    cls)))
          (incf cur cw))))))
