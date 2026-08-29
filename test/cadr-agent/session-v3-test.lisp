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

(test session-v3-jsonl-decodes-into-session-entry
  ;; journal_read / load-session: v3 body lines are session-entry,
  ;; not EQUAL hashes.  Header stays a hash.  File bytes unchanged.
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((session
             (cadr-agent:create-session
              :directory sessions :cwd cwd :id "decode"
              :timestamp 100))
           (path (cadr-agent:session-path session)))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-user-message :content "hi" :timestamp 101))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-assistant-message
        :content
        (list
         (cadr-ai:make-text-content :text "ok")
         (cadr-ai:make-tool-call
          :id "c1"
          :name "read"
          :arguments
          (cadr-ai::json-object "path" "docs/a.md")))
        :api :openai-responses
        :provider :openai
        :model "mock"
        :stop-reason :tool-use
        :timestamp 102))
      (let* ((before (uiop:read-file-string path))
             (objects (cadr-agent::read-session-objects path))
             (loaded (cadr-agent:load-session path))
             (after (uiop:read-file-string path)))
        (is (string= before after))
        (is (cadr-agent::session-file-header-p (first objects)))
        (is (not (hash-table-p (first objects))))
        (is (string=
             "session"
             (cadr-agent::session-header-ref (first objects) "type")))
        (is (every #'cadr-agent::session-entry-p (rest objects)))
        (is (string=
             "message"
             (cadr-agent::session-entry-type
              (second objects))))
        (is (cadr-agent::session-json-message-p
             (cadr-agent::session-entry-message
              (second objects))))
        (is (string=
             "user"
             (cadr-agent::session-json-message-role
              (cadr-agent::session-entry-message
               (second objects)))))
        (is (typep
             (cadr-agent::session-json-message-usage
              (cadr-agent::session-entry-message
               (third objects)))
             'cadr-ai:usage))
        (is (typep
             (first
              (cadr-agent::session-json-message-content
               (cadr-agent::session-entry-message
                (third objects))))
             'cadr-ai:text-content))
        (let ((call
                (second
                 (cadr-agent::session-json-message-content
                  (cadr-agent::session-entry-message
                   (third objects))))))
          (is (typep call 'cadr-ai:tool-call))
          (is (cadr-ai::json-object-pairs-p
               (cadr-ai:tool-call-arguments call)))
          (is (string=
               "docs/a.md"
               (cadr-ai::json-get
                (cadr-ai:tool-call-arguments call)
                "path")))
          (is (not
               (hash-table-p
                (cadr-ai:tool-call-arguments call)))))
        (is (equal
             '("hi" "ok")
             (message-texts
              (cadr-agent:session-messages loaded))))))))

(test load-session-index-follows-file-entry-order
  ;; pi _buildIndex walks FileEntry[] in order. Lisp encoding is a
  ;; simple-vector of parsed records. Drives shipped load-session,
  ;; not a reimplementation. File bytes unchanged.
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((session
             (cadr-agent:create-session
              :directory sessions :cwd cwd :id "index"
              :timestamp 100))
           (path (cadr-agent:session-path session)))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-user-message :content "one" :timestamp 101))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-assistant-message
        :content (list (cadr-ai:make-text-content :text "two"))
        :api :openai-responses
        :provider :openai
        :model "mock"
        :stop-reason :stop
        :timestamp 102))
      (let* ((before (uiop:read-file-string path))
             (objects (cadr-agent::read-session-objects path))
             (loaded (cadr-agent:load-session path))
             (after (uiop:read-file-string path))
             (file-ids
               (mapcar #'cadr-agent::session-entry-id (rest objects)))
             (loaded-ids
               (mapcar #'cadr-agent::session-entry-id
                       (cadr-agent:session-entries loaded))))
        (is (string= before after))
        (is (equal file-ids loaded-ids))
        (is (string= (car (last file-ids))
                     (cadr-agent:session-leaf-id loaded)))
        (is (eq
             (first (cadr-agent:session-entries loaded))
             (gethash
              (first file-ids)
              (cadr-agent::session-by-id loaded))))))))

(test session-header-fills-typed-struct-not-hash
  ;; First JSONL line fills session-file-header.  Not EQUAL hash.
  ;; File bytes stay stringify.  Not intern.  Not FFI.
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((path (merge-pathnames "hdr.jsonl" sessions))
           (canonical (cadr-agent::canonical-session-cwd cwd))
           (header-line
             (format
              nil
              "{\"type\":\"session\",\"version\":3,\"id\":\"hdr\",\"timestamp\":1,\"cwd\":\"~A\",\"parentSession\":null}"
              canonical)))
      (with-open-file
          (stream path
                  :direction :output
                  :if-exists :supersede
                  :if-does-not-exist :create
                  :external-format :utf-8)
        (write-string header-line stream)
        (terpri stream)
        (write-string
         "{\"type\":\"message\",\"id\":\"one\",\"parentId\":null,\"timestamp\":2,\"message\":{\"role\":\"user\",\"content\":\"hi\",\"timestamp\":2}}"
         stream)
        (terpri stream))
      (let* ((octets (cadr-ai::utf8-octets header-line))
             (header
               (cadr-agent::parse-session-header-octets
                octets 0 (length octets)))
             (objects (cadr-agent::read-session-objects path))
             (before (uiop:read-file-string path))
             (loaded (cadr-agent:load-session path))
             (after (uiop:read-file-string path)))
        (is (string= before after))
        (is (cadr-agent::session-file-header-p header))
        (is (not (hash-table-p header)))
        (is (string= "session"
                     (cadr-agent::session-file-header-type header)))
        (is (= 3 (cadr-agent::session-file-header-version header)))
        (is (string= "hdr" (cadr-agent::session-file-header-id header)))
        (is (cadr-agent::session-file-header-p (first objects)))
        (is (equal
             '("hi")
             (message-texts
              (cadr-agent:session-messages loaded))))))))

(test session-escaped-string-values-decode-on-octet-walker
  ;; PARSE-STRING-VALUE decodes JSON escapes from the octet
  ;; window.  Pairing fixture tool results use \n.  File bytes
  ;; stay stringify.  Not intern.  Not FFI.
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((path (merge-pathnames "esc.jsonl" sessions))
           (canonical (cadr-agent::canonical-session-cwd cwd))
           (text (format nil "alpha~%beta~%gamma~%delta"))
           (record
             "{\"type\":\"message\",\"id\":\"one\",\"parentId\":null,\"timestamp\":2,\"message\":{\"role\":\"user\",\"content\":\"alpha\\nbeta\\ngamma\\ndelta\",\"timestamp\":2}}"))
      (with-open-file
          (stream path
                  :direction :output
                  :if-exists :supersede
                  :if-does-not-exist :create
                  :external-format :utf-8)
        (format
         stream
         "{\"type\":\"session\",\"version\":3,\"id\":\"esc\",\"timestamp\":1,\"cwd\":\"~A\"}~%"
         canonical)
        (write-string record stream)
        (terpri stream))
      (let* ((file (uiop:read-file-string path))
             (octets (cadr-ai::utf8-octets record))
             (entry
               (cadr-agent::parse-session-record-octets
                octets 0 (length octets)))
             (loaded (cadr-agent:load-session path))
             (after (uiop:read-file-string path)))
        (is (string= file after))
        (is (search "alpha\\nbeta\\ngamma\\ndelta" file))
        (is (string=
             text
             (cadr-agent::session-json-message-content
              (cadr-agent::session-entry-message entry))))
        (is (equal
             (list text)
             (message-texts
              (cadr-agent:session-messages loaded))))))))

(test session-argument-objects-are-pairs-not-hashes
  ;; Remaining generic values must not re-enter parse-json-octets
  ;; (EQUAL hash).  Nested argument objects stay tagged pairs.
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((session
             (cadr-agent:create-session
              :directory sessions :cwd cwd :id "pairs"
              :timestamp 100))
           (path (cadr-agent:session-path session)))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-user-message :content "q" :timestamp 101))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-assistant-message
        :content
        (list
         (cadr-ai:make-tool-call
          :id "c1"
          :name "read"
          :arguments
          (cadr-ai::json-object
           "path" "docs/a.md"
           "meta" (cadr-ai::json-object "k" "v" "n" 1))))
        :timestamp 102))
      (let* ((loaded (cadr-agent:load-session path))
             (call
               (find-if
                (lambda (block)
                  (typep block 'cadr-ai:tool-call))
                (cadr-ai:assistant-message-content
                 (second (cadr-agent:session-messages loaded)))))
             (arguments (cadr-ai:tool-call-arguments call))
             (meta (cadr-ai::json-get arguments "meta")))
        (is (cadr-ai::json-object-pairs-p arguments))
        (is (cadr-ai::json-object-pairs-p meta))
        (is (not (hash-table-p meta)))
        (is (string= "v" (cadr-ai::json-get meta "k")))
        (is (= 1 (cadr-ai::json-get meta "n")))))))

(test session-v3-block-read-accepts-missing-final-newline
  ;; read-session-objects splits 1MiB octet chunks on LF.  A last
  ;; line without newline must still parse.
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let ((path (merge-pathnames "no-nl.jsonl" sessions))
          (canonical (cadr-agent::canonical-session-cwd cwd)))
      (with-open-file
          (stream path
                  :direction :output
                  :if-exists :supersede
                  :if-does-not-exist :create
                  :external-format :utf-8)
        (format
         stream
         "{\"type\":\"session\",\"version\":3,\"id\":\"nolf\",\"timestamp\":1,\"cwd\":\"~A\"}~%"
         canonical)
        (write-string
         "{\"type\":\"message\",\"id\":\"one\",\"parentId\":null,\"timestamp\":2,\"message\":{\"role\":\"user\",\"content\":\"tail\",\"timestamp\":2}}"
         stream))
      (let ((objects (cadr-agent::read-session-objects path))
            (loaded (cadr-agent:load-session path)))
        (is (= 2 (length objects)))
        (is (cadr-agent::session-file-header-p (first objects)))
        (is (cadr-agent::session-entry-p (second objects)))
        (is (equal
             '("tail")
             (message-texts
              (cadr-agent:session-messages loaded))))))))

(test session-type-keyword-maps-closed-record-types
  (is (eq :message (cadr-agent::session-type-keyword "message")))
  (is (eq :model-change
          (cadr-agent::session-type-keyword "model_change")))
  (is (eq :thinking-level-change
          (cadr-agent::session-type-keyword "thinking_level_change")))
  (is (eq :custom-message
          (cadr-agent::session-type-keyword "custom_message")))
  (is (eq :session-info
          (cadr-agent::session-type-keyword "session_info")))
  (is (eq :message (cadr-agent::session-type-keyword :message))))

(test session-octet-fsm-fills-typed-entry
  ;; Dedicated octet walker fills session-entry slots.  Content
  ;; is a typed list.  ISO timestamps become integers in place.
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((session
             (cadr-agent:create-session
              :directory sessions :cwd cwd :id "octfsm"
              :timestamp 1))
           (path (cadr-agent:session-path session)))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-assistant-message
        :content
        (list (cadr-ai:make-text-content :text "ok"))
        :timestamp 2))
      (cadr-agent::session-append-custom-message
       session "notice"
       (list (cadr-ai:make-text-content :text "hi")))
      (let* ((before (uiop:read-file-string path))
             (objects (cadr-agent::read-session-objects path))
             (entry (second objects))
             (bag (cadr-agent::session-entry-message entry))
             (content (cadr-agent::session-json-message-content bag))
             (custom (third objects))
             (loaded (cadr-agent:load-session path))
             (after (uiop:read-file-string path)))
        (is (string= before after))
        (is (cadr-agent::session-entry-p entry))
        (is (not (hash-table-p entry)))
        (is (cadr-agent::session-json-message-p bag))
        (is (integerp (cadr-agent::session-entry-timestamp entry)))
        (is (listp content))
        (is (not (vectorp content)))
        (is (typep (first content) 'cadr-ai:text-content))
        (is (not (hash-table-p (first content))))
        (is (string=
             "custom_message"
             (cadr-agent::session-entry-type custom)))
        (is (listp (cadr-agent::session-entry-content custom)))
        (is (typep
             (first (cadr-agent::session-entry-content custom))
             'cadr-ai:text-content))
        (is (typep
             (first (cadr-agent:session-messages loaded))
             'cadr-ai:assistant-message))
        (is (= 2 (length (cadr-agent:session-entries loaded))))))))

(test session-typed-content-blocks-skip-hash-rewalk
  (let* ((block (cadr-ai:make-text-content :text "hi"))
         (out
           (cadr-agent::content-blocks-from-json (vector block))))
    (is (eq block (first out)))
    (is (= 1 (length out)))))

(test session-typed-jsonl-matches-hash-stringify
  ;; One-pass emit must keep session file bytes identical to
  ;; stringify of session-entry-to-json.
  (let* ((user
           (cadr-ai:make-user-message :content "hi" :timestamp 2))
         (assistant
           (cadr-ai:make-assistant-message
            :content
            (list
             (cadr-ai:make-thinking-content :thinking "t")
             (cadr-ai:make-text-content :text "ok")
             (cadr-ai:make-tool-call
              :id "c1"
              :name "read"
              :arguments (cadr-ai::json-object "path" "docs/a.md")))
            :timestamp 3))
         (tool
           (cadr-ai:make-tool-result-message
            :tool-call-id "c1"
            :tool-name "read"
            :content (list (cadr-ai:make-text-content :text "x"))
            :is-error nil
            :timestamp 4)))
    (dolist (message (list user assistant tool))
      (let ((entry
              (cadr-agent::make-session-entry
               :type :message
               :id "e1"
               :parent-id nil
               :timestamp 3
               :message message)))
        (let ((expected
                (cadr-ai::stringify-json
                 (cadr-agent::session-entry-to-json entry)))
              (buffer (cadr-agent::make-session-octet-buffer)))
          (cadr-agent::emit-session-message-entry entry buffer)
          (is (string=
               expected
               (sb-ext:octets-to-string
                buffer :external-format :utf-8)))
          (is (string=
               expected
               (with-output-to-string (stream)
                 (cadr-agent::write-session-message-entry
                  entry stream)))))))))

(test session-journal-reuses-open-stream
  ;; Product append keeps one journal fd after first persist.
  ;; Bytes still go through write-session-entry-jsonl.
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((session
             (cadr-agent:create-session
              :directory sessions :cwd cwd :id "fdreuse"
              :timestamp 1))
           (path (cadr-agent:session-path session)))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-user-message :content "one" :timestamp 2))
      (is (null (cadr-agent::session-%journal-stream session)))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-assistant-message
        :content (list (cadr-ai:make-text-content :text "two"))
        :timestamp 3))
      (let ((stream (cadr-agent::session-%journal-stream session)))
        (is (streamp stream))
        (is (open-stream-p stream))
        (cadr-agent:session-append-message
         session
         (cadr-ai:make-user-message :content "three" :timestamp 4))
        (is (eq stream (cadr-agent::session-%journal-stream session)))
        (is (open-stream-p stream)))
      (let ((loaded (cadr-agent:load-session path)))
        (is (equal
             '("one" "two" "three")
             (message-texts
              (cadr-agent:session-messages loaded))))))))

(test keyword-from-json-closed-vocab-matches-intern
  (is (eq :stop (cadr-agent::keyword-from-json "stop")))
  (is (eq :tooluse (cadr-agent::keyword-from-json "toolUse")))
  (is (eq :openai-completions
          (cadr-agent::keyword-from-json "openai-completions")))
  (is (eq (intern (string-upcase "novelToken") "KEYWORD")
          (cadr-agent::keyword-from-json "novelToken"))))

(test octet-swar-finds-quote-or-backslash
  ;; Shipped string-window SWAR: first " or \ or control.
  (let ((mask (cadr-agent::swar-quote-or-bs-mask #x22222222)))
    (is (typep mask 'fixnum))
    (is (= mask cadr-agent::+swar-msb+)))
  (let ((buf (make-array 12 :element-type '(unsigned-byte 8)
                         :initial-element 65)))
    (setf (aref buf 0) 34)
    (is (= 0 (cadr-agent::octet-find-quote-or-backslash buf 0 12)))
    (setf (aref buf 0) 65
          (aref buf 3) 34)
    (is (= 3 (cadr-agent::octet-find-quote-or-backslash buf 0 12)))
    (setf (aref buf 3) 65
          (aref buf 4) 34)
    (is (= 4 (cadr-agent::octet-find-quote-or-backslash buf 0 12)))
    (setf (aref buf 4) 65
          (aref buf 7) 92)
    (is (= 7 (cadr-agent::octet-find-quote-or-backslash buf 0 12)))
    (is (null (cadr-agent::octet-find-quote-or-backslash buf 8 12))))
  (let* ((octets
           (cadr-ai::utf8-octets
            "{\"type\":\"message\",\"id\":\"esc\",\"parentId\":null,\"timestamp\":5,\"message\":{\"role\":\"user\",\"content\":\"a\\\"b\",\"timestamp\":5}}"))
         (entry
           (cadr-agent::parse-session-record-octets
            octets 0 (length octets))))
    (is (string=
         "a\"b"
         (cadr-agent::session-json-message-content
          (cadr-agent::session-entry-message entry))))))

(test octet-swar-finds-lf-and-skips-json-space
  ;; Shipped SWAR helpers: LF at word edges, JSON whitespace prefix.
  (let ((buf (make-array 24 :element-type '(unsigned-byte 8)
                         :initial-element 65)))
    (setf (aref buf 0) 10)
    (is (= 0 (cadr-agent::octet-find-lf buf 0 24)))
    (setf (aref buf 0) 65
          (aref buf 7) 10)
    (is (= 7 (cadr-agent::octet-find-lf buf 0 24)))
    (setf (aref buf 7) 65
          (aref buf 8) 10)
    (is (= 8 (cadr-agent::octet-find-lf buf 0 24)))
    (setf (aref buf 8) 65
          (aref buf 15) 10)
    (is (= 15 (cadr-agent::octet-find-lf buf 0 24)))
    (is (null (cadr-agent::octet-find-lf buf 16 24))))
  (let ((ws (make-array 16 :element-type '(unsigned-byte 8)
                        :initial-contents
                        '(32 9 13 10 32 32 32 32
                          123 32 32 32 32 32 32 32))))
    (is (= 8 (cadr-agent::octet-skip-json-space ws 0 16)))
    (is (= 8 (cadr-agent::octet-skip-json-space ws 8 16))))
  ;; Two ub32: haszero stays a fixnum even when byte 7 is LF.
  (let ((mask (cadr-agent::swar-eq-msb #x0A0A0A0A #x0A0A0A0A)))
    (is (typep mask 'fixnum))
    (is (= mask cadr-agent::+swar-msb+)))
  (let ((buf (make-array 8 :element-type '(unsigned-byte 8)
                         :initial-contents '(65 65 65 65 65 65 65 10))))
    (is (= 7 (cadr-agent::octet-find-lf buf 0 8)))
    (is (typep
         (cadr-agent::swar-eq-msb
          (cadr-ai::octet-u32-le buf 4)
          cadr-agent::+swar-nl+)
         'fixnum)))
  ;; Byte 7 = #x7B would set bit 62 of a 64-bit raw word and box.
  (let ((buf (make-array 8 :element-type '(unsigned-byte 8)
                         :initial-element #x7B)))
    (is (null (cadr-agent::octet-find-lf buf 0 8)))
    (is (typep (cadr-ai::octet-u32-le buf 4) 'fixnum))
    (is (= 0 (cadr-agent::octet-skip-json-space buf 0 8)))))

(test session-content-uses-unescaped-octet-block-copy
  ;; PARSE-STRING-VALUE copies unescaped ASCII via shipped
  ;; copy-unescaped-json-octets (ub32 schar stores).
  (let* ((octets
           (cadr-ai::utf8-octets
            "{\"type\":\"message\",\"id\":\"blk\",\"parentId\":null,\"timestamp\":4,\"message\":{\"role\":\"user\",\"content\":\"hello-block\",\"timestamp\":4}}"))
         (entry
           (cadr-agent::parse-session-record-octets
            octets 0 (length octets)))
         (content
           (cadr-agent::session-json-message-content
            (cadr-agent::session-entry-message entry))))
    (is (string= "hello-block" content))
    (is (typep content 'simple-base-string))))

(test pairing-record-keys-use-word-window-equals
  ;; Session walker key= goes through shipped octet-window-equals
  ;; (ub32 chunks). Pairing fixture + a timestamp/id record.
  (let* ((root (asdf:system-source-directory "cadr-agent"))
         (path
           (merge-pathnames
            "test/fixtures/goal20-paired-paths/session.jsonl"
            root))
         (objects (cadr-agent::read-session-objects path))
         (octets
           (cadr-ai::utf8-octets
            "{\"type\":\"message\",\"id\":\"weq\",\"parentId\":null,\"timestamp\":3,\"message\":{\"role\":\"user\",\"content\":\"hi\",\"timestamp\":3}}"))
         (entry
           (cadr-agent::parse-session-record-octets
            octets 0 (length octets))))
    (is (cadr-agent::session-file-header-p (first objects)))
    (is (string= "message" (cadr-agent::session-entry-type entry)))
    (is (string= "weq" (cadr-agent::session-entry-id entry)))
    (is (eql 3 (cadr-agent::session-entry-timestamp entry)))))

(test pairing-fixture-and-spaced-record-use-swar-walker
  (let* ((root (asdf:system-source-directory "cadr-agent"))
         (path
           (merge-pathnames
            "test/fixtures/goal20-paired-paths/session.jsonl"
            root))
         (objects (cadr-agent::read-session-objects path))
         (spaced
           (cadr-ai::utf8-octets
            "{  \"type\" : \"message\" , \"id\" : \"swar\" , \"parentId\" : null , \"timestamp\" : 2 , \"message\" : { \"role\" : \"user\" , \"content\" : \"hi\" , \"timestamp\" : 2 } }"))
         (entry
           (cadr-agent::parse-session-record-octets
            spaced 0 (length spaced))))
    (is (cadr-agent::session-file-header-p (first objects)))
    (is (>= (length objects) 2))
    (is (cadr-agent::session-entry-p entry))
    (is (string= "message" (cadr-agent::session-entry-type entry)))
    (is (string= "swar" (cadr-agent::session-entry-id entry)))
    (is (string=
         "hi"
         (cadr-agent::session-json-message-content
          (cadr-agent::session-entry-message entry))))))

(test compact-content-prefix-equals-generic-mutants
  ;; Knife 2: type-first compact prefixes fill typed content without
  ;; session-json-block. Spaced / reordered / escaped-type records must
  ;; EQUAL the generic path. Unknown type still errors.
  (flet ((parse-content (content-json)
           (let* ((octets
                    (cadr-ai::utf8-octets
                     (format
                      nil
                      "{\"type\":\"message\",\"id\":\"c\",\"parentId\":null,\"timestamp\":1,\"message\":{\"role\":\"assistant\",\"content\":~A,\"timestamp\":1}}"
                      content-json)))
                  (entry
                    (cadr-agent::parse-session-record-octets
                     octets 0 (length octets))))
             (cadr-agent::session-json-message-content
              (cadr-agent::session-entry-message entry)))))
    (let ((compact (parse-content "[{\"type\":\"text\",\"text\":\"hello\"}]"))
          (spaced
            (parse-content
             "[{ \"type\" : \"text\" , \"text\" : \"hello\" }]"))
          (reordered
            (parse-content "[{\"text\":\"hello\",\"type\":\"text\"}]"))
          (escaped
            (parse-content
             "[{\"type\":\"te\\u0078t\",\"text\":\"hello\"}]")))
      (is (typep (first compact) 'cadr-ai:text-content))
      (is (string= "hello" (cadr-ai:text-content-text (first compact))))
      (is (string= "hello" (cadr-ai:text-content-text (first spaced))))
      (is (string= "hello" (cadr-ai:text-content-text (first reordered))))
      (is (string= "hello" (cadr-ai:text-content-text (first escaped)))))
    (let ((thinking
            (parse-content
             "[{\"type\":\"thinking\",\"thinking\":\"plan\"}]")))
      (is (typep (first thinking) 'cadr-ai:thinking-content))
      (is (string=
           "plan"
           (cadr-ai:thinking-content-thinking (first thinking)))))
    (let ((tool
            (parse-content
             "[{\"type\":\"toolCall\",\"id\":\"call-1\",\"name\":\"read\",\"arguments\":{\"path\":\"x\"}}]")))
      (is (typep (first tool) 'cadr-ai:tool-call))
      (is (string= "call-1" (cadr-ai:tool-call-id (first tool))))
      (is (string= "read" (cadr-ai:tool-call-name (first tool)))))
    (signals error
      (parse-content "[{\"type\":\"nope\"}]"))))

(test single-block-content-shortcut-equals-generic-mutants
  ;; One-element content arrays skip list+nreverse aggregation after
  ;; kept compact-prefix. Compact / spaced / reordered stay EQUAL on
  ;; slots. Two-element arrays still a list of that length. Not bag,
  ;; not D svref, not first-byte.
  (flet ((parse-content (content-json)
           (let* ((octets
                    (cadr-ai::utf8-octets
                     (format
                      nil
                      "{\"type\":\"message\",\"id\":\"c\",\"parentId\":null,\"timestamp\":1,\"message\":{\"role\":\"assistant\",\"content\":~A,\"timestamp\":1}}"
                      content-json)))
                  (entry
                    (cadr-agent::parse-session-record-octets
                     octets 0 (length octets))))
             (cadr-agent::session-json-message-content
              (cadr-agent::session-entry-message entry))))
         (text-slot (block)
           (cadr-ai:text-content-text block))
         (thinking-slot (block)
           (cadr-ai:thinking-content-thinking block))
         (tool-slots (block)
           (list (cadr-ai:tool-call-id block)
                 (cadr-ai:tool-call-name block))))
    (let ((compact (parse-content "[{\"type\":\"text\",\"text\":\"hello\"}]"))
          (spaced
            (parse-content
             "[{ \"type\" : \"text\" , \"text\" : \"hello\" }]"))
          (reordered
            (parse-content "[{\"text\":\"hello\",\"type\":\"text\"}]")))
      (is (listp compact))
      (is (= 1 (length compact)))
      (is (typep (first compact) 'cadr-ai:text-content))
      (is (string= "hello" (text-slot (first compact))))
      (is (equal (mapcar #'text-slot compact)
                 (mapcar #'text-slot spaced)))
      (is (equal (mapcar #'text-slot compact)
                 (mapcar #'text-slot reordered))))
    (let ((thinking
            (parse-content
             "[{\"type\":\"thinking\",\"thinking\":\"plan\"}]")))
      (is (listp thinking))
      (is (= 1 (length thinking)))
      (is (typep (first thinking) 'cadr-ai:thinking-content))
      (is (string= "plan" (thinking-slot (first thinking)))))
    (let ((tool
            (parse-content
             "[{\"type\":\"toolCall\",\"id\":\"call-1\",\"name\":\"read\",\"arguments\":{\"path\":\"x\"}}]")))
      (is (listp tool))
      (is (= 1 (length tool)))
      (is (typep (first tool) 'cadr-ai:tool-call))
      (is (equal '("call-1" "read") (tool-slots (first tool)))))
    (let ((two
            (parse-content
             "[{\"type\":\"text\",\"text\":\"a\"},{\"type\":\"thinking\",\"thinking\":\"b\"}]"))
          (two-spaced
            (parse-content
             "[{ \"type\" : \"text\" , \"text\" : \"a\" } , { \"type\" : \"thinking\" , \"thinking\" : \"b\" }]")))
      (is (listp two))
      (is (= 2 (length two)))
      (is (typep (first two) 'cadr-ai:text-content))
      (is (typep (second two) 'cadr-ai:thinking-content))
      (is (string= "a" (text-slot (first two))))
      (is (string= "b" (thinking-slot (second two))))
      (is (= 2 (length two-spaced)))
      (is (string= "a" (text-slot (first two-spaced))))
      (is (string= "b" (thinking-slot (second two-spaced)))))))

(test usage-first-byte-dispatch-equals-generic-mutants
  ;; parse-usage first-byte field dispatch (proposal-3 family).
  ;; Compact pairing-fixture usage, spaced, and reordered keys
  ;; EQUAL on slots. Unknown keys (totalTokens) still skip so
  ;; usage-total stays 0. Not whole-object compact-prefix.
  (flet ((parse-usage-json (usage-json)
           (let* ((octets
                    (cadr-ai::utf8-octets
                     (format
                      nil
                      "{\"type\":\"message\",\"id\":\"u\",\"parentId\":null,\"timestamp\":1,\"message\":{\"role\":\"assistant\",\"content\":\"x\",\"usage\":~A,\"timestamp\":1}}"
                      usage-json)))
                  (entry
                    (cadr-agent::parse-session-record-octets
                     octets 0 (length octets))))
             (cadr-agent::session-json-message-usage
              (cadr-agent::session-entry-message entry))))
         (usage-slots (usage)
           (list (cadr-ai:usage-input usage)
                 (cadr-ai:usage-output usage)
                 (cadr-ai:usage-cache-read usage)
                 (cadr-ai:usage-cache-write usage)
                 (cadr-ai:usage-total usage)
                 (cadr-ai:cost-input (cadr-ai:usage-cost usage))
                 (cadr-ai:cost-output (cadr-ai:usage-cost usage))
                 (cadr-ai:cost-total (cadr-ai:usage-cost usage)))))
    (let* ((compact
             (parse-usage-json
              "{\"input\":1201,\"output\":65,\"cacheRead\":0,\"cacheWrite\":0,\"totalTokens\":1266,\"cost\":{\"input\":0,\"output\":0,\"cacheRead\":0,\"cacheWrite\":0,\"total\":0}}"))
           (spaced
             (parse-usage-json
              "{ \"input\" : 1201 , \"output\" : 65 , \"cacheRead\" : 0 , \"cacheWrite\" : 0 , \"totalTokens\" : 1266 , \"cost\" : { \"input\" : 0 , \"output\" : 0 , \"cacheRead\" : 0 , \"cacheWrite\" : 0 , \"total\" : 0 } }"))
           (reordered
             (parse-usage-json
              "{\"output\":65,\"input\":1201,\"cacheRead\":0,\"cacheWrite\":0,\"totalTokens\":1266,\"cost\":{\"input\":0,\"output\":0,\"cacheRead\":0,\"cacheWrite\":0,\"total\":0}}"))
           (snake
             (parse-usage-json
              "{\"input\":3,\"output\":4,\"cache_read\":5,\"cache_write\":6,\"total\":7}")))
      (is (typep compact 'cadr-ai:usage))
      (is (equal (usage-slots compact) (usage-slots spaced)))
      (is (equal (usage-slots compact) (usage-slots reordered)))
      (is (eql 1201 (cadr-ai:usage-input compact)))
      (is (eql 65 (cadr-ai:usage-output compact)))
      (is (eql 0 (cadr-ai:usage-total compact)))
      (is (eql 5 (cadr-ai:usage-cache-read snake)))
      (is (eql 6 (cadr-ai:usage-cache-write snake)))
      (is (eql 7 (cadr-ai:usage-total snake))))))

(test interned-ascii-value-length-gate-equals-closed-set
  ;; parse-string-value skips intern labels when n is outside 4–18.
  ;; Closed-set values still interned (eq). Long text still copies.
  ;; Drives shipped parse-session-record-octets. Not intern-grow.
  (flet ((parse-message-json (role content-json)
           (let* ((octets
                    (cadr-ai::utf8-octets
                     (format
                      nil
                      "{\"type\":\"message\",\"id\":\"i\",\"parentId\":null,\"timestamp\":1,\"message\":{\"role\":~S,\"content\":~A,\"timestamp\":1}}"
                      role
                      content-json)))
                  (entry
                    (cadr-agent::parse-session-record-octets
                     octets 0 (length octets))))
             (cadr-agent::session-entry-message entry))))
    (let ((msg (parse-message-json "assistant" "\"text\""))
          (msg2 (parse-message-json "assistant" "\"text\"")))
      (is (string=
           "assistant"
           (cadr-agent::session-json-message-role msg)))
      (is (eq (cadr-agent::session-json-message-role msg)
              (cadr-agent::session-json-message-role msg2)))
      (is (eq (cadr-agent::session-json-message-content msg)
              (cadr-agent::session-json-message-content msg2)))
      (is (string=
           "text"
           (cadr-agent::session-json-message-content msg))))
    (let* ((long (make-string 40 :initial-element #\a))
           (msg
             (parse-message-json
              "user"
              (cadr-ai::stringify-json long)))
           (content
             (cadr-agent::session-json-message-content msg)))
      (is (string= "user" (cadr-agent::session-json-message-role msg)))
      (is (string= long content))
      (is (not (eq long content))))))

(test usage-ascii-number-value-equals-generic-mutants
  ;; Usage value-side ASCII integer (not key first-byte).
  ;; Compact / spaced / reordered EQUAL slots. Exponent and
  ;; decimal fall back to parse-number-value. Leading-zero
  ;; padded form stays on the generic path.
  (flet ((parse-usage-json (usage-json)
           (let* ((octets
                    (cadr-ai::utf8-octets
                     (format
                      nil
                      "{\"type\":\"message\",\"id\":\"u\",\"parentId\":null,\"timestamp\":1,\"message\":{\"role\":\"assistant\",\"content\":\"x\",\"usage\":~A,\"timestamp\":1}}"
                      usage-json)))
                  (entry
                    (cadr-agent::parse-session-record-octets
                     octets 0 (length octets))))
             (cadr-agent::session-json-message-usage
              (cadr-agent::session-entry-message entry))))
         (usage-slots (usage)
           (list (cadr-ai:usage-input usage)
                 (cadr-ai:usage-output usage)
                 (cadr-ai:usage-cache-read usage)
                 (cadr-ai:usage-cache-write usage)
                 (cadr-ai:usage-total usage)
                 (cadr-ai:cost-input (cadr-ai:usage-cost usage))
                 (cadr-ai:cost-output (cadr-ai:usage-cost usage))
                 (cadr-ai:cost-total (cadr-ai:usage-cost usage)))))
    (let* ((compact
             (parse-usage-json
              "{\"input\":1201,\"output\":65,\"cacheRead\":0,\"cacheWrite\":0,\"totalTokens\":1266,\"cost\":{\"input\":0,\"output\":0,\"cacheRead\":0,\"cacheWrite\":0,\"total\":0}}"))
           (spaced
             (parse-usage-json
              "{ \"input\" : 1201 , \"output\" : 65 , \"cacheRead\" : 0 , \"cacheWrite\" : 0 , \"totalTokens\" : 1266 , \"cost\" : { \"input\" : 0 , \"output\" : 0 , \"cacheRead\" : 0 , \"cacheWrite\" : 0 , \"total\" : 0 } }"))
           (reordered
             (parse-usage-json
              "{\"output\":65,\"input\":1201,\"cacheRead\":0,\"cacheWrite\":0,\"totalTokens\":1266,\"cost\":{\"input\":0,\"output\":0,\"cacheRead\":0,\"cacheWrite\":0,\"total\":0}}"))
           (snake
             (parse-usage-json
              "{\"input\":3,\"output\":4,\"cache_read\":5,\"cache_write\":6,\"total\":7}"))
           (exponent
             (parse-usage-json
              "{\"input\":1e3,\"output\":6.5e1,\"total\":0}"))
           (decimal
             (parse-usage-json
              "{\"input\":1201,\"cost\":{\"input\":1.25,\"output\":0.5,\"total\":1.75}}")))
      (is (typep compact 'cadr-ai:usage))
      (is (equal (usage-slots compact) (usage-slots spaced)))
      (is (equal (usage-slots compact) (usage-slots reordered)))
      (is (eql 1201 (cadr-ai:usage-input compact)))
      (is (eql 65 (cadr-ai:usage-output compact)))
      (is (eql 0 (cadr-ai:usage-total compact)))
      (is (eql 5 (cadr-ai:usage-cache-read snake)))
      (is (eql 6 (cadr-ai:usage-cache-write snake)))
      (is (eql 7 (cadr-ai:usage-total snake)))
      (is (eql 1000 (cadr-ai:usage-input exponent)))
      (is (eql 65 (cadr-ai:usage-output exponent)))
      (is (= 1.25d0 (cadr-ai:cost-input (cadr-ai:usage-cost decimal))))
      (is (= 0.5d0 (cadr-ai:cost-output (cadr-ai:usage-cost decimal))))
      (is (= 1.75d0 (cadr-ai:cost-total (cadr-ai:usage-cost decimal)))))))

(test load-session-repairs-a-missing-trailing-newline
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((session
             (cadr-agent:create-session
              :directory sessions :cwd cwd :id "tail"
              :timestamp 100))
           (path (cadr-agent:session-path session)))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-user-message :content "one" :timestamp 101))
      (let ((text (uiop:read-file-string path)))
        (with-open-file
            (stream path :direction :output :if-exists :supersede
                    :external-format :utf-8)
          (write-string (string-right-trim '(#\Newline) text) stream)))
      (cadr-agent:load-session path)
      (let ((octets
              (with-open-file
                  (stream path :element-type '(unsigned-byte 8))
                (let ((buffer
                        (make-array (file-length stream)
                                    :element-type '(unsigned-byte 8))))
                  (read-sequence buffer stream)
                  buffer))))
        (is (= 10 (aref octets (1- (length octets)))))))))
