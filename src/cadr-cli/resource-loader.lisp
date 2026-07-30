(in-package #:cadr-cli)

(defstruct resource-snapshot
  (skills nil :type list)
  (prompts nil :type list)
  (themes nil :type list)
  (context-files nil :type list)
  system-prompt-path
  append-system-prompt-path
  (diagnostics nil :type list))

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
        (merge-pathnames ".cadr/" ancestor)
        when (uiop:directory-exists-p config)
          collect config))

(defun dedupe-resources-by-name
    (global project name-function)
  (let ((table (make-hash-table :test #'equal)))
    (dolist (resource global)
      (setf (gethash
             (funcall name-function resource)
             table)
            resource))
    (dolist (resource project)
      (setf (gethash
             (funcall name-function resource)
             table)
            resource))
    (sort
     (loop for resource being the hash-values of table
           collect resource)
     #'string<
     :key name-function)))

(defun load-skills-at-paths (paths)
  (let ((items nil)
        (diagnostics nil))
    (dolist (path paths)
      (multiple-value-bind (loaded warnings)
          (cadr-agent::load-skills path)
        (setf items (nconc items loaded)
              diagnostics
              (nconc diagnostics warnings))))
    (values items diagnostics)))

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
  (let ((items nil)
        (diagnostics nil))
    (dolist (path paths)
      (multiple-value-bind (loaded warnings)
          (cadr-agent::load-prompt-templates path)
        (setf items (nconc items loaded)
              diagnostics
              (nconc diagnostics warnings))))
    (values items diagnostics)))

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

(defun load-project-context-files (cwd)
  (let ((files nil))
    (dolist (directory
             (ancestor-directories cwd))
      (dolist (name '("AGENTS.md" "CLAUDE.md"))
        (let ((path
                (existing-file
                 (merge-pathnames name directory))))
          (when path
            (push path files)))))
    (nreverse files)))

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
               nil))
         (agent
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
         (global-skill-paths
           (append
            (unless
                (default-resource-loader-no-skills-p
                 loader)
              (list
               (merge-pathnames "skills/" agent)))
            (unless
                (default-resource-loader-no-skills-p
                 loader)
              (default-resource-loader-package-global-skill-paths
               loader))
            (mapcar
             #'explicit-resource-directory
             (default-resource-loader-explicit-skill-paths
              loader))))
         (project-skill-paths
           (unless
               (default-resource-loader-no-skills-p
                loader)
             (append
              (mapcar
              (lambda (config)
                (merge-pathnames "skills/" config))
              configs)
              (default-resource-loader-package-project-skill-paths
               loader)
              (mapcar
               #'pathname
               (getf extension-paths
                     :skill-paths)))))
         (global-prompt-paths
           (append
            (unless
                (default-resource-loader-no-prompts-p
                 loader)
              (list
               (merge-pathnames "prompts/" agent)))
            (unless
                (default-resource-loader-no-prompts-p
                 loader)
              (default-resource-loader-package-global-prompt-paths
               loader))
            (mapcar
             #'explicit-resource-directory
             (default-resource-loader-explicit-prompt-paths
              loader))))
         (project-prompt-paths
           (unless
               (default-resource-loader-no-prompts-p
                loader)
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
                     :prompt-paths)))))
         (theme-paths
           (append
            (unless
                (default-resource-loader-no-themes-p
                 loader)
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
               (getf extension-paths
                     :theme-paths))))
            (mapcar
             #'pathname
             (default-resource-loader-explicit-theme-paths
              loader)))))
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
            (let ((snapshot
                    (make-resource-snapshot
                     :skills
                     (dedupe-resources-by-name
                      global-skills project-skills
                      #'cadr-agent::skill-name)
                     :prompts
                     (dedupe-resources-by-name
                      global-prompts project-prompts
                      #'cadr-agent::prompt-template-name)
                     :themes
                     (load-themes-at-paths
                      theme-paths)
                     :context-files
                     (unless
                         (default-resource-loader-no-context-files-p
                          loader)
                       (load-project-context-files
                        (default-resource-loader-cwd
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
                      project-prompt-warnings))))
              (setf
               (default-resource-loader-snapshot loader)
               snapshot)
              snapshot)))))))
