(in-package #:pi-cli)

(defparameter +default-system-prompt+
  "You are Pi, a precise coding agent. Inspect before editing, use the provided tools, preserve unrelated changes, run relevant checks, and report results concisely.")

(defun resolve-system-prompt (value)
  (cond
    ((null value) +default-system-prompt+)
    ((probe-file value)
     (uiop:read-file-string value :external-format :utf-8))
    (t value)))
