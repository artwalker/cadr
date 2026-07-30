(in-package #:pi-agent/tests)
(in-suite pi-agent-suite)

(defun parse-json-lines (path)
  (with-open-file
      (stream path :direction :input :external-format :utf-8)
    (loop for line = (read-line stream nil nil)
          while line
          collect (pi-ai::parse-json line))))

(defun message-texts (messages)
  (loop for message in messages
        collect
        (cond
          ((typep message 'pi-ai:user-message)
           (pi-ai:user-message-content message))
          ((typep message 'pi-ai:assistant-message)
           (pi-ai:text-content-text
            (first (pi-ai:assistant-message-content message))))
          (t :tool-result))))

(test session-v2-branches-from-any-node-and-persists-both-paths
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((session
             (pi-agent:create-session
              :directory sessions :cwd cwd :id "tree"))
           (root-id
             (pi-agent:session-append-message
              session
              (pi-ai:make-user-message
               :content "root" :timestamp 1)))
           (first-leaf-id
             (pi-agent:session-append-message
              session
              (pi-ai:make-assistant-message
               :content
               (list (pi-ai:make-text-content :text "first"))
               :api :openai-responses
               :provider :openai
               :model "mock"
               :stop-reason :stop
               :timestamp 2))))
      (pi-agent:session-branch session root-id)
      (let ((second-leaf-id
              (pi-agent:session-append-message
               session
               (pi-ai:make-assistant-message
                :content
                (list (pi-ai:make-text-content :text "second"))
                :api :openai-responses
                :provider :openai
                :model "mock"
                :stop-reason :stop
                :timestamp 3))))
        (is (equal '("root" "first")
                   (message-texts
                    (pi-agent:session-messages
                     session first-leaf-id))))
        (is (equal '("root" "second")
                   (message-texts
                     (pi-agent:session-messages
                      session second-leaf-id))))
        (let ((loaded
                (pi-agent:load-session
                 (pi-agent:session-path session))))
          (is (string= second-leaf-id
                       (pi-agent:session-leaf-id loaded)))
          (is (equal '("root" "first")
                     (message-texts
                      (pi-agent:session-messages
                       loaded first-leaf-id))))
          (is (equal '("root" "second")
                     (message-texts
                      (pi-agent:session-messages
                       loaded second-leaf-id))))
          (pi-agent:session-branch loaded first-leaf-id)
          (let ((continued-id
                  (pi-agent:session-append-message
                   loaded
                   (pi-ai:make-user-message
                    :content "continue first" :timestamp 4))))
            (is (equal '("root" "first" "continue first")
                       (message-texts
                        (pi-agent:session-messages
                         (pi-agent:load-session
                          (pi-agent:session-path loaded))
                         continued-id))))))
        (let ((records (parse-json-lines
                        (pi-agent:session-path session))))
          (is (= 2 (pi-ai::json-get (first records) "version")))
          (dolist (record (rest records))
            (is (stringp (pi-ai::json-get record "id")))
            (multiple-value-bind (value present-p)
              (gethash "parentId" record)
              (declare (ignore value))
              (is (eq t present-p)))))))))

(test session-v1-load-migrates-atomically-without-losing-envelope-fields
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let ((path (merge-pathnames "legacy.jsonl" sessions))
          (canonical (pi-agent::canonical-session-cwd cwd)))
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
      (let ((loaded (pi-agent:load-session path)))
        (is (equal '("legacy text")
                   (message-texts
                    (pi-agent:session-messages loaded))))
        (let ((records (parse-json-lines path)))
          (is (= 2 (pi-ai::json-get (first records) "version")))
          (is (string= "kept"
                       (pi-ai::json-get
                        (first records) "future_header")))
          (is (= 7
                 (pi-ai::json-get
                  (pi-ai::json-get
                   (second records) "future_envelope")
                  "x")))
          (is (stringp
               (pi-ai::json-get (second records) "id")))
          (is (null
               (pi-ai::json-get
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
                  (pi-agent::canonical-session-cwd cwd))
          (dolist (record records)
            (format stream "~A~%" record)))
        (signals pi-agent:session-error
          (pi-agent:load-session path))))))

(test session-v2-round-trips-image-content
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let ((session
            (pi-agent:create-session
             :directory sessions :cwd cwd :id "image")))
      (pi-agent:session-append-message
       session
       (pi-ai:make-user-message
        :content
        (list
         (pi-ai:make-text-content :text "inspect")
         (pi-ai:make-image-content
          :mime-type "image/png" :data "YWJj"))))
      (let* ((loaded
               (pi-agent:load-session
                (pi-agent:session-path session)))
             (content
               (pi-ai:user-message-content
                (first (pi-agent:session-messages loaded)))))
        (is (typep (second content) 'pi-ai:image-content))
        (is (string= "image/png"
                     (pi-ai:image-content-mime-type
                      (second content))))
        (is (string= "YWJj"
                     (pi-ai:image-content-data
                      (second content))))))))

(test session-list-resume-and-html-export-cover-the-entire-tree
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((older
             (pi-agent:create-session
              :directory sessions :cwd cwd
              :id "older" :timestamp 10))
           (newer
             (pi-agent:create-session
              :directory sessions :cwd cwd
              :id "newer" :timestamp 20))
           (root-id
             (pi-agent:session-append-message
              newer
              (pi-ai:make-user-message
               :content "<script>alert(1)</script>")))
           (old-leaf
             (pi-agent:session-append-message
              newer
              (pi-ai:make-user-message :content "left"))))
      (values older)
      (pi-agent:session-branch newer root-id)
      (pi-agent:session-append-message
       newer (pi-ai:make-user-message :content "right"))
      (let ((listed
              (pi-agent:list-sessions
               :directory sessions :cwd cwd)))
        (is (equal '("newer" "older")
                   (mapcar #'pi-agent:session-id listed))))
      (let ((resumed
              (pi-agent:resume-session
               "newer" :directory sessions)))
        (is (string= "newer" (pi-agent:session-id resumed)))
        (is (equal '("<script>alert(1)</script>" "left")
                   (message-texts
                    (pi-agent:session-messages
                     resumed old-leaf)))))
      (let ((html-path (merge-pathnames "tree.html" sessions)))
        (pi-agent:export-session-html newer html-path)
        (let ((html
                (uiop:read-file-string
                 html-path :external-format :utf-8)))
          (is (search "&lt;script&gt;alert(1)&lt;/script&gt;"
                      html))
          (is (not (search "<script>alert(1)</script>" html)))
          (is (search "left" html))
          (is (search "right" html))
          (is (search root-id html)))))))
