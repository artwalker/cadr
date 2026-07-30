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

(test copy-clone-and-import-commands-match-interactive-session-semantics
  (with-test-directory (root)
    (let* ((sessions
             (merge-pathnames "sessions/" root))
           (imports
             (merge-pathnames "imports/" root))
           (cwd
             (merge-pathnames "project/" root))
           (_
             (ensure-directories-exist
              (merge-pathnames "anchor" cwd)))
           (source
             (cadr-agent:create-session
              :directory sessions
              :cwd cwd
              :id "source"))
           (agent
             (cadr-agent:make-agent
              :provider :mock
              :model (cli-mock-model)
              :session source))
           (copied nil)
           (output
             (make-string-output-stream)))
      (declare (ignore _))
      (cadr-agent:session-append-message
       source
       (cadr-ai:make-user-message
        :content "question"))
      (cadr-agent:session-append-message
       source
       (cadr-ai:make-assistant-message
        :content
        (list
         (cadr-ai:make-text-content
          :text " first ")
         (cadr-ai:make-thinking-content
          :thinking "hidden")
         (cadr-ai:make-text-content
          :text "second "))
        :api :openai-responses
        :provider :openai
        :model "mock"
        :stop-reason :stop))
      (setf
       (cadr-agent:agent-messages agent)
       (cadr-agent:session-messages source))
      (is
       (cadr-cli::handle-session-command
        "/copy" agent
        :directory sessions
        :cwd cwd
        :output output
        :copy-function
        (lambda (text)
          (setf copied text))))
      (is (string= "first second" copied))
      (let ((old-path
              (cadr-agent:session-path source)))
        (is
         (cadr-cli::handle-session-command
          "/clone" agent
          :directory sessions
          :cwd cwd
          :output output))
        (is (not
             (string=
              "source"
              (cadr-agent:session-id
               (cadr-agent:agent-session agent)))))
        (is (string=
             (namestring old-path)
             (cadr-agent:session-parent-session
              (cadr-agent:agent-session agent))))
        (is (= 2
               (length
                (cadr-agent:session-messages
                 (cadr-agent:agent-session agent))))))
      (let ((imported
              (cadr-agent:create-session
               :directory imports
               :cwd cwd
               :id "outside")))
        (cadr-agent:session-append-message
         imported
         (cadr-ai:make-assistant-message
          :content
          (list
           (cadr-ai:make-text-content
            :text "imported"))
          :api :openai-responses
          :provider :openai
          :model "mock"
          :stop-reason :stop))
        (is
         (cadr-cli::handle-session-command
          (format nil "/import \"~A\""
                  (namestring
                   (cadr-agent:session-path imported)))
          agent
          :directory sessions
          :cwd cwd
          :output output
          :confirm-function
          (lambda (title message)
            (is (string= "Import session" title))
            (is (search "Replace current session"
                        message))
            t)))
        (is (string= "outside"
                     (cadr-agent:session-id
                      (cadr-agent:agent-session
                       agent))))
        (is (probe-file
             (merge-pathnames
              "outside.jsonl" sessions))))
      (is
       (cadr-cli::handle-session-command
        "/import /does/not/exist.jsonl"
        agent
        :directory sessions
        :cwd cwd
        :output output
        :confirm-function
        (lambda (title message)
          (declare (ignore title message))
          t)))
      (let ((text
              (get-output-stream-string
               output)))
        (is (search
             "Copied last agent message to clipboard"
             text))
        (is (search
             "Cloned to new session" text))
        (is (search
             "Session imported from:" text))
        (is (search
             "Failed to import session: File not found:"
             text))))))

(test name-session-new-and-fork-commands-match-interactive-semantics
  (with-test-directory (root)
    (let* ((sessions
             (merge-pathnames "sessions/" root))
           (cwd
             (merge-pathnames "project/" root))
           (_
             (ensure-directories-exist
              (merge-pathnames "anchor" cwd)))
           (source
             (cadr-agent:create-session
              :directory sessions
              :cwd cwd
              :id "source"))
           (agent
             (cadr-agent:make-agent
              :provider :mock
              :model (cli-mock-model)
              :session source))
           (output
             (make-string-output-stream)))
      (declare (ignore _))
      (let ((first-user
              (cadr-agent:session-append-message
               source
               (cadr-ai:make-user-message
                :content "first question"))))
        (cadr-agent:session-append-message
         source
         (cadr-ai:make-assistant-message
          :content
          (list
           (cadr-ai:make-text-content
            :text "answer"))
          :api :openai-responses
          :provider :openai
          :model "mock"
          :usage
          (cadr-ai:make-usage
           :input 10
           :output 5
           :cache-read 2
           :cache-write 3
           :cost
           (cadr-ai:make-cost
            :input 0.01d0
            :output 0.02d0
            :cache-read 0.003d0
            :cache-write 0.004d0
            :total 0.037d0))
          :stop-reason :stop))
        (cadr-agent:session-append-compaction
         source
         "summary"
         (list first-user)
         first-user
         20
         :usage
         (cadr-ai:make-usage
          :input 4
          :output 2
          :cache-read 1
          :cost
          (cadr-ai:make-cost
           :input 0.004d0
           :output 0.005d0
           :cache-read 0.001d0
           :total 0.01d0)))
        (setf
         (cadr-agent:agent-messages agent)
         (cadr-agent:session-messages source))
        (is
         (cadr-cli::handle-session-command
          (format nil "/name   sprint~%review  ")
          agent
          :directory sessions
          :cwd cwd
          :output output))
        (is (string=
             "sprint review"
             (cadr-agent:session-name source)))
        (is
         (cadr-cli::handle-session-command
          "/name"
          agent
          :directory sessions
          :cwd cwd
          :output output))
        (is
         (cadr-cli::handle-session-command
          "/session"
          agent
          :directory sessions
          :cwd cwd
          :output output))
        (multiple-value-bind
              (fork selected-text)
            (cadr-cli::fork-agent-session
             agent first-user sessions)
          (is (typep fork 'cadr-agent:session))
          (is (string= "first question"
                       selected-text))
          (is (null
               (cadr-agent:session-messages
                fork)))
          (is (string=
               (namestring
                (cadr-agent:session-path source))
               (cadr-agent:session-parent-session
                fork))))
        (let ((new
                (cadr-cli::new-agent-session
                 agent sessions cwd)))
          (is (typep new 'cadr-agent:session))
          (is (null
               (cadr-agent:session-messages new)))
          (is (eq new
                  (cadr-agent:agent-session
                   agent)))))
      (let ((text
              (get-output-stream-string
               output)))
        (is (search "Session name set: sprint review"
                    text))
        (is (search "Session name: sprint review"
                    text))
        (is (search "Session Info" text))
        (is (search "User: 1" text))
        (is (search "Assistant: 1" text))
        (is (search "Input: 20" text))
        (is (search "Output: 7" text))
        (is (search "Total: 27" text))
        (is (search "Cost" text))
        (is (search "$0.047" text))))))
