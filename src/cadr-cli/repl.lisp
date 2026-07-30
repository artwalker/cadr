(in-package #:cadr-cli)

(defun response-text (message)
  (format
   nil "~{~A~^~%~}"
   (loop for block in (cadr-ai:assistant-message-content message)
         when (typep block 'cadr-ai:text-content)
           collect (cadr-ai:text-content-text block))))

(defun dispatch-user-input
    (line prompt-function
     &key command-function template-function
       bash-function)
  (let ((trimmed
          (string-trim
           '(#\Space #\Tab #\Newline #\Return)
           line)))
    (when (zerop (length trimmed))
      (return-from dispatch-user-input
        (values :empty nil)))
    (cond
      ((and bash-function
            (char= (char trimmed 0) #\!))
       (let* ((exclude-p
                (and (> (length trimmed) 1)
                     (char= (char trimmed 1)
                            #\!)))
              (start (if exclude-p 2 1))
              (command
                (string-left-trim
                 '(#\Space #\Tab)
                 (subseq trimmed start))))
         (if (zerop (length command))
             (values :empty nil)
             (values
              :bash
              (funcall
               bash-function command exclude-p)))))
      ((char= (char trimmed 0) #\/)
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
                   (values :unknown-command nil))))))
      (t
       (values :prompt
               (funcall prompt-function line))))))

(defun run-repl (prompt-function
                 &key
                   (input *standard-input*)
                   (output *standard-output*)
                   (render-response t)
                   command-function
                   template-function
                   bash-function)
  (labels
      ((run-prompt (text)
         (let ((message (funcall prompt-function text)))
           (when render-response
             (let ((response (response-text message)))
               (format output "~&assistant> ~A~%" response)
               (when
                   (member
                    (cadr-ai:assistant-message-stop-reason message)
                    '(:error :aborted))
                 (format
                  output "error> ~A~%"
                  (or
                   (cadr-ai:assistant-message-error-message
                    message)
                   (cadr-ai:assistant-message-stop-reason
                    message))))))
           message)))
  (loop
    (format output "~&cadr> ")
    (finish-output output)
    (let ((line (read-line input nil nil)))
      (unless line
        (return))
      (multiple-value-bind (kind result)
          (dispatch-user-input
           line #'run-prompt
           :command-function command-function
           :template-function template-function
           :bash-function bash-function)
        (when (eq kind :unknown-command)
          (format output
                  "error> Unknown command~%"))
        (when (eq kind :bash)
          (format output "~A~%" result))))
    (finish-output output))))
