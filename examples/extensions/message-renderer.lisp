(load (merge-pathnames "support.lisp" *load-truename*))

(defun status-update-level-token (level)
  (cond
    ((string= level "error") :error)
    ((string= level "warn") :warning)
    (t :success)))

(cadr-agent:define-component-message-renderer
 "status-update"
 :renderer
 (lambda (message options theme)
   (let* ((details (getf message :details))
          (level (or (getf details :level) "info"))
          (prefix (format nil "[~:@(~A~)]" level))
          (content (or (getf message :content) ""))
          (colored
            (handler-case
                (example-theme-fg
                 theme (status-update-level-token level) prefix)
              (error () prefix)))
          (text (format nil "~A ~A" colored content)))
     (when (and (getf options :expanded-p) (getf details :timestamp))
       (setf text
             (format nil "~A~%~A" text
                     (handler-case
                         (example-theme-fg
                          theme :dim
                          (format nil "  at ~A"
                                  (example-clock-time-string
                                   (getf details :timestamp))))
                       (error () "")))))
     (cadr-tui:make-text-component
      text
      :padding-x (or (getf options :output-pad) 0)
      :padding-y 1))))

(cadr-agent:define-command
 "status"
 :description "Send a status message (usage: /status [warn|error] message)"
 :handler
 (lambda (arguments context)
   (declare (ignore context))
   (let* ((text (example-trim arguments))
          (words
            (remove ""
                    (uiop:split-string
                     text :separator '(#\Space #\Tab #\Newline #\Return))
                    :test #'string=))
          (level-p
            (member (or (first words) "") '("warn" "error")
                    :test #'string=))
          (level (if level-p (first words) "info"))
          (rest-text (format nil "~{~A~^ ~}" (rest words)))
          (content
            (cond
              ((not level-p) text)
              ((plusp (length rest-text)) rest-text)
              (t "Status update"))))
     (cadr-agent:extension-api-send-message
      *example-api*
      (list :custom-type "status-update"
            :content content
            :details
            (list :level level :timestamp (example-unix-milliseconds))
            :display-p t)))))
