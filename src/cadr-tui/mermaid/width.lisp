;;; grok-mermaid@0.2.2 dist/width.js:1-75 — direct port.
;;;
;;; Copyright 2023-2026 SpaceXAI
;;; Copyright 2026 Alexey Zaytsev
;;; Licensed under the Apache License, Version 2.0.
;;; This file is a Common Lisp port by the cadr authors; it is a
;;; modified version of the original work.  License text:
;;; docs/third-party/grok-mermaid-LICENSE.txt
;;;
;;; Display width measured in grapheme clusters.  A cluster is the unit both
;;; of measuring and of painting, so a box is always sized for exactly what
;;; gets drawn into it.  Clustering comes from UAX #29 (SBCL's sb-unicode
;;; graphemes), which handles ZWJ sequences, skin-tone modifiers, variation
;;; selectors, keycaps, flags and Hangul.  Per-code-point widths come from the
;;; mechanically converted +gm-widths+ table (width-data.lisp).

(in-package #:cadr-tui)

(defconstant +gm-vs16+ #xfe0f)

(defun gm-regional-indicator-p (cp)
  (<= #x1f1e6 cp #x1f1ff))

;;; Width of one code point; the table covers the whole code point space.
(defun gm-code-point-width (cp)
  (let ((lo 0)
        (hi (1- (length +gm-widths+))))
    (loop while (<= lo hi)
          do (let* ((mid (ash (+ lo hi) -1))
                    (run (aref +gm-widths+ mid))
                    (run-lo (aref run 0))
                    (run-hi (aref run 1)))
               (cond ((< cp run-lo) (setf hi (1- mid)))
                     ((> cp run-hi) (setf lo (1+ mid)))
                     (t (return-from gm-code-point-width (aref run 2))))))
    1))

;;; Columns occupied by one grapheme cluster: the widest code point wins, so
;;; a base plus its combining marks measures as the base.  A variation
;;; selector requesting emoji presentation forces two columns, as does a
;;; regional indicator pair (a flag).  Zero is a real answer (soft hyphen,
;;; zero-width space): callers skip painting such a cluster.
(defun gm-cluster-width (cluster)
  (let ((w 0)
        (vs16 nil)
        (regional 0))
    (loop for ch across cluster
          for cp = (char-code ch)
          do (when (= cp +gm-vs16+) (setf vs16 t))
             (when (gm-regional-indicator-p cp) (incf regional))
             (let ((cw (gm-code-point-width cp)))
               (when (> cw w) (setf w cw))))
    (if (or vs16 (>= regional 2)) 2 w)))

;;; Iterate grapheme clusters as a list of strings, so no loop splits one.
(defun gm-clusters (s)
  (if (zerop (length s))
      nil
      (sb-unicode:graphemes s)))

;;; Iterate clusters paired with their display width.
(defun gm-measured (s)
  (mapcar (lambda (cluster)
            (cons cluster (gm-cluster-width cluster)))
          (gm-clusters s)))

;;; Display columns of a string.
(defun gm-string-width (s)
  (let ((w 0))
    (dolist (cluster (gm-clusters s))
      (incf w (gm-cluster-width cluster)))
    w))
