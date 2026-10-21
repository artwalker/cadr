(in-package #:cadr-agent/tests)

(in-suite cadr-agent-suite)

(test assistant-duration-round-trips-in-session-json
  (let* ((message
           (cadr-ai:make-assistant-message
            :api :faux
            :provider :faux
            :model "faux-1"
            :content
            (list (cadr-ai:make-text-content :text "ok"))
            :stop-reason :stop
            :duration-ms 1300
            :timestamp 10))
         (restored
           (cadr-agent::message-from-json
            (cadr-agent::message-to-json message)))
         (buffer (cadr-agent::make-session-octet-buffer)))
    (is (= 1300
           (cadr-ai:assistant-message-duration-ms restored)))
    (cadr-agent::write-session-message message buffer)
    (let* ((text
             (sb-ext:octets-to-string
              buffer :external-format :utf-8))
           (from-octets
             (cadr-agent::message-from-json
              (cadr-ai::parse-json text))))
      (is (< (search "\"durationMs\"" text)
             (search "\"model\"" text)))
      (is (= 1300
             (cadr-ai:assistant-message-duration-ms from-octets))))
    (is (null
         (cadr-ai:assistant-message-duration-ms
          (cadr-agent::message-from-json
           (cadr-agent::message-to-json
            (cadr-ai:make-assistant-message
             :api :faux
             :provider :faux
             :model "faux-1"
             :stop-reason :stop
             :timestamp 10))))))))
