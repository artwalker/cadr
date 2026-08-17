(in-package #:cadr-ai/tests)
(in-suite cadr-ai-suite)

(test usage-defaults-and-total
  (let ((usage (cadr-ai:make-usage :input 7
                                 :output 5
                                 :cache-read 3
                                 :cache-write 2)))
    (is (= 7 (usage-input usage)))
    (is (= 5 (usage-output usage)))
    (is (= 3 (usage-cache-read usage)))
    (is (= 2 (usage-cache-write usage)))
    (is (= 17 (usage-total usage)))))

(test constructors-retain-unified-message-data
  (let* ((block (make-text-content :text "hello" :signature "sig"))
         (message (cadr-ai:make-assistant-message
                   :content (list block)
                   :api :openai-responses
                   :provider :openai
                   :model "gpt-test"
                   :stop-reason :stop
                   :timestamp 42)))
    (is (string= "hello" (first-text message)))
    (is (eq :stop (assistant-message-stop-reason message)))
    (is (= 0 (usage-total (assistant-message-usage message))))))

(test assistant-message-constructor-is-the-defstruct-owner
  (is (null (fboundp 'cadr-ai::%make-assistant-message)))
  (let ((message (cadr-ai:make-assistant-message :model "owned")))
    (is (string= "owned" (cadr-ai:assistant-message-model message)))
    (is (eq :pending
            (cadr-ai:assistant-message-stop-reason message)))))
