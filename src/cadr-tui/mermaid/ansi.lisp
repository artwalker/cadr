;;; grok-mermaid@0.2.2 dist/ansi.js:1-22 - direct port.
;;;
;;; Copyright 2023-2026 SpaceXAI
;;; Copyright 2026 Alexey Zaytsev
;;; Licensed under the Apache License, Version 2.0.
;;; This file is a Common Lisp port by the cadr authors; it is a
;;; modified version of the original work.  License text:
;;; docs/third-party/grok-mermaid-LICENSE.txt
;;;
;;; Render art to ANSI-coloured lines.  A convenience over mapping
;;; `styled` yourself; cadr's own TUI has its own styling model and renders
;;; through that instead.  Kept for API parity with the reference so the
;;; golden fixtures can be produced by either path.

(in-package #:cadr-tui)

;;; Dim frame, plain labels, cyan connectors.  Readable on light and dark.
(defparameter +gm-default-theme+
  '(("border" . "2")
    ("edge" . "36")
    ("edgeLabel" . "2;36")
    ("title" . "1")))

(defun gm-to-ansi (art &optional (theme +gm-default-theme+))
  (mapcar (lambda (row)
            (with-output-to-string (out)
              (dolist (span row)
                (let ((sgr (cdr (assoc (second span) theme :test #'string=))))
                  (if (null sgr)
                      (write-string (first span) out)
                      (progn
                        (write-char #\Escape out)
                        (write-string (format nil "[~Am" sgr) out)
                        (write-string (first span) out)
                        (write-char #\Escape out)
                        (write-string "[0m" out)))))))
          (getf art :styled)))
