(in-package #:cadr-cli)

(defun split-extension-command (line)
  (let* ((trimmed
           (string-trim
            '(#\Space #\Tab #\Newline #\Return)
            line))
         (separator
           (position-if
            (lambda (character)
              (member character
                      '(#\Space #\Tab #\Newline #\Return)))
            trimmed)))
    (values
     (if separator
         (subseq trimmed 0 separator)
         trimmed)
     (if separator
         (string-left-trim
          '(#\Space #\Tab #\Newline #\Return)
          (subseq trimmed separator))
         ""))))

(defun handle-extension-command (line manager)
  (multiple-value-bind (command arguments)
      (split-extension-command line)
    (cond
      ((string= command "/reload")
       (let ((report
               (reload-cli-extensions manager)))
         (extension-manager-notify
          manager
          (format nil
                  "Reloaded ~D extension~:P; ~D error~:P"
                  (getf report :active)
                  (length (getf report :errors)))
          (if (getf report :errors)
              :warning
              :info)))
       t)
      ((and
        (plusp (length command))
        (char= (char command 0) #\/))
       (cadr-agent::invoke-extension-command
        (cli-extension-manager-host manager)
        (subseq command 1)
        arguments))
      (t nil))))

(defun expand-cli-extension-prompt
    (manager text)
  (cadr-agent::expand-extension-prompt
   (cli-extension-manager-host manager)
   text))

(defun expand-cli-slash-prompt
    (manager text skills prompts)
  (multiple-value-bind (expanded found-p)
      (expand-cli-extension-prompt manager text)
    (when found-p
      (return-from expand-cli-slash-prompt
        (values expanded t)))
    (multiple-value-bind (skill-text skill-p)
        (cadr-agent::expand-skill-command-text
         text skills)
      (when skill-p
        (return-from expand-cli-slash-prompt
          (values skill-text t)))
      (multiple-value-bind (prompt-text prompt-p)
          (cadr-agent::expand-prompt-template-text
           text prompts)
        (if prompt-p
            (values prompt-text t)
            (values text t))))))

;;; Git package installation
