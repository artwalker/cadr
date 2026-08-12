;;; grok-mermaid@0.2.2 dist/layout.js:1-880 - direct port.
;;;
;;; Copyright 2023-2026 SpaceXAI
;;; Copyright 2026 Alexey Zaytsev
;;; Licensed under the Apache License, Version 2.0.
;;; This file is a Common Lisp port by the cadr authors; it is a
;;; modified version of the original work.  License text:
;;; docs/third-party/grok-mermaid-LICENSE.txt
;;;
;;; Graph layout: rank, order, place, route, draw.  Follows the Sugiyama
;;; outline - assign ranks along the flow axis, reorder within ranks to cut
;;; crossings, then relax positions on the cross axis so chains stay straight.
;;; Edges between adjacent ranks share horizontal "bus" rows; everything else
;;; is routed around the diagram through vertical "lanes".
;;;
;;; BT and RL reuse the TD/LR layouts and flip the finished canvas, so text
;;; never ends up mirrored.

(in-package #:cadr-tui)

(declaim (ftype (function *) gm-compute-ranks gm-order-ranks gm-count-crossings
                 gm-assign-positions gm-assign-tracks gm-place-td gm-place-lr
                 gm-layout-canvas gm-layout-grouped gm-build-scope
                 gm-draw-box gm-draw-class-box gm-draw-frame
                 gm-place-label gm-route-forward gm-route-self
                 gm-route-back gm-route-forward-lr gm-route-back-lr))

;;; Cells of padding between a box border and its text.
(defconstant +gm-pad+ 1)
;;; Minimum horizontal / vertical space between boxes.
(defconstant +gm-gap-x+ 3)
(defconstant +gm-gap-y+ 2)
;;; Refuse to allocate a canvas larger than this many cells.
(defconstant +gm-max-canvas-cells+ (ash 1 21))

;;; Saturating subtraction; Rust's usize arithmetic never goes negative.
(defun gm-sat (a b)
  (max 0 (- a b)))

(defun gm-half (n)
  (floor n 2))

;;; ---------------------------------------------------------------- ranking
;;; Longest-path ranking over the graph's DAG.
;;;
;;; Back edges (those closing a cycle) are excluded by a DFS colouring pass,
;;; so A --> B --> C --> A still ranks 0, 1, 2 rather than diverging.
(defun gm-compute-ranks (graph)
  (let* ((n (gm-graph-node-count graph))
         (children (make-array n))
         (indeg (make-array n :initial-element 0)))
    (dotimes (i n)
      (setf (aref children i) (make-array 0 :adjustable t :fill-pointer 0)))
    (loop for e across (gm-graph-edges graph)
          do (let ((from (getf e :from)) (to (getf e :to)))
               (when (/= from to)
                 (vector-push-extend to (aref children from))
                 (incf (aref indeg to)))))
    (let ((color (make-array n :element-type '(unsigned-byte 8) :initial-element 0))
          (dag (make-array n))
          (order nil))
      (dotimes (i n)
        (setf (aref dag i) (make-array 0 :adjustable t :fill-pointer 0)))
      ;; Iterative DFS recording postorder and skipping edges back into the
      ;; stack.
      (labels ((dfs-dag (start)
                 (let ((stack (list (cons start 0))))
                   (setf (aref color start) 1)
                   (loop while stack
                         do (let* ((frame (car stack))
                                   (u (car frame))
                                   (i (cdr frame)))
                              (if (< i (length (aref children u)))
                                  (let ((v (aref (aref children u) i)))
                                    (setf (cdr frame) (1+ i))
                                    (if (= (aref color v) 1)
                                        nil   ; grey: a back edge, skip it
                                        (progn
                                          (vector-push-extend v (aref dag u))
                                          (when (zerop (aref color v))
                                            (setf (aref color v) 1)
                                            (push (cons v 0) stack)))))
                                  (progn
                                    (setf (aref color u) 2)
                                    (push u order)
                                    (pop stack))))))))
        ;; Roots first so ranks grow from natural entry points, then any
        ;; leftovers.
        (let ((roots (loop for i from 0 below n
                           when (zerop (aref indeg i)) collect i)))
          (dolist (start (append roots (loop for i from 0 below n collect i)))
            (when (zerop (aref color start))
              (dfs-dag start))))
        ;; Lisp `order` is newest-first, i.e. the reverse of the JS array, so
        ;; walking it head-to-tail matches JS iterating from the end.
        (let ((rank (make-array n :initial-element 0)))
          (dolist (u order)
            (loop for v across (aref dag u)
                  do (setf (aref rank v)
                           (max (aref rank v) (1+ (aref rank u))))))
          rank)))))

;;; Count crossings between edges joining adjacent ranks.
(defun gm-count-crossings (edges ranks pos)
  (let ((adjacent nil))
    (loop for e across edges
          do (let ((from (getf e :from)) (to (getf e :to)))
               (when (and (/= from to)
                          (= (aref ranks to) (1+ (aref ranks from))))
                 (push (list (aref ranks from)
                             (aref pos from)
                             (aref pos to))
                       adjacent))))
    (setf adjacent (nreverse adjacent))
    (let ((crossings 0))
      (loop for a in adjacent
            for i from 0
            do (loop for b in (nthcdr (1+ i) adjacent)
                     do (when (and (= (first a) (first b))
                                   (or (and (< (second a) (second b))
                                            (> (third a) (third b)))
                                       (and (> (second a) (second b))
                                            (< (third a) (third b)))))
                          (incf crossings))))
      crossings)))

;;; Stable barycenter sort of one rank against a neighbour table.
(defun gm-sort-by-barycenter (row neigh pos)
  (let ((keyed (loop for v across row
                     collect (let ((nbrs (aref neigh v)))
                               (if (zerop (length nbrs))
                                   (list (aref pos v) v)
                                   (list (/ (loop for u across nbrs
                                                  summing (aref pos u))
                                            (length nbrs))
                                         v))))))
    (setf keyed (stable-sort keyed (lambda (a b) (< (first a) (first b)))))
    (loop for i from 0 below (length row)
          do (setf (aref row i) (second (nth i keyed))))))

;;; Reorder nodes within each rank to minimise edge crossings (barycenter
;;; sweeps): alternate down/up passes sort each rank by the mean position of
;;; its neighbours, keeping whichever ordering crossed least.
(defun gm-order-ranks (by-rank edges ranks)
  (let ((n (length ranks)))
    (when (or (< (length by-rank) 2) (< n 3))
      (return-from gm-order-ranks nil))
    (let ((parents (make-array n))
          (children (make-array n))
          (pos (make-array n :initial-element 0)))
      (dotimes (i n)
        (setf (aref parents i) (make-array 0 :adjustable t :fill-pointer 0))
        (setf (aref children i) (make-array 0 :adjustable t :fill-pointer 0)))
      (loop for e across edges
            do (let ((from (getf e :from)) (to (getf e :to)))
                 (when (and (/= from to) (> (aref ranks to) (aref ranks from)))
                   (vector-push-extend from (aref parents to))
                   (vector-push-extend to (aref children from)))))
      (flet ((reindex (row)
               (dotimes (i (length row))
                 (setf (aref pos (aref row i)) i))))
        (dotimes (r (length by-rank))
          (reindex (aref by-rank r)))
        (let* ((best (loop for r below (length by-rank)
                           collect (copy-seq (aref by-rank r))))
               (best-crossings (gm-count-crossings edges ranks pos)))
          (when (zerop best-crossings)
            (return-from gm-order-ranks nil))
          (dotimes (it 8)
            ;; Alternate sweeping down (sort by parents) and up (sort by
            ;; children).  Rows are shared; only the outer container is copied.
            (let* ((rows (if (evenp it)
                             (subseq by-rank 1)
                             (coerce (reverse (subseq by-rank 0
                                                      (1- (length by-rank))))
                                     'vector)))
                   (neigh (if (evenp it) parents children)))
              (dotimes (r (length rows))
                (gm-sort-by-barycenter (aref rows r) neigh pos)
                (reindex (aref rows r)))
              (let ((crossings (gm-count-crossings edges ranks pos)))
                (when (< crossings best-crossings)
                  (setf best-crossings crossings)
                  (setf best (loop for r below (length by-rank)
                                   collect (copy-seq (aref by-rank r)))))
                (when (zerop best-crossings)
                  (return)))))
          (dotimes (r (length by-rank))
            (let ((row (aref by-rank r))
                  (best-row (nth r best)))
              (setf (fill-pointer row) 0)
              (loop for v across best-row
                    do (vector-push-extend v row)))))))))

;;; Assign a cross-axis centre to every node so nodes line up under their
;;; neighbours: each node drifts toward the average of its neighbours while
;;; ranks keep their order and boxes keep `sep` between them.
(defun gm-assign-positions (by-rank size sep edges ranks)
  (let* ((n (length size))
         (parents (make-array n))
         (children (make-array n))
         (pos (make-array n :initial-element 0d0)))
    (dotimes (i n)
      (setf (aref parents i) (make-array 0 :adjustable t :fill-pointer 0))
      (setf (aref children i) (make-array 0 :adjustable t :fill-pointer 0)))
    (loop for e across edges
          do (let ((from (getf e :from)) (to (getf e :to)))
               (when (and (/= from to) (> (aref ranks to) (aref ranks from)))
                 (vector-push-extend from (aref parents to))
                 (vector-push-extend to (aref children from)))))
    (dotimes (r (length by-rank))
      (let ((x 0d0))
        (loop for v across (aref by-rank r)
              do (let ((hh (/ (aref size v) 2d0)))
                   (incf x hh)
                   (setf (aref pos v) x)
                   (incf x (+ hh sep))))))
    (dotimes (it 10)
      (let* ((rows (if (evenp it)
                       by-rank
                       (coerce (reverse (coerce by-rank 'list)) 'vector)))
             (neigh (if (evenp it) parents children)))
        (dotimes (r (length rows))
          (gm-relax-rank (aref rows r) neigh pos size sep))))
    (let ((min-left most-positive-double-float))
      (dotimes (v n)
        (setf min-left (min min-left (- (aref pos v) (/ (aref size v) 2d0)))))
      (let ((out (make-array n)))
        (dotimes (v n)
          ;; Math.round rounds positive halves up; floor(x + 1/2) matches.
          (setf (aref out v)
                (max 0 (floor (+ (- (aref pos v) min-left) 0.5d0)))))
        out))))

(defun gm-relax-rank (nodes neigh pos size sep)
  (let ((n (length nodes)))
    (when (zerop n)
      (return-from gm-relax-rank nil))
    (let ((desired (make-array n))
          (left (make-array n))
          (right (make-array n)))
      (dotimes (i n)
        (let* ((v (aref nodes i))
               (nbrs (aref neigh v)))
          (setf (aref desired i)
                (if (zerop (length nbrs))
                    (aref pos v)
                    (/ (loop for u across nbrs summing (aref pos u))
                       (length nbrs))))))
      (labels ((half-of (i) (/ (aref size (aref nodes i)) 2d0)))
        ;; Sweep right then left, then take the midpoint: this centres a node
        ;; between the tightest packing that respects order from either side.
        (dotimes (i n)
          (setf (aref left i)
                (if (zerop i)
                    (aref desired i)
                    (max (aref desired i)
                         (+ (aref left (1- i))
                            (half-of (1- i))
                            sep
                            (half-of i))))))
        (loop for i from (1- n) downto 0
              do (setf (aref right i)
                       (if (= i (1- n))
                           (aref desired i)
                           (min (aref desired i)
                                (- (aref right (1+ i))
                                   (half-of (1+ i))
                                   sep
                                   (half-of i))))))
        (dotimes (i n)
          (setf (aref pos (aref nodes i))
                (/ (+ (aref left i) (aref right i)) 2d0)))
        (loop for i from 1 below n
              do (let ((min-p (+ (aref pos (aref nodes (1- i)))
                                 (half-of (1- i))
                                 sep
                                 (half-of i))))
                   (when (< (aref pos (aref nodes i)) min-p)
                     (setf (aref pos (aref nodes i)) min-p))))))))

;;; Lexicographic comparison of 5-element numeric tuples (JS array sort).
(defun gm-lex5< (a b)
  (loop for i from 0 below 5
        for ai = (nth i a)
        for bi = (nth i b)
        when (< ai bi) return t
        when (> ai bi) return nil
        finally (return nil)))

;;; Pack spans into as few parallel tracks as possible.
;;;
;;; Two spans share a track when they are two cells apart, or when they share
;;; an endpoint - edges fanning out of one node deliberately reuse a single
;;; row so a merge draws one arrowhead rather than a stack of them.
(defun gm-assign-tracks (spans)
  (let* ((sorted (stable-sort (copy-list spans) #'gm-lex5<))
         (tracks (make-array 0 :adjustable t :fill-pointer 0))
         (assigned (make-array 0 :adjustable t :fill-pointer 0)))
    (dolist (span sorted)
      (destructuring-bind (s e f to idx) span
        (let ((slot nil))
          (loop for ti from 0 below (length tracks)
                do (when (every (lambda (m)
                                  (destructuring-bind (s2 e2 f2 t2) m
                                    (or (<= (+ e2 2) s)
                                        (<= (+ e 2) s2)
                                        (= f2 f)
                                        (= t2 to))))
                                (aref tracks ti))
                     (setf slot ti)
                     (return)))
          (unless slot
            (setf slot (length tracks))
            (vector-push-extend nil tracks))
          (setf (aref tracks slot)
                (cons (list s e f to) (aref tracks slot)))
          (vector-push-extend (list idx slot) assigned))))
    (values assigned (length tracks))))

;;; Edges from rank `r` to `r + 1` that must jog sideways, so need a bus row.
(defun gm-bus-spans (graph ranks centers r exact)
  (let ((out nil))
    (loop for e across (gm-graph-edges graph)
          for i from 0
          do (let* ((from (getf e :from))
                    (to (getf e :to))
                    (jogs (if exact
                              (/= (aref centers from) (aref centers to))
                              (> (abs (- (aref centers from) (aref centers to))) 1))))
               (when (and (/= from to)
                          (= (aref ranks from) r)
                          (= (aref ranks to) (1+ r))
                          jogs)
                 (push (list (min (aref centers from) (aref centers to))
                             (max (aref centers from) (aref centers to))
                             from to i)
                       out))))
    (nreverse out)))

;;; Edges skipping a rank or running backwards; these go around in a lane.
(defun gm-lane-spans (graph ranks placed vertical)
  (let ((out nil))
    (loop for e across (gm-graph-edges graph)
          for i from 0
          do (let* ((from (getf e :from))
                    (to (getf e :to)))
               (unless (or (= from to)
                           (= (aref ranks to) (1+ (aref ranks from))))
                 (let* ((pf (aref placed from))
                        (pt (aref placed to))
                        (a (if vertical
                               (min (getf pf :cy) (getf pt :cy))
                               (min (getf pf :cx) (getf pt :cx))))
                        (b (if vertical
                               (max (getf pf :cy) (getf pt :cy))
                               (max (getf pf :cx) (getf pt :cx)))))
                   (push (list a b from to i) out)))))
    (nreverse out)))

;;; ------------------------------------------------------------- placement
(defun gm-place-td (ranks max-rank by-rank sizes graph placed)
  (let* ((n-edges (length (gm-graph-edges graph)))
         (centers (gm-assign-positions by-rank (getf sizes :lay-w) +gm-gap-x+
                                       (gm-graph-edges graph) ranks))
         (edge-bus (make-array n-edges :initial-element 0))
         (bus-tracks (make-array (1+ max-rank) :initial-element 0)))
    (loop for r from 0 below max-rank
          do (let ((spans (gm-bus-spans graph ranks centers r nil)))
               (when spans
                 (multiple-value-bind (assigned count) (gm-assign-tracks spans)
                   (loop for pair across assigned
                         do (setf (aref edge-bus (first pair)) (second pair)))
                   (setf (aref bus-tracks r) count)))))
    (let* ((rank-h (make-array (length by-rank)))
           (box-h (getf sizes :box-h))
           (extra-h (getf sizes :extra-h))
           (box-w (getf sizes :box-w))
           (self-label-w (getf sizes :self-label-w)))
      (dotimes (r (length by-rank))
        (let ((row (aref by-rank r)))
          (if (zerop (length row))
              (setf (aref rank-h r) 3)
              (setf (aref rank-h r)
                    (reduce #'max (loop for i across row
                                        collect (+ (aref box-h i)
                                                   (aref extra-h i))))))))
      (let ((rank-y (make-array (1+ max-rank) :initial-element 0)))
        (loop for r from 1 to max-rank
              do (setf (aref rank-y r)
                       (+ (aref rank-y (1- r))
                          (aref rank-h (1- r))
                          (max +gm-gap-y+ (1+ (aref bus-tracks (1- r)))))))
        (let* ((canvas-h (+ (aref rank-y max-rank) (aref rank-h max-rank)))
               (band-end (make-array (1+ max-rank))))
          (dotimes (r (1+ max-rank))
            (setf (aref band-end r) (+ (aref rank-y r) (aref rank-h r))))
          (let ((diagram-w 1))
            (dotimes (r (length by-rank))
              (let ((row (aref by-rank r)))
                (loop for idx across row
                      do (let* ((w (aref box-w idx))
                                (h (aref box-h idx))
                                (cx (aref centers idx))
                                (x (gm-sat cx (gm-half w)))
                                (eh (aref extra-h idx))
                                (y (+ (aref rank-y r)
                                      (gm-half (- (aref rank-h r) h eh)))))
                           (setf (aref placed idx)
                                 (list :x x :y y :w w :h h :cx cx
                                       :cy (+ y (gm-half h)) :rank r))
                           (setf diagram-w (max diagram-w (+ x w)))
                           (when (and (plusp eh) (plusp (aref self-label-w idx)))
                             (setf diagram-w
                                   (max diagram-w
                                        (+ x w 2 (aref self-label-w idx)))))))))
            (let ((content-w diagram-w))
              (loop for e across (gm-graph-edges graph)
                    do (let ((from (getf e :from)) (to (getf e :to))
                             (label (getf e :label)))
                         (when (and (/= from to) (not (null label)))
                           (let ((lw (min (gm-string-width label) +gm-max-label+)))
                             (if (= (aref ranks to) (1+ (aref ranks from)))
                                 (setf content-w
                                       (max content-w
                                            (+ (getf (aref placed to) :cx) 2 lw)))
                                 (setf content-w
                                       (max content-w (+ diagram-w lw 1))))))))
              (let ((edge-lane (make-array n-edges :initial-element 0))
                    (lanes (gm-lane-spans graph ranks placed t))
                    (canvas-w content-w)
                    (lane-base 0))
                (when lanes
                  (multiple-value-bind (assigned count) (gm-assign-tracks lanes)
                    (loop for pair across assigned
                          do (setf (aref edge-lane (first pair)) (second pair)))
                    (setf canvas-w (+ content-w 1 count))
                    (setf lane-base (+ content-w 1))))
                (list :canvas-w canvas-w :canvas-h canvas-h
                      :band-end band-end :edge-bus edge-bus
                      :lane-base lane-base :edge-lane edge-lane)))))))))

(defun gm-place-lr (ranks max-rank by-rank sizes graph placed)
  (let* ((n-edges (length (gm-graph-edges graph)))
         (box-w (getf sizes :box-w))
         (box-h (getf sizes :box-h))
         (extra-h (getf sizes :extra-h))
         (self-label-w (getf sizes :self-label-w))
         (col-w (make-array (length by-rank))))
    (dotimes (r (length by-rank))
      (let ((row (aref by-rank r)))
        (if (zerop (length row))
            (setf (aref col-w r) 0)
            (setf (aref col-w r)
                  (reduce #'max (loop for i across row collect (aref box-w i)))))))
    ;; Left-to-right edge labels sit in the gap between columns, so the gap
    ;; has to be wide enough for the widest of them.
    (let ((max-label 0))
      (loop for e across (gm-graph-edges graph)
            do (let ((from (getf e :from)) (to (getf e :to)))
                 (when (and (or (= from to)
                                (= (aref ranks to) (1+ (aref ranks from))))
                            (not (null (getf e :label))))
                   (setf max-label
                         (max max-label
                              (min (gm-string-width (getf e :label))
                                   +gm-max-label+))))))
      (let* ((base-gap (max (1+ +gm-gap-x+) (+ max-label 3)))
             (centers (gm-assign-positions by-rank (getf sizes :lay-h) 1
                                           (gm-graph-edges graph) ranks))
             (edge-bus (make-array n-edges :initial-element 0))
             (bus-tracks (make-array (1+ max-rank) :initial-element 0)))
        (loop for r from 0 below max-rank
              do (let ((spans (gm-bus-spans graph ranks centers r t)))
                   (when spans
                     (multiple-value-bind (assigned count) (gm-assign-tracks spans)
                       (loop for pair across assigned
                             do (setf (aref edge-bus (first pair)) (second pair)))
                       (setf (aref bus-tracks r) count)))))
        (let ((rank-x (make-array (1+ max-rank) :initial-element 0)))
          (loop for r from 1 to max-rank
                do (setf (aref rank-x r)
                         (+ (aref rank-x (1- r))
                            (aref col-w (1- r))
                            (max base-gap (1+ (aref bus-tracks (1- r)))))))
          (let ((self-tails (loop for i across (aref by-rank max-rank)
                                  when (and (plusp (aref extra-h i))
                                            (plusp (aref self-label-w i)))
                                  collect (+ 2 (aref self-label-w i)))))
            (let ((canvas-w (+ (aref rank-x max-rank)
                               (aref col-w max-rank)
                               (if self-tails (reduce #'max self-tails) 0)))
                  (band-end (make-array (1+ max-rank))))
              (dotimes (r (1+ max-rank))
                (setf (aref band-end r) (+ (aref rank-x r) (aref col-w r))))
              (let ((diagram-h 1))
                (dotimes (r (length by-rank))
                  (let ((x (aref rank-x r)))
                    (loop for idx across (aref by-rank r)
                          do (let* ((w (aref box-w idx))
                                    (h (aref box-h idx))
                                    (cy (aref centers idx))
                                    (y (gm-sat cy (gm-half (+ h (aref extra-h idx))))))
                               (setf (aref placed idx)
                                     (list :x x :y y :w w :h h
                                           :cx (+ x (gm-half w))
                                           :cy (+ y (gm-half h))
                                           :rank r))
                               (setf diagram-h
                                     (max diagram-h
                                          (+ y h (aref extra-h idx))))))))
                (let ((edge-lane (make-array n-edges :initial-element 0))
                      (lanes (gm-lane-spans graph ranks placed nil))
                      (canvas-h diagram-h)
                      (lane-base 0))
                  (when lanes
                    (multiple-value-bind (assigned count) (gm-assign-tracks lanes)
                      (loop for pair across assigned
                            do (setf (aref edge-lane (first pair)) (second pair)))
                      (setf canvas-h (+ diagram-h 1 count))
                      (setf lane-base (+ diagram-h 1))))
                  (list :canvas-w canvas-w :canvas-h canvas-h
                        :band-end band-end :edge-bus edge-bus
                        :lane-base lane-base :edge-lane edge-lane))))))))))

;;; --------------------------------------------------------------- canvas
;;; Rank, place, draw and route a graph onto a fresh canvas.
(defun gm-layout-canvas (graph extras)
  (let ((n (gm-graph-node-count graph)))
    (when (zerop n)
      (return-from gm-layout-canvas nil))
    (let* ((ranks (gm-compute-ranks graph))
           (max-rank 0)
           (by-rank nil)
           (wrapped (map 'vector (lambda (node)
                                   (gm-wrap-label (first node)
                                                  +gm-wrap-width+
                                                  +gm-max-lines+))
                         (gm-graph-nodes graph))))
      (dotimes (i (length ranks))
        (setf max-rank (max max-rank (aref ranks i))))
      (setf by-rank (make-array (1+ max-rank)))
      (dotimes (r (1+ max-rank))
        (setf (aref by-rank r) (make-array 0 :adjustable t :fill-pointer 0)))
      (dotimes (idx (length ranks))
        (vector-push-extend idx (aref by-rank (aref ranks idx))))
      (gm-order-ranks by-rank (gm-graph-edges graph) ranks)
      (flet ((widest (lines)
               (max 1 (if (null lines)
                          1
                          (reduce #'max (mapcar #'gm-string-width lines))))))
        (let ((box-w (make-array n))
              (box-h (make-array n)))
          (dotimes (i n)
            (let ((extra (nth i extras)))
              (setf (aref box-w i)
                    (cond ((string= (getf extra :kind) "frame")
                           (max (+ (gm-canvas-w (getf extra :sub)) 2)
                                (+ (gm-string-width
                                    (gm-fit-label (gm-node-label-at graph i)
                                                  +gm-wrap-width+))
                                   4)))
                          ((string= (getf extra :kind) "compartments")
                           (+ (widest (loop for sec in (getf extra :sections)
                                            append sec))
                              4))
                          (t (+ (widest (aref wrapped i)) 4))))
              (setf (aref box-h i)
                    (cond ((string= (getf extra :kind) "frame")
                           (+ (gm-canvas-h (getf extra :sub)) 2))
                          ((string= (getf extra :kind) "compartments")
                           (let ((filled (count-if (lambda (s)
                                                     (plusp (length s)))
                                                   (getf extra :sections))))
                             (+ (loop for sec in (getf extra :sections)
                                      summing (length sec))
                                (gm-sat filled 1)
                                2)))
                          (t (+ (length (aref wrapped i)) 2))))))
          ;; A self-edge needs two rows below its box, and room beside it for
          ;; a label.
          (let ((extra-h (make-array n :initial-element 0))
                (self-label-w (make-array n :initial-element 0)))
            (loop for e across (gm-graph-edges graph)
                  do (let ((from (getf e :from)) (to (getf e :to)))
                       (when (= from to)
                         (setf (aref extra-h from) 2)
                         (unless (null (getf e :label))
                           (setf (aref self-label-w from)
                                 (max (aref self-label-w from)
                                      (min (gm-string-width (getf e :label))
                                           +gm-max-label+)))))))
            (dotimes (i n)
              (when (plusp (aref extra-h i))
                (setf (aref box-w i) (max (aref box-w i) 7))))
            (let ((sizes (list :box-w box-w :box-h box-h
                               :lay-w (loop for i below n
                                            collect (+ (aref box-w i)
                                                       (if (plusp (aref self-label-w i))
                                                           (* 2 (+ (aref self-label-w i) 3))
                                                           0)))
                               :lay-h (loop for i below n
                                            collect (+ (aref box-h i)
                                                       (aref extra-h i)))
                               :extra-h extra-h
                               :self-label-w self-label-w)))
              ;; Lisp vectors for the layout sizes.
              (setf (getf sizes :lay-w)
                    (coerce (getf sizes :lay-w) 'vector))
              (setf (getf sizes :lay-h)
                    (coerce (getf sizes :lay-h) 'vector))
              (let ((placed (make-array n))
                    (vertical (or (string= (gm-graph-dir graph) "down")
                                  (string= (gm-graph-dir graph) "up"))))
                (dotimes (i n)
                  (setf (aref placed i)
                        (list :x 0 :y 0 :w 0 :h 0 :cx 0 :cy 0 :rank 0)))
                (let ((plan (if vertical
                                (gm-place-td ranks max-rank by-rank sizes graph placed)
                                (gm-place-lr ranks max-rank by-rank sizes graph placed))))
                  (when (> (* (getf plan :canvas-w) (getf plan :canvas-h))
                           +gm-max-canvas-cells+)
                    (return-from gm-layout-canvas nil))
                  (let ((canvas (gm-make-canvas (getf plan :canvas-w)
                                                (getf plan :canvas-h))))
                    (dotimes (idx n)
                      (let ((extra (nth idx extras)))
                        (cond ((string= (getf extra :kind) "frame")
                               (gm-draw-frame canvas (aref placed idx)
                                              (gm-node-label-at graph idx)
                                              (getf extra :sub)))
                              ((string= (getf extra :kind) "compartments")
                               (gm-draw-class-box canvas (aref placed idx)
                                                  (getf extra :sections)))
                              (t
                               (gm-draw-box canvas (aref placed idx)
                                            (aref wrapped idx)
                                            (gm-node-shape-at graph idx))))))
                    (loop for edge across (gm-graph-edges graph)
                          for i from 0
                          do (setf (gm-canvas-cur-style canvas)
                                   (cond ((string= (getf edge :line) "dotted")
                                          +gm-sty-dot+)
                                         ((string= (getf edge :line) "thick")
                                          +gm-sty-thick+)
                                         (t +gm-sty-solid+)))
                             (let ((from (getf edge :from))
                                   (to (getf edge :to)))
                               (if (= from to)
                                   (gm-route-self canvas (aref placed from) edge)
                                   (let* ((fp (aref placed from))
                                          (tp (aref placed to))
                                          (adjacent (= (getf tp :rank)
                                                       (1+ (getf fp :rank))))
                                          (bus (+ (aref (getf plan :band-end)
                                                        (getf fp :rank))
                                                  (aref (getf plan :edge-bus) i)))
                                          (lane (+ (getf plan :lane-base)
                                                   (aref (getf plan :edge-lane) i))))
                                     (cond ((and vertical adjacent)
                                            (gm-route-forward canvas fp tp edge bus))
                                           (vertical
                                            (gm-route-back canvas fp tp edge lane))
                                           (adjacent
                                            (gm-route-forward-lr canvas fp tp edge bus))
                                           (t
                                            (gm-route-back-lr canvas fp tp edge lane)))))))
                    (gm-canvas-finalize-mask canvas)
                    canvas))))))))))

;;; Apply the direction flip a finished canvas needs for BT / RL.
(defun gm-orient (canvas graph)
  (cond ((string= (gm-graph-dir graph) "up")
         (gm-canvas-flip-vertical canvas))
        ((string= (gm-graph-dir graph) "left")
         (gm-canvas-flip-horizontal canvas))
        (t nil))
  canvas)

;;; Flowchart and state diagrams: plain boxes, no extra content.
(defun gm-layout-flowchart (graph)
  (let ((extras (loop for i below (gm-graph-node-count graph)
                      collect (list :kind "plain"))))
    (let ((canvas (gm-layout-canvas graph extras)))
      (if canvas (gm-orient canvas graph) nil))))

;;; Class and ER diagrams: boxes divided into title / attribute / method rows.
(defun gm-layout-class (graph infos)
  (let ((extras (loop for i below (gm-graph-node-count graph)
                      collect (let* ((info (aref infos i))
                                     (title (append (if (getf info :annotation)
                                                        (list (format nil "«~A»"
                                                                      (getf info :annotation)))
                                                        nil)
                                                    (list (gm-display-generics
                                                           (gm-node-label-at graph i))))))
                                (list :kind "compartments"
                                      :sections (list title
                                                      (getf info :attrs)
                                                      (getf info :methods)))))))
    (let ((canvas (gm-layout-canvas graph extras)))
      (if canvas (gm-orient canvas graph) nil))))

(defun gm-node-key (i)
  (format nil "n~D" i))

(defun gm-group-key (i)
  (format nil "g~D" i))

;;; Lay out a flowchart that uses `subgraph`.
;;;
;;; Each subgraph becomes a framed box holding its own independently laid-out
;;; canvas.  An edge is drawn in the innermost scope containing both
;;; endpoints; one crossing a subgraph boundary attaches to the frame instead
;;; of the node.
(defun gm-layout-grouped (graph)
  ;; A node whose id matches a subgraph id stands in for that subgraph.
  (let ((proxy (make-hash-table :test 'equal))
        (groups (gm-graph-groups graph)))
    (loop for gi from 0 below (length groups)
          do (let ((ni (gethash (getf (nth gi groups) :id)
                                (gm-graph-index graph))))
               (when ni (setf (gethash ni proxy) gi))))
    (labels ((group-chain (g)
               (let ((chain nil))
                 (loop while g
                       do (push g chain)
                          (setf g (getf (nth g groups) :parent)))
                 (nreverse chain)))
             (endpoint (n)
               (let ((gi (gethash n proxy)))
                 (if (null gi)
                     (list :key (gm-node-key n)
                           :chain (group-chain (gm-node-group-at graph n)))
                     (list :key (gm-group-key gi)
                           :chain (group-chain
                                   (getf (nth gi groups) :parent)))))))
      ;; Edges bucketed by the scope that draws them; NIL is the top level.
      (let ((scope-edges (make-hash-table :test 'equal))
            (referenced (make-array (length groups) :initial-element nil)))
        (loop for e across (gm-graph-edges graph)
              for ei from 0
              do (let* ((f (endpoint (getf e :from)))
                        (t-ep (endpoint (getf e :to)))
                        (f-chain (getf f :chain))
                        (t-chain (getf t-ep :chain))
                        (k 0))
                   (loop while (and (< k (length f-chain))
                                    (< k (length t-chain))
                                    (= (nth k f-chain) (nth k t-chain)))
                         do (incf k))
                   (let ((scope (if (zerop k) nil (nth (1- k) f-chain)))
                         (f-key (if (> (length f-chain) k)
                                    (gm-group-key (nth k f-chain))
                                    (getf f :key)))
                         (t-key (if (> (length t-chain) k)
                                    (gm-group-key (nth k t-chain))
                                    (getf t-ep :key))))
                     (dolist (key (list f-key t-key))
                       (when (char= (char key 0) #\g)
                         (setf (aref referenced
                                     (parse-integer (subseq key 1)))
                               t)))
                     (let ((list (gethash scope scope-edges)))
                       (if list
                           (setf (gethash scope scope-edges)
                                 (append list (list (list f-key t-key ei))))
                           (setf (gethash scope scope-edges)
                                 (list (list f-key t-key ei))))))))
        (let ((direct-nodes (make-hash-table :test 'equal)))
          (dotimes (ni (gm-graph-node-count graph))
            (unless (gethash ni proxy)
              (let* ((g (gm-node-group-at graph ni))
                     (list (gethash g direct-nodes)))
                (if list
                    (setf (gethash g direct-nodes)
                          (append list (list ni)))
                    (setf (gethash g direct-nodes) (list ni))))))
          ;; Drop empty subgraphs, but keep any that an edge attaches to.
          (let ((keep (make-array (length groups) :initial-element nil)))
            (loop for gi from (1- (length groups)) downto 0
                  do (let ((has-nodes (plusp (length
                                              (gethash gi direct-nodes nil))))
                           (has-children (loop for c from 0 below (length groups)
                                               thereis (and (eql (getf (nth c groups)
                                                                       :parent)
                                                                gi)
                                                            (aref keep c)))))
                       (setf (aref keep gi)
                             (or has-nodes has-children
                                 (aref referenced gi)))))
            (let ((canvas (gm-build-scope graph nil scope-edges
                                          direct-nodes keep)))
              (if canvas (gm-orient canvas graph) nil))))))))

(defun gm-build-scope (graph scope scope-edges direct-nodes keep)
  (let ((items nil))
    (dolist (ni (gethash scope direct-nodes nil))
      (push (gm-node-key ni) items))
    (let ((child-groups nil))
      (dotimes (gi (length (gm-graph-groups graph)))
        (when (and (eql (getf (nth gi (gm-graph-groups graph)) :parent) scope)
                   (aref keep gi))
          (push gi child-groups)))
      (setf child-groups (nreverse child-groups))
      (dolist (gi child-groups)
        (push (gm-group-key gi) items)))
    (setf items (nreverse items))
    (if (null items)
        (gm-make-canvas 1 1)
        (let ((index-of (make-hash-table :test 'equal))
              (nodes (make-array 0 :adjustable t :fill-pointer 0))
              (extras nil))
          (loop for item in items
                do (setf (gethash item index-of) (length nodes))
                   (let ((i (parse-integer (subseq item 1))))
                     (if (char= (char item 0) #\n)
                         (progn
                           (vector-push-extend (list (gm-node-label-at graph i)
                                                     (gm-node-shape-at graph i))
                                               nodes)
                           (push (list :kind "plain") extras))
                         (let ((sub (gm-build-scope graph i scope-edges
                                                    direct-nodes keep)))
                           (when (null sub)
                             (return-from gm-build-scope nil))
                           (vector-push-extend
                            (list (getf (nth i (gm-graph-groups graph)) :label)
                                  "rect")
                            nodes)
                           (push (list :kind "frame" :sub sub) extras)))))
          (let ((edges (make-array 0 :adjustable t :fill-pointer 0)))
            (dolist (triple (gethash scope scope-edges nil))
              (destructuring-bind (f t-ep ei) triple
                (let ((fi (gethash f index-of))
                      (ti (gethash t-ep index-of)))
                  (when (and fi ti)
                    (let ((e (aref (gm-graph-edges graph) ei)))
                      (vector-push-extend
                       (gm-make-edge :from fi :to ti
                                     :label (getf e :label)
                                     :head-to (getf e :head-to)
                                     :head-from (getf e :head-from)
                                     :line (getf e :line))
                       edges))))))
            ;; Layout only reads nodes/edges/dir, so a bare graph carrying
            ;; those is enough.
            (let ((synth (gm-make-graph (gm-graph-dir graph))))
              (setf (gm-graph-nodes synth) nodes)
              (setf (gm-graph-edges synth) edges)
              (gm-layout-canvas synth (nreverse extras))))))))

;;; ---------------------------------------------------------------- drawing
(defun gm-draw-box (canvas p lines shape)
  (let* ((x (getf p :x))
         (y (getf p :y))
         (w (getf p :w))
         (h (getf p :h))
         (right (+ x w -1))
         (bottom (+ y h -1))
         (rounded (or (string= shape "round") (string= shape "diamond"))))
    (gm-canvas-set canvas x y (if rounded "╭" "┌") "border")
    (gm-canvas-set canvas right y (if rounded "╮" "┐") "border")
    (gm-canvas-set canvas x bottom (if rounded "╰" "└") "border")
    (gm-canvas-set canvas right bottom (if rounded "╯" "┘") "border")
    ;; The perimeter is drawn as bits so edges can tee into it, but it is the
    ;; box outline, so it claims `border` rather than `edge`.
    (loop for cx from (1+ x) below right
          do (gm-canvas-add-bits canvas cx y (logior +gm-l+ +gm-r+) "border")
             (gm-canvas-add-bits canvas cx bottom
                                 (logior +gm-l+ +gm-r+) "border"))
    (loop for cy from (1+ y) below bottom
          do (gm-canvas-add-bits canvas x cy (logior +gm-u+ +gm-d+) "border")
             (gm-canvas-add-bits canvas right cy
                                 (logior +gm-u+ +gm-d+) "border"))
    (loop for cy from y to bottom
          do (loop for cx from x to right
                   do (setf (aref (gm-canvas-occupied canvas)
                                  (gm-canvas-idx canvas cx cy))
                            1)))
    (let ((inner (max 1 (gm-sat w (+ (* 2 +gm-pad+) 2)))))
      (loop for line in lines
            for li from 0
            do (let* ((text (gm-fit-label line inner))
                      (text-x (+ x 1 +gm-pad+
                                 (gm-half (gm-sat inner
                                                  (gm-string-width text))))))
                 (gm-draw-text canvas text text-x (+ y 1 li) "text"))))))

;;; A class or ER box: sections separated by horizontal rules, title centred.
(defun gm-draw-class-box (canvas p sections)
  (gm-draw-box canvas p nil "rect")
  (let* ((inner (max 1 (gm-sat (getf p :w) (+ (* 2 +gm-pad+) 2))))
         (row (+ (getf p :y) 1))
         (first t))
    (loop for section in sections
          for si from 0
          do (unless (null section)
               (unless first
                 (gm-canvas-set canvas (getf p :x) row "├" "border")
                 (loop for x from (+ (getf p :x) 1)
                       below (+ (getf p :x) (getf p :w) -1)
                       do (gm-canvas-set canvas x row "─" "border"))
                 (gm-canvas-set canvas (+ (getf p :x) (getf p :w) -1)
                                row "┤" "border")
                 (incf row))
               (setf first nil)
               (loop for line in section
                     do (let* ((text (gm-fit-label line inner))
                               (tx (if (zerop si)
                                       (+ (getf p :x) 1 +gm-pad+
                                          (gm-half (gm-sat inner
                                                           (gm-string-width text))))
                                       (+ (getf p :x) 1 +gm-pad+))))
                          (gm-draw-text-over-edges canvas text tx row "text")
                          (incf row)))))))

;;; A subgraph frame: a titled box with a finished sub-canvas centred inside.
(defun gm-draw-frame (canvas p title sub)
  (gm-draw-box canvas p nil "rect")
  (let ((t-text (gm-fit-label title (gm-sat (getf p :w) 4))))
    (gm-draw-text-over-edges canvas (format nil " ~A " t-text)
                             (+ (getf p :x) 1) (getf p :y) "text")
    (gm-canvas-blit canvas sub
                    (+ (getf p :x) 1
                       (gm-half (- (- (getf p :w) 2) (gm-canvas-w sub))))
                    (+ (getf p :y) 1
                       (gm-half (- (- (getf p :h) 2) (gm-canvas-h sub)))))))

;;; --------------------------------------------------------------- routing
(defun gm-head-glyph (head arrow)
  (cond ((string= head "circle") "o")
        ((string= head "cross") "×")
        ((string= head "diamondFill") "◆")
        ((string= head "diamondOpen") "◇")
        ((string= head "triangle")
         (cond ((string= arrow "▼") "▽")
               ((string= arrow "▲") "△")
               ((string= arrow "◄") "◁")
               ((string= arrow "▶") "▷")
               (t arrow)))
        (t arrow)))

;;; Write an edge label, stopping at the first cell already occupied.
(defun gm-place-label (canvas label row start-x)
  (when (>= row (gm-canvas-h canvas))
    (return-from gm-place-label nil))
  (let ((text (gm-fit-label label +gm-max-label+))
        (x start-x))
    (dolist (pair (gm-measured text))
      (let ((c (car pair)) (cw (cdr pair)))
        (unless (zerop cw)
          (when (> (+ x cw) (gm-canvas-w canvas))
            (return))
          (let ((blocked nil))
            (loop for k from 0 below cw
                  do (let ((i (gm-canvas-idx canvas (+ x k) row)))
                       (when (or (not (string= (aref (gm-canvas-ch canvas) i) " "))
                                 (not (zerop (aref (gm-canvas-mask canvas) i)))
                                 (not (zerop (aref (gm-canvas-occupied canvas) i))))
                         (setf blocked t))))
            (when blocked (return))
            (gm-canvas-set canvas x row c "edgeLabel")
            (loop for k from 1 below cw
                  do (gm-canvas-set canvas (+ x k) row
                                    +gm-cont+ "edgeLabel"))
            (incf x cw)))))))

;;; Adjacent ranks, top-down: drop, jog along the bus row, drop into the head.
(defun gm-route-forward (canvas from to edge bus)
  (let* ((tx (getf to :cx))
         ;; A jog of one column reads as a kink; snap straight instead.
         (bx (if (<= (abs (- (getf from :cx) tx)) 1)
                 tx
                 (getf from :cx)))
         (by (+ (getf from :y) (getf from :h) -1))
         (head-row (1- (getf to :y))))
    (gm-canvas-junction canvas bx by +gm-d+)
    (gm-canvas-seg-v canvas bx by bus)
    (if (= bx tx)
        (gm-canvas-seg-v canvas bx bus head-row)
        (progn
          (gm-canvas-seg-h canvas bus bx tx)
          (gm-canvas-seg-v canvas tx bus head-row)))
    (if (string= (getf edge :head-to) "none")
        (gm-canvas-add-bits canvas tx head-row +gm-u+)
        (gm-canvas-set canvas tx head-row
                       (gm-head-glyph (getf edge :head-to) "▼") "edge"))
    (unless (string= (getf edge :head-from) "none")
      (gm-canvas-set canvas bx by
                     (gm-head-glyph (getf edge :head-from) "▲") "edge"))
    (unless (null (getf edge :label))
      (gm-place-label canvas (getf edge :label) head-row (1+ tx)))))

;;; A self-edge: a stub loop hanging below the box.
(defun gm-route-self (canvas p edge)
  (let* ((bottom (+ (getf p :y) (getf p :h) -1))
         (exit-x (1+ (getf p :cx)))
         (ret-x (- (+ (getf p :x) (getf p :w)) 2)))
    (when (or (<= ret-x exit-x)
              (>= (+ bottom 2) (gm-canvas-h canvas)))
      (return-from gm-route-self nil))
    (let ((line (getf edge :line))
          (v nil) (h nil) (bl nil) (br nil))
      (cond ((string= line "dotted")
             (setf v "╎" h "╌" bl "╰" br "╯"))
            ((string= line "thick")
             (setf v "┃" h "━" bl "┗" br "┛"))
            (t
             (setf v "│" h "─" bl "╰" br "╯")))
      (gm-canvas-junction canvas exit-x bottom +gm-d+)
      (gm-canvas-set canvas exit-x (+ bottom 1) v "edge")
      (gm-canvas-set canvas exit-x (+ bottom 2) bl "edge")
      (loop for x from (1+ exit-x) below ret-x
            do (gm-canvas-set canvas x (+ bottom 2) h "edge"))
      (gm-canvas-set canvas ret-x (+ bottom 2) br "edge")
      (gm-canvas-set canvas ret-x (+ bottom 1)
                     (gm-head-glyph (getf edge :head-to) "▲") "edge")
      (unless (null (getf edge :label))
        (gm-place-label canvas (getf edge :label) (+ bottom 1)
                        (+ (getf p :x) (getf p :w) 1))))))

;;; Skip or back edge, top-down: out the right side, up a lane, back in.
(defun gm-route-back (canvas from to edge lane-x)
  (let* ((sx (+ (getf from :x) (getf from :w) -1))
         (sy (getf from :cy))
         (tx (+ (getf to :x) (getf to :w) -1))
         (tyc (getf to :cy)))
    (gm-canvas-junction canvas sx sy +gm-r+)
    (gm-canvas-seg-h canvas sy sx lane-x)
    (gm-canvas-seg-v canvas lane-x sy tyc)
    (gm-canvas-seg-h canvas tyc (1+ tx) lane-x)
    (if (string= (getf edge :head-to) "none")
        (gm-canvas-add-bits canvas (1+ tx) tyc +gm-r+)
        (gm-canvas-set canvas (1+ tx) tyc
                       (gm-head-glyph (getf edge :head-to) "◄") "edge"))
    (unless (string= (getf edge :head-from) "none")
      (gm-canvas-set canvas sx sy
                     (gm-head-glyph (getf edge :head-from) "◄") "edge"))
    (unless (null (getf edge :label))
      (gm-place-label canvas (getf edge :label)
                      (gm-sat tyc 1)
                      (gm-sat lane-x (+ (gm-string-width (getf edge :label))
                                        1))))))

;;; Adjacent ranks, left-to-right: out the right side, jog on the bus column.
(defun gm-route-forward-lr (canvas from to edge bus)
  (let* ((rx (+ (getf from :x) (getf from :w) -1))
         (ry (getf from :cy))
         (ly (getf to :cy))
         (head-col (1- (getf to :x))))
    (gm-canvas-junction canvas rx ry +gm-r+)
    (gm-canvas-seg-h canvas ry rx bus)
    (if (= ry ly)
        (gm-canvas-seg-h canvas ry bus head-col)
        (progn
          (gm-canvas-seg-v canvas bus ry ly)
          (gm-canvas-seg-h canvas ly bus head-col)))
    (if (string= (getf edge :head-to) "none")
        (gm-canvas-add-bits canvas head-col ly +gm-r+)
        (gm-canvas-set canvas head-col ly
                       (gm-head-glyph (getf edge :head-to) "▶") "edge"))
    (unless (string= (getf edge :head-from) "none")
      (gm-canvas-set canvas rx ry
                     (gm-head-glyph (getf edge :head-from) "◄") "edge"))
    (unless (null (getf edge :label))
      (gm-place-label canvas (getf edge :label) (gm-sat ly 1) (1+ bus)))))

;;; Skip or back edge, left-to-right: down out the bottom, along a lane, back
;;; up.
(defun gm-route-back-lr (canvas from to edge lane-y)
  (let* ((sx (getf from :cx))
         (sy (+ (getf from :y) (getf from :h) -1))
         (tx (getf to :cx))
         (ty (+ (getf to :y) (getf to :h) -1)))
    (gm-canvas-junction canvas sx sy +gm-d+)
    (gm-canvas-seg-v canvas sx sy lane-y)
    (gm-canvas-seg-h canvas lane-y sx tx)
    (gm-canvas-seg-v canvas tx lane-y (1+ ty))
    (if (string= (getf edge :head-to) "none")
        (gm-canvas-add-bits canvas tx (1+ ty) +gm-d+)
        (gm-canvas-set canvas tx (1+ ty)
                       (gm-head-glyph (getf edge :head-to) "▲") "edge"))
    (unless (string= (getf edge :head-from) "none")
      (gm-canvas-set canvas sx sy
                     (gm-head-glyph (getf edge :head-from) "▲") "edge"))
    (unless (null (getf edge :label))
      (gm-place-label canvas (getf edge :label)
                      (gm-sat lane-y 1)
                      (gm-half (+ sx tx))))))
