(in-package #:cadr-cli)

(defstruct package-command-options
  command
  source
  (local-p nil :type boolean)
  (force-p nil :type boolean)
  (offline-p nil :type boolean)
  project-trust-override
  (project-trust-override-supplied-p
   nil :type boolean)
  update-target
  (help-p nil :type boolean))

(defun parse-package-command (arguments)
  (let* ((name (first arguments))
         (command
           (cond
             ((string= name "uninstall") :remove)
             ((member name
                      '("install" "remove" "update"
                        "list" "config")
                      :test #'string=)
              (intern
               (string-upcase name)
               :keyword))
             (t nil))))
    (unless command
      (return-from parse-package-command nil))
    (let ((options
            (make-package-command-options
             :command command))
          (rest (rest arguments))
          (targets nil))
      (labels
          ((invalid (format-control &rest values)
             (error
              'cadr-ai:configuration-error
              :message
              (apply #'format nil
                     format-control values)))
           (set-trust (value)
             (when
                 (and
                  (package-command-options-project-trust-override-supplied-p
                   options)
                  (not
                   (eq
                    value
                    (package-command-options-project-trust-override
                     options))))
               (invalid
                "--approve and --no-approve cannot be combined"))
             (setf
              (package-command-options-project-trust-override
               options)
              value
              (package-command-options-project-trust-override-supplied-p
               options)
              t)))
        (loop while rest
              for argument = (pop rest)
              do
              (cond
                ((member argument '("-h" "--help")
                         :test #'string=)
                 (setf
                  (package-command-options-help-p options)
                  t))
                ((member argument '("-l" "--local")
                         :test #'string=)
                 (unless
                     (member command
                             '(:install :remove :config))
                   (invalid
                    "Unknown ~A option: ~A"
                    (string-downcase
                     (symbol-name command))
                    argument))
                 (setf
                  (package-command-options-local-p
                   options)
                  t))
                ((member argument '("-a" "--approve")
                         :test #'string=)
                 (set-trust t))
                ((member argument '("-na" "--no-approve")
                         :test #'string=)
                 (set-trust nil))
                ((string= argument "--force")
                 (unless (eq command :update)
                   (invalid
                    "Unknown ~A option: --force"
                    (string-downcase
                     (symbol-name command))))
                 (setf
                  (package-command-options-force-p options)
                  t))
                ((string= argument "--offline")
                 (setf
                  (package-command-options-offline-p
                   options)
                  t))
                ((and (eq command :update)
                      (member
                       argument
                       '("--self" "--extensions"
                         "--models" "--all")
                       :test #'string=))
                 (push
                  (intern
                   (string-upcase
                    (subseq argument 2))
                   :keyword)
                  targets))
                ((and (eq command :update)
                      (string= argument
                               "--extension"))
                 (unless rest
                   (invalid
                    "--extension requires a value"))
                 (push
                  (list :extensions
                        (pop rest))
                  targets))
                ((cli-string-prefix-p "-" argument)
                 (invalid
                  "Unknown ~A option: ~A"
                  (string-downcase
                   (symbol-name command))
                  argument))
                ((package-command-options-source options)
                 (invalid
                  "Unexpected argument ~A"
                  argument))
                (t
                 (setf
                  (package-command-options-source options)
                  argument)))))
      (when (> (length targets) 1)
        (error
         'cadr-ai:configuration-error
         :message
         "Update target options cannot be combined"))
      (when targets
        (let ((target (first targets)))
          (setf
           (package-command-options-update-target options)
           (if (listp target)
               target
               (list target)))))
      (when
          (and
           (member command '(:install :remove))
           (not
            (package-command-options-help-p options))
           (null
            (package-command-options-source options)))
        (error
         'cadr-ai:configuration-error
         :message
         (format nil
                 "Missing ~A source"
                 (string-downcase
                  (symbol-name command)))))
      (when
          (and
           (eq command :update)
           (package-command-options-source options)
           targets)
        (error
         'cadr-ai:configuration-error
         :message
         "An update source cannot be combined with an update target option"))
      (when
          (and
           (eq command :update)
           (null
            (package-command-options-update-target
             options)))
        (setf
         (package-command-options-update-target options)
         (if
             (package-command-options-source options)
             (list
              :extensions
              (package-command-options-source
               options))
             '(:self))))
      options)))

(defun package-command-usage
    (command)
  (ecase command
    (:install
     "cadr install <source> [-l] [--approve|--no-approve]")
    (:remove
     "cadr remove <source> [-l] [--approve|--no-approve]")
    (:update
     "cadr update [source] [--self|--extensions|--models|--all] [--extension <source>] [--force]")
    (:list
     "cadr list [--approve|--no-approve]")
    (:config
     "cadr config [-l] [--approve|--no-approve]")))

(defun print-package-command-help
    (command &optional
               (stream *standard-output*))
  (format stream "Usage:~%  ~A~%~%"
          (package-command-usage command))
  (ecase command
    (:install
     (format stream
             "Install a Common Lisp extension/resource package and add it to settings.~%"))
    (:remove
     (format stream
             "Remove a configured package. Alias: cadr uninstall.~%"))
    (:update
     (format stream
             "Update installed Git packages. Self updates follow the Lisp build/install method.~%"))
    (:list
     (format stream
             "List configured user and project packages.~%"))
    (:config
     (format stream
             "Show the active resource configuration paths.~%")))
  (finish-output stream))

(defun package-root-has-resources-p (root)
  (let ((directory
          (uiop:ensure-directory-pathname
           root)))
    (or
     (probe-file
      (merge-pathnames
       "extension.lisp" directory))
     (some
      (lambda (name)
        (uiop:directory-exists-p
         (merge-pathnames name directory)))
      '("skills/" "prompts/" "themes/")))))

(defun install-git-package
    (source install-root
     &key
       (runner #'default-git-clone-runner))
  (let* ((destination
           (package-git-install-path
            source install-root))
         (staging
           (make-extension-staging-directory
            (uiop:pathname-directory-pathname
             destination)))
         (repo
           (package-source-repo source))
         (ref
           (package-source-ref source)))
    (ensure-directories-exist
     (merge-pathnames
      "anchor"
      (uiop:pathname-directory-pathname
       destination)))
    (when (probe-file destination)
      (error
       'cadr-ai:configuration-error
       :message
       (format nil
               "Package destination already exists: ~A"
               (namestring destination))))
    (unwind-protect
         (progn
           (funcall
            runner
            (append
             (list "git" "clone")
             (when ref
               (list "--branch" ref
                     "--single-branch"))
             (list "--" repo
                   (namestring staging))))
           (unless
               (package-root-has-resources-p
                staging)
             (error
              'cadr-ai:configuration-error
              :message
              "Installed package has no Lisp extension, skill, prompt, or theme resources"))
           (rename-file staging destination)
           (setf staging nil)
           destination)
      (when (and staging
                 (probe-file staging))
        (uiop:delete-directory-tree
         staging
         :validate t
         :if-does-not-exist
         :ignore)))))

(defun package-record-install-path
    (record global-install-root
     project-install-root)
  (or
   (getf record :path)
   (let ((parsed
           (getf record :parsed)))
     (when (eq :git
               (package-source-type parsed))
       (package-git-install-path
        parsed
        (if (eq :project
                (getf record :scope))
            project-install-root
            global-install-root))))))

(defun print-configured-packages
    (records &optional
               (stream *standard-output*))
  (if (null records)
      (format stream "No packages installed.~%")
      (dolist (scope '(:global :project))
        (let ((selected
                (remove scope records
                        :test-not #'eq
                        :key
                        (lambda (record)
                          (getf record :scope)))))
          (when selected
            (format stream "~:(~A~) packages:~%"
                    scope)
            (dolist (record selected)
              (format stream "  ~A~%"
                      (getf record :source)))))))
  (finish-output stream))

(defun handle-package-command
    (arguments
     &key
       (cwd (uiop:getcwd))
       (agent-directory
         (default-agent-directory))
       (output *standard-output*)
       (error-output *error-output*)
       (offline-p nil)
       (runner #'default-git-clone-runner))
  (let ((options
          (parse-package-command arguments)))
    (unless options
      (return-from handle-package-command
        (values nil nil)))
    (when
        (package-command-options-help-p
         options)
      (print-package-command-help
       (package-command-options-command
        options)
       output)
      (return-from handle-package-command
        (values t 0)))
    (let* ((cwd
             (uiop:ensure-directory-pathname
              cwd))
           (agent
             (uiop:ensure-directory-pathname
              agent-directory))
           (project-config
             (merge-pathnames ".cadr/" cwd))
           (global-settings
             (merge-pathnames
              "settings.json" agent))
           (project-settings
             (merge-pathnames
              "settings.json" project-config))
           (trust-store
             (make-project-trust-store
              (merge-pathnames
               "trust.json" agent)))
           (trusted-p
             (resolve-project-trusted
              trust-store cwd
              :override
              (package-command-options-project-trust-override
               options)
              :override-supplied-p
              (package-command-options-project-trust-override-supplied-p
               options)
              :default :ask
              :has-ui-p nil))
           (settings
             (make-settings-manager
              :global-path global-settings
              :project-path project-settings
              :project-trusted-p trusted-p))
           (records
             (configured-package-records
              settings
              :global-base agent
              :project-base project-config))
           (command
             (package-command-options-command
              options))
           (scope
             (if
                 (package-command-options-local-p
                  options)
                 :project :global))
           (base
             (if (eq scope :project)
                 project-config agent))
           (global-install-root
             (merge-pathnames
              "packages/" agent))
           (project-install-root
             (merge-pathnames
              "packages/" project-config))
           (offline-p
             (or
              offline-p
              (package-command-options-offline-p
               options))))
      (when
          (and
           (eq scope :project)
           (member command '(:install :remove))
           (not trusted-p))
        (error
         'cadr-ai:configuration-error
         :message
         "Project is not trusted. Use --approve to modify local package config."))
      (ecase command
        (:install
         (let* ((source-text
                  (package-command-options-source
                   options))
                (source
                  (parse-package-source
                   source-text)))
           (case
             (package-source-type source)
             (:npm
              (error
               'cadr-ai:configuration-error
               :message
               "npm packages are unavailable in the Common Lisp build; install a Lisp local or Git package"))
             (:local
              (let ((path
                      (uiop:ensure-absolute-pathname
                       (merge-pathnames
                        (pathname
                         (package-source-path
                          source))
                        cwd))))
                (unless
                    (package-root-has-resources-p
                     path)
                  (error
                   'cadr-ai:configuration-error
                   :message
                   "Local package has no Lisp extension, skill, prompt, or theme resources"))))
             (:git
              (when offline-p
                (error
                 'cadr-ai:configuration-error
                 :message
                 "Cannot install a missing Git package while offline"))
              (install-git-package
               source
               (if (eq scope :project)
                   project-install-root
                   global-install-root)
               :runner runner)))
           (persist-package-source
            settings
            (package-command-source-value
             source-text cwd)
            :scope scope
            :base-directory base)
           (format output "Installed ~A~%"
                   source-text)
           (values t 0)))
        (:remove
         (let* ((source
                  (package-command-options-source
                   options))
                (stored-source
                  (package-command-source-value
                   source cwd)))
           (if
               (remove-package-source
                settings stored-source
                :scope scope
                :base-directory base)
               (progn
                 (let ((parsed
                         (parse-package-source
                          source)))
                   (when (eq :git
                             (package-source-type
                              parsed))
                     (let ((path
                             (package-git-install-path
                              parsed
                              (if (eq scope :project)
                                  project-install-root
                                  global-install-root))))
                       (when (probe-file path)
                         (uiop:delete-directory-tree
                          path
                          :validate t
                          :if-does-not-exist
                          :ignore)))))
                 (format output "Removed ~A~%"
                         source)
                 (values t 0))
               (progn
                 (format error-output
                         "No matching package found for ~A~%"
                         source)
                 (values t 1)))))
        (:list
         (print-configured-packages
          records output)
         (values t 0))
        (:config
         (format output
                 "Global settings: ~A~%Project settings: ~A~%Project trusted: ~:[no~;yes~]~%"
                 (namestring global-settings)
                 (namestring project-settings)
                 trusted-p)
         (values t 0))
        (:update
         (let ((target
                 (package-command-options-update-target
                  options)))
           (case (first target)
             (:models
              (format output
                      "Model catalogs are bundled with this cadr build.~%"))
             (:self
              (format output
                      "Update cadr through the Common Lisp build/install method.~%"))
             ((:extensions :all)
              (unless offline-p
                (let ((wanted
                        (second target)))
                  (dolist (record records)
                    (when
                        (and
                         (eq :git
                             (package-source-type
                              (getf record
                                    :parsed)))
                         (or
                          (null wanted)
                          (equal
                           (package-source-identity
                            wanted cwd)
                           (package-source-identity
                            (getf record :source)
                            (getf record :base))))
                         (not
                          (package-source-pinned-p
                           (getf record
                                 :parsed))))
                      (let ((path
                              (package-record-install-path
                               record
                               global-install-root
                               project-install-root)))
                        (when (probe-file path)
                          (funcall
                           runner
                           (list
                            "git" "-C"
                            (namestring path)
                            "pull" "--ff-only")))))))))
              (format output
                      "Updated packages~%")))
           (values t 0))))))
