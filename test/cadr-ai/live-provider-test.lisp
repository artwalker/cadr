(in-package #:cadr-ai/live-tests)
(in-suite cadr-ai-live-suite)

(defun live-environment-value (name)
  (let ((value (uiop:getenv name)))
    (and value
         (let ((trimmed
                 (string-trim
                  '(#\Space #\Tab #\Newline #\Return)
                  value)))
           (and (plusp (length trimmed))
                trimmed)))))

(defun run-live-stream
    (provider-id api-key model-id messages
     &key reasoning)
  (multiple-value-bind (provider model)
      (cadr-ai:instantiate-provider
       provider-id
       :api-key api-key
       :model-id model-id)
    (let ((events nil))
      (values
       (cadr-ai:stream-chat
        provider model
        (cadr-ai:make-context
         :system-prompt
         "Follow the requested output format exactly and do not call tools."
         :messages messages)
        (lambda (event)
          (push event events))
        :reasoning reasoning)
       (nreverse events)))))

(defun live-thinking-text (message)
  (let ((block
          (find-if
           (lambda (item)
             (typep item 'cadr-ai:thinking-content))
           (cadr-ai:assistant-message-content message))))
    (and block
         (cadr-ai:thinking-content-thinking block))))

(defun assert-live-stream-result
    (message events expected)
  (is (eq :stop
          (cadr-ai:assistant-message-stop-reason
           message)))
  (is (string=
       expected
       (string-trim
        '(#\Space #\Tab #\Newline #\Return)
        (or (first-text message) ""))))
  (is (plusp
       (cadr-ai:usage-total
        (cadr-ai:assistant-message-usage
         message))))
  (is (eq :start
          (cadr-ai:stream-event-type
           (first events))))
  (is (eq :done
          (cadr-ai:stream-event-type
           (car (last events))))))

(test live-deepseek-chat-completions-streams
  (let ((api-key
          (live-environment-value
           "DEEPSEEK_API_KEY")))
    (if (not api-key)
        (skip "DEEPSEEK_API_KEY is not set")
        (multiple-value-bind (message events)
            (run-live-stream
             :deepseek api-key "deepseek-v4-flash"
             (list
              (cadr-ai:make-user-message
               :content
               "Reply with exactly DEEPSEEK_OK and nothing else.")))
          (assert-live-stream-result
           message events "DEEPSEEK_OK")))))

(test live-anthropic-stream-preserves-two-turn-context
  (let ((api-key
          (live-environment-value
           "ANTHROPIC_API_KEY")))
    (if (not api-key)
        (skip "ANTHROPIC_API_KEY is not set")
        (let ((first-user
                (cadr-ai:make-user-message
                 :content
                 "Reply with exactly FIRST_OK and nothing else.")))
          (multiple-value-bind (first-message first-events)
              (run-live-stream
               :anthropic api-key "claude-opus-4-8"
               (list first-user))
            (assert-live-stream-result
             first-message first-events "FIRST_OK")
            (multiple-value-bind (second-message second-events)
                (run-live-stream
                 :anthropic api-key "claude-opus-4-8"
                 (list
                  first-user
                  first-message
                  (cadr-ai:make-user-message
                   :content
                   "Repeat the exact token from your immediately preceding assistant reply, followed by :SECOND_OK, and nothing else.")))
              (assert-live-stream-result
               second-message second-events
               "FIRST_OK:SECOND_OK")))))))

(test live-opencode-go-mimo-stream-emits-thinking
  (let ((credential
          (cadr-live-test-support:prepare-opencode-go-credential)))
    (if
        (not
         (typep credential
                'cadr-ai:api-key-credential))
        (skip "OpenCode Go API key is not configured")
        (multiple-value-bind (message events)
            (run-live-stream
             :opencode-go
             (cadr-ai:api-key-credential-key credential)
             "mimo-v2.5"
             (list
              (cadr-ai:make-user-message
               :content
               "Think through why 17 is prime, then reply with one short sentence."))
             :reasoning :medium)
          (is (eq :stop
                  (cadr-ai:assistant-message-stop-reason
                   message)))
          (is (find :thinking-start events
                    :key #'cadr-ai:stream-event-type)
              "opencode-go mimo-v2.5 stream had no :thinking-start: ~S"
              (mapcar #'cadr-ai:stream-event-type events))
          (is (and (stringp (live-thinking-text message))
                   (plusp (length (live-thinking-text message))))
              "opencode-go mimo-v2.5 thinking content was empty: ~S"
              (live-thinking-text message))))))
