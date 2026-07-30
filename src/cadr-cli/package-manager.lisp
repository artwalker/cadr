(in-package #:cadr-cli)

(defstruct package-source
  (type :local :type symbol)
  spec
  name
  version
  repo
  host
  path
  ref
  (pinned-p nil :type boolean))

(defun exact-package-version-p (version)
  (and version
       (cl-ppcre:scan
        "^\\d+\\.\\d+\\.\\d+(?:-[0-9A-Za-z.-]+)?$"
        version)))

(defun parse-npm-package-spec (spec)
  (let* ((start
           (if (and (plusp (length spec))
                    (char= (char spec 0) #\@))
               (1+
                (or (position #\/ spec)
                    (length spec)))
               0))
         (separator
           (position #\@ spec :start start))
         (name
           (if separator
               (subseq spec 0 separator)
               spec))
         (version
           (and separator
                (subseq spec (1+ separator)))))
    (values name version)))

(defun strip-package-git-ref (source)
  (let* ((scp-p
           (cl-ppcre:scan "^git@[^:]+:" source))
         (path-start
           (cond
             (scp-p
              (1+ (position #\: source)))
             ((search "://" source)
              (let ((authority
                      (+ (search "://" source) 3)))
                (or
                 (position #\/ source
                           :start authority)
                 (length source))))
             (t
              (or (position #\/ source)
                  (length source)))))
         (separator
           (position #\@ source
                     :start path-start)))
    (if (and separator
             (< (1+ separator)
                (length source)))
        (values
         (subseq source 0 separator)
         (subseq source (1+ separator)))
        (values source nil))))

(defun parse-package-git-location (source)
  (multiple-value-bind (repo ref)
      (strip-package-git-ref source)
    (let ((host nil)
          (path nil)
          (clone-repo repo))
      (cond
        ((cl-ppcre:scan "^git@[^:]+:" repo)
         (let ((at (position #\@ repo))
               (colon (position #\: repo)))
           (setf host
                 (subseq repo (1+ at) colon)
                 path
                 (subseq repo (1+ colon)))))
        ((search "://" repo)
         (let* ((scheme-end
                  (+ (search "://" repo) 3))
                (slash
                  (position #\/ repo
                            :start scheme-end))
                (authority
                  (and slash
                       (subseq repo
                               scheme-end slash)))
                (at
                  (and authority
                       (position #\@ authority
                                 :from-end t))))
           (setf host
                 (and authority
                      (subseq authority
                              (if at (1+ at) 0)))
                 path
                 (and slash
                      (subseq repo (1+ slash))))))
        (t
         (let ((slash (position #\/ repo)))
           (when slash
             (setf host (subseq repo 0 slash)
                   path (subseq repo (1+ slash))
                   clone-repo
                   (format nil "https://~A"
                           repo))))))
      (when path
        (setf path
              (string-right-trim
               "/"
               (if
                   (uiop:string-suffix-p
                    path ".git")
                   (subseq path
                           0 (- (length path) 4))
                   path))))
      (when
          (or
           (null host)
           (null path)
           (< (count #\/ path) 1)
           (unsafe-git-source-p path)
           (find #\/ host)
           (search ".." host))
        (return-from
            parse-package-git-location nil))
      (make-package-source
       :type :git
       :repo clone-repo
       :host (string-downcase host)
       :path path
       :ref ref
       :pinned-p (not (null ref))))))

(defun explicit-package-git-url-p (source)
  (some
   (lambda (prefix)
     (string-prefix-p prefix source))
   '("https://" "http://" "ssh://"
     "git://")))

(defun parse-package-source (source)
  (let ((trimmed
          (string-trim
           '(#\Space #\Tab #\Newline #\Return)
           source)))
    (cond
      ((string-prefix-p "npm:" trimmed)
       (let ((spec
               (string-trim
                '(#\Space #\Tab)
                (subseq trimmed 4))))
         (multiple-value-bind (name version)
             (parse-npm-package-spec spec)
           (make-package-source
            :type :npm
            :spec spec
            :name name
            :version version
            :pinned-p
            (not
             (null
              (exact-package-version-p
               version)))))))
      ((string-prefix-p "git:" trimmed)
       (or
        (parse-package-git-location
         (string-trim
          '(#\Space #\Tab)
          (subseq trimmed 4)))
        (make-package-source
         :type :local :path trimmed)))
      ((explicit-package-git-url-p trimmed)
       (or
        (parse-package-git-location trimmed)
        (make-package-source
         :type :local :path trimmed)))
      (t
       (make-package-source
        :type :local :path trimmed)))))

(defun package-source-identity
    (source &optional base-directory)
  (let ((parsed
          (etypecase source
            (string
             (parse-package-source source))
            (package-source source))))
    (case (package-source-type parsed)
      (:npm
       (format nil "npm:~A"
               (package-source-name parsed)))
      (:git
       (format nil "git:~A/~A"
               (package-source-host parsed)
               (package-source-path parsed)))
      (:local
       (format
        nil "local:~A"
        (canonical-file-name
         (merge-pathnames
          (pathname
           (package-source-path parsed))
          (uiop:ensure-directory-pathname
           (or base-directory
               (uiop:getcwd))))))))))

(defun ensure-package-path-inside-root
    (root relative)
  (let* ((relative-path (pathname relative))
         (relative-directory
           (pathname-directory relative-path))
         (directory
           (uiop:ensure-directory-pathname root))
         (candidate
           (merge-pathnames
            (uiop:ensure-directory-pathname relative)
            directory))
         (root-name
           (namestring
            (uiop:ensure-absolute-pathname
             directory)))
         (candidate-name
           (namestring
            (uiop:ensure-absolute-pathname
             candidate))))
    (when
        (or
         (uiop:absolute-pathname-p relative-path)
         (member :up relative-directory))
      (error
       'cadr-ai:configuration-error
       :message
       "Package path resolves outside package install root"))
    (unless
        (uiop:string-prefix-p
         root-name candidate-name)
      (error
       'cadr-ai:configuration-error
       :message
       "Package path resolves outside package install root"))
    candidate))

(defun package-git-install-path
    (source root)
  (unless (eq :git
              (package-source-type source))
    (error "Not a git package source"))
  (ensure-package-path-inside-root
   root
   (format nil "~A/~A/"
           (package-source-host source)
           (package-source-path source))))

(defun package-npm-install-argv
    (sources install-root
     &key npm-command
       package-manager)
  (let* ((prefix
           (or npm-command '("npm")))
         (manager
           (string-downcase
            (or package-manager
                (pathname-name
                 (pathname
                  (first prefix)))
                "npm"))))
    (append
     prefix
     (cond
       ((string= manager "bun")
        (append
         (list "install")
         sources
         (list "--cwd"
               (namestring
                (uiop:ensure-directory-pathname
                 install-root))
               "--omit=peer")))
       ((string= manager "pnpm")
        (append
         (list "install")
         sources
         (list "--dir"
               (namestring
                (uiop:ensure-directory-pathname
                 install-root))
               "--strict-peer-dependencies=false")))
       (t
        (append
         (list
          "install"
          "--prefix"
          (namestring
           (uiop:ensure-directory-pathname
            install-root))
          "--no-save"
          "--legacy-peer-deps")
         sources))))))

(defun package-source-with-ref (source)
  (if (package-source-ref source)
      (format nil "~A@~A"
              (package-source-repo source)
              (package-source-ref source))
      (package-source-repo source)))

(defun dedupe-package-sources
    (user-sources project-sources
     &key user-base project-base)
  (let ((result nil)
        (seen (make-hash-table :test #'equal)))
    (dolist (entry
             (append
              (mapcar
               (lambda (source)
                 (list source :user user-base))
               user-sources)
              (mapcar
               (lambda (source)
                 (list source :project project-base))
               project-sources)))
      (destructuring-bind
          (source scope base)
          entry
        (let ((identity
                (package-source-identity
                 source base)))
          (multiple-value-bind (index found-p)
              (gethash identity seen)
            (if found-p
                (when (eq scope :project)
                  (setf (nth index result)
                        (cons scope source)))
                (progn
                  (setf
                   (gethash identity seen)
                   (length result))
                  (setf result
                        (append
                         result
                         (list
                          (cons scope
                                source))))))))))
    result))

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

(defun sequence-list (value)
  (cond
    ((null value) nil)
    ((vectorp value) (coerce value 'list))
    ((listp value) value)
    (t nil)))

(defun package-entry-source (entry)
  (cond
    ((stringp entry) entry)
    ((hash-table-p entry)
     (cadr-ai::json-get entry "source"))
    (t nil)))

(defun package-source-storage-value
    (source base-directory)
  (let ((parsed
          (parse-package-source source)))
    (if (eq :local
            (package-source-type parsed))
        (let* ((base
                 (uiop:ensure-directory-pathname
                  base-directory))
               (resolved
                 (uiop:ensure-absolute-pathname
                  (merge-pathnames
                   (pathname
                    (package-source-path parsed))
                   base))))
          (enough-namestring resolved base))
        source)))

(defun package-command-source-value
    (source cwd)
  (let ((parsed
          (parse-package-source source)))
    (if (eq :local
            (package-source-type parsed))
        (namestring
         (uiop:ensure-absolute-pathname
          (merge-pathnames
           (pathname
            (package-source-path parsed))
           (uiop:ensure-directory-pathname
            cwd))))
        source)))

(defun settings-package-entries
    (manager scope)
  (sequence-list
   (cadr-ai::json-get
    (ecase scope
      (:global
       (settings-manager-global manager))
      (:project
       (settings-manager-project manager)))
    "packages")))

(defun package-entry-identity
    (entry base-directory)
  (let ((source (package-entry-source entry)))
    (and source
         (package-source-identity
          source base-directory))))

(defun persist-package-source
    (manager source
     &key (scope :global)
       base-directory)
  (let* ((base
           (uiop:ensure-directory-pathname
            base-directory))
         (stored
           (package-source-storage-value
            source base))
         (identity
           (package-source-identity
            stored base))
         (entries
           (copy-list
            (settings-package-entries
             manager scope)))
         (existing
           (position
            identity entries
            :test #'equal
            :key
            (lambda (entry)
              (package-entry-identity
               entry base)))))
    (when existing
      (when
          (string=
           stored
           (package-entry-source
            (nth existing entries)))
        (return-from
            persist-package-source nil))
      (let ((entry (nth existing entries)))
        (if (hash-table-p entry)
            (cadr-ai::json-put
             entry "source" stored)
            (setf (nth existing entries)
                  stored))))
    (unless existing
      (setf entries
            (append entries
                    (list stored))))
    (settings-set
     manager "packages" entries
     :scope scope)
    t))

(defun remove-package-source
    (manager source
     &key (scope :global)
       base-directory)
  (let* ((base
           (uiop:ensure-directory-pathname
            base-directory))
         (identity
           (package-source-identity
            source base))
         (entries
           (copy-list
            (settings-package-entries
             manager scope)))
         (remaining
           (remove
            identity entries
            :test #'equal
            :key
            (lambda (entry)
              (package-entry-identity
               entry base)))))
    (when (= (length entries)
             (length remaining))
      (return-from
          remove-package-source nil))
    (settings-set
     manager "packages" remaining
     :scope scope)
    t))

(defun configured-package-records
    (manager
     &key global-base project-base)
  (let ((global nil)
        (project nil))
    (dolist
        (entry
         (settings-package-entries
          manager :global))
      (let ((source
              (package-entry-source entry)))
        (when source
          (push source global))))
    (when
        (settings-manager-project-trusted-p
         manager)
      (dolist
          (entry
           (settings-package-entries
            manager :project))
        (let ((source
                (package-entry-source entry)))
          (when source
            (push source project)))))
    (mapcar
     (lambda (entry)
       (let* ((scope (car entry))
              (source (cdr entry))
              (base
                (if (eq scope :project)
                    project-base
                    global-base))
              (parsed
                (parse-package-source source)))
         (list
          :scope scope
          :source source
          :base base
          :parsed parsed
          :path
          (and
           (eq :local
               (package-source-type parsed))
           (uiop:ensure-absolute-pathname
            (merge-pathnames
             (pathname
              (package-source-path parsed))
             (uiop:ensure-directory-pathname
              base)))))))
     (dedupe-package-sources
       (nreverse global)
       (nreverse project)
       :user-base global-base
       :project-base project-base))))

(defun materialize-package-records
    (records global-install-root
     project-install-root)
  (mapcar
   (lambda (record)
     (let ((copy (copy-list record)))
       (setf
        (getf copy :path)
        (package-record-install-path
         record global-install-root
         project-install-root))
       copy))
   records))

(defun package-resource-paths (records)
  (let ((global-extensions nil)
        (project-extensions nil)
        (global-skills nil)
        (project-skills nil)
        (global-prompts nil)
        (project-prompts nil)
        (global-themes nil)
        (project-themes nil))
    (dolist (record records)
      (let* ((root (getf record :path))
             (scope
               (if (eq :project
                       (getf record :scope))
                   :project :global)))
        (when root
          (let ((entry
                  (if
                      (uiop:directory-exists-p root)
                      (merge-pathnames
                       "extension.lisp"
                       (uiop:ensure-directory-pathname
                        root))
                      root)))
            (when (probe-file entry)
              (if (eq scope :project)
                  (push root project-extensions)
                  (push root global-extensions))))
          (when
              (uiop:directory-exists-p
               (merge-pathnames
                "skills/"
                (uiop:ensure-directory-pathname
                 root)))
            (let ((path
                    (merge-pathnames
                     "skills/"
                     (uiop:ensure-directory-pathname
                      root))))
              (if (eq scope :project)
                  (push path project-skills)
                  (push path global-skills))))
          (when
              (uiop:directory-exists-p
               (merge-pathnames
                "prompts/"
                (uiop:ensure-directory-pathname
                 root)))
            (let ((path
                    (merge-pathnames
                     "prompts/"
                     (uiop:ensure-directory-pathname
                      root))))
              (if (eq scope :project)
                  (push path project-prompts)
                  (push path global-prompts))))
          (when
              (uiop:directory-exists-p
               (merge-pathnames
                "themes/"
                (uiop:ensure-directory-pathname
                 root)))
            (let ((path
                    (merge-pathnames
                     "themes/"
                     (uiop:ensure-directory-pathname
                      root))))
              (if (eq scope :project)
                  (push path project-themes)
                  (push path global-themes)))))))
    (setf
     global-extensions (nreverse global-extensions)
     project-extensions (nreverse project-extensions)
     global-skills (nreverse global-skills)
     project-skills (nreverse project-skills)
     global-prompts (nreverse global-prompts)
     project-prompts (nreverse project-prompts)
     global-themes (nreverse global-themes)
     project-themes (nreverse project-themes))
    (list
     :extensions
     (append project-extensions global-extensions)
     :skills
     (append project-skills global-skills)
     :prompts
     (append project-prompts global-prompts)
     :themes
     (append project-themes global-themes)
     :global-extensions global-extensions
     :project-extensions project-extensions
     :global-skills global-skills
     :project-skills project-skills
     :global-prompts global-prompts
     :project-prompts project-prompts
     :global-themes global-themes
     :project-themes project-themes)))

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
