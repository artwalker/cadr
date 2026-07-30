(in-package #:cadr-agent/tests)

(cadr-agent:define-tool
 "legacy-echo"
 :description "Legacy extension tool"
 :parameters (object-schema "value")
 :handler
 (lambda (call-id arguments context)
   (declare (ignore call-id))
   (push
    (list
     :tool
     (namestring
      (cadr-agent:extension-context-cwd context))
     (cadr-agent:extension-context-mode context)
     (cadr-agent:extension-context-source-path context)
     (not
      (null
       (cadr-agent:extension-context-agent context)))
     (cadr-agent:extension-context-session context))
    *legacy-extension-observations*)
   (values
    (list
     (cadr-ai:make-text-content
      :text (cadr-ai::json-get arguments "value")))
    nil)))

(cadr-agent:define-command
 "legacy-context"
 :description "Exercise the legacy extension context"
 :handler
 (lambda (arguments context)
   (declare (ignore arguments))
   (cadr-agent:extension-context-notify
    context "legacy-notify" :level :warning)
   (push
    (list
     :command
     (cadr-agent:extension-context-compact
      context :force-p nil))
    *legacy-extension-observations*)
   (cadr-agent:extension-context-reload context)))

(cadr-agent:define-prompt-template
 "legacy-template"
 :description "Legacy template"
 :template "legacy=$1")

(cadr-agent:define-event-hook
 :turn-start
 :priority -20
 :handler
 (lambda (event context)
   (declare (ignore event context))
   (push :turn-start *legacy-extension-observations*)
   (cadr-agent:make-extension-hook-result
    :replacement
    (cadr-ai:make-user-message :content "legacy-user")
    :append-messages
    (list
     (cadr-ai:make-user-message
      :content "legacy-start-extra")))))

(cadr-agent:define-event-hook
 :turn-end
 :handler
 (lambda (event context)
   (declare (ignore context))
   (push
    (list
     :turn-end
     (cadr-agent:extension-event-turn-index event)
     (length
      (cadr-agent:extension-event-tool-results event)))
    *legacy-extension-observations*)
   (cadr-agent:make-extension-hook-result
    :replacement
    (assistant
     (list
      (cadr-ai:make-text-content
       :text "legacy-assistant"))))))

(cadr-agent:define-event-hook
 :tool-call-before
 :priority -20
 :handler
 (lambda (event context)
   (declare (ignore context))
   (let ((call
           (cadr-agent:extension-event-tool-call event)))
     (cadr-agent:make-extension-hook-result
      :replacement
      (cadr-ai:make-tool-call
       :id (cadr-ai:tool-call-id call)
       :name (cadr-ai:tool-call-name call)
       :arguments
       (cadr-ai::json-object
        "value" "legacy-rewritten"))))))

(cadr-agent:define-event-hook
 :tool-call-before
 :priority 0
 :handler
 (lambda (event context)
   (declare (ignore event context))
   (error "legacy-contained-error")))

(cadr-agent:define-event-hook
 :tool-call-before
 :priority 20
 :handler
 (lambda (event context)
   (declare (ignore context))
   (let ((call
           (cadr-agent:extension-event-tool-call event)))
     (push
      (list
       :tool-call-before
       (cadr-ai::json-get
        (cadr-ai:tool-call-arguments call)
        "value"))
      *legacy-extension-observations*)
     (when
         (string=
          "legacy-block"
          (cadr-ai:tool-call-name call))
       (cadr-agent:make-extension-hook-result
        :block-p t
        :reason "legacy-blocked")))))

(cadr-agent:define-event-hook
 :tool-call-after
 :handler
 (lambda (event context)
   (declare (ignore context))
   (let ((result
           (cadr-agent:extension-event-tool-result event)))
     (push :tool-call-after
           *legacy-extension-observations*)
     (cadr-agent:make-extension-hook-result
      :replacement
      (cadr-ai:make-tool-result-message
       :tool-call-id
       (cadr-ai:tool-result-message-tool-call-id
        result)
       :tool-name
       (cadr-ai:tool-result-message-tool-name result)
       :content
       (list
        (cadr-ai:make-text-content
         :text "legacy-after"))
       :is-error nil)))))
