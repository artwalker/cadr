(load (merge-pathnames "support.lisp" *load-truename*))

(defun example-notify-terminal (title body)
  (cond
    ((uiop:getenv "WT_SESSION")
     (ignore-errors
       (uiop:launch-program
        (list
         "powershell.exe" "-NoProfile" "-Command"
         (format nil
                 "[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > $null; $xml = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText01); $xml.GetElementsByTagName('text')[0].AppendChild($xml.CreateTextNode('~A')) > $null; [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('~A').Show([Windows.UI.Notifications.ToastNotification]::new($xml))"
                 body title))
        :output :interactive :error-output :interactive)))
    ((uiop:getenv "KITTY_WINDOW_ID")
     (format *standard-output* "~C]99;i=1:d=0;~A~C\\~C]99;i=1:p=body;~A~C\\"
             #\Escape title #\Escape #\Escape body #\Escape)
     (finish-output *standard-output*))
    (t
     (format *standard-output* "~C]777;notify;~A;~A~C"
             #\Escape title body #\Bell)
     (finish-output *standard-output*))))

(cadr-agent:define-event-hook
 :agent-end
 :handler
 (lambda (event context)
   (declare (ignore event context))
   (example-notify-terminal "Pi" "Ready for input")))
