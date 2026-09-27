(in-package #:cadr-agent/tests)
(in-suite cadr-agent-suite)

(test goal24-session-append-usage-round-trips-kind-and-note
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((session
             (cadr-agent:create-session
              :directory sessions
              :cwd cwd
              :id "usage-rt"
              :timestamp 100))
           (usage
             (cadr-ai:make-usage
              :input 12 :output 3 :total 15
              :cache-read 4 :cache-write 1))
           path loaded entry)
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-assistant-message
        :content
        (list
         (cadr-ai:make-text-content :text "hi"))
        :api :openai-responses
        :provider :openai
        :model "mock"
        :stop-reason :stop
        :timestamp 101))
      (cadr-agent:session-append-usage
       session "cache_warm" "openai" "gpt-test" usage
       :note "warm after resume")
      (setf path (cadr-agent:session-path session)
            loaded (cadr-agent:load-session path)
            entry
            (find :usage (cadr-agent:session-entries loaded)
                  :key #'cadr-agent:session-entry-type))
      (is (not (null entry)))
      (is (string=
           "cache_warm"
           (cadr-agent:session-entry-kind entry)))
      (is (string=
           "openai"
           (cadr-agent:session-entry-provider entry)))
      (is (string=
           "gpt-test"
           (cadr-agent:session-entry-model-id entry)))
      (is (string=
           "warm after resume"
           (cadr-agent:session-entry-note entry)))
      (is (typep
           (cadr-agent:session-entry-usage entry)
           'cadr-ai:usage))
      (is (= 12
             (cadr-ai:usage-input
              (cadr-agent:session-entry-usage entry))))
      (is (= 4
             (cadr-ai:usage-cache-read
              (cadr-agent:session-entry-usage entry)))))))

(test goal24-session-messages-omit-usage-entries
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((session
             (cadr-agent:create-session
              :directory sessions
              :cwd cwd
              :id "usage-ctx"
              :timestamp 100))
           before
           after)
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-user-message
        :content "ask" :timestamp 101))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-assistant-message
        :content
        (list
         (cadr-ai:make-text-content :text "ans"))
        :api :openai-responses
        :provider :openai
        :model "mock"
        :stop-reason :stop
        :timestamp 102))
      (setf before (cadr-agent:session-messages session))
      (cadr-agent:session-append-usage
       session "cache_warm" "openai" "gpt-test"
       (cadr-ai:make-usage :input 1 :output 0 :total 1)
       :note "ignored by context")
      (setf after (cadr-agent:session-messages session))
      (is (= 2 (length before)))
      (is (= 2 (length after)))
      (is (typep (first after) 'cadr-ai:user-message))
      (is (typep (second after) 'cadr-ai:assistant-message))
      (is (string=
           "ask"
           (cadr-ai:user-message-content
            (first after))))
      (is (string=
           "ans"
           (cadr-ai:text-content-text
            (first
             (cadr-ai:assistant-message-content
              (second after)))))))))

(test goal24-load-session-accepts-usage-jsonl-line
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((path
             (merge-pathnames "hand-usage.jsonl" sessions))
           loaded entry)
      (with-open-file
          (stream path
                  :direction :output
                  :if-exists :supersede
                  :if-does-not-exist :create)
        (write-line
         "{\"type\":\"session\",\"version\":3,\"id\":\"hand-usage\",\"timestamp\":\"1970-01-01T00:00:00.100Z\",\"cwd\":\"/tmp\"}"
         stream)
        (write-line
         "{\"type\":\"message\",\"id\":\"aaaaaaaa\",\"parentId\":null,\"timestamp\":\"1970-01-01T00:00:00.101Z\",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"x\"}],\"api\":\"openai-responses\",\"provider\":\"openai\",\"model\":\"mock\",\"usage\":{\"input\":0,\"output\":0,\"cacheRead\":0,\"cacheWrite\":0,\"total\":0,\"cost\":{\"input\":0,\"output\":0,\"cacheRead\":0,\"cacheWrite\":0,\"total\":0}},\"stopReason\":\"stop\",\"timestamp\":101}}"
         stream)
        (write-line
         "{\"type\":\"usage\",\"id\":\"bbbbbbbb\",\"parentId\":\"aaaaaaaa\",\"timestamp\":\"1970-01-01T00:00:00.102Z\",\"kind\":\"cache_warm\",\"provider\":\"openai\",\"model\":\"gpt-test\",\"usage\":{\"input\":9,\"output\":1,\"cacheRead\":2,\"cacheWrite\":0,\"total\":10,\"cost\":{\"input\":0,\"output\":0,\"cacheRead\":0,\"cacheWrite\":0,\"total\":0}},\"note\":\"from file\"}"
         stream))
      (setf loaded (cadr-agent:load-session path)
            entry
            (find :usage (cadr-agent:session-entries loaded)
                  :key #'cadr-agent:session-entry-type))
      (is (not (null loaded)))
      (is (not (null entry)))
      (is (string=
           "cache_warm"
           (cadr-agent:session-entry-kind entry)))
      (is (string=
           "from file"
           (cadr-agent:session-entry-note entry)))
      (is (= 9
             (cadr-ai:usage-input
              (cadr-agent:session-entry-usage entry)))))))
