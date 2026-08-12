;;; grok-mermaid@0.2.2 dist/graph.js:1-90 - direct port.
;;;
;;; Copyright 2023-2026 SpaceXAI
;;; Copyright 2026 Alexey Zaytsev
;;; Licensed under the Apache License, Version 2.0.
;;; This file is a Common Lisp port by the cadr authors; it is a
;;; modified version of the original work.  License text:
;;; docs/third-party/grok-mermaid-LICENSE.txt
;;;
;;; The shared diagram model.  Flowchart, state, class and ER sources all
;;; parse into a gm-graph; only sequence diagrams have their own model.

(in-package #:cadr-tui)

(defparameter +gm-max-nodes+ 128)
(defparameter +gm-max-edges+ 512)
(defparameter +gm-max-groups+ 24)
(defparameter +gm-max-group-depth+ 6)
(defparameter +gm-max-members+ 8)

(defun gm-empty-class-info ()
  (list :annotation nil :attrs nil :methods nil))

;;; LR/RL/BT as written in a header or direction statement; else down.
(defun gm-parse-dir (token)
  (cond ((string= (gm-ascii-upper token) "LR") "right")
        ((string= (gm-ascii-upper token) "RL") "left")
        ((string= (gm-ascii-upper token) "BT") "up")
        (t "down")))

(defstruct (gm-graph (:constructor gm-make-graph (&optional (dir "down"))))
  (nodes (make-array 0 :adjustable t :fill-pointer 0))
  (edges (make-array 0 :adjustable t :fill-pointer 0))
  (index (make-hash-table :test 'equal))
  (groups nil)
  ;; Innermost subgraph each node was declared in, parallel to nodes (oldest
  ;; first; see gm-node-group-at).
  (node-group nil)
  (cur-group nil)
  ;; Set when a cap was hit; the caller abandons the parse.
  (over-cap nil)
  ;; Text the flowchart grammar could not read and silently discarded.
  (warnings nil)
  (dir "down"))

(defun gm-graph-node-count (graph)
  (length (gm-graph-nodes graph)))

(defun gm-node-at (graph i)
  (aref (gm-graph-nodes graph) i))

(defun gm-node-label-at (graph i)
  (first (gm-node-at graph i)))

(defun gm-node-shape-at (graph i)
  (second (gm-node-at graph i)))

(defun gm-node-group-at (graph i)
  ;; node-group is pushed in declaration order; convert index from the head of
  ;; the list.  Groups are bounded (MAX_GROUPS), so this stays cheap.
  (nth (- (length (gm-graph-nodes graph)) 1 i) (gm-graph-node-group graph)))

(defun gm-graph-push-node (graph label shape)
  (let ((nodes (gm-graph-nodes graph)))
    (vector-push-extend (list label shape) nodes)
    (push (gm-graph-cur-group graph) (gm-graph-node-group graph))
    (1- (length nodes))))

;;; Index of id, creating the node if new.  A later declaration carrying a
;;; label overwrites the placeholder one an edge created.  Returns NIL once
;;; MAX-NODES is reached, which aborts the parse.
(defun gm-node-index (graph id label shape)
  (let ((existing (gethash id (gm-graph-index graph))))
    (when existing
      (when label
        (setf (first (gm-node-at graph existing)) label)
        (setf (second (gm-node-at graph existing)) shape))
      (return-from gm-node-index existing))
    (when (>= (length (gm-graph-nodes graph)) +gm-max-nodes+)
      (setf (gm-graph-over-cap graph) t)
      (return-from gm-node-index nil))
    (setf (gethash id (gm-graph-index graph)) (length (gm-graph-nodes graph)))
    (gm-graph-push-node graph (or label id) shape)))

;;; Set a node's label without disturbing its shape, creating it if new.
(defun gm-node-label (graph id label)
  (let ((existing (gethash id (gm-graph-index graph))))
    (if existing
        (progn
          (setf (first (gm-node-at graph existing)) label)
          existing)
        (gm-node-index graph id label "round"))))

;;; Append an edge, or flag over-cap when MAX-EDGES is reached.
(defun gm-push-edge (graph edge)
  (if (>= (length (gm-graph-edges graph)) +gm-max-edges+)
      (progn
        (setf (gm-graph-over-cap graph) t)
        nil)
      (progn
        (vector-push-extend edge (gm-graph-edges graph))
        t)))

(defun gm-make-edge (&key from to label head-to head-from line)
  (list :from from :to to :label label
        :head-to head-to :head-from head-from :line line))
