(in-package #:cadr-cli/tests)

(in-suite cadr-cli-suite)

(fiveam:test goal28-missing-session-cwd-reaches-existing-import
  (with-test-directory (root)
    (let* ((sessions (merge-pathnames "sessions/" root))
           (cwd (merge-pathnames "project/" root))
           (agent
             (cadr-agent:make-agent
              :provider :mock
              :model (cli-mock-model))))
      (ensure-directories-exist
       (merge-pathnames "anchor" sessions))
      (ensure-directories-exist
       (merge-pathnames "anchor" cwd))
      (let* ((session
               (cadr-agent:create-session
                :directory sessions :cwd cwd :id "gone-cwd"))
             (source
               (namestring (cadr-agent:session-path session)))
             (stored-cwd (cadr-agent:session-cwd session))
             (seen nil)
             (original (fdefinition 'cl:error)))
        (cadr-agent:session-append-message
         session
         (cadr-ai:make-assistant-message
          :content
          (list (cadr-ai:make-text-content :text "persist"))
          :api :openai-responses
          :provider :openai
          :model "mock"
          :stop-reason :stop))
        (cadr-agent::close-session-journal-stream session)
        (uiop:delete-directory-tree
         cwd :validate t :if-does-not-exist :ignore)
        (unwind-protect
             (progn
               (sb-ext:without-package-locks
                 (setf
                  (fdefinition 'cl:error)
                  (lambda (&rest arguments)
                    (handler-bind
                        ((cadr-cli::missing-session-cwd-error
                          (lambda (condition)
                            (setf seen condition))))
                      (apply original arguments)))))
               (multiple-value-bind (imported error-message)
                   (cadr-cli::import-agent-session
                    agent source sessions root)
                 (is (null imported))
                 (is (typep seen
                            'cadr-cli::missing-session-cwd-error))
                 (is (equal
                      stored-cwd
                      (cadr-cli::missing-session-cwd-error-session-cwd
                       seen)))
                 (is (string=
                      (format
                       nil
                       "Session working directory does not exist: ~A"
                       stored-cwd)
                      error-message))))
          (sb-ext:without-package-locks
            (setf (fdefinition 'cl:error) original)))))))

(fiveam:test goal28-missing-session-cwd-prompt-continues-in-the-fallback
  (is (string=
       (format nil
               "cwd from session file does not exist~%/missing~%~%continue in current cwd~%/here")
       (cadr-cli::missing-session-cwd-prompt "/missing" "/here")))
  (with-test-directory (root)
    (let* ((sessions (merge-pathnames "sessions/" root))
           (cwd (merge-pathnames "project/" root))
           (agent
             (cadr-agent:make-agent
              :provider :mock
              :model (cli-mock-model))))
      (ensure-directories-exist
       (merge-pathnames "anchor" sessions))
      (ensure-directories-exist
       (merge-pathnames "anchor" cwd))
      (let* ((session
               (cadr-agent:create-session
                :directory sessions :cwd cwd :id "gone-cwd-override"))
             (source
               (namestring (cadr-agent:session-path session))))
        (cadr-agent:session-append-message
         session
         (cadr-ai:make-assistant-message
          :content
          (list (cadr-ai:make-text-content :text "persist"))
          :api :openai-responses
          :provider :openai
          :model "mock"
          :stop-reason :stop))
        (cadr-agent::close-session-journal-stream session)
        (is (null
             (cadr-cli::missing-session-cwd-issue session root)))
        (uiop:delete-directory-tree
         cwd :validate t :if-does-not-exist :ignore)
        (is (equal
             (list :session-cwd
                   (namestring (cadr-agent:session-cwd session))
                   :fallback-cwd (namestring root)
                   :session-file source)
             (cadr-cli::missing-session-cwd-issue session root)))
        (multiple-value-bind (imported error-message)
            (cadr-cli::import-agent-session
             agent source sessions root
             :cwd-override root)
          (is (cadr-agent::session-p imported))
          (is (null error-message))
          (is (equal
               (cadr-agent::canonical-session-cwd root)
               (cadr-agent:session-cwd imported))))))))
