(defpackage #:pi-ai/tests
  (:use #:cl #:fiveam)
  (:import-from #:pi-ai
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

(in-package #:pi-ai/tests)

(def-suite pi-ai-suite)
(in-suite pi-ai-suite)

(defun run-tests ()
  (run! 'pi-ai-suite))
