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

;;; Git package installation
