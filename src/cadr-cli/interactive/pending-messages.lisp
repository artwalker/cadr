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
               (component-text-line
                (cadr-tui:theme-foreground
                 :dim text :enabled-p t)
                width)))
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
             (key-display-text
              "app.message.dequeue")
             "Alt+Up")))))))))
