(in-package #:cadr-tui)

(defun fit-status (text width)
  (multiple-value-bind (prefix used)
      (slice-to-width text width)
    (concatenate
     'string prefix
     (make-string
      (max 0 (- width used))
     :initial-element #\Space))))

(defun format-footer-tokens (count)
  (cond
    ((< count 1000)
     (format nil "~D" count))
    ((< count 10000)
     (format nil "~,1Fk"
             (/ count 1000d0)))
    ((< count 1000000)
     (format nil "~Dk"
             (floor (+ count 500) 1000)))
    ((< count 10000000)
     (format nil "~,1FM"
             (/ count 1000000d0)))
    (t
     (format nil "~DM"
             (floor (+ count 500000)
                    1000000)))))

(defun footer-context-text
    (percent context-window
     auto-compact-p ansi-theme-p)
  (let* ((display
           (format
            nil "~A/~A~:[~; (auto)~]"
            (if (numberp percent)
                (format nil "~,1F%"
                        (coerce percent
                                'double-float))
                "?")
            (format-footer-tokens
             (or context-window 0))
            auto-compact-p))
         (token
           (cond
             ((and (numberp percent)
                   (> percent 90))
              :error)
             ((and (numberp percent)
                   (> percent 70))
              :warning)
             (t :dim))))
    (theme-foreground
     token display
     :enabled-p ansi-theme-p)))

(defun sanitize-footer-status (text)
  (string-trim
   '(#\Space #\Tab)
   (cl-ppcre:regex-replace-all
    "[\\r\\n\\t ]+" (or text "") " ")))

(defun render-footer
    (width
     &key cwd branch session-name
       model provider thinking
       (input 0) (output 0)
       (cache-read 0) (cache-write 0)
       latest-cache-hit-rate
       cost subscription-p
       context-percent
       (context-window 0)
       (auto-compact-p t)
       multiple-providers-p
       statuses
       (ansi-theme-p nil))
  (let* ((location
           (format
            nil "~A~@[ (~A)~]~@[ • ~A~]"
            (or cwd "")
            branch session-name))
         (parts nil))
    (when (plusp input)
      (push
       (format nil "↑~A"
               (format-footer-tokens input))
       parts))
    (when (plusp output)
      (push
       (format nil "↓~A"
               (format-footer-tokens output))
       parts))
    (when (plusp cache-read)
      (push
       (format nil "R~A"
               (format-footer-tokens cache-read))
       parts))
    (when (plusp cache-write)
      (push
       (format nil "W~A"
               (format-footer-tokens cache-write))
       parts))
    (when
        (and
         (or (plusp cache-read)
             (plusp cache-write))
         (numberp latest-cache-hit-rate))
      (push
       (format
        nil "CH~,1F%"
        (coerce latest-cache-hit-rate
                'double-float))
       parts))
    (when (or cost subscription-p)
      (push
       (format
        nil "$~,3F~:[~; (sub)~]"
        (coerce (or cost 0d0)
                'double-float)
        subscription-p)
       parts))
    (setf parts (nreverse parts))
    (let* ((plain-left
             (format nil "~{~A~^ ~}" parts))
           (context
             (footer-context-text
              context-percent context-window
              auto-compact-p ansi-theme-p))
           (left
             (if (plusp
                  (length plain-left))
                 (concatenate
                  'string
                  (theme-foreground
                   :dim plain-left
                   :enabled-p ansi-theme-p)
                  " " context)
                 context))
           (thinking-name
             (and thinking
                  (string-downcase
                   (if (symbolp thinking)
                       (symbol-name thinking)
                       (princ-to-string
                        thinking)))))
           (right-without-provider
             (format
              nil "~A~@[ • ~A~]"
              (or model "no-model")
              (and
               thinking-name
               (if (string= thinking-name
                            "off")
                   "thinking off"
                   thinking-name))))
           (right
             (if
                 (and multiple-providers-p
                      provider)
                 (format nil "(~A) ~A"
                         provider
                         right-without-provider)
                 right-without-provider))
           (left-width (visible-width left))
           (right-width (visible-width right)))
      (when (> left-width width)
        (setf left
              (truncate-to-width
               left width "...")
              left-width
              (visible-width left)))
      (when
          (and
           multiple-providers-p
           (> (+ left-width 2 right-width)
              width))
        (setf right right-without-provider
              right-width
              (visible-width right)))
      (let* ((available
               (- width left-width 2))
             (visible-right
               (if (plusp available)
                   (truncate-to-width
                    right available "" nil)
                   ""))
             (visible-right-width
               (visible-width visible-right))
             (second-line
               (if (plusp visible-right-width)
                   (concatenate
                    'string left
                    (make-string
                     (max
                      2
                      (- width left-width
                         visible-right-width))
                     :initial-element #\Space)
                    (theme-foreground
                     :dim visible-right
                     :enabled-p
                     ansi-theme-p))
                   left))
             (lines
               (list
                (truncate-to-width
                 (theme-foreground
                  :dim location
                  :enabled-p ansi-theme-p)
                 width "...")
                (truncate-to-width
                 second-line width "" nil))))
        (if statuses
            (append
             lines
             (list
              (truncate-to-width
               (format
                nil "~{~A~^ ~}"
                (loop for entry in
                        (sort
                         (copy-list statuses)
                         #'string<
                         :key #'car)
                      collect
                      (sanitize-footer-status
                       (cdr entry))))
               width
               (theme-foreground
                :dim "..."
                :enabled-p ansi-theme-p)
               nil)))
            lines)))))

(defun render-status-bar
    (width &key model (input 0) (output 0)
                  (cache 0) cost session)
  (second
   (render-footer
    width
    :session-name session
    :model model
    :input input
    :output output
    :cache-read cache
    :cost cost)))
