(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(declaim (notinline goal13-crash-origin))

(defun goal13-crash-origin (system-prompt session-content secret)
  (error "~A ~A ~A"
         system-prompt session-content secret))

(test native-image-options-omit-unsupported-compression-keyword
  (let ((without
          (cadr-cli::native-image-save-arguments
           '(:sbcl :linux)))
        (with
          (cadr-cli::native-image-save-arguments
           '(:sbcl :linux :sb-core-compression))))
    (is (eq #'cadr-cli:executable-main
            (getf without :toplevel)))
    (is (eq t (getf without :executable)))
    (is (eq t (getf without :save-runtime-options)))
    (is (not (member :compression without)))
    (is (eq t (getf with :compression)))))

(test goal13-fatal-condition-boundary-redacts-user-output-and-crash-log
  (with-test-directory (directory)
    (let* ((visible (make-string-output-stream))
             (secret "oauth-secret-must-not-leak")
             (system-prompt "SYSTEM-PROMPT-MUST-NOT-REACH-TERMINAL")
             (session-content "SESSION-CONTENT-MUST-NOT-REACH-TERMINAL")
             (status
               (let ((*error-output* visible))
                 (cadr-cli::call-with-fatal-condition-boundary
                  (lambda ()
                    (goal13-crash-origin
                     system-prompt session-content secret))
                  :crash-directory directory
                  :secrets (list secret)
                  :exit-function #'identity)))
             (output (get-output-stream-string visible))
             (logs
               (directory
                (merge-pathnames "cadr-crash-*.log" directory))))
        (is (= 1 status))
        (is (search "SIMPLE-ERROR" output))
        (is (search "Crash log:" output))
        (is (null (search system-prompt output)))
        (is (null (search session-content output)))
        (is (null (search secret output)))
        (is (= 1 (length logs)))
        (when logs
          (is (= #o600
                 (logand #o777
                         (sb-posix:stat-mode
                          (sb-posix:stat (first logs))))))
          (let ((diagnostic (read-text (first logs))))
            (is (search "CRASH-ORIGIN" diagnostic))
            (is (search system-prompt diagnostic))
            (is (search session-content diagnostic))
            (is (null (search secret diagnostic)))
            (is (search "[REDACTED]" diagnostic)))))))

(test goal13-cli-configuration-objects-never-print-secret-material
  (with-test-directory (directory)
    (let* ((secret "cli-secret-must-never-print")
           (storage
             (cadr-cli:make-file-auth-storage
              (merge-pathnames "auth.json" directory)))
           (objects
             (list
              (cadr-cli::make-cli-arguments :api-key secret)
              (cadr-cli::make-provider-config
               :name "faux"
               :provider
               (cadr-ai:make-openai-provider
                :api-key secret))
              (cadr-cli::make-runtime-credentials storage)
              (cadr-cli::make-runtime-auth-input-state
               (list :type :secret :message "API key"))
              (cadr-cli::make-api-key-input-state
               (cadr-cli::make-oauth-selector-option
                :id :faux :name "Faux" :auth-type :api-key))
              (cadr-cli:make-model-registry
               :path (merge-pathnames "models.json" directory)
               :credentials storage)
              (cadr-cli::%make-hugging-face-client
               :token secret)
              (cadr-cli::%make-llama-client
               :api-key secret))))
      (dolist (object objects)
        (let ((printed
                (write-to-string object :readably nil)))
          (is (null (search secret printed)))
          (is (search "REDACTED" printed)))))))

(test goal13-interactive-interrupt-uses-the-sanitized-fatal-path
  (with-test-directory (directory)
    (let* ((visible (make-string-output-stream))
           (status
             (let ((*error-output* visible))
               (cadr-cli::call-with-fatal-condition-boundary
                (lambda ()
                  (signal 'sb-sys:interactive-interrupt))
                :crash-directory directory
                :exit-function #'identity)))
           (output (get-output-stream-string visible)))
      (is (= 1 status))
      (is (search "INTERACTIVE-INTERRUPT" output))
      (is (search "Interactive interrupt" output))
      (is (null (search "Backtrace for:" output)))
      (is (= 1
             (length
              (directory
               (merge-pathnames
                "cadr-crash-*.log" directory))))))))

(test goal13-cleanup-never-blocks-on-an-unresponsive-thread
  (let* ((started (sb-thread:make-semaphore :count 0))
         (thread
           (sb-thread:make-thread
            (lambda ()
              (sb-thread:signal-semaphore started)
              (loop (sleep 60)))
            :name "cadr-test-unresponsive-cleanup")))
    (sb-thread:wait-on-semaphore started)
    (is (eq :terminated
            (cadr-cli::stop-thread-for-cleanup
             thread :timeout 0.01d0)))
    (is (not (sb-thread:thread-alive-p thread)))))

(test goal10-part-e-release-identity-has-one-version-source
  (let* ((root (asdf:system-source-directory "cadr-cli"))
         (version-path (merge-pathnames "version.sexp" root))
         (version
           (and
            (probe-file version-path)
            (with-open-file (stream version-path :direction :input)
              (read stream nil nil))))
         (identity
           (and version
                (format
                 nil
                 "cadr ~A · aligned with pi v0.84.3 (+0, 4e58f324f)"
                 version))))
    (dolist (asd
              '("cadr-core.asd" "cadr-ai.asd" "cadr-agent.asd"
                "cadr-tui.asd" "cadr-cli.asd" "cadr-storage.asd"
                "cadr-server.asd" "cadr-evals.asd" "cadr-protocol.asd"))
      (asdf:load-asd (merge-pathnames asd root)))
    (is (stringp version))
    (when (stringp version)
      (dolist (system
                '("cadr-ai" "cadr-agent" "cadr-tui" "cadr-cli"
                  "cadr-storage" "cadr-server" "cadr-evals"
                  "cadr-protocol"))
        (is (string=
             version
             (asdf:component-version
              (asdf:find-system system)))))
      (is (string= version (cadr-ai::cadr-version)))
      (is (string=
           identity
           (cadr-ai::cadr-release-identity)))
      (multiple-value-bind (compact expanded)
          (cadr-cli::make-tui-startup-lines
           (cadr-cli::make-resource-snapshot))
        (declare (ignore expanded))
        (is (string=
             (format nil "cadr v~A" version)
             (first compact))))
      (with-test-directory (directory)
        (let ((old-home (uiop:getenv "HOME"))
              (output (make-string-output-stream))
              (errors (make-string-output-stream))
              (status nil))
          (unwind-protect
               (progn
                 (setf (uiop:getenv "HOME")
                       (namestring directory))
                 (let ((*standard-output* output)
                       (*error-output* errors))
                   (setf status
                         (cadr-cli:main '("--version")))))
            (setf (uiop:getenv "HOME") old-home))
          (is (= 0 status))
          (is (string=
               (format nil "~A~%" identity)
               (get-output-stream-string output)))
          (is (string= ""
                       (get-output-stream-string errors)))))
      (dolist (relative
                '("README.md" "CHANGELOG.md"
                  "docs/acceptance/goal-v10-part-e.md"))
        (is (search
             identity
             (uiop:read-file-string
              (merge-pathnames relative root)))))
      (dolist (relative
                '("cadr-core.asd" "cadr-ai.asd" "cadr-agent.asd" "cadr-tui.asd"
                  "cadr-cli.asd" "cadr-storage.asd" "cadr-server.asd"
                  "cadr-evals.asd" "cadr-protocol.asd"
                  "src/cadr-ai/transport/http.lisp"
                  "src/cadr-ai/support/release.lisp"
                  "src/cadr-cli/bootstrap/tools.lisp"
                  "src/cadr-cli/bootstrap/sessions.lisp"
                  "src/cadr-cli/bootstrap/settings.lisp"
                  "src/cadr-cli/bootstrap/auth.lisp"
                  "src/cadr-cli/bootstrap/commands.lisp"
                  "src/cadr-cli/bootstrap/main.lisp"
                  "src/cadr-cli/interactive/controller.lisp"
                  "src/cadr-server/main.lisp"
                  "src/cadr-server/radius.lisp"))
        (is (not
             (search
              version
              (uiop:read-file-string
               (merge-pathnames relative root)))))))))

(test goal9-part-e-repository-hygiene-and-navigation-contract
  (let* ((root (asdf:system-source-directory "cadr-cli"))
         (changelog-path (merge-pathnames "CHANGELOG.md" root))
         (index-path (merge-pathnames "docs/README.md" root))
         (ignore-path (merge-pathnames ".gitignore" root))
         (changelog
           (and (probe-file changelog-path)
                (uiop:read-file-string changelog-path)))
         (index
           (and (probe-file index-path)
                (uiop:read-file-string index-path)))
         (ignore (uiop:read-file-string ignore-path)))
    (is-true changelog)
    (is-true index)
    (when changelog
      (is (search "## [Unreleased]" changelog))
      (loop for goal from 1 to 9
            do (is (search
                    (format nil "Goal ~D" goal)
                    changelog))))
    (when index
      (dolist (entry
                '("architecture.md" "parity-map.md" "visual-parity.md"
                  "test-matrix.md" "dependency-audit.md"
                  "open-questions.md" "progress/" "proposals/"
                  "acceptance/" "../README.md" "../CHANGELOG.md"))
        (is (search entry index))))
    (dolist (pattern
              '("/.codex" "/.tmp-home/" "/.obsidian/"
                "/docs/.obsidian/" "/goal*.md" "__pycache__/"
                "*.py[cod]" "cadr-*.html" "out.html"))
      (is (search pattern ignore)))
    (is (not (probe-file (merge-pathnames "packages/" root))))
    (is (not (probe-file (merge-pathnames "goal9.md" root))))
    (is (not (probe-file (merge-pathnames "goal10.md" root))))
    (is (probe-file
         (merge-pathnames "docs/progress/goal-v9.md" root)))
    (is (probe-file
         (merge-pathnames "docs/progress/goal-v10.md" root)))))
