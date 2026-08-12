;;; grok-mermaid@0.2.2 dist/layout-seq.js:1-193 - direct port.
;;;
;;; Copyright 2023-2026 SpaceXAI
;;; Copyright 2026 Alexey Zaytsev
;;; Licensed under the Apache License, Version 2.0.
;;; This file is a Common Lisp port by the cadr authors; it is a
;;; modified version of the original work.  License text:
;;; docs/third-party/grok-mermaid-LICENSE.txt
;;;
;;; Sequence diagram layout.  Participants get one column each, with lifelines
;;; running the full height and a box repeated at top and bottom.  Column gaps
;;; are solved from the widest thing that has to fit between any two columns -
;;; a message label, a note, a self-message stub - then items stack down the
;;; canvas in source order.

(in-package #:cadr-tui)

(defparameter +gm-seq-pad+ 1)
;;; Minimum columns between adjacent lifelines.
(defparameter +gm-seq-gap+ 5)

;;; Where a note box sits, given the lifeline positions.  Returns (values x w).
(defun gm-seq-note-geometry (xs anchor text-w)
  (let ((kind (getf anchor :kind)))
    (if (string= kind "over")
        (let* ((center (gm-half (+ (aref xs (getf anchor :from))
                                   (aref xs (getf anchor :to)))))
               (w (max (+ (- (aref xs (getf anchor :to))
                             (aref xs (getf anchor :from)))
                          5)
                       (+ text-w (* 2 +gm-seq-pad+) 2))))
          (values (gm-sat center (gm-half w)) w))
        (let ((w (+ text-w (* 2 +gm-seq-pad+) 2)))
          (if (string= kind "left")
              (values (gm-sat (aref xs (getf anchor :at)) (1+ w)) w)
              (values (+ (aref xs (getf anchor :at)) 2) w))))))

(defun gm-seq-item-text-w (text)
  (if (null text) 0 (gm-string-width text)))

(defun gm-layout-sequence (seq)
  (let* ((n (length (gm-seq-labels seq)))
         (labels (map 'vector
                      (lambda (l) (gm-fit-label l +gm-wrap-width+))
                      (gm-seq-labels seq)))
         (box-w (map 'vector
                     (lambda (l) (+ (max 1 (gm-string-width l)) (* 2 +gm-seq-pad+) 2))
                     labels))
         (box-h 3)
         (gaps (make-array (gm-sat n 1) :element-type 'fixnum :initial-element 0)))
    (dotimes (i (length gaps))
      (setf (aref gaps i)
            (max +gm-seq-gap+
                 (+ (nth-value 0 (ceiling (aref box-w i) 2))
                    (nth-value 0 (ceiling (aref box-w (1+ i)) 2))
                    1))))
    ;; Each requirement is "columns l..r together need at least `need` cells".
    (let ((reqs nil))
      (loop for item across (gm-seq-items seq)
            do (let ((kind (getf item :kind)))
                 (cond ((string= kind "message")
                        (let ((tw (gm-seq-item-text-w (getf item :text)))
                              (from (getf item :from))
                              (to (getf item :to)))
                          (if (/= from to)
                              (push (list (min from to) (max from to)
                                          (max (+ tw 2) 4))
                                    reqs)
                              (when (< (1+ from) n)
                                (push (list from (1+ from) (+ 5 tw 2)) reqs)))))
                       ((string= kind "note")
                        (let* ((tw (gm-string-width (getf item :text)))
                               (a (getf item :anchor))
                               (akind (getf a :kind)))
                          (cond ((and (string= akind "over")
                                      (< (getf a :from) (getf a :to)))
                                 (push (list (getf a :from) (getf a :to)
                                             (gm-sat tw 1))
                                       reqs))
                                ((string= akind "over")
                                 (let ((need (+ (nth-value 0 (ceiling (+ tw 4) 2))
                                                2)))
                                   (when (plusp (getf a :from))
                                     (push (list (1- (getf a :from))
                                                 (getf a :from) need)
                                           reqs))
                                   (when (< (1+ (getf a :from)) n)
                                     (push (list (getf a :from)
                                                 (1+ (getf a :from)) need)
                                           reqs))))
                                ((and (string= akind "left")
                                      (plusp (getf a :at)))
                                 (push (list (1- (getf a :at)) (getf a :at)
                                             (+ tw 7))
                                       reqs))
                                ((and (string= akind "right")
                                      (< (1+ (getf a :at)) n))
                                 (push (list (getf a :at) (1+ (getf a :at))
                                             (+ tw 7))
                                       reqs))))))))
      ;; Narrowest spans first, so a wide requirement absorbs what they
      ;; already gave.  JS Array#sort is stable; stable-sort keeps equal spans
      ;; in source order so the gap adjustment order matches.
      (setf reqs (stable-sort reqs
                              (lambda (a b)
                                (< (- (second a) (first a))
                                   (- (second b) (first b))))))
      (dolist (req reqs)
        (let ((l (first req)) (r (second req)) (need (third req))
              (cur 0))
          (loop for i from l below r
                do (incf cur (aref gaps i)))
          (when (< cur need)
            (incf (aref gaps (1- r)) (- need cur))))))
    (let ((xs (make-array n :element-type 'fixnum :initial-element 0)))
      (setf (aref xs 0) (gm-half (aref box-w 0)))
      (loop for i from 1 below n
            do (setf (aref xs i)
                     (+ (aref xs (1- i)) (aref gaps (1- i)))))
      (let ((canvas-w (+ (aref xs (1- n))
                         (nth-value 0 (ceiling (aref box-w (1- n)) 2))
                         1)))
        (loop for item across (gm-seq-items seq)
              do (let ((kind (getf item :kind)))
                   (cond ((and (string= kind "message")
                               (= (getf item :from) (getf item :to)))
                          (setf canvas-w
                                (max canvas-w
                                     (+ (aref xs (getf item :from)) 5
                                        (gm-seq-item-text-w (getf item :text))
                                        1))))
                         ((string= kind "note")
                          (multiple-value-bind (gx gw)
                              (gm-seq-note-geometry
                               xs (getf item :anchor)
                               (gm-string-width (getf item :text)))
                            (setf canvas-w (max canvas-w (+ gx gw 1)))))
                         ((string= kind "divider")
                          (setf canvas-w
                                (max canvas-w
                                     (+ (gm-string-width (getf item :text)) 4)))))))
        (let ((rows (make-array (length (gm-seq-items seq))
                                :element-type 'fixnum
                                :initial-element 0))
              (y (+ box-h 1)))
          (loop for k from 0 below (length rows)
                do (setf (aref rows k) y)
                   (incf y (gm-seq-row-height (aref (gm-seq-items seq) k))))
          (let ((bottom-top y)
                (canvas-h (+ y box-h)))
            (when (> (* canvas-w canvas-h) +gm-max-canvas-cells+)
              (return-from gm-layout-sequence nil))
            (let ((canvas (gm-make-canvas canvas-w canvas-h)))
              (dotimes (i n)
                (dolist (by (list 0 bottom-top))
                  (gm-draw-box canvas
                               (gm-seq-box (gm-sat (aref xs i)
                                                   (gm-half (aref box-w i)))
                                           by (aref box-w i) box-h)
                               (list (aref labels i))
                               "rect")))
              (loop for k from 0 below (length (gm-seq-items seq))
                    for item = (aref (gm-seq-items seq) k)
                    when (string= (getf item :kind) "note")
                      do (multiple-value-bind (gx gw)
                             (gm-seq-note-geometry
                              xs (getf item :anchor)
                              (gm-string-width (getf item :text)))
                           (gm-draw-box canvas
                                        (gm-seq-box gx (aref rows k) gw 3)
                                        (list (getf item :text))
                                        "rect")))
              (dotimes (i n)
                (let ((x (aref xs i)))
                  (gm-canvas-junction canvas x (1- box-h) +gm-d+)
                  (gm-canvas-seg-v canvas x box-h (1- bottom-top))
                  (gm-canvas-junction canvas x bottom-top +gm-u+)))
              (loop for k from 0 below (length (gm-seq-items seq))
                    for item = (aref (gm-seq-items seq) k)
                    do (let ((r (aref rows k)))
                         (cond ((string= (getf item :kind) "message")
                                (gm-seq-draw-message canvas item xs r))
                               ((string= (getf item :kind) "divider")
                                (gm-seq-draw-divider canvas (getf item :text)
                                                     r canvas-w)))))
              (gm-canvas-finalize-mask canvas)
              canvas)))))))

(defun gm-seq-row-height (item)
  (let ((kind (getf item :kind)))
    (cond ((string= kind "note") 4)
          ((string= kind "divider") 2)
          ((= (getf item :from) (getf item :to)) 4)
          ((null (getf item :text)) 2)
          (t 3))))

;;; Geometry for a box drawn by position and size; ranks are irrelevant here.
(defun gm-seq-box (x y w h)
  (list :x x :y y :w w :h h
        :cx (+ x (gm-half w))
        :cy (1+ y)
        :rank 0))

(defun gm-seq-draw-message (canvas item xs r)
  (let ((line-ch (if (getf item :dashed) "╌" "─")))
    (if (= (getf item :from) (getf item :to))
        ;; A stub that leaves the lifeline and returns two rows down.
        (let ((x (aref xs (getf item :from))))
          (gm-canvas-junction canvas x r +gm-r+)
          (gm-canvas-set canvas (+ x 1) r line-ch "edge")
          (gm-canvas-set canvas (+ x 2) r line-ch "edge")
          (gm-canvas-set canvas (+ x 3) r "╮" "edge")
          (gm-canvas-set canvas (+ x 3) (+ r 1) "│" "edge")
          (gm-canvas-set canvas (+ x 1) (+ r 2)
                         (if (string= (getf item :head) "cross") "×" "◄")
                         "edge")
          (gm-canvas-set canvas (+ x 2) (+ r 2) line-ch "edge")
          (gm-canvas-set canvas (+ x 3) (+ r 2) "╯" "edge")
          (when (getf item :text)
            (gm-draw-text-over-edges canvas (getf item :text)
                                     (+ x 5) (+ r 1) "text")))
        (let* ((x0 (aref xs (getf item :from)))
               (x1 (aref xs (getf item :to)))
               (rightward (> x1 x0))
               ;; A labelled message writes its text on `r` and draws the
               ;; arrow below it.
               (arrow-row (if (getf item :text) (+ r 1) r))
               (lo (min x0 x1))
               (hi (max x0 x1)))
          (gm-canvas-junction canvas x0 arrow-row
                              (if rightward +gm-r+ +gm-l+))
          (loop for x from (+ lo 1) below hi
                do (gm-canvas-set canvas x arrow-row line-ch "edge"))
          (let ((head-ch (if (string= (getf item :head) "cross")
                             "×"
                             (if rightward "▶" "◄"))))
            (gm-canvas-set canvas (if rightward (- x1 1) (+ x1 1))
                           arrow-row head-ch "edge"))
          (when (getf item :text)
            (let* ((span (- hi lo 1))
                   (text (gm-fit-label (getf item :text) (max 1 span))))
              (gm-draw-text-over-edges
               canvas text
               (+ lo 1 (gm-half (gm-sat span (gm-string-width text))))
               r "text")))))))

;;; A full-width rule labelling a `loop` / `alt` / `opt` block boundary.
(defun gm-seq-draw-divider (canvas text r canvas-w)
  (dotimes (x canvas-w)
    (gm-canvas-set canvas x r "─" "edge"))
  (gm-draw-text-over-edges
   canvas
   (format nil " ~A " (gm-fit-label text (gm-sat canvas-w 4)))
   2 r "edgeLabel"))
