(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(test package-sources-parse-reference-npm-git-ssh-and-local-forms
  (let ((exact
          (cadr-cli::parse-package-source
           "npm:@scope/pkg@1.2.3"))
        (range
          (cadr-cli::parse-package-source
           "npm:@scope/pkg@^1.2.3")))
    (is (eq :npm
            (cadr-cli::package-source-type exact)))
    (is (string= "@scope/pkg"
                 (cadr-cli::package-source-name exact)))
    (is (cadr-cli::package-source-pinned-p exact))
    (is (not
         (cadr-cli::package-source-pinned-p range))))
  (dolist
      (input
       '("https://github.com/user/repo"
         "ssh://git@github.com/user/repo"
         "git:git@github.com:user/repo"
         "git:github.com/user/repo"
         "https://github.com/user/repo.git"))
    (let ((source
            (cadr-cli::parse-package-source input)))
      (is (eq :git
              (cadr-cli::package-source-type source)))
      (is (string= "github.com"
                   (cadr-cli::package-source-host source)))
      (is (string= "user/repo"
                   (cadr-cli::package-source-path source)))
      (is (string=
           "git:github.com/user/repo"
           (cadr-cli::package-source-identity
            source)))))
  (let ((pinned
          (cadr-cli::parse-package-source
           "git:git@github.com:user/repo@v1.0.0")))
    (is (cadr-cli::package-source-pinned-p pinned))
    (is (string= "v1.0.0"
                 (cadr-cli::package-source-ref pinned))))
  (dolist
      (input
       '("./relative/package"
         "../relative/package"
         "git@github.com:user/repo"
         "github.com/user/repo"))
    (is (eq :local
            (cadr-cli::package-source-type
             (cadr-cli::parse-package-source
              input))))))

(test package-paths-commands-and-cross-scope-dedupe-are-safe
  (with-test-directory (root)
    (let* ((install-root
             (merge-pathnames "packages/" root))
           (source
             (cadr-cli::parse-package-source
              "git:github.com/user/repo"))
           (path
             (cadr-cli::package-git-install-path
              source install-root)))
      (is (uiop:string-suffix-p
           (namestring path)
           "packages/github.com/user/repo/"))
      (signals cadr-ai:configuration-error
        (cadr-cli::ensure-package-path-inside-root
         install-root "../../escape/"))
      (is (equal
           (list
            "npm" "install" "--prefix"
            (namestring
             (uiop:ensure-directory-pathname
              install-root))
            "--no-save" "--legacy-peer-deps"
            "@scope/pkg")
           (cadr-cli::package-npm-install-argv
            '("@scope/pkg") install-root)))
      (is (equal
           (list
            "bun" "install" "pkg"
            "--cwd"
            (namestring
             (uiop:ensure-directory-pathname
              install-root))
            "--omit=peer")
           (cadr-cli::package-npm-install-argv
            '("pkg") install-root
            :npm-command '("bun")
            :package-manager "bun")))
      (is (equal
           '((:project
              . "ssh://git@github.com/user/repo@main"))
           (cadr-cli::dedupe-package-sources
            '("https://github.com/user/repo")
            '("ssh://git@github.com/user/repo@main")
           :user-base root
            :project-base root))))))

(test package-command-parser-covers-aliases-targets-and-errors
  (let ((install
          (cadr-cli::parse-package-command
           '("install" "./extension" "--local"
             "--approve")))
        (remove
          (cadr-cli::parse-package-command
           '("uninstall" "./extension")))
        (update
          (cadr-cli::parse-package-command
           '("update" "--extension"
             "git:github.com/user/repo"
             "--offline"))))
    (is (eq :install
            (cadr-cli::package-command-options-command
             install)))
    (is (cadr-cli::package-command-options-local-p
         install))
    (is (eq t
            (cadr-cli::package-command-options-project-trust-override
             install)))
    (is (eq :remove
            (cadr-cli::package-command-options-command
             remove)))
    (is (equal
         '(:extensions
           "git:github.com/user/repo")
         (cadr-cli::package-command-options-update-target
          update)))
    (is (cadr-cli::package-command-options-offline-p
         update)))
  (is (null
       (cadr-cli::parse-package-command
        '("--model" "mock"))))
  (signals cadr-ai:configuration-error
    (cadr-cli::parse-package-command
     '("install")))
  (signals cadr-ai:configuration-error
    (cadr-cli::parse-package-command
     '("install" "./extension" "--bogus")))
  (signals cadr-ai:configuration-error
    (cadr-cli::parse-package-command
     '("update" "--models" "--all"))))

(test local-package-settings-persist-dedupe-remove-and-resolve-resources
  (with-test-directory (root)
    (let* ((agent
             (merge-pathnames "agent/" root))
           (project
             (merge-pathnames "project/" root))
           (package
             (merge-pathnames "packages/review/" root))
           (global-settings
             (merge-pathnames "settings.json" agent))
           (project-settings
             (merge-pathnames ".cadr/settings.json"
                              project))
           (manager
             (cadr-cli::make-settings-manager
              :global-path global-settings
              :project-path project-settings
              :project-trusted-p t)))
      (write-text
       (merge-pathnames "extension.lisp" package)
       "(define-command \"review\" :handler (lambda (arguments context) (declare (ignore arguments context))))")
      (write-text
       (merge-pathnames "skills/review/SKILL.md"
                        package)
       "---\nname: review\ndescription: Review\n---\nReview.")
      (write-text
       (merge-pathnames "prompts/review.md" package)
       "---\nname: review\ndescription: Review\n---\nReview.")
      (write-text
       (merge-pathnames "themes/review.json" package)
       "{\"name\":\"review\",\"colors\":{}}")
      (is (cadr-cli::persist-package-source
           manager
           (namestring package)
           :scope :global
           :base-directory agent))
      (is (not
           (cadr-cli::persist-package-source
            manager
            (format nil "~A/"
                    (string-right-trim
                     "/" (namestring package)))
            :scope :global
            :base-directory agent)))
      (let* ((records
               (cadr-cli::configured-package-records
                manager
                :global-base agent
                :project-base
                (merge-pathnames ".cadr/" project)))
             (paths
               (cadr-cli::package-resource-paths
                records)))
        (is (= 1 (length records)))
        (is (= 1 (length (getf paths :extensions))))
        (is (= 1 (length (getf paths :skills))))
        (is (= 1 (length (getf paths :prompts))))
        (is (= 1 (length (getf paths :themes)))))
      (is (cadr-cli::remove-package-source
           manager
           (format nil "~A/"
                   (string-right-trim
                    "/" (namestring package)))
           :scope :global
           :base-directory agent))
      (is (null
           (cadr-cli::configured-package-records
            manager
            :global-base agent
            :project-base
            (merge-pathnames ".cadr/" project))))
      (setf
       (cadr-cli::settings-manager-project-trusted-p
        manager)
       nil)
      (signals error
        (cadr-cli::persist-package-source
         manager "./blocked"
         :scope :project
         :base-directory
         (merge-pathnames ".cadr/" project))))))

(test configured-package-resources-enter-extension-and-resource-loaders
  (with-test-directory (root)
    (let* ((package
             (merge-pathnames "package/" root))
           (agent
             (merge-pathnames "agent/" root))
           (project
             (merge-pathnames "project/" root))
           (extension-output
             (make-string-output-stream)))
      (ensure-directories-exist project)
      (write-text
       (merge-pathnames "extension.lisp" package)
       "(define-command \"package-command\" :handler (lambda (arguments context) (declare (ignore arguments context)) \"ok\"))")
      (write-text
       (merge-pathnames "skills/package-skill/SKILL.md"
                        package)
       (format nil
               "---~%name: package-skill~%description: Package skill~%---~%Use package skill."))
      (let ((manager
              (cadr-cli::make-cli-extension-manager
               :cwd project
               :global-directory
               (merge-pathnames "extensions/" agent)
               :configured-package-paths
               (list (cons :project package))
               :output extension-output)))
        (cadr-cli::reload-cli-extensions manager)
        (is (not
             (null
              (cadr-agent::find-extension-command
               (cadr-agent::extension-host-snapshot
                (cadr-cli::cli-extension-manager-host
                 manager))
               "package-command")))))
      (let* ((paths
               (cadr-cli::package-resource-paths
                (list
                 (list :scope :project
                       :path package))))
             (loader
               (cadr-cli::make-default-resource-loader
                :cwd project
                :agent-directory agent
                :project-trusted-p t
                :package-project-skill-paths
                (getf paths :project-skills)))
             (snapshot
               (cadr-cli::reload-resources loader)))
        (is (not
             (null
              (find
               "package-skill"
               (cadr-cli::resource-snapshot-skills
                snapshot)
               :key #'cadr-agent::skill-name
               :test #'string=)))))
      (let ((disabled
              (cadr-cli::make-cli-extension-manager
               :cwd project
               :global-directory
               (merge-pathnames "extensions/" agent)
               :configured-package-paths
               (list (cons :project package))
               :no-discovery-p t
               :output extension-output)))
        (cadr-cli::reload-cli-extensions disabled)
        (is (null
            (cadr-agent::find-extension-command
              (cadr-agent::extension-host-snapshot
               (cadr-cli::cli-extension-manager-host
                disabled))
              "package-command")))))))

(test goal9-malformed-package-manifest-ignores-invalid-fields-without-dropping-valid-fields
  (with-test-directory (root)
    (let ((package
            (merge-pathnames "package/" root)))
      (write-text
       (merge-pathnames
        "skills/bad/SKILL.md" package)
       "---\nname: bad\ndescription: Must not load\n---\n")
      (write-text
       (merge-pathnames "prompts/valid.md"
                        package)
       "Valid prompt\n")
      (write-text
       (merge-pathnames "package.json"
                        package)
       "{\"name\":\"bad-package\",\"version\":\"1.0.0\",\"pi\":{\"skills\":\"./skills\",\"prompts\":[\"./prompts\"]}}")
      (let ((paths
              (cadr-cli::package-resource-paths
               (list
                (list :scope :project
                      :path package)))))
        (is (null (getf paths :skills)))
        (is (= 1
               (length
                (getf paths :prompts))))
        (is (uiop:subpathp
             (first (getf paths :prompts))
             package))))))
