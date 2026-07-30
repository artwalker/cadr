(in-package #:cadr-agent/tests)
(in-suite cadr-agent-suite)

(defun parse-json-lines (path)
  (with-open-file
      (stream path :direction :input :external-format :utf-8)
    (loop for line = (read-line stream nil nil)
          while line
          collect (cadr-ai::parse-json line))))

(defun message-texts (messages)
  (loop for message in messages
        collect
        (cond
          ((typep message 'cadr-ai:user-message)
           (cadr-ai:user-message-content message))
          ((typep message 'cadr-ai:assistant-message)
           (cadr-ai:text-content-text
            (first (cadr-ai:assistant-message-content message))))
          (t :tool-result))))

(test session-v2-branches-from-any-node-and-persists-both-paths
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((session
             (cadr-agent:create-session
              :directory sessions :cwd cwd :id "tree"))
           (root-id
             (cadr-agent:session-append-message
              session
              (cadr-ai:make-user-message
               :content "root" :timestamp 1)))
           (first-leaf-id
             (cadr-agent:session-append-message
              session
              (cadr-ai:make-assistant-message
               :content
               (list (cadr-ai:make-text-content :text "first"))
               :api :openai-responses
               :provider :openai
               :model "mock"
               :stop-reason :stop
               :timestamp 2))))
      (cadr-agent:session-branch session root-id)
      (let ((second-leaf-id
              (cadr-agent:session-append-message
               session
               (cadr-ai:make-assistant-message
                :content
                (list (cadr-ai:make-text-content :text "second"))
                :api :openai-responses
                :provider :openai
                :model "mock"
                :stop-reason :stop
                :timestamp 3))))
        (is (equal '("root" "first")
                   (message-texts
                    (cadr-agent:session-messages
                     session first-leaf-id))))
        (is (equal '("root" "second")
                   (message-texts
                     (cadr-agent:session-messages
                      session second-leaf-id))))
        (let ((loaded
                (cadr-agent:load-session
                 (cadr-agent:session-path session))))
          (is (string= second-leaf-id
                       (cadr-agent:session-leaf-id loaded)))
          (is (equal '("root" "first")
                     (message-texts
                      (cadr-agent:session-messages
                       loaded first-leaf-id))))
          (is (equal '("root" "second")
                     (message-texts
                      (cadr-agent:session-messages
                       loaded second-leaf-id))))
          (cadr-agent:session-branch loaded first-leaf-id)
          (let ((continued-id
                  (cadr-agent:session-append-message
                   loaded
                   (cadr-ai:make-user-message
                    :content "continue first" :timestamp 4))))
            (is (equal '("root" "first" "continue first")
                       (message-texts
                        (cadr-agent:session-messages
                         (cadr-agent:load-session
                          (cadr-agent:session-path loaded))
                         continued-id))))))
        (let ((records (parse-json-lines
                        (cadr-agent:session-path session))))
          (is (= 3 (cadr-ai::json-get (first records) "version")))
          (dolist (record (rest records))
            (is (stringp (cadr-ai::json-get record "id")))
            (multiple-value-bind (value present-p)
              (gethash "parentId" record)
              (declare (ignore value))
              (is (eq t present-p)))))))))

(test session-v1-load-migrates-atomically-without-losing-envelope-fields
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let ((path (merge-pathnames "legacy.jsonl" sessions))
          (canonical (cadr-agent::canonical-session-cwd cwd)))
      (with-open-file
          (stream path
                  :direction :output
                  :if-exists :supersede
                  :if-does-not-exist :create
                  :external-format :utf-8)
        (format stream
                "{\"type\":\"session\",\"version\":1,\"id\":\"legacy\",\"timestamp\":10,\"cwd\":\"~A\",\"future_header\":\"kept\"}~%"
                canonical)
        (format stream
                "{\"type\":\"message\",\"timestamp\":11,\"future_envelope\":{\"x\":7},\"message\":{\"type\":\"user\",\"content\":\"legacy text\",\"timestamp\":11}}~%"))
      (let ((loaded (cadr-agent:load-session path)))
        (is (equal '("legacy text")
                   (message-texts
                    (cadr-agent:session-messages loaded))))
        (let ((records (parse-json-lines path)))
          (is (= 3 (cadr-ai::json-get (first records) "version")))
          (is (string= "kept"
                       (cadr-ai::json-get
                        (first records) "future_header")))
          (is (= 7
                 (cadr-ai::json-get
                  (cadr-ai::json-get
                   (second records) "future_envelope")
                  "x")))
          (is (stringp
               (cadr-ai::json-get (second records) "id")))
          (is (null
               (cadr-ai::json-get
                (second records) "parentId" :missing))))))))

(test session-v2-rejects-duplicate-ids-and-dangling-parents
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (dolist
        (records
         (list
          (list
           "{\"type\":\"message\",\"id\":\"same\",\"parentId\":null,\"timestamp\":1,\"message\":{\"type\":\"user\",\"content\":\"a\",\"timestamp\":1}}"
           "{\"type\":\"message\",\"id\":\"same\",\"parentId\":\"same\",\"timestamp\":2,\"message\":{\"type\":\"user\",\"content\":\"b\",\"timestamp\":2}}")
          (list
           "{\"type\":\"message\",\"id\":\"orphan\",\"parentId\":\"missing\",\"timestamp\":1,\"message\":{\"type\":\"user\",\"content\":\"a\",\"timestamp\":1}}")))
      (let ((path
              (merge-pathnames
               (format nil "bad-~D.jsonl" (random 1000000))
               sessions)))
        (with-open-file
            (stream path
                    :direction :output
                    :if-exists :supersede
                    :if-does-not-exist :create
                    :external-format :utf-8)
          (format stream
                  "{\"type\":\"session\",\"version\":2,\"id\":\"bad\",\"timestamp\":1,\"cwd\":\"~A\"}~%"
                  (cadr-agent::canonical-session-cwd cwd))
          (dolist (record records)
            (format stream "~A~%" record)))
        (signals cadr-agent:session-error
          (cadr-agent:load-session path))))))

(test session-v2-round-trips-image-content
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let ((session
            (cadr-agent:create-session
             :directory sessions :cwd cwd :id "image")))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-user-message
        :content
        (list
         (cadr-ai:make-text-content :text "inspect")
         (cadr-ai:make-image-content
          :mime-type "image/png" :data "YWJj"))))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-assistant-message
        :content
        (list (cadr-ai:make-text-content :text "seen"))
        :api :openai-responses
        :provider :openai
        :model "mock"
        :stop-reason :stop))
      (let* ((loaded
               (cadr-agent:load-session
                (cadr-agent:session-path session)))
             (content
               (cadr-ai:user-message-content
                (first (cadr-agent:session-messages loaded)))))
        (is (typep (second content) 'cadr-ai:image-content))
        (is (string= "image/png"
                     (cadr-ai:image-content-mime-type
                      (second content))))
        (is (string= "YWJj"
                     (cadr-ai:image-content-data
                      (second content))))))))

(test session-list-resume-and-html-export-cover-the-entire-tree
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((older
             (cadr-agent:create-session
              :directory sessions :cwd cwd
              :id "older" :timestamp 10))
           (newer
             (cadr-agent:create-session
              :directory sessions :cwd cwd
              :id "newer" :timestamp 20))
           (root-id
             (cadr-agent:session-append-message
              newer
              (cadr-ai:make-user-message
               :content "<script>alert(1)</script>")))
           (old-leaf
             (cadr-agent:session-append-message
              newer
              (cadr-ai:make-user-message :content "left"))))
      (values older)
      (cadr-agent:session-append-message
       older
       (cadr-ai:make-assistant-message
        :content
        (list (cadr-ai:make-text-content :text "older"))
        :api :openai-responses
        :provider :openai
        :model "mock"
        :stop-reason :stop))
      (cadr-agent:session-branch newer root-id)
      (cadr-agent:session-append-message
       newer (cadr-ai:make-user-message :content "right"))
      (cadr-agent:session-append-message
       newer
       (cadr-ai:make-assistant-message
        :content
        (list (cadr-ai:make-text-content :text "right answer"))
        :api :openai-responses
        :provider :openai
        :model "mock"
        :stop-reason :stop))
      (let ((listed
              (cadr-agent:list-sessions
               :directory sessions :cwd cwd)))
        (is (equal '("newer" "older")
                   (mapcar #'cadr-agent:session-id listed))))
      (let ((resumed
              (cadr-agent:resume-session
               "newer" :directory sessions)))
        (is (string= "newer" (cadr-agent:session-id resumed)))
        (is (equal '("<script>alert(1)</script>" "left")
                   (message-texts
                    (cadr-agent:session-messages
                     resumed old-leaf)))))
      (let ((html-path (merge-pathnames "tree.html" sessions)))
        (cadr-agent:export-session-html newer html-path)
        (let ((html
                (uiop:read-file-string
                 html-path :external-format :utf-8)))
          (is (search "&lt;script&gt;alert(1)&lt;/script&gt;"
                      html))
          (is (not (search "<script>alert(1)</script>" html)))
          (is (search "left" html))
          (is (search "right" html))
          (is (search root-id html)))))))

(test session-html-export-renders-skill-wrapper-as-visible-sibling-blocks
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((session
             (cadr-agent:create-session
              :directory sessions
              :cwd cwd
              :id "skill-export"))
           (skill-text
             (format
              nil
              "<skill name=\"review\" location=\"/skills/review/SKILL.md\">~%# Review~%~%<script>bad()</script>~%</skill>~%~%check this diff"))
           (message
             (cadr-ai:make-user-message
              :content
              (list
               (cadr-ai:make-text-content
                :text skill-text)
               (cadr-ai:make-image-content
                :mime-type "image/png"
                :data "AA=="))))
           (path
             (merge-pathnames
              "skill.html" sessions)))
      (cadr-agent:session-append-message
       session message)
      (cadr-agent:export-session-html
       session path)
      (let ((html
              (uiop:read-file-string
               path :external-format :utf-8)))
        (is (not
             (search "&lt;skill" html)))
        (is (search
             "class=\"skill-invocation\"" html))
        (is (search
             "<h1>Review</h1>" html))
        (is (search
             "&lt;script&gt;bad()&lt;/script&gt;"
             html))
        (is (not
             (search "<script>bad()</script>"
                     html)))
        (is (search
             "class=\"user-message\"" html))
        (is (search "check this diff" html))
        (is (search
             "data:image/png;base64,AA=="
             html))
        (is (search
             "tree-role-skill" html))
        (is (<
             (search "skill-invocation" html)
             (search "user-message" html)))))))
