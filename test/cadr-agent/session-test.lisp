(in-package #:cadr-agent/tests)
(in-suite cadr-agent-suite)

(defmacro with-session-directories ((sessions cwd other-cwd) &body body)
  `(uiop:with-temporary-file
       (:pathname marker :keep t)
     (delete-file marker)
     (let* ((root
              (uiop:ensure-directory-pathname
               (pathname
                (format nil "~A-session-dir/"
                        (namestring marker)))))
            (,sessions (merge-pathnames "sessions/" root))
            (,cwd (merge-pathnames "project-a/" root))
            (,other-cwd (merge-pathnames "project-b/" root)))
       (ensure-directories-exist
        (merge-pathnames "anchor" ,sessions))
       (ensure-directories-exist
        (merge-pathnames "anchor" ,cwd))
       (ensure-directories-exist
        (merge-pathnames "anchor" ,other-cwd))
       (unwind-protect
            (progn ,@body)
         (when (probe-file root)
           (uiop:delete-directory-tree
            root :validate t :if-does-not-exist :ignore))))))

(test session-jsonl-round-trips-all-first-version-message-types
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((session
             (cadr-agent::create-session
              :directory sessions
              :cwd cwd
              :id "roundtrip"
              :timestamp 100))
           (user
             (cadr-ai:make-user-message
              :content "hello" :timestamp 101))
           (assistant-message
             (cadr-ai:make-assistant-message
              :content
              (list
               (cadr-ai:make-text-content :text "thinking done")
               (cadr-ai:make-thinking-content
                :thinking "private thought"
                :signature "sig")
               (cadr-ai:make-tool-call
                :id "call-1"
                :name "read"
                :arguments (cadr-ai::json-object "path" "README.md")))
              :api :anthropic-messages
              :provider :anthropic
              :model "claude-test"
              :response-id "msg-1"
              :usage (cadr-ai:make-usage
                      :input 10 :output 5
                      :cache-read 2 :cache-write 1)
              :stop-reason :tool-use
              :raw-stop-reason "tool_use"
              :timestamp 102))
           (result
             (cadr-ai:make-tool-result-message
              :tool-call-id "call-1"
              :tool-name "read"
              :content
              (list (cadr-ai:make-text-content :text "contents"))
              :details (list :path "README.md" :truncated nil)
              :timestamp 103)))
      (dolist (message (list user assistant-message result))
        (cadr-agent::session-append-message session message))
      (let* ((loaded
               (cadr-agent::load-session
                (cadr-agent::session-path session)))
             (messages (cadr-agent::session-messages loaded))
             (loaded-assistant (second messages)))
        (is (string= "roundtrip"
                     (cadr-agent::session-id loaded)))
        (is (= 3 (length messages)))
        (is (typep (first messages) 'cadr-ai:user-message))
        (is (typep loaded-assistant 'cadr-ai:assistant-message))
        (is (typep (third messages)
                   'cadr-ai:tool-result-message))
        (is (= 18
               (cadr-ai:usage-total
                (cadr-ai:assistant-message-usage
                 loaded-assistant))))
        (is (typep
             (third
              (cadr-ai:assistant-message-content
               loaded-assistant))
             'cadr-ai:tool-call))
        (is (not
             (search
              "api-key"
              (uiop:read-file-string
               (cadr-agent::session-path session)
               :external-format :utf-8))))))))

(test session-loader-skips-malformed-jsonl-records-including-the-final-tail
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let ((session
            (cadr-agent::create-session
             :directory sessions :cwd cwd :id "tail")))
      (cadr-agent::session-append-message
       session (cadr-ai:make-user-message :content "kept"))
      (cadr-agent::session-append-message
       session
       (cadr-ai:make-assistant-message
        :content (list (cadr-ai:make-text-content :text "answer"))
        :api :openai-responses
        :provider :openai
        :model "mock"
        :stop-reason :stop))
      (with-open-file
          (stream (cadr-agent::session-path session)
                  :direction :output
                  :if-exists :append
                  :external-format :utf-8)
        (write-string "{\"type\":\"message\"" stream))
      (is (= 2
             (length
              (cadr-agent::session-messages
               (cadr-agent::load-session
                (cadr-agent::session-path session)))))))
    (let ((session
            (cadr-agent::create-session
             :directory sessions :cwd cwd :id "middle")))
      (cadr-agent::session-append-message
       session
       (cadr-ai:make-assistant-message
        :content (list (cadr-ai:make-text-content :text "before"))
        :api :openai-responses
        :provider :openai
        :model "mock"
        :stop-reason :stop))
      (with-open-file
          (stream (cadr-agent::session-path session)
                  :direction :output
                  :if-exists :append
                  :external-format :utf-8)
        (format stream "{broken}~%"))
      (cadr-agent::session-append-message
       session (cadr-ai:make-user-message :content "after"))
      (is
       (= 2
          (length
           (cadr-agent::session-messages
            (cadr-agent::load-session
             (cadr-agent::session-path session)))))))))

(test continue-session-selects-latest-canonical-matching-cwd
  (with-session-directories (sessions cwd other-cwd)
    (dolist
        (session
         (list
          (cadr-agent::create-session
           :directory sessions :cwd cwd :id "older" :timestamp 10)
          (cadr-agent::create-session
           :directory sessions :cwd other-cwd :id "other" :timestamp 30)
          (cadr-agent::create-session
           :directory sessions :cwd cwd :id "newer" :timestamp 20)))
      (cadr-agent::session-append-message
       session
       (cadr-ai:make-assistant-message
        :content (list (cadr-ai:make-text-content :text "persist"))
        :api :openai-responses
        :provider :openai
        :model "mock"
        :stop-reason :stop)))
    (let ((continued
            (cadr-agent::continue-session
             :directory sessions :cwd cwd)))
      (is (string= "newer"
                   (cadr-agent::session-id continued))))))

(test continue-session-rejects-invalid-session-headers
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (with-open-file
        (stream (merge-pathnames "invalid.jsonl" sessions)
                :direction :output
                :if-exists :supersede
                :if-does-not-exist :create
                :external-format :utf-8)
      (format stream
              "{\"type\":\"session\",\"version\":99,\"id\":\"bad\",\"timestamp\":1,\"cwd\":\"~A\"}~%"
              (cadr-agent::canonical-session-cwd cwd)))
    (signals cadr-agent::session-error
      (cadr-agent::continue-session
       :directory sessions :cwd cwd))))

(test agent-flushes-final-user-and-assistant-messages-to-session
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((session
             (cadr-agent::create-session
              :directory sessions :cwd cwd :id "agent"))
           (*responses*
             (list
              (assistant
               (list (make-text-content :text "persisted")))))
           (*contexts* nil))
      (declare (special *responses* *contexts*))
      (let ((agent
              (make-agent
               :provider :mock
               :model (mock-model)
               :session session
               :stream-function
               (faux-stream '*responses* '*contexts*))))
        (agent-prompt agent "save me")
        (let ((loaded
                (cadr-agent::load-session
                 (cadr-agent::session-path session))))
          (is (= 2
                 (length
                  (cadr-agent::session-messages loaded))))
          (is (string=
               "save me"
               (cadr-ai:user-message-content
               (first
                 (cadr-agent::session-messages loaded))))))))))

(test session-message-ingestion-normalizes-null-or-missing-content
  (let* ((usage
           (cadr-ai::json-object
            "input" 0
            "output" 0
            "cacheRead" 0
            "cacheWrite" 0
            "total" 0
            "cost"
            (cadr-ai::json-object
             "input" 0
             "output" 0
             "cacheRead" 0
             "cacheWrite" 0
             "total" 0)))
         (messages
           (list
            (cadr-ai::json-object
             "role" "user"
             "content" nil
             "timestamp" 1)
            (cadr-ai::json-object
             "role" "assistant"
             "content" nil
             "api" "openai-responses"
             "provider" "openai"
             "model" "test"
             "usage" usage
             "stopReason" "stop"
             "timestamp" 2)
            (cadr-ai::json-object
             "role" "toolResult"
             "toolCallId" "call-1"
             "toolName" "search"
             "isError" nil
             "timestamp" 3))))
    (dolist (object messages)
      (let ((message
              (cadr-agent::message-from-json
               object)))
        (is
         (null
          (etypecase message
            (cadr-ai:user-message
             (cadr-ai:user-message-content
              message))
            (cadr-ai:assistant-message
             (cadr-ai:assistant-message-content
              message))
             (cadr-ai:tool-result-message
             (cadr-ai:tool-result-message-content
              message)))))))))

(test session-round-trips-assistant-diagnostics
  (let* ((diagnostic
           (cadr-ai:make-assistant-message-diagnostic
            :type :bedrock-response-failure
            :timestamp 123
            :details
            '(:status 429
              :error-code "ThrottlingException"
              :request-id "request-1")))
         (message
           (cadr-ai:make-assistant-message
            :api :bedrock-converse-stream
            :provider :amazon-bedrock
            :model "test"
            :diagnostics (list diagnostic)
            :stop-reason :error
            :error-message "throttled"
            :timestamp 456))
         (json
           (cadr-agent::message-to-json message))
         (loaded
           (cadr-agent::message-from-json json))
         (loaded-diagnostic
           (first
            (cadr-ai:assistant-message-diagnostics loaded))))
    (is (= 1
           (length
            (cadr-ai:assistant-message-diagnostics loaded))))
    (is (eq :bedrock-response-failure
            (cadr-ai:assistant-message-diagnostic-type
             loaded-diagnostic)))
    (is (= 123
           (cadr-ai:assistant-message-diagnostic-timestamp
            loaded-diagnostic)))
    (is (equal
         '(:status 429
           :error-code "ThrottlingException"
           :request-id "request-1")
         (cadr-ai:assistant-message-diagnostic-details
          loaded-diagnostic)))))
