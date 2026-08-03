(in-package #:cadr-cli)

(defun tui-queued-message-text (message)
  (typecase message
    (cadr-ai:user-message
     (cadr-ai::content-text
      (cadr-ai:user-message-content message)))
    (string message)
    (t (princ-to-string message))))

(defun restore-queued-messages-to-editor (editor queued)
  (let ((count (length queued)))
    (when (plusp count)
      (let* ((queued-text
               (format nil "~{~A~^~%~%~}" queued))
             (current
               (cadr-tui:editor-text editor))
             (combined
               (if
                   (zerop
                    (length
                     (string-trim
                      '(#\Space #\Tab #\Newline #\Return)
                      current)))
                   queued-text
                   (format nil "~A~%~%~A"
                           queued-text current))))
        (tui-editor-component-set-text editor combined)))
    count))

(defun render-tui-pending-message-lines (state width)
  (let ((steering
          (tui-state-steering-messages state))
        (follow-up
          (tui-state-follow-up-messages state)))
    (when (or steering follow-up)
      (flet ((pending-line (text)
               (cadr-tui:theme-foreground
                :dim
                (cadr-tui:truncate-to-width
                 (concatenate 'string " " text)
                 width "")
                :enabled-p t)))
        (nconc
         (list "")
         (mapcar
          (lambda (message)
            (pending-line
             (format nil "Steering: ~A"
                     (tui-queued-message-text message))))
          steering)
         (mapcar
          (lambda (message)
            (pending-line
             (format nil "Follow-up: ~A"
                     (tui-queued-message-text message))))
          follow-up)
         (list
          (pending-line
           (format
            nil "↳ ~A to edit all queued messages"
            (or
             (first
              (cadr-tui:keybinding-keys
               (cadr-tui:get-keybindings)
               "app.message.dequeue"))
             "alt+up")))))))))
