(load (merge-pathnames "support.lisp" *load-truename*))

(cadr-agent:define-command
 "timed"
 :description "Confirm with a ten-second timeout"
 :handler
 (lambda (arguments context)
   (declare (ignore arguments))
   (cadr-agent:extension-context-notify
    context
    (if (cadr-agent:extension-context-confirm
         context "Timed confirmation" "Confirm?" :timeout-ms 10000)
        "Confirmed by user!" "Cancelled or timed out"))))

(cadr-agent:define-command
 "timed-select"
 :description "Select with a ten-second timeout"
 :handler
 (lambda (arguments context)
   (declare (ignore arguments))
   (let ((choice (cadr-agent:extension-context-select
                  context "Pick an option"
                  '("Option A" "Option B" "Option C")
                  :timeout-ms 10000)))
     (cadr-agent:extension-context-notify
      context (if choice (format nil "Selected: ~A" choice)
                  "Selection cancelled or timed out")))))

(cadr-agent:define-command
 "timed-signal"
 :description "Confirm with an explicitly abortable signal"
 :handler
 (lambda (arguments context)
   (declare (ignore arguments))
   (let ((signal (cadr-agent:make-extension-cancellation-signal)))
     (cadr-agent:extension-context-notify context "Dialog will auto-cancel in 5 seconds...")
     (cadr-agent:extension-context-confirm
      context "Signal confirmation" "Confirm?"
      :signal signal :timeout-ms 5000))))
