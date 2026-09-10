(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(test goal28-rpc-bash-settings-reach-existing-executor
  (with-test-directory (directory)
    (let* ((global (merge-pathnames "settings.json" directory))
           (expected-prefix "shopt -s expand_aliases")
           (expected-shell "/bin/bash")
           (_
             (write-text
              global
              "{\"shellPath\":\"/bin/bash\",\"shellCommandPrefix\":\"shopt -s expand_aliases\"}"))
           (settings
             (cadr-cli::make-settings-manager
              :global-path global))
           (captured nil)
           (original
             (symbol-function
              'cadr-cli::execute-user-bash)))
      (declare (ignore _))
      (unwind-protect
           (progn
             (setf
              (symbol-function
               'cadr-cli::execute-user-bash)
              (lambda
                  (host cwd command
                   &key exclude-from-context-p
                     timeout abort-p
                     command-prefix
                     custom-shell-path)
                (declare
                 (ignore
                  host cwd command
                  exclude-from-context-p timeout
                  abort-p))
                (setf captured
                      (list
                       :command-prefix command-prefix
                       :custom-shell-path
                       custom-shell-path))
                (values
                 nil
                 (list :exit-code 0))))
             (let* ((output
                      (make-string-output-stream))
                    (extension-manager
                      (cadr-cli::make-cli-extension-manager
                       :cwd directory
                       :global-directory
                       (merge-pathnames
                        "extensions/" directory)
                       :output
                       (make-string-output-stream)
                       :mode :rpc))
                    (agent
                      (cadr-agent:make-agent
                       :provider :mock
                       :model
                       (cadr-ai:make-model
                        :id "mock"
                        :name "Mock"
                        :provider :openai
                        :api :openai-responses
                        :base-url
                        "https://example.invalid"
                        :max-tokens 1024)
                       :session
                       (cadr-agent:create-session
                        :directory directory
                        :cwd directory)
                       :stream-function
                       (lambda
                           (provider model context
                            on-event
                            &key max-tokens
                              temperature abort-p)
                         (declare
                          (ignore
                           provider model context
                           on-event max-tokens
                           temperature abort-p))
                         nil)))
                    (state
                      (cadr-cli::%make-rpc-state
                       :agent agent
                       :extension-manager
                       extension-manager
                       :input
                       (make-string-input-stream "")
                       :output output
                       :error-output
                       (make-string-output-stream)
                       :shell-command-prefix
                       (cadr-cli::settings-shell-command-prefix
                        settings)
                       :shell-path
                       (cadr-cli::settings-shell-path
                        settings))))
               (cadr-cli::rpc-handle-line
                state
                "{\"id\":\"bash-settings-1\",\"type\":\"bash\",\"command\":\"printf hi\"}")
               (let ((thread
                       (cadr-cli::rpc-state-bash-thread
                        state)))
                 (when thread
                   (sb-thread:join-thread thread)))
               (is (string=
                    expected-prefix
                    (getf captured :command-prefix)))
               (is (string=
                    expected-shell
                    (getf captured
                          :custom-shell-path)))))
        (setf
         (symbol-function
          'cadr-cli::execute-user-bash)
         original)))))
