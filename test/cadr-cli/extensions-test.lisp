(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun extension-source (body)
  (format nil "~A~%" body))

(defun make-test-extension-manager
    (cwd global output
     &optional explicit secret-function extension-factories)
  (cadr-cli::make-cli-extension-manager
   :cwd cwd
   :global-directory global
   :explicit-paths explicit
   :extension-factories extension-factories
   :output output
   :secret-function secret-function))

(test inline-extension-factories-rerun-and-preserve-baseline-naming
  (with-test-directory (root)
    (let* ((cwd (merge-pathnames "project/" root))
           (global (merge-pathnames "global/" root))
           (output (make-string-output-stream))
           (runs nil)
           (apis nil)
           (manager
             (cadr-cli::make-cli-extension-manager
              :cwd cwd
              :global-directory global
              :output output
              :extension-factories
              (list
               (lambda (api)
                 (push :bare runs)
                 (push api apis)
                 (cadr-agent::define-flag
                  "bare" :type :boolean :default t))
               (list
                :name "named"
                :factory
                (lambda (api)
                  (push :named runs)
                  (push api apis)
                  (cadr-agent::define-flag
                   "named" :type :string
                   :default "yes"))
                :hidden-p t)))))
      (let ((first
              (cadr-cli::reload-cli-extensions
               manager)))
        (is (= 3 (getf first :active)))
        (is (= 3 (getf first :loaded))))
      (let* ((host
               (cadr-cli::cli-extension-manager-host
                manager))
             (bundles
               (cadr-agent::extension-snapshot-bundles
                (cadr-agent::extension-host-current-snapshot
                 host))))
        (is (equal
             '("<inline:llama.cpp>"
               "<inline:1>"
               "<inline:named>")
             (mapcar
              #'cadr-agent::extension-bundle-path
              bundles)))
        (is
         (cadr-agent::extension-bundle-hidden-p
          (first bundles)))
        (is (null
             (cadr-agent::extension-bundle-hidden-p
              (second bundles))))
        (is
         (cadr-agent::extension-bundle-hidden-p
          (third bundles))))
      (let ((old-apis (copy-list apis)))
        (cadr-cli::reload-cli-extensions manager)
        (is (= 4 (length runs)))
        (dolist (api old-apis)
          (signals cadr-agent:stale-extension-context
            (cadr-agent::extension-api-get-flag
             api "bare")))))))

(test cli-extension-ui-bridge-delegates-theme-custom-autocomplete-and-expansion
  (with-test-directory (root)
    (let* ((calls nil)
           (manager
             (cadr-cli::make-cli-extension-manager
              :cwd root
              :global-directory
              (merge-pathnames "global/" root)
              :output (make-string-output-stream))))
      (cadr-cli::configure-extension-ui-bridge
       manager
       :custom-function
       (lambda (factory overlay-p overlay-options)
         (push
          (list :custom
                (funcall factory)
                overlay-p overlay-options)
          calls)
         :custom-result)
       :autocomplete-function
       (lambda (factory)
         (push (list :autocomplete factory) calls))
       :theme-function
       (lambda () '(:name "dark"))
       :all-themes-function
       (lambda ()
         '((:name "dark") (:name "light")))
       :get-theme-function
       (lambda (name)
         (list :name name))
       :set-theme-function
       (lambda (theme)
         (list :success (string= theme "light")))
       :tools-expanded-function (constantly t)
       :set-tools-expanded-function
       (lambda (expanded-p)
         (push (list :expanded expanded-p) calls)))
      (let ((ui
              (cadr-agent::extension-host-ui-function
               (cadr-cli::cli-extension-manager-host
                manager))))
        (is (eq
             :custom-result
             (funcall
              ui :custom
              (list
               :factory (lambda () '("line"))
               :overlay-p t
               :overlay-options '(:width 40)))))
        (funcall
         ui :add-autocomplete-provider
         (list :factory (lambda () nil)))
        (is (equal
             '(:name "dark")
             (funcall ui :theme nil)))
        (is (= 2
               (length
                (funcall ui :all-themes nil))))
        (is (equal
             '(:name "light")
             (funcall ui :get-theme
                      '(:name "light"))))
        (is (equal
             '(:success t)
             (funcall ui :set-theme
                      '(:theme "light"))))
        (is (funcall ui :tools-expanded-p nil))
        (funcall ui :set-tools-expanded
                 '(:expanded-p nil))
        (is (member :custom calls :key #'first))
        (is (member :autocomplete calls :key #'first))
        (is (member :expanded calls :key #'first))))))

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

(test extension-reload-keeps-extension-output-and-isolates-asdf-diagnostics
  (with-test-directory (root)
    (let* ((cwd (merge-pathnames "project/" root))
           (global (merge-pathnames "global/" root))
           (output (make-string-output-stream))
           (manager
             (make-test-extension-manager
              cwd global output)))
      (write-text
       (merge-pathnames "output.lisp" global)
       (extension-source
        (format
         nil
         "(format t \"extension stdout visible~~%\")~%(signal 'asdf/plan:system-out-of-date :name \"cadr-cli\")~%(format *error-output* \"extension stderr visible~~%\")")))
      (let ((report
              (cadr-cli::reload-cli-extensions
               manager))
            (text
              (get-output-stream-string output)))
        (is (null (getf report :errors)))
        (is (search "extension stdout visible" text))
        (is (search "extension stderr visible" text))
        (is (not
             (search
              "system cadr-cli is out of date"
              text)))))))

(test inline-extension-output-uses-the-same-diagnostic-boundary
  (with-test-directory (root)
    (let* ((cwd (merge-pathnames "project/" root))
           (global (merge-pathnames "global/" root))
           (output (make-string-output-stream))
           (manager
             (make-test-extension-manager
              cwd global output nil nil
              (list
               (list
                :name "output-boundary"
                :factory
                (lambda (api)
                  (declare (ignore api))
                  (format t "inline stdout visible~%")
                  (signal
                   'asdf/plan:system-out-of-date
                   :name "cadr-cli")
                  (format *error-output*
                          "inline stderr visible~%")))))))
      (let ((report
              (cadr-cli::reload-cli-extensions manager))
            (text
              (get-output-stream-string output)))
        (is (null (getf report :errors)))
        (is (search "inline stdout visible" text))
        (is (search "inline stderr visible" text))
        (is (not
             (search
              "system cadr-cli is out of date"
              text)))))))

(test discovered-extension-source-registers-markdown-transformer
  (with-test-directory (root)
    (let* ((cwd
             (merge-pathnames "project/" root))
           (global
             (merge-pathnames "global/" root))
           (source
             (merge-pathnames
              "markdown.lisp" global))
           (manager
             (make-test-extension-manager
              cwd global
              (make-string-output-stream))))
      (write-text
       source
       (extension-source
        "(define-markdown-transformer (lambda (markdown context) (format nil \"~(~A~)|~A|~A\" (getf context :message-type) (getf context :available-width) markdown)))"))
      (let ((report
              (cadr-cli::reload-cli-extensions
               manager)))
        (is (null (getf report :errors)))
        (is
         (string=
          "assistant|78|hello"
          (cadr-agent::transform-extension-markdown
           (cadr-cli::cli-extension-manager-host
            manager)
           "hello"
           '(:message-type :assistant
             :streaming-p nil
             :available-width 78))))))))

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
        (is (= 2 (getf report :loaded)))
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

(test wave3-startup-resource-trust-and-user-bash-hooks-are-wired
  (with-test-directory (root)
    (let* ((cwd (merge-pathnames "project/" root))
           (global (merge-pathnames "global/" root))
           (extra-skills
             (merge-pathnames "extra-skills/" root))
           (output (make-string-output-stream)))
      (write-text
       (merge-pathnames "demo/SKILL.md" extra-skills)
       (format nil
               "---~%name: demo~%description: Demo~%---~%Body"))
      (write-text
       (merge-pathnames ".cadr/settings.json" cwd)
       "{}")
      (write-text
       (merge-pathnames "wave3.lisp" global)
       (extension-source
        (format
         nil
         "(define-event-hook :resources-discover :handler (lambda (event context) (declare (ignore event context)) (list :skill-paths (list ~S))))~%(define-event-hook :project-trust :handler (lambda (event context) (declare (ignore event context)) '(:trusted :yes :remember-p t)))~%(define-event-hook :user-bash :handler (lambda (event context) (declare (ignore event context)) '(:result (:output \"intercepted\" :exit-code 7))))"
         (namestring extra-skills))))
      (let* ((manager
               (make-test-extension-manager
                cwd global output))
             (report
               (cadr-cli::reload-cli-extensions
                manager))
             (host
               (cadr-cli::cli-extension-manager-host
                manager))
             (loader
               (cadr-cli::make-default-resource-loader
                :cwd cwd
                :agent-directory
                (merge-pathnames "agent/" root)
                :extension-host host))
             (snapshot
               (cadr-cli::reload-resources loader))
             (trust
               (cadr-cli::make-project-trust-store
                (merge-pathnames "trust.json" root))))
        (is (null (getf report :errors)))
        (is (equal
             '("demo")
             (mapcar
              #'cadr-agent::skill-name
              (cadr-cli::resource-snapshot-skills
               snapshot))))
        (is
         (cadr-cli::resolve-project-trusted
          trust cwd :extension-host host))
        (multiple-value-bind (decision found-p)
            (cadr-cli::project-trust-get trust cwd)
          (is (not (null found-p)))
          (is (not (null decision))))
        (multiple-value-bind (content details)
            (cadr-cli::execute-user-bash
             host cwd "exit 99")
          (is (= 7 (getf details :exit-code)))
          (is (search
               "intercepted"
               (result-text content))))))))

(test user-bash-dispatch-preserves-single-and-double-bang-semantics
  (let ((calls nil))
    (flet ((bash (command exclude-p)
             (push (list command exclude-p) calls)
             "done")
           (prompt (text)
             text))
      (multiple-value-bind (kind result)
          (cadr-cli::dispatch-user-input
           "! pwd" #'prompt :bash-function #'bash)
        (is (eq kind :bash))
        (is (string= "done" result)))
      (cadr-cli::dispatch-user-input
       "!! echo hidden" #'prompt
       :bash-function #'bash)
      (is (equal
           '(("echo hidden" t)
             ("pwd" nil))
           calls)))))

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

(test nonbaseline-install-command-stays-out-of-slash-surface
  (with-test-directory (root)
    (let ((manager
            (make-test-extension-manager
             (merge-pathnames "project/" root)
             (merge-pathnames "global/" root)
             (make-string-output-stream))))
      (is (null
           (cadr-cli::handle-extension-command
            "/install https://example.invalid/extension.git"
            manager))))))

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
               (format t "git wrapper stdout must stay hidden~%")
               (format *error-output*
                       "git wrapper stderr must stay hidden~%")
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
      (let ((text (get-output-stream-string output)))
        (is (search "Installed https://example.com/acme/demo.git"
                    text))
        (is (null (search "git wrapper stdout" text)))
        (is (null (search "git wrapper stderr" text))))
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
                "--verbose"
                "--reuseaddr"
                "--export-all"
                (format nil "--base-path=~A"
                        (namestring repositories))
                "--listen=127.0.0.1"
                (format nil "--port=~D" port)
               (namestring repositories))
               :output :stream
               :error-output :output))
             (let ((ready
                     (read-line
                      (uiop:process-info-output daemon)
                      nil nil)))
               (is (and ready
                        (search "Ready to rumble" ready))))
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
          (uiop:wait-process daemon)
          (ignore-errors
            (close (uiop:process-info-output daemon))))))))

(test goal12-extension-local-asdf-dependencies-are-explicit-repeatable-and-outside-the-main-closure
  (with-test-directory (temporary)
    (let* ((extension-directory
             (merge-pathnames "with-deps/" temporary))
           (system-name
             (format nil "goal12-duration-~36R" (random most-positive-fixnum)))
           (helper-system-name
             (format nil "goal12-duration-helper-~36R"
                     (random most-positive-fixnum)))
           (package-name (string-upcase system-name))
           (helper-package-name (string-upcase helper-system-name))
           (output (make-string-output-stream)))
      (ensure-directories-exist
       (merge-pathnames "anchor" extension-directory))
      (write-text
       (merge-pathnames "extension-dependencies.sexp" extension-directory)
       (format nil "(:systems (~S))~%" system-name))
      (write-text
       (merge-pathnames (format nil "~A.asd" system-name) extension-directory)
       (format nil
               "(asdf:defsystem ~S :depends-on (~S) :serial t :components ((:file \"duration\")))~%"
               system-name helper-system-name))
      (write-text
       (merge-pathnames
        (format nil "~A.asd" helper-system-name)
        extension-directory)
       (format nil
               "(asdf:defsystem ~S :serial t :components ((:file \"duration-helper\")))~%"
               helper-system-name))
      (write-text
       (merge-pathnames "duration-helper.lisp" extension-directory)
       (format nil
               "(defpackage ~S (:use :cl) (:export #:seconds-to-ms))~%(in-package ~S)~%(defun seconds-to-ms (value) (* 1000 value))~%"
               helper-package-name helper-package-name))
      (write-text
       (merge-pathnames "duration.lisp" extension-directory)
       (format nil
               "(defpackage ~S (:use :cl) (:export #:parse-ms))~%(in-package ~S)~%(defun parse-ms (value) (~A:seconds-to-ms (parse-integer value)))~%"
               package-name package-name helper-package-name))
      (write-text
       (merge-pathnames "extension.lisp" extension-directory)
       (format nil
               "(define-tool \"parse_duration\" :description \"parse\" :parameters (cadr-ai::json-object \"type\" \"object\" \"properties\" (cadr-ai::json-object \"duration\" (cadr-ai::json-object \"type\" \"string\")) \"required\" (vector \"duration\") \"additionalProperties\" nil) :handler (lambda (id args context) (declare (ignore id context)) (values (format nil \"~~D\" (~A:parse-ms (gethash \"duration\" args))) nil)))~%"
               package-name))
      (let* ((manager
               (make-test-extension-manager
                temporary (merge-pathnames "global/" temporary)
                output (list extension-directory)))
             (first (cadr-cli::reload-cli-extensions manager))
             (second (cadr-cli::reload-cli-extensions manager)))
        (is (null (getf first :errors)))
        (is (null (getf second :errors)))
        (is (= 2 (getf first :active)))
        (is (= 2 (getf second :active)))
        (is (asdf:find-system system-name nil))
        (is (asdf:find-system helper-system-name nil))
        (is (not (member system-name
                         (asdf:system-depends-on
                          (asdf:find-system "cadr-cli"))
                         :test #'string-equal)))
        (is (not (member helper-system-name
                         (asdf:system-depends-on
                          (asdf:find-system "cadr-cli"))
                         :test #'string-equal)))
        (is (string= "" (get-output-stream-string output)))))))

(test goal12-extension-local-dependency-errors-name-the-system-and-extension-path
  (with-test-directory (temporary)
    (let* ((extension-directory
             (merge-pathnames "broken-deps/" temporary))
           (output (make-string-output-stream)))
      (ensure-directories-exist
       (merge-pathnames "anchor" extension-directory))
      (write-text
       (merge-pathnames "extension-dependencies.sexp" extension-directory)
       "(:systems (\"missing-goal12-system\"))\n")
      (write-text
       (merge-pathnames "extension.lisp" extension-directory)
       "(define-command \"never\" :handler (lambda (arguments context) (declare (ignore arguments context))))\n")
      (let* ((manager
               (make-test-extension-manager
                temporary (merge-pathnames "global/" temporary)
                output (list extension-directory)))
             (report (cadr-cli::reload-cli-extensions manager))
             (message (first (getf report :errors))))
        (is (= 1 (length (getf report :errors))))
        (is (search "missing-goal12-system" message))
        (is (search "broken-deps" message))))))
