(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defparameter +goal28-pin-slash-commands+
  '("bug" "changelog" "clone" "compact" "copy" "export"
    "fork" "hotkeys" "import" "login" "logout"
    "model" "name" "new" "quit" "reload" "resume"
    "scoped-models" "session" "settings" "share"
    "thinking" "tree" "trust"))

(test goal28-slash-commands-reach-existing-surfaces
  (let ((names
          (mapcar
           #'first
           cadr-cli::+tui-autocomplete-command-specifications+)))
    (is (= (length +goal28-pin-slash-commands+)
           (length names)))
    (dolist (command +goal28-pin-slash-commands+)
      (is (find command names :test #'string=))))
  (with-test-directory (root)
    (let* ((sessions
             (merge-pathnames "sessions/" root))
           (cwd (merge-pathnames "cwd/" root))
           (changelog
             (merge-pathnames "CHANGELOG.md" root))
           (_
             (progn
               (ensure-directories-exist sessions)
               (ensure-directories-exist cwd)
               (write-text
                changelog
                (format nil
                        "## [0.1.0]~%~%### Added~%~%- goal28~%"))))
           (session
             (cadr-agent:create-session
              :directory sessions
              :cwd cwd
              :id "slash"
              :timestamp 1))
           (agent
             (cadr-agent:make-agent
              :session session
              :provider nil
              :model nil))
           (out (make-string-output-stream)))
      (declare (ignore _))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-assistant-message
        :content
        (list
         (cadr-ai:make-text-content
          :text "hello"))
        :api :openai-responses
        :provider :openai
        :model "mock"
        :stop-reason :stop
        :timestamp 2))
      (is (eq t
              (cadr-cli::handle-session-command
               "/changelog" agent
               :directory sessions
               :cwd cwd
               :output out
               :changelog-path changelog)))
      (is (eq t
              (cadr-cli::handle-session-command
               "/hotkeys" agent
               :directory sessions
               :cwd cwd
               :output out)))
      (is (eq t
              (cadr-cli::handle-session-command
               "/session" agent
               :directory sessions
               :cwd cwd
               :output out)))
      (is (eq t
              (cadr-cli::handle-session-command
               "/name slash-name" agent
               :directory sessions
               :cwd cwd
               :output out)))
      (is (eq t
              (cadr-cli::handle-session-command
               "/copy" agent
               :directory sessions
               :cwd cwd
               :output out
               :copy-function
               (lambda (text)
                 (declare (ignore text))
                 nil))))
      (is (eq t
              (cadr-cli::handle-session-command
               "/compact" agent
               :directory sessions
               :cwd cwd
               :output out)))
      (is (search
           "What's New"
           (get-output-stream-string out))))))
