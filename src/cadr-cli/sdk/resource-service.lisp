(in-package #:cadr-cli)

(defclass sdk-resource-loader ()
  ((cwd
    :initarg :cwd
    :reader sdk-resource-loader-cwd)
   (agent-directory
    :initarg :agent-directory
    :reader sdk-resource-loader-agent-directory)
   (settings-manager
    :initarg :settings-manager
    :reader sdk-resource-loader-settings-manager)
   (core-loader
    :initarg :core-loader
    :reader sdk-resource-loader-core-loader)
   (extension-manager
    :initarg :extension-manager
    :reader sdk-resource-loader-extension-manager)
   (system-prompt-source
    :initarg :system-prompt-source
    :initform :discover
    :reader sdk-resource-loader-system-prompt-source)
   (append-system-prompt-source
    :initarg :append-system-prompt-source
    :initform :discover
    :reader sdk-resource-loader-append-system-prompt-source)
   (system-prompt-override
    :initarg :system-prompt-override
    :initform nil
    :reader sdk-resource-loader-system-prompt-override)
   (append-system-prompt-override
    :initarg :append-system-prompt-override
    :initform nil
    :reader sdk-resource-loader-append-system-prompt-override)
   (skills-override
    :initarg :skills-override
    :initform nil
    :reader sdk-resource-loader-skills-override)
   (prompts-override
    :initarg :prompts-override
    :initform nil
    :reader sdk-resource-loader-prompts-override)
   (themes-override
    :initarg :themes-override
    :initform nil
    :reader sdk-resource-loader-themes-override)
   (context-files-override
    :initarg :context-files-override
    :initform nil
    :reader sdk-resource-loader-context-files-override)
   (snapshot
    :initform nil
    :accessor sdk-resource-loader-snapshot)
   (extension-report
    :initform nil
    :accessor sdk-resource-loader-extension-report)
   (skills
    :initform nil
    :accessor sdk-resource-loader-skills)
   (prompts
    :initform nil
    :accessor sdk-resource-loader-prompts)
   (themes
    :initform nil
    :accessor sdk-resource-loader-themes)
   (context-files
    :initform nil
    :accessor sdk-resource-loader-context-files)
   (system-prompt
    :initform nil
    :accessor sdk-resource-loader-system-prompt)
   (append-system-prompt
    :initform nil
    :accessor sdk-resource-loader-append-system-prompt)
   (diagnostics
    :initform nil
    :accessor sdk-resource-loader-diagnostics)))

(defun make-sdk-resource-loader
    (&key
       (cwd (uiop:getcwd))
       (agent-directory
         (merge-pathnames
          ".cadr/" (user-homedir-pathname)))
       settings-manager
       additional-extension-paths
       extension-factories
       additional-skill-paths
       additional-prompt-paths
       additional-theme-paths
       no-extensions-p no-skills-p no-prompts-p
       no-themes-p no-context-files-p
       (project-trusted-p t)
       (system-prompt nil system-prompt-p)
       (append-system-prompt nil append-system-prompt-p)
       system-prompt-override
       append-system-prompt-override
       skills-override prompts-override themes-override
       context-files-override
       (output (make-broadcast-stream)))
  (let* ((resolved-cwd
           (uiop:ensure-directory-pathname
            (uiop:ensure-absolute-pathname cwd)))
         (resolved-agent
           (uiop:ensure-directory-pathname
            (uiop:ensure-absolute-pathname
             agent-directory)))
         (settings
           (or settings-manager
               (make-sdk-settings-manager
                :global-path
                (merge-pathnames
                 "settings.json" resolved-agent)
                :project-path
                (merge-pathnames
                 ".cadr/settings.json"
                 resolved-cwd)
                :project-trusted-p
                project-trusted-p)))
         (extension-manager
           (make-cli-extension-manager
            :cwd resolved-cwd
            :global-directory
            (merge-pathnames
             "extensions/" resolved-agent)
            :explicit-paths
            additional-extension-paths
            :extension-factories extension-factories
            :no-discovery-p no-extensions-p
            :output output
            :mode :sdk))
         (core-loader
           (make-default-resource-loader
            :cwd resolved-cwd
            :agent-directory resolved-agent
            :project-trusted-p project-trusted-p
            :no-context-files-p no-context-files-p
            :no-skills-p no-skills-p
            :no-prompts-p no-prompts-p
            :no-themes-p no-themes-p
            :explicit-skill-paths
            additional-skill-paths
            :explicit-prompt-paths
            additional-prompt-paths
            :explicit-theme-paths
            additional-theme-paths
            :extension-host
            (cli-extension-manager-host
             extension-manager))))
    (apply
     #'make-instance 'sdk-resource-loader
     :cwd resolved-cwd
     :agent-directory resolved-agent
     :settings-manager settings
     :extension-manager extension-manager
     :core-loader core-loader
     :system-prompt-override system-prompt-override
     :append-system-prompt-override
     append-system-prompt-override
     :skills-override skills-override
     :prompts-override prompts-override
     :themes-override themes-override
     :context-files-override context-files-override
     (append
      (when system-prompt-p
        (list :system-prompt-source system-prompt))
      (when append-system-prompt-p
        (list :append-system-prompt-source
              append-system-prompt))))))

(defun sdk-resolve-prompt-input (input)
  (cond
    ((null input) nil)
    ((pathnamep input)
     (uiop:read-file-string input
                            :external-format :utf-8))
    ((and (stringp input) (probe-file input))
     (uiop:read-file-string input
                            :external-format :utf-8))
    ((stringp input) input)
    (t
     (error
      'cadr-ai:configuration-error
      :message
      (format nil "Invalid system prompt input: ~S"
              input)))))

(defun sdk-context-file-records (paths)
  (mapcar
   (lambda (path)
     (list
      :path path
      :content
      (uiop:read-file-string
       path :external-format :utf-8)))
   paths))

(defun sdk-apply-resource-list-override
    (function items diagnostics)
  (if function
      (multiple-value-bind
            (next-items next-diagnostics)
          (funcall function
                   (copy-list items)
                   (copy-list diagnostics))
        (values
         (or next-items nil)
         (if (null next-diagnostics)
             diagnostics
             next-diagnostics)))
      (values items diagnostics)))

(defgeneric sdk-resource-loader-reload (loader))

(defmethod sdk-resource-loader-reload
    ((loader sdk-resource-loader))
  (let* ((report
           (reload-cli-extensions
            (sdk-resource-loader-extension-manager
             loader)))
         (snapshot
           (reload-resources
            (sdk-resource-loader-core-loader
             loader)))
         (diagnostics
           (append
            (copy-list
             (resource-snapshot-diagnostics
              snapshot))
            (copy-list (getf report :errors))))
         (context-files
           (sdk-context-file-records
            (resource-snapshot-context-files
             snapshot)))
         (system-source
           (sdk-resource-loader-system-prompt-source
            loader))
         (append-source
           (sdk-resource-loader-append-system-prompt-source
            loader))
         (system
           (sdk-resolve-prompt-input
            (if (eq system-source :discover)
                (resource-snapshot-system-prompt-path
                 snapshot)
                system-source)))
         (append-prompts
           (if (eq append-source :discover)
               (let ((path
                       (resource-snapshot-append-system-prompt-path
                        snapshot)))
                 (if path
                     (list
                      (sdk-resolve-prompt-input path))
                     nil))
               (mapcar
                #'sdk-resolve-prompt-input
                (etypecase append-source
                  (null nil)
                  (list append-source)
                  ((or string pathname)
                   (list append-source)))))))
    (multiple-value-bind (skills skill-diagnostics)
        (sdk-apply-resource-list-override
         (sdk-resource-loader-skills-override loader)
         (resource-snapshot-skills snapshot)
         diagnostics)
      (multiple-value-bind (prompts prompt-diagnostics)
          (sdk-apply-resource-list-override
           (sdk-resource-loader-prompts-override loader)
           (resource-snapshot-prompts snapshot)
           skill-diagnostics)
        (multiple-value-bind (themes final-diagnostics)
            (sdk-apply-resource-list-override
             (sdk-resource-loader-themes-override loader)
             (resource-snapshot-themes snapshot)
             prompt-diagnostics)
          (setf
           (sdk-resource-loader-extension-report loader)
           report
           (sdk-resource-loader-snapshot loader)
           snapshot
           (sdk-resource-loader-skills loader)
           skills
           (sdk-resource-loader-prompts loader)
           prompts
           (sdk-resource-loader-themes loader)
           themes
           (sdk-resource-loader-context-files loader)
           (if
               (sdk-resource-loader-context-files-override
                loader)
               (funcall
                (sdk-resource-loader-context-files-override
                 loader)
                (copy-tree context-files))
               context-files)
           (sdk-resource-loader-system-prompt loader)
           (if
               (sdk-resource-loader-system-prompt-override
                loader)
               (funcall
                (sdk-resource-loader-system-prompt-override
                 loader)
                system)
               system)
           (sdk-resource-loader-append-system-prompt
            loader)
           (if
               (sdk-resource-loader-append-system-prompt-override
                loader)
               (funcall
                (sdk-resource-loader-append-system-prompt-override
                 loader)
                (copy-list append-prompts))
               append-prompts)
           (sdk-resource-loader-diagnostics loader)
           final-diagnostics)))))
  loader)

(defgeneric sdk-resource-loader-extensions (loader))

(defmethod sdk-resource-loader-extensions
    ((loader sdk-resource-loader))
  (let ((report
          (sdk-resource-loader-extension-report
           loader))
        (manager
          (sdk-resource-loader-extension-manager
           loader)))
    (list
     :loaded (getf report :loaded 0)
     :active (getf report :active 0)
     :errors (copy-list (getf report :errors))
     :runtime
     (cli-extension-manager-host manager))))

(defgeneric sdk-resource-loader-extend-resources
    (loader &key skill-paths prompt-paths theme-paths))

(defmethod sdk-resource-loader-extend-resources
    ((loader sdk-resource-loader)
     &key skill-paths prompt-paths theme-paths)
  (let ((core
          (sdk-resource-loader-core-loader loader)))
    (setf
     (default-resource-loader-explicit-skill-paths core)
     (append
      (default-resource-loader-explicit-skill-paths core)
      skill-paths)
     (default-resource-loader-explicit-prompt-paths core)
     (append
      (default-resource-loader-explicit-prompt-paths core)
      prompt-paths)
     (default-resource-loader-explicit-theme-paths core)
     (append
      (default-resource-loader-explicit-theme-paths core)
      theme-paths)))
  (sdk-resource-loader-reload loader))

(defgeneric sdk-resource-loader-extension-host
    (loader))

(defmethod sdk-resource-loader-extension-host
    ((loader sdk-resource-loader))
  (cli-extension-manager-host
   (sdk-resource-loader-extension-manager
    loader)))
