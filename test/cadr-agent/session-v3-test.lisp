(in-package #:cadr-agent/tests)
(in-suite cadr-agent-suite)

(test session-v3-delays-file-until-first-assistant-and-flushes-buffer
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((session
             (cadr-agent:create-session
              :directory sessions
              :cwd cwd
              :id "delayed"
              :timestamp 100))
           (path (cadr-agent:session-path session)))
      (is (not (probe-file path)))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-user-message
        :content "buffered user"
        :timestamp 101))
      (cadr-agent::session-append-thinking-level-change
       session "high")
      (is (not (probe-file path)))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-assistant-message
        :content
        (list
         (cadr-ai:make-text-content
          :text "first assistant"))
        :api :openai-responses
        :provider :openai
        :model "mock"
        :stop-reason :stop
        :timestamp 102))
      (is (probe-file path))
      (let ((records (parse-json-lines path)))
        (is (= 4 (length records)))
        (is (string=
             "session"
             (cadr-ai::json-get
              (first records) "type")))
        (is
         (equal
          '("message"
            "thinking_level_change"
            "message")
          (loop for record in (rest records)
                collect
                (cadr-ai::json-get
                 record "type"))))))))

(test session-v3-discovery-is-bounded-and-skips-corrupt-candidates
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((valid
             (cadr-agent:create-session
              :directory sessions
              :cwd cwd
              :id "valid"
              :timestamp 100))
           (oversized
             (merge-pathnames
              "oversized.jsonl" sessions))
           (non-header
             (merge-pathnames
              "non-header.jsonl" sessions)))
      (cadr-agent:session-append-message
       valid
       (cadr-ai:make-assistant-message
        :content
        (list
         (cadr-ai:make-text-content
          :text "persist"))
        :api :openai-responses
        :provider :openai
        :model "mock"
        :stop-reason :stop
        :timestamp 101))
      (with-open-file
          (stream oversized
                  :direction :output
                  :if-exists :supersede
                  :if-does-not-exist :create
                  :external-format :utf-8)
        (write-string
         (make-string
          (1+
           cadr-agent::+max-session-header-scan-bytes+)
          :initial-element #\x)
         stream)
        (terpri stream)
        (cadr-agent::write-jsonl-object
         stream
         (cadr-ai::json-object
          "type" "session"
          "version" 3
          "id" "hidden"
          "timestamp"
          "1970-01-01T00:00:00.100Z"
          "cwd"
          (cadr-agent::canonical-session-cwd
           cwd))))
      (with-open-file
          (stream non-header
                  :direction :output
                  :if-exists :supersede
                  :if-does-not-exist :create
                  :external-format :utf-8)
        (cadr-agent::write-jsonl-object
         stream
         (cadr-ai::json-object
          "type" "message"
          "id" "first"
          "parentId" 'null
          "timestamp"
          "1970-01-01T00:00:00.100Z")))
      (is
       (equal
        '("valid")
        (mapcar
         #'cadr-agent:session-id
         (cadr-agent:list-sessions
          :directory sessions
          :cwd cwd)))))))

(test session-v3-list-order-uses-last-user-or-assistant-message-time
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let ((newer-header
            (cadr-agent:create-session
             :directory sessions
             :cwd cwd
             :id "newer-header"
             :timestamp 2000))
          (newer-message
            (cadr-agent:create-session
             :directory sessions
             :cwd cwd
             :id "newer-message"
             :timestamp 1000)))
      (cadr-agent:session-append-message
       newer-header
       (cadr-ai:make-assistant-message
        :content
        (list
         (cadr-ai:make-text-content
          :text "older activity"))
        :api :openai-responses
        :provider :openai
        :model "mock"
        :stop-reason :stop
        :timestamp 4000))
      (cadr-agent:session-append-message
       newer-message
       (cadr-ai:make-assistant-message
        :content
        (list
         (cadr-ai:make-text-content
          :text "newer activity"))
        :api :openai-responses
        :provider :openai
        :model "mock"
        :stop-reason :stop
        :timestamp 5000))
      (cadr-agent:session-set-name
       newer-header "metadata must not win")
      (is
       (equal
        '("newer-message" "newer-header")
        (mapcar
         #'cadr-agent:session-id
         (cadr-agent:list-sessions
          :directory sessions
          :cwd cwd)))))))

(test session-v3-writes-reference-header-and-all-entry-envelopes
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((session
             (cadr-agent:create-session
              :directory sessions
              :cwd cwd
              :id "v3-all"
              :timestamp 100
              :parent-session "/tmp/parent.jsonl"))
           (message-id
             (cadr-agent:session-append-message
              session
              (cadr-ai:make-user-message
               :content "hello"
               :timestamp 101))))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-assistant-message
        :content
        (list
         (cadr-ai:make-text-content
          :text "answer"))
        :api :openai-responses
        :provider :openai
        :model "mock"
        :stop-reason :stop
        :timestamp 102))
      (cadr-agent::session-append-thinking-level-change
       session "high")
      (is
       (and
        (= 8 (length message-id))
        (every
         (lambda (character)
           (digit-char-p character 16))
         message-id)))
      (cadr-agent::session-append-model-change
       session "openai" "gpt-test")
      (cadr-agent:session-append-compaction
       session "summary" (list message-id)
       message-id 42
       :details '(:kind :test)
       :from-hook-p t)
      (cadr-agent::session-append-branch-summary
       session message-id "branch"
       :details '(:branch t))
      (cadr-agent::session-append-custom
       session "state" '(:value 7))
      (cadr-agent::session-append-custom-message
       session "notice" "custom content"
       :display-p t)
      (cadr-agent::session-set-label
       session message-id "bookmark")
      (cadr-agent::session-set-name
       session
       (format nil "hello~%world~C~%again" #\Return))
      (let* ((records
               (parse-json-lines
                (cadr-agent:session-path session)))
             (header (first records))
             (types
               (loop for record in (rest records)
                     collect
                     (cadr-ai::json-get record "type"))))
        (is (= 3 (cadr-ai::json-get header "version")))
        (is (stringp
             (cadr-ai::json-get header "timestamp")))
        (is (search "T"
                    (cadr-ai::json-get header "timestamp")))
        (is
         (string=
          "/tmp/parent.jsonl"
          (cadr-ai::json-get header "parentSession")))
        (is
         (equal
          '("message"
            "message"
            "thinking_level_change"
            "model_change"
            "compaction"
            "branch_summary"
            "custom"
            "custom_message"
            "label"
            "session_info")
          types)))
      (let ((loaded
              (cadr-agent:load-session
               (cadr-agent:session-path session))))
        (is (= 10
               (length
                (cadr-agent:session-entries loaded))))
        (is
         (string=
          "hello world again"
          (cadr-agent::session-name loaded)))
        (is
         (string=
          "bookmark"
          (cadr-agent::session-label
           loaded message-id)))
        (let ((html
                (merge-pathnames
                 "v3-all.html" sessions)))
          (cadr-agent:export-session-html
           loaded html)
          (let* ((text
                   (uiop:read-file-string
                    html :external-format :utf-8))
                 (data
                   (exported-session-data text))
                 (actual-entries
                   (cadr-ai::json-get data "entries"))
                 (expected-entries
                   (map 'vector
                        #'cadr-agent::session-entry-to-json
                        (cadr-agent:session-entries loaded))))
            (is (= (length expected-entries)
                   (length actual-entries)))
            (labels ((same-json-p (expected actual)
                       (cond
                         ((and (hash-table-p expected)
                               (hash-table-p actual))
                          (and
                           (= (hash-table-count expected)
                              (hash-table-count actual))
                           (loop for key being
                                 the hash-keys of expected
                                 always
                                 (multiple-value-bind
                                       (value present-p)
                                     (gethash key actual)
                                   (and present-p
                                        (same-json-p
                                         (gethash key expected)
                                         value))))))
                         ((and (vectorp expected)
                               (vectorp actual))
                          (and
                           (= (length expected) (length actual))
                           (loop for expected-value across expected
                                 for actual-value across actual
                                 always
                                 (same-json-p
                                  expected-value actual-value))))
                         ((and (numberp expected)
                               (numberp actual))
                          (= expected actual))
                         (t (equal expected actual)))))
              (loop for expected across expected-entries
                    for actual across actual-entries
                    do
                    (is (string=
                         (cadr-ai::json-get expected "id")
                         (cadr-ai::json-get actual "id")))
                    (is (equal
                         (cadr-ai::json-get expected "parentId")
                         (cadr-ai::json-get actual "parentId")))
                    (is (string=
                         (cadr-ai::json-get expected "type")
                         (cadr-ai::json-get actual "type")))
                    (when (string=
                           "message"
                           (cadr-ai::json-get expected "type"))
                      (let ((expected-message
                              (cadr-ai::json-get expected "message"))
                            (actual-message
                              (cadr-ai::json-get actual "message")))
                        (is (string=
                             (cadr-ai::json-get expected-message "role")
                             (cadr-ai::json-get actual-message "role")))
                        (is (same-json-p
                             (cadr-ai::json-get expected-message "content")
                             (cadr-ai::json-get actual-message "content")))))
                    (is (same-json-p expected actual))))))))))

(test session-v1-and-v2-migrate-to-v3-with-unknown-fields-preserved
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let ((path (merge-pathnames "v2.jsonl" sessions))
          (canonical
            (cadr-agent::canonical-session-cwd cwd)))
      (with-open-file
          (stream path
                  :direction :output
                  :if-exists :supersede
                  :if-does-not-exist :create
                  :external-format :utf-8)
        (format
         stream
         "{\"type\":\"session\",\"version\":2,\"id\":\"v2\",\"timestamp\":10,\"cwd\":\"~A\",\"future\":\"kept\"}~%"
         canonical)
        (format
         stream
         "{\"type\":\"message\",\"id\":\"one\",\"parentId\":null,\"timestamp\":11,\"futureEntry\":{\"x\":7},\"message\":{\"role\":\"hookMessage\",\"content\":\"legacy custom\",\"timestamp\":11}}~%"))
      (cadr-agent:load-session path)
      (let ((records (parse-json-lines path)))
        (is (= 3
               (cadr-ai::json-get
                (first records) "version")))
        (is
         (string=
          "kept"
          (cadr-ai::json-get
           (first records) "future")))
        (is
         (string=
          "custom"
          (cadr-ai::json-get
           (cadr-ai::json-get
            (second records) "message")
           "role")))
        (is
         (= 7
            (cadr-ai::json-get
             (cadr-ai::json-get
              (second records) "futureEntry")
             "x")))))))

(test session-v3-set-name-nil-clears-durably
  ;; Baseline v0.84.2 conformance case "clears session names durably":
  ;; setName(undefined) clears the name and the clearing survives reload.
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((session
             (cadr-agent:create-session
              :directory sessions :cwd cwd :id "name-clear"
              :timestamp 100)))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-user-message :content "hi" :timestamp 101))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-assistant-message
        :content
        (list (cadr-ai:make-text-content :text "answer"))
        :api :openai-responses
        :provider :openai
        :model "mock"
        :stop-reason :stop
        :timestamp 102))
      (cadr-agent:session-set-name session "Temporary")
      (is (string= "Temporary" (cadr-agent::session-name session)))
      (cadr-agent:session-set-name session nil)
      (is (null (cadr-agent::session-name session)))
      (let ((loaded
              (cadr-agent:load-session
               (cadr-agent:session-path session))))
        (is (null (cadr-agent::session-name loaded)))))))
