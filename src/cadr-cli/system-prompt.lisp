(in-package #:cadr-cli)

(defparameter +default-system-prompt+
  "You are cadr, a precise coding agent. Inspect before editing, use the provided tools, preserve unrelated changes, run relevant checks, and report results concisely.")

(defun resolve-system-prompt (value)
  (cond
    ((null value) +default-system-prompt+)
    ((probe-file value)
     (uiop:read-file-string value :external-format :utf-8))
    (t value)))

(defun resolve-system-prompt-with-appends
    (value appends)
  (let ((base
          (resolve-system-prompt value)))
    (format
     nil "~{~A~^~%~%~}"
     (cons
      base
      (mapcar
       #'resolve-system-prompt
       appends)))))
