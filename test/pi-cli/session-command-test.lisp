(in-package #:pi-cli/tests)
(in-suite pi-cli-suite)

(defun cli-mock-model ()
  (pi-ai:make-model
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
      (pi-agent:create-session
       :directory sessions :cwd cwd :id "wanted")
      (let ((session
              (pi-cli::resolve-cli-session
               :resume-id "wanted"
               :cwd cwd
               :directory sessions
               :output output)))
        (is (string= "wanted"
                     (pi-agent:session-id session))))
      (signals pi-ai:configuration-error
        (pi-cli::resolve-cli-session
         :continue-p t
         :resume-id "wanted"
         :cwd cwd
         :directory sessions
         :output output))
      (signals pi-agent:session-error
        (pi-cli::resolve-cli-session
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
             (pi-agent:create-session
              :directory sessions :cwd cwd :id "first"))
           (second
             (pi-agent:create-session
              :directory sessions :cwd cwd :id "second"))
           (first-node
             (pi-agent:session-append-message
              first
              (pi-ai:make-user-message :content "first root")))
           (agent
             (pi-agent:make-agent
              :provider :mock
              :model (cli-mock-model)
              :session second))
           (output (make-string-output-stream))
           (export-path (merge-pathnames "export.html" root)))
      (declare (ignore _))
      (is (pi-cli::handle-session-command
           "/sessions" agent
           :directory sessions :cwd cwd :output output))
      (is (pi-cli::handle-session-command
           "/switch first" agent
           :directory sessions :cwd cwd :output output))
      (is (string= "first"
                   (pi-agent:session-id
                    (pi-agent:agent-session agent))))
      (is (pi-cli::handle-session-command
           (format nil "/branch ~A" first-node)
           agent
           :directory sessions :cwd cwd :output output))
      (is (pi-cli::handle-session-command
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
