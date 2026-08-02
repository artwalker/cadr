(load (merge-pathnames "support.lisp" *load-truename*))

(defvar *rpc-demo-turns* 0)

(cadr-agent:define-event-hook
 :session-start
 :handler
 (lambda (event context)
   (cadr-agent:extension-context-set-title
    context
    (if (eq (example-event-value event :reason) :new)
        "cadr RPC Demo (new session)"
        "cadr RPC Demo"))
   (cadr-agent:extension-context-set-widget
    context "rpc-demo" '("--- RPC Extension UI Demo ---" "Loaded and ready."))
   (cadr-agent:extension-context-set-status context "rpc-demo" "Turns: 0")))

(cadr-agent:define-event-hook
 :turn-start
 :handler
 (lambda (event context)
   (declare (ignore event))
   (incf *rpc-demo-turns*)
   (cadr-agent:extension-context-set-status
    context "rpc-demo" (format nil "Turn ~D running..." *rpc-demo-turns*))))

(cadr-agent:define-event-hook
 :turn-end
 :handler
 (lambda (event context)
   (declare (ignore event))
   (cadr-agent:extension-context-set-status
    context "rpc-demo" (format nil "Turn ~D done" *rpc-demo-turns*))))

(cadr-agent:define-event-hook
 :tool-call-before
 :handler
 (lambda (event context)
   (let ((call (cadr-agent:extension-event-tool-call event)))
     (when (and (string= (cadr-ai:tool-call-name call) "bash")
                (cl-ppcre:scan
                 "(?i)(\\brm\\s+(-rf?|--recursive)|\\bsudo\\b)"
                 (or (cadr-ai::json-get
                      (cadr-ai:tool-call-arguments call) "command") "")))
       (if (not (cadr-agent:extension-context-has-ui-p context))
           (cadr-agent:make-extension-hook-result
            :block-p t :reason "Dangerous command blocked (no UI)")
           (let ((choice
                   (cadr-agent:extension-context-select
                    context "Dangerous command" '("Allow" "Block"))))
             (unless (string= (or choice "") "Allow")
               (cadr-agent:extension-context-notify
                context "Command blocked by user" :level :warning)
               (cadr-agent:make-extension-hook-result
                :block-p t :reason "Blocked by user"))))))))

(cadr-agent:define-event-hook
 :session-before-switch
 :handler
 (lambda (event context)
   (when (and (eq (example-event-value event :reason) :new)
              (cadr-agent:extension-context-has-ui-p context)
              (not (cadr-agent:extension-context-confirm
                    context "Clear session?" "All messages will be lost.")))
     (cadr-agent:extension-context-notify context "Clear cancelled")
     '(:cancel-p t))))

(cadr-agent:define-command
 "rpc-input"
 :description "Prompt for text through the active UI bridge"
 :handler
 (lambda (arguments context)
   (declare (ignore arguments))
   (let ((value (cadr-agent:extension-context-input
                 context "Enter a value" :placeholder "type something...")))
     (cadr-agent:extension-context-notify
      context (if value (format nil "You entered: ~A" value) "Input cancelled")))))

(cadr-agent:define-command
 "rpc-editor"
 :description "Open the multi-line editor through the UI bridge"
 :handler
 (lambda (arguments context)
   (declare (ignore arguments))
   (let ((value (cadr-agent:extension-context-editor
                 context "Edit some text" :prefill "Line 1
Line 2
Line 3")))
     (cadr-agent:extension-context-notify
      context
     (if value
          (format nil "Editor submitted (~D lines)"
                  (length (uiop:split-string value :separator '(#\Newline))))
          "Editor cancelled")))))

(cadr-agent:define-command
 "rpc-prefill"
 :description "Prefill the input editor through the UI bridge"
 :handler
 (lambda (arguments context)
   (declare (ignore arguments))
   (cadr-agent:extension-context-set-editor-text
    context "This text was set by the rpc-demo extension.")
   (cadr-agent:extension-context-notify context "Editor prefilled")))
