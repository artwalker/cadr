(in-package #:cadr-cli)

(defstruct resource-snapshot
  (skills nil :type list)
  (prompts nil :type list)
  (themes nil :type list)
  (context-files nil :type list)
  system-prompt-path
  append-system-prompt-path
  (diagnostics nil :type list)
  (skill-diagnostics nil :type list)
  (prompt-diagnostics nil :type list)
  (skill-collisions nil :type list)
  (prompt-collisions nil :type list)
  cwd
  agent-directory)

(defstruct default-resource-loader
  cwd
  agent-directory
  (project-trusted-p t :type boolean)
  (no-context-files-p nil :type boolean)
  (no-skills-p nil :type boolean)
  (no-prompts-p nil :type boolean)
  (no-themes-p nil :type boolean)
  (explicit-skill-paths nil :type list)
  (explicit-prompt-paths nil :type list)
  (explicit-theme-paths nil :type list)
  (package-global-skill-paths nil :type list)
  (package-project-skill-paths nil :type list)
  (package-global-prompt-paths nil :type list)
  (package-project-prompt-paths nil :type list)
  (package-global-theme-paths nil :type list)
  (package-project-theme-paths nil :type list)
  extension-host
  snapshot)

(defun ancestor-directories (directory)
  (loop for current =
        (uiop:ensure-directory-pathname directory)
          then (parent-directory current)
        while current
        collect current))

(defun existing-file (path)
  (and
   (probe-file path)
   (not (uiop:directory-exists-p path))
   (truename path)))

(defun project-config-directories (cwd)
  (loop for ancestor in (ancestor-directories cwd)
        for config =
        (cadr-core:project-config-directory ancestor)
        when (uiop:directory-exists-p config)
          collect config))

(defun dedupe-resources-by-name
    (global project name-function &optional path-function)
  "First occurrence wins, matching the baseline: its package-manager
resolve() adds project resources before user resources and the
dedupe keeps the first occurrence, so the project resource wins a
same-name collision (packages/coding-agent/src/core/package-manager.ts
project-before-user ordering, core/skills.ts first-wins skillMap).
Returns the deduped list and a list of collision records
(:name :winner-path :loser-path) for the skipped losers."
  (let ((table (make-hash-table :test #'equal))
        (collisions nil))
    (dolist (resource (append project global))
      (let ((name (funcall name-function resource)))
        (multiple-value-bind (winner present-p)
            (gethash name table)
          (if present-p
              (push
               (list
                :name name
                :winner-path
                (and path-function (funcall path-function winner))
                :loser-path
                (and path-function (funcall path-function resource)))
               collisions)
              (setf (gethash name table) resource)))))
    (values
     (sort
      (loop for resource being the hash-values of table
            collect resource)
      #'string<
      :key name-function)
     (nreverse collisions))))

(defun load-resources-at-paths (paths loader-fn)
  (let ((items nil)
        (diagnostics nil))
    (dolist (path paths)
      (multiple-value-bind (loaded warnings)
          (funcall loader-fn path)
        (setf items (nconc items loaded)
              diagnostics
              (nconc diagnostics warnings))))
    (values items diagnostics)))

(defun load-skills-at-paths (paths)
  (load-resources-at-paths paths #'cadr-agent::load-skills))

(defun explicit-resource-directory (path)
  (let ((resolved
          (merge-pathnames
           (pathname path)
           (uiop:getcwd))))
    (cond
      ((uiop:directory-exists-p resolved)
       resolved)
      ((probe-file resolved)
       (uiop:pathname-directory-pathname
        resolved))
      (t resolved))))

(defun load-prompts-at-paths (paths)
  (load-resources-at-paths
   paths #'cadr-agent::load-prompt-templates))

(defun default-resource-loader-theme-search-paths
    (loader &optional extension-paths)
  (let* ((agent
           (uiop:ensure-directory-pathname
            (default-resource-loader-agent-directory
             loader)))
         (configs
           (if
               (default-resource-loader-project-trusted-p
                loader)
               (project-config-directories
                (default-resource-loader-cwd loader))
               nil))
         (no-themes-p
           (default-resource-loader-no-themes-p loader)))
    (append
     (unless no-themes-p
       (append
        (list
         (merge-pathnames "themes/" agent))
        (default-resource-loader-package-global-theme-paths
         loader)
        (mapcar
         (lambda (config)
           (merge-pathnames "themes/" config))
         configs)
        (default-resource-loader-package-project-theme-paths
         loader)
        (mapcar
         #'pathname
         (getf extension-paths :theme-paths))))
     (mapcar
      #'pathname
      (default-resource-loader-explicit-theme-paths
       loader)))))

(defun default-resource-loader-skill-path-lists
    (loader &optional extension-paths)
  (let* ((agent
           (uiop:ensure-directory-pathname
            (default-resource-loader-agent-directory
             loader)))
         (configs
           (if
               (default-resource-loader-project-trusted-p
                loader)
               (project-config-directories
                (default-resource-loader-cwd loader))
               nil))
         (no-skills-p
           (default-resource-loader-no-skills-p loader)))
    (values
     (append
      (unless no-skills-p
        (list
         (merge-pathnames "skills/" agent)))
      (unless no-skills-p
        (default-resource-loader-package-global-skill-paths
         loader))
      (mapcar
       #'explicit-resource-directory
       (default-resource-loader-explicit-skill-paths
        loader)))
     (unless no-skills-p
       (append
        (mapcar
         (lambda (config)
           (merge-pathnames "skills/" config))
         configs)
        (default-resource-loader-package-project-skill-paths
         loader)
        (mapcar
         #'pathname
         (getf extension-paths :skill-paths)))))))

(defun default-resource-loader-skill-search-paths
    (loader &optional extension-paths)
  (multiple-value-bind (global project)
      (default-resource-loader-skill-path-lists
       loader extension-paths)
    (append global project)))

(defun default-resource-loader-prompt-path-lists
    (loader &optional extension-paths)
  (let* ((agent
           (uiop:ensure-directory-pathname
            (default-resource-loader-agent-directory
             loader)))
         (configs
           (if
               (default-resource-loader-project-trusted-p
                loader)
               (project-config-directories
                (default-resource-loader-cwd loader))
               nil))
         (no-prompts-p
           (default-resource-loader-no-prompts-p loader)))
    (values
     (append
      (unless no-prompts-p
        (list
         (merge-pathnames "prompts/" agent)))
      (unless no-prompts-p
        (default-resource-loader-package-global-prompt-paths
         loader))
      (mapcar
       #'explicit-resource-directory
       (default-resource-loader-explicit-prompt-paths
        loader)))
     (unless no-prompts-p
       (append
        (mapcar
         (lambda (config)
           (merge-pathnames "prompts/" config))
         configs)
        (default-resource-loader-package-project-prompt-paths
         loader)
        (mapcar
         #'pathname
         (getf extension-paths
               :prompt-paths)))))))

(defun default-resource-loader-prompt-search-paths
    (loader &optional extension-paths)
  (multiple-value-bind (global project)
      (default-resource-loader-prompt-path-lists
       loader extension-paths)
    (append global project)))

(defun load-themes-at-paths (paths)
  (let ((items nil))
    (dolist (raw paths)
      (let ((path (pathname raw)))
        (cond
          ((uiop:directory-exists-p path)
           (setf items
                 (nconc items
                        (load-theme-summaries path))))
          ((probe-file path)
           (let ((object
                   (handler-case
                       (cadr-ai::parse-json
                        (uiop:read-file-string
                         path
                         :external-format :utf-8))
                     (condition () nil))))
             (when (hash-table-p object)
               (push
                (list
                 :name
                 (or
                  (cadr-ai::json-get object "name")
                  (pathname-name path))
                 :path (truename path)
                 :object object)
                items)))))))
    (sort items #'string<
          :key (lambda (entry)
                 (getf entry :name)))))

(defstruct git-footer-paths
  repo-directory
  common-git-directory
  head-path)

(defun parent-directory-pathname (directory)
  (let* ((normalized
           (uiop:ensure-directory-pathname
            directory))
         (parts
           (pathname-directory normalized)))
    (when (> (length parts) 1)
      (make-pathname
       :directory (butlast parts)
       :defaults normalized))))

(defun find-git-footer-paths (cwd)
  (loop
    with directory =
    (uiop:ensure-directory-pathname
     (uiop:ensure-absolute-pathname cwd))
    for git-path =
    (merge-pathnames ".git" directory)
    do
    (when (probe-file git-path)
      (handler-case
          (if (uiop:directory-pathname-p
               (truename git-path))
              (let* ((git-directory
                       (uiop:ensure-directory-pathname
                        (truename git-path)))
                     (head
                       (merge-pathnames
                        "HEAD" git-directory)))
                (when (probe-file head)
                  (return
                    (make-git-footer-paths
                     :repo-directory directory
                     :common-git-directory
                     git-directory
                     :head-path head))))
              (let* ((content
                       (string-trim
                        '(#\Space #\Tab
                          #\Newline #\Return)
                        (uiop:read-file-string
                         git-path
                         :external-format
                         :utf-8)))
                     (prefix "gitdir: "))
                (when
                    (uiop:string-prefix-p
                     prefix content)
                  (let* ((git-directory
                           (uiop:ensure-directory-pathname
                            (uiop:ensure-absolute-pathname
                             (subseq
                              content
                              (length prefix))
                             directory)))
                         (head
                           (merge-pathnames
                            "HEAD"
                            git-directory))
                         (common-file
                           (merge-pathnames
                            "commondir"
                            git-directory))
                         (common-directory
                           (if
                               (probe-file
                                common-file)
                               (uiop:ensure-directory-pathname
                                (uiop:ensure-absolute-pathname
                                 (string-trim
                                  '(#\Space #\Tab
                                    #\Newline #\Return)
                                  (uiop:read-file-string
                                   common-file
                                   :external-format
                                   :utf-8))
                                 git-directory))
                               git-directory)))
                    (when (probe-file head)
                      (return
                        (make-git-footer-paths
                         :repo-directory directory
                         :common-git-directory
                         common-directory
                         :head-path head)))))))
        (condition ()
          (return nil))))
    (let ((parent
            (parent-directory-pathname
             directory)))
      (unless parent
        (return nil))
      (setf directory parent))))

(defun directory-inside-p (ancestor directory)
  (let* ((parent (string-right-trim "/" ancestor))
         (child (string-right-trim "/" directory)))
    (and (plusp (length parent))
         (uiop:string-prefix-p
          (concatenate 'string parent "/")
          child))))

(defun context-shadow-key (directory filename)
  (namestring
   (merge-pathnames
    filename
    (uiop:ensure-directory-pathname
     (canonical-directory-name directory)))))

(defun load-context-file-from-dir (directory)
  ;; Keep the path as written. probe-file follows a symlink and would
  ;; make a worktree AGENTS.md look like the main repo's file.
  (dolist (name '("AGENTS.override.md" "AGENTS.md"
                  "AGENTS.MD" "CLAUDE.md" "CLAUDE.MD"))
    (let ((path (merge-pathnames name directory)))
      (when (and (probe-file path)
                 (not (uiop:directory-exists-p path)))
        (return path)))))

(defun find-shadowed-context-file (cwd)
  ;; pi@71023aec1 resource-loader.ts findShadowedContextFile. A nested
  ;; linked worktree and its main repo share one logical scope. The
  ;; shadowed path is the main repo root plus the worktree file's name,
  ;; not the file's real path: a symlink still names the worktree copy.
  (let ((paths (find-git-footer-paths cwd)))
    (when paths
      (let* ((common
               (canonical-directory-name
                (git-footer-paths-common-git-directory paths)))
             (worktree
               (canonical-directory-name
                (git-footer-paths-repo-directory paths)))
             (main
               (parent-directory common)))
        (when (and main
                   (directory-inside-p (namestring main) worktree))
          (let ((main-git
                  (canonical-directory-name
                   (merge-pathnames ".git" main))))
            (when (string= main-git common)
              (let ((file
                      (load-context-file-from-dir
                       (git-footer-paths-repo-directory paths))))
                (when file
                  (context-shadow-key
                   main
                   (file-namestring file)))))))))))

(defun load-project-context-files (&key cwd agent-directory)
  ;; pi@71023aec1 core/resource-loader.ts. Global agent-dir context
  ;; first, then cwd→root ancestors rootward-first. A nested worktree
  ;; drops only the main repo file of the same name.
  (let* ((ancestors nil)
         (seen (make-hash-table :test #'equal))
         (shadowed (find-shadowed-context-file cwd))
         (global
           (when agent-directory
             (load-context-file-from-dir
              (uiop:ensure-directory-pathname
               agent-directory)))))
    (when global
      (setf (gethash (namestring global) seen) t))
    (loop for directory in (ancestor-directories cwd)
          for match = (load-context-file-from-dir directory)
          when (and match
                    (not (gethash (namestring match) seen))
                    (not (and shadowed
                              (string=
                               shadowed
                               (context-shadow-key
                                directory
                                (file-namestring match))))))
            do (setf (gethash (namestring match) seen) t)
               (push match ancestors))
    (append (and global (list global)) ancestors)))

(defun nearest-config-file (configs name)
  (loop for directory in configs
        for path =
        (existing-file
         (merge-pathnames name directory))
        when path return path))

(defun reload-resources (loader)
  (let* ((extension-paths
           (if
               (default-resource-loader-extension-host
                loader)
               (cadr-agent::run-extension-lifecycle-hooks
                (default-resource-loader-extension-host
                 loader)
                :resources-discover
                :payload
                (list
                 :cwd
                 (namestring
                  (uiop:ensure-directory-pathname
                   (default-resource-loader-cwd
                    loader)))
                 :reason
                 (if
                     (default-resource-loader-snapshot
                      loader)
                     :reload :startup)))
               nil)))
    (note-loader-extension-sources
     loader
     (getf extension-paths :extension-resource-sources))
    (let* ((configs
           (if
               (default-resource-loader-project-trusted-p
                loader)
               (project-config-directories
                (default-resource-loader-cwd loader))
               nil))
         (skill-path-lists
           (multiple-value-list
            (default-resource-loader-skill-path-lists
             loader extension-paths)))
         (global-skill-paths (first skill-path-lists))
         (project-skill-paths (second skill-path-lists))
         (prompt-path-lists
           (multiple-value-list
            (default-resource-loader-prompt-path-lists
             loader extension-paths)))
         (global-prompt-paths (first prompt-path-lists))
         (project-prompt-paths (second prompt-path-lists))
         (theme-paths
           (default-resource-loader-theme-search-paths
            loader extension-paths)))
    (multiple-value-bind
          (global-skills global-skill-warnings)
        (load-skills-at-paths global-skill-paths)
      (multiple-value-bind
            (project-skills project-skill-warnings)
          (load-skills-at-paths project-skill-paths)
        (multiple-value-bind
              (global-prompts global-prompt-warnings)
            (load-prompts-at-paths global-prompt-paths)
          (multiple-value-bind
                (project-prompts project-prompt-warnings)
              (load-prompts-at-paths project-prompt-paths)
            (multiple-value-bind (skills skill-collisions)
                (dedupe-resources-by-name
                 global-skills project-skills
                 #'cadr-agent::skill-name
                 #'cadr-agent::skill-file-path)
              (multiple-value-bind (prompts prompt-collisions)
                  (dedupe-resources-by-name
                   global-prompts project-prompts
                   #'cadr-agent::prompt-template-name
                   #'cadr-agent::prompt-template-file-path)
            (let ((snapshot
                    (make-resource-snapshot
                     :skills skills
                     :prompts prompts
                     :themes
                     (load-themes-at-paths
                      theme-paths)
                     :context-files
                     (unless
                         (default-resource-loader-no-context-files-p
                          loader)
                       (load-project-context-files
                        :cwd
                        (default-resource-loader-cwd
                         loader)
                        :agent-directory
                        (default-resource-loader-agent-directory
                         loader)))
                     :system-prompt-path
                     (nearest-config-file
                      configs "SYSTEM.md")
                     :append-system-prompt-path
                     (nearest-config-file
                      configs "APPEND_SYSTEM.md")
                     :diagnostics
                     (nconc
                      global-skill-warnings
                      project-skill-warnings
                      global-prompt-warnings
                      project-prompt-warnings)
                     :skill-diagnostics
                     (nconc
                      global-skill-warnings
                      project-skill-warnings)
                     :prompt-diagnostics
                     (nconc
                      global-prompt-warnings
                      project-prompt-warnings)
                     :skill-collisions skill-collisions
                     :prompt-collisions prompt-collisions
                     :cwd (default-resource-loader-cwd loader)
                     :agent-directory
                     (default-resource-loader-agent-directory loader))))
              (setf
               (default-resource-loader-snapshot loader)
               snapshot)
              snapshot))))))))))

(defvar *loader-package-sources*
  (make-hash-table :test #'eq :weakness :key))

(defun note-loader-package-sources (loader sources)
  (setf (gethash loader *loader-package-sources*)
        (copy-list sources))
  loader)

(defun loader-package-sources (loader)
  (copy-list (gethash loader *loader-package-sources*)))

(defvar *loader-extension-sources*
  (make-hash-table :test #'eq :weakness :key))

(defun note-loader-extension-sources (loader sources)
  (setf (gethash loader *loader-extension-sources*)
        (copy-list sources))
  loader)

(defun loader-extension-sources (loader)
  (copy-list (gethash loader *loader-extension-sources*)))

(defun resource-path-under-p (file directory)
  (let ((dir
          (namestring
           (uiop:ensure-directory-pathname directory)))
        (name (namestring file)))
    (and (plusp (length dir))
         (uiop:string-prefix-p dir name))))

(defun resource-path-matches-source-p (file source-path)
  (or (string= (namestring file) (namestring source-path))
      (resource-path-under-p file source-path)))

(defun resource-path-source-info (loader path)
  (when (or (null loader) (null path))
    (return-from resource-path-source-info
      (values nil nil)))
  (dolist (entry (loader-extension-sources loader))
    (when (resource-path-matches-source-p
           path (getf entry :path))
      (return-from resource-path-source-info
        (values (getf entry :source)
                (getf entry :scope)))))
  (dolist (entry (loader-package-sources loader))
    (when (resource-path-under-p path (getf entry :path))
      (return-from resource-path-source-info
        (values (getf entry :source)
                (getf entry :scope)))))
  (dolist (root
           (append
            (default-resource-loader-explicit-skill-paths
             loader)
            (default-resource-loader-explicit-prompt-paths
             loader)
            (default-resource-loader-explicit-theme-paths
             loader)))
    (when (resource-path-under-p path root)
      (return-from resource-path-source-info
        (values "cli" "temporary"))))
  (let ((agent
          (default-resource-loader-agent-directory loader))
        (project
          (cadr-core:project-config-directory
           (default-resource-loader-cwd loader))))
    (dolist (name '("skills" "prompts" "themes" "extensions"))
      (when (resource-path-under-p
             path
             (merge-pathnames
              (concatenate 'string name "/")
              agent))
        (return-from resource-path-source-info
          (values "local" "user"))))
    (dolist (name '("skills" "prompts" "themes" "extensions"))
      (when (resource-path-under-p
             path
             (merge-pathnames
              (concatenate 'string name "/")
              project))
        (return-from resource-path-source-info
          (values "local" "project")))))
  (values "local" "temporary"))
