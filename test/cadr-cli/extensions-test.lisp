(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun extension-source (body)
  (format nil "~A~%" body))

(defun make-test-extension-manager
    (cwd global output &optional explicit secret-function)
  (cadr-cli::make-cli-extension-manager
   :cwd cwd
   :global-directory global
   :explicit-paths explicit
   :output output
   :secret-function secret-function))

(test extension-discovery-loads-isolated-packages-and-obeys-precedence
  (with-test-directory (root)
    (let* ((cwd (merge-pathnames "project/" root))
           (global (merge-pathnames "global/" root))
           (project
             (merge-pathnames ".cadr/extensions/" cwd))
           (explicit
             (merge-pathnames "explicit/same.lisp" root))
           (output (make-string-output-stream)))
      (write-text
       (merge-pathnames "same.lisp" global)
       (extension-source
        "(define-prompt-template \"source\" :template \"global\")"))
      (write-text
       (merge-pathnames "same/extension.lisp" project)
       (extension-source
        "(define-prompt-template \"source\" :template \"project\")"))
      (write-text
       explicit
       (extension-source
        "(define-prompt-template \"source\" :template \"explicit\")"))
      (write-text
       (merge-pathnames "one.lisp" global)
       (extension-source "(defparameter *private-name* :one)"))
      (write-text
       (merge-pathnames "two.lisp" global)
       (extension-source "(defparameter *private-name* :two)"))
      (let ((manager
              (make-test-extension-manager
               cwd global output (list explicit))))
        (cadr-cli::reload-cli-extensions manager)
        (multiple-value-bind (text found-p)
            (cadr-cli::expand-cli-extension-prompt
             manager "/source")
          (is (not (null found-p)))
          (is (string= "explicit" text)))
        (let ((packages
                (cadr-cli::cli-extension-manager-package-names
                 manager)))
          (is (= (length packages)
                 (length (remove-duplicates packages
                                            :test #'string=))))
          (is (every #'find-package packages)))))))

(test later-cli-extension-wins-and-shadowed-sources-never-load
  (with-test-directory (root)
    (let* ((cwd (merge-pathnames "project/" root))
           (global (merge-pathnames "global/" root))
           (project
             (merge-pathnames ".cadr/extensions/" cwd))
           (earlier
             (merge-pathnames "earlier/same.lisp" root))
           (later
             (merge-pathnames "later/same.lisp" root))
           (output (make-string-output-stream)))
      (write-text
       (merge-pathnames "same.lisp" global)
       (extension-source
        "(error \"shadowed global source executed\")"))
      (write-text
       (merge-pathnames "same.lisp" project)
       (extension-source
        "(define-prompt-template \"source\" :template \"project\")"))
      (write-text
       earlier
       (extension-source
        "(define-prompt-template \"source\" :template \"earlier\")"))
      (write-text
       later
       (extension-source
        "(define-prompt-template \"source\" :template \"later\")"))
      (let* ((manager
               (make-test-extension-manager
                cwd global output
                (list earlier later)))
             (report
               (cadr-cli::reload-cli-extensions manager)))
        (is (null (getf report :errors)))
        (multiple-value-bind (text found-p)
            (cadr-cli::expand-cli-extension-prompt
             manager "/source")
          (is (not (null found-p)))
          (is (string= "later" text)))
        (is
         (not
          (search
           "shadowed global source executed"
           (get-output-stream-string output))))))))

(test reload-keeps-last-known-good-and-other-load-errors-do-not-stop-it
  (with-test-directory (root)
    (let* ((cwd (merge-pathnames "project/" root))
           (global (merge-pathnames "global/" root))
           (good (merge-pathnames "reloadable.lisp" global))
           (bad (merge-pathnames "bad.lisp" global))
           (output (make-string-output-stream))
           (manager
             (make-test-extension-manager cwd global output)))
      (write-text
       good
       (extension-source
        "(define-prompt-template \"value\" :template \"old\")"))
      (write-text bad (extension-source "(error \"load boom\")"))
      (let ((report (cadr-cli::reload-cli-extensions manager)))
        (is (= 1 (getf report :loaded)))
        (is (= 1 (length (getf report :errors)))))
      (write-text good (extension-source "(error \"reload boom\")"))
      (cadr-cli::reload-cli-extensions manager)
      (multiple-value-bind (text found-p)
          (cadr-cli::expand-cli-extension-prompt manager "/value")
        (is (not (null found-p)))
        (is (string= "old" text)))
      (let ((text (get-output-stream-string output)))
        (is (search "load boom" text))
        (is (search "reload boom" text))))))

(test extension-command-and-template-errors-are-contained
  (with-test-directory (root)
    (let* ((cwd (merge-pathnames "project/" root))
           (global (merge-pathnames "global/" root))
           (output (make-string-output-stream))
           (manager
             (make-test-extension-manager
              cwd global output nil
              (lambda () (list "phase7-secret")))))
      (write-text
       (merge-pathnames "errors.lisp" global)
       (extension-source
        (format
         nil
         "(define-command \"explode\" :handler (lambda (arguments context) (declare (ignore arguments context)) (error \"command boom phase7-secret\")))~%(define-prompt-template \"bad-template\" :template (lambda (argv context) (declare (ignore argv context)) (error \"template boom\")))")))
      (cadr-cli::reload-cli-extensions manager)
      (is (cadr-cli::handle-extension-command
           "/explode now" manager))
      (multiple-value-bind (text found-p)
          (cadr-cli::expand-cli-extension-prompt
           manager "/bad-template")
        (is (not (null found-p)))
        (is (string= "/bad-template" text)))
      (let ((text (get-output-stream-string output)))
        (is (search "command boom" text))
        (is (search "template boom" text))
        (is (search "[REDACTED]" text))
        (is (not (search "phase7-secret" text)))))))

(test builtin-command-wins-and-command-wins-over-template
  (with-test-directory (root)
    (let* ((cwd (merge-pathnames "project/" root))
           (global (merge-pathnames "global/" root))
           (output (make-string-output-stream))
           (manager
             (make-test-extension-manager cwd global output)))
      (write-text
       (merge-pathnames "priority.lisp" global)
       (extension-source
        (format
         nil
         "(define-command \"same\" :handler (lambda (arguments context) (declare (ignore arguments)) (extension-context-notify context \"command-won\")))~%(define-prompt-template \"same\" :template \"template-lost\")~%(define-command \"reload\" :handler (lambda (arguments context) (declare (ignore arguments)) (extension-context-notify context \"builtin-lost\")))")))
      (cadr-cli::reload-cli-extensions manager)
      (is (cadr-cli::handle-extension-command
           "/same value" manager))
      (is (cadr-cli::handle-extension-command
           "/reload" manager))
      (let ((text (get-output-stream-string output)))
        (is (search "command-won" text))
        (is (not (search "builtin-lost" text)))))))

(test self-extension-write-reload-and-tool-call-completes-in-one-agent
  (with-test-directory (root)
    (let* ((cwd (merge-pathnames "project/" root))
           (global (merge-pathnames "global/" root))
           (output (make-string-output-stream))
           (manager
             (make-test-extension-manager cwd global output))
           (extension-text
             (format
              nil
              "(define-tool \"self-echo\"~%  :description \"Self extension echo\"~%  :parameters (cadr-ai::json-object \"type\" \"object\" \"properties\" (cadr-ai::json-object \"value\" (cadr-ai::json-object \"type\" \"string\")) \"required\" (vector \"value\") \"additionalProperties\" nil)~%  :handler (lambda (call-id arguments context)~%             (declare (ignore call-id context))~%             (values (list (cadr-ai:make-text-content :text (format nil \"self:~~A\" (cadr-ai::json-get arguments \"value\")))) nil)))~%"))
           (responses
             (list
              (cadr-ai:make-assistant-message
               :content
               (list
                (cadr-ai:make-tool-call
                 :id "write-extension"
                 :name "write"
                 :arguments
                 (args
                  "path"
                  ".cadr/extensions/self/extension.lisp"
                  "content" extension-text)))
               :api :openai-responses
               :provider :openai
               :model "mock"
               :stop-reason :tool-use)
              (cadr-ai:make-assistant-message
               :content
               (list
                (cadr-ai:make-text-content :text "written"))
               :api :openai-responses
               :provider :openai
               :model "mock"
               :stop-reason :stop)
              (cadr-ai:make-assistant-message
               :content
               (list
                (cadr-ai:make-tool-call
                 :id "self-call"
                 :name "self-echo"
                 :arguments (args "value" "ok")))
               :api :openai-responses
               :provider :openai
               :model "mock"
               :stop-reason :tool-use)
              (cadr-ai:make-assistant-message
               :content
               (list
                (cadr-ai:make-text-content :text "finished"))
               :api :openai-responses
               :provider :openai
               :model "mock"
               :stop-reason :stop)))
           (host (cadr-cli::cli-extension-manager-host manager))
           (agent
             (cadr-agent:make-agent
              :provider :mock
              :model (cli-mock-model)
              :tools (cadr-cli:make-coding-tools cwd)
              :extension-host host
              :stream-function
              (lambda (provider model context on-event
                       &key max-tokens temperature abort-p)
                (declare
                 (ignore provider model context max-tokens
                         temperature abort-p))
                (let ((message (pop responses)))
                  (funcall
                   on-event
                   (cadr-ai:make-stream-event
                    :type :start :message message))
                  (funcall
                   on-event
                   (cadr-ai:make-stream-event
                    :type :done
                    :message message
                    :reason
                    (cadr-ai:assistant-message-stop-reason
                     message)))
                  message)))))
      (cadr-agent:agent-prompt agent "write the extension")
      (is (probe-file
           (merge-pathnames
            ".cadr/extensions/self/extension.lisp"
            cwd)))
      (is (cadr-cli::handle-extension-command
           "/reload" manager))
      (cadr-agent:agent-prompt agent "use the extension")
      (let ((self-result
              (find-if
               (lambda (message)
                 (and
                  (typep message 'cadr-ai:tool-result-message)
                  (string=
                   "self-call"
                   (cadr-ai:tool-result-message-tool-call-id
                    message))))
               (cadr-agent:agent-messages agent))))
        (is (not (null self-result)))
        (is (string= "self:ok" (result-text
                                (cadr-ai:tool-result-message-content
                                 self-result)))))
      (is (null responses)))))

(test install-validates-url-uses-argv-and-never-overwrites
  (with-test-directory (root)
    (let* ((cwd (merge-pathnames "project/" root))
           (global (merge-pathnames "global/" root))
           (output (make-string-output-stream))
           (manager
             (make-test-extension-manager cwd global output))
           (captured nil)
           (runner
             (lambda (argv)
               (setf captured argv)
               (let ((target
                       (pathname (car (last argv)))))
                 (write-text
                  (merge-pathnames "extension.lisp" target)
                  (extension-source
                   "(define-prompt-template \"installed\" :template \"yes\")"))))))
      (cadr-cli::install-extension-package
       manager
       "https://example.com/acme/demo.git"
       :runner runner)
      (is (equal
           '("git" "clone" "--"
             "https://example.com/acme/demo.git")
           (butlast captured)))
      (is (probe-file
           (merge-pathnames "demo/extension.lisp" global)))
      (signals error
        (cadr-cli::install-extension-package
         manager
         "https://example.com/acme/demo.git"
         :runner runner))
      (dolist (invalid
               '("file:///tmp/repo"
                 "/tmp/repo"
                 "-uhoh"
                 "https://example.com/a/../b.git"))
        (signals error
          (cadr-cli::install-extension-package
           manager invalid :runner runner))))))

(defun unused-loopback-port ()
  (require :sb-bsd-sockets)
  (let ((socket
          (make-instance
           'sb-bsd-sockets:inet-socket
           :type :stream
           :protocol :tcp)))
    (unwind-protect
         (progn
           (sb-bsd-sockets:socket-bind
            socket
            (sb-bsd-sockets:make-inet-address
             "127.0.0.1")
            0)
           (nth-value
            1
            (sb-bsd-sockets:socket-name socket)))
      (sb-bsd-sockets:socket-close socket))))

(test install-clones-a-real-local-git-daemon-repository
  (with-test-directory (root)
    (let* ((cwd (merge-pathnames "project/" root))
           (global (merge-pathnames "global/" root))
           (repositories
             (merge-pathnames "repositories/" root))
           (repository
             (merge-pathnames "demo/" repositories))
           (output (make-string-output-stream))
           (manager
             (make-test-extension-manager cwd global output))
           (port (unused-loopback-port))
           (daemon nil))
      (write-text
       (merge-pathnames "extension.lisp" repository)
       (extension-source
        "(define-prompt-template \"installed-real\" :template \"yes\")"))
      (dolist
          (argv
           (list
            (list "git" "init" (namestring repository))
            (list "git" "-C" (namestring repository)
                  "config" "user.email" "cadr@example.invalid")
            (list "git" "-C" (namestring repository)
                  "config" "user.name" "cadr test")
            (list "git" "-C" (namestring repository)
                  "add" "extension.lisp")
            (list "git" "-C" (namestring repository)
                  "commit" "-m" "fixture")))
        (uiop:run-program
         argv :output nil :error-output nil))
      (unwind-protect
           (progn
             (setf
              daemon
              (uiop:launch-program
               (list
                "git" "daemon"
                "--reuseaddr"
                "--export-all"
                (format nil "--base-path=~A"
                        (namestring repositories))
                "--listen=127.0.0.1"
                (format nil "--port=~D" port)
                (namestring repositories))
               :output nil
               :error-output nil))
             (sleep 0.2)
             (cadr-cli::install-extension-package
              manager
              (format nil
                      "git://127.0.0.1:~D/demo"
                      port))
             (is
              (probe-file
               (merge-pathnames
                "demo/extension.lisp" global)))
             (multiple-value-bind (text found-p)
                 (cadr-cli::expand-cli-extension-prompt
                  manager "/installed-real")
               (is (not (null found-p)))
               (is (string= "yes" text))))
        (when daemon
          (uiop:terminate-process daemon)
          (uiop:wait-process daemon))))))
