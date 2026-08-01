(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

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
                 "cadr ~A · aligned with pi v0.83.0 (+38, 74caa2649)"
                 version))))
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
                '("cadr-ai.asd" "cadr-agent.asd" "cadr-tui.asd"
                  "cadr-cli.asd" "cadr-storage.asd" "cadr-server.asd"
                  "cadr-evals.asd" "cadr-protocol.asd"
                  "src/cadr-ai/http.lisp"
                  "src/cadr-ai/utilities.lisp"
                  "src/cadr-cli/main.lisp"
                  "src/cadr-cli/tui.lisp"
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
                "*.py[cod]"))
      (is (search pattern ignore)))
    (is (not (probe-file (merge-pathnames "packages/" root))))
    (is (not (probe-file (merge-pathnames "goal9.md" root))))
    (is (not (probe-file (merge-pathnames "goal10.md" root))))
    (is (probe-file
         (merge-pathnames "docs/progress/goal-v9.md" root)))
    (is (probe-file
         (merge-pathnames "docs/progress/goal-v10.md" root)))))
