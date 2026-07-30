(in-package #:cadr-tui/tests)

(defun escape-sequence (body)
  (concatenate 'string (string #\Escape) body))

(defun csi (body)
  (escape-sequence (concatenate 'string "[" body)))

(defun osc-bel (body)
  (concatenate
   'string (string #\Escape) "]" body
   (string (code-char 7))))

(defun osc-st (body)
  (concatenate
   'string (string #\Escape) "]" body
   (string #\Escape) "\\"))
