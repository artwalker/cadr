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
               (let ((*error-output* visible)
                     (cadr-ai::*fatal-session-file* nil))
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
        (is (search "cadr exiting due to uncaughtException:" output))
        (is (search (format nil "Error: ~A ~A [REDACTED]"
                            system-prompt session-content)
                    output))
        (is (null (search "Crash log:" output)))
        (is (null (search "SIMPLE-ERROR" output)))
        (is (search "    at GOAL13-CRASH-ORIGIN" output))
        (dolist (line (uiop:split-string output :separator '(#\Newline)))
          (when (uiop:string-prefix-p "    at " line)
            (is (null (search secret line)))
            (is (null (search system-prompt line)))
            (is (null (search session-content line)))))
        (is (null (search secret output)))
        (is (search
             "To report this crash: start cadr and run /bug. The crash details are attached automatically."
             output))
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

(declaim (notinline gap72-parameter-leak))

(defun gap72-parameter-leak (secret)
  (if (stringp secret)
      (error "gap72 parameter boom")
      (error "gap72 parameter boom")))

(defun gap72-terminal-frame-p (line)
  (and (uiop:string-prefix-p "    at " line)
       (multiple-value-bind (start end)
           (cl-ppcre:scan " \\([^()[:space:]]+:[0-9]+\\)$" line)
         (declare (ignore end))
         (or (null start)
             (not (search " (" (subseq line 0 start)))))))

(test gap72-terminal-frames-omit-parameter-values
  ;; v1.4.0 interactive-mode.ts uncaughtCrash prints Error: message and
  ;; stack frames. Argument values stay in the mode-0600 log.
  (with-test-directory (directory)
    (let* ((visible (make-string-output-stream))
           (secret "sk-test-SECRET")
           (record-path (merge-pathnames "crashes.json" directory))
           (status
             (let ((*error-output* visible)
                   (cadr-cli::*fatal-crash-record-path* record-path)
                   (cadr-ai::*fatal-session-file* nil))
               (cadr-cli::call-with-fatal-condition-boundary
                (lambda () (gap72-parameter-leak secret))
                :crash-directory directory
                :exit-function #'identity)))
           (output (get-output-stream-string visible))
           (lines (uiop:split-string output :separator '(#\Newline)))
           (frames
             (remove-if-not
              (lambda (line) (uiop:string-prefix-p "    at " line))
              lines))
           (logs
             (directory
              (merge-pathnames "cadr-crash-*.log" directory))))
      (is (= 1 status))
      (is (string= "cadr exiting due to uncaughtException:" (first lines)))
      (is (string= "Error: gap72 parameter boom" (second lines)))
      (is (find-if
           (lambda (line)
             (or (string= line "    at GAP72-PARAMETER-LEAK")
                 (cl-ppcre:scan
                  "^    at GAP72-PARAMETER-LEAK \\([^()]+\\:[0-9]+\\)$"
                  line)))
           frames))
      (is (every #'gap72-terminal-frame-p frames))
      (is (null (search secret output)))
      (is (search
           "To report this crash: start cadr and run /bug. The crash details are attached automatically."
           output))
      (is (= 1 (length logs)))
      (when logs
        (is (= #o600
               (logand #o777
                       (sb-posix:stat-mode
                        (sb-posix:stat (first logs))))))
        (is (search secret (read-text (first logs)))))
      (let* ((diag (cadr-cli::crash-log-for-diagnostics record-path))
             (bundle
               (cadr-cli::collect-bug-report-diagnostics nil diag)))
        (is (= 1 (length diag)))
        (when diag
          (is (string= "uncaught_exception" (getf (first diag) :kind)))
          (is (string= "gap72 parameter boom" (getf (first diag) :message)))
          (is (search "    at GAP72-PARAMETER-LEAK"
                      (getf (first diag) :stack)))
          (is (null (search secret (getf (first diag) :stack)))))
        (is (search "gap72 parameter boom"
                    (princ-to-string (getf bundle :crashes))))
        (is (null (search secret (princ-to-string bundle))))))))

(defun gap72-fatal-page (directory)
  (let* ((visible (make-string-output-stream))
         (status
           (let ((*error-output* visible))
             (cadr-cli::call-with-fatal-condition-boundary
              (lambda () (error "gap72 session boom"))
              :crash-directory directory
              :exit-function #'identity)))
         (output (get-output-stream-string visible)))
    (values status output)))

(test gap72-session-file-uses-the-resume-bug-hint
  ;; v1.4.0 newSession sets sessionFile when persist is true, before
  ;; the file exists. crashReportInstructions then uses the resume sentence.
  (with-test-directory (directory)
    (let* ((session
             (cadr-agent:create-session
              :directory directory
              :cwd directory))
           (path (cadr-agent:session-path session)))
      (is (pathnamep path))
      (is (null (probe-file path)))
      (is (not (cadr-agent:session-persisted-p session)))
      (let ((cadr-ai::*fatal-session-file* nil))
        (is (string= (namestring path)
                     (cadr-cli::note-fatal-session-file session)))
        (multiple-value-bind (status output)
            (gap72-fatal-page directory)
          (is (= 1 status))
          (is (search
               "To report this crash: run `cadr -r` to resume the session, then run /bug. The crash details are attached automatically."
               output))
          (is (null (search "start cadr and" output)))
          (is (null (search "Crash log:" output)))))
      (let ((memory
              (cadr-agent:create-session
               :directory directory
               :cwd directory
               :persist-p nil)))
        (is (null (cadr-agent:session-path memory)))
        (let ((cadr-ai::*fatal-session-file* "stale-session.jsonl"))
          (is (null (cadr-cli::note-fatal-session-file memory)))
          (multiple-value-bind (status output)
              (gap72-fatal-page directory)
            (is (= 1 status))
            (is (search
                 "To report this crash: start cadr and run /bug. The crash details are attached automatically."
                 output))
            (is (null (search "run `cadr -r`" output)))))))))

(defun gap72-run-print-startup (directory arguments)
  (let ((home (merge-pathnames "home/" directory))
        (workspace (merge-pathnames "workspace/" directory))
        (original-home (uiop:getenv "HOME")))
    (ensure-directories-exist (merge-pathnames "anchor" home))
    (ensure-directories-exist (merge-pathnames "anchor" workspace))
    (unwind-protect
         (progn
           (setf (uiop:getenv "HOME") (namestring home))
           (uiop:with-current-directory (workspace)
             (let ((*standard-input* (make-string-input-stream ""))
                   (*standard-output* (make-string-output-stream))
                   (*error-output* (make-string-output-stream)))
               (cadr-cli::cli-handler
                (cadr-cli::parse-cli-arguments arguments)))))
      (setf (uiop:getenv "HOME") original-home))))

(test gap72-startup-session-path-uses-the-resume-bug-hint
  ;; v1.4.0 interactive startup keeps sessionFile on the session that
  ;; newSession just created. The crash page reads that string.
  (with-test-directory (directory)
    (let ((sessions (merge-pathnames "sessions/" directory)))
      (ensure-directories-exist (merge-pathnames "anchor" sessions))
      (let ((cadr-ai::*fatal-session-file* nil))
        (is (member
             (gap72-run-print-startup
              directory
              (list "--print" "--no-extensions" "--no-skills"
                    "--no-prompt-templates" "--no-context-files"
                    "--no-tools"
                    "--session-dir" (namestring sessions)))
             '(0 1)))
        (is (stringp cadr-ai::*fatal-session-file*))
        (is (null (probe-file cadr-ai::*fatal-session-file*)))
        (multiple-value-bind (status output)
            (gap72-fatal-page directory)
          (is (= 1 status))
          (is (search
               "To report this crash: run `cadr -r` to resume the session, then run /bug. The crash details are attached automatically."
               output))
          (is (null (search "start cadr and" output)))))
      (let ((cadr-ai::*fatal-session-file* "stale-session.jsonl"))
        (is (member
             (gap72-run-print-startup
              directory
              (list "--print" "--no-session" "--no-extensions"
                    "--no-skills" "--no-prompt-templates"
                    "--no-context-files" "--no-tools"))
             '(0 1)))
        (is (null cadr-ai::*fatal-session-file*))
        (multiple-value-bind (status output)
            (gap72-fatal-page directory)
          (is (= 1 status))
          (is (search
               "To report this crash: start cadr and run /bug. The crash details are attached automatically."
               output))
          (is (null (search "run `cadr -r`" output))))))))

(test gap72-terminal-error-name-maps-node-subclasses
  (is (string= "Error"
               (cadr-ai::fatal-terminal-error-name
                (make-condition 'simple-error :format-control "x"))))
  (is (string= "TypeError"
               (cadr-ai::fatal-terminal-error-name
                (make-condition 'simple-type-error
                                :format-control "x"
                                :datum 1
                                :expected-type 'string))))
  (is (string= "SyntaxError"
               (cadr-ai::fatal-terminal-error-name
                (make-condition 'parse-error))))
  (handler-case (eval 'gap72-no-such-variable)
    (unbound-variable (condition)
      (is (string= "ReferenceError"
                   (cadr-ai::fatal-terminal-error-name condition)))))
  (handler-case (/ 1 0)
    (division-by-zero (condition)
      (is (string= "RangeError"
                   (cadr-ai::fatal-terminal-error-name condition))))))

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

(test dead-terminal-errors-exit-without-a-crash-report
  (dolist (errno '(5 25 32 107))
    (with-test-directory (directory)
      (let* ((visible (make-string-output-stream))
             (status
               (let ((*error-output* visible))
                 (cadr-cli::call-with-fatal-condition-boundary
                  (lambda ()
                    (sb-impl::simple-stream-perror
                     "read" *standard-input* errno))
                  :crash-directory directory
                  :exit-function #'identity)))
             (output (get-output-stream-string visible)))
        (is (= 129 status))
        (is (string= "" output))
        (is (null
             (directory
              (merge-pathnames
               "cadr-crash-*.log" directory))))))))

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
      (is (search "cadr exiting due to uncaughtException:" output))
      (is (search "Error: Interactive interrupt" output))
      (is (null (search "uncaught INTERACTIVE-INTERRUPT" output)))
      (is (null (search "Crash log:" output)))
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
                 "cadr ~A · aligned with pi v1.4.0 (+0, 4a080252f)"
                 version))))
    (dolist (asd
              '("cadr-core.asd" "cadr-telemetry.asd" "cadr-ai.asd" "cadr-agent.asd"
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
