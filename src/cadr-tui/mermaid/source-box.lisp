;;; grok-mermaid@0.2.2 dist/source-box.js:1-77 - direct port.
;;;
;;; Copyright 2023-2026 SpaceXAI
;;; Copyright 2026 Alexey Zaytsev
;;; Licensed under the Apache License, Version 2.0.
;;; This file is a Common Lisp port by the cadr authors; it is a
;;; modified version of the original work.  License text:
;;; docs/third-party/grok-mermaid-LICENSE.txt
;;;
;;; The raw source in a framed box.  What to show when `render` returns NIL,
;;; or returns art too wide for the space at hand.  Both are the caller's
;;; call, so this is theirs to invoke - and theirs to caption, since only they
;;; know whether some other view of the diagram exists to point the reader at.

(in-package #:cadr-tui)

(defun gm-rstrip-js-ws (s)
  ;; JS `str.replace(/\s+$/, "")`; the \s set is JS whitespace, not just
  ;; ASCII space/tab.
  (let ((end (length s)))
    (loop while (and (plusp end) (gm-whitespace-p (char s (1- end))))
          do (decf end))
    (subseq s 0 end)))

;;; Hard-break a line at `limit` columns, never splitting a wide glyph.
(defun gm-chunk-line (line limit)
  (if (or (null limit) (<= (gm-string-width line) limit))
      (list line)
      (let ((out nil)
            (cur "")
            (cur-w 0))
        (dolist (pair (gm-measured line))
          (let ((c (car pair))
                (cw (cdr pair)))
            (when (and (> (+ cur-w cw) limit) (not (string= cur "")))
              (push cur out)
              (setf cur "")
              (setf cur-w 0))
            (setf cur (concatenate 'string cur c))
            (incf cur-w cw)))
        (unless (string= cur "")
          (push cur out))
        (nreverse out))))

;;; Frame `src` in a titled box, hard-wrapping its lines to `max-width`
;;; columns.  The result can still exceed `max-width`: the body wraps to
;;; `max(8, max-width - 4)` and the ` mermaid: <kind> ` title is never
;;; truncated, so a long first token sets a floor.  Check `:width` if it
;;; matters.
(defun gm-source-box (src max-width)
  (setf src (gm-strip-controls src))
  (let* ((header (or (first (gm-split-words src)) "diagram"))
         (title (format nil " mermaid: ~A " header))
         (limit (if (null max-width)
                    nil
                    (max 8 (gm-sat max-width 4))))
         (body nil)
         (started nil))
    (dolist (line (mapcar #'gm-rstrip-js-ws (gm-src-lines src)))
      (when (or started (not (string= line "")))
        (setf started t)
        (setf body (nconc body (gm-chunk-line line limit)))))
    (let ((content-w (max (gm-string-width title)
                          (if body
                              (apply #'max (mapcar #'gm-string-width body))
                              0)))
          (plain nil)
          (styled nil))
      (let* ((inner (+ content-w 2))
             (rule (make-string (gm-sat inner (gm-string-width title))
                                :initial-element #\─)))
        (push (concatenate 'string "╭" title rule "╮") plain)
        (push (list (list "╭" "border")
                    (list title "title")
                    (list (concatenate 'string rule "╮") "border"))
              styled)
        (dolist (line body)
          (let ((pad (make-string (gm-sat content-w (gm-string-width line))
                                  :initial-element #\Space)))
            (push (concatenate 'string "│ " line pad " │") plain)
            (push (list (list "│ " "border")
                        (list line "text")
                        (list (concatenate 'string pad " │") "border"))
                  styled)))
        (let ((bottom (concatenate 'string "╰"
                                   (make-string inner :initial-element #\─)
                                   "╯")))
          (push bottom plain)
          (push (list (list bottom "border")) styled))
        (list :plain (nreverse plain)
              :styled (nreverse styled)
              :width (+ inner 2)
              :warnings nil)))))
