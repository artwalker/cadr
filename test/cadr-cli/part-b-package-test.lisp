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

(test goal17-installed-git-package-update-check-matches-the-baseline-contract
  ;; pi@74caa2649 package-manager.ts:1159-1221 checks every unpinned,
  ;; materialized package and compares local HEAD with the remote upstream.
  (with-test-directory (root)
    (let* ((path (merge-pathnames "github.com/user/repo/" root))
           (missing-path
             (merge-pathnames "github.com/user/missing/" root))
           (source
             (cadr-cli::parse-package-source
              "git:github.com/user/repo"))
           (pinned-source
             (cadr-cli::parse-package-source
              "git:github.com/user/pinned@v1"))
           (record
             (list :scope :global
                   :source "git:github.com/user/repo"
                   :parsed source
                   :path path))
           (pinned-record
             (list :scope :global
                   :source "git:github.com/user/pinned@v1"
                   :parsed pinned-source
                   :path path))
           (missing-record
             (list :scope :global
                   :source "git:github.com/user/missing"
                   :parsed
                   (cadr-cli::parse-package-source
                    "git:github.com/user/missing")
                   :path missing-path))
           (commands nil)
           (local (make-string 40 :initial-element #\a))
           (remote (make-string 40 :initial-element #\b)))
      (ensure-directories-exist
       (merge-pathnames "anchor" path))
      (flet ((runner (argv)
               (push argv commands)
               (cond
                 ((member "--abbrev-ref" argv :test #'string=)
                  "origin/main")
                 ((member "ls-remote" argv :test #'string=)
                  (format nil "~A~Crefs/heads/main~%" remote #\Tab))
                 ((member "HEAD" argv :test #'string=)
                  local)
                 (t (error "Unexpected git command: ~S" argv)))))
        (is (equal
             '("github.com/user/repo")
             (cadr-cli::check-for-available-package-updates
              (list record) :runner #'runner)))
        (is
         (some
          (lambda (argv)
            (and (member "ls-remote" argv :test #'string=)
                 (member "refs/heads/main" argv :test #'string=)))
          commands))
        (is
         (notany
          (lambda (argv)
            (or
             (member "core.sshCommand=ssh -oBatchMode=yes"
                     argv :test #'string=)
             (member "core.sshCommand" argv :test #'string=)))
          commands))
        (setf commands nil)
        (is (null
             (cadr-cli::check-for-available-package-updates
              (list record) :runner #'runner :offline-p t)))
        (is (null commands))
        (is (null
             (cadr-cli::check-for-available-package-updates
              (list pinned-record missing-record)
              :runner #'runner)))
        (is (null commands))
        (flet ((same-runner (argv)
                 (cond
                   ((member "--abbrev-ref" argv :test #'string=)
                    "origin/main")
                   ((member "ls-remote" argv :test #'string=)
                    (format nil "~A~Crefs/heads/main~%"
                            local #\Tab))
                   (t local))))
          (is (null
               (cadr-cli::check-for-available-package-updates
                (list record) :runner #'same-runner))))
        (dolist (unusable-upstream
                 '("" "not-an-object-id"))
          (let ((remote-queries nil))
            (flet ((fallback-runner (argv)
                     (cond
                       ((member "--abbrev-ref" argv :test #'string=)
                        "origin/main")
                       ((member "ls-remote" argv :test #'string=)
                        (let ((ref (car (last argv))))
                          (push ref remote-queries)
                          (if (string= ref "HEAD")
                              (format nil "~A~CHEAD~%" remote #\Tab)
                              unusable-upstream)))
                       (t local))))
              (is
               (equal
                '("github.com/user/repo")
                (cadr-cli::check-for-available-package-updates
                 (list record) :runner #'fallback-runner)))
              (is
               (equal
                '("refs/heads/main" "HEAD")
                (nreverse remote-queries))))))
        (let ((remote-queries nil))
          (flet ((no-upstream-runner (argv)
                   (cond
                     ((member "--abbrev-ref" argv :test #'string=)
                      "main")
                     ((member "ls-remote" argv :test #'string=)
                      (push (car (last argv)) remote-queries)
                      (format nil "~A~CHEAD~%" remote #\Tab))
                     (t local))))
            (is
             (equal
              '("github.com/user/repo")
              (cadr-cli::check-for-available-package-updates
               (list record) :runner #'no-upstream-runner)))
            (is (equal '("HEAD") (nreverse remote-queries)))))
        (flet ((malformed-runner (argv)
                 (cond
                   ((member "--abbrev-ref" argv :test #'string=)
                    "origin/main")
                   ((member "ls-remote" argv :test #'string=)
                    "not-an-object-id")
                   (t local))))
          (is (null
               (cadr-cli::check-for-available-package-updates
                (list record) :runner #'malformed-runner))))
        (flet ((failed-runner (argv)
                 (declare (ignore argv))
                 (error "private git failure")))
          (is (null
               (cadr-cli::check-for-available-package-updates
                (list record) :runner #'failed-runner))))))))

(test goal17-package-update-checks-are-project-first-bounded-and-stable
  ;; pi@74caa2649 package-manager.ts:1164-1221 queues project packages before
  ;; user packages, runs at most four checks, and stores results by input index.
  ;; Semaphores force reverse completion without relying on scheduler timing.
  (with-test-directory (root)
    (labels
        ((make-record (scope name)
           (let ((path (merge-pathnames
                        (format nil "~A/" name) root)))
             (ensure-directories-exist
              (merge-pathnames "anchor" path))
             (list
              :scope scope
              :source (format nil "git:github.com/user/~A" name)
              :parsed
              (cadr-cli::parse-package-source
               (format nil "git:github.com/user/~A" name))
              :path path))))
      (let* ((input
               (list
                (make-record :global "g1")
                (make-record :project "p1")
                (make-record :global "g2")
                (make-record :project "p2")
                (make-record :global "g3")
                (make-record :project "p3")))
             (scheduled
               (cadr-cli::package-update-records-project-first
                input))
             (count (length scheduled))
             (path-indices (make-hash-table :test #'equal))
             (gates
               (make-array
                count
                :initial-contents
                (loop repeat count collect
                  (sb-thread:make-semaphore :count 0))))
             (started (sb-thread:make-semaphore :count 0))
             (finished (sb-thread:make-semaphore :count 0))
             (lock
               (sb-thread:make-mutex
                :name "goal17 package concurrency test"))
             (active 0)
             (maximum-active 0)
             (started-count 0)
             (local (make-string 40 :initial-element #\a))
             (remote (make-string 40 :initial-element #\b))
             (result nil)
             (check-thread nil))
        (loop for record in scheduled
              for index from 0
              do
              (setf
               (gethash
                (namestring (getf record :path))
                path-indices)
               index))
        (flet ((runner (argv)
                 (let* ((path (third argv))
                        (index (gethash path path-indices)))
                   (cond
                     ((member "ls-remote" argv :test #'string=)
                      (sb-thread:with-mutex (lock)
                        (decf active))
                      (sb-thread:signal-semaphore finished)
                      (format nil "~A~Crefs/heads/main~%"
                              remote #\Tab))
                     ((member "--abbrev-ref" argv :test #'string=)
                      "origin/main")
                     (t
                      (sb-thread:with-mutex (lock)
                        (incf active)
                        (incf started-count)
                        (setf maximum-active
                              (max maximum-active active)))
                      (sb-thread:signal-semaphore started)
                      (unless
                          (sb-thread:wait-on-semaphore
                           (aref gates index) :timeout 5)
                        (error "Package update gate timed out"))
                      local)))))
          (unwind-protect
               (progn
                 (setf
                  check-thread
                  (sb-thread:make-thread
                   (lambda ()
                     (setf
                      result
                      (cadr-cli::check-for-available-package-updates
                       input :runner #'runner)))
                   :name "goal17 package checker"))
                 (loop repeat 4 do
                   (is
                    (sb-thread:wait-on-semaphore
                     started :timeout 5)))
                 (sb-thread:with-mutex (lock)
                   (is (= 4 active))
                   (is (= 4 maximum-active))
                   (is (= 4 started-count)))
                 (dolist (index '(3 2))
                   (sb-thread:signal-semaphore
                    (aref gates index))
                   (is
                    (sb-thread:wait-on-semaphore
                     finished :timeout 5))
                   (is
                    (sb-thread:wait-on-semaphore
                     started :timeout 5)))
                 (sb-thread:with-mutex (lock)
                   (is (= 4 active))
                   (is (= 4 maximum-active))
                   (is (= 6 started-count)))
                 (dolist (index '(5 4 1 0))
                   (sb-thread:signal-semaphore
                    (aref gates index))
                   (is
                    (sb-thread:wait-on-semaphore
                     finished :timeout 5)))
                 (is
                  (sb-thread:join-thread
                   check-thread :timeout 5 :default nil))
                 (setf check-thread nil)
                 (is
                  (equal
                   '("github.com/user/p1"
                     "github.com/user/p2"
                     "github.com/user/p3"
                     "github.com/user/g1"
                     "github.com/user/g2"
                     "github.com/user/g3")
                   result)))
            (dotimes (index count)
              (sb-thread:signal-semaphore
               (aref gates index)))
            (when check-thread
              (sb-thread:join-thread
               check-thread :timeout 5 :default nil)
              (when (sb-thread:thread-alive-p check-thread)
                (sb-thread:terminate-thread check-thread)))))))))

(test goal17-package-update-check-discards-diagnostics-and-kills-timeout-tree
  (let ((user-errors
          (make-string-output-stream)))
    (let ((*error-output* user-errors))
      (is (string=
           (format nil "remote-output~%")
           (cadr-cli::default-package-update-check-runner
            (list "/bin/sh" "-c"
                  "printf 'remote-output\\n'; printf 'private git diagnostic\\n' >&2")))))
    (is (string= "" (get-output-stream-string user-errors))))
  (let ((previous-prompt
          (uiop:getenv "GIT_TERMINAL_PROMPT"))
        (previous-ssh
          (uiop:getenv "GIT_SSH_COMMAND")))
    (unwind-protect
         (progn
           (sb-posix:setenv "GIT_TERMINAL_PROMPT" "ask" 1)
           (sb-posix:setenv
            "GIT_SSH_COMMAND" "ssh -F /tmp/user-config" 1)
           (is
            (string=
             (format nil "0|ssh -F /tmp/user-config~%")
             (cadr-cli::default-package-update-check-runner
              (list
               "/bin/sh" "-c"
               "printf '%s|%s\\n' \"$GIT_TERMINAL_PROMPT\" \"$GIT_SSH_COMMAND\"")))))
      (if previous-prompt
          (sb-posix:setenv
           "GIT_TERMINAL_PROMPT" previous-prompt 1)
          (sb-posix:unsetenv "GIT_TERMINAL_PROMPT"))
      (if previous-ssh
          (sb-posix:setenv "GIT_SSH_COMMAND" previous-ssh 1)
          (sb-posix:unsetenv "GIT_SSH_COMMAND"))))
  (with-test-directory (root)
    (let* ((pid-path
             (merge-pathnames "child.pid" root))
           (clock-calls 0)
           (timed-out-p nil))
      (flet ((clock ()
               (incf clock-calls)
               (if (and (> clock-calls 1)
                        (probe-file pid-path))
                   (* 2 internal-time-units-per-second)
                   0)))
        (handler-case
            (cadr-cli::default-package-update-check-runner
             (list
              "/bin/sh" "-c"
              (format nil
                      "trap '' TERM; sleep 30 & child=$!; printf '%s' \"$child\" > '~A'; wait"
                      (namestring pid-path)))
             :timeout-seconds 1
             :clock #'clock)
          (error (condition)
            (setf timed-out-p
                  (search "timed out"
                          (princ-to-string condition))))))
      (is (not (null timed-out-p)))
      (is (probe-file pid-path))
      (let ((child-pid
              (parse-integer
               (string-trim
                '(#\Space #\Tab #\Newline #\Return)
                (uiop:read-file-string pid-path)))))
        (let* ((process-path
                 (pathname
                  (format nil "/proc/~D/stat" child-pid)))
               (stat
                 (and (probe-file process-path)
                      (ignore-errors
                        (uiop:read-file-string
                         process-path))))
               (close
                 (and stat
                      (position #\) stat :from-end t)))
               (state
                 (and close
                      (< (+ close 2) (length stat))
                      (char stat (+ close 2)))))
          ;; PID 1 in a container can retain an already-killed orphan as a
          ;; zombie. Such a process cannot execute git or ssh.
          (is (member state '(nil #\Z #\X #\x))))))))
