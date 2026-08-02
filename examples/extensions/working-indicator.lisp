(load (merge-pathnames "support.lisp" *load-truename*))

(defun set-working-indicator-mode (context mode)
  (ecase mode
    (:dot
     (cadr-agent:extension-context-set-working-indicator
      context :frames '("·" "•" "●" "•") :interval-ms 120))
    (:pulse
     (cadr-agent:extension-context-set-working-indicator
      context :frames '("░" "▒" "▓" "█" "▓" "▒") :interval-ms 90))
    (:none
     (cadr-agent:extension-context-set-working-indicator
      context :frames '("") :interval-ms 100))
    (:spinner
     (cadr-agent:extension-context-set-working-indicator
      context :frames '("⠋" "⠙" "⠹" "⠸") :interval-ms 80))
    (:reset
     (cadr-agent:extension-context-set-working-indicator context))))

(cadr-agent:define-event-hook
 :session-start
 :handler (lambda (event context)
            (declare (ignore event))
            (set-working-indicator-mode context :dot)))

(cadr-agent:define-command
 "working-indicator"
 :description "Set the working indicator: dot, pulse, none, spinner, reset"
 :handler
 (lambda (arguments context)
   (let ((mode (find-symbol (string-upcase (example-trim arguments)) :keyword)))
     (if (member mode '(:dot :pulse :none :spinner :reset))
         (progn
           (set-working-indicator-mode context mode)
           (cadr-agent:extension-context-set-status
            context "working-indicator" (format nil "Indicator: ~(~A~)" mode)))
         (cadr-agent:extension-context-notify
          context "Usage: /working-indicator [dot|pulse|none|spinner|reset]"
          :level :error)))))
