(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun cli-mock-model ()
  (cadr-ai:make-model
   :id "mock"
   :provider :openai
   :api :openai-responses
   :base-url "https://example.invalid"
   :max-tokens 128))

(test resume-option-selects-exact-session-and-conflicts-with-continue
  (with-test-directory (root)
    (let ((sessions (merge-pathnames "sessions/" root))
          (cwd (merge-pathnames "project/" root))
          (output (make-string-output-stream)))
      (ensure-directories-exist
       (merge-pathnames "anchor" sessions))
      (ensure-directories-exist
       (merge-pathnames "anchor" cwd))
      (let ((wanted
              (cadr-agent:create-session
               :directory sessions :cwd cwd :id "wanted")))
        (cadr-agent:session-append-message
         wanted
         (cadr-ai:make-assistant-message
          :content
          (list (cadr-ai:make-text-content :text "persist"))
          :api :openai-responses
          :provider :openai
          :model "mock"
          :stop-reason :stop)))
      (let ((session
              (cadr-cli::resolve-cli-session
               :resume-id "wanted"
               :cwd cwd
               :directory sessions
               :output output)))
        (is (string= "wanted"
                     (cadr-agent:session-id session))))
      (signals cadr-ai:configuration-error
        (cadr-cli::resolve-cli-session
         :continue-p t
         :resume-id "wanted"
         :cwd cwd
         :directory sessions
         :output output))
      (signals cadr-agent:session-error
        (cadr-cli::resolve-cli-session
         :resume-id "missing"
         :cwd cwd
         :directory sessions
         :output output)))))

(test session-commands-list-switch-branch-and-export
  (with-test-directory (root)
    (let* ((sessions (merge-pathnames "sessions/" root))
           (cwd (merge-pathnames "project/" root))
           (_
             (ensure-directories-exist
              (merge-pathnames "anchor" cwd)))
           (first
             (cadr-agent:create-session
              :directory sessions :cwd cwd :id "first"))
           (second
             (cadr-agent:create-session
              :directory sessions :cwd cwd :id "second"))
           (first-node
             (cadr-agent:session-append-message
              first
              (cadr-ai:make-user-message :content "first root")))
           (agent
             (cadr-agent:make-agent
              :provider :mock
              :model (cli-mock-model)
              :session second))
           (output (make-string-output-stream))
           (export-path (merge-pathnames "export.html" root)))
      (declare (ignore _))
      (cadr-agent:session-append-message
       first
       (cadr-ai:make-assistant-message
        :content (list (cadr-ai:make-text-content :text "first answer"))
        :api :openai-responses
        :provider :openai
        :model "mock"
        :stop-reason :stop))
      (cadr-agent:session-append-message
       second
       (cadr-ai:make-assistant-message
        :content (list (cadr-ai:make-text-content :text "second answer"))
        :api :openai-responses
        :provider :openai
        :model "mock"
        :stop-reason :stop))
      (is (cadr-cli::handle-session-command
           "/sessions" agent
           :directory sessions :cwd cwd :output output))
      (is (cadr-cli::handle-session-command
           "/switch first" agent
           :directory sessions :cwd cwd :output output))
      (is (string= "first"
                   (cadr-agent:session-id
                    (cadr-agent:agent-session agent))))
      (is (cadr-cli::handle-session-command
           (format nil "/branch ~A" first-node)
           agent
           :directory sessions :cwd cwd :output output))
      (is (cadr-cli::handle-session-command
           (format nil "/export ~A" (namestring export-path))
           agent
           :directory sessions :cwd cwd :output output))
      (is (probe-file export-path))
      (let ((text (get-output-stream-string output)))
        (is (search "first" text))
        (is (search "second" text))
        (is (search "Switched to session first" text))
        (is (search "Branch point" text))
        (is (search "Exported" text))))))
