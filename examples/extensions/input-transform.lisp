(load (merge-pathnames "support.lisp" *load-truename*))

(cadr-agent:define-event-hook
 :input
 :handler
 (lambda (event context)
   (let* ((payload (cadr-agent:extension-event-payload event))
          (text (getf payload :text))
          (source (getf payload :source)))
     (cond
       ((eq source :extension) '(:action :continue))
       ((uiop:string-prefix-p "?quick " text)
        (let ((query (example-trim (subseq text 7))))
          (if (zerop (length query))
              (progn
                (cadr-agent:extension-context-notify
                 context "Usage: ?quick <question>" :level :warning)
                '(:action :handled))
              (list :action :transform
                    :text (format nil
                                  "Respond briefly in 1-2 sentences: ~A"
                                  query)))))
       ((string-equal text "ping")
        (cadr-agent:extension-context-notify context "pong")
        '(:action :handled))
       ((string-equal text "time")
        (cadr-agent:extension-context-notify
         context (multiple-value-bind (second minute hour day month year)
                     (decode-universal-time (get-universal-time))
                   (format nil "~4,'0D-~2,'0D-~2,'0D ~2,'0D:~2,'0D:~2,'0D"
                           year month day hour minute second)))
        '(:action :handled))
       (t '(:action :continue))))))
