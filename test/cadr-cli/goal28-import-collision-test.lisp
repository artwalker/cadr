(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(test import-preserves-existing-session-with-same-filename
  (with-test-directory (root)
    (let* ((sessions
             (merge-pathnames "sessions/" root))
           (import-dir
             (merge-pathnames "import/" root))
           (cwd
             (merge-pathnames "project/" root)))
      (ensure-directories-exist
       (merge-pathnames "anchor" sessions))
      (ensure-directories-exist
       (merge-pathnames "anchor" import-dir))
      (ensure-directories-exist
       (merge-pathnames "anchor" cwd))
      (let* ((agent
               (cadr-agent:make-agent
                :provider :mock
                :model
                (cadr-ai:make-model
                 :id "mock"
                 :provider :openai
                 :api :openai-responses
                 :base-url "https://example.invalid"
                 :max-tokens 128)
                :session
                (cadr-agent:create-session
                 :directory sessions
                 :cwd cwd
                 :id "source")))
             (stored
               (cadr-agent:create-session
                :directory sessions
                :cwd cwd
                :id "collision"))
             (stored-path
               (cadr-agent:session-path stored))
             (external
               (cadr-agent:create-session
                :directory import-dir
                :cwd cwd
                :id "imported"))
             (import-path
               (merge-pathnames
                "collision.jsonl" import-dir)))
        (cadr-agent:session-append-message
         stored
         (cadr-ai:make-assistant-message
          :content
          (list
           (cadr-ai:make-text-content
            :text "stored-marker"))
          :api :openai-responses
          :provider :openai
          :model "mock"
          :stop-reason :stop))
        (cadr-agent::close-session-journal-stream
         stored)
        (cadr-agent:session-append-message
         external
         (cadr-ai:make-assistant-message
          :content
          (list
           (cadr-ai:make-text-content
            :text "imported-marker"))
          :api :openai-responses
          :provider :openai
          :model "mock"
          :stop-reason :stop))
        (cadr-agent::close-session-journal-stream
         external)
        (rename-file
         (cadr-agent:session-path external)
         import-path)
        (let ((stored-before
                (uiop:read-file-string stored-path)))
          (multiple-value-bind
                (imported error-message)
              (cadr-cli::import-agent-session
               agent
               (namestring import-path)
               sessions
               cwd)
            (is (cadr-agent::session-p imported))
            (is (null error-message))
            (is
             (string=
              stored-before
              (uiop:read-file-string stored-path)))
            (is
             (not
              (cadr-cli::same-session-file-p
               stored-path
               (cadr-agent:session-path imported))))
            (is
             (search
              "imported-marker"
              (uiop:read-file-string
               (cadr-agent:session-path
                imported))))))))))
