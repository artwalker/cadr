(in-package #:cl-user)

(cadr-agent:define-event-hook
 :input
 :handler
 (lambda (event context)
   (declare (ignore event))
   (format
    *error-output*
    "rpc-ui-diag: hook-start thread=~A~%"
    (sb-thread:thread-name sb-thread:*current-thread*))
   (force-output *error-output*)
   (cadr-agent:extension-context-notify
    context "rpc-notify" :level :warning)
   (cadr-agent:extension-context-set-status
    context "rpc" "waiting")
   (cadr-agent:extension-context-set-widget
    context "rpc" '("one" "two")
    :placement :below-editor)
   (cadr-agent:extension-context-set-title
    context "RPC title")
   (cadr-agent:extension-context-set-editor-text
    context "draft")
   (unless
       (null
        (cadr-agent:extension-context-input
         context "Timeout" :timeout-ms 20))
     (error "RPC UI timeout did not return NIL"))
   (let ((choice
           (cadr-agent:extension-context-select
            context "Pick" '("alpha" "beta")
            :timeout-ms 2000))
         (confirmed
           (progn
             (format *error-output* "rpc-ui-diag: hook-call confirm~%")
             (force-output *error-output*)
             (cadr-agent:extension-context-confirm
              context "Confirm" "Continue?"
              :timeout-ms 2000)))
         (input
           (cadr-agent:extension-context-input
            context "Input"
            :placeholder "value"
            :timeout-ms 2000))
         (edited
           (progn
             (format *error-output* "rpc-ui-diag: hook-call editor~%")
             (force-output *error-output*)
             (cadr-agent:extension-context-editor
              context "Edit" :prefill "before"))))
     (unless
         (and
          (string= choice "beta")
          (not confirmed)
          (string= input "typed")
          (string= edited "after"))
       (error "RPC UI response mismatch")))
   nil))
