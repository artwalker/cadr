(in-package #:cadr-cli)

(defparameter +default-system-prompt+
  "You are cadr, a precise coding agent. Inspect before editing, use the provided tools, preserve unrelated changes, run relevant checks, and report results concisely.")

(defun resolve-system-prompt
    (value &optional (description "system prompt"))
  (cond
    ((null value) +default-system-prompt+)
    ((probe-file value)
     ;; Baseline core/resource-loader.ts:53-66 resolvePromptInput: an
     ;; existing but unreadable prompt file is a yellow warning and the
     ;; input falls back to literal text; never a raw condition.
     (handler-case
         (uiop:read-file-string value :external-format :utf-8)
       (error (cause)
         (format
          *error-output*
          "~A~%"
          (cli-warning-text
           *error-output*
           (format nil "Warning: Could not read ~A file ~A: ~A"
                   description value
                   ;; String(error) carries the "Error: " prefix.
                   (format nil "Error: ~A"
                           (node-read-error-message value cause)))))
         (finish-output *error-output*)
         value)))
    (t value)))

(defun node-read-error-message (path cause)
  "Map a CL file read failure onto the Node.js error text the baseline
prints (resource-loader.ts:62 / file-processor.ts:80)."
  (cond
    ((uiop:directory-exists-p path)
     "EISDIR: illegal operation on a directory, read")
    ((search "Permission denied" (princ-to-string cause)
             :test #'char-equal)
     (format nil "EACCES: permission denied, open '~A'" path))
    (t
     (princ-to-string cause))))

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
