(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

;;; pi@4a080252f extensions/index.ts and resource-loader.test.ts.
;;; Built-ins are hidden builtin:<name> resources. llama.cpp stays.
;;; codemode, tool-search, and mcp are left out when another
;;; extension already registered the same tool, command, or flag.

(defun builtin-extension-paths (manager)
  (mapcar
   #'cadr-agent::extension-bundle-path
   (cadr-agent::extension-snapshot-bundles
    (cadr-agent::extension-host-current-snapshot
     (cadr-cli::cli-extension-manager-host manager)))))

(defun builtin-extension-tool (manager name)
  (find name
        (cadr-agent::extension-snapshot-tools
         (cadr-agent::extension-host-current-snapshot
          (cadr-cli::cli-extension-manager-host manager)))
        :key #'cadr-agent::extension-tool-definition-name
        :test #'string=))

(defun builtin-extension-command (manager name)
  (find name
        (cadr-agent::extension-snapshot-commands
         (cadr-agent::extension-host-current-snapshot
          (cadr-cli::cli-extension-manager-host manager)))
        :key #'cadr-agent::extension-command-definition-name
        :test #'string=))

(defun builtin-startup-messages (manager)
  (mapcar
   (lambda (issue) (getf issue :message))
   (cadr-cli::cli-extension-manager-startup-issues manager)))

(defparameter *builtin-tool-parameters*
  "(cadr-ai::json-object \"type\" \"object\" \"properties\" (cadr-ai::json-object) \"additionalProperties\" nil)")

(test builtin-extensions-load-hidden-in-upstream-order
  (with-test-directory (root)
    (let* ((manager
             (cadr-cli::make-cli-extension-manager
              :cwd root
              :global-directory (merge-pathnames "global/" root)
              :output (make-string-output-stream)))
           (report (cadr-cli::reload-cli-extensions manager))
           (bundles
             (cadr-agent::extension-snapshot-bundles
              (cadr-agent::extension-host-current-snapshot
               (cadr-cli::cli-extension-manager-host manager)))))
      (is (null (getf report :errors)))
      (is (equal
           '("builtin:llama.cpp" "builtin:codemode"
             "builtin:tool-search" "builtin:mcp")
           (mapcar #'cadr-agent::extension-bundle-path bundles)))
      (is (every #'cadr-agent::extension-bundle-hidden-p bundles))
      (is (null
           (cadr-agent::extension-bundle-replaceable-p
            (first bundles))))
      (is (every #'cadr-agent::extension-bundle-replaceable-p
                 (rest bundles))))))

(test builtin-global-exclude-skips-mcp-and-keeps-llama
  (with-test-directory (root)
    (let ((manager
            (cadr-cli::make-cli-extension-manager
             :cwd root
             :global-directory (merge-pathnames "global/" root)
             :global-extension-entries '("-builtin:mcp")
             :output (make-string-output-stream))))
      (cadr-cli::reload-cli-extensions manager)
      (is (equal
           '("builtin:llama.cpp" "builtin:codemode"
             "builtin:tool-search")
           (builtin-extension-paths manager)))
      (is (null (builtin-extension-command manager "mcp"))))))

(test builtin-project-override-waits-until-trust
  (with-test-directory (root)
    (let ((manager
            (cadr-cli::make-cli-extension-manager
             :cwd root
             :global-directory (merge-pathnames "global/" root)
             :defer-builtin-extensions-p t
             :project-trusted-p nil
             :global-extension-entries '("-builtin:mcp")
             :project-extension-entries
             '("+builtin:mcp" "-builtin:llama.cpp")
             :extension-factories
             (list (lambda (api) (declare (ignore api))))
             :output (make-string-output-stream))))
      (cadr-cli::reload-cli-extensions manager)
      (is (equal '("<inline:1>") (builtin-extension-paths manager)))
      (setf (cadr-cli::cli-extension-manager-defer-builtin-extensions-p
             manager)
            nil
            (cadr-cli::cli-extension-manager-project-trusted-p
             manager)
            t)
      (cadr-cli::reload-cli-extensions manager)
      (is (equal
           '("builtin:codemode" "builtin:tool-search"
             "builtin:mcp" "<inline:1>")
           (builtin-extension-paths manager))))))

(test builtin-no-extensions-loads-only-named-builtins
  (with-test-directory (root)
    (let* ((manager
             (cadr-cli::make-cli-extension-manager
              :cwd root
              :global-directory (merge-pathnames "global/" root)
              :no-discovery-p t
              :explicit-paths '("builtin:mcp" "builtin:missing")
              :output (make-string-output-stream)))
           (report (cadr-cli::reload-cli-extensions manager)))
      (is (equal '("builtin:mcp") (builtin-extension-paths manager)))
      (is (equal
           '("Unknown built-in extension: builtin:missing")
           (getf report :errors))))))

(test builtin-settings-file-path-still-loads
  (with-test-directory (root)
    (let* ((file (merge-pathnames "from-settings.lisp" root))
           (manager
             (cadr-cli::make-cli-extension-manager
              :cwd root
              :global-directory (merge-pathnames "global/" root)
              :global-extension-entries
              (list (namestring file) "-builtin:codemode"
                    "-builtin:tool-search" "-builtin:mcp")
              :output (make-string-output-stream))))
      (write-text
       file
       "(define-command \"from-settings\" :description \"settings file\" :handler (lambda (arguments context) (declare (ignore arguments context))))")
      (cadr-cli::reload-cli-extensions manager)
      (is (equal
           (list (namestring (truename file)) "builtin:llama.cpp")
           (builtin-extension-paths manager))))))

(test builtin-command-collision-omits-mcp-with-cadr-warning
  (with-test-directory (root)
    (let* ((file (merge-pathnames "other-mcp.lisp" root))
           (output (make-string-output-stream))
           (manager
             (cadr-cli::make-cli-extension-manager
              :cwd root
              :global-directory (merge-pathnames "global/" root)
              :explicit-paths (list (namestring file))
              :output output)))
      (write-text
       file
       "(define-command \"mcp\" :description \"third party mcp\" :handler (lambda (arguments context) (declare (ignore arguments context))))")
      (cadr-cli::reload-cli-extensions manager)
      (let ((winner (namestring (truename file))))
        (is (equal
             (list winner "builtin:llama.cpp" "builtin:codemode"
                   "builtin:tool-search")
             (builtin-extension-paths manager)))
        (is (string=
             "third party mcp"
             (cadr-agent::extension-command-definition-description
              (builtin-extension-command manager "mcp"))))
        (is (member
             (format nil
                     "Extension ~A registers command `/mcp`, so built-in extension `mcp` was not loaded. To use `mcp`, run `cadr config` and make sure it is enabled under Built-in extensions, then disable or remove the existing extension. We recommend only having one or the other loaded at a time."
                     winner)
             (builtin-startup-messages manager)
             :test #'string=))))))

(test replaceable-inline-sharing-a-command-is-omitted-quietly
  (with-test-directory (root)
    (let* ((file (merge-pathnames "owner.lisp" root))
           (manager
             (cadr-cli::make-cli-extension-manager
              :cwd root
              :global-directory (merge-pathnames "global/" root)
              :explicit-paths (list (namestring file))
              :global-extension-entries
              '("-builtin:codemode" "-builtin:tool-search")
              :extension-factories
              (list
               (list :name "mcp"
                     :replaceable-p t
                     :factory
                     (lambda (api)
                       (declare (ignore api))
                       (cadr-agent:define-command
                           "mcp"
                         :description "inline mcp"
                         :handler
                         (lambda (arguments context)
                           (declare (ignore arguments context)))))))
              :output (make-string-output-stream))))
      (write-text
       file
       "(define-command \"mcp\" :description \"file mcp\" :handler (lambda (arguments context) (declare (ignore arguments context))))")
      (cadr-cli::reload-cli-extensions manager)
      (is (equal
           (list (namestring (truename file)) "builtin:llama.cpp")
           (builtin-extension-paths manager)))
      (is (null
           (find-if
            (lambda (message)
              (search "<inline:mcp>" message))
            (builtin-startup-messages manager)))))))

(test two-replaceable-mcp-extensions-both-stay
  (with-test-directory (root)
    (let ((manager
            (cadr-cli::make-cli-extension-manager
             :cwd root
             :global-directory (merge-pathnames "global/" root)
             :global-extension-entries
             '("-builtin:llama.cpp" "-builtin:codemode"
               "-builtin:tool-search")
             :extension-factories
             (list
              (list :name "also"
                    :replaceable-p t
                    :factory
                    (lambda (api)
                      (declare (ignore api))
                      (cadr-agent:define-command
                          "mcp"
                        :description "also mcp"
                        :handler
                        (lambda (arguments context)
                          (declare (ignore arguments context)))))))
             :output (make-string-output-stream))))
      (cadr-cli::reload-cli-extensions manager)
      (is (equal
           '("builtin:mcp" "<inline:also>")
           (builtin-extension-paths manager))))))

(test third-party-tool-omits-tool-search-and-codemode
  (with-test-directory (root)
    (let* ((file (merge-pathnames "tools.lisp" root))
           (manager
             (cadr-cli::make-cli-extension-manager
              :cwd root
              :global-directory (merge-pathnames "global/" root)
              :explicit-paths (list (namestring file))
              :output (make-string-output-stream))))
      (write-text
       file
       (format nil
               "(define-tool \"tool_search\" :description \"other search\" :parameters ~A :handler (lambda (id arguments context) (declare (ignore id arguments context)) nil))~%(define-tool \"codemode\" :description \"other code\" :parameters ~A :handler (lambda (id arguments context) (declare (ignore id arguments context)) nil))~%"
               *builtin-tool-parameters*
               *builtin-tool-parameters*))
      (let ((report (cadr-cli::reload-cli-extensions manager)))
        (is (null (getf report :errors)))
        (is (equal
             (list (namestring (truename file))
                   "builtin:llama.cpp" "builtin:mcp")
             (builtin-extension-paths manager)))
        (is (string=
             "other search"
             (cadr-agent::extension-tool-definition-description
              (builtin-extension-tool manager "tool_search"))))
        (is (null
             (find-if
              (lambda (message)
                (search "conflicts" message))
              (builtin-startup-messages manager))))))))

(test tool-search-extension-is-inactive-and-not-a-base-tool
  (with-test-directory (root)
    (let ((manager
            (cadr-cli::make-cli-extension-manager
             :cwd root
             :global-directory (merge-pathnames "global/" root)
             :output (make-string-output-stream)))
          (base (cadr-cli::make-all-coding-tools root)))
      (cadr-cli::reload-cli-extensions manager)
      (is (null
           (find "tool_search" base
                 :key #'cadr-ai:tool-name :test #'string=)))
      (let ((tool (builtin-extension-tool manager "tool_search")))
        (is (string=
             (cadr-ai:tool-description
              (cadr-agent:make-tool-search-tool))
             (cadr-agent::extension-tool-definition-description tool)))
        (is (null
             (cadr-agent::extension-tool-definition-default-active
              tool)))
        (is (eq :direct
                (cadr-agent::extension-tool-definition-exposure
                 tool)))))))

(test codemode-extension-registers-the-inactive-model-only-tool
  (with-test-directory (root)
    (let ((manager
            (cadr-cli::make-cli-extension-manager
             :cwd root
             :global-directory (merge-pathnames "global/" root)
             :output (make-string-output-stream))))
      (cadr-cli::reload-cli-extensions manager)
      (let* ((tool (builtin-extension-tool manager "codemode"))
             (parameters
               (cadr-agent::extension-tool-definition-parameters tool))
             (code
               (cadr-ai::json-get
                (cadr-ai::json-get parameters "properties")
                "code")))
        (is (eq :model-only
                (cadr-agent::extension-tool-definition-exposure tool)))
        (is (null
             (cadr-agent::extension-tool-definition-default-active
              tool)))
        (is (string=
             "Run JavaScript that calls other tools"
             (cadr-agent::extension-tool-definition-prompt-snippet
              tool)))
        (is (equal
             '("Use codemode to batch independent tool calls (Promise.allSettled), chain them, or filter large output, instead of many separate calls.")
             (cadr-agent::extension-tool-definition-prompt-guidelines
              tool)))
        (is (search
             "Run JavaScript that calls other tools. The input is raw JavaScript"
             (cadr-agent::extension-tool-definition-description tool)))
        (is (search
             (cadr-agent::mcp-join
              (cadr-ai::cadr-docs-directory) "codemode.md")
             (cadr-agent::extension-tool-definition-description tool)))
        (is (search
             "`models`: classifiers and image generation."
             (cadr-agent::extension-tool-definition-description tool)))
        (is (string= "Raw JavaScript source."
                     (cadr-ai::json-get code "description")))
        (is (equalp #("code")
                    (cadr-ai::json-get parameters "required")))))))

(test mcp-command-status-and-usage-match-upstream
  (with-test-directory (root)
    (let* ((agent (merge-pathnames "agent/" root))
           (previous (uiop:getenv "CADR_CODING_AGENT_DIR"))
           (output (make-string-output-stream))
           (manager
             (cadr-cli::make-cli-extension-manager
              :cwd root
              :global-directory (merge-pathnames "global/" root)
              :output output)))
      (ensure-directories-exist agent)
      (unwind-protect
           (progn
             (sb-posix:setenv "CADR_CODING_AGENT_DIR"
                              (namestring agent) 1)
             (cadr-cli::reload-cli-extensions manager)
             (cadr-agent::invoke-extension-command
              (cadr-cli::cli-extension-manager-host manager)
              "mcp" "")
             (is (search
                  (format nil
                          "No MCP servers configured. Add them to ~A or .pi/mcp.json."
                          (cadr-agent::mcp-join agent "mcp.json"))
                  (get-output-stream-string output)))
             (cadr-agent::invoke-extension-command
              (cadr-cli::cli-extension-manager-host manager)
              "mcp" "login one extra")
             (is (search
                  "Usage: /mcp, /mcp login [server], /mcp logout [server], /mcp reconnect [server]"
                  (get-output-stream-string output))))
        (if previous
            (sb-posix:setenv "CADR_CODING_AGENT_DIR" previous 1)
            (sb-posix:unsetenv "CADR_CODING_AGENT_DIR"))))))
