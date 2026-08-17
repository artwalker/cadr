;;; grok-mermaid@0.2.2 dist/index.js:1-99 - direct port.
;;;
;;; Copyright 2023-2026 SpaceXAI
;;; Copyright 2026 Alexey Zaytsev
;;; Licensed under the Apache License, Version 2.0.
;;; This file is a Common Lisp port by the cadr authors; it is a
;;; modified version of the original work.  License text:
;;; docs/third-party/grok-mermaid-LICENSE.txt
;;;
;;; Render a Mermaid source block as Unicode box-drawing art.  Supported:
;;; `graph`/`flowchart` (including `subgraph`), `stateDiagram`,
;;; `classDiagram`, `erDiagram` and `sequenceDiagram`.  The diagram is laid
;;; out at whatever size it needs; `:width` reports the columns that turned
;;; out to be.  Deciding what to do when that exceeds the space at hand is the
;;; caller's - `gm-source-box` is the usual answer.
;;;
;;; NIL means there is no art to show: blank input, a syntax error, a diagram
;;; type this renderer does not draw, or one large enough that laying it out
;;; is refused.  `gm-diagram-kind` separates the middle two.  Rendering is
;;; best-effort: a flowchart keeps whatever parsed; the stricter grammars
;;; additionally get one retry without their final line.  Everything given up
;;; on is listed in `:warnings` - advisory only, never a reason to withhold
;;; the art.

(in-package #:cadr-tui)

(defun gm-render (src)
  (setf src (gm-strip-controls src))
  (when (string= (gm-trim src) "")
    (return-from gm-render nil))
  (let ((drawn (gm-attempt src)))
    (when (null drawn)
      (return-from gm-render nil))
    (multiple-value-bind (plain styled width)
        (gm-canvas-to-lines (getf drawn :canvas))
      (list :plain plain
            :styled styled
            :width width
            :warnings (getf drawn :warnings)))))

;;; Draw `src`, retrying once without its last line if the grammar rejects it.
;;; State, class, ER and sequence fail a whole diagram on one unreadable
;;; statement, and while a source is streaming its last line is usually still
;;; being typed - so without this a diagram alternates with the source box all
;;; the way in.  Only the final line is dropped, and doing so is always
;;; reported.
(defun gm-attempt (src)
  (let ((drawn (gm-draw src)))
    (when drawn
      (return-from gm-attempt drawn))
    ;; JS: `src.replace(/\s+$/, "")` - trailing whitespace only.
    (let* ((body (gm-trim-end src))
           (cut (position #\Newline body :from-end t)))
      (when (null cut)
        (return-from gm-attempt nil))
      (let ((salvaged (gm-draw (subseq body 0 cut))))
        (when (null salvaged)
          (return-from gm-attempt nil))
        (let ((dropped (gm-trim (subseq body (1+ cut)))))
          (list :canvas (getf salvaged :canvas)
                :warnings (append (getf salvaged :warnings)
                                  (list (format nil
                                                "dropped, unreadable final line: \"~A\""
                                                dropped)))))))))

(defun gm-drawn (canvas warnings)
  (when canvas
    (list :canvas canvas :warnings warnings)))

;;; One parse→layout owner per kind.  Goldens pin the emitted bytes.
(defparameter +gm-draw-kinds+
  (list
   (cons "flowchart"
         (lambda (src)
           (let ((graph (gm-parse-graph src)))
             (gm-drawn
              (and graph
                   (if (null (gm-graph-groups graph))
                       (gm-layout-flowchart graph)
                       (gm-layout-grouped graph)))
              (and graph (gm-graph-warnings graph))))))
   (cons "state"
         (lambda (src)
           (let ((state (gm-parse-state src)))
             (gm-drawn (and state (gm-layout-flowchart state)) nil))))
   (cons "class"
         (lambda (src)
           (let ((cls (gm-parse-class src)))
             (gm-drawn
              (and cls (gm-layout-class (first cls) (second cls)))
              nil))))
   (cons "er"
         (lambda (src)
           (let ((er (gm-parse-er src)))
             (gm-drawn
              (and er (gm-layout-class (first er) (second er)))
              nil))))
   (cons "sequence"
         (lambda (src)
           (let ((seq (gm-parse-sequence src)))
             (gm-drawn (and seq (gm-layout-sequence seq)) nil))))))

;;; Dispatch on the declared diagram type; NIL means nothing was drawn.
(defun gm-draw (src)
  (let ((drawer
          (cdr (assoc (gm-diagram-kind src)
                      +gm-draw-kinds+
                      :test #'string=))))
    (and drawer (funcall drawer src))))
