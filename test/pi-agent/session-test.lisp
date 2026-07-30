(in-package #:pi-agent/tests)
(in-suite pi-agent-suite)

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
             (pi-agent::create-session
              :directory sessions
              :cwd cwd
              :id "roundtrip"
              :timestamp 100))
           (user
             (pi-ai:make-user-message
              :content "hello" :timestamp 101))
           (assistant-message
             (pi-ai:make-assistant-message
              :content
              (list
               (pi-ai:make-text-content :text "thinking done")
               (pi-ai:make-thinking-content
                :thinking "private thought"
                :signature "sig")
               (pi-ai:make-tool-call
                :id "call-1"
                :name "read"
                :arguments (pi-ai::json-object "path" "README.md")))
              :api :anthropic-messages
              :provider :anthropic
              :model "claude-test"
              :response-id "msg-1"
              :usage (pi-ai:make-usage
                      :input 10 :output 5
                      :cache-read 2 :cache-write 1)
              :stop-reason :tool-use
              :raw-stop-reason "tool_use"
              :timestamp 102))
           (result
             (pi-ai:make-tool-result-message
              :tool-call-id "call-1"
              :tool-name "read"
              :content
              (list (pi-ai:make-text-content :text "contents"))
              :details (list :path "README.md" :truncated nil)
              :timestamp 103)))
      (dolist (message (list user assistant-message result))
        (pi-agent::session-append-message session message))
      (let* ((loaded
               (pi-agent::load-session
                (pi-agent::session-path session)))
             (messages (pi-agent::session-messages loaded))
             (loaded-assistant (second messages)))
        (is (string= "roundtrip"
                     (pi-agent::session-id loaded)))
        (is (= 3 (length messages)))
        (is (typep (first messages) 'pi-ai:user-message))
        (is (typep loaded-assistant 'pi-ai:assistant-message))
        (is (typep (third messages)
                   'pi-ai:tool-result-message))
        (is (= 18
               (pi-ai:usage-total
                (pi-ai:assistant-message-usage
                 loaded-assistant))))
        (is (typep
             (third
              (pi-ai:assistant-message-content
               loaded-assistant))
             'pi-ai:tool-call))
        (is (not
             (search
              "api-key"
              (uiop:read-file-string
               (pi-agent::session-path session)
               :external-format :utf-8))))))))

(test session-loader-ignores-only-an-incomplete-final-line
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let ((session
            (pi-agent::create-session
             :directory sessions :cwd cwd :id "tail")))
      (pi-agent::session-append-message
       session (pi-ai:make-user-message :content "kept"))
      (with-open-file
          (stream (pi-agent::session-path session)
                  :direction :output
                  :if-exists :append
                  :external-format :utf-8)
        (write-string "{\"type\":\"message\"" stream))
      (is (= 1
             (length
              (pi-agent::session-messages
               (pi-agent::load-session
                (pi-agent::session-path session)))))))
    (let ((session
            (pi-agent::create-session
             :directory sessions :cwd cwd :id "middle")))
      (with-open-file
          (stream (pi-agent::session-path session)
                  :direction :output
                  :if-exists :append
                  :external-format :utf-8)
        (format stream "{broken}~%"))
      (pi-agent::session-append-message
       session (pi-ai:make-user-message :content "after"))
      (signals pi-agent::session-error
        (pi-agent::load-session
         (pi-agent::session-path session))))))

(test continue-session-selects-latest-canonical-matching-cwd
  (with-session-directories (sessions cwd other-cwd)
    (pi-agent::create-session
     :directory sessions :cwd cwd :id "older" :timestamp 10)
    (pi-agent::create-session
     :directory sessions :cwd other-cwd :id "other" :timestamp 30)
    (pi-agent::create-session
     :directory sessions :cwd cwd :id "newer" :timestamp 20)
    (let ((continued
            (pi-agent::continue-session
             :directory sessions :cwd cwd)))
      (is (string= "newer"
                   (pi-agent::session-id continued))))))

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
              (pi-agent::canonical-session-cwd cwd)))
    (signals pi-agent::session-error
      (pi-agent::continue-session
       :directory sessions :cwd cwd))))

(test agent-flushes-final-user-and-assistant-messages-to-session
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((session
             (pi-agent::create-session
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
                (pi-agent::load-session
                 (pi-agent::session-path session))))
          (is (= 2
                 (length
                  (pi-agent::session-messages loaded))))
          (is (string=
               "save me"
               (pi-ai:user-message-content
                (first
                 (pi-agent::session-messages loaded))))))))))
