(in-package #:pi-cli)

(defun response-text (message)
  (format
   nil "~{~A~^~%~}"
   (loop for block in (pi-ai:assistant-message-content message)
         when (typep block 'pi-ai:text-content)
           collect (pi-ai:text-content-text block))))

(defun dispatch-user-input
    (line prompt-function
     &key command-function template-function)
  (let ((trimmed
          (string-trim
           '(#\Space #\Tab #\Newline #\Return)
           line)))
    (when (zerop (length trimmed))
      (return-from dispatch-user-input
        (values :empty nil)))
    (if (char= (char trimmed 0) #\/)
        (multiple-value-bind (handled command-result)
            (if command-function
                (funcall command-function line)
                (values nil nil))
          (if handled
              (values :command command-result)
              (multiple-value-bind (expanded found-p)
                  (if template-function
                      (funcall template-function line)
                      (values line nil))
                (if found-p
                    (values
                     :prompt
                     (funcall prompt-function expanded))
                    (values :unknown-command nil)))))
        (values :prompt
                (funcall prompt-function line)))))

(defun run-repl (prompt-function
                 &key
                   (input *standard-input*)
                   (output *standard-output*)
                   (render-response t)
                   command-function
                   template-function)
  (labels
      ((run-prompt (text)
         (let ((message (funcall prompt-function text)))
           (when render-response
             (let ((response (response-text message)))
               (format output "~&assistant> ~A~%" response)
               (when
                   (member
                    (pi-ai:assistant-message-stop-reason message)
                    '(:error :aborted))
                 (format
                  output "error> ~A~%"
                  (or
                   (pi-ai:assistant-message-error-message
                    message)
                   (pi-ai:assistant-message-stop-reason
                    message))))))
           message)))
  (loop
    (format output "~&pi> ")
    (finish-output output)
    (let ((line (read-line input nil nil)))
      (unless line
        (return))
      (multiple-value-bind (kind result)
          (dispatch-user-input
           line #'run-prompt
           :command-function command-function
           :template-function template-function)
        (declare (ignore result))
        (when (eq kind :unknown-command)
          (format output
                  "error> Unknown command~%"))))
    (finish-output output))))
