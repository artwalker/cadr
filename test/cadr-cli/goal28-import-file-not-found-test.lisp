(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(test goal28-import-file-not-found-reaches-existing-import
  (with-test-directory (root)
    (let* ((sessions
             (merge-pathnames "sessions/" root))
           (cwd
             (merge-pathnames "project/" root))
           (_
             (ensure-directories-exist
              (merge-pathnames "anchor" cwd)))
           (missing
             (merge-pathnames "missing.jsonl" cwd))
           (expected
             (cadr-cli::resolve-general-path
              (namestring missing)
              cwd))
           (agent
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
               :id "source"))))
      (declare (ignore _))
      (handler-case
          (progn
            (cadr-cli::import-agent-session
             agent (namestring missing) sessions cwd)
            (fail
             "expected session-import-file-not-found-error"))
        (cadr-cli::session-import-file-not-found-error
            (condition)
          (is
           (equal
            expected
            (cadr-cli::session-import-file-not-found-error-file-path
             condition))))))))
