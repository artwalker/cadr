(defpackage #:cadr-agent/tests
  (:use #:cl #:fiveam)
  (:import-from #:cadr-agent
                #:agent-event-message
                #:agent-event-tool-call
                #:agent-event-tool-result
                #:agent-event-type
                #:agent-messages
                #:agent-prompt
                #:make-agent
                #:make-tool-registry
                #:register-tool)
  (:import-from #:cadr-ai
                #:assistant-message-content
                #:assistant-message-stop-reason
                #:make-assistant-message
                #:make-model
                #:make-stream-event
                #:make-text-content
                #:make-tool
                #:make-tool-call
                #:stream-event-type
                #:text-content-text
                #:tool-result-message
                #:tool-result-message-content
                #:tool-result-message-is-error
                #:tool-result-message-tool-call-id)
  (:export #:run-tests))

(in-package #:cadr-agent/tests)

(def-suite cadr-agent-suite)
(in-suite cadr-agent-suite)

(defun run-tests ()
  (run! 'cadr-agent-suite))
