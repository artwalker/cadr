(in-package #:cadr-agent/tests)
(in-suite cadr-agent-suite)

(test goal24-harness-append-usage-fields-and-omits-from-messages
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let ((environment
            (cadr-agent:make-node-execution-env
             :cwd cwd)))
      (dolist
          (storage
           (list
            (cadr-agent:make-memory-session-storage)
            (cadr-agent:create-jsonl-session-storage
             environment
             (merge-pathnames
              "harness-usage.jsonl" sessions)
             :id "harness-usage"
             :cwd cwd)))
        (let* ((session
                 (cadr-agent:make-harness-session
                  :storage storage))
               (usage
                 (cadr-ai:make-usage
                  :input 12 :output 3 :total 15
                  :cache-read 4 :cache-write 1))
               before after entry)
          (cadr-agent:harness-session-append-message
           session
           (cadr-ai:make-user-message
            :content "ask"
            :timestamp 100))
          (cadr-agent:harness-session-append-message
           session
           (cadr-ai:make-assistant-message
            :content
            (list
             (cadr-ai:make-text-content :text "ans"))
            :api :openai-responses
            :provider :openai
            :model "mock"
            :stop-reason :stop
            :timestamp 101))
          (setf before
                (getf
                 (cadr-agent:harness-session-build-context
                  session)
                 :messages))
          (cadr-agent:harness-session-append-usage
           session "cache_warm" "openai" "gpt-test" usage
           :note "warm via harness")
          (setf after
                (getf
                 (cadr-agent:harness-session-build-context
                  session)
                 :messages)
                entry
                (find
                 :usage
                 (cadr-agent:harness-session-entries
                  session)
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
               "warm via harness"
               (cadr-agent:session-entry-note entry)))
          (is (typep
               (cadr-agent:session-entry-usage entry)
               'cadr-ai:usage))
          (is (= 12
                 (cadr-ai:usage-input
                  (cadr-agent:session-entry-usage entry))))
          (is (= 2 (length before)))
          (is (= 2 (length after)))
          (cadr-agent:harness-session-cleanup
           session))))))

(test goal24-harness-append-usage-jsonl-reload
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((environment
             (cadr-agent:make-node-execution-env
              :cwd cwd))
           (path
             (merge-pathnames
              "harness-usage-reload.jsonl" sessions))
           (session
             (cadr-agent:make-harness-session
              :storage
              (cadr-agent:create-jsonl-session-storage
               environment path
               :id "harness-usage-reload"
               :cwd cwd)))
           (usage
             (cadr-ai:make-usage
              :input 9 :output 1 :total 10
              :cache-read 2))
           loaded entry)
      (cadr-agent:harness-session-append-message
       session
       (cadr-ai:make-assistant-message
        :content
        (list
         (cadr-ai:make-text-content :text "x"))
        :api :openai-responses
        :provider :openai
        :model "mock"
        :stop-reason :stop
        :timestamp 101))
      (cadr-agent:harness-session-append-usage
       session "cache_warm" "openai" "gpt-test" usage
       :note "from harness reload")
      (cadr-agent:harness-session-cleanup session)
      (setf loaded
            (cadr-agent:make-harness-session
             :storage
             (cadr-agent:open-jsonl-session-storage
              environment path))
            entry
            (find
             :usage
             (cadr-agent:harness-session-entries loaded)
             :key #'cadr-agent:session-entry-type))
      (is (not (null entry)))
      (is (string=
           "cache_warm"
           (cadr-agent:session-entry-kind entry)))
      (is (string=
           "from harness reload"
           (cadr-agent:session-entry-note entry)))
      (is (= 9
             (cadr-ai:usage-input
              (cadr-agent:session-entry-usage entry))))
      (is
       (= 1
          (length
           (getf
            (cadr-agent:harness-session-build-context
             loaded)
            :messages))))
      (cadr-agent:harness-session-cleanup loaded))))
