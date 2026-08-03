(in-package #:cadr-cli)

(defparameter +osc-133-start+
  (format nil "~C]133;A~C" #\Escape (code-char 7)))
(defparameter +osc-133-end+
  (format nil "~C]133;B~C" #\Escape (code-char 7)))
(defparameter +osc-133-final+
  (format nil "~C]133;C~C" #\Escape (code-char 7)))

(defun output-padding-string (output-pad)
  (make-string
   (if (member output-pad '(0 1))
       output-pad 1)
   :initial-element #\Space))

(defun render-user-message-lines
    (text width &key (output-pad 1))
  (let* ((padding
           (output-padding-string output-pad))
         (lines
           (cadr-tui:wrap-text
            (concatenate 'string padding text)
            width)))
    (append
     (list
      (concatenate
       'string +osc-133-start+
       (format nil "~C[49m" #\Escape)))
     lines
     (list
      (concatenate
       'string +osc-133-end+
       +osc-133-final+
       (format nil "~C[49m" #\Escape))))))

(defun render-assistant-message-lines
    (blocks width
     &key (output-pad 1)
       thinking-visible-p stop-reason)
  (let ((contains-tool-p nil)
        (thinking-run-p nil)
        (lines nil)
        (padding
          (output-padding-string output-pad)))
    (dolist (block blocks)
      (case (getf block :type)
        (:tool-call
         (setf contains-tool-p t
               thinking-run-p nil))
        (:thinking
         (unless thinking-run-p
           (setf
            lines
            (nconc
             lines
             (cadr-tui:wrap-text
              (concatenate
               'string padding
               (if thinking-visible-p
                   (or (getf block :thinking)
                       "")
                   "Thinking..."))
              width))))
         (setf thinking-run-p t))
        (:text
         (setf thinking-run-p nil)
         (setf
          lines
          (nconc
           lines
           (cadr-tui:wrap-text
            (concatenate
             'string padding
             (or (getf block :text) ""))
            width))))))
    (when (eq stop-reason :length)
      (setf
       lines
       (nconc
        lines
        (cadr-tui:wrap-text
         "Error: maximum output token limit reached; response may be incomplete."
         width))))
    (if contains-tool-p
        lines
        (if lines
            (let ((copy (copy-list lines)))
              (setf
               (first copy)
               (concatenate
                'string +osc-133-start+
                (first copy))
               (car (last copy))
               (concatenate
                'string +osc-133-end+
                +osc-133-final+
                (car (last copy))))
              copy)
            nil))))

