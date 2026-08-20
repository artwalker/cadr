(defpackage #:cadr-ai/tests
  (:use #:cl #:fiveam)
  (:import-from #:cadr-ai
                #:*http-request-function*
                #:assistant-message-content
                #:assistant-message-error-message
                #:assistant-message-response-id
                #:assistant-message-stop-reason
                #:assistant-message-usage
                #:build-request
                #:complete-chat
                #:context
                #:make-anthropic-provider
                #:make-context
                #:make-google-provider
                #:make-bedrock-provider
                #:make-model
                #:make-openai-provider
                #:make-text-content
                #:make-tool
                #:make-user-message
                #:model
                #:parse-complete-response
                #:read-sse-stream
                #:request-spec-headers
                #:request-spec-payload
                #:request-spec-stream-p
                #:request-spec-url
                #:request-sse
                #:sse-event-data
                #:sse-event-event
                #:sse-event-id
                #:stream-chat
                #:stream-event-content
                #:stream-event-delta
                #:stream-event-message
                #:stream-event-reason
                #:stream-event-type
                #:text-content-text
                #:usage-cache-read
                #:usage-cache-write
                #:usage-input
                #:usage-output
                #:usage-reasoning
                #:usage-total)
  (:export #:run-tests))

(in-package #:cadr-ai/tests)

(def-suite cadr-ai-suite)
(in-suite cadr-ai-suite)

(defun run-tests ()
  (run! 'cadr-ai-suite))
