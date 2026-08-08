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
           (member
            (package-command-options-source options)
            (list "self" (cadr-ai::cadr-product-slug))
            :test #'string=))
        (setf
         (package-command-options-source options) nil
         (package-command-options-update-target options)
         '(:self)))
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
  (let ((slug (cadr-ai::cadr-product-slug)))
    (ecase command
      (:install
       (format nil "~A install <source> [-l] [--approve|--no-approve]"
               slug))
      (:remove
       (format nil "~A remove <source> [-l] [--approve|--no-approve]"
               slug))
      (:update
       (format
        nil
        "~A update [source|self|~A] [--self|--extensions|--models|--all] [--extension <source>] [--approve|--no-approve] [--force]"
        slug slug))
      (:list
       (format nil "~A list [--approve|--no-approve]" slug))
      (:config
       (format nil "~A config [-l] [--approve|--no-approve]" slug)))))

(defun print-package-command-help
    (command &optional
               (stream *standard-output*))
  (let ((slug (cadr-ai::cadr-product-slug)))
    (format stream "~A~%  ~A~%~%"
          (cadr-tui:theme-bold
           "Usage:"
           :enabled-p (interactive-stream-p stream))
          (package-command-usage command))
    (ecase command
      (:install
       (format
        stream
        "Install a package and add it to settings.~%~%Options:~%  -l, --local       Install project-locally (.~A/settings.json)~%  -a, --approve     Trust project-local files for this command~%  -na, --no-approve Ignore project-local files for this command~%~%Examples:~%  ~A install git:github.com/user/repo~%  ~A install git:git@github.com:user/repo~%  ~A install https://github.com/user/repo~%  ~A install ssh://git@github.com/user/repo~%  ~A install ./local/path~%"
        slug slug slug slug slug slug))
      (:remove
       (format
        stream
        "Remove a package and its source from settings.~%Alias: ~A uninstall <source> [-l]~%~%Options:~%  -l, --local       Remove from project settings (.~A/settings.json)~%  -a, --approve     Trust project-local files for this command~%  -na, --no-approve Ignore project-local files for this command~%~%Examples:~%  ~A remove git:github.com/user/repo~%  ~A uninstall ./local/path~%"
        slug slug slug slug))
      (:update
       (format
        stream
        "Update ~A, installed packages, or model catalogs.~%~%Options:~%  --self                  Update ~A only (default when no target is given)~%  --extensions            Update installed packages only~%  --models                Refresh model catalogs only~%  --all                   Update ~A and installed packages~%  --extension <source>    Update one package only~%  -a, --approve           Trust project-local files for this command~%  -na, --no-approve       Ignore project-local files for this command~%  --force                 Reinstall ~A even if the current version is latest~%~%Short forms:~%  ~A update                Update ~A only~%  ~A update --all          Update ~A and all extensions~%  ~A update --models       Refresh model catalogs only~%  ~A update <source>       Update one package~%  ~A update ~A           Update ~A only (self works as alias to ~A)~%"
        slug slug slug slug
        slug slug slug slug slug slug slug slug slug slug))
      (:list
       (format
        stream
        "List installed packages from user and project settings.~%~%Options:~%  -a, --approve      Trust project-local files for this command~%  -na, --no-approve  Ignore project-local files for this command~%"))
      (:config
       (format
        stream
        "Open the resource configuration TUI to enable or disable package resources.~%Without -l, starts in global settings (~~/.~A/agent/settings.json).~%Press Tab in the TUI to switch between global and project-local modes.~%~%Options:~%  -l, --local       Edit project overrides (.~A/settings.json)~%  -a, --approve     Trust project-local files for this command with -l~%  -na, --no-approve Ignore project-local files for this command with -l~%"
        slug slug)))
    (terpri stream)
    (finish-output stream)))

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

(defun package-update-check-group-path ()
  (merge-pathnames
   (format nil "cadr-package-update-~D-~D.pgid"
           (get-universal-time)
           (random most-positive-fixnum))
   (uiop:temporary-directory)))

(defun package-update-check-process-argv
    (argv group-path)
  (if (or (uiop:os-windows-p)
          (not (probe-file "/usr/bin/setsid")))
      argv
      (append
       (list
        "/usr/bin/setsid" "--fork" "--wait"
        "/bin/sh" "-c"
        "group_path=$1; shift; printf '%s' \"$$\" > \"$group_path\"; exec \"$@\""
        "cadr-package-update-check"
        (namestring group-path))
       argv)))

(defun package-update-check-environment ()
  (let ((prompt-prefix "GIT_TERMINAL_PROMPT="))
    (cons
     "GIT_TERMINAL_PROMPT=0"
     (remove-if
      (lambda (entry)
        (uiop:string-prefix-p prompt-prefix entry))
      #+sbcl (sb-ext:posix-environ)
      #-sbcl nil))))

(defun stop-package-update-check-process
    (process group-path)
  (when process
    (let* ((group-id
             (and group-path
                  (probe-file group-path)
                  (ignore-errors
                    (parse-integer
                     (uiop:read-file-string group-path)
                     :junk-allowed t))))
           (pid
             (ignore-errors
               (uiop:process-info-pid process))))
      (if pid
          (kill-process-tree (or group-id pid))
          (ignore-errors
            (uiop:terminate-process process :urgent t))))
    (ignore-errors
      (uiop:wait-process process)))
  nil)

(defun default-package-update-check-runner
    (argv
     &key
       (timeout-seconds 10)
       (clock #'get-internal-real-time))
  (let* ((group-path
           (and (not (uiop:os-windows-p))
                (probe-file "/usr/bin/setsid")
                (package-update-check-group-path)))
         (process
           (uiop:launch-program
            (package-update-check-process-argv
             argv group-path)
            :environment
            (package-update-check-environment)
            :output :stream
            ;; UIOP defines NIL as the platform null device. Keep git and
            ;; transport diagnostics out of every user-visible stream.
            :error-output nil))
         (output-stream
           (uiop:process-info-output process))
         (deadline
           (+ (funcall clock)
              (* timeout-seconds
                 internal-time-units-per-second)))
         (completed-p nil))
    (unwind-protect
         (progn
           (loop while (uiop:process-alive-p process)
                 do
                 (when (>= (funcall clock)
                           deadline)
                   (stop-package-update-check-process
                    process group-path)
                   (error "Package update check timed out"))
                 (sleep 0.01d0))
           (let ((output
                   (with-output-to-string (stream)
                     (loop for line =
                             (read-line output-stream nil nil)
                           while line
                           do (write-line line stream))))
                 (status (uiop:wait-process process)))
             (setf completed-p t)
             (unless (zerop (or status 1))
               (error "Package update check command failed"))
             output))
      (when (and (not completed-p)
                 (ignore-errors
                   (uiop:process-alive-p process)))
        (stop-package-update-check-process
         process group-path))
      (when output-stream
        (ignore-errors
          (close output-stream)))
      (when (and group-path
                 (probe-file group-path))
        (ignore-errors
          (delete-file group-path))))))

(defun package-update-git-output
    (runner path &rest arguments)
  (funcall
   runner
   (append
    (list "git" "-C" (namestring path))
    arguments)))

(defun package-update-remote-ref (runner path)
  (let ((upstream
          (ignore-errors
            (string-trim
             '(#\Space #\Tab #\Newline #\Return)
             (package-update-git-output
              runner path
              "rev-parse" "--abbrev-ref"
              "@{upstream}")))))
    (if (and upstream
             (uiop:string-prefix-p
              "origin/" upstream)
             (> (length upstream)
                (length "origin/")))
        (format nil "refs/heads/~A"
                (subseq upstream
                        (length "origin/")))
        nil)))

(defun package-update-git-object-id (output)
  (let* ((trimmed
           (string-trim
            '(#\Space #\Tab #\Newline #\Return)
            output))
         (end
           (or (position-if
                (lambda (character)
                  (member character
                          '(#\Space #\Tab #\Newline #\Return)))
                trimmed)
               (length trimmed)))
         (object-id (subseq trimmed 0 end)))
    (and (= 40 (length object-id))
         (every
          (lambda (character)
            (digit-char-p character 16))
          object-id)
         (string-downcase object-id))))

(defun package-git-update-available-p
    (record runner)
  (let* ((path (getf record :path))
         (local
           (package-update-git-object-id
            (package-update-git-output
             runner path "rev-parse" "HEAD")))
         (remote-ref
           (package-update-remote-ref runner path))
         (remote
           (or
            (and
             remote-ref
             (package-update-git-object-id
              (package-update-git-output
               runner path
               "ls-remote" "origin" remote-ref)))
            ;; Match Pi's Git update contract: an unavailable, empty, or
            ;; malformed upstream ref falls back to the remote default branch.
            (package-update-git-object-id
             (package-update-git-output
              runner path
              "ls-remote" "origin" "HEAD")))))
    (and local remote
         (not (string= local remote)))))

(defun package-update-records-project-first (records)
  (append
   (remove-if-not
    (lambda (record)
      (eq :project (getf record :scope)))
    records)
   (remove-if
    (lambda (record)
      (eq :project (getf record :scope)))
    records)))

(defun package-update-candidate-record-p (record)
  (let ((source (getf record :parsed))
        (path (getf record :path)))
    (and
     (typep source 'package-source)
     (eq :git (package-source-type source))
     (not (package-source-pinned-p source))
     path
     (probe-file path))))

(defun package-update-record-result (record runner)
  (handler-case
      (when (package-git-update-available-p
             record runner)
        (let ((source (getf record :parsed)))
          (format nil "~A/~A"
                  (package-source-host source)
                  (package-source-path source))))
    (condition () nil)))

(defun run-package-update-checks
    (records runner max-concurrency)
  (let* ((items (coerce records 'vector))
         (count (length items)))
    (when (zerop count)
      (return-from run-package-update-checks nil))
    (let ((results (make-array count :initial-element nil))
          (next-index 0)
          (lock
            (sb-thread:make-mutex
             :name "cadr package update scheduler")))
      (labels
          ((claim-index ()
             (sb-thread:with-mutex (lock)
               (when (< next-index count)
                 (prog1 next-index
                   (incf next-index)))))
           (worker ()
             (loop for index = (claim-index)
                   while index
                   do
                   (setf
                    (aref results index)
                    (package-update-record-result
                     (aref items index) runner)))))
        (let ((threads nil)
              (completed-p nil))
          (unwind-protect
               (progn
                 (setf
                  threads
                  (loop
                    repeat
                    (min count
                         (max 1 max-concurrency))
                    collect
                    (sb-thread:make-thread
                     #'worker
                     :name "cadr package update check")))
                 (dolist (thread threads)
                   (cadr-core:join-active-thread
                    thread
                    :reason
                    "Package update results require every bounded worker to finish"))
                 (setf completed-p t)
                 (loop for result across results
                       when result collect result))
            ;; The TUI owns only the outer update-check thread.  If cleanup
            ;; terminates that owner, unwind its lexically owned workers too;
            ;; otherwise their git subprocesses can outlive the session.
            (unless completed-p
              (dolist (thread threads)
                (cadr-core:stop-thread-for-cleanup
                 thread)))))))))

(defun check-for-available-package-updates
    (records
     &key
       (runner #'default-package-update-check-runner)
       (offline-p (offline-mode-p))
       (max-concurrency 4))
  (when offline-p
    (return-from
        check-for-available-package-updates nil))
  (run-package-update-checks
   (remove-if-not
    #'package-update-candidate-record-p
    (package-update-records-project-first records))
   runner max-concurrency))

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
             (cadr-core:project-config-directory cwd))
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
         (run-config-selector
          settings cwd agent output
          :write-scope scope
          :project-mode-available-p trusted-p)
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
